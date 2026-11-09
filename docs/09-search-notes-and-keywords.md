# 09 搜尋紀錄與關鍵字

## 一、結論

截至 2026-10-29，我們用英文與繁體中文共搜尋 12 次（另有 2 次直接讀取頁面），**沒有找到**描述下列任一項的文章：

- 重設之後，框架套件資料夾沒有 `BUILTIN\Users` 權限條目，造成所有 UWP App 閃退；
- AppModel-Runtime 事件 57「信任狀態失敗」的繁體中文原文；
- 「補一個框架、下一個冒出來」的 Procmon 現象；
- 主因 A 與主因 B 疊在一起的組合。

找到的有四類：

1. 同一類症狀的文章（Store 打不開、App 閃退），但給的是通用做法。
2. 相同的錯誤碼或訊息出現在別的情境。
3. 官方 KB 2798317：預設權限被改，ALL APPLICATION PACKAGES 缺少權限。這是最接近的官方文件。
4. 使用者自己改壞 `WindowsApps` 權限的討論，做法是還原預設。

**限制：** 搜尋工具讀不到需要登入的討論區與社群貼文。**「沒找到」不等於「不存在」。** 如果你找到了，請開 issue 告訴我們。

## 二、我們怎麼搜（方法）

查詢由粗到細，每一輪換一種「層級」：

| 層級 | 查詢的組成 | 目的 |
|---|---|---|
| 症狀層 | 系統版本 + 症狀 + 錯誤碼 | 看有沒有已知問題 |
| 記錄層 | 記錄名稱 + 事件編號 + 引號包住的訊息片段 | 找到寫過這個事件的人 |
| 訊息層 | 訊息原文、DLL 名稱、錯誤碼 | 找到同一個錯誤出現過的情境 |
| 機制層 | 資料夾、權限條目、指令名稱 | 找有人做過同樣的修復 |
| 官方層 | 官方文件網址 + 症狀 | 找有沒有官方說明 |

**一個教訓：** 我們一開始只用症狀層（「重設後內建 App 打不開」），搜了很久。後來才用記錄層與訊息層，但那時問題的方向已經確定了。如果當初這份文件已經存在，事件編號和訊息原文一搜就會到。這也是下面關鍵字庫刻意寫得這麼長的原因。

## 三、查詢紀錄

「模式」：`標準` 是一般搜尋，`延伸` 是較徹底、較慢的搜尋。「讀過」指我們有開啟頁面讀內文；沒有標的是只看標題與摘要。

