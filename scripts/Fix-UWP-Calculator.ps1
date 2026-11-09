#requires -RunAsAdministrator
<#
.SYNOPSIS
  Fix-UWP-Calculator.ps1
  針對 Windows 10 計算機等 UWP 啟動失敗的一站式修復腳本。

.DESCRIPTION
  依實際故障鏈設計（對話／事件／Procmon 已驗證的模式）：

  1) 框架／相依套件目錄 ACL 缺 BUILTIN\Users 或 ALL APPLICATION PACKAGES
     → CalculatorApp.exe 載入時 ACCESS DENIED
     → 系統對話框常顯示「找不到 mrt100_app.dll / SharedLibrary.dll / vcruntime140_app.dll」
  2) .NET Native x64 被 GamingServices 占用無法 Register (0x80073D02)
  3) 套件需 DisableDevelopmentMode -Register
  4) 使用者 Packages 狀態損毀（次要）
  5) AppContainer 未建立（事件 40，次要／並列處理）

  腳本會：偵測 → 修復 → 驗證 → 寫入報告。
  預設只動計算機相關相依；可用 -FixAllNativeApps 一併處理時鐘／便利貼等同類型。

.PARAMETER FixAllNativeApps
  一併重註冊時鐘、便利貼、相機（與計算機相同 .NET Native 啟動鏈）。

.PARAMETER SkipGamingServicesRemoval
  不移除 GamingServices（若 Register 被占用仍會嘗試 Stop-Process）。

.PARAMETER WhatIf
  只報告將執行的動作，不修改 ACL／不 Register。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Fix-UWP-Calculator.ps1

.NOTES
  請以「系統管理員」PowerShell 5.1 / 7 執行。
  報告預設寫入 %TEMP%\Fix-UWP-Calculator_yyyyMMdd_HHmmss\
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$FixAllNativeApps,
  [switch]$SkipGamingServicesRemoval
)

$ErrorActionPreference = 'Continue'
$script:LogDir = Join-Path $env:TEMP ('Fix-UWP-Calculator_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
$script:LogFile = Join-Path $script:LogDir 'report.txt'
$script:Issues = New-Object System.Collections.Generic.List[string]
$script:Actions = New-Object System.Collections.Generic.List[string]

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
  Write-Host $line
  Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
}

function Write-Section {
  param([string]$Title)
  $bar = ('=' * 8) + ' ' + $Title + ' ' + ('=' * 8)
  Write-Host $bar -ForegroundColor Cyan
  Add-Content -Path $script:LogFile -Value "`r`n$bar" -Encoding UTF8
}

function Test-IsAdmin {
  $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-KeyDllNames {
  @(
    'mrt100_app.dll',          # .NET Native Runtime — 缺或不可讀 → 對話框「找不到 mrt100_app.dll」
    'SharedLibrary.dll',       # .NET Native Framework 共用庫
    'vcruntime140_app.dll',    # VCLibs — Procmon 曾對此 ACCESS DENIED
    'msvcp140_app.dll',
    'vccorlib140_app.dll'
  )
}

function Test-FileReadable {
  param([string]$Path)
  try {
    $s = [IO.File]::OpenRead($Path)
    $len = $s.Length
    $s.Close()
    return @{ Ok = $true; Length = $len; Error = $null }
  } catch {
    return @{ Ok = $false; Length = 0; Error = $_.Exception.Message }
  }
}

function Repair-PackageAcl {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Label = ''
  )
  if (-not (Test-Path -LiteralPath $Root)) {
    Write-Log "路徑不存在: $Root" 'WARN'
    return $false
  }
  if ($WhatIfPreference) {
    Write-Log "WhatIf: 將修復 ACL → $Root" 'WHATIF'
    return $true
  }
  Write-Log "ACL 修復: $Label $Root"
  # takeown + 完整控制給 Administrators，再給 AAP 與 Users 讀取執行（與已驗證成功的 Store 修復同一模式）
  $null = cmd /c "takeown /f `"$Root`" /a /r /d y" 2>&1
  $null = cmd /c "icacls `"$Root`" /grant Administrators:(OI)(CI)(F) /T /C" 2>&1
  # S-1-15-2-1 = ALL APPLICATION PACKAGES
  $null = cmd /c "icacls `"$Root`" /grant *S-1-15-2-1:(OI)(CI)(RX) /T /C" 2>&1
  # S-1-5-32-545 = BUILTIN\Users（Procmon／Claude 主線關鍵）
  $null = cmd /c "icacls `"$Root`" /grant *S-1-5-32-545:(OI)(CI)(RX) /T /C" 2>&1
  $script:Actions.Add(('ACL:{0}' -f $Root))
  return $true
}

