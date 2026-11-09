#requires -Version 5.1
<#
.SYNOPSIS
  唯讀。檢查「框架套件資料夾」是否缺少 BUILTIN\Users 的權限條目，並彙整相關事件。

.DESCRIPTION
  不修改任何東西。對應 README 第三節的檢查 4、5、6。

  用法（你自己帳號開的「系統管理員」Windows PowerShell，64 位元，不要用 SYSTEM／PsExec 視窗）：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Detect-FrameworkFolderAcl.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Detect-FrameworkFolderAcl.ps1 -Days 7

  -Days      往回看幾天的事件，預設 3。
  -NoSanitize  關閉去識別。預設會把輸出檔中的電腦名稱、使用者名稱、SID 取代掉，方便貼到 issue。
               這支腳本本來就不蒐集 IP 位址、MAC 位址、序號或裝置識別碼。
  -OutFile   輸出檔路徑，預設放在桌面。

  這個腳本只是「判斷線索」，不是診斷結論。決定性的證據是 Process Monitor（見 README 4.1）。
  尚未在其他機器驗證。
#>
[CmdletBinding()]
param(
  [int]$Days = 3,
  [switch]$NoSanitize,
  [string]$OutFile = ''
)

$ErrorActionPreference = 'Continue'
$script:Report = New-Object System.Collections.ArrayList

function Say {
  param([string]$Text)
  Write-Host $Text
  [void]$script:Report.Add($Text)
}
function Sect { param([string]$Text) Say ''; Say ('==== ' + $Text + ' ====') }

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
  Write-Host '這是 32 位元的 PowerShell。請改開 64 位元的 Windows PowerShell。' -ForegroundColor Red; exit 1
}

# ---------- 共用函式 ----------
function Run-Icacls {
  param([string[]]$IcaclsArgs)
  $out = @(& icacls.exe @IcaclsArgs 2>&1 | ForEach-Object { [string]$_ })
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
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
    HasUsers      = (($txt -match 'BUILTIN\\Users:') -or ($txt -match 'S-1-5-32-545:'))
    HasAap        = (($txt -match 'ALL APPLICATION PACKAGES:') -or ($txt -match 'S-1-15-2-1:'))
    AdminExplicit = $adminExplicit
    Raw           = $lines
  }
}
function Sanitize-Text {
  param([string]$Text)
  $s = $Text
  if ($env:COMPUTERNAME) { $s = $s -replace ('\b' + [regex]::Escape($env:COMPUTERNAME) + '\b'), '<COMPUTER>' }
  if ($env:USERNAME)     { $s = $s -replace ('\b' + [regex]::Escape($env:USERNAME) + '\b'), '<USER>' }
  $s = $s -replace 'S-1-5-21-\d+-\d+-\d+', 'S-1-5-21-<…>'
  return $s
}
function Short {
  param([string]$Text, [int]$Max = 220)
  $t = ($Text -replace '\s+', ' ').Trim()
  if ($t.Length -gt $Max) { return $t.Substring(0, $Max) + '…' }
  return $t
}

