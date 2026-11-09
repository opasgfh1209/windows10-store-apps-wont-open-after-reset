# 02 時間軸

時間為台灣時間（UTC+8）。**C** = Claude，**G** = Grok，**U** = 使用者貼出的輸出。

- 有「約」或時間範圍的列，代表輸出本身沒有時間戳，時間是依前後文推的。
- 「來源」欄寫的是誰提出該步驟、誰提供輸出。一個步驟常常是 G 或 C 提出、U 執行。
- 使用者在兩個 AI 之間來回貼對話，所以同一個結論偶爾會同時出現在兩邊。歸屬以原始紀錄為準，見 [06](08-who-said-what.md)。

## 時間軸

### 2026-10-24（週六）

| # | 時間 | 事件 | 來源 | 結果 |
|---|---|---|---|---|
| 1 | 06:12 | 「重設此電腦」完成（雲端下載、全部移除） | U | 重設後內建 App 仍然未安裝或閃退 |
| 2 | 13:02 | 重設後第一批部署失敗：VCLibs 140 x86 與 Realtek 音訊控制程式，Register 0x80070005 | U | 錯誤從第一次登入就存在 |
| 3 | 13:59 | 第一份診斷：服務、政策、套件狀態、事件統計 | C 腳本、U 輸出 | 服務正常；0x80070005 共 230 次；Store、計算機、相片 `Status: Ok` |
| 4 | 14:09 | 新帳號 `test` 的截圖與設定頁 | U | 磚塊在；Store 顯示 0 位元組；仍閃退。排除「舊帳號設定檔壞掉」 |
| 5 | 14:09 到 14:44 之間 | 排查磁碟、檔案系統、`DISM`、`sfc`、群組原則、安全軟體、MDM | C 指令、U 輸出 | 全部正常，見 [01](01-environment-and-symptoms.md) |
| 6 | 14:44 | 全面診斷（12 段，我寫的腳本） | C 腳本、U 輸出 | 腳本標了 27 項「嚴重」，多數是腳本誤判。真線索：框架套件只有 SYSTEM 為 `Staged`；Store 權杖與授權錯誤各數百筆 |
| 7 | 14:44 之後 | 唯讀檢查：資料夾權限、MDM 註冊、WHEA | C 指令、U 輸出 | WHEA 無記錄；MDM 只有空殼；頂層權限正常 |
| 8 | 20:53 | 證據包 A（靜態證據）與 B（啟動測試） | C 腳本、U 輸出；C 與 G 各自讀 zip | Edge 能啟動，Store、計算機不行；計算機部署事件 605 失敗於 `PrerequisitesChecked`；約 20 個框架只有 SYSTEM `Staged` |
| 9 | 約 22:20 | 14 個框架 `Add-AppxPackage -Register`，全部 OK | G 指令、U 輸出 | 框架在使用者帳號變 `Installed`；Store 仍閃退 |
| 10 | 22:31 | Store 深入診斷 | G 腳本、U 輸出 | 事件 57 指向 Xaml 2.8 x64、61 完整性檢查失敗；Manifest 相依全部 `Installed` |
| 11 | 22:50 到 23:15 | 移除並重新註冊 Xaml 2.8 | G、U | 仍 57 |
| 12 | 23:31 | 比對 Edge 與 Xaml 2.8 的資料夾 | G 腳本、U 輸出 | Edge 有 Users、AAP、受限 AAP 條目；Xaml 2.8 沒有；Xaml DLL 簽章有效 |
| 13 | 23:46 | 對 Xaml 2.8 `takeown`，補 AAP 與受限 AAP | G、U | 仍 57。方向不完全對：缺的是 Users，不是 AAP |

### 2026-10-25（週日）

