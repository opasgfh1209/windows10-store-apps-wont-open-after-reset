# 04 主因 B：.NET Native 的 App 啟動後讀不到框架的檔案

標記：**C** = Claude，**G** = Grok，**U** = 使用者輸出。這一段的後半由 Grok 接手（Claude 額度用完），Claude 沒有逐步參與，內容依 Grok 對話的匯出檔與使用者貼出的輸出整理。

## 一句話

主因 A 修好、Store 能開之後，計算機、鬧鐘、相機、便利貼仍然打不開。它們依賴 .NET Native 框架；`CalculatorApp.exe` 啟動後，在沙箱（AppContainer）裡讀不到框架資料夾的 DLL。另外，x64 的 .NET Native 套件曾因 `Microsoft.GamingServices` 占用而無法註冊。把框架資料夾的權限補齊、註冊 x86 與 x64 框架、清掉該 App 的使用者資料後，計算機能開。**這幾個步驟是一起做的，沒有分辨哪一步是關鍵。**

## 一、症狀

主因 A 修好後（2026-10-25 19:53），Store 能開，其他 App 的錯誤變了：

```
Microsoft-Windows-TWinUI/Operational  事件 5961
Microsoft.WindowsCalculator_8wekyb3d8bbwe!App 啟用失敗。錯誤碼: 應用程式未啟動。啟用階段: COM ActivateExtension
EventData:  ErrorCode = -2144927141    PhaseFlags = 34
```

- `-2144927141` = `0x8027025B`。Grok 的紀錄把它寫成 `0x8027021B`，是換算錯誤。
- 英文版系統的訊息文字是 **"The app didn't start."**（出處見 [09](09-search-notes-and-keywords.md) 的 HelpDeskGeek 條目）。
- AppModel-Runtime 的 **57 與 61 不再出現**，代表第 3 步（框架資料夾檢查）已經過了。
- 同一時段另有 AppModel-Runtime 事件 40，訊息大意是「未建立 AppContainer」，來源檔是 `appcontainer.cpp`（Grok 的對話中引用，節錄）。

## 二、與主因 A 的差別

| | 主因 A | 主因 B |
|---|---|---|
| 5961 的 `ErrorCode` | 存取被拒（`0x80070005`） | `-2144927141`（`0x8027025B`，「應用程式未啟動」） |
| AppModel-Runtime 57／61 | 有 | 沒有 |
| App 的程序 | 沒有被建立 | 被建立（或已啟動），隨即消失 |
| 受影響的 App | 全部 UWP | 只有依賴 .NET Native 的 App |
| 缺的權限 | 一般使用者（`BUILTIN\Users`） | 沙箱程式（ALL APPLICATION PACKAGES 或套件專屬條目） |
| 失敗的步驟 | 第 3 步：檢查框架資料夾 | 第 5 步：載入框架的 DLL |

## 三、縮小範圍

### 3.1 五個 App 對照（C，2026-10-26 01:09 之後）

啟動方式用 `shell:AppsFolder\<套件家族名稱>!App`，再查 5961：

```powershell
Start-Process 'shell:AppsFolder\Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'
```

| App | 結果 |
|---|---|
| 計算機 | 失敗 |
| 鬧鐘 | 失敗 |
| 相機 | 失敗 |
| 便利貼 | 失敗 |
| 相片 | 成功 |

### 3.2 失敗的 App 有什麼共同點（G）

比對清單檔的 `Dependencies`：失敗的四個 App 都依賴 `Microsoft.NET.Native.Framework.2.2` 與 `Microsoft.NET.Native.Runtime.2.2`（計算機另依賴 `Microsoft.VCLibs.140.00.UWPDesktop`）。Store 與相片不依賴 .NET Native。

```powershell
$p = Get-AppxPackage Microsoft.WindowsCalculator
([xml](Get-Content (Join-Path $p.InstallLocation 'AppxManifest.xml') -Raw)).Package.Dependencies.PackageDependency |
  Select-Object Name, MinVersion
```

## 四、發現過程（G 與 U）

### 4.1 x64 的 .NET Native 套件註冊失敗

對 x64 的 `Microsoft.NET.Native.Framework.2.2`、`Runtime.2.2` 做 `Add-AppxPackage -Register`，回 `0x80073D02`（無法安裝，因為它修改的資源目前已在使用中）。使用者輸出顯示 `gamingservices` 程序在執行。停止該程序，並對目前使用者移除 `Microsoft.GamingServices` 後，`Register` 成功。**計算機仍然打不開。**