Say ('Detect-FrameworkFolderAcl  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

# ---------- A. 環境 ----------
Sect 'A. 環境'
$os  = Get-CimInstance Win32_OperatingSystem
$cv  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
Say ('系統：' + $os.Caption + '  build ' + $os.BuildNumber + '.' + $cv.UBR)
Say ('系統安裝（或重設）時間：' + $os.InstallDate)
Say ('目前身分：' + $ident.Name + '    64 位元：' + [Environment]::Is64BitProcess)

# ---------- B. 事件 ----------
Sect ('B. 事件（最近 ' + $Days + ' 天）')
$from = (Get-Date).AddDays(-$Days)
$ev57 = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppModel-Runtime/Admin'; Id = 57; StartTime = $from } -ErrorAction SilentlyContinue)
$ev61 = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppModel-Runtime/Admin'; Id = 61; StartTime = $from } -ErrorAction SilentlyContinue)
Say ('AppModel-Runtime 事件 57（信任狀態失敗）：' + $ev57.Count + ' 筆')
Say ('AppModel-Runtime 事件 61（完整性檢查失敗）：' + $ev61.Count + ' 筆')
foreach ($e in @($ev57 | Select-Object -First 3)) { Say ('  57  ' + $e.TimeCreated + '  ' + (Short $e.Message)) }
foreach ($e in @($ev61 | Select-Object -First 2)) { Say ('  61  ' + $e.TimeCreated + '  ' + (Short $e.Message)) }

$pkgPattern = '[A-Za-z0-9\.\-]+_\d+(?:\.\d+)+_(?:x64|x86|arm64|neutral)_[A-Za-z0-9~\-]*_[a-z0-9]+'
$named = @{}
foreach ($e in $ev57) {
  foreach ($m in [regex]::Matches([string]$e.Message, $pkgPattern)) {
    if ($named.ContainsKey($m.Value)) { $named[$m.Value]++ } else { $named[$m.Value] = 1 }
  }
}
if ($named.Count -gt 0) {
  Say '事件 57 點名的套件：'
  foreach ($kv in ($named.GetEnumerator() | Sort-Object Value -Descending)) { Say ('  ' + $kv.Value + ' 次  ' + $kv.Key) }
}

$ev5961 = @(Get-WinEvent -LogName 'Microsoft-Windows-TWinUI/Operational' -MaxEvents 1000 -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -eq 5961 -and $_.TimeCreated -ge $from })
Say ('TWinUI 事件 5961（啟用失敗）：' + $ev5961.Count + ' 筆')
$codes = @{}
foreach ($e in $ev5961) {
  try {
    $x = [xml]$e.ToXml()
    $c = [string](($x.Event.EventData.Data | Where-Object { $_.Name -eq 'ErrorCode' }).'#text')
  } catch { $c = '(讀不到)' }
  if ($codes.ContainsKey($c)) { $codes[$c]++ } else { $codes[$c] = 1 }
}
foreach ($kv in ($codes.GetEnumerator() | Sort-Object Value -Descending)) {
  $hex = ''
  $n = 0
  if ([int]::TryParse($kv.Key, [ref]$n)) { $hex = '0x' + ([uint32]([int64]$n -band 0xFFFFFFFFL)).ToString('X8') }
  Say ('  ErrorCode ' + $kv.Key + '  ' + $hex + '  ×' + $kv.Value)
}

# ---------- C. 對照：一般 App ----------
Sect 'C. 對照：能正常啟動的一般 App 資料夾'
$refPkg = $null
foreach ($n in @('Microsoft.WindowsCalculator', 'Microsoft.MicrosoftEdge.Stable', 'Microsoft.WindowsStore', 'Microsoft.Windows.Photos')) {
  $p = @(Get-AppxPackage -Name $n -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework }) | Select-Object -First 1
  if ($p -and $p.InstallLocation -and (Test-Path -LiteralPath $p.InstallLocation)) { $refPkg = $p; break }
}
if ($refPkg) {
  $rf = Get-AclFacts $refPkg.InstallLocation
  Say ($refPkg.Name + '：有 BUILTIN\Users=' + $rf.HasUsers + '，有 AAP=' + $rf.HasAap + '，擁有者 ' + (Get-OwnerSafe $refPkg.InstallLocation))
  Say '  （這是 App 本身，不是框架。在我們的機器上，它有 Users 條目。）'
} else { Say '找不到可對照的一般 App。' }