| # | 查詢（原文） | 模式 | 找到什麼 | 判斷 |
|---|---|---|---|---|
| 1 | `Windows 10 22H2 19045.3803 known issue Microsoft Store apps fail to install 0x80070005 after reset` | 標準 | windowsreport.com 的 Store 0x80070005 通用修復文、Microsoft Q&A 數則、lhotka.net 的〈Fixing Windows 10 store issues〉、anoopcnair.com 的 0x80131500 | 通用做法。**沒有** 19045.3803 的已知問題 |
| 2 | `Download Windows 10 22H2 disc image ISO official Microsoft download page Media Creation Tool after end of support` | 標準 | 微軟官方下載頁、windowslatest 與 winaero 的相關文章 | 用來規劃就地升級；使用者已經試過，無效 |
| 3 | `AppModel-Runtime event 57 "trust state" package folder failed event 61 "integrity check" access denied UWP apps crash` | 延伸 | GitHub 上幾個無關的 issue、NVIDIA 論壇與 ugetfix 的「Failed with 0x57 retrieving AppModel Runtime status」、Microsoft Q&A〈UWP Apps are not working - Settings broken〉（讀過） | `0x57` 是另一個錯誤（參數錯誤），不是我們的 57 事件。Q&A 那篇指向 ALL APPLICATION PACKAGES 的登錄權限，方向相近 |
| 4 | `Microsoft Store apps fail to start if default registry or file permissions modified troubleshoot learn.microsoft.com` | 標準 | KB 2798317（讀過）、Microsoft 的 Process Monitor 疑難排解文章、KB 2787623、KB 3092053、HelpDeskGeek〈Fix Windows 10 App Opens Then Closes〉 | **最接近的官方文件**，但位置與本案例不同 |
| 5 | （直接讀取）KB 2798317 頁面 | — | 轉址到 learn.microsoft.com 的 `microsoft-store-apps-fail-to-start`；內容是 ALL APPLICATION PACKAGES 缺少哪些位置的讀取權限，並列出兩種症狀（事件 5961、`0xc000027b`） | 見第四節 |
| 6 | `Microsoft.UI.Xaml nuget package tools AppX x64 Release Microsoft.UI.Xaml.2.8.appx WinUI 2.8 extract appx` | 標準 | 幾個 GitHub gist（winget 相依套件安裝）、PowerShell Gallery 的 winget 安裝腳本 | 用來確認 NuGet 套件裡有 `tools\AppX\<架構>\Release\*.appx`。與問題無關 |
| 7 | `DistributedCOM 10016 "316CDED5-E4AE-4B15-9113-7055D84DCC97" OR "C2F03A33-21F5-47FA-B4BB-156362A2F239" ShellExperienceHost local activation permission` | 標準 | KB 4022522、Microsoft Q&A、winhelponline 的 10016 修復文 | 10016 通常是良性事件；與計算機無關 |
| 8 | `Microsoft Store won't open after reset "WindowsApps" framework folder "BUILTIN\Users" missing ACL "Microsoft.UI.Xaml" takeown icacls fix access denied` | 延伸 | mundobytes〈Restore apps that won't open due to permissions in Windows〉、tenforums〈I broke the Microsoft Store. Help!〉、thesolving.com 的 icacls 重設權限文、Microsoft Q&A 的 Store 打不開數則、GitHub 一則無關 issue | 都是通用做法，或「使用者自己改壞權限」的情況。**沒有**框架資料夾缺 `BUILTIN\Users` 的內容 |
| 9 | `"信任狀態失敗" 套件 資料夾 AppModel-Runtime 存取被拒 UWP 內建 App 閃退 重設後` | 延伸 | Microsoft Learn 繁體中文〈針對 Windows 應用程式的封裝、部署和查詢進行疑難排解〉、一篇 CSDN 的 WindowsApps 存取被拒問答、一篇 CSDN 的〈修復 UWP 應用在啟動頁閃退的問題〉 | 沒有事件 57 的中文原文。CSDN 那篇症狀相近（重設後所有 UWP 閃退），做法是重新註冊全部套件，本案例已試過，無效 |
| 10 | `"mrt100_app.dll" OR "SharedLibrary.dll" calculator UWP app won't start .NET Native framework access denied AppContainer` | 標準 | itechguides 與 macmyths 的 mrt100 錯誤文、techbloat、幾則 Stack Overflow／Super User 的 .NET Native 問題 | 通用的「修復 App、重設、更新」。其中一篇把權限或設定檔列為可能原因，沒有細節 |
| 11 | `Microsoft-Windows-TWinUI/Operational event 5961 "activation failed" "COM ActivateExtension" UWP app closes immediately Windows 10` | 標準 | HelpDeskGeek（兩個網址）、edugeek 論壇、Microsoft Q&A 的 `0x80040904`、Super User 的〈UWP apps launch and then disappear immediately〉 | HelpDeskGeek 引用了「The app didn't start」並指向 ALL APPLICATION PACKAGES 權限；其餘是別的錯誤碼 |
| 12 | `"0x8027025B" OR "-2144927141" UWP app "The app didn't start" activation failed Windows 10` | 標準 | Qt 郵件列表（2017）、windows-hexerror 網站的 `0x8027025B` 頁、Super User〈XBOX App not working on Windows 10〉、Stack Overflow 的 Visual Studio XAML 設計工具錯誤與〈Activation of the Windows Store app … failed with error 'The app didn't start'〉 | **同一個錯誤碼**出現在別的情境：2015 年 Windows 10 剛推出時的 Xbox App 閃退（回答只有重灌）、開發者的 UWP 專案。沒有與本案例相同的原因 |
| 13 | （直接讀取）`learn.microsoft.com/en-us/answers/questions/5895149`〈UWP Apps are not working - Settings broken〉 | — | ALL APPLICATION PACKAGES 缺少登錄機碼讀取權限會讓 UWP 與設定頁打不開 | 方向相近；位置是登錄，不是框架資料夾 |
| 14 | （直接讀取，失敗）`learn.microsoft.com/troubleshoot/windows-client/shell-experience/microsoft-store-apps-fail-to-start` | — | 第一次直接讀取被擋：該網址沒有出現在先前的搜尋結果中。改由查詢 4 取得 | — |

## 四、最接近的結果，以及為什麼沒有解決我們的問題