這一步排除的是「x64 框架沒註冊」，沒有排除權限問題。

### 4.2 用 winget 重裝計算機

`winget install` 成功，仍失敗。排除「計算機本體壞了」。

### 4.3 直接執行 `CalculatorApp.exe`

在安裝資料夾直接執行，程序起得來，但跳出系統對話框，內容是找不到 `mrt100_app.dll`（.NET Native 的執行階段）與 `SharedLibrary.dll`（.NET Native 的框架）。對話框原文沒有保留，這是使用者的描述與 Grok 的摘要。

這是整個錯誤 B 最關鍵的一個現象：**程序起得來，卡在載入 DLL**，確認失敗發生在第 5 步，不是第 3 步。

### 4.4 Procmon

`CalculatorApp.exe` 讀取 `…\microsoft.vclibs.140.00_14.0.33519.0_x64__8wekyb3d8bbwe\vcruntime140_app.dll` 回 `ACCESS DENIED`。

Grok 的判斷：DLL 檔案在，是**框架資料夾對 App 自己（AppContainer）不可讀**，Windows 把「讀不到」報成「找不到」。

## 五、根因（最佳解釋，非確證）

三個條件疊在一起：

| # | 條件 | 證據強度 |
|---|---|---|
| 1 | 框架資料夾對沙箱程式沒有讀取權限。A 只補了給使用者身分用的 `BUILTIN\Users`；App 在沙箱裡跑，需要 ALL APPLICATION PACKAGES 或套件專屬條目 | 有直接證據：Procmon 的 `ACCESS DENIED` |
| 2 | x64 的 .NET Native 套件沒有註冊成功，`Microsoft.GamingServices` 占住它們 | 有錯誤碼證據：`0x80073D02` 與 `gamingservices` 程序。是否是 `Register` 成功的必要條件，沒有分離 |
| 3 | App 的使用者資料可能殘留壞狀態 | 沒有證據；腳本檔頭自己也把它標為「次要」 |

**關鍵的不確定性：** 修復腳本把權限、註冊、使用者資料備份一起做，成功了，但我們沒有分別測試每一步。要證明哪一步必要，需要在另一台有同樣症狀的機器上，一次只做一步。

## 六、修復腳本做了什麼

`Fix-UWP-Calculator.ps1`（Grok 產生）。全文收錄在 [`scripts/Fix-UWP-Calculator.ps1`](../scripts/Fix-UWP-Calculator.ps1)，**原樣收錄，沒有修改**。

**怎麼取得、怎麼確認是同一個版本：** 原本上傳的檔案是 0 位元組，內容是使用者把文字貼出來才有的。我們把腳本裡的訊息字串，和 Grok 對話中兩次執行的輸出逐一比對：兩次執行的第一行（`FixAllNativeApps=False SkipGamingServicesRemoval=False`、`FixAllNativeApps=True …`）、`ACL 修復:`、`釋放可能占用 .NET Native 的程序`、`Register OK`、`已改名備份`、`成功：CalculatorApp PID=`、`結果: 計算機進程已出現，修復成功。` 等關鍵訊息都對得上，第 1 次執行的 23 個動作也與腳本流程吻合。所以這就是當時執行的版本。

### 6.1 腳本檔頭自己寫的故障鏈

1. 框架或相依套件資料夾的 ACL 缺 `BUILTIN\Users` 或 ALL APPLICATION PACKAGES → `CalculatorApp.exe` 載入時 `ACCESS DENIED` → 對話框常顯示找不到 `mrt100_app.dll`、`SharedLibrary.dll`、`vcruntime140_app.dll`。
2. .NET Native x64 被 GamingServices 占用，無法 `Register`（`0x80073D02`）。
3. 套件需要用 `-DisableDevelopmentMode -Register`。
4. 使用者的 `Packages` 資料夾狀態損毀（腳本自己標為**次要**）。
5. AppContainer 未建立（事件 40，次要，並列處理）。

這個排序與本文的判斷一致：權限是主要的，使用者資料是次要的。

### 6.2 執行順序（依原始碼）