| # | 時間 | 事件 | 來源 | 結果 |
|---|---|---|---|---|
| 14 | 約 00:40 | 撤回「權限缺 AAP」的推論；要求先還原權限，再用官方 appx 重裝 | C | `icacls /reset` 的子項目被拒；NuGet 2.8.7 內的 appx 版本為 `8.2501.31001.0`，簽章有效 |
| 15 | 01:22 | Windows 記憶體診斷：未偵測到問題 | U | 排除記憶體 |
| 16 | 01:33 | 以官方 appx 重裝 Xaml 2.8（x64、x86） | G 建議下載站、C 建議 NuGet、U 執行 | `Status: Ok`，仍 57／61。檔名格式符合商店套件下載站，推測使用者用了 G 建議的來源 |
| 17 | 01:39 到 01:41 | `CodeIntegrity.cat` 取得擁有權、授權後可讀 | G 指令、U 輸出 | 仍 57 |
| 18 | 02:05 到 04:00 | restore-appx：`-Diagnose`、`-Rebuild -DatabaseOnly`、`-Rebuild`、`-Rebuild -Force` | G 推薦、U 執行 | 診斷 Degraded、缺 `PackageRepository` 機碼、缺 50 個 manifest。重建後無效；`-Force` 失敗於不存在的 `C:\Program Files (x86)\WindowsApps` |
| 19 | 02:48 | Microsoft-Store-Fix v1.4.0 | G 推薦、U | 0x80073CF3（工具把 Framework 1.7 硬塞進相依） |
| 20 | 03:47 到 03:51 | Pester 測試 restore-appx | G、U | 7 過 1 失敗，與問題無關 |
| 21 | 12:28 | Grok 診斷腳本 | G 腳本、U 輸出 | `CodeIntegrity.cat` 可讀、擁有者 TrustedInstaller；`PackageRepository` 機碼不存在；`.srd` 被鎖；57／61 不變。腳本後半因變數 `$Log` 與 `$log` 同名而寫檔失敗 |
| 22 | 12:39 | 依 KB 2798317 檢查 ALL APPLICATION PACKAGES 權限；`gpresult` | C 指令、U 輸出 | `C:\Program Files`、`C:\Windows` 有 AAP；`C:\Users` 沒有；沒有任何群組原則 |
| 23 | 12:40 到 13:40 | 對 `C:\Users` 遞迴授 AAP 讀取 | G 建議、U 執行 | 處理 37,433 個、失敗 3,743 個；無效，且弱化沙箱 |
| 24 | 13:09 | Procmon 第 1 次 | G、U | 2,541 筆全是 `ApplicationFrameHost.exe`，沒有 ACCESS DENIED。擷取範圍太窄 |
| 25 | 18:02 | ACL 備份腳本 | C 腳本、U 輸出 | 備份寫進 `…\config\systemprofile\Desktop`：發現視窗是 SYSTEM |
| 26 | 18:10 | Procmon 第 2、3 次（同一次擷取的兩份匯出） | C 指令、U | 第 2 份 22,510 筆，ACCESS DENIED 只有 `explorer.exe`；第 3 份 47 萬筆，含 `svchost.exe` |
| 27 | 18:10:48、:54、:57 | `svchost.exe` 以使用者身分開啟 Xaml 2.8 x64 資料夾，`READ_CONTROL` 被拒 | C 分析 | **錯誤 A 的根因證據** |
| 28 | 約 19:00 | 對 Xaml 2.8 x64 加 `BUILTIN\Users:(OI)(CI)(RX)` | C 指令、U | 16 項、0 失敗 |
| 29 | 19:05、19:23 | 測試仍失敗 | C、U | 視窗是 SYSTEM（`whoami` 回 `nt authority\system`），測試無效 |
| 30 | 19:34 到 19:35 | Procmon 第 4 次（只篩 ACCESS DENIED，34 筆） | C 指令、U | Xaml 的拒絕消失；新拒絕：NET Native Framework 2.2 x64（19:35:00）、VCLibs 140 x64（19:35:12） |
| 31 | 約 19:36 到 19:50 | 四個 x64 框架加 Users | C 指令、U 輸出 | 第一次幾乎全是「存取被拒」；先 `takeown /a /r /d y` 再授權後 0 失敗（11／12／21／35 項） |
| 32 | 19:53 | Store 開啟 | C、U | `WinStore.App` 程序 19:53:35 出現；沒有 57／61。計算機的錯誤改成「應用程式未啟動」→ 錯誤 B 開始 |
| 33 | 約 21:10 | Store 開了但停在「初始化」 | G、U | 關閉代理軟體 FlClash 後正常 |
| 34 | 23:26 到 23:48 | `AppX_FullDiag`、批次註冊；ScreenSketch、錄音機、Xbox 相關 App 出現 0x80073D04 或 0x80070005 | G、U | 對舊版相依資料夾（Xaml 2.0、NET Native Runtime／Framework 1.7、Store.Engagement、WebpImageExtension）takeown 與授權；相片能開 |

### 2026-10-26（週一）

