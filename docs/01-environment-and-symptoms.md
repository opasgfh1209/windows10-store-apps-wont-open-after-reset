# 01 環境與症狀

標記：**C** = Claude 的分析或指令，**G** = Grok 的分析或指令，**U** = 使用者貼出的實際輸出。

## 機器與系統

| 項目 | 內容 | 來源 |
|---|---|---|
| 作業系統 | Windows 10 專業版 22H2，build 19045；DISM 回報映像版本 `10.0.19045.3803` | U |
| 重設時間 | 2026-10-24 06:12:40（`Win32_OperatingSystem.InstallDate`） | U |
| 重設方式 | 「重設此電腦」→ 雲端下載 → 全部移除 | U |
| 儲存 | WDC WDS500G2B0C-00PXH0 SSD；`HealthStatus: Healthy`、`OperationalStatus: OK`、溫度 46、`Wear: 0` | U |
| 主機板 | 華碩（開機後自動出現 Armoury Crate、Intel Graphics Command Center、Realtek 音訊控制程式的 App） | U |
| 帳號 | 一個管理員帳號，另建一個 `test` 帳號對照；兩者症狀相同 | U |
| 其他 | 安裝了代理軟體 FlClash | U |

Windows 10 的一般支援已在 2025-10-14 結束，這台沒有 ESU 資料。這點與本問題無已知關聯，只作為背景。

## 重設之前已經做過的事

下列是本紀錄開始之前，使用者在其他對話中做過的，細節沒有保留：

- `sfc /scannow`、`DISM /Online /Cleanup-Image /RestoreHealth`
- 多輪 `Add-AppxPackage -Register`、`wsreset`、離線 `msixbundle`
- 使用 Media Creation Tool 做就地升級（仍然「待安裝」與閃退）
- 「重設此電腦」（雲端下載）

使用者特別強調：重設之後問題「一樣在」，所以不是殘留的舊設定。

## 使用者看到的症狀

1. 開始功能表有 Store、計算機、相片、郵件等磚塊，點下去閃退，或在「設定 → 應用程式」顯示未安裝。
2. 新建的 `test` 帳號登入後，開始功能表同樣有磚塊；在設定中點 Microsoft Store 會出現進度條，大小顯示 **0 位元組**；打開仍閃退。
3. 主機板廠商的 App（Armoury Crate）一樣閃退。
4. PowerShell：

   ```
   PS> Start-Process 'ms-windows-store:'
   Start-Process : 無法執行這個命令，因為發生錯誤: 存取被拒。。
   ```

5. 從 SYSTEM 視窗啟動 `ms-windows-calculator:` 會跳出「您需要新的應用程式才能開啟此 ms-windows-calculator 連結」。**這是測試環境不對的症狀，不是本問題。**

## 系統記錄的症狀

| 記錄 | 事件 | 內容（繁體中文系統原文） |
|---|---|---|
| `Microsoft-Windows-AppModel-Runtime/Admin` | 57 | 抓取套件 `Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe` 資料夾的信任狀態失敗，狀態為 2147942405。 |
| `Microsoft-Windows-AppModel-Runtime/Admin` | 61 | 0x5: 無法建立套件 `Microsoft.WindowsStore_22609.1401.6.0_x64__8wekyb3d8bbwe` 的處理程序，因為執行完整性檢查時發生錯誤。存取被拒。 |
| `Microsoft-Windows-TWinUI/Operational` | 5961 | `Microsoft.WindowsStore_8wekyb3d8bbwe!App` 啟用失敗。錯誤碼: 存取被拒。啟用階段: COM ActivateExtension |
| `Microsoft-Windows-AppXDeploymentServer/Operational` | 404、401 | 套件的 AppX 部署操作失敗，錯誤為 0x80070005。重設之後共 230 筆 `0x80070005`（逐字原文見 [11](11-evidence-excerpts.md) 第 1 節） |
| 同上 | 605 | 上次成功達到的狀態是 PrerequisitesChecked，之後失敗 |
| 同上 | 8761 | AppExecutionAlias 目錄遺失，錯誤碼 0x8007010B（早期） |
| `Microsoft-Windows-Store/Operational` | 2007、8002 | 取得使用者權杖失敗、授權流程失敗（各數百筆） |

數字換算：`2147942405` = `0x80070005`（`E_ACCESSDENIED`）。