function Find-DllInPackage {
  param([string]$Root, [string]$DllName)
  if (-not (Test-Path -LiteralPath $Root)) { return $null }
  return Get-ChildItem -LiteralPath $Root -Recurse -Filter $DllName -ErrorAction SilentlyContinue |
    Select-Object -First 1
}

function Repair-NamedPackages {
  param([string[]]$PackageNames)
  foreach ($name in $PackageNames) {
    $pkgs = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
    if (-not $pkgs.Count) {
      Write-Log "未安裝套件: $name" 'WARN'
      $script:Issues.Add(('MissingPackage:{0}' -f $name))
      continue
    }
    foreach ($p in $pkgs) {
      $root = $p.InstallLocation
      Write-Section "$($p.Name) [$($p.Architecture)] $($p.Version)"
      Write-Log "Status=$($p.Status) Path=$root"
      if (-not $root) {
        Write-Log 'InstallLocation 為空' 'ERROR'
        $script:Issues.Add(('EmptyPath:{0}' -f $p.PackageFullName))
        continue
      }
      Repair-PackageAcl -Root $root -Label $p.PackageFullName | Out-Null

      foreach ($dll in Get-KeyDllNames) {
        $hit = Find-DllInPackage -Root $root -DllName $dll
        if ($hit) {
          $r = Test-FileReadable -Path $hit.FullName
          if ($r.Ok) {
            Write-Log "可讀 $dll ($($r.Length) bytes) @ $($hit.FullName)"
          } else {
            Write-Log ("不可讀 {0} - {1} ; 再補一次檔案級權限" -f $dll, $r.Error) 'WARN'
            if (-not $WhatIfPreference) {
              $null = cmd /c "takeown /f `"$($hit.FullName)`" /a" 2>&1
              $null = cmd /c "icacls `"$($hit.FullName)`" /grant *S-1-15-2-1:RX *S-1-5-32-545:RX Administrators:F" 2>&1
            }
            $r2 = Test-FileReadable -Path $hit.FullName
            Write-Log $(if ($r2.Ok) { "重試後可讀 $dll" } else { "仍不可讀 $dll" })
            if (-not $r2.Ok) { $script:Issues.Add(('Unreadable:{0}:{1}' -f $dll, $hit.FullName)) }
          }
        }
      }
    }
  }
}

function Stop-GamingServicesBlockers {
  Write-Section '釋放可能占用 .NET Native 的程序'
  $names = @(
    'GameBar', 'GameBarFTServer', 'gamingservices', 'gamingservicesnet',
    'XboxGameBarWidgets', 'XboxPcApp', 'XboxPcAppFT', 'XboxPcTray', 'GamingServices'
  )
  foreach ($n in $names) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
      Write-Log "Stop-Process $($_.Name) PID=$($_.Id)"
      if (-not $WhatIfPreference) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      }
    }
  }
  if (-not $SkipGamingServicesRemoval -and -not $WhatIfPreference) {
    $gs = Get-AppxPackage Microsoft.GamingServices -ErrorAction SilentlyContinue
    if ($gs) {
      Write-Log "暫時移除目前使用者的 GamingServices（可稍後從市集裝回）: $($gs.PackageFullName)"
      try {
        $gs | Remove-AppxPackage -ErrorAction Stop
        $script:Actions.Add('Removed:Microsoft.GamingServices')
      } catch {
        Write-Log "無法移除 GamingServices: $($_.Exception.Message)" 'WARN'
      }
    }
  }
  Start-Sleep -Seconds 2
}

