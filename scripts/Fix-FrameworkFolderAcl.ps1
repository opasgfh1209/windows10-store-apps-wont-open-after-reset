#requires -Version 5.1
<#
.SYNOPSIS
  對「缺少 BUILTIN\Users 權限條目的框架套件資料夾」補上讀取與執行。預設只報告。

.DESCRIPTION
  這是 README 4.2 的自動化版本。每個資料夾依序：記下擁有者 → takeown → 備份權限 → 授權。
  只處理框架套件（IsFramework）的資料夾；不碰 WindowsApps 根目錄、不碰 App 本身的資料夾。

  預設只報告，不改任何東西。加 -Apply 才會執行，而且每個資料夾都先問 Y/N。
  備份與日誌放在「文件\AppX_Framework_ACL_<時間>」。

  用法（你自己帳號開的「系統管理員」Windows PowerShell，64 位元，不要用 SYSTEM／PsExec 視窗）：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Fix-FrameworkFolderAcl.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Fix-FrameworkFolderAcl.ps1 -Apply
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Fix-FrameworkFolderAcl.ps1 -Apply -Only 'Microsoft.UI.Xaml.2.8','Microsoft.VCLibs.*'
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Fix-FrameworkFolderAcl.ps1 -Rollback "C:\Users\<USER>\Documents\AppX_Framework_ACL_<時間>"

  -Only        只處理名稱符合的框架（可用萬用字元）
  -IncludeAap  同時補 ALL APPLICATION PACKAGES 的讀取執行（README 4.4 的 B3，主因 B 才需要）
  -Yes         不逐一詢問（不建議）
  -Rollback    依備份資料夾裡的 manifest.csv 還原

  限制：
  - 尚未在其他機器驗證。我們只在一台機器上，用等價的手動指令成功過。
  - 修完不會自動測試。請用 Test-UwpApps.ps1 或開始功能表測試。
  - 修好 A 之後如果還是失敗，請再抓一次 Process Monitor（README 4.1），可能還有別的框架被拒。
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [string[]]$Only = @(),
  [switch]$IncludeAap,
  [switch]$Yes,
  [string]$Rollback = ''
)

$ErrorActionPreference = 'Continue'
$script:LogFile   = $null
$script:BackupDir = $null
$script:Manifest  = New-Object System.Collections.ArrayList

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
  Write-Host '這是 32 位元的 PowerShell。請改開 64 位元的 Windows PowerShell。' -ForegroundColor Red; exit 1
}

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
  $txt = ($r.Out -join "`n")
  return [pscustomobject]@{
    HasUsers = (($txt -match 'BUILTIN\\Users:') -or ($txt -match 'S-1-5-32-545:'))
    HasAap   = (($txt -match 'ALL APPLICATION PACKAGES:') -or ($txt -match 'S-1-15-2-1:'))
  }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$docs  = [Environment]::GetFolderPath('MyDocuments')
$script:BackupDir = Join-Path $docs ('AppX_Framework_ACL_' + $stamp)
New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
$script:LogFile = Join-Path $script:BackupDir 'log.txt'

# ---------- 還原模式 ----------
if ($Rollback) {
  Sect ('還原：' + $Rollback)
  $mf = Join-Path $Rollback 'manifest.csv'
  if (-not (Test-Path -LiteralPath $mf)) { Fail '找不到 manifest.csv，這不是本腳本建立的備份資料夾。'; exit 1 }
  foreach ($r in @(Import-Csv -LiteralPath $mf -Encoding UTF8)) {
    if (-not (Test-Path -LiteralPath $r.AclFile)) { Note ('缺少備份檔：' + $r.AclFile); continue }
    Line ('還原：' + $r.Path)
    & takeown.exe /f $r.Path /a /r /d y 2>&1 | Out-Null
    $x = Run-Icacls @($r.Parent, '/restore', $r.AclFile, '/C')
    Line ('  DACL：' + (LastLine $x.Out))
    if ($r.OwnerBefore -and $r.OwnerBefore -ne '(讀不到)') {
      $y = Run-Icacls @($r.Path, '/setowner', $r.OwnerBefore, '/T', '/C')
      Line ('  擁有者：' + (LastLine $y.Out))
    }
  }
  Good '還原完成。BUILTIN\Users 條目會消失，原本的問題會回來。'
  exit 0
}

# ---------- 找出目標 ----------
function Get-Targets {
  $seen = @{}
  $list = New-Object System.Collections.ArrayList
  foreach ($p in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework })) {
    $loc = [string]$p.InstallLocation
    if (-not $loc -or $seen.ContainsKey($loc) -or -not (Test-Path -LiteralPath $loc)) { continue }
    if ($Only.Count -gt 0) {
      $match = $false
      foreach ($pat in $Only) { if ($p.Name -like $pat) { $match = $true } }
      if (-not $match) { continue }
    }
    $seen[$loc] = $true
    $f = Get-AclFacts $loc
    $needUsers = (-not $f.HasUsers)
    $needAap   = ($IncludeAap -and -not $f.HasAap)
    [void]$list.Add([pscustomobject]@{
      Name = $p.Name; Arch = [string]$p.Architecture; FullName = [string]$p.PackageFullName; Path = $loc
      HasUsers = $f.HasUsers; HasAap = $f.HasAap; NeedUsers = $needUsers; NeedAap = $needAap
    })
  }
  return $list.ToArray()
}

