# Windows 10 重設後，Microsoft Store 與內建 App 全部打不開

AppModel-Runtime 事件 57／61、TWinUI 事件 5961、`0x80070005` 存取被拒、「應用程式未啟動」`0x8027025B` 的完整排查紀錄、主因與修復

- **狀態**：在一台機器上修好：Microsoft Store、計算機、相片已實際開啟確認；鬧鐘、便利貼、相機只確認修復腳本跑完，**尚未實際開啟**。**尚未在其他機器驗證**
- **系統**：Windows 10 專業版 22H2，build 19045。發生在「重設此電腦（雲端下載、全部移除）」之後
- **期間**：2026-10-24 至 2026-10-29（台灣時間，UTC+8）
- **參與者**：使用者、Claude（Anthropic）、Grok（xAI）。每一段分析都標明出自誰，見 [08](docs/08-who-said-what.md)
- **修復涉及**：`C:\Program Files\WindowsApps` 底下的資料夾權限。動手前請先讀 [4.0](#40-開始之前)
- **授權**：文件（`README.md` 與 `docs/`）採 CC BY 4.0，見 [LICENSE](LICENSE)；腳本與工具（`scripts/`、`tools/`）採 MIT，見 [LICENSE-CODE](LICENSE-CODE)。GitHub 側欄會同時列出這兩個授權。版權 © 2026 contributors

## 先看這裡（30 秒版）

- **發生了什麼**：重設之後，Store、計算機、相片、鬧鐘、相機、便利貼，連主機板廠商的 Armoury Crate 都一樣：點下去閃一下就消失，或在設定裡顯示未安裝。系統檔案、磁碟、記憶體檢查都正常，`Get-AppxPackage` 還說它們是 `Ok`
- **主因**：兩層權限缺口。**錯誤 A**：App 依賴的「框架資料夾」（`WindowsApps` 底下的 `Microsoft.UI.Xaml.2.8`、`Microsoft.NET.Native.Framework.2.2`、`Microsoft.VCLibs.140.00` 等）沒有給 `BUILTIN\Users` 任何權限條目，系統用你的身分去檢查它時被拒，App 連程序都建立不了。**錯誤 B**：A 補好後，依賴 .NET Native 的 App 仍起不來，因為 App 在沙箱裡讀不到框架的 DLL，另外 x64 的 .NET Native 套件曾被 Gaming Services 占住而註冊不上
- **怎麼確認跟我一樣**：看事件 57／61／5961，對照框架資料夾與正常 App 資料夾的權限，再用 Process Monitor 抓 `ACCESS DENIED`。完整八項檢查見 [三](#三怎麼判斷是不是跟我一模一樣)
- **怎麼修**：對被指到的框架資料夾：備份權限 → `takeown /a /r /d y` → `icacls /grant *S-1-5-32-545:(OI)(CI)(RX)`。B 再加 ALL APPLICATION PACKAGES、註冊框架、清 App 的使用者資料。完整步驟見 [四](#四怎麼解決)

## English summary

On Windows 10 Pro 22H2 (build 19045), after *Reset this PC → Cloud download → Remove everything*, Microsoft Store, Calculator and other built-in UWP apps flash and close, or show as "not installed". `Get-AppxPackage` reports `Status: Ok`, the AppX-related services are in their normal states, and `sfc`, `DISM /ScanHealth`, disk and memory checks are clean. `Start-Process ms-windows-store:` fails with *Access is denied*. Event Viewer shows `Microsoft-Windows-AppModel-Runtime/Admin` events **57** and **61** and `Microsoft-Windows-TWinUI/Operational` event **5961** (`COM ActivateExtension`).

**Problem A.** Process Monitor, filtered only on `Result is ACCESS DENIED` (no process filter), showed `svchost.exe`, impersonating the logged-on user, being denied `READ_CONTROL` on the dependency (framework) package folders under `C:\Program Files\WindowsApps`: first `Microsoft.UI.Xaml.2.8`, then `Microsoft.NET.Native.Framework.2.2` and `Microsoft.VCLibs.140.00` (x64). Those folders had no `BUILTIN\Users` ACE. After `takeown /a /r` and `icacls ... /grant *S-1-5-32-545:(OI)(CI)(RX)`, the Store started. Each fix exposed the next blocked framework: the denial moved down the dependency chain.

**Problem B.** Calculator, Clock, Camera and Sticky Notes still failed with event 5961 `ErrorCode -2144927141` (`0x8027025B`, English text "The app didn't start"). They depend on .NET Native; Photos and the Store do not. Running `CalculatorApp.exe` directly showed missing `mrt100_app.dll` and `SharedLibrary.dll`; Procmon showed `CalculatorApp.exe` denied reading `vcruntime140_app.dll` in the VCLibs folder. The x64 .NET Native packages also could not be registered (`0x80073D02`, package in use) while `Microsoft.GamingServices` was running. A script that took ownership of ten framework folders, granted Users, ALL APPLICATION PACKAGES and Administrators, registered the frameworks, moved the apps' user data aside and re-registered Calculator fixed it. The individual contribution of each step was **not isolated**.

**Third factor.** The Store window stuck on "initializing" until the proxy client (FlClash) was turned off.

**Why an administrator account is denied (inference).** Apps are activated with the user's non-elevated token, in which the Administrators group is deny-only, so an elevated PowerShell window proves nothing about what the activation path can read.

Searching in English and Traditional Chinese found nothing that matched this mechanism (see [09](docs/09-search-notes-and-keywords.md)). This repository records the whole process, including wrong turns, so that people and AI assistants searching for these event IDs and messages can find it.

## 一、發生了什麼

### 1.1 我們的情況

| 項目 | 內容 |
|---|---|
| 系統 | Windows 10 專業版 22H2，build 19045 |
| 觸發 | 「重設此電腦」→ 雲端下載 → 全部移除。重設前就已經有同樣的症狀，重設之後**一模一樣** |
| 帳號 | 一個管理員帳號。另建的 `test` 帳號症狀相同 |
| 硬體 | 華碩主機板、SSD。磁碟、記憶體檢查都正常 |
| 之前做過的事 | `sfc`、`DISM`、重新註冊、`wsreset`、離線安裝、Media Creation Tool 就地升級、重設 |

詳細環境與已排除項目見 [01](docs/01-environment-and-symptoms.md)。

### 1.2 你會看到的現象

**A. 使用者眼中的現象**

- 開始功能表的磚塊都在，點下去視窗閃一下就消失。
- 「設定 → 應用程式」裡，這些 App 顯示未安裝，或大小是 0 位元組。
- 新建的帳號一樣。
- 主機板廠商附的 App（Armoury Crate）一樣。
- 在系統管理員 PowerShell 輸入 `Start-Process 'ms-windows-store:'`，得到「無法執行這個命令，因為發生錯誤: 存取被拒」。

**B. 看起來正常的地方（這些會誤導你）**

- `Get-AppxPackage Microsoft.WindowsStore` 顯示 `Status : Ok`，`InstallLocation` 也存在。
- AppX 相關服務的啟動類型都是預設值（`AppXSvc`、`ClipSVC` 是手動／觸發式，平常停止，不是異常）。
- `sfc /verifyonly` 沒有違規；`DISM /ScanHealth` 沒有損毀；磁碟與記憶體診斷通過。
- 沒有群組原則；Windows 安全性沒有任何封鎖紀錄。

### 1.3 系統記錄裡的現象

| 記錄 | 事件 | 內容（繁體中文系統原文，括號內為翻譯） |
|---|---|---|
| `Microsoft-Windows-AppModel-Runtime/Admin` | 57 | 抓取套件 `Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe` 資料夾的信任狀態失敗，狀態為 2147942405。（失敗，狀態 `0x80070005`） |
| 同上 | 61 | 0x5: 無法建立套件 `Microsoft.WindowsStore_…` 的處理程序，因為執行完整性檢查時發生錯誤。存取被拒。 |
| `Microsoft-Windows-TWinUI/Operational` | 5961 | `Microsoft.WindowsStore_8wekyb3d8bbwe!App` 啟用失敗。錯誤碼: 存取被拒。啟用階段: COM ActivateExtension |
| 同上（A 修好之後的計算機） | 5961 | `Microsoft.WindowsCalculator_8wekyb3d8bbwe!App` 啟用失敗。錯誤碼: 應用程式未啟動。啟用階段: COM ActivateExtension（`ErrorCode = -2144927141`、`PhaseFlags = 34`） |

數字換算：`2147942405` = `0x80070005`（存取被拒）；`-2144927141` = `0x8027025B`（英文訊息「The app didn't start」）。

**關於原文：** 5961 的訊息是逐字原文。事件 57、61 的訊息是依輸出整理的，其中「信任狀態」「完整性檢查」「存取被拒」「2147942405」與套件名稱是原文用字，標點與助詞可能略有差異。

### 1.4 網路上常見的做法，在這個案例都沒有用

`wsreset`、重設單一 App、重新註冊 Store 或全部 App、`sfc /scannow`、`DISM /RestoreHealth`、重設此電腦、Media Creation Tool 就地升級、離線安裝 `msixbundle`、重裝框架 appx、restore-appx 工具。原因見 [07](docs/07-wrong-turns-and-side-effects.md)：這些做法都不會補上框架資料夾缺少的權限條目。

## 二、為什麼會這樣（主因）

### 2.1 先弄清楚三件事

名詞的完整解釋見 [00](docs/00-glossary.md)，這裡只講理解主因需要的三件。

1. **框架套件。** Windows 的 App（UWP／MSIX 格式）不會把共用的程式庫帶在自己身上。它依賴另外安裝的「框架套件」：`Microsoft.UI.Xaml`（介面元件）、`Microsoft.VCLibs`（C++ 執行階段）、`Microsoft.NET.Native`（.NET 執行階段）等。每個框架套件的檔案放在 `C:\Program Files\WindowsApps\<套件名稱>` 的一個資料夾裡。
2. **權限條目（ACE）。** 每個資料夾有一份清單，寫著哪些帳號或群組可以對它做什麼。清單沒有寫到的對象，就不能碰它。`BUILTIN\Users` 是「這台電腦上的一般使用者」這個群組。
3. **安裝狀態與資料夾權限是兩回事。** `Staged` 表示檔案放好了、還沒登記給任何使用者；`Installed` 表示已登記給某個使用者。把狀態從 `Staged` 改成 `Installed`，不會補上資料夾的權限條目。

### 2.2 啟動一個 App 時，系統做了哪些事

這是依我們的觀察推得的流程，**不是微軟文件**：

1. 你點磚塊。殼層（開始功能表、檔案總管）要求系統「啟用」這個 App。事件 5961 就是這一步失敗時記的。
2. 系統讀 App 的清單檔，找出它依賴哪些框架套件。
3. 系統服務（`svchost.exe` 裡的 AppX 相關元件）**以你的帳號身分**，開啟每一個依賴的框架資料夾，檢查它的信任狀態與完整性。事件 57、61 就是這一步失敗時記的。
4. 檢查通過，系統才建立 App 的程序，並把它放進沙箱（AppContainer）。
5. App 程序在沙箱裡載入它需要的 DLL：自己的，和框架資料夾裡的。
6. 載入成功，視窗出現。

### 2.3 錯誤 A：第 3 步被拒

這台機器的框架資料夾，權限清單只有從上層 `WindowsApps` 繼承來的條目：TrustedInstaller 與 SYSTEM 完全控制；Administrators 只能讀，而且只適用於子資料夾；LOCAL SERVICE、NETWORK SERVICE 等服務帳號可以讀。**清單裡沒有 `BUILTIN\Users`。**

對照一個能正常啟動的 App（Edge、計算機、Store）：它的資料夾有 `BUILTIN\Users`、ALL APPLICATION PACKAGES、受限應用程式封包，還有套件專屬的能力 SID。

所以第 3 步，系統以你的身分去開框架資料夾，連「讀取權限設定」都被拒。檢查失敗，第 4 步不會發生：**App 的程序從來沒有被建立**。這就是 5961 寫「存取被拒」、而且閃退得這麼快的原因。

證據：Process Monitor 抓到 `svchost.exe` 以 `Impersonating: <電腦>\<使用者>` 開啟 `microsoft.ui.xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe`，結果 `ACCESS DENIED`，時間與三次點擊吻合。補上 `BUILTIN\Users` 之後再抓，這個拒絕消失，下一個框架出現。最後所有 x64 框架補完，Store 開啟。完整證據鏈見 [03](docs/03-root-cause-a-framework-folder-acl.md)。

### 2.4 為什麼管理員帳號也會被擋

這是**推論**，我們沒有另外驗證。

Windows 開啟 UAC（使用者帳戶控制）時，管理員帳號平常用的是「未提升的權杖」。這個權杖裡，Administrators 群組只用來**拒絕**，不能用來**允許**存取。App 的啟用走的是你平常登入的這個權杖，不是你按「以系統管理員身分執行」開出來的視窗。

所以「Administrators 可以讀」這一條，對 App 啟動時的檢查沒有幫助。能幫上忙的只有直接寫給 `BUILTIN\Users` 的條目。

這也解釋了我們一度卡住的想法：「我已經提權了，為什麼還被拒？」提權視窗的權限，與 App 啟動時用的身分，不是同一回事。

### 2.5 錯誤 B：第 5 步讀不到

A 補好之後，Store 開了，但計算機、鬧鐘、相機、便利貼還是不行。5961 的錯誤碼從「存取被拒」變成「應用程式未啟動」，57 與 61 不再出現，代表第 3 步已經過了。

這幾個 App 依賴 .NET Native；Store 與相片不依賴。直接在安裝資料夾執行 `CalculatorApp.exe`，程序起得來，但跳出系統對話框：找不到 `mrt100_app.dll` 與 `SharedLibrary.dll`。Process Monitor 顯示 `CalculatorApp.exe` 讀 VCLibs 資料夾裡的 `vcruntime140_app.dll` 被拒。

DLL 檔案在，但 App 在沙箱裡**讀不到**，系統把「讀不到」報成「找不到」。沙箱程式的身分是 AppContainer，不是一般使用者，所以 A 補的 `BUILTIN\Users` 對它沒有用，需要 ALL APPLICATION PACKAGES（所有應用程式套件）或套件專屬的條目。

另外還有兩件事疊在一起：

- x64 的 `Microsoft.NET.Native.Framework.2.2` 與 `Runtime.2.2` 做 `Register` 時回 `0x80073D02`（套件修改的資源目前已在使用中）。使用者輸出顯示 `gamingservices` 程序在執行。停掉它、對目前使用者移除 `Microsoft.GamingServices` 之後，`Register` 才成功。
- 修復腳本還把 App 的使用者資料夾改名備份，再重新註冊。這一步有沒有必要，我們沒有證據。

### 2.6 第三個因素：代理軟體

Store 能啟動之後，視窗停在載入畫面。使用者關閉代理軟體 FlClash，Store 就恢復。機制沒有查證（系統代理、TUN 模式還是 WinHTTP 代理，我們沒有分辨）。這個問題長得像「權限還沒修完」，很容易誤判。

### 2.7 我們確定的與不確定的

| 確定（有直接證據） | 不確定 |
|---|---|
| Procmon 顯示 `svchost.exe` 以使用者身分開框架資料夾被拒 | 為什麼這個映像的框架資料夾缺少 `BUILTIN\Users`。我們沒有健康機器的框架資料夾可以對照 |
| 補 `BUILTIN\Users` 後，該框架的拒絕消失，下一個框架出現 | 錯誤 B 的修復腳本是多步驟一起做的，哪一步是關鍵沒有分離 |
| 所有 x64 框架補完，Store 開啟，57／61 消失 | 為什麼重設後第一次登入的部署（13:02）就失敗：是這個缺口造成，還是別的原因先造成缺口 |
| 5961 的錯誤碼在 A 修好後變成 `-2144927141` | 「管理員也被拒」的 UAC 權杖解釋 |
| 修復腳本跑完，`CalculatorApp` 程序出現 | 其他機器是否相同 |
| 關閉代理軟體後，Store 不再停在初始化 | Gaming Services 占用是否是 x64 .NET Native 註冊的必要條件 |

## 三、怎麼判斷是不是跟我一模一樣

下面八項，**越多項符合，越可能是同一個問題**。第 4、6、7 項最關鍵。更詳細的版本（含每項看不到時代表什麼）見 [05](docs/05-is-it-the-same-problem.md)。

先用管理員身分開 PowerShell：開始功能表輸入 `PowerShell` → 右鍵「Windows PowerShell」→「以系統管理員身分執行」。**不要用 PsExec 開的 SYSTEM 視窗。**

### 檢查 1：時機與版本

- Windows 10 或 11？build 是多少？`winver` 可以看。
- 問題是在「重設此電腦」之後出現，還是更新、清理軟體、改權限之後出現？
- 一模一樣：重設之後出現，且重設前的症狀相同。

### 檢查 2：App 顯示已安裝，卻打不開

```powershell
Get-AppxPackage Microsoft.WindowsStore | Format-List Name, Version, Status, InstallLocation
```

- 一模一樣：`Status : Ok`，`InstallLocation` 指向 `C:\Program Files\WindowsApps\…`。

### 檢查 3：啟動時的錯誤

```powershell
Start-Process 'ms-windows-store:'
```

- 一模一樣：回「存取被拒」。
- 注意：這要在**你自己的**系統管理員視窗做。SYSTEM 視窗啟動 `ms-windows-calculator:` 會跳「您需要新的應用程式才能開啟此連結」，那是測試環境的問題。

### 檢查 4：事件 57、61、5961（關鍵）

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-AppModel-Runtime/Admin' -MaxEvents 200 |
  Where-Object { $_.Id -in 57,61 } | Select-Object TimeCreated, Id, Message | Format-List

Get-WinEvent -LogName 'Microsoft-Windows-TWinUI/Operational' -MaxEvents 500 |
  Where-Object { $_.Id -eq 5961 } | Select-Object TimeCreated, Message | Format-List
```

- 一模一樣（A）：57 指到一個**框架**套件（`Microsoft.UI.Xaml.*`、`Microsoft.VCLibs.*`、`Microsoft.NET.Native.*`），狀態 2147942405；61 說完整性檢查存取被拒；5961 的錯誤碼是存取被拒。
- 看不到 57／61：不是錯誤 A。

### 檢查 5：框架套件的安裝狀態

```powershell
Get-AppxPackage -AllUsers | Where-Object { $_.IsFramework } |
  Select-Object Name, Architecture, @{n='狀態';e={ ($_.PackageUserInformation | ForEach-Object { [string]$_ }) -join ' | ' }}
```

- 這台的現象：很多框架只有 `S-1-5-18: Staged`（SYSTEM），沒有使用者的 `Installed`。**這不是必要條件**：我們把它們註冊成 `Installed` 之後症狀完全沒變，所以只當作旁證。

### 檢查 6：框架資料夾與正常 App 資料夾的權限對照（關鍵）

```powershell
$ok  = (Get-AppxPackage Microsoft.WindowsCalculator).InstallLocation
$bad = (Get-AppxPackage -Name Microsoft.UI.Xaml.2.8 | Select-Object -First 1).InstallLocation
icacls $ok
icacls $bad
```

- 一模一樣：`$ok` 的輸出有 `BUILTIN\Users:` 的行；`$bad`（框架）**沒有**。
- 非英文系統的名稱不同，認 SID：Users 是 `S-1-5-32-545`。
- 也可以用 [`scripts/Detect-FrameworkFolderAcl.ps1`](scripts/Detect-FrameworkFolderAcl.ps1) 一次檢查全部框架（唯讀）。

### 檢查 7：Process Monitor（決定性）

這一項能直接看到「誰被拒絕、拒絕什麼路徑」。步驟見 [4.1](#41-找出要修的資料夾)。

- 一模一樣：`ACCESS DENIED` 的紀錄裡，`svchost.exe`、`CreateFile`、路徑在 `C:\Program Files\WindowsApps\<框架套件>`，`Detail` 欄有 `Impersonating: <電腦>\<使用者>`。

### 檢查 8：修好 A 之後，是否進入 B

- 一模一樣：Store 能開了，但部分 App 仍打不開；5961 的 `ErrorCode` 變成 `-2144927141`；57、61 沒有了；打不開的 App 都依賴 .NET Native（相片、Store 能開）。

### 結果對照

| 符合哪幾項 | 判斷 | 去哪裡 |
|---|---|---|
| 4、6、7 都符合 | 錯誤 A | [4.2](#42-修復錯誤-a) |
| A 修好後 8 符合 | 加上錯誤 B | [4.4](#44-修復錯誤-b) |
| Store 能開但一直轉圈 | 代理軟體或網路 | [4.6](#46-store-一直轉圈) |
| 只有第 2、3 項符合，沒有 57／61 | 不是這個問題 | 看下表 |

### 看起來像、但不是同一個問題的情況

| 你看到的 | 可能是什麼 | 做法 |
|---|---|---|
| 5961 的錯誤碼是 `0xc000027b`，或 Application 記錄有事件 1000 崩潰 | 官方 KB 2798317 描述的：預設權限被改（`ALL APPLICATION PACKAGES` 缺少） | 對照 KB 2798317 |
| 只有「安裝」時失敗：`0x80073CF3`、`0x80073CF9`、`0x80073D02` | 套件相依、衝突、占用。這是部署問題，不是啟動問題 | 看 [06](docs/06-fix-step-by-step.md) 的訊息對照 |
| Store 能開，但出現 `0x80131500` 或連線錯誤 | 網路、時間、代理 | 關代理、校時 |
| 你曾自己改過 `WindowsApps` 的權限，之後 App 打不開 | 與本案例相反：你把權限弄壞了。網路上「還原預設權限」的教學適用 | **小心**：`icacls /reset` 會移除我們補上的 `Users` 條目，見 [4.8](#48-還原與注意事項) |
| DistributedCOM 10016 | 在正常的 Windows 上也常見，通常是雜訊 | 不用處理 |

## 四、怎麼解決

### 4.0 開始之前

**你需要**

- 自己的管理員帳號，約 30 到 60 分鐘。
- Process Monitor（微軟 Sysinternals 的工具，要自己從 Microsoft 的 Sysinternals 頁面下載）。
- 一個 64 位元的系統管理員 PowerShell。

**風險**

- 你要改的是 `WindowsApps` 底下的資料夾權限。改錯可能讓更多 App 打不開。
- **一次只改被指到的資料夾**。**不要**對整個 `C:\Program Files\WindowsApps` 做 `takeown /r`、`icacls /T`、`icacls /reset` 或 `/setowner`。
- 先備份權限，下面每個步驟都有備份。
- 這個修復只在一台機器驗證過。

**確認你開對了視窗**

```powershell
whoami                                    # 應該是 <電腦名稱>\<你的帳號>，不是 nt authority\system
[Environment]::Is64BitProcess             # 應該是 True
```

**建議：先建立還原點（選用）**

```powershell
Checkpoint-Computer -Description "before-framework-acl" -RestorePointType MODIFY_SETTINGS
```

「系統保護」沒開時會失敗，這不影響後面的步驟。

### 4.1 找出要修的資料夾

三種方法，由快到準：

**方法 1：從事件 57 取得第一個。** 事件訊息裡的套件完整名稱，就是第一個要修的框架，例如 `Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe`。取得資料夾路徑：

```powershell
Get-AppxPackage -AllUsers -Name Microsoft.UI.Xaml.2.8 | Select-Object Architecture, InstallLocation
```

**方法 2：用偵測腳本。** [`Detect-FrameworkFolderAcl.ps1`](scripts/Detect-FrameworkFolderAcl.ps1) 會列出全部框架資料夾，標出缺 `BUILTIN\Users` 的（唯讀，不改任何東西）。

**方法 3：用 Process Monitor（最準，我們靠這個找到根因）。**

1. 用**你自己的帳號**開的系統管理員身分，執行 Process Monitor。
2. 按 `Ctrl+L` 開篩選器，**只加一條**：`Result` 　`is` 　`ACCESS DENIED` 　→ `Include`，按「新增」再「確定」。**不要加任何處理序名稱的條件**。我們的第一次擷取只看 `ApplicationFrameHost.exe`，完全看不到拒絕，因為拒絕發生在 `svchost.exe`。
3. 按 `Ctrl+X` 清空畫面，按 `Ctrl+E` 開始擷取。
4. 從開始功能表點壞掉的 App，閃退後馬上再點一次，總共兩到三次。
5. 按 `Ctrl+E` 停止。檔案 → 儲存 → 格式選 CSV → 範圍選「目前顯示的事件」。
6. 讀法：找 `Process Name` 是 `svchost.exe`、`Operation` 是 `CreateFile`、`Path` 在 `C:\Program Files\WindowsApps\` 底下的列。`Path` 就是下一個要修的資料夾。

### 4.2 修復錯誤 A

**對每一個被指到的框架資料夾，依序做四步。** 以下用 `Microsoft.UI.Xaml.2.8` 的 x64 為例，請換成你自己的路徑。

**步驟 1：先記下擁有者**（`takeown` 之前做）

```powershell
(Get-Acl "C:\Program Files\WindowsApps\microsoft.ui.xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe").Owner
```

預期是 `NT SERVICE\TrustedInstaller` 或 `NT AUTHORITY\SYSTEM`。寫下來，還原要用。

**步驟 2：取得擁有權**

```cmd
takeown /f "C:\Program Files\WindowsApps\microsoft.ui.xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe" /a /r /d y
```

- `/a`：把擁有者設成 Administrators 群組。
- `/r`：包含所有子資料夾與檔案。
- `/d y`：遇到沒權限列出的資料夾，預設回答「是」。
- **這一步不能省。** 沒做的話，後面幾乎全部回「存取被拒」。這些資料夾的擁有者是 TrustedInstaller 或 SYSTEM，系統管理員沒有改權限的資格，要先當擁有者才行。我們第一次嘗試就是在這裡失敗的。

**步驟 3：備份權限**（`takeown` 之後做，否則大部分檔案讀不到權限）

```cmd
icacls "C:\Program Files\WindowsApps\microsoft.ui.xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe" /save "%USERPROFILE%\acl_xaml28_x64.txt" /T /C
```

**步驟 4：給 `BUILTIN\Users` 讀取與執行**

```cmd
icacls "C:\Program Files\WindowsApps\microsoft.ui.xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe" /grant "*S-1-5-32-545:(OI)(CI)(RX)" /T /C
```

- `*S-1-5-32-545` 是 `BUILTIN\Users`。用 SID，中英文系統都適用。
- `(OI)(CI)`：讓底下的檔案與資料夾都繼承這條權限。
- `(RX)`：讀取與執行。
- `/T`：套用到所有子項目。`/C`：遇到錯誤繼續。

**成功的樣子**（輸出最後一行）：

```
已順利處理 16 個檔案; 0 個檔案處理失敗
```

**這台機器上需要處理的資料夾**（x64 與 x86 都處理）：

| 框架 | 說明 |
|---|---|
| `Microsoft.UI.Xaml.2.8` | 事件 57 第一個點名的 |
| `Microsoft.NET.Native.Framework.2.2` | Procmon 第二個冒出來的 |
| `Microsoft.VCLibs.140.00` | Procmon 第三個冒出來的 |
| `Microsoft.NET.Native.Runtime.2.2` | 一併處理 |
| `Microsoft.VCLibs.140.00.UWPDesktop` | 一併處理 |

**你的清單可能不同，以 Procmon 為準。** 想一次處理多個，用 [`scripts/Fix-FrameworkFolderAcl.ps1`](scripts/Fix-FrameworkFolderAcl.ps1)：它先報告、再逐一詢問，並自動備份與寫日誌（**尚未在其他機器驗證**）。

### 4.3 驗證 A

1. 從**你自己帳號**的開始功能表點 Store。
2. 或用 [`scripts/Test-UwpApps.ps1`](scripts/Test-UwpApps.ps1)，它看事件 5961，不靠肉眼判斷。
3. 成功的證據：`WinStore.App` 程序存在，而且 57、61 沒有新的紀錄。

```powershell
Get-Process WinStore.App -ErrorAction SilentlyContinue | Select-Object Name, Id, StartTime
```

如果仍然失敗，**再抓一次 Procmon**（4.1 方法 3）。我們的經驗是補一個、下一個冒出來；重複到 `ACCESS DENIED` 裡不再有 `WindowsApps` 底下的框架資料夾為止。

### 4.4 修復錯誤 B

**只有在 A 修好、Store 能開、卻還有 App 打不開、5961 的錯誤碼是 `-2144927141` 時才做。** 以下步驟是依修復腳本（Grok 產生，全文收錄在 [`scripts/Fix-UWP-Calculator.ps1`](scripts/Fix-UWP-Calculator.ps1)）的流程整理成「可以一步一步做、一步一步測」的版本，**不是逐字複製**。那支腳本一次做太多事（包含改擁有者、移除 Gaming Services），風險見 [04](docs/04-root-cause-b-dotnet-native.md) 的 6.5。

**步驟 B1：確認是依賴 .NET Native 的 App 在失敗**

```powershell
$p = Get-AppxPackage Microsoft.WindowsCalculator
([xml](Get-Content (Join-Path $p.InstallLocation 'AppxManifest.xml') -Raw)).Package.Dependencies.PackageDependency |
  Select-Object Name, MinVersion
```

看有沒有 `Microsoft.NET.Native.Framework.2.2`、`Microsoft.NET.Native.Runtime.2.2`。

**步驟 B2：確認 Gaming Services 有沒有占住**

```powershell
Get-Process gamingservices* -ErrorAction SilentlyContinue | Select-Object Name, Id
```

有的話，先停掉（腳本結束的是這幾個程序）：

```powershell
'GameBar','GameBarFTServer','gamingservices','gamingservicesnet','XboxGameBarWidgets','XboxPcApp','XboxPcAppFT','XboxPcTray' |
  ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force }
```

如果下一步的 `Register` 仍回 `0x80073D02`，我們當時的做法是對目前使用者移除 Gaming Services：

```powershell
Get-AppxPackage Microsoft.GamingServices | Remove-AppxPackage
```

**修好之後要玩 Xbox 或 Minecraft，必須從 Store 把 Gaming Services 裝回來。**

**步驟 B3：補框架資料夾的權限（比 A 多兩項）**

對 4.2 那一批框架資料夾，每個再做：

```cmd
icacls "<框架資料夾>" /grant "*S-1-15-2-1:(OI)(CI)(RX)" /T /C
icacls "<框架資料夾>" /grant "*S-1-5-32-544:(OI)(CI)(F)" /T /C
```

- `*S-1-15-2-1`：ALL APPLICATION PACKAGES（所有應用程式套件）。沙箱程式靠它讀框架。
- `*S-1-5-32-544`：Administrators 完全控制。**我們沒有證據它是必要的**；修復腳本給了。想最小化改動，可以先只做第一行，不行再加第二行。
- 原機器上實際做的是「Users、AAP、Administrators 三項都有」。最小必要組合沒有驗證。

**步驟 B4：註冊五個相依套件的 x64 與 x86 版本**（腳本是每個名稱先 x64、再 x86）

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

**步驟 B5：把失敗的 App 的使用者資料改名備份，再重新註冊**

```powershell
$pfn = (Get-AppxPackage Microsoft.WindowsCalculator).PackageFamilyName
$dir = Join-Path $env:LOCALAPPDATA ('Packages\' + $pfn)
if (Test-Path $dir) { Rename-Item $dir ($pfn + '.bak_' + (Get-Date -Format HHmmss)) }
$p = Get-AppxPackage Microsoft.WindowsCalculator
Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $p.InstallLocation 'AppxManifest.xml')
```

鬧鐘、便利貼、相機把 `Microsoft.WindowsCalculator` 換成 `Microsoft.WindowsAlarms`、`Microsoft.MicrosoftStickyNotes`、`Microsoft.WindowsCamera`。這一步會讓 App 的設定與歷程記錄重置。

### 4.5 驗證 B

```powershell
Start-Process 'shell:AppsFolder\Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'
Start-Sleep 8
Get-Process CalculatorApp -ErrorAction SilentlyContinue | Select-Object Name, Id, StartTime
```

有 `CalculatorApp` 程序，而且 5961 沒有新的紀錄，就是成功。我們的成功輸出是 `CalculatorApp` PID 5104。

### 4.6 Store 一直轉圈

Store 能啟動，但停在載入畫面：先關掉代理軟體與 VPN，再重開 Store。我們的案例關掉 FlClash 就恢復。

### 4.7 失敗時怎麼辦

| 訊息 | 意思 | 做法 |
|---|---|---|
| `icacls` 對大部分項目回「存取被拒」 | 你還不是擁有者 | 先 `takeown /f … /a /r /d y` |
| `takeown`「找不到指定的路徑」 | 路徑打錯，或你開的是 32 位元視窗 | 用 `Get-AppxPackage` 取得路徑；確認 `Is64BitProcess` 是 True |
| `Register` 回 `0x80073D02` | 有程序占住套件 | 停 `gamingservices`、關掉相關 App、必要時重開機 |
| `Register` 回 `0x80073D04`（簽章無效） | 相依的資料夾讀不到 | 補那個相依資料夾的權限（我們在 ScreenSketch、錄音機遇到） |
| `Register` 回 `0x80073CF3` | 相依、更新或衝突驗證失敗 | 確認沒有多給不需要的相依套件 |
| 補完 A，Store 還是閃退 | 還有下一個框架被拒 | 再抓一次 Procmon |
| 補完 B，App 還是打不開 | 超出我們驗證的範圍 | 附上偵測腳本與 Procmon 的輸出開 issue |
| 測試時出現「您需要新的應用程式才能開啟此連結」 | 你在 SYSTEM 視窗 | 換自己的管理員視窗 |

### 4.8 還原與注意事項

**還原單一資料夾**（用步驟 1 記下的擁有者與步驟 3 的備份）：

```cmd
takeown /f "<框架資料夾>" /a /r /d y
icacls "C:\Program Files\WindowsApps" /restore "%USERPROFILE%\acl_xaml28_x64.txt" /C
icacls "<框架資料夾>" /setowner "<步驟 1 記下的擁有者>" /T /C
```

備份檔裡的名稱是相對於父資料夾，所以 `/restore` 要對**父資料夾**執行。`icacls /save` 只存權限，不存擁有者。還原後，`BUILTIN\Users` 條目會消失，問題會回來。

**不要因為網路教學就套用這些：**

| 常見建議 | 為什麼要小心 |
|---|---|
| `icacls "C:\Program Files\WindowsApps" /reset /T /C` | 會把我們補上的 `BUILTIN\Users` 條目清掉，問題回來 |
| `takeown /f "C:\Program Files\WindowsApps" /r` 加 `/setowner` | 範圍太大，會改到上百個無關的套件 |
| 對 `C:\Users` 遞迴授予 ALL APPLICATION PACKAGES | 與啟動鏈無關，而且讓所有 Store 沙箱程式能讀你的使用者資料夾 |

修好之後要清掉哪些副作用（我們留下的），見 [10](docs/10-cleanup-and-rollback.md)。

## 五、文件導覽

| 檔案 | 內容 |
|---|---|
| [00 名詞解釋](docs/00-glossary.md) | 給新手：套件、框架、ACL、ACE、SID、擁有者、AppContainer、UAC 權杖等 |
| [01 環境與症狀](docs/01-environment-and-symptoms.md) | 機器、重設前做過的事、症狀、錯誤碼對照、已排除項目 |
| [02 時間軸](docs/02-timeline.md) | 49 個時間點，每列標明來源 |
| [03 主因 A](docs/03-root-cause-a-framework-folder-acl.md) | 證據鏈、機制、為什麼補一個冒一個、為什麼其他做法無效 |
| [04 主因 B](docs/04-root-cause-b-dotnet-native.md) | .NET Native、GamingServices、修復腳本做了什麼 |
| [05 是不是同一個問題](docs/05-is-it-the-same-problem.md) | 八項檢查的完整版，看不到時代表什麼 |
| [06 解決步驟](docs/06-fix-step-by-step.md) | 逐步操作、每一步的預期輸出與常見失敗 |
| [07 走錯的路與副作用](docs/07-wrong-turns-and-side-effects.md) | 錯誤判斷、環境陷阱、留下的變更 |
| [08 誰說了什麼](docs/08-who-said-what.md) | Claude 與 Grok 各自的分析，對或錯 |
| [09 搜尋紀錄與關鍵字](docs/09-search-notes-and-keywords.md) | 我們怎麼搜、搜到什麼、你該搜什麼 |
| [10 收尾與回復](docs/10-cleanup-and-rollback.md) | 修好之後要清掉什麼、怎麼清 |
| [11 證據節錄](docs/11-evidence-excerpts.md) | 已去識別的事件、權限清單、Procmon、指令輸出 |

### 腳本與工具

| 檔案 | 用途 | 驗證狀態 |
|---|---|---|
| [`scripts/Detect-FrameworkFolderAcl.ps1`](scripts/Detect-FrameworkFolderAcl.ps1) | 唯讀：列出缺 `BUILTIN\Users` 的框架資料夾與相關事件。輸出檔預設已去識別 | 語法檢查通過；判斷邏輯用真實輸出測過；未在其他機器驗證 |
| [`scripts/Fix-FrameworkFolderAcl.ps1`](scripts/Fix-FrameworkFolderAcl.ps1) | 對缺權限的框架資料夾補 `BUILTIN\Users`（先報告、備份、可還原） | 語法檢查通過；**整個流程沒有在 Windows 上實測** |
| [`scripts/Test-UwpApps.ps1`](scripts/Test-UwpApps.ps1) | 啟動內建 App，用事件 5961 與程序判斷成功與否 | 語法檢查通過 |
| [`scripts/Fix-UWP-Calculator.ps1`](scripts/Fix-UWP-Calculator.ps1) | Grok 產生的原始修復腳本，**原樣收錄** | 在原機器執行兩次，計算機成功。風險見 [04](docs/04-root-cause-b-dotnet-native.md) 的 6.5 |
| [`scripts/Cleanup-AfterAppxFix.ps1`](scripts/Cleanup-AfterAppxFix.ps1) | 修好之後的收尾與回復（預設只報告） | 語法檢查通過；**尚未實測**，見 [10](docs/10-cleanup-and-rollback.md) |
| [`tools/check_privacy.py`](tools/check_privacy.py) | 發佈或貼出前，自我檢查有沒有 IP、MAC、序號、電腦名稱等 | 用假資料測試過 |

## 六、搜尋關鍵字

這一節刻意寫得很長。我們在最開始搜尋時，用的是「重設後內建 App 打不開」這類日常描述，搜了很久都找不到。下面把**每一個階段的說法**都列出來，讓你一開始就能搜到這裡。

**日常症狀**

- 重設此電腦之後 Microsoft Store 打不開、閃退
- 雲端下載重設後 內建 App 全部未安裝
- Windows 10 計算機 打不開 閃退
- 內建 App 全部無法開啟 只有 Edge 能用
- Windows 10 重設後 所有 UWP 閃退
- Armoury Crate 閃退 Microsoft Store 打不開
- 開始功能表 磚塊 點了沒反應 一閃而過
- Microsoft Store 設定 大小 0 位元組
- Get-AppxPackage Status Ok 但 App 打不開
- `Start-Process ms-windows-store:` 存取被拒
- wsreset 無效、重新註冊無效、sfc DISM 無效、重設也無效、就地升級也無效

**事件與訊息（繁體中文系統原文）**

- `抓取套件 Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe 資料夾的信任狀態失敗，狀態 2147942405`（依輸出整理，見 1.3 的說明）
- `無法建立套件 Microsoft.WindowsStore_… 的處理程序，因為執行完整性檢查…存取被拒`（依輸出整理，見 1.3 的說明）
- `啟用失敗。錯誤碼: 存取被拒。啟用階段: COM ActivateExtension`
- `啟用失敗。錯誤碼: 應用程式未啟動。啟用階段: COM ActivateExtension`
- `找不到 mrt100_app.dll`、`找不到 SharedLibrary.dll`
- `您需要新的應用程式才能開啟此 ms-windows-calculator 連結`

**English（依中文訊息翻譯者標為「譯」，不是 Windows 英文版原文）**

- `AppModel-Runtime event 57 trust state package folder failed 2147942405`（譯）
- `AppModel-Runtime event 61 cannot create process for package integrity check access denied`（譯）
- `TWinUI event 5961 activation failed COM ActivateExtension access denied`
- `Activation of the app for the Windows.Launch contract failed with error: The app didn't start.`（英文原文，見 [09](docs/09-search-notes-and-keywords.md) 的來源）
- `Windows 10 Microsoft Store won't open after Reset this PC cloud download`
- `UWP framework package folder missing BUILTIN\Users ACE WindowsApps`
- `svchost impersonating ACCESS DENIED READ_CONTROL WindowsApps framework Process Monitor`
- `Microsoft.UI.Xaml.2.8 Microsoft.VCLibs.140.00 Microsoft.NET.Native.Framework.2.2 access denied`
- `calculator won't open mrt100_app.dll SharedLibrary.dll .NET Native`
- `0x80073D02 Microsoft.NET.Native Register GamingServices in use`

**錯誤碼**

`0x80070005`、`2147942405`、`0x8027025B`、`-2144927141`、`0x80073D02`、`0x80073D04`、`0x80073CF3`、`0x80073CF9`、`0x80073CF1`、`0x8007010B`、`0x80070525`、`0x80070520`、`0x800F0984`、`0x80070015`、`0x8007000D`、`0x80070057`、`0x80070490`

**記錄、工具、指令名稱**

`AppxDeploymentFailureBlue`、`StoreAgentInstallFailure1`、`MicrosoftAccount.TokenProvider.Core`、`AppExecutionAlias`、`PrerequisitesChecked`、`Microsoft-Windows-AppXDeploymentServer/Operational`、`Microsoft-Windows-AppReadiness/Admin`、`StateRepository-Machine.srd`、`PackageRepository`、`takeown /a /r /d y`、`icacls /grant *S-1-5-32-545:(OI)(CI)(RX)`、`icacls /save /restore`、`Add-AppxPackage -DisableDevelopmentMode -Register`、`Get-AppxPackage -AllUsers`、`Process Monitor`、`Procmon`、`PsExec`、`restore-appx`、`Microsoft-Store-Fix`

完整的搜尋流程、錯誤碼對照與建議的 GitHub topics 見 [09](docs/09-search-notes-and-keywords.md)。

## 七、授權、隱私與回報

### 授權

本專案有**兩份授權，分別適用於不同的檔案**。兩份都放在根目錄，GitHub 側欄會同時列出：

| 授權檔 | 適用於 | 授權 |
|---|---|---|
| [`LICENSE`](LICENSE) | 文件：`README.md` 與 `docs/` 底下所有 `.md` | CC BY 4.0（創用 CC 姓名標示 4.0 國際） |
| [`LICENSE-CODE`](LICENSE-CODE) | 程式碼：`scripts/` 與 `tools/` 底下所有檔案 | MIT |

- 版權：© 2026 windows10-store-apps-wont-open-after-reset contributors。
- **轉載或改作文件**：請依 CC BY 4.0 標示出處，寫上上面的版權人名稱、附上本專案連結與[授權連結](https://creativecommons.org/licenses/by/4.0/deed.zh-hant)，並註明是否做過修改。
- **使用或改作程式碼**：請保留 `LICENSE-CODE` 的版權與授權聲明。
- `scripts/Fix-UWP-Calculator.ps1` 由 Grok（xAI）產生，隨本專案以 MIT 發佈。
- 不確定某個檔案適用哪一份時：`scripts/` 與 `tools/` 底下是 MIT，其餘都是 CC BY 4.0。兩份授權的適用範圍以上表為準。

### 隱私

本專案**刻意不包含**：IP 位址、MAC 位址、序號與裝置識別碼（機器 GUID、硬體識別碼等）、電腦名稱、使用者名稱、真實的機器 SID、電子郵件、帶 token 的連結。所有輸出都已去識別，電腦名稱寫成 `<COMPUTER>`，使用者名稱寫成 `<USER>`，SID 的機器部分寫成 `<…>`。

- 腳本本身不蒐集上述資訊。`Detect-FrameworkFolderAcl.ps1` 的輸出檔預設已去識別。
- **貼出任何輸出（issue、討論區）前，請自己再看一次**，也可以跑 `python3 tools/check_privacy.py <資料夾> --names <你的電腦名稱> <你的使用者名稱>` 檢查。
- 文件裡仍保留的環境資訊，是為了讓你判斷「是不是同一個問題」，不具個人識別性：Windows 版本與 build、硬體型號（主機板品牌、SSD 型號）、軟體名稱、事件的時間戳。

### 免責聲明

本專案按現狀提供，不保證適用於其他機器。修復涉及系統資料夾權限，請先備份，並自行承擔風險。

### 回報

如果你遇到相同的症狀，不論修好或沒修好，歡迎開 issue，並附上 [`Detect-FrameworkFolderAcl.ps1`](scripts/Detect-FrameworkFolderAcl.ps1) 的輸出。這個案例目前只有一台機器的證據。

本文最後更新：2026-11-13。

---

## 後記（2026 年 11 月 13 日）

這一段和前面的技術內容無關，是我寫完這份紀錄之後，個人的感想。

2026 年 11 月 12 日，輝達宣布黃仁勳辭去總裁、執行長與董事職務，由財務長 Colette Kress 暫代執行長。依報導，他在 11 月 8 日寄給全體員工的信中，承認自己與一名女子有婚外情。同一天，董事會宣布由獨立董事組成的委員會展開調查，並表示沒有理由相信公司機密或國家安全受到危害，對他仍有信心，預期他會繼續擔任執行長。四天後，他就辭職了，調查還沒有結論。

報導也提到，對方被指與中國有關聯，美國聯邦調查局（FBI）已介入相關調查。這些指控目前都還沒有被證實。截至我撰寫這段時，我沒有看到官方公布任何調查結果。

這件事讓我很震驚。一家市值這麼大的公司，執行長從「董事會有信心，會繼續任職」到辭職，只隔了四天，而且是在調查結束前。報導提到，有員工在內部意見箱要求董事會公布調查結果，並徵詢他們對他續任的看法。

我覺得這件事很嚴重。但我說的嚴重，是指它對公司、股東與員工的影響，不是在替任何一方定罪。我不知道全部的事實，所以不判斷他有沒有過錯。

如果要說我替誰說話，那只是我自己。一件影響這麼多人的事，應該等事實比較清楚，再做決定，而且結果要讓相關的人知道。

如果之後調查有結果，我會回來更新這段文字。

### 個人意見

這一段是我個人的看法，和前面的技術內容無關。消息出來的時候，我一開始以為是假新聞，直到看到官方新聞稿才確定是真的，我非常驚訝。當天盤前股價一度下跌超過 10%，市場的反應很大。我寫下這段，只是為了記錄這件事確實發生過，以及它帶給我的衝擊。

參考報導：

- [中央社：黃仁勳辭去執行長　輝達盤前股價下殺逾10%](https://www.cna.com.tw/news/afe/202611120372.aspx)
- [公視新聞網：輝達宣布黃仁勳辭職　財務長克雷斯接任臨時執行長](https://news.pts.org.tw/article/835526)
- [聯合新聞網：「把老大請回來」！輝達員工聲援黃仁勳　追問調查未完為何先走人](https://udn.com/news/story/125066/9876841)