function Register-PackageByName {
  param([string]$Name, [ValidateSet('X64', 'X86', 'Any')]$Arch = 'Any')
  $pkgs = @(Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue)
  if ($Arch -ne 'Any') {
    $pkgs = @($pkgs | Where-Object { $_.Architecture -eq $Arch })
  }
  foreach ($p in $pkgs) {
    $m = Join-Path $p.InstallLocation 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $m)) {
      Write-Log "無 Manifest: $($p.PackageFullName)" 'WARN'
      continue
    }
    Write-Log "Register $($p.PackageFullName)"
    if ($WhatIfPreference) {
      Write-Log 'WhatIf: skip Register' 'WHATIF'
      continue
    }
    try {
      Add-AppxPackage -DisableDevelopmentMode -Register $m -ErrorAction Stop
      Write-Log '  Register OK' 'OK'
      $script:Actions.Add(('Register:{0}' -f $p.PackageFullName))
    } catch {
      $msg = $_.Exception.Message
      Write-Log "  Register FAIL: $msg" 'ERROR'
      $script:Issues.Add(('RegisterFail:{0}:{1}' -f $p.PackageFullName, $msg))
      if ($msg -match '0x80073D02|使用中|in use|GamingServices') {
        Write-Log '偵測到占用錯誤，再次嘗試停止 Gaming 相關程序後重試一次' 'WARN'
        Stop-GamingServicesBlockers
        try {
          Add-AppxPackage -DisableDevelopmentMode -Register $m -ErrorAction Stop
          Write-Log '  Register OK（重試）' 'OK'
          $script:Actions.Add(('RegisterRetry:{0}' -f $p.PackageFullName))
        } catch {
          Write-Log "  重試仍失敗: $($_.Exception.Message)" 'ERROR'
        }
      }
    }
  }
}

function Reset-UserPackageState {
  param([string]$FamilyName)
  $dir = Join-Path $env:LOCALAPPDATA "Packages\$FamilyName"
  Write-Log "使用者 Packages: $dir Exists=$(Test-Path -LiteralPath $dir)"
  if (-not (Test-Path -LiteralPath $dir)) { return }
  if ($WhatIfPreference) {
    Write-Log 'WhatIf: 將備份並重置使用者 Packages' 'WHATIF'
    return
  }
  Get-Process CalculatorApp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  $bak = $dir + '.bak_' + (Get-Date -Format 'HHmmss')
  try {
    Rename-Item -LiteralPath $dir -NewName (Split-Path $bak -Leaf) -ErrorAction Stop
    Write-Log "已改名備份 → $bak"
    $script:Actions.Add(('UserPkgBackup:{0}' -f $bak))
  } catch {
    try {
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
      Write-Log '改名失敗，已直接刪除使用者 Packages'
      $script:Actions.Add(('UserPkgDeleted:{0}' -f $FamilyName))
    } catch {
      Write-Log "無法重置使用者 Packages: $($_.Exception.Message)" 'WARN'
    }
  }
}