| 來源 | 它說什麼 | 與本案例的差別 |
|---|---|---|
| **KB 2798317**（Microsoft） | 預設權限被改，`ALL APPLICATION PACKAGES` 缺少特定檔案與登錄位置的讀取權限，會讓 App 啟動失敗（事件 5961 或 `0xc000027b`）。修法是把權限加回去 | 它要的位置（`C:\Program Files`、`C:\Windows` 等）我們這台**都有 AAP**。缺的是**框架套件資料夾**的 `BUILTIN\Users`，KB 沒有提到 |
| **HelpDeskGeek**〈Fix Windows 10 App Opens Then Closes〉 | 5961 的訊息「The app didn't start」，原因指向 AAP 權限；做法參照 KB | 同上。本文取了它引用的英文訊息 |
| **Microsoft Q&A**〈UWP Apps are not working - Settings broken〉 | AAP 缺少登錄權限，UWP 與設定頁打不開 | 位置是登錄，不是檔案系統的框架資料夾 |
| **Super User**〈XBOX App not working on Windows 10〉（2015） | 同樣的 `ErrorCode -2144927141` | 回答是重灌，沒有找出原因 |
| **tenforums**〈I broke the Microsoft Store. Help!〉、**mundobytes**〈Restore apps that won't open due to permissions in Windows〉 | 使用者自己改壞 `WindowsApps` 權限，做法是還原擁有者與預設權限 | **與本案例相反**：我們的缺口是條目從來沒有，不是被改壞。照做 `icacls /reset` 反而會清掉我們補上的條目。（只看標題與摘要，未讀全文） |
| **CSDN**〈修復 UWP 應用在啟動頁閃退的問題〉（原標題為簡體中文，這裡轉成繁體） | 重設後所有 UWP 閃退，建議重新註冊全部套件 | 症狀幾乎一樣；本案例已試過，無效 |
| **Microsoft Learn**〈針對 Windows 應用程式的封裝、部署和查詢進行疑難排解〉 | 部署錯誤碼表；`0x80073CFE` 時提到 `PackageRepositoryRoot` 登錄值 | restore-appx 檢查的是 `PackageRepository`，不是它。與本案例無關 |
| **Stack Overflow／Super User**「Cannot reinstall Calculator: Microsoft.UI.Xaml.2.0 missing」 | 缺少相依套件，從商店下載站補上 | 那是套件**沒裝**；我們是裝了、權限不足 |
| **mrt100 系列文章**（itechguides、macmyths、techbloat） | 修復 App、重設、更新、重裝 | 通用做法；沒有講框架資料夾的權限 |
| **KB 4022522**（DCOM 10016） | 這個事件通常是良性的 | 與本案例無關，只是我們一度被它誤導 |

## 五、為什麼公開的解法在這個案例失效

不是這些做法本身有錯，而是它們各自假設了一個「原因」，而本案例的原因不在其中，又沒有任何一個做法會先檢查「**誰被拒絕、拒絕什麼路徑**」。

| 常見建議 | 它假設什麼 | 本案例為什麼不成立 | 少了什麼診斷資訊 |
|---|---|---|---|
| `wsreset`、清 Store 快取 | 快取壞了 | 啟動鏈在更前面就失敗 | 事件 5961、57、61 的內容 |
| 重設或重新註冊 App | App 的註冊壞了 | `Get-AppxPackage` 是 `Ok`；註冊本來就沒問題 | App 之外的相依（框架）有沒有問題 |
| `sfc`、`DISM` | 系統檔案或元件存放區壞了 | 掃描結果全部正常 | — |
| 重設此電腦、就地升級 | 殘留的設定壞了 | 重設後症狀一樣，代表缺口在映像或權限結構 | 重設前後的對照 |
| 重新註冊全部套件 | 套件狀態壞了 | 狀態變 `Installed`，權限不變 | 「安裝狀態」與「資料夾權限」是兩件事 |
| 還原 `WindowsApps` 預設權限 | 有人改壞權限 | 條目從來沒有，不是被改壞 | 與正常 App 資料夾的權限對照 |
| 補 ALL APPLICATION PACKAGES（KB 2798317） | AAP 缺在標準位置 | 標準位置都有；缺的是框架資料夾的 `Users` | 檢查的身分是誰（一般使用者還是沙箱） |
| 以管理員身分執行 | 權限不夠 | App 啟用用的是未提升的權杖 | 為什麼管理員視窗的權限與 App 啟動不同 |

**共通的缺口：** 沒有一個建議要求先用 Process Monitor 看 `ACCESS DENIED`。我們也是在第三個階段才做，而那是整個案例裡唯一找到根因的方法。

## 六、搜尋關鍵字庫