第一批失敗的部署在 2026-10-24 13:02:53：`Microsoft.VCLibs.140.00_14.0.33519.0_x86` 與 Realtek 音訊控制程式的 Register 都是 0x80070005。**錯誤從重設後第一次登入就存在。**

## 看起來正常、其實沒有幫助的資訊

- `Get-AppxPackage` 對 Store、計算機、相片、Armoury Crate 都回 `Status: Ok`，`InstallLocation` 也存在。
- `StateRepository`、`TokenBroker`、`InstallService` 在執行；`AppXSvc`、`ClipSVC`、`wlidsvc` 在診斷時是停止的，因為它們是手動／觸發式服務，需要時才會啟動，不是原因。
- `Get-AppxPackage -AllUsers` 顯示約 20 個框架套件（UI.Xaml 2.0 到 2.7、NET Native、VCLibs UWPDesktop 110／120／140、WindowsAppRuntime 1.5 到 1.7 與 2 等）**只有 SYSTEM 是 `Staged`，使用者帳號沒有 `Installed`**。後來把它們用 `Add-AppxPackage -Register` 註冊進使用者帳號，狀態變成 `Installed`，但症狀完全沒變。這是一個誘人的錯誤線索。

## 已排除的項目

| 項目 | 做法 | 結果 |
|---|---|---|
| 磁碟 | `Get-PhysicalDisk`、`Repair-Volume -DriveLetter C -Scan`、System 記錄查 disk／Ntfs／stornvme | Healthy；`NoErrorsFound`；沒有相關錯誤。`ReadErrorsTotal` 等欄位是空白，代表驅動不回報，不能當成 0 |
| 記憶體 | Windows 記憶體診斷（2026-10-25 01:22）；查 WHEA-Logger | 「未偵測到問題」（事件 1101／1201）；WHEA 沒有任何記錄 |
| 元件存放區與系統檔 | `DISM /Online /Cleanup-Image /ScanHealth`、`sfc /verifyonly` | 未偵測到元件存放區損毀；沒有完整性違規 |
| 群組原則 | `gpresult /h` | 沒有已套用的 GPO，「設定」欄位寫「沒有設定定義」 |
| 安全軟體 | Windows 安全性保護歷程記錄；`CodeIntegrity/Operational`；`AppIDSvc` | 保護歷程記錄「沒有任何最近的動作」；CodeIntegrity 只有 3084 號資訊事件；AppIDSvc 停止 |
| MDM／公司管理 | `dsregcmd /status`、`HKLM\SOFTWARE\Microsoft\Enrollments` | 沒有加入 Azure AD 或網域；有 23 筆註冊機碼但 `ProviderID` 為空；有一筆 `MdmHosts` 原則值。判斷為映像殘留，沒有證據顯示它在作用 |
| 舊帳號設定檔 | 建立 `test` 帳號重測 | 兩個帳號症狀一樣 |
| 資料夾權限（頂層） | `icacls "C:\Program Files\WindowsApps"` 與一般 App 資料夾對照 | 頂層看起來是預設。**真正的缺口在框架資料夾**，見 [03](03-root-cause-a-framework-folder-acl.md) |
| 網路 | 測 Store 端點連線 | 可連線；但代理軟體會影響 Store 初始化，見 [04](04-root-cause-b-dotnet-native.md) |

## 觀察到、但沒有解釋的異常

| 觀察 | 備註 |
|---|---|
| DISM 回報映像版本 `10.0.19045.3803`，但 `StartMenuExperienceHost` 登錄版本是 `10.0.19041.5438`、`ShellExperienceHost` 是 `10.0.19041.5072`、`CloudExperienceHost` 是 `10.0.19041.6396`。第一次診斷（10/24 13:59）時 `ShellExperienceHost` 登錄的是 `10.0.19041.3636`；restore-appx 重新註冊 `C:\Windows\SystemApps` 之後變成 5072 | 版本不一致的原因沒有查。可能與雲端映像的服務堆疊狀態有關，也可能無關。列出來給後人參考 |
| 曾出現 0x800F0984，指向 `MicrosoftAccount.TokenProvider.Core` 元件不符（更新服務層，這是重設前階段的紀錄） | 沒有證據顯示它與本問題有關 |
| `W32Time`（Windows 時間服務）在診斷時是停止的 | 它是手動／觸發式服務，不算異常 |

## 使用者看到的症狀（逐項，含變體）

這一節把「你可能怎麼描述它」都列出來，方便比對自己的情況。