function Test-CalculatorLaunch {
  Write-Section '啟動測試：計算機'
  $t0 = Get-Date
  $calc = Get-AppxPackage Microsoft.WindowsCalculator | Where-Object Architecture -eq 'X64' | Select-Object -First 1
  if (-not $calc) {
    Write-Log '計算機未安裝' 'ERROR'
    $script:Issues.Add('CalculatorNotInstalled')
    return $false
  }
  Write-Log "計算機 Version=$($calc.Version) Status=$($calc.Status)"

  try {
    Start-Process "shell:AppsFolder\$($calc.PackageFamilyName)!App" -ErrorAction Stop
  } catch {
    Write-Log "Start-Process 失敗: $($_.Exception.Message)" 'ERROR'
  }
  Start-Sleep -Seconds 8

  $proc = Get-Process -Name CalculatorApp -ErrorAction SilentlyContinue
  if ($proc) {
    Write-Log "成功：CalculatorApp PID=$($proc.Id)" 'OK'
    return $true
  }

  $ev = @(Get-WinEvent -LogName 'Microsoft-Windows-TWinUI/Operational' -ErrorAction SilentlyContinue |
    Where-Object { $_.TimeCreated -ge $t0 -and $_.Id -eq 5961 -and $_.Message -like '*Calculator*' } |
    Select-Object -First 3)
  foreach ($e in $ev) {
    Write-Log "5961: $($e.Message -replace '\s+',' ')" 'ERROR'
  }

  $am = @(Get-WinEvent -LogName 'Microsoft-Windows-AppModel-Runtime/Admin' -ErrorAction SilentlyContinue |
    Where-Object { $_.TimeCreated -ge $t0 } | Select-Object -First 8)
  foreach ($e in $am) {
    $m = ($e.Message -replace '\s+', ' ')
    if ($m.Length -gt 200) { $m = $m.Substring(0, 200) }
    Write-Log "AppModel Id=$($e.Id) $m"
    if ($e.Id -eq 40) { $script:Issues.Add('AppContainerNotCreated') }
  }
  return $false
}

function Install-CalculatorIfMissing {
  $calc = Get-AppxPackage Microsoft.WindowsCalculator -ErrorAction SilentlyContinue
  if ($calc) { return }
  Write-Section '計算機未安裝 — 嘗試 winget'
  if ($WhatIfPreference) { Write-Log 'WhatIf: winget install 9WZDNCRFHVN5' 'WHATIF'; return }
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    Write-Log 'winget install 9WZDNCRFHVN5 ...'
    & winget install 9WZDNCRFHVN5 --accept-package-agreements --accept-source-agreements
    $script:Actions.Add('winget:9WZDNCRFHVN5')
  } else {
    Write-Log '無 winget，開啟市集產品頁'
    Start-Process 'ms-windows-store://pdp/?ProductId=9WZDNCRFHVN5'
    $script:Issues.Add('NeedManualStoreInstall')
  }
}

function Ensure-Services {
  Write-Section '關鍵服務'
  foreach ($n in @('StateRepository', 'AppXSvc', 'ClipSVC', 'AppReadiness', 'camsvc', 'LicenseManager')) {
    $s = Get-Service -Name $n -ErrorAction SilentlyContinue
    if (-not $s) { Write-Log "服務不存在: $n" 'WARN'; continue }
    Write-Log "$n Status=$($s.Status) StartType=$($s.StartType)"
    if ($s.Status -ne 'Running' -and -not $WhatIfPreference) {
      try {
        Start-Service $n -ErrorAction Stop
        Write-Log "已啟動 $n" 'OK'
      } catch {
        Write-Log "無法啟動 $n : $($_.Exception.Message)" 'WARN'
      }
    }
  }
}

# ----------------------------- main -----------------------------
Write-Section '0. 環境'
if (-not (Test-IsAdmin)) {
  Write-Host '請以系統管理員執行此腳本。' -ForegroundColor Red
  exit 1
}
$os = Get-CimInstance Win32_OperatingSystem
Write-Log "User=$env:USERNAME Computer=$env:COMPUTERNAME"
Write-Log "OS=$($os.Caption) Build=$($os.BuildNumber)"
Write-Log "LogDir=$script:LogDir"
Write-Log "FixAllNativeApps=$FixAllNativeApps SkipGamingServicesRemoval=$SkipGamingServicesRemoval"

Ensure-Services
Install-CalculatorIfMissing