刻意寫得很長，按「你會怎麼描述它」分類。包含我們最開始用的說法。

### 6.1 日常症狀（繁體中文）

- 重設此電腦之後 Microsoft Store 打不開
- 重設之後 內建 App 全部未安裝
- 雲端下載重設 還是一樣 App 打不開
- Windows 10 重設後 所有內建程式 閃退
- 內建程式 全部無法使用 都顯示未安裝
- Microsoft Store 打開就閃退
- Microsoft Store 閃退 重設無效
- 計算機 打不開 閃退
- 小算盤 閃退 Windows 10
- 相片 計算機 鬧鐘 打不開
- 開始功能表 磚塊 點了沒反應
- 開始功能表 App 一閃而過
- Windows 10 UWP 應用程式 全部無法開啟
- 內建 App 只有 Edge 能用
- Armoury Crate 閃退
- 設定 應用程式 Microsoft Store 大小 0 位元組
- 新增使用者帳號 一樣打不開 Store
- sfc DISM 都正常 但 App 打不開
- wsreset 沒用
- 重新註冊 Store 沒用
- 就地升級 沒用 Store 還是打不開
- Get-AppxPackage 顯示 Ok 但是打不開
- 存取被拒 Start-Process ms-windows-store
- Microsoft Store 開了一直轉圈 初始化

### 6.2 日常症狀（English）

- Microsoft Store won't open after Reset this PC
- Windows 10 cloud download reset built-in apps not working
- all UWP apps crash on launch Windows 10
- Calculator won't open Windows 10 flashes and closes
- Microsoft Store crashes immediately Windows 10 22H2
- Start menu tiles click nothing happens apps close instantly
- Get-AppxPackage Status Ok but app won't launch
- Start-Process ms-windows-store: access denied
- Windows 10 apps open then close immediately
- built-in apps missing "not installed" after reset
- Store stuck on loading spinner after fixing
- Armoury Crate crashes along with Microsoft Store
- sfc DISM clean but UWP apps still crash

### 6.3 事件與訊息（繁體中文系統）

「逐字」表示直接取自使用者貼出的輸出；「整理」表示依輸出整理，關鍵詞是原文，標點可能略有差異。

- 逐字：`Microsoft.WindowsStore_8wekyb3d8bbwe!App 啟用失敗。錯誤碼: 存取被拒。。啟用階段: COM ActivateExtension`
- 逐字：`Microsoft.WindowsCalculator_8wekyb3d8bbwe!App 啟用失敗。錯誤碼: 應用程式未啟動。。啟用階段: COM ActivateExtension`
- 逐字：`AppExecutionAlias 目錄遺失，錯誤碼為 0x8007010B。`
- 逐字：`套件 Microsoft.WindowsStore_22609.1401.6.0_neutral_~_8wekyb3d8bbwe 的 AppX 部署操作失敗，錯誤為 0x80070005。此失敗的特定錯誤文字是:`
- 逐字：`Windows 無法執行 StageUserData 操作，因為在存放庫中找不到 aimgr_0.20.61.0_x64__8wekyb3d8bbwe。`
- 逐字：`'aimgr_8wekyb3d8bbwe' install 失敗。錯誤: '找不到套件。'`（AppReadiness 214）
- 逐字：`部署失敗，HRESULT 為: 0x80073CF3, 套件無法進行更新、相依性或衝突驗證。Windows 無法安裝套件 Microsoft.WindowsStore，因為已提供套件 Microsoft.NET.Native.Runtime.1.7 但並未被使用。`
- 逐字：`電腦預設 權限設定無法將含有 CLSID {C2F03A33-21F5-47FA-B4BB-156362A2F239} 與 APPID {316CDED5-E4AE-4B15-9113-7055D84DCC97} 之 COM 伺服器應用程式的 本機 啟用 權限授與`（DCOM 10016）
- 逐字：`您需要新的應用程式才能開啟此 ms-windows-calculator 連結`
- 整理：`抓取套件 Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe 資料夾的信任狀態失敗，狀態 2147942405`（事件 57）
- 整理：`無法建立套件 Microsoft.WindowsStore_22609.1401.6.0_x64__8wekyb3d8bbwe 的處理程序，因為執行完整性檢查…存取被拒（0x5）`（事件 61）
- 整理（使用者描述）：`找不到 mrt100_app.dll`、`找不到 SharedLibrary.dll`
- 關鍵詞：`PrerequisitesChecked`（事件 605）、`StageUserData`、`AppExecutionAlias`、`aimgr`