Say ('Fix-FrameworkFolderAcl  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if ($Apply) { Say '模式：執行（每個資料夾都會先問 Y/N）' 'Yellow' }
else { Say '模式：只報告，不會改任何東西。確認內容沒問題後，加上 -Apply 再跑一次。' 'Yellow' }
Say ('備份與日誌資料夾：' + $script:BackupDir)

Sect '1. 掃描框架套件資料夾'
$all  = @(Get-Targets)
$todo = @($all | Where-Object { $_.NeedUsers -or $_.NeedAap })
Say ('{0,-40} {1,-6} {2,-6} {3,-6} {4}' -f '名稱', '架構', 'Users', 'AAP', '需要處理')
foreach ($t in ($all | Sort-Object Name, Arch)) {
  $need = ''
  if ($t.NeedUsers) { $need += '補 Users ' }
  if ($t.NeedAap)   { $need += '補 AAP' }
  if (-not $need) { $need = '-' }
  Say ('{0,-40} {1,-6} {2,-6} {3,-6} {4}' -f $t.Name, $t.Arch, $t.HasUsers, $t.HasAap, $need)
}
Say ''
Say ('共 ' + $all.Count + ' 個框架資料夾；需要處理 ' + $todo.Count + ' 個。')
if ($todo.Count -eq 0) { Good '沒有需要處理的資料夾。'; exit 0 }
Note '這個腳本只補「讀取與執行」，只處理框架資料夾。它會先 takeown（擁有者改成 Administrators 群組），並把原本的擁有者記在 manifest.csv。'
Note '缺 BUILTIN\Users 不一定等於你的問題。建議先用 Procmon 或事件 57 確認被拒的是哪些（README 4.1）；可以用 -Only 只處理那幾個。'

if (-not $Apply) {
  Line ''
  Line '報告模式結束。要執行請加 -Apply。'
  exit 0
}

# ---------- 執行 ----------
Sect '2. 逐一處理'
$done = 0; $skip = 0; $bad = 0
foreach ($t in $todo) {
  Say ''
  Say ('-- ' + $t.FullName) 'Cyan'
  Line ('路徑：' + $t.Path)
  if (-not (Confirm-Step ('處理 ' + $t.Name + ' [' + $t.Arch + ']'))) { $skip++; continue }

  $owner = Get-OwnerSafe $t.Path
  Line ('1) 原本的擁有者：' + $owner)

  $tk = @(& takeown.exe /f $t.Path /a /r /d y 2>&1 | ForEach-Object { [string]$_ })
  Line ('2) takeown：' + (LastLine $tk))

  $tag = ($t.FullName -replace '[^A-Za-z0-9\.]', '_')
  $aclFile = Join-Path $script:BackupDir ('acl_' + $tag + '.txt')
  $sv = Run-Icacls @($t.Path, '/save', $aclFile, '/T', '/C')
  Line ('3) 備份權限：' + (LastLine $sv.Out))
  [void]$script:Manifest.Add([pscustomobject]@{
    Path = $t.Path; Parent = (Split-Path -Parent $t.Path); AclFile = $aclFile; OwnerBefore = $owner })
  $script:Manifest | Export-Csv -LiteralPath (Join-Path $script:BackupDir 'manifest.csv') -NoTypeInformation -Encoding UTF8

  if ($t.NeedUsers) {
    $g = Run-Icacls @($t.Path, '/grant', '*S-1-5-32-545:(OI)(CI)(RX)', '/T', '/C')
    Line ('4) 授權 Users：' + (LastLine $g.Out))
  }
  if ($t.NeedAap) {
    $g2 = Run-Icacls @($t.Path, '/grant', '*S-1-15-2-1:(OI)(CI)(RX)', '/T', '/C')
    Line ('4) 授權 AAP：' + (LastLine $g2.Out))
  }

  $after = Get-AclFacts $t.Path
  if ((-not $t.NeedUsers -or $after.HasUsers) -and (-not $t.NeedAap -or $after.HasAap)) { Good '條目已加上'; $done++ }
  else { Fail '授權後仍檢查不到條目，請看日誌。'; $bad++ }
}

Sect '3. 總結'
Line ('完成 ' + $done + ' 個；略過 ' + $skip + ' 個；失敗 ' + $bad + ' 個。')
Line ('備份與日誌：' + $script:BackupDir)
Line '下一步：用 Test-UwpApps.ps1 或從開始功能表測試。'
Line '如果還是失敗：再抓一次 Process Monitor（README 4.1），可能還有別的框架被拒。'
Line ('要還原：powershell -NoProfile -ExecutionPolicy Bypass -File .\Fix-FrameworkFolderAcl.ps1 -Rollback "' + $script:BackupDir + '"')