# 核心：Procmon 已證實 VCLibs vcruntime140_app.dll ACCESS DENIED；
# 對話框缺 mrt100_app.dll / SharedLibrary.dll → Native Runtime/Framework
Write-Section '1. 修復相依套件 ACL 並檢查關鍵 DLL'
$dependencyNames = @(
  'Microsoft.VCLibs.140.00',
  'Microsoft.VCLibs.140.00.UWPDesktop',
  'Microsoft.NET.Native.Runtime.2.2',
  'Microsoft.NET.Native.Framework.2.2',
  'Microsoft.UI.Xaml.2.8'
)
Repair-NamedPackages -PackageNames $dependencyNames

# 計算機本體目錄也補 ACL（避免套件內 dll 不可讀）
Write-Section '2. 計算機套件本體 ACL'
$calcPkgs = @(Get-AppxPackage Microsoft.WindowsCalculator -ErrorAction SilentlyContinue)
foreach ($p in $calcPkgs) {
  if ($p.InstallLocation) {
    Repair-PackageAcl -Root $p.InstallLocation -Label $p.PackageFullName | Out-Null
  }
}

Write-Section '3. 釋放占用並 Register 框架（優先 x64）'
Stop-GamingServicesBlockers
foreach ($n in @(
  'Microsoft.NET.Native.Framework.2.2',
  'Microsoft.NET.Native.Runtime.2.2',
  'Microsoft.VCLibs.140.00',
  'Microsoft.VCLibs.140.00.UWPDesktop',
  'Microsoft.UI.Xaml.2.8'
)) {
  Register-PackageByName -Name $n -Arch 'X64'
  Register-PackageByName -Name $n -Arch 'X86'
}

Write-Section '4. 重置計算機使用者狀態並 Register'
Reset-UserPackageState -FamilyName 'Microsoft.WindowsCalculator_8wekyb3d8bbwe'
Register-PackageByName -Name 'Microsoft.WindowsCalculator' -Arch 'X64'

if ($FixAllNativeApps) {
  Write-Section '5. 同類型 App（時鐘／便利貼／相機）'
  foreach ($pair in @(
    @{ Name = 'Microsoft.WindowsAlarms'; Family = 'Microsoft.WindowsAlarms_8wekyb3d8bbwe' },
    @{ Name = 'Microsoft.MicrosoftStickyNotes'; Family = 'Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe' },
    @{ Name = 'Microsoft.WindowsCamera'; Family = 'Microsoft.WindowsCamera_8wekyb3d8bbwe' }
  )) {
    Reset-UserPackageState -FamilyName $pair.Family
    Register-PackageByName -Name $pair.Name -Arch 'Any'
  }
}

$ok = Test-CalculatorLaunch

Write-Section '摘要'
Write-Log "執行動作數: $($script:Actions.Count)"
$script:Actions | ForEach-Object { Write-Log "  ACTION $_" }
if ($script:Issues.Count) {
  Write-Log "待注意項目: $($script:Issues.Count)" 'WARN'
  $script:Issues | ForEach-Object { Write-Log "  ISSUE $_" 'WARN' }
}

if ($ok) {
  Write-Log '結果: 計算機進程已出現，修復成功。' 'OK'
  Write-Host "`n完成。報告: $script:LogFile" -ForegroundColor Green
  exit 0
} else {
  Write-Log '結果: 計算機仍未正常啟動。' 'ERROR'
  Write-Log '若報告中有 Unreadable:dll，把該路徑貼給協助者。' 'ERROR'
  Write-Log '若有 AppContainerNotCreated，可再查本機安全性原則／使用者設定檔。' 'ERROR'
  Write-Log 'GamingServices 若被移除，可於 Microsoft Store 搜尋 Xbox / Gaming Services 裝回。' 'INFO'
  Write-Host "`n未完全成功。報告: $script:LogFile" -ForegroundColor Yellow
  exit 2
}
