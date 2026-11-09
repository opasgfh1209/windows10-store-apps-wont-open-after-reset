# 06 解決步驟（逐步版）

這一份是 [README 第四節](../README.md#四怎麼解決)的完整版：每一步講清楚**做什麼、為什麼、預期看到什麼、失敗時怎麼辦**。

**範圍與限制**

- 這些步驟在**一台機器**上驗證過。
- 錯誤 A 的指令是我們實際執行並成功的。錯誤 B 的指令是依修復腳本（全文收錄在 [`scripts/Fix-UWP-Calculator.ps1`](../scripts/Fix-UWP-Calculator.ps1)）的流程重寫的，不是逐字複製。
- 本章的備份順序（先記擁有者、再 `takeown`、再備份、最後授權）是依權限機制推得的，在預設權限的機器上沒有逐字驗證過。

## 0. 開始之前

### 0.1 開對視窗

開始功能表輸入 `PowerShell` → 右鍵「Windows PowerShell」→「以系統管理員身分執行」。

```powershell
whoami                              # 應該是 <電腦>\<你的帳號>
[Environment]::Is64BitProcess       # 應該是 True
```

- 回 `nt authority\system`：你在 SYSTEM 視窗，會讓測試失去意義。關掉重開。
- `Is64BitProcess` 是 False：你開的是 32 位元的 PowerShell（名稱裡有 `(x86)`），路徑與登錄會被導向。重開 64 位元的。

### 0.2 風險與底線

- 你要改的是 `C:\Program Files\WindowsApps` 底下的資料夾權限。
- 一次只改被指到的資料夾。
- **不要**對整個 `WindowsApps` 做 `takeown /r`、`icacls /T`、`icacls /reset`、`/setowner`。
- 修復只在一台機器驗證過。

### 0.3 建立還原點（選用）

```powershell
Checkpoint-Computer -Description "before-framework-acl" -RestorePointType MODIFY_SETTINGS
```

「系統保護」沒開時會失敗，不影響後面。還原點不包含 `WindowsApps` 的權限，它只是額外的保險。

## 1. 找出要修的資料夾

### 1.1 方法 1：事件 57

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-AppModel-Runtime/Admin' -MaxEvents 200 |
  Where-Object { $_.Id -eq 57 } | Select-Object -First 3 TimeCreated, Message | Format-List
```

訊息裡的套件完整名稱（例如 `Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe`）就是**第一個**要修的。事件 57 只會點名第一個被拒的，後面的還沒被檢查到。

### 1.2 方法 2：偵測腳本

[`scripts/Detect-FrameworkFolderAcl.ps1`](../scripts/Detect-FrameworkFolderAcl.ps1)。唯讀。它列出所有框架資料夾，標出沒有 `BUILTIN\Users` 的，並顯示相關事件的次數。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Detect-FrameworkFolderAcl.ps1
```

### 1.3 方法 3：Process Monitor（最準）

1. 從 Microsoft Sysinternals 下載 Process Monitor，解壓縮後用**你自己的帳號**以系統管理員身分執行 `Procmon64.exe`。
2. 第一次執行會問 EULA，按同意。
3. 按 `Ctrl+L` 開篩選器：
   - 第一格選 `Result`，第二格選 `is`，第三格輸入 `ACCESS DENIED`，第四格選 `Include`；
   - 按「Add」，再按「OK」。
   - **不要加任何 `Process Name` 的條件。**
4. 按 `Ctrl+X` 清空畫面。確認左上角放大鏡圖示是開著的（`Ctrl+E` 切換擷取）。
5. 從開始功能表點壞掉的 App。閃退後馬上再點一次，總共兩到三次。
6. 按 `Ctrl+E` 停止擷取。
7. 看畫面上的紀錄。找 `Process Name` 是 `svchost.exe`、`Path` 在 `C:\Program Files\WindowsApps\` 底下的列。這個 `Path` 就是下一個要修的資料夾。
8. 要存下來分析：檔案 → 儲存 → 格式 `CSV`，範圍選「目前顯示的事件」。

**預期看到：** `Operation` 是 `CreateFile`，`Result` 是 `ACCESS DENIED`，`Detail` 欄有 `Impersonating: <電腦>\<使用者>`。

**常見問題：**

| 情況 | 怎麼辦 |
|---|---|
| 畫面完全空白 | 你的篩選或擷取沒開；確認 `Ctrl+E` 的圖示，確認有真的點 App |
| 只有 `explorer.exe` 的紀錄，路徑在登錄 | 那是雜訊，不是我們要的 |
| 一次擷取太久，檔案很大 | 開始擷取後 20 到 30 秒內做完操作，馬上停止 |

分析 CSV 的小工具：

```python
import csv, collections
rows = list(csv.DictReader(open('Logfile.CSV', encoding='utf-8-sig')))
den = [r for r in rows if r['Result'] == 'ACCESS DENIED']
for (proc, path), n in collections.Counter((r['Process Name'], r['Path']) for r in den).most_common(30):
    print(n, proc, path)
```

### 1.4 把套件名稱換成資料夾路徑

```powershell
Get-AppxPackage -AllUsers -Name Microsoft.UI.Xaml.2.8 | Select-Object Architecture, InstallLocation
```

x64 與 x86 各有一個資料夾，兩個都要處理。

## 2. 修復錯誤 A

### 2.1 單一資料夾：四步

以下用 `<資料夾>` 代表 1.4 取得的完整路徑。

**步驟 1：記下擁有者**（`takeown` 之前做）

```powershell
(Get-Acl -LiteralPath "<資料夾>").Owner
```

預期：`NT SERVICE\TrustedInstaller` 或 `NT AUTHORITY\SYSTEM`。寫下來，還原要用。

**步驟 2：取得擁有權**

```cmd
takeown /f "<資料夾>" /a /r /d y
```

| 參數 | 意思 |
|---|---|
| `/a` | 把擁有者設成 Administrators 群組（不是目前使用者） |
| `/r` | 包含所有子資料夾與檔案 |
| `/d y` | 遇到沒有權限列出的資料夾，預設回答「是」 |

預期：每個項目一行「成功…擁有」。

**這一步不能省。** 這些資料夾的擁有者是 TrustedInstaller 或 SYSTEM，系統管理員沒有改權限的資格。沒有先做，步驟 4 幾乎全部回「存取被拒」。這是我們第一次嘗試失敗的原因。

**步驟 3：備份權限**（`takeown` 之後做，否則大部分檔案讀不到權限）

```cmd
icacls "<資料夾>" /save "%USERPROFILE%\acl_<名稱>.txt" /T /C
```

預期最後一行：`已順利處理 N 個檔案; 0 個檔案處理失敗`。

**步驟 4：給 `BUILTIN\Users` 讀取與執行**

```cmd
icacls "<資料夾>" /grant "*S-1-5-32-545:(OI)(CI)(RX)" /T /C
```

| 部分 | 意思 |
|---|---|
| `*S-1-5-32-545` | `BUILTIN\Users`。前面的星號表示後面是 SID。用 SID 中英文系統都適用 |
| `(OI)` | 底下的檔案繼承 |
| `(CI)` | 底下的資料夾繼承 |
| `(RX)` | 讀取與執行 |
| `/T` | 套用到所有子項目 |
| `/C` | 遇到錯誤繼續 |

**成功的樣子**（我們的輸出，最後一行）：

```
已順利處理 16 個檔案; 0 個檔案處理失敗   (Xaml 2.8 x64)
已順利處理 11 個檔案; 0 個檔案處理失敗   (NET Native Framework 2.2 x64)
已順利處理 12 個檔案; 0 個檔案處理失敗   (NET Native Runtime 2.2 x64)
已順利處理 21 個檔案; 0 個檔案處理失敗   (VCLibs 140 x64)
已順利處理 35 個檔案; 0 個檔案處理失敗   (VCLibs UWPDesktop 14 x64)
```

**確認條目有加上：**

```cmd
icacls "<資料夾>" | findstr /i "Users"
```

應該看得到 `BUILTIN\Users:(OI)(CI)(RX)`。

### 2.2 多個資料夾：迴圈版

把名稱換成你的清單。這是我們在 19:3x 成功執行的迴圈，加上擁有者記錄與備份：

```powershell
$names = 'Microsoft.UI.Xaml.2.8','Microsoft.NET.Native.Framework.2.2','Microsoft.NET.Native.Runtime.2.2',
         'Microsoft.VCLibs.140.00','Microsoft.VCLibs.140.00.UWPDesktop'
$bk = Join-Path $env:USERPROFILE ('AppX_ACL_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $bk | Out-Null
foreach ($n in $names) {
  foreach ($p in @(Get-AppxPackage -AllUsers -Name $n)) {
    $path = [string]$p.InstallLocation
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
    $tag = $p.PackageFullName -replace '[^A-Za-z0-9\.]', '_'
    Write-Host ('處理 ' + $p.PackageFullName) -ForegroundColor Cyan
    (Get-Acl -LiteralPath $path).Owner | Out-File (Join-Path $bk ($tag + '.owner.txt'))
    takeown /f $path /a /r /d y | Out-Null
    icacls $path /save (Join-Path $bk ($tag + '.acl.txt')) /T /C | Select-Object -Last 1
    icacls $path /grant '*S-1-5-32-545:(OI)(CI)(RX)' /T /C | Select-Object -Last 1
  }
}
Write-Host ('備份在：' + $bk)
```

### 2.3 用腳本

[`scripts/Fix-FrameworkFolderAcl.ps1`](../scripts/Fix-FrameworkFolderAcl.ps1)：先報告、再逐一詢問，自動記錄擁有者、備份、寫日誌，並在最後測試。**尚未在其他機器驗證。**

### 2.4 這一步常見的失敗

| 訊息 | 意思 | 做法 |
|---|---|---|
| `icacls` 對大部分項目回「存取被拒」 | 你還不是擁有者 | 先做步驟 2 |
| `takeown` 回「找不到指定的路徑」 | 路徑打錯，或你在 32 位元視窗 | 用 1.4 取得路徑；確認 `Is64BitProcess` |
| `icacls /save` 回「存取被拒」 | 你還沒 `takeown`，讀不到檔案的權限 | 先做步驟 2 |
| 輸出「n 個檔案處理失敗」且 n 很大 | 有檔案被程序占用或權限結構特殊 | 把失敗的路徑記下；關掉相關 App 重試 |

## 3. 驗證 A

1. 從**自己帳號**的開始功能表點 Store。
2. 或：

```powershell
Start-Process 'shell:AppsFolder\Microsoft.WindowsStore_8wekyb3d8bbwe!App'
Start-Sleep 8
Get-Process WinStore.App -ErrorAction SilentlyContinue | Select-Object Name, Id, StartTime
```

3. 看事件：

```powershell
$t0 = (Get-Date).AddMinutes(-5)
Get-WinEvent -LogName 'Microsoft-Windows-AppModel-Runtime/Admin' | Where-Object { $_.TimeCreated -ge $t0 -and $_.Id -in 57,61 }
```

**成功：** `WinStore.App` 程序存在，且 57、61 沒有新紀錄。我們的輸出：

```
Name         Id StartTime
----         -- ---------
WinStore.App 14104 2026/10/25 下午 07:53:35
```

**失敗：** 再抓一次 Procmon（1.3）。我們的經驗是補一個、下一個冒出來。

## 4. 修復錯誤 B

只有在「A 修好、Store 能開、卻還有 App 打不開、5961 的錯誤碼是 `-2144927141`」時才做。

**想知道哪一步是必要的，請一次只做一步，每步之後測試**（見 4.7）。我們沒有這樣做過，所以不知道。

### 4.1 步驟 B1：確認打不開的是 .NET Native 的 App

```powershell
$p = Get-AppxPackage Microsoft.WindowsCalculator
([xml](Get-Content (Join-Path $p.InstallLocation 'AppxManifest.xml') -Raw)).Package.Dependencies.PackageDependency |
  Select-Object Name, MinVersion
```

看有沒有 `Microsoft.NET.Native.Framework.2.2` 與 `Microsoft.NET.Native.Runtime.2.2`。

### 4.2 步驟 B2：確認 Gaming Services 有沒有占住

```powershell
Get-Process gamingservices* -ErrorAction SilentlyContinue | Select-Object Name, Id
```

有的話，先停掉（腳本結束的是這幾個程序）：

```powershell
'GameBar','GameBarFTServer','gamingservices','gamingservicesnet','XboxGameBarWidgets','XboxPcApp','XboxPcAppFT','XboxPcTray' |
  ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force }
```

如果步驟 B4 的 `Register` 仍回 `0x80073D02`，我們當時的做法是對目前使用者移除 Gaming Services：

```powershell
Get-AppxPackage Microsoft.GamingServices | Remove-AppxPackage
```

**修好之後要玩 Xbox 或 Minecraft，必須從 Store 把 Gaming Services 裝回來。**

### 4.3 步驟 B3：補 ALL APPLICATION PACKAGES

對 2.1 或 2.2 那一批框架資料夾，每個再做：

```cmd
icacls "<框架資料夾>" /grant "*S-1-15-2-1:(OI)(CI)(RX)" /T /C
```

- `*S-1-15-2-1` 是 ALL APPLICATION PACKAGES（所有應用程式套件）。沙箱程式屬於這個群組。
- 修復腳本還給了 `Administrators` 完全控制：

```cmd
icacls "<框架資料夾>" /grant "*S-1-5-32-544:(OI)(CI)(F)" /T /C
```

- **我們沒有證據第二行是必要的。** 想最小化改動，只做第一行，測試，不行再加第二行。

### 4.4 步驟 B4：註冊五個相依套件的 x64 與 x86 版本

```powershell
$names = 'Microsoft.NET.Native.Framework.2.2','Microsoft.NET.Native.Runtime.2.2','Microsoft.VCLibs.140.00',
         'Microsoft.VCLibs.140.00.UWPDesktop','Microsoft.UI.Xaml.2.8'
foreach ($n in $names) {
  foreach ($arch in 'X64','X86') {
    Get-AppxPackage -Name $n | Where-Object { $_.Architecture -eq $arch } | ForEach-Object {
      $m = Join-Path $_.InstallLocation 'AppxManifest.xml'
      if (Test-Path -LiteralPath $m) { Add-AppxPackage -DisableDevelopmentMode -Register $m }
    }
  }
}
```

預期：沒有紅字。出現 `0x80073D02`：回 B2。

### 4.5 步驟 B5：把失敗的 App 的使用者資料改名備份，再重新註冊

```powershell
$app = 'Microsoft.WindowsCalculator'
$pfn = (Get-AppxPackage $app).PackageFamilyName
$dir = Join-Path $env:LOCALAPPDATA ('Packages\' + $pfn)
if (Test-Path $dir) { Rename-Item $dir ($pfn + '.bak_' + (Get-Date -Format HHmmss)) }
$p = Get-AppxPackage $app
Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $p.InstallLocation 'AppxManifest.xml')
```

鬧鐘、便利貼、相機把 `$app` 換成 `Microsoft.WindowsAlarms`、`Microsoft.MicrosoftStickyNotes`、`Microsoft.WindowsCamera`。**這一步會讓 App 的設定與歷程記錄重置。**

### 4.6 驗證 B

```powershell
Start-Process 'shell:AppsFolder\Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'
Start-Sleep 8
Get-Process CalculatorApp -ErrorAction SilentlyContinue | Select-Object Name, Id, StartTime
```

有 `CalculatorApp` 程序，而且 5961 沒有新的紀錄，就是成功。我們的輸出是 PID 5104。

也可以用 [`scripts/Test-UwpApps.ps1`](../scripts/Test-UwpApps.ps1) 一次測多個 App。

### 4.7 想找出最小必要步驟

如果你的環境有同樣症狀，**請一次只做一步，並在每一步之後測試**，把結果告訴我們：

| 順序 | 只做這一步 | 測試後 |
|---|---|---|
| 1 | B3 的第一行（AAP） | 能開嗎？ |
| 2 | 再加 B3 的第二行（Administrators） | 能開嗎？ |
| 3 | 再加 B4（註冊框架） | 能開嗎？ |
| 4 | 再加 B2（停 Gaming Services） | 能開嗎？ |
| 5 | 再加 B5（清使用者資料） | 能開嗎？ |

## 5. Store 一直轉圈

Store 能啟動，但停在載入畫面：先關掉代理軟體與 VPN，再重開 Store。我們的案例關掉 FlClash 就恢復。

## 6. 修好之後

- 要玩 Xbox 或 Minecraft：先從 Store 裝回 Gaming Services。
- 想清掉修復期間留下的副作用（`C:\Users` 的授權、`SOFTWARE` 登錄檔檔案的擁有者、執行原則、測試檔等）：見 [10](10-cleanup-and-rollback.md) 與 [`scripts/Cleanup-AfterAppxFix.ps1`](../scripts/Cleanup-AfterAppxFix.ps1)。
- 重開機後再測一次。

## 7. 還原

**還原單一資料夾**（用 2.1 的備份與擁有者記錄）：

```cmd
takeown /f "<資料夾>" /a /r /d y
icacls "<資料夾的父資料夾>" /restore "%USERPROFILE%\acl_<名稱>.txt" /C
icacls "<資料夾>" /setowner "<步驟 1 記下的擁有者>" /T /C
```

- 備份檔裡的名稱是相對於父資料夾，所以 `/restore` 要對**父資料夾**執行。
- `icacls /save` 只存權限，不存擁有者。
- 還原後，`BUILTIN\Users` 條目會消失，問題會回來。

## 8. FAQ

**Q：我可以直接對整個 `WindowsApps` 做一次，省得一個個找嗎？**
不建議。範圍太大，會改到上百個無關的套件，而且我們沒有證據這樣做是安全的。用偵測腳本或 Procmon 找出被指到的就好。

**Q：為什麼一定要用 SID（`*S-1-5-32-545`），不能寫 `Users`？**
中英文系統的群組名稱不同。SID 都一樣。

**Q：修完要重開機嗎？**
我們沒有重開機就成功了。重開機後再測一次比較保險。

**Q：改了 `BUILTIN\Users`，會不會讓一般使用者能改框架檔案？**
我們給的是讀取與執行（`RX`），不是寫入。這是推論，沒有另外做安全評估。

**Q：我已經用過 `icacls /reset` 或 restore-appx 了，會怎樣？**
`/reset` 會把明確寫的條目清掉，包括我們補的 `Users`。補回去即可。restore-appx 的副作用見 [07](07-wrong-turns-and-side-effects.md)。

**Q：我沒有 Store，也沒辦法用 Xbox。我要先裝回哪些？**
先修好 A。Store 能開之後，從 Store 安裝 Gaming Services，再裝 Xbox。