### 6.4 事件與訊息（English）

依中文訊息翻譯者標「譯」，不是 Windows 英文版原文。

- `AppModel-Runtime event 57 failed to get trust state of package folder … status 2147942405`（譯）
- `AppModel-Runtime event 61 cannot create process for package because an error occurred during integrity check access denied`（譯）
- `Microsoft-Windows-TWinUI/Operational 5961 activation failed COM ActivateExtension access denied`
- `Activation of the app for the Windows.Launch contract failed with error: The app didn't start.`（原文，來源 HelpDeskGeek）
- `ErrorCode -2144927141 PhaseFlags 34`
- `Microsoft-Windows-Immersive-Shell 5961`（事件的提供者名稱）
- `PrerequisitesChecked deployment failed 0x80070005`
- `0x80073D02 package could not be installed because resources it modifies are currently in use`
- `framework package folder ACL missing BUILTIN\Users`
- `svchost.exe impersonating user ACCESS DENIED CreateFile WindowsApps`
- `READ_CONTROL denied WindowsApps package folder`
- `takeown /a /r /d y icacls grant *S-1-5-32-545:(OI)(CI)(RX) WindowsApps`

### 6.5 錯誤碼

| 十六進位 | 十進位 | 意思（依訊息與一般文件，非完整官方對照） | 本案例出現在哪 |
|---|---|---|---|
| `0x80070005` | `2147942405` | 存取被拒（`E_ACCESSDENIED`） | 事件 57、404／401、5961 |
| `0x8027025B` | `-2144927141` | 「應用程式未啟動」／"The app didn't start" | 5961，主因 B |
| `0x80073D02` | `2147957506` | 套件修改的資源目前使用中 | x64 .NET Native `Register`，Gaming Services 占用 |
| `0x80073D04` | | 簽章無效（訊息）。實際是相依資料夾讀不到（`0x80070005`） | ScreenSketch、錄音機等 |
| `0x80073CF3` | | 相依、更新或衝突驗證失敗 | Microsoft-Store-Fix 強塞 Framework 1.7 |
| `0x80073CF9` | | 安裝失敗；套件已暫停 | 鬧鐘的重試 |
| `0x80073CF1` | | 找不到套件 | `StageUserData` |
| `0x8007010B` | | 目錄名稱無效 | `AppExecutionAlias` |
| `0x80070525`、`0x80070520` | | 使用者不存在、登入工作階段不存在 | Store 的權杖錯誤 |
| `0x800F0984` | | 元件修補失敗 | `MicrosoftAccount.TokenProvider.Core` |
| `0x80070015` | | 裝置尚未就緒 | 早期統計 |
| `0x8007000D` | | 資料無效 | 早期統計 |
| `0x80070057` | | 參數錯誤 | 早期統計 |
| `0x80070490` | | 找不到項目 | 早期統計 |
| `0x80070002` | | 找不到檔案 | 早期統計 |
| `0xc000027b` | | App 崩潰（KB 2798317 的症狀 2） | 本案例沒有出現 |
| `0x80040904` | | COM App 啟用錯誤 | 搜尋結果中別人的案例，不是我們的 |

### 6.6 套件、檔案與記錄名稱

`Microsoft.UI.Xaml.2.8`、`Microsoft.UI.Xaml.2.7`、`Microsoft.UI.Xaml.2.0`、`Microsoft.VCLibs.140.00`、`Microsoft.VCLibs.140.00.UWPDesktop`、`Microsoft.NET.Native.Framework.2.2`、`Microsoft.NET.Native.Runtime.2.2`、`Microsoft.WindowsAppRuntime.1.8`、`Microsoft.GamingServices`、`Microsoft.WindowsStore`、`Microsoft.WindowsCalculator`、`Microsoft.WindowsAlarms`、`Microsoft.WindowsCamera`、`Microsoft.MicrosoftStickyNotes`、`Microsoft.Windows.Photos`、`Microsoft.MicrosoftEdge.Stable`、`CalculatorApp.exe`、`WinStore.App.exe`、`mrt100_app.dll`、`SharedLibrary.dll`、`vcruntime140_app.dll`、`AppxManifest.xml`、`AppxSignature.p7x`、`AppxBlockMap.xml`、`CodeIntegrity.cat`、`StateRepository-Machine.srd`、`StateRepository-Deployment.srd`、`C:\Program Files\WindowsApps`、`C:\ProgramData\Microsoft\Windows\AppRepository`、`Microsoft-Windows-AppModel-Runtime/Admin`、`Microsoft-Windows-TWinUI/Operational`、`Microsoft-Windows-AppXDeploymentServer/Operational`、`Microsoft-Windows-AppReadiness/Admin`、`Microsoft-Windows-Store/Operational`、`Microsoft-Windows-CodeIntegrity/Operational`、`AppxDeploymentFailureBlue`、`StoreAgentInstallFailure1`

