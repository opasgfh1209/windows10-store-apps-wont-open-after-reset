#requires -Version 5.1
<#
.SYNOPSIS
  啟動幾個內建 App，用事件 5961 與程序判斷是否成功。不改任何系統設定。

.DESCRIPTION
  用法（你自己帳號開的 PowerShell，不要用 SYSTEM 視窗）：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-UwpApps.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-UwpApps.ps1 -WaitSeconds 12

  判斷方式：
    成功   ：程序在執行，而且沒有該 App 的 5961 啟動失敗紀錄
    失敗   ：有該 App 的 5961 紀錄
    不確定 ：沒有程序，也沒有 5961（可能啟動太慢，或程序名稱無法比對）
  5961 只有在啟動失敗時才會寫入，所以比肉眼看視窗可靠。
  測試完會關閉它啟動的 App 程序。
#>
[CmdletBinding()]
param(
  [int]$WaitSeconds = 8
)

$ErrorActionPreference = 'Continue'
$ident = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($ident.IsSystem) {
  Write-Host '這是 SYSTEM 視窗，SYSTEM 啟動不了你的 UWP App，測試沒有意義。請改用你自己的帳號。' -ForegroundColor Red; exit 1
}

$targets = @(
  @{ N = '計算機';          Id = 'Microsoft.WindowsCalculator' },
  @{ N = 'Microsoft Store'; Id = 'Microsoft.WindowsStore' },
  @{ N = '相片';            Id = 'Microsoft.Windows.Photos' },
  @{ N = '鬧鐘';            Id = 'Microsoft.WindowsAlarms' },
  @{ N = '便利貼';          Id = 'Microsoft.MicrosoftStickyNotes' },
  @{ N = '相機';            Id = 'Microsoft.WindowsCamera' },
  @{ N = '螢幕剪取';        Id = 'Microsoft.ScreenSketch' },
  @{ N = '錄音機';          Id = 'Microsoft.WindowsSoundRecorder' }
)

function Get-AppUserModelId {
  param($Package)
  $appId = 'App'
  try {
    $mf = Join-Path ([string]$Package.InstallLocation) 'AppxManifest.xml'
    $x = [xml](Get-Content -LiteralPath $mf -Raw -ErrorAction Stop)
    $first = @($x.Package.Applications.Application) | Select-Object -First 1
    if ($first -and $first.Id) { $appId = [string]$first.Id }
  } catch {}
  return ([string]$Package.PackageFamilyName + '!' + $appId)
}

Write-Host ('{0,-18} {1,-8} {2}' -f 'App', '結果', '說明') -ForegroundColor Cyan
foreach ($t in $targets) {
  $pkg = @(Get-AppxPackage -Name $t.Id -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework }) | Select-Object -First 1
  if (-not $pkg) { Write-Host ('{0,-18} {1,-8} {2}' -f $t.N, '略過', '沒有安裝') -ForegroundColor DarkGray; continue }
  $aumid = Get-AppUserModelId $pkg
  $loc   = [string]$pkg.InstallLocation
  $t0 = Get-Date
  try { Start-Process ('shell:AppsFolder\' + $aumid) -ErrorAction Stop }
  catch { Write-Host ('{0,-18} {1,-8} {2}' -f $t.N, '失敗', ('啟動要求被拒：' + $_.Exception.Message)) -ForegroundColor Red; continue }
  Start-Sleep -Seconds $WaitSeconds

  $procs = @()
  try {
    $procs = @(Get-Process -ErrorAction SilentlyContinue |
               Where-Object { $_.Path -and $_.Path.StartsWith($loc, [System.StringComparison]::OrdinalIgnoreCase) })
  } catch {}
  $errs = @(Get-WinEvent -LogName 'Microsoft-Windows-TWinUI/Operational' -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -eq 5961 -and $_.TimeCreated -ge $t0 -and $_.Message -like ('*' + $pkg.Name + '*') })

  if ($errs.Count -gt 0) {
    Write-Host ('{0,-18} {1,-8} {2}' -f $t.N, '失敗', ('5961 啟動失敗紀錄 ' + $errs.Count + ' 筆')) -ForegroundColor Red
    Write-Host ('                           ' + (($errs[0].Message -replace '\s+', ' ').Trim())) -ForegroundColor DarkGray
  } elseif ($procs.Count -gt 0) {
    Write-Host ('{0,-18} {1,-8} {2}' -f $t.N, '成功', ('程序 ' + (($procs | ForEach-Object { $_.ProcessName + ' (' + $_.Id + ')' }) -join ', '))) -ForegroundColor Green
  } else {
    Write-Host ('{0,-18} {1,-8} {2}' -f $t.N, '不確定', '沒有程序，也沒有 5961。可以加大 -WaitSeconds 再試') -ForegroundColor Yellow
  }
  foreach ($pr in $procs) { try { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue } catch {} }
}
Write-Host ''
Write-Host '提醒：鬧鐘、便利貼、相機若顯示失敗，且 5961 的 ErrorCode 是 -2144927141，見 README 4.4。' -ForegroundColor Gray