| 編號 | 你看到的 | 在我們的案例中 |
|---|---|---|
| S1 | 點開始功能表的 App 磚塊，視窗閃一下就消失 | 全部內建 App 與 Store |
| S2 | 點了沒有任何反應，也沒有錯誤訊息 | 部分 App，依啟動方式而不同 |
| S3 | 「設定 → 應用程式 → 應用程式與功能」中，該 App 顯示未安裝，或大小 0 位元組 | Store、計算機等 |
| S4 | 在 PowerShell 啟動 `ms-windows-store:` 得到「存取被拒」 | 在使用者的系統管理員視窗 |
| S5 | `Get-AppxPackage` 顯示 `Status: Ok`，`InstallLocation` 存在 | 全部 |
| S6 | 在 SYSTEM 視窗啟動 `ms-windows-calculator:` 跳出「您需要新的應用程式才能開啟此連結」 | 這是測試環境錯誤，與本問題無關 |
| S7 | 主機板廠商附的 App 一樣閃退 | Armoury Crate |
| S8 | A 修好後，Store 能開，但視窗停在載入畫面 | 代理軟體造成 |
| S9 | A 修好後，Store 能開，計算機、鬧鐘、相機、便利貼仍打不開 | 錯誤 B |
| S10 | 相片、Edge 等能正常開 | 相片不依賴 .NET Native；Edge 是 Chromium，權限條目完整 |

## 早期出現的其他錯誤碼（多半是雜訊或連鎖反應）

第一次診斷（2026-10-24 13:59）的 AppXDeploymentServer 與 AppReadiness 記錄，重設之後共 217 筆與 106 筆錯誤或警告。依錯誤碼統計：

| 錯誤碼 | 次數 | 意思（依事件訊息與一般文件，非完整官方對照） | 與本案例的關係 |
|---|---|---|---|
| `0x80070005` | 230 | 存取被拒 | 核心。大部分部署失敗的共同原因 |
| `0x80070015` | 19 | 裝置尚未就緒 | 查不到明確關聯，可能是掃到沒有媒體的磁碟機 |
| `0x80070057` | 6 | 參數錯誤 | 連鎖反應 |
| `0x80073CF9` | 5 | 套件註冊或安裝失敗（訊息內容未保留） | 套件狀態不一致，與重試有關 |
| `0x8007010B` | 5 | 目錄名稱無效；事件 8761：「AppExecutionAlias 目錄遺失，錯誤碼為 0x8007010B。」 | 早期現象，後來沒有再追 |
| `0x80073CF1` | 4 | 找不到套件；事件 712：「Windows 無法執行 StageUserData 操作，因為在存放庫中找不到 aimgr_0.20.61.0_x64__8wekyb3d8bbwe」 | 連鎖反應，與框架權限無關 |
| `0x80070490` | 2 | 找不到項目 | 雜訊 |
| `0x8007000D` | 1 | 資料無效 | 雜訊 |
| `0x80070002` | 1 | 找不到檔案 | 雜訊 |
| `0x80070525`、`0x80070520` | 各數百 | 使用者不存在、登入工作階段不存在 | 與權杖／身分有關，Store 的 2007、8002 事件帶這兩個碼。在補好框架權限之前出現，後來沒有再單獨追 |
| `0x800F0984` | 少數 | 元件修補失敗；指向 `MicrosoftAccount.TokenProvider.Core` 元件不符 | 更新服務層，與本案例的因果沒有確認 |

另外，Windows 錯誤報告（WER）的記錄名稱有 `AppxDeploymentFailureBlue` 與 `StoreAgentInstallFailure1`（Grok 對話中引用，原始 WER 內容未保留）。

## 沒有出現的症狀

這些**沒有**出現，可以用來排除其他類型的問題：

- 藍屏、無預警重開機（事件 1001、41、6008 都是 0）。
- 磁碟或檔案系統錯誤事件。
- WHEA 硬體錯誤。
- Windows Defender 或其他安全軟體的封鎖紀錄。
- 一般桌面程式（瀏覽器、Dev-C++、Steam 等）的異常。問題只在 UWP App。

## 重設前後的對照

| | 重設前 | 重設後 |
|---|---|---|
| 內建 App | 未安裝、閃退 | 一樣 |
| 錯誤 | 0x80070005 與 `AppxDeploymentFailureBlue` | 一樣，從第一次登入就有 |
| 新帳號 | 未測 | 同樣失敗 |
| 結論 | 重設不會修復這個問題。這暗示缺口不在使用者資料，而在重設後的映像或系統層 | |
