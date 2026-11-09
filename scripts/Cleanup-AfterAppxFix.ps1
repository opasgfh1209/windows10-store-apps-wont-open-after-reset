#requires -Version 5.1
<#
.SYNOPSIS
  Store／計算機修好之後的收尾回復腳本。

.DESCRIPTION
  預設只「報告」，不改任何東西。加上 -Apply 才會執行，而且每一段都會先問 Y/N。
  會動權限的步驟，都會「先備份、套用、啟動測試、失敗就自動還原」。
  不會動：框架資料夾上 BUILTIN\Users 與 ALL APPLICATION PACKAGES 的讀取執行權限（修復本體）、
          已重新註冊的套件、Fix-UWP-Calculator.ps1 與它的紀錄（只會封存，不會刪）。

  用法（你自己帳號開的「系統管理員」Windows PowerShell，64 位元，不要用 SYSTEM／PsExec 視窗）：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Cleanup-AfterAppxFix.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Cleanup-AfterAppxFix.ps1 -Apply
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Cleanup-AfterAppxFix.ps1 -Rollback "C:\Users\<USER>\Documents\AppX收尾_日期時間"
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [string]$Rollback = '',
  [switch]$Yes
)

$ErrorActionPreference = 'Continue'
$script:Stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:WA        = 'C:\Program Files\WindowsApps'
$script:Done      = New-Object System.Collections.ArrayList
$script:Skipped   = New-Object System.Collections.ArrayList
$script:Manifest  = New-Object System.Collections.ArrayList
$script:LogFile   = $null
$script:BackupDir = $null
$script:Archive   = $null

# ---------- 輸出 ----------
function Say {
  param([string]$Text, [string]$Color = 'Gray')
  Write-Host $Text -ForegroundColor $Color
  if ($script:LogFile) { try { Add-Content -LiteralPath $script:LogFile -Value $Text -Encoding UTF8 } catch {} }
}
function Sect { param([string]$Text) Say ''; Say ('==== ' + $Text + ' ====') 'Cyan' }
function Line { param([string]$Text) Say ('  ' + $Text) 'Gray' }
function Good { param([string]$Text) Say ('  [OK] ' + $Text) 'Green' }
function Note { param([string]$Text) Say ('  [注意] ' + $Text) 'Yellow' }
function Fail { param([string]$Text) Say ('  [失敗] ' + $Text) 'Red' }

function Confirm-Step {
  param([string]$Title)
  if (-not $Apply) { return $false }
  if ($Yes) { return $true }
  $a = Read-Host ('  要執行「' + $Title + '」嗎？(Y/N，預設 N)')
  return ($a -match '^[Yy]')
}

# ---------- 環境檢查 ----------
$ident = [Security.Principal.WindowsIdentity]::GetCurrent()
$prin  = New-Object Security.Principal.WindowsPrincipal($ident)
if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host '請用「以系統管理員身分執行」開啟 Windows PowerShell，再跑一次。' -ForegroundColor Red; exit 1
}
if ($ident.IsSystem) {
  Write-Host '這是 SYSTEM 視窗。請改用你自己帳號開的系統管理員視窗。' -ForegroundColor Red; exit 1
}
if (-not [Environment]::Is64BitProcess) {
  Write-Host '這是 32 位元的 PowerShell。請改開 64 位元的 Windows PowerShell（開始功能表那個，不是 x86）。' -ForegroundColor Red; exit 1
}

$docs = [Environment]::GetFolderPath('MyDocuments')
$script:BackupDir = Join-Path $docs ('AppX收尾_' + $script:Stamp)
$script:Archive   = Join-Path $docs 'AppX修復存檔'
New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
$script:LogFile = Join-Path $script:BackupDir 'report.txt'