| 步驟 | 做了什麼 | 備註 |
|---|---|---|
| 0 | 檢查系統管理員身分；印出使用者、電腦、OS 與日誌路徑（`%TEMP%\Fix-UWP-Calculator_<時間>\report.txt`） | 不是系統管理員就以結束碼 1 離開 |
| 前置 | `Ensure-Services`：`StateRepository`、`AppXSvc`、`ClipSVC`、`AppReadiness`、`camsvc`、`LicenseManager` 沒在執行就啟動 | 只啟動，不改啟動類型。兩次執行都啟動了 `AppReadiness` |
| 前置 | `Install-CalculatorIfMissing`：計算機沒裝才用 `winget install 9WZDNCRFHVN5`，沒有 winget 就開 Store 產品頁 | 兩次執行都沒有觸發 |
| 1 | 對五個相依套件（`Microsoft.VCLibs.140.00`、`…UWPDesktop`、`Microsoft.NET.Native.Runtime.2.2`、`…Framework.2.2`、`Microsoft.UI.Xaml.2.8`）的**每個架構**（x86、x64）：`takeown /a /r /d y`；`icacls` 授予 `Administrators:(OI)(CI)(F)`、`*S-1-15-2-1:(OI)(CI)(RX)`、`*S-1-5-32-545:(OI)(CI)(RX)`，全部 `/T /C`。再檢查五個關鍵 DLL 可不可讀：`mrt100_app.dll`、`SharedLibrary.dll`、`vcruntime140_app.dll`、`msvcp140_app.dll`、`vccorlib140_app.dll`；不可讀就對該檔案再 `takeown` 與授權 | 共 10 個資料夾 |
| 2 | 計算機套件本體資料夾做同一組 ACL 修復 | 共 11 個資料夾。**沒有動 Store 的資料夾**，也沒有動 `WindowsApps` 根目錄 |
| 3 | 結束 `GameBar`、`GameBarFTServer`、`gamingservices`、`gamingservicesnet`、`XboxGameBarWidgets`、`XboxPcApp`、`XboxPcAppFT`、`XboxPcTray` 等程序；**預設**再對目前使用者 `Remove-AppxPackage Microsoft.GamingServices`（`-SkipGamingServicesRemoval` 可略過）；然後對五個相依套件依序 `Register`（每個名稱先 x64、再 x86） | `Register` 若回 `0x80073D02` 或「使用中」，再停一次程序並重試一次 |
| 4 | 結束 `CalculatorApp` 程序；把 `%LOCALAPPDATA%\Packages\Microsoft.WindowsCalculator_8wekyb3d8bbwe` 改名為 `.bak_HHmmss`（**改名失敗才直接刪除**）；`Register` 計算機 x64 | |
| 5 | （`-FixAllNativeApps`）對鬧鐘、便利貼、相機做同樣的使用者資料備份與 `Register` | **不**對這三個 App 的資料夾補 ACL |
| 測試 | `Start-Process shell:AppsFolder\<套件家族名稱>!App`，等 8 秒，看 `CalculatorApp` 程序。失敗就印出 5961 與 AppModel-Runtime 事件，事件 40 記為 `AppContainerNotCreated` | 結束碼 0 成功、2 失敗 |

### 6.3 兩次執行實際做了什麼（依紀錄）

| 執行 | 時間 | 動作 | 結果 |
|---|---|---|---|
| 第 1 次（預設） | 12:44:28 開始 | 共 23 個動作：11 次 ACL（10 個框架資料夾加計算機）、11 次 `Register`（10 個框架加計算機）、1 次使用者資料備份。**紀錄中沒有 GamingServices 的移除動作**，可能是先前已手動移除 | 12:44:52 `成功：CalculatorApp PID=5104`，約 24 秒 |
| 第 2 次（`-FixAllNativeApps`） | 13:15:26 開始 | 匯出檔只節錄了 42 行，看得到 4 次使用者資料備份（計算機、鬧鐘、便利貼、相機）與 14 次 `Register` | 13:15:54 收尾訊息「計算機進程已出現，修復成功」 |

### 6.4 與 README 4.4 的關係

README 4.4 的步驟是依這支腳本的流程，整理成可以一步一步做、一步一步測的版本，**不是逐字複製**。想一次做完，也可以直接用這支腳本，但請先看下一節的風險。

### 6.5 這支腳本的風險與限制

