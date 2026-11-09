# 10 收尾與回復

## 一、為什麼要收尾

修復期間，為了找原因，我們改了很多不屬於修復本體的東西。修好之後，使用者指出：**沒有人提醒他把這些清掉。** 這一份記錄我們盤點出什麼、怎麼處理，以及一支還沒有實機驗證的收尾腳本。

收尾的原則：

1. **不動修復本體。** 框架資料夾上 `BUILTIN\Users` 與 ALL APPLICATION PACKAGES 的讀取權限、已重新註冊的套件，都保留。
2. **能回復的才回復；不確定原始狀態的，只報告。**
3. **動權限的步驟：先備份、套用、測試、失敗就自動還原。**

## 二、盤點方法

重掃四份 Grok 對話匯出檔與 Claude 的對話，列出所有「會改系統狀態」的指令（`takeown`、`icacls`、`cacls`、`Set-ExecutionPolicy`、`Add/Remove-AppxPackage`、`reg`、`New-Item`、服務與排程、`Install-Module`、`winget`、`taskkill` 等），再對照使用者貼出的輸出，確認哪些真的執行。

## 三、盤點結果與處理

「腳本段」對應 [`Cleanup-AfterAppxFix.ps1`](../scripts/Cleanup-AfterAppxFix.ps1) 的段落編號。

| 腳本段 | 變更 | 如何判斷有沒有發生 | 處理 | 風險 |
|---|---|---|---|---|
| 1 | `C:\Windows\System32\config\SOFTWARE` 的擁有者被改成使用者 | `(Get-Acl C:\Windows\System32\config\SOFTWARE).Owner` | 改回同資料夾其他登錄檔的擁有者 | 中 |
| 2 | 執行原則曾設為 `Unrestricted` | `Get-ExecutionPolicy -List` | LocalMachine 改回 `Restricted`、CurrentUser 改回 `Undefined` | 中 |
| 3 | restore-appx 停止服務，「還原狀態」失敗 | `Get-Service` 的 `StartType` 對照預設 | 把不同於預設的改回 | 低到中 |
| 4 | 空的 `PackageRepository` 登錄機碼（可能在 `WOW6432Node`）；Sysinternals 的 EULA 登錄值 | `Test-Path` 兩個位置 | 空的才刪；刪不掉就留著 | 低 |
| 5 | `PSEXESVC` 服務、`PROCMON24` 驅動、排程 `FixXamlCat`、Pester 5.9.1 | 各自查詢 | 刪除 | 低 |
| 6 | `C:\ProgramData\Packages` 的權限被 restore-appx 改過 | 比對 restore-appx 在 `Temp\Restore-AppX` 留下的最早一份備份 | 用備份還原**根目錄**；子項目沒有備份 | 中 |
| 7 | `WindowsApps` 根目錄的擁有者與權限；是否執行過 `cacls /s` | `icacls "C:\Program Files\WindowsApps"` | 只報告；根目錄擁有者不是 TrustedInstaller 才會問 | 高（若執行過） |
| 8 | `C:\Users` 底下的 ALL APPLICATION PACKAGES 授權 | `icacls C:\Users` 與 `icacls "$env:USERPROFILE\Documents"` 有沒有 AAP | `icacls C:\Users /remove:g *S-1-15-2-1 /T /C`，先備份、測試、失敗自動還原 | 高 |
| 9 | `%LOCALAPPDATA%\Packages\*.bak_*` | 資料夾名稱結尾 `.bak_` 加六位數字 | 確認 App 正常後刪 | 低 |
| 10 | 桌面、文件、Downloads、Temp、SYSTEM 設定檔桌面的測試檔與工具 | 依檔名樣式 | 證據封存、工具刪除 | 低 |
| 11 | 框架與 App 資料夾：擁有者改成 Administrators、多了 Administrators 完全控制 | `Get-Acl` 與 `icacls` | **選用**：擁有者改回原廠值、移除多給的 Administrators 完全控制 | 低到中 |
| 12 | `Microsoft.GamingServices` 被停止或移除；`C:\$WINDOWS.~BT` 升級殘留 | `Get-AppxPackage`；`Test-Path` | 只報告 | 中 |

**不處理的：**

- AppX 資料庫（`StateRepository-*.srd`）被 restore-appx 重建，系統 App 與 WindowsApps 套件被重新註冊：無法還原，也已與修復混在一起。
- 修復腳本對框架資料夾的 ALL APPLICATION PACKAGES 授權：保留。

## 四、Grok 的收尾腳本與我們的比較

Grok 也給了一份收尾腳本（硬寫完整路徑，刪殘留、把擁有者改回 TrustedInstaller）。我們沒有採用，原因：