# ---------- 共用函式 ----------
function Run-Icacls {
  param([string[]]$IcaclsArgs)
  $out = @(& icacls.exe @IcaclsArgs 2>&1 | ForEach-Object { [string]$_ })
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function LastLine {
  param($Lines)
  $l = @($Lines | Where-Object { $_ -and $_.Trim() })
  if ($l.Count -gt 0) { return $l[$l.Count - 1].Trim() }
  return ''
}
function Get-OwnerSafe {
  param([string]$Path)
  try { return [string](Get-Acl -LiteralPath $Path -ErrorAction Stop).Owner } catch { return '(讀不到)' }
}
function Get-AclFacts {
  param([string]$Path)
  $r = Run-Icacls @($Path)
  $lines = @($r.Out)
  $adminExplicit = $false
  foreach ($l in $lines) {
    if ($l -match 'BUILTIN\\Administrators:' -and $l -notmatch 'BUILTIN\\Administrators:\(I\)') { $adminExplicit = $true }
  }
  $txt = $lines -join "`n"
  return [pscustomobject]@{
    HasUsers      = ($txt -match 'BUILTIN\\Users:')
    HasAap        = (($txt -match 'ALL APPLICATION PACKAGES:') -or ($txt -match 'S-1-15-2-1:'))
    AdminExplicit = $adminExplicit
    Raw           = $lines
  }
}
function Get-DirSize {
  param([string]$Path)
  try {
    $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($it.PSIsContainer) {
      $s = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    } else { $s = $it.Length }
    if (-not $s) { $s = 0 }
    return [double]$s
  } catch { return [double]0 }
}
function Fmt-Size {
  param([double]$Bytes)
  if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
  return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function New-AclBackup {
  param([string]$Path, [string]$Tag, [bool]$Recurse = $false)
  $file = Join-Path $script:BackupDir ('acl_' + $Tag + '.txt')
  $a = @($Path, '/save', $file)
  if ($Recurse) { $a += '/T' }
  $a += '/C'
  $r = Run-Icacls $a
  $parent = Split-Path -Parent $Path
  [void]$script:Manifest.Add([pscustomobject]@{
    Path = $Path; Parent = $parent; AclFile = $file; OwnerBefore = (Get-OwnerSafe $Path); Recurse = $Recurse })
  $script:Manifest | Export-Csv -LiteralPath (Join-Path $script:BackupDir 'manifest.csv') -NoTypeInformation -Encoding UTF8
  Line ('已備份權限：' + $Path + '  →  ' + (Split-Path -Leaf $file) + '  （' + (LastLine $r.Out) + '）')
  return $file
}

# ---------- 啟動測試 ----------
function Test-Repair {
  param([string]$Label)
  Sect ('啟動測試（' + $Label + '）')
  $items = @(
    @{ Name = '計算機';          Aumid = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'; Proc = 'CalculatorApp'; Pkg = 'Microsoft.WindowsCalculator' },
    @{ Name = 'Microsoft Store'; Aumid = 'Microsoft.WindowsStore_8wekyb3d8bbwe!App';      Proc = 'WinStore.App';   Pkg = 'Microsoft.WindowsStore' }
  )
  $allOk = $true
  foreach ($it in $items) {
    Get-Process -Name $it.Proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    $t0 = Get-Date
    try { Start-Process ('shell:AppsFolder\' + $it.Aumid) -ErrorAction Stop }
    catch { Fail ($it.Name + ' 啟動要求失敗：' + $_.Exception.Message); $allOk = $false; continue }
    for ($i = 0; $i -lt 12; $i++) {
      Start-Sleep -Seconds 1
      if (Get-Process -Name $it.Proc -ErrorAction SilentlyContinue) { break }
    }
    Start-Sleep -Seconds 4
    $alive = [bool](Get-Process -Name $it.Proc -ErrorAction SilentlyContinue)
    $errs = @(Get-WinEvent -LogName 'Microsoft-Windows-TWinUI/Operational' -ErrorAction SilentlyContinue |
              Where-Object { $_.Id -eq 5961 -and $_.TimeCreated -ge $t0 -and $_.Message -like ('*' + $it.Pkg + '*') })
    if ($alive -and $errs.Count -eq 0) { Good ($it.Name + '：程序在執行，沒有啟動失敗紀錄') }
    else { Fail ($it.Name + '：程序在執行=' + $alive + '，啟動失敗紀錄 ' + $errs.Count + ' 筆'); $allOk = $false }
    Get-Process -Name $it.Proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }
  return $allOk
}

function Invoke-WithTest {
  param([string]$Title, [scriptblock]$Action, [scriptblock]$Undo)
  & $Action
  $ok = Test-Repair ('套用後：' + $Title)
  if ($ok) { Good ('「' + $Title + '」完成，測試通過'); [void]$script:Done.Add($Title); return }
  Fail ('「' + $Title + '」之後測試失敗，開始自動還原')
  & $Undo
  $ok2 = Test-Repair ('還原後：' + $Title)
  if ($ok2) { Note '已還原，測試恢復正常。這一項先不要做，把上面的訊息貼給 Claude。' }
  else { Fail '還原後仍然失敗。請重開機再測；仍失敗就用 -Rollback 還原全部備份，並把訊息貼給 Claude。' }
  [void]$script:Skipped.Add($Title + '（測試失敗，已還原）')
}

# ---------- 還原模式 ----------
if ($Rollback) {
  Sect ('還原權限：' + $Rollback)
  $mf = Join-Path $Rollback 'manifest.csv'
  if (-not (Test-Path -LiteralPath $mf)) { Fail '找不到 manifest.csv，這不是本腳本建立的備份資料夾。'; exit 1 }
  foreach ($r in @(Import-Csv -LiteralPath $mf -Encoding UTF8)) {
    if (-not (Test-Path -LiteralPath $r.AclFile)) { Note ('缺少備份檔：' + $r.AclFile); continue }
    Line ('還原：' + $r.Path)
    if ($r.Recurse -eq 'True' -and $r.Path -like 'C:\Program Files\WindowsApps\*') { & takeown.exe /f $r.Path /a /r /d y 2>&1 | Out-Null }
    $x = Run-Icacls @($r.Parent, '/restore', $r.AclFile, '/C')
    Line ('  DACL：' + (LastLine $x.Out))
    if ($r.OwnerBefore -and $r.OwnerBefore -ne '(讀不到)') {
      $sw = @($r.Path, '/setowner', $r.OwnerBefore)
      if ($r.Recurse -eq 'True') { $sw += '/T' }
      $sw += '/C'
      $y = Run-Icacls $sw
      Line ('  擁有者：' + (LastLine $y.Out))
    }
  }
  Good '還原完成。建議重開機後再測試計算機與 Store。'
  exit 0
}

# ---------- 目標資料夾 ----------
function Get-TargetFolders {
  $defs = @(
    @{ Name = 'Microsoft.VCLibs.140.00';            Owner = 'NT SERVICE\TrustedInstaller' },
    @{ Name = 'Microsoft.VCLibs.140.00.UWPDesktop'; Owner = 'NT SERVICE\TrustedInstaller' },
    @{ Name = 'Microsoft.NET.Native.Runtime.2.2';   Owner = 'NT SERVICE\TrustedInstaller' },
    @{ Name = 'Microsoft.NET.Native.Framework.2.2'; Owner = 'NT SERVICE\TrustedInstaller' },
    @{ Name = 'Microsoft.UI.Xaml.2.8';              Owner = 'NT SERVICE\TrustedInstaller' },
    @{ Name = 'Microsoft.WindowsCalculator';        Owner = 'NT AUTHORITY\SYSTEM' },
    @{ Name = 'Microsoft.WindowsStore';             Owner = 'NT AUTHORITY\SYSTEM' },
    @{ Name = 'Microsoft.StorePurchaseApp';         Owner = 'NT AUTHORITY\SYSTEM' }
  )
  $seen = @{}
  $list = New-Object System.Collections.ArrayList
  foreach ($d in $defs) {
    foreach ($p in @(Get-AppxPackage -Name $d.Name -AllUsers -ErrorAction SilentlyContinue)) {
      $loc = [string]$p.InstallLocation
      if ($loc -and -not $seen.ContainsKey($loc) -and (Test-Path -LiteralPath $loc)) {
        $seen[$loc] = $true
        [void]$list.Add([pscustomobject]@{ Name = $p.Name; Arch = [string]$p.Architecture; Path = $loc; WantOwner = $d.Owner })
      }
    }
  }
  return $list.ToArray()
}

# ================= 各段 =================

function Sec-HiveOwner {
  Sect '1. 登錄檔 SOFTWARE 的檔案擁有者（之前的 takeown 改過）'
  $hive = Join-Path $env:SystemRoot 'System32\config\SOFTWARE'
  $cur = Get-OwnerSafe $hive
  Line ('目前擁有者：' + $cur)
  $ref = @()
  foreach ($n in @('SYSTEM', 'SECURITY', 'SAM', 'DEFAULT')) {
    $o = Get-OwnerSafe (Join-Path $env:SystemRoot ('System32\config\' + $n))
    if ($o -ne '(讀不到)') { $ref += $o }
  }
  if ($ref.Count -gt 0) { $want = ($ref | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name }
  else { $want = 'NT AUTHORITY\SYSTEM' }
  Line ('同資料夾其他登錄檔的擁有者：' + (($ref | Select-Object -Unique) -join ', ') + '  →  目標：' + $want)
  if ($cur -eq $want) { Good '已經是正確的擁有者'; return }
  if ($cur -eq '(讀不到)') { Note '讀不到目前的擁有者，略過'; return }
  if (-not (Confirm-Step ('把 SOFTWARE 檔案的擁有者改回 ' + $want))) { [void]$script:Skipped.Add('SOFTWARE 擁有者'); return }
  $r = Run-Icacls @($hive, '/setowner', $want)
  $after = Get-OwnerSafe $hive
  if ($after -eq $want) { Good ('已改回：' + $after); [void]$script:Done.Add('SOFTWARE 擁有者') }
  else { Fail ('沒改成功（目前 ' + $after + '）：' + (LastLine $r.Out)) }
}

function Sec-ExecPolicy {
  Sect '2. 腳本執行原則（ExecutionPolicy）'
  Get-ExecutionPolicy -List | ForEach-Object { Line ('{0,-14} {1}' -f $_.Scope, $_.ExecutionPolicy) }
  $lm = [string](Get-ExecutionPolicy -Scope LocalMachine)
  $cu = [string](Get-ExecutionPolicy -Scope CurrentUser)
  $lmOk = ($lm -eq 'Restricted' -or $lm -eq 'Undefined')
  $cuOk = ($cu -eq 'Undefined')
  if ($lmOk -and $cuOk) { Good 'LocalMachine 與 CurrentUser 都是預設值'; return }
  Note ('LocalMachine=' + $lm + '，CurrentUser=' + $cu + '（Windows 10 預設是 Restricted／Undefined）')
  if (-not (Confirm-Step '把執行原則改回預設')) { [void]$script:Skipped.Add('執行原則'); return }
  try {
    if (-not $lmOk) { Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope LocalMachine -Force -ErrorAction Stop }
    if (-not $cuOk) { Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser -Force -ErrorAction Stop }
    Good '已改回預設'; [void]$script:Done.Add('執行原則')
  } catch { Fail ('設定失敗：' + $_.Exception.Message) }
}

function Sec-Services {
  Sect '3. AppX 相關服務的啟動類型'
  $expect = @{
    'StateRepository' = 'Manual'; 'AppXSvc' = 'Manual'; 'ClipSVC' = 'Manual'; 'AppReadiness' = 'Manual'
    'InstallService' = 'Manual'; 'camsvc' = 'Manual'; 'LicenseManager' = 'Manual'; 'TokenBroker' = 'Manual'
    'wlidsvc' = 'Manual'; 'wuauserv' = 'Manual'; 'TrustedInstaller' = 'Manual'; 'cryptsvc' = 'Automatic'
  }
  $diff = @()
  foreach ($k in ($expect.Keys | Sort-Object)) {
    $s = Get-Service -Name $k -ErrorAction SilentlyContinue
    if (-not $s) { Line ($k + '：不存在'); continue }
    $st = [string]$s.StartType
    Line ('{0,-18} {1,-9} 啟動類型 {2,-10} 預期 {3}' -f $k, $s.Status, $st, $expect[$k])
    if ($st -ne $expect[$k]) { $diff += $k }
  }
  if ($diff.Count -eq 0) { Good '啟動類型都是預設值'; return }
  Note ('和預設不同：' + ($diff -join ', '))
  if (-not (Confirm-Step '把這些服務的啟動類型改回預設')) { [void]$script:Skipped.Add('服務啟動類型'); return }
  foreach ($k in $diff) {
    try { Set-Service -Name $k -StartupType $expect[$k] -ErrorAction Stop; Good ($k + ' → ' + $expect[$k]) }
    catch { Fail ($k + '：' + $_.Exception.Message) }
  }
  [void]$script:Done.Add('服務啟動類型')
}

function Sec-Registry {
  Sect '4. 登錄機碼殘留（restore-appx 建的 PackageRepository、Sysinternals 同意記錄）'
  Line '說明：PsExec 開的 32 位元視窗會把機碼建到 WOW6432Node，所以兩個位置都查。'
  $keys = @(
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\PackageRepository',
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Appx\PackageRepository'
  )
  foreach ($k in $keys) {
    if (-not (Test-Path -LiteralPath $k)) { Line ('不存在：' + $k.Replace('Registry::', '')); continue }
    $vals = @((Get-Item -LiteralPath $k).GetValueNames()).Count
    $subs = @(Get-ChildItem -LiteralPath $k -ErrorAction SilentlyContinue).Count
    Line ('存在：' + $k.Replace('Registry::', '') + '（值 ' + $vals + ' 個、子機碼 ' + $subs + ' 個）')
    if ($vals -gt 0 -or $subs -gt 0) { Note '這個機碼有內容，不自動刪。'; continue }
    if (Confirm-Step ('刪除空的機碼 ' + $k.Replace('Registry::', ''))) {
      try { Remove-Item -LiteralPath $k -Force -ErrorAction Stop; Good '已刪除'; [void]$script:Done.Add('PackageRepository 機碼') }
      catch { Note ('刪不掉（建立它時用的是 SYSTEM 權限）：' + $_.Exception.Message + '。這是空機碼，留著沒有影響。') }
    }
  }
  foreach ($k in @('HKCU:\Software\Sysinternals\PsExec', 'HKCU:\Software\Sysinternals\Process Monitor')) {
    if (Test-Path -LiteralPath $k) {
      Line ('存在：' + $k)
      if (Confirm-Step ('刪除 ' + $k)) {
        try { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop; Good '已刪除'; [void]$script:Done.Add($k) }
        catch { Fail $_.Exception.Message }
      }
    } else { Line ('不存在：' + $k) }
  }
}

function Sec-Tools {
  Sect '5. 工具殘留（PsExec 服務、Procmon 驅動、排程、Pester）'
  $ps = Get-Service -Name 'PSEXESVC' -ErrorAction SilentlyContinue
  if ($ps) {
    Line ('PSEXESVC 服務存在，狀態 ' + $ps.Status)
    if (Confirm-Step '刪除 PSEXESVC 服務') {
      if ($ps.Status -ne 'Stopped') { Stop-Service -Name 'PSEXESVC' -Force -ErrorAction SilentlyContinue }
      $x = (& sc.exe delete PSEXESVC 2>&1 | Out-String).Trim(); Line $x
    }
  } else { Line 'PSEXESVC：不存在' }

  $pmKey = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PROCMON24'
  if (Test-Path -LiteralPath $pmKey) {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Procmon*' }).Count
    Line ('Procmon 驅動服務 PROCMON24 存在；Procmon 執行中的程序 ' + $running + ' 個')
    if ($running -gt 0) { Note '請先關掉 Process Monitor 再處理這一項。' }
    elseif (Confirm-Step '刪除 PROCMON24 驅動服務與檔案') {
      $x = (& sc.exe delete PROCMON24 2>&1 | Out-String).Trim(); Line $x
      $sys = Join-Path $env:SystemRoot 'System32\drivers\PROCMON24.SYS'
      if (Test-Path -LiteralPath $sys) { try { Remove-Item -LiteralPath $sys -Force -ErrorAction Stop; Good '已刪除 PROCMON24.SYS' } catch { Note ('驅動檔刪不掉（重開機後再試）：' + $_.Exception.Message) } }
      [void]$script:Done.Add('Procmon 驅動')
    }
  } else { Line 'Procmon 驅動服務：不存在' }

  & schtasks.exe /Query /TN 'FixXamlCat' 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Note '排程工作 FixXamlCat 存在（之前建立失敗的那個沒有清乾淨）'
    if (Confirm-Step '刪除排程工作 FixXamlCat') { & schtasks.exe /Delete /TN 'FixXamlCat' /F 2>&1 | ForEach-Object { Line $_ } }
  } else { Line '排程工作 FixXamlCat：不存在'}

  $pest = @(Get-Module -ListAvailable -Name Pester -ErrorAction SilentlyContinue | Where-Object { $_.Version -eq [version]'5.9.1' })
  if ($pest.Count -gt 0) {
    foreach ($m in $pest) {
      Line ('Pester 5.9.1（跑 restore-appx 測試時裝的）：' + $m.ModuleBase)
      if (Confirm-Step ('刪除 ' + $m.ModuleBase)) {
        try { Remove-Item -LiteralPath $m.ModuleBase -Recurse -Force -ErrorAction Stop; Good '已刪除'; [void]$script:Done.Add('Pester 5.9.1') }
        catch { Fail $_.Exception.Message }
      }
    }
  } else { Line 'Pester 5.9.1：不存在' }
}

function Sec-ProgramDataPackages {
  Sect '6. C:\ProgramData\Packages（restore-appx 改過權限）'
  $p = 'C:\ProgramData\Packages'
  if (-not (Test-Path -LiteralPath $p)) { Line '資料夾不存在，略過'; return }
  Line ('目前擁有者：' + (Get-OwnerSafe $p))
  $cur = Run-Icacls @($p)
  @($cur.Out | Where-Object { $_ -and $_.Trim() } | Select-Object -First 14) | ForEach-Object { Line ('  ' + $_) }
  $dirs = @($env:TEMP, 'C:\Windows\Temp')
  foreach ($u in @(Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue)) { $dirs += (Join-Path $u.FullName 'AppData\Local\Temp') }
  $found = @()
  foreach ($d in ($dirs | Select-Object -Unique)) {
    $rd = Join-Path $d 'Restore-AppX'
    if (Test-Path -LiteralPath $rd) {
      $found += @(Get-ChildItem -LiteralPath $rd -Filter 'AclBackup_ProgramDataPackages_*' -File -ErrorAction SilentlyContinue)
    }
  }
  if ($found.Count -eq 0) {
    Note '找不到 restore-appx 留下的原始權限備份，無法自動回復。把上面 icacls 的輸出貼給 Claude。'
    [void]$script:Skipped.Add('ProgramData\Packages（沒有備份檔）'); return
  }
  $first = $found | Sort-Object LastWriteTime | Select-Object -First 1
  Line ('最早的備份（修改前）：' + $first.FullName)
  $content = @(Get-Content -LiteralPath $first.FullName -ErrorAction SilentlyContinue)
  $content | Select-Object -First 8 | ForEach-Object { Line ('  | ' + $_) }
  $sddlLine = $content | Where-Object { $_ -match '^\s*O:\S+.*D:' } | Select-Object -First 1
  $iaclLine = $content | Where-Object { $_ -match '^\s*D:' } | Select-Object -First 1
  if (-not $sddlLine -and -not $iaclLine) {
    Note '備份檔的格式看不懂，不自動處理。把上面 | 開頭的內容貼給 Claude。'
    [void]$script:Skipped.Add('ProgramData\Packages（格式不明）'); return
  }
  Note '只能還原根目錄的權限；工具對子項目做的遞迴授權沒有備份，無法自動還原。'
  if (-not (Confirm-Step '用這份備份還原 ProgramData\Packages 根目錄的權限')) { [void]$script:Skipped.Add('ProgramData\Packages'); return }
  $snap = New-AclBackup $p 'ProgramDataPackages' $false
  Invoke-WithTest 'ProgramData\Packages 根目錄權限還原' {
    if ($sddlLine) {
      $acl = Get-Acl -LiteralPath $p
      $acl.SetSecurityDescriptorSddlForm($sddlLine.Trim(), [Security.AccessControl.AccessControlSections]::Access)
      Set-Acl -LiteralPath $p -AclObject $acl
    } else {
      [void](Run-Icacls @('C:\ProgramData', '/restore', $first.FullName, '/C'))
    }
  } {
    [void](Run-Icacls @('C:\ProgramData', '/restore', $snap, '/C'))
  }
}

function Sec-WindowsAppsRoot {
  Sect '7. C:\Program Files\WindowsApps 根目錄與套件資料夾擁有者'
  $own = Get-OwnerSafe $script:WA
  Line ('根目錄擁有者：' + $own + '（原廠是 NT SERVICE\TrustedInstaller）')
  $r = Run-Icacls @($script:WA)
  @($r.Out | Where-Object { $_ -and $_.Trim() } | Select-Object -First 16) | ForEach-Object { Line ('  ' + $_) }
  $odd = @($r.Out | Where-Object { ($_ -match ([regex]::Escape($env:USERNAME) + ':')) -or ($_ -match 'Everyone:') -or ($_ -match 'Authenticated Users:') })
  if ($odd.Count -gt 0) { Note '根目錄權限裡有你的帳號或 Everyone，不是原廠樣子。把上面的輸出貼給 Claude，我給精準指令（這裡不自動改）。' }
  if ($own -match 'TrustedInstaller') { Good '根目錄擁有者正常' }
  elseif ($own -eq '(讀不到)') { Note '讀不到根目錄的擁有者' }
  else {
    Note ('根目錄擁有者不是 TrustedInstaller：' + $own)
    if (Confirm-Step '把 WindowsApps 根目錄的擁有者改回 TrustedInstaller（只改這一層）') {
      $oldOwner = $own
      [void](New-AclBackup $script:WA 'WindowsAppsRoot' $false)
      Invoke-WithTest 'WindowsApps 根目錄擁有者改回 TrustedInstaller' {
        [void](Run-Icacls @($script:WA, '/setowner', 'NT SERVICE\TrustedInstaller'))
      } {
        [void](Run-Icacls @($script:WA, '/setowner', $oldOwner))
      }
    }
  }
  $pk = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation -like 'C:\Program Files\WindowsApps\*' } | Select-Object -ExpandProperty InstallLocation -Unique)
  $odd2 = @()
  foreach ($loc in $pk) {
    $o = Get-OwnerSafe $loc
    if ($o -notmatch 'TrustedInstaller|SYSTEM|讀不到') { $odd2 += ($o + '   ' + (Split-Path -Leaf $loc)) }
  }
  if ($odd2.Count -gt 0) {
    Note ('擁有者不是 TrustedInstaller／SYSTEM 的套件資料夾共 ' + $odd2.Count + ' 個（供參考，不自動改；其中有些在我們動手前就是這樣）：')
    $odd2 | Select-Object -First 30 | ForEach-Object { Line ('  ' + $_) }
  } else { Good '所有套件資料夾的擁有者都是 TrustedInstaller 或 SYSTEM' }
}

function Sec-UsersAap {
  Sect '8. C:\Users 的 ALL APPLICATION PACKAGES 讀取權限（Grok 建議的遞迴授權）'
  $root = 'C:\Users'
  $docsDir = [Environment]::GetFolderPath('MyDocuments')
  $a = @((Run-Icacls @($root)).Out | Where-Object { $_ -match 'ALL APPLICATION PACKAGES|S-1-15-2-1' })
  $b = @((Run-Icacls @($docsDir)).Out | Where-Object { $_ -match 'ALL APPLICATION PACKAGES|S-1-15-2-1' })
  Line ('C:\Users：AAP 條目 ' + $a.Count + ' 筆；你的「文件」資料夾：' + $b.Count + ' 筆')
  if ($a.Count -eq 0 -and $b.Count -eq 0) { Good '沒有，已經是原樣'; return }
  Note '這會讓所有 Store 沙箱程式都能讀你的使用者資料夾。證據顯示修復不需要它（Procmon 沒有任何 C:\Users 的拒絕與修復有關）。'
  Note '要遞迴處理幾萬個檔案，備份和移除各要幾分鐘。'
  if (-not (Confirm-Step '移除 C:\Users 底下的 ALL APPLICATION PACKAGES 權限（有測試與自動還原）')) { [void]$script:Skipped.Add('C:\Users 的 AAP'); return }
  $snap = New-AclBackup $root 'Users' $true
  Invoke-WithTest '移除 C:\Users 的 AAP 權限' {
    $x = Run-Icacls @($root, '/remove:g', '*S-1-15-2-1', '/T', '/C')
    Line ('移除結果：' + (LastLine $x.Out))
  } {
    $x = Run-Icacls @('C:\', '/restore', $snap, '/C')
    Line ('還原結果：' + (LastLine $x.Out))
  }
}

function Sec-CalcBackups {
  Sect '9. 腳本留下的使用者資料備份資料夾（Packages 底下的 .bak_ 開頭）'
  $pk = Join-Path $env:LOCALAPPDATA 'Packages'
  $baks = @(Get-ChildItem -LiteralPath $pk -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.bak_\d{6}$' })
  if ($baks.Count -eq 0) { Good '沒有'; return }
  foreach ($b in $baks) { Line ($b.Name + '  ' + (Fmt-Size (Get-DirSize $b.FullName))) }
  Line '這些是 Fix-UWP-Calculator.ps1 改名備份的舊資料（計算機的歷程記錄之類），確認計算機正常後可以刪。'
  if (-not (Confirm-Step '刪除上面這些 .bak_ 資料夾')) { [void]$script:Skipped.Add('.bak_ 備份資料夾'); return }
  foreach ($b in $baks) {
    try { Remove-Item -LiteralPath $b.FullName -Recurse -Force -ErrorAction Stop; Good ('已刪除 ' + $b.Name) }
    catch { Fail ($b.Name + '：' + $_.Exception.Message) }
  }
  [void]$script:Done.Add('.bak_ 備份資料夾')
}

function Find-Candidates {
  $list = New-Object System.Collections.ArrayList
  function Add-Cand {
    param([string]$Path, [string]$Kind)
    if (Test-Path -LiteralPath $Path) { [void]$list.Add([pscustomobject]@{ Path = $Path; Kind = $Kind }) }
  }
  function Scan {
    param([string]$Dir, [string[]]$Patterns, [string]$Kind)
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    foreach ($pt in $Patterns) {
      foreach ($m in @(Get-ChildItem -LiteralPath $Dir -Filter $pt -Force -ErrorAction SilentlyContinue)) { Add-Cand $m.FullName $Kind }
    }
  }
  $evidence = @('AppX診斷報告*', 'AppX全面診斷_*', 'AppX證據包_*', 'xaml_before.txt', 'xaml28_x64_acl_backup.txt', 'ACL備份_*',
                'gpreport.html', 'backup_Ole.reg', 'backup_ImmersiveShell_AppID.reg', 'Fix-UWP-Calculator*', 'Logfile*.CSV', 'Logfile*.PML')
  $desk = @((Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:PUBLIC 'Desktop'),
            'C:\Windows\System32\config\systemprofile\Desktop', 'C:\Windows\SysWOW64\config\systemprofile\Desktop') | Select-Object -Unique
  foreach ($d in $desk) { Scan $d $evidence 'Evidence' }
  foreach ($d in $desk) { Scan $d @('AppX-XamlTrust-DiagRepair*', 'Post-Fix-Cleanup-Restore*') 'Tool' }
  Scan $docs @('未命名1.ps1') 'Tool'
  $dl = Join-Path $env:USERPROFILE 'Downloads'
  foreach ($d in @($dl, (Join-Path $dl 'FireFox下載'), $docs)) {
    Scan $d @('Logfile*.CSV', 'Logfile*.PML') 'Evidence'
  }
  foreach ($d in @($dl, (Join-Path $dl 'FireFox下載'))) {
    Scan $d @('Xaml28', 'MSStore Install', 'MicrosoftStore_Fix*', 'restore-appx*', 'Microsoft.VCLibs*', 'Microsoft.NET.Native*',
              'Microsoft.UI.Xaml*', 'Microsoft.WindowsStore_*', 'Procmon*', 'ProcessMonitor*', 'PSTools*') 'Tool'
  }
  foreach ($t in (@($env:TEMP, 'C:\Windows\Temp') | Select-Object -Unique)) {
    Scan $t @('Fix-UWP-Calculator_*', 'AppXDiag_*', 'AppX_FullDiag_*', 'Restore-AppX') 'Evidence'
    Scan $t @('xaml_2.8.*', 'Test-AppX-Backup-*') 'Tool'
  }
  Add-Cand 'C:\Windows\PSTools' 'Tool'
  return $list.ToArray()
}

function Move-Archive {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $script:Archive)) { New-Item -ItemType Directory -Path $script:Archive -Force | Out-Null }
  $leaf = Split-Path -Leaf $Path
  $dest = Join-Path $script:Archive $leaf
  if (Test-Path -LiteralPath $dest) { $dest = Join-Path $script:Archive ($script:Stamp + '_' + $leaf) }
  try { Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop; return $true }
  catch { Fail ('移動失敗 ' + $Path + '：' + $_.Exception.Message); return $false }
}

function Sec-Files {
  Sect '10. 測試檔、輸出紀錄與下載的工具'
  $c = @(Find-Candidates)
  if ($c.Count -eq 0) { Good '沒有找到'; return }
  $ev = @($c | Where-Object { $_.Kind -eq 'Evidence' })
  $tl = @($c | Where-Object { $_.Kind -eq 'Tool' })
  Line ('證據與紀錄（建議「封存」到 ' + $script:Archive + '，之後整理 GitHub 文件用）：' + $ev.Count + ' 項')
  foreach ($x in $ev) { Line ('  ' + (Fmt-Size (Get-DirSize $x.Path)).PadLeft(10) + '  ' + $x.Path) }
  Line ('下載的安裝檔與工具（建議「刪除」）：' + $tl.Count + ' 項')
  foreach ($x in $tl) { Line ('  ' + (Fmt-Size (Get-DirSize $x.Path)).PadLeft(10) + '  ' + $x.Path) }
  Line '提醒：Fix-UWP-Calculator.ps1 與它的紀錄資料夾在「證據」那一組，只會被移到封存資料夾，不會刪。'
  if ($ev.Count -gt 0 -and (Confirm-Step '把「證據與紀錄」移到封存資料夾')) {
    $n = 0; foreach ($x in $ev) { if (Move-Archive $x.Path) { $n++ } }
    Good ('已封存 ' + $n + ' 項'); [void]$script:Done.Add('封存證據與紀錄')
  } elseif ($ev.Count -gt 0) { [void]$script:Skipped.Add('封存證據與紀錄') }
  if ($tl.Count -gt 0 -and (Confirm-Step '刪除「下載的安裝檔與工具」')) {
    $n = 0
    foreach ($x in $tl) {
      if ((Split-Path -Leaf $x.Path) -eq 'MSStore Install') {
        $lg = Join-Path $x.Path 'Logs'
        if (Test-Path -LiteralPath $lg) { [void](Move-Archive $lg) }
      }
      try { Remove-Item -LiteralPath $x.Path -Recurse -Force -ErrorAction Stop; $n++ }
      catch { Fail ($x.Path + '：' + $_.Exception.Message) }
    }
    Good ('已刪除 ' + $n + ' 項'); [void]$script:Done.Add('刪除下載的工具')
  } elseif ($tl.Count -gt 0) { [void]$script:Skipped.Add('刪除下載的工具') }
}

function Sec-Frameworks {
  Sect '11.（選用）框架、計算機與 Store 資料夾：只清副作用（擁有者、多給的 Administrators 完全控制）'
  Line '保留不動：BUILTIN\Users 與 ALL APPLICATION PACKAGES 的讀取執行權限（修復本體）。'
  Line '這一段會碰到修復用的資料夾。留著不處理也可以，風險最小；想完全回原樣再做。'
  $targets = @(Get-TargetFolders)
  if ($targets.Count -eq 0) { Note '找不到目標套件'; return }
  $todo = @()
  foreach ($t in $targets) {
    $own = Get-OwnerSafe $t.Path
    $f = Get-AclFacts $t.Path
    $flag = @()
    if ($own -ne $t.WantOwner) { $flag += ('擁有者 ' + $own + ' → ' + $t.WantOwner) }
    if ($f.AdminExplicit) { $flag += '多了 Administrators 完全控制' }
    if (-not $f.HasUsers) { $flag += '缺 Users 讀取（修復需要，會補上）' }
    if (-not $f.HasAap) { $flag += '缺 ALL APPLICATION PACKAGES 讀取（修復需要，會補上）' }
    if ($flag.Count -gt 0) { Line ($t.Name + ' [' + $t.Arch + ']：' + ($flag -join '；')); $todo += $t }
    else { Line ($t.Name + ' [' + $t.Arch + ']：已是理想狀態') }
  }
  if ($todo.Count -eq 0) { Good '全部都已是理想狀態'; return }
  if (-not (Confirm-Step ('處理上面 ' + $todo.Count + ' 個資料夾（有備份、測試與自動還原）'))) { [void]$script:Skipped.Add('框架資料夾副作用'); return }
  $snaps = @()
  foreach ($t in $todo) {
    $tag = 'fw_' + (($t.Name + '_' + $t.Arch) -replace '[^A-Za-z0-9\.]+', '_')
    $snaps += [pscustomobject]@{ Path = $t.Path; File = (New-AclBackup $t.Path $tag $true); Owner = (Get-OwnerSafe $t.Path) }
  }
  Invoke-WithTest '框架與計算機資料夾副作用清理' {
    foreach ($t in $todo) {
      Line ('處理 ' + $t.Name + ' [' + $t.Arch + ']')
      [void](Run-Icacls @($t.Path, '/grant', '*S-1-5-32-545:(OI)(CI)(RX)', '/T', '/C'))
      [void](Run-Icacls @($t.Path, '/grant', '*S-1-15-2-1:(OI)(CI)(RX)', '/T', '/C'))
      $o = Run-Icacls @($t.Path, '/setowner', $t.WantOwner, '/T', '/C')
      Line ('  擁有者：' + (LastLine $o.Out))
      if ((Get-OwnerSafe $t.Path) -eq $t.WantOwner) {
        $x = Run-Icacls @($t.Path, '/remove:g', '*S-1-5-32-544', '/T', '/C')
        Line ('  移除多餘的 Administrators：' + (LastLine $x.Out))
      } else { Note '  擁有者沒改成功，保留 Administrators 權限，不繼續移除。' }
    }
  } {
    foreach ($s in $snaps) {
      Line ('還原 ' + $s.Path)
      & takeown.exe /f $s.Path /a /r /d y 2>&1 | Out-Null
      [void](Run-Icacls @($s.Path, '/grant', '*S-1-5-32-544:(OI)(CI)(F)', '/T', '/C'))
      $x = Run-Icacls @((Split-Path -Parent $s.Path), '/restore', $s.File, '/C')
      Line ('  DACL：' + (LastLine $x.Out))
      if ($s.Owner -and $s.Owner -ne '(讀不到)') { [void](Run-Icacls @($s.Path, '/setowner', $s.Owner, '/T', '/C')) }
    }
  }
}

function Sec-Misc {
  Sect '12. 其他（只報告）'
  $gs = @(Get-AppxPackage -Name 'Microsoft.GamingServices' -AllUsers -ErrorAction SilentlyContinue)
  if ($gs.Count -eq 0) { Note 'Gaming Services 目前沒有安裝。要玩 Xbox／Minecraft 之前，先從 Store 安裝 Gaming Services，再裝 Xbox 與 Minecraft。' }
  else { Good ('Gaming Services 已安裝（' + $gs[0].Version + '）') }
  foreach ($p in @('C:\$WINDOWS.~BT', 'C:\Windows.old')) {
    if (Test-Path -LiteralPath $p) { Note ($p + ' 存在（之前升級嘗試留下的）。用「磁碟清理 → 清理系統檔案」勾選「Windows 安裝暫存檔」可以清掉。') }
    else { Line ($p + '：不存在') }
  }
  Line 'MicrosoftStore_Fix 那支腳本做過什麼，看它的 Logs 資料夾（Downloads\MSStore Install\Logs；清理步驟會先把它移到封存資料夾）。'
  Line 'DCOM 設定警告視窗如果你按過「是」：只是多了幾筆 Intel／Realtek 的 AppID 紀錄，沒有影響，不用處理。'
}

# ================= 主流程 =================
Say ('收尾腳本  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  使用者 ' + $env:USERNAME) 'Cyan'
if ($Apply) { Say '模式：執行（每一段都會先問 Y/N；動權限的步驟有備份、測試與自動還原）' 'Yellow' }
else { Say '模式：只報告，不會改任何東西。確認內容沒問題後，加上 -Apply 再跑一次。' 'Yellow' }
Say ('備份與報告資料夾：' + $script:BackupDir)

if ($Apply) {
  Sect '0. 收尾前先確認修復是好的'
  if (-not (Test-Repair '收尾前')) {
    Fail '計算機或 Store 現在就打不開，請先不要收尾，把上面的訊息貼給 Claude。'
    exit 1
  }
} else { Sect '0. 修復狀態'; Line '（報告模式不做啟動測試）' }

Sec-HiveOwner
Sec-ExecPolicy
Sec-Services
Sec-Registry
Sec-Tools
Sec-ProgramDataPackages
Sec-WindowsAppsRoot
Sec-UsersAap
Sec-CalcBackups
Sec-Files
Sec-Frameworks
Sec-Misc

Sect '總結'
if ($Apply) {
  if ($script:Done.Count -gt 0)    { Good ('已完成：' + ($script:Done -join '；')) }
  if ($script:Skipped.Count -gt 0) { Note ('略過或未完成：' + ($script:Skipped -join '；')) }
  [void](Test-Repair '全部做完之後')
  Line ('備份資料夾（要整個還原用）：' + $script:BackupDir)
  Line ('還原指令：powershell -NoProfile -ExecutionPolicy Bypass -File .\Cleanup-AfterAppxFix.ps1 -Rollback "' + $script:BackupDir + '"')
  Line '建議：重開機後，再從開始功能表點一次計算機與 Store。'
} else {
  Line ('報告已存到：' + $script:LogFile)
  Line '把報告貼給 Claude 看過，沒問題再加上 -Apply 執行。'
}