### 6.7 工具與指令

`takeown /f /a /r /d y`、`icacls /grant *S-1-5-32-545:(OI)(CI)(RX) /T /C`、`icacls /save`、`icacls /restore`、`icacls /reset`、`icacls /setowner`、`icacls /remove:g`、`Get-AppxPackage -AllUsers`、`Get-AppxPackage -Name`、`Add-AppxPackage -DisableDevelopmentMode -Register`、`Remove-AppxPackage`、`Get-AppxProvisionedPackage -Online`、`Get-WinEvent -LogName`、`Process Monitor`、`Procmon`、`PsExec -s`、`gpresult /h`、`DISM /Online /Cleanup-Image /ScanHealth`、`sfc /verifyonly`、`Repair-Volume -Scan`、`Get-PhysicalDisk`、`mdsched.exe`、`winget install`、`restore-appx`、`Microsoft-Store-Fix`、`Pester`、`Get-Acl`、`whoami`、`Is64BitProcess`

### 6.8 硬體與環境

Windows 10 專業版 22H2、build 19045、`10.0.19045.3803`、華碩主機板、Armoury Crate、Intel Graphics Command Center、Realtek Audio Control、WDC WDS500G2B0C SSD、FlClash（代理軟體）

### 6.9 早期階段的說法（我們一開始搜的）

這些是在還不知道原因時，我們用過或想到的搜尋方向。把它們也列出來，是因為遇到問題的人一開始也會這樣搜：

- Windows 10 專業版 10.0.19045 雲端重設 內建 App 損壞 0x80070005
- 雲端重設後 內建 App 顯示未安裝 打不開
- 事件紀錄 反覆出現 0x80070005 存取被拒
- AppxDeploymentFailureBlue
- StoreAgentInstallFailure1
- 0x800F0984 MicrosoftAccount.TokenProvider.Core 元件存放區損壞
- icacls WindowsApps 權限 正常 App 還是打不開
- 服務都在執行 WindowsApps 資料夾存在 Get-AppxPackage 都是 Ok
- Windows 10 Store 重設 疑難排解 Windows 市集應用程式 無效
- PowerShell 重新註冊計算機 無效

## 七、GitHub 發佈建議

**Repository 名稱：** `windows10-store-apps-wont-open-after-reset`

為什麼這樣取：

- 用一般人描述問題的說法，最容易被搜尋到，也看得懂。
- 技術縮寫與錯誤碼不放進名稱：名稱太長、太冷僻，一般人不會搜。技術細節放在 Description、Topics 與 README，讓有技術背景的人也找得到。
- 不用 `fix`、`solved`、`100-working` 這類字。這個修復只在一台機器驗證過，而且我們想和那些一行指令就說「已解決」的教學文章區隔開來：這個 repo 的重點是**診斷過程與證據**。

**Description（About 欄位，一行）：**

> 診斷紀錄：Windows 10 重設後 Store 與內建 App 全部打不開，主因是框架資料夾缺 BUILTIN\Users 權限（AppModel-Runtime 57/61、5961、0x80070005）。含證據、判斷方法與修復 | Why Store and built-in apps won't open after Reset this PC: a diagnostic record

**Topics：** `windows-10`、`microsoft-store`、`uwp`、`appx`、`msix`、`windowsapps`、`appmodel`、`troubleshooting`、`icacls`、`takeown`、`procmon`、`process-monitor`、`access-denied`、`0x80070005`、`dotnet-native`、`ui-xaml`、`vclibs`、`event-viewer`、`powershell`、`zh-tw`

**讓搜尋引擎與 AI 找得到：**

- 事件與訊息的**原文**放在程式碼區塊或行內程式碼中，不要改寫。
- 標題與第一段要包含症狀的日常說法與錯誤碼。
- 保留英文摘要與英文關鍵字。
- 發佈後，用第 6 節的幾條原文去搜尋，確認有被收錄。搜尋引擎收錄需要時間，可能要幾天到幾週。
- 考慮在 Microsoft Q&A、Reddit、PTT、巴哈姆特等討論區，附上連結回覆類似的提問（請遵守各站規則，不要洗版）。