# ---------- D. 框架資料夾 ----------
Sect 'D. 框架套件資料夾'
$fw = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework })
$seen = @{}
$rows = New-Object System.Collections.ArrayList
foreach ($p in $fw) {
  $loc = [string]$p.InstallLocation
  if (-not $loc -or $seen.ContainsKey($loc) -or -not (Test-Path -LiteralPath $loc)) { continue }
  $seen[$loc] = $true
  $f = Get-AclFacts $loc
  $states = @($p.PackageUserInformation | ForEach-Object { [string]$_ })
  $installed = @($states | Where-Object { $_ -match 'Installed' }).Count
  [void]$rows.Add([pscustomobject]@{
    Name = $p.Name; Arch = [string]$p.Architecture; Version = [string]$p.Version; Path = $loc
    HasUsers = $f.HasUsers; HasAap = $f.HasAap; Owner = (Get-OwnerSafe $loc); InstalledUsers = $installed
  })
}
$missingUsers = @($rows | Where-Object { -not $_.HasUsers })
$missingAap   = @($rows | Where-Object { -not $_.HasAap })
Say ('框架資料夾共 ' + $rows.Count + ' 個；缺 BUILTIN\Users：' + $missingUsers.Count + ' 個；缺 AAP：' + $missingAap.Count + ' 個')
Say ''
Say ('{0,-40} {1,-6} {2,-6} {3,-6} {4}' -f '名稱', '架構', 'Users', 'AAP', '擁有者')
foreach ($r in ($rows | Sort-Object Name, Arch)) {
  Say ('{0,-40} {1,-6} {2,-6} {3,-6} {4}' -f $r.Name, $r.Arch, $r.HasUsers, $r.HasAap, $r.Owner)
}

# ---------- E. 判斷線索 ----------
Sect 'E. 判斷線索（不是診斷結論）'
$hit57Fw = $false
foreach ($k in $named.Keys) {
  foreach ($r in $missingUsers) {
    if ($k -like ($r.Name + '_*')) { $hit57Fw = $true }
  }
}
if ($ev57.Count -gt 0 -and $hit57Fw) {
  Say '與主因 A 吻合：事件 57 點名的框架，資料夾沒有 BUILTIN\Users。請用 Process Monitor 確認（README 4.1），再照 README 4.2 處理。'
} elseif ($missingUsers.Count -gt 0 -and $ev57.Count -eq 0) {
  Say ('有 ' + $missingUsers.Count + ' 個框架資料夾缺 BUILTIN\Users，但最近 ' + $Days + ' 天沒有事件 57。這可能是正常狀態（我們沒有健康機器可對照），也可能問題尚未發生。')
} elseif ($ev57.Count -gt 0) {
  Say '有事件 57，但點名的框架資料夾並不缺 BUILTIN\Users。這和我們的案例不同，請開 issue 並附上這份輸出。'
} else {
  Say '沒有看到事件 57／61。'
}
if ($codes.ContainsKey('-2144927141')) {
  Say '5961 出現 ErrorCode -2144927141（0x8027025B，「應用程式未啟動」）：可能是主因 B，見 README 4.4。'
}
Say ''
Say '注意：「缺 BUILTIN\Users」不一定等於問題。我們沒有找到健康的 Windows 10 機器上框架資料夾的對照輸出。如果你有，歡迎貼上來。'

# ---------- 輸出檔 ----------
if (-not $OutFile) {
  $desk = [Environment]::GetFolderPath('Desktop')
  $OutFile = Join-Path $desk ('FrameworkAcl_Report_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
}
$text = ($script:Report -join "`r`n")
if (-not $NoSanitize) { $text = Sanitize-Text $text }
Set-Content -LiteralPath $OutFile -Value $text -Encoding UTF8
Write-Host ''
Write-Host ('報告已存到：' + $OutFile) -ForegroundColor Cyan
if (-not $NoSanitize) { Write-Host '（輸出檔已去識別：電腦名稱、使用者名稱、SID。貼出前請再人工檢查一次。）' -ForegroundColor Cyan }
else { Write-Host '（輸出檔沒有去識別。貼出前請自行處理電腦名稱、使用者名稱、SID。）' -ForegroundColor Yellow }