| # | 時間 | 事件 | 來源 | 結果 |
|---|---|---|---|---|
| 35 | 00:48 到 00:58 | 計算機：重新註冊、重設、移除後從 Store 重裝 | C 指令、U 輸出 | 全部仍失敗 |
| 36 | 00:58 | DistributedCOM 10016（Immersive Shell） | C 分析、U 輸出 | 後來證實與計算機無關 |
| 37 | 01:09 | 改用 `shell:AppsFolder` 啟動 | C、U | 仍失敗，且沒有 10016 → 排除 |
| 38 | 01:09 之後 | 五個 App 對照 | C 指令、U 輸出 | 計算機、鬧鐘、相機、便利貼失敗；相片成功 |
| 39 | 01:38 | 改由 Grok 接手（Claude 額度用完） | G、U | 5961 `ErrorCode -2144927141`、`PhaseFlags 34`；失敗的 App 都依賴 .NET Native |
| 40 | 01:38 到 02:12 | x64 .NET Native 套件 Register 0x80073D02 | G、U | `Microsoft.GamingServices` 占用；停止後 Register OK，仍失敗 |
| 41 | 01:38 到 02:12 | `winget install` 重裝計算機 | G、U | 成功，仍失敗 |
| 42 | 02:12 | AppModel-Runtime 事件 40「未建立 AppContainer」；直接執行 `CalculatorApp.exe`；Procmon | G、U | 對話框找不到 `mrt100_app.dll`、`SharedLibrary.dll`；`CalculatorApp.exe` 讀 VCLibs 的 `vcruntime140_app.dll` 被拒 → **錯誤 B 的證據** |
| 43 | 12:44 | `Fix-UWP-Calculator.ps1` 第 1 次 | G 腳本、U 輸出 | `CalculatorApp` 程序出現（PID 5104）✔ |
| 44 | 13:15 | 第 2 次，`-FixAllNativeApps` | G、U | 計算機成功 ✔；鬧鐘、便利貼、相機一併處理，但沒有實際開啟確認 |

### 2026-10-27 至 10-29

| # | 時間 | 事件 | 來源 | 結果 |
|---|---|---|---|---|
| 45 | 10/27 | 使用者指出：修好之後沒有清理測試檔與權限 | U | 開始盤點 |
| 46 | 10/27 到 10/28 | 重掃全部紀錄，盤點留下的變更 | C | 11 類，見 [05](07-wrong-turns-and-side-effects.md) |
| 47 | 10/28 | Grok 給了一份收尾腳本；Claude 比較並指出風險 | G、C | 見 [08](10-cleanup-and-rollback.md) |
| 48 | 10/28 | `Cleanup-AfterAppxFix.ps1` 完成；用 PowerShell 7.4.6 解析器檢查語法，並以真實 `icacls` 輸出驗證判斷邏輯 | C | **尚未在 Windows 實測** |
| 49 | 10/29 | 整理本文件 | C、U | |
| 50 | 10/29 之後 | 事後尋回 `Fix-UWP-Calculator.ps1` 原始內容：使用者貼出全文（上傳檔是 0 位元組）。Claude 先前抓取使用者給的對話連結時，內容在前段被截斷，誤判為不相關，已更正 | U、C | 全文收錄為 `scripts/Fix-UWP-Calculator.ps1`，訊息字串與兩次執行的紀錄逐一比對吻合 |

## 階段小結

| 階段 | 範圍 | 做了什麼 | 為什麼沒有結果或有結果 |
|---|---|---|---|
| 1 | #1 到 #8 | 排除磁碟、記憶體、系統檔、政策、安全軟體、舊帳號 | 全部正常，但這一步是必要的。沒有它，後面的「權限」假設沒有依據 |
| 2 | #9 到 #26 | 註冊框架、重裝 Xaml、補 AAP、restore-appx、C:\Users 授權 | 這些都在「改東西」，沒有先找出**誰被拒絕、拒絕什麼路徑** |
| 3 | #26 到 #32 | Procmon 只篩 `ACCESS DENIED`、不篩處理序，逐一補框架資料夾 | 決定性的一步。約 90 分鐘從不知道缺什麼，到 Store 開啟 |
| 4 | #32 到 #44 | 錯誤 B：縮小到 .NET Native，找出 DLL 讀不到 | 需要兩個 AI 接力，也需要直接執行 `.exe` 看到系統對話框 |
| 5 | #45 到 #49 | 清理與回復 | 修復時沒有做權限備份，所以回復只能靠推論 |

最大的教訓：**第 2 階段花了大約 22 小時，第 3 階段花了不到 2 小時。** 如果一開始就用 Procmon 抓「`Result is ACCESS DENIED`、不加處理序條件」，大半的彎路可以省掉。