- 它**沒有備份權限**，也沒有還原功能。`-WhatIf` 只報告。
- 它把 10 個相依資料夾與計算機資料夾的擁有者改成 Administrators 群組，並給 `Administrators` 完全控制。我們沒有證據這兩項是必要的。
- 預設會對目前使用者移除 Gaming Services。
- 改名失敗時會**直接刪除** App 的使用者資料。
- `Administrators` 是用名稱寫的，不是 SID。名稱不同的語系可能失敗，我們只在繁體中文系統（群組名稱顯示為 `Administrators`）驗證過。
- 一次做太多事，所以**無法判斷哪一步是關鍵**。想找出最小必要步驟，請看 [06](06-fix-step-by-step.md) 的 4.7。
- 本 repo 的 [`Fix-FrameworkFolderAcl.ps1`](../scripts/Fix-FrameworkFolderAcl.ps1) 較保守（先報告、先記擁有者、有備份與日誌、可還原），但只涵蓋主因 A 的權限，不含 `Register`、使用者資料與 Gaming Services。

## 七、結果

| 執行 | 時間 | 結果 |
|---|---|---|
| 第 1 次（預設） | 2026-10-26 12:44:28 開始 | 計算機程序出現（PID 5104） |
| 第 2 次（`-FixAllNativeApps`） | 13:15:26 開始 | 計算機成功；鬧鐘、便利貼、相機被一併處理 |

使用者回報「終於修好了」。**鬧鐘、便利貼、相機沒有被實際開啟確認**（使用者之後沒有電腦可測），只能說腳本已對它們執行。

## 八、誤導我們的東西

| 項目 | 發生什麼 | 為什麼不相關 |
|---|---|---|
| 比對 `HKLM\SOFTWARE\Classes\PackagedCom`（C） | Store 有 9 個子項目，計算機沒有，一度以為是缺口 | 那是 `windows.comServer` 擴充點的登錄；計算機的清單檔沒有宣告它，本來就沒有 |
| DistributedCOM 10016（C） | 00:58 出現，CLSID `{C2F03A33-21F5-47FA-B4BB-156362A2F239}`、AppID `{316CDED5-E4AE-4B15-9113-7055D84DCC97}`，ShellExperienceHost（在沙箱裡）的本機啟用權限被拒 | 改用 `shell:AppsFolder` 啟動時這個事件**不會出現**，計算機照樣失敗。`DefaultLaunchPermission` 裡有 `IU`（互動式使用者）；`dcomcnfg` 裡也找不到這個 AppID。這個事件在正常的 Windows 上也常見，KB 4022522 說它是良性的 |
| 重設 App、移除後從 Store 重裝、`winget` 重裝（C、G） | 都不改框架資料夾權限 | 無效 |
| 錯誤碼換算（G） | 把 `-2144927141` 寫成 `0x8027021B` | 正確是 `0x8027025B` |

## 九、第三個因素：Store 停在「初始化」

Store 在 19:53 能啟動，但視窗停在載入畫面。使用者關閉代理軟體 FlClash 後，Store 恢復（G 建議，U 驗證）。之後曾出現「Store 需要更新自己」的提示，最後使用者回報 Store 正常。

機制沒有查證：是系統代理、TUN 模式還是 WinHTTP 代理造成的，我們沒有分辨。**如果你的 Store 能開卻一直轉圈，先關掉代理與 VPN 軟體再判斷。** 這個問題很容易被當成「權限還沒修完」。

## 十、與官方文件的關係

「The app didn't start」這個訊息，在網路上最接近的是 HelpDeskGeek 的〈Fix Windows 10 App Opens Then Closes〉，它指向 KB 2798317：原因是 ALL APPLICATION PACKAGES 缺少特定資料夾與登錄機碼的權限。這與我們主因 B 的方向一致（沙箱程式缺權限）。**差別在位置**：KB 與該文章講的是 `C:\Windows`、`C:\Program Files` 等標準位置，我們這台那些位置的 AAP 都正常，缺的是**框架套件資料夾**。

## 十一、修好之後的提醒

- 腳本可能已經移除 `Microsoft.GamingServices`。**要玩 Xbox 或 Minecraft 前，先從 Store 安裝 Gaming Services**，再裝 Xbox 與遊戲。
- 這一組權限變更讓 ALL APPLICATION PACKAGES 能讀框架資料夾，這與一般已安裝框架的樣子相同，不是安全問題。但 `Administrators` 完全控制與擁有者變更是副作用，收尾見 [10](10-cleanup-and-rollback.md)。

## 十二、沒有解釋的部分

1. 哪一步是關鍵：權限、註冊、清使用者資料，還是 Gaming Services。
2. 為什麼 Gaming Services 會占住 .NET Native 套件。
3. 鬧鐘、便利貼、相機實際上有沒有修好。