| 項目 | Grok 的腳本 | 問題 |
|---|---|---|
| 擁有者 | `icacls "C:\Program Files\WindowsApps" /setowner "NT SERVICE\TrustedInstaller" /T /C` | 帶了 `/T`，會把整個 `WindowsApps` 上百個套件的擁有者全改成 TrustedInstaller，原本是 SYSTEM 的也一起改 |
| 修復腳本 | 刪除桌面上的 `Fix-UWP-Calculator.ps1` 與 Temp 裡的執行紀錄 | 那是修復的證據，也是要放進這個 repo 的材料 |
| restore-appx 資料夾 | 整個刪除 | 裡面有 `C:\ProgramData\Packages` 修改前的權限備份，是還原的唯一依據 |
| 計算機與 Store 的擁有者 | 改成 TrustedInstaller | 原本是 SYSTEM |
| `C:\Users` 的 AAP | 沒有處理 | 影響 3 萬多個物件，是最大的副作用 |
| `SOFTWARE` 登錄檔檔案擁有者、執行原則、服務、32 位元視窗留下的位置 | 沒有處理 | — |
| 備份、測試、還原 | 沒有 | 出錯無法回頭 |

Grok 的腳本有用的地方：它列出了幾個我們的檔名樣式沒涵蓋到的名稱（`AppX_FullDiag_*` 的 Temp 資料夾、桌面上的兩支腳本、`未命名1.ps1`）。這些已經併進我們的腳本。

## 五、`Cleanup-AfterAppxFix.ps1` 怎麼運作

**預設只報告，不改任何東西。** 加 `-Apply` 才會執行，而且每一段都先問 Y/N。

| 特性 | 做法 |
|---|---|
| 環境檢查 | 不是系統管理員、是 SYSTEM、是 32 位元，都直接拒絕 |
| 修復狀態確認 | `-Apply` 時先啟動計算機與 Store，確認現在是好的；不是好的就停止，不收尾 |
| 備份 | 每個會動權限的段落，先用 `icacls /save` 備份，並把擁有者記進 `manifest.csv` |
| 測試與自動還原 | 動完權限，再啟動計算機與 Store；失敗就自動還原，並再測一次 |
| 還原模式 | `-Rollback "<備份資料夾>"` 依 `manifest.csv` 還原全部備份 |
| 證據 | 測試檔與紀錄移到「文件\AppX修復存檔」，不刪 |

使用方式：

```powershell
# 1. 先報告（不會改任何東西）
powershell -NoProfile -ExecutionPolicy Bypass -File .\Cleanup-AfterAppxFix.ps1

# 2. 看過報告、確認沒問題，再執行（每一段都會問）
powershell -NoProfile -ExecutionPolicy Bypass -File .\Cleanup-AfterAppxFix.ps1 -Apply

# 3. 需要時，整個還原
powershell -NoProfile -ExecutionPolicy Bypass -File .\Cleanup-AfterAppxFix.ps1 -Rollback "C:\Users\<USER>\Documents\AppX收尾_<時間>"
```

**驗證狀態（誠實說明）：**

- 用 PowerShell 7.4.6 的解析器做過語法檢查，沒有錯誤。
- 用我們實際貼出的 `icacls` 輸出，驗證過 `Get-AclFacts` 的判斷（原廠樣子、動過之後、修復前的框架）。
- **沒有在 Windows 上實測。** 還原段的順序在撰寫時重讀發現有誤，已修正。第一次請只跑報告模式。

**已知的不確定：**

- restore-appx 備份檔的格式我們沒有看過。看不懂時，腳本會停下來，不會硬還原。
- 原廠擁有者（框架是 TrustedInstaller，計算機與 Store 是 SYSTEM）是依 10/25 凌晨的一份清單推得的，沒有健康機器對照。所以第 11 段是選用。
- `icacls /remove:g *S-1-15-2-1 /T /C` 可能移除 `C:\Users` 底下原本就存在的 AAP 條目（如果有）。測試只涵蓋計算機與 Store，所以如果之後有 App 異常，用 `-Rollback` 還原。

## 六、手動做法（不用腳本時）

**1. 登錄檔 SOFTWARE 的擁有者**

```powershell
(Get-Acl 'C:\Windows\System32\config\SYSTEM').Owner
icacls 'C:\Windows\System32\config\SOFTWARE' /setowner '<上一行顯示的擁有者>'
```

**2. 執行原則**

```powershell
Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope LocalMachine
Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser
```

**8. `C:\Users` 的 AAP**（先備份）

```cmd
icacls C:\Users /save "%USERPROFILE%\acl_users.txt" /T /C
icacls C:\Users /remove:g "*S-1-15-2-1" /T /C
```

做完測試計算機與 Store。失敗就還原：

```cmd
icacls C:\ /restore "%USERPROFILE%\acl_users.txt" /C
```

**9. `.bak_` 資料夾**

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory | Where-Object { $_.Name -match '\.bak_\d{6}$' }
# 確認 App 正常後：Remove-Item -Recurse -Force
```

其餘（服務、機碼、工具殘留）建議用腳本的報告模式先看有沒有。

## 七、實測結果

**待補。** 使用者之後在電腦上跑完，請把下面這張表補上：

| 項目 | 報告模式的發現 | `-Apply` 的結果 | 測試通過？ |
|---|---|---|---|
| 1 SOFTWARE 擁有者 | | | |
| 2 執行原則 | | | |
| 3 服務 | | | |
| 4 機碼 | | | |
| 5 工具殘留 | | | |
| 6 ProgramData\Packages | | | |
| 7 WindowsApps 根目錄 | | | |
| 8 C:\Users AAP | | | |
| 9 `.bak_` | | | |
| 10 檔案 | | | |
| 11 框架資料夾（選用） | | | |
| 12 其他 | | | |
