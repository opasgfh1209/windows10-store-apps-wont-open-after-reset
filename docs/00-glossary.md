# 00 名詞解釋

給第一次接觸這些名詞的人。每一條只講讀這份文件需要的部分，不求完整。

## 套件與 App

| 名詞 | 意思 |
|---|---|
| **AppX、MSIX** | Windows 的 App 封裝格式。從 Microsoft Store 安裝的 App，以及計算機、相片、鬧鐘等內建 App，大多是這種格式 |
| **UWP** | 通用 Windows 平台。這種 App 用 AppX 或 MSIX 格式封裝，在沙箱裡執行 |
| **套件（Package）** | 一個封裝單位。App 是套件，App 依賴的共用程式庫也是套件 |
| **框架套件（Framework package）** | 一種提供共用程式庫的套件，給多個 App 共用。本案例涉及的有 `Microsoft.UI.Xaml`（介面元件）、`Microsoft.VCLibs`（C++ 執行階段）、`Microsoft.NET.Native`（.NET 執行階段）、`Microsoft.WindowsAppRuntime` |
| **套件完整名稱（PackageFullName）** | 例如 `Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe`。格式是 名稱_版本_架構__發行者代碼 |
| **套件家族名稱（PFN）** | 例如 `Microsoft.WindowsCalculator_8wekyb3d8bbwe`。不含版本與架構。使用者資料夾 `%LOCALAPPDATA%\Packages\` 底下用這個命名 |
| **AUMID** | 啟動 App 用的識別字串，格式是 `套件家族名稱!App`。`shell:AppsFolder\<AUMID>` 可以啟動它 |
| **WindowsApps 資料夾** | `C:\Program Files\WindowsApps`。所有套件的檔案都在這裡，每個套件一個子資料夾。預設連系統管理員都不能直接開啟 |
| **Staged、Installed、Registered** | `Staged`：檔案已放好，還沒登記給任何使用者。`Installed`：已登記給某個使用者。`Register` 指用 `Add-AppxPackage -Register` 登記。這些是安裝**狀態**，與資料夾**權限**無關 |
| **IsFramework** | `Get-AppxPackage` 輸出的欄位，True 表示它是框架套件 |
| **清單檔（AppxManifest.xml）** | 套件裡的一個檔案，寫著這個套件是什麼、依賴哪些框架、宣告哪些功能 |
| **AppContainer（沙箱）** | UWP App 的執行環境。程序在裡面有自己的身分，只能讀寫被明確允許的位置 |
| **.NET Native** | 一種把 .NET 程式預先編譯的技術。用它做的 App 需要 `Microsoft.NET.Native.Framework` 與 `Runtime`，執行時載入 `mrt100_app.dll`、`SharedLibrary.dll` |

## 權限

| 名詞 | 意思 |
|---|---|
| **ACL、DACL** | 一個檔案或資料夾的存取控制清單。DACL 是其中決定「誰可以做什麼」的部分 |
| **ACE** | 清單裡的一條規則，例如「`BUILTIN\Users` 可以讀取與執行」 |
| **SID** | 帳號或群組的識別碼。名稱可能隨系統語言不同，SID 不會變。`S-1-5-32-545` 是 Users，`S-1-5-32-544` 是 Administrators，`S-1-15-2-1` 是 ALL APPLICATION PACKAGES，`S-1-15-2-2` 是 ALL RESTRICTED APP PACKAGES，`S-1-5-18` 是 SYSTEM |
| **BUILTIN\Users** | 「這台電腦上的一般使用者」群組。所有本機帳號都屬於它 |
| **ALL APPLICATION PACKAGES（AAP）** | 「所有應用程式套件」群組。沙箱裡的 App 程序屬於它。要讓沙箱程式讀某個位置，通常要給它條目 |
| **擁有者** | 每個檔案或資料夾有一個擁有者。擁有者可以改權限清單。`WindowsApps` 底下的擁有者通常是 TrustedInstaller 或 SYSTEM |
| **TrustedInstaller** | Windows 更新與系統元件維護用的內建服務帳號，擁有大部分系統檔案 |
| **SYSTEM** | 作業系統本身使用的帳戶，不是使用者。`PsExec -s` 開出來的視窗身分是它 |
| **UAC 與未提升的權杖** | 開啟 UAC 時，管理員帳號平常用的權杖裡，Administrators 群組只能拒絕、不能允許。按「以系統管理員身分執行」才會拿到提升過的權杖。本文第 2.4 節用它解釋為什麼管理員也被擋（推論） |
| **Impersonating（模擬）** | 系統服務暫時以某個使用者的身分做事。Procmon 的 `Detail` 欄會寫 `Impersonating: <電腦>\<使用者>` |

## ACE 的寫法（`icacls` 輸出）

例如 `BUILTIN\Users:(OI)(CI)(RX)`：

| 符號 | 意思 |
|---|---|
| `(I)` | 這條規則是從上層繼承來的，不是直接寫在這個資料夾上 |
| `(OI)` | 底下的**檔案**會繼承這條規則 |
| `(CI)` | 底下的**資料夾**會繼承這條規則 |
| `(IO)` | 只給底下的項目，不適用這個資料夾本身 |
| `(F)` | 完全控制 |
| `(M)` | 修改 |
| `(RX)` | 讀取與執行 |
| `(R)` | 讀取 |

## 指令與工具

| 名詞 | 意思 |
|---|---|
| **takeown** | 取得檔案或資料夾的擁有權。`/f` 指定路徑，`/a` 把擁有者設成 Administrators 群組，`/r` 遞迴子項目，`/d y` 遇到無法列出的資料夾預設回答「是」 |
| **icacls** | 顯示與修改權限。`/grant` 加權限，`/remove:g` 移除授予的權限，`/save` 把權限存成檔，`/restore` 還原，`/reset` 把明確寫的權限清掉改回繼承，`/setowner` 改擁有者，`/T` 遞迴，`/C` 遇到錯誤繼續 |
| **Process Monitor（Procmon）** | 微軟 Sysinternals 的工具，即時記錄所有處理序對檔案、登錄的操作與結果。本案例用它找出誰被拒絕、拒絕哪個路徑 |
| **PsExec** | Sysinternals 的工具，可以用 SYSTEM 等身分開程式。注意它開的視窗不是你的使用者 |
| **事件檢視器與記錄名稱** | `Microsoft-Windows-AppModel-Runtime/Admin`（App 執行階段）、`Microsoft-Windows-TWinUI/Operational`（啟用 App 的殼層）、`Microsoft-Windows-AppXDeploymentServer/Operational`（部署）。路徑在「應用程式及服務記錄 → Microsoft → Windows」底下 |
| **WOW64、32 位元視窗** | 64 位元 Windows 上執行 32 位元程式的機制。32 位元的 PowerShell 會看到被導向的資料夾與登錄：`System32` 變 `SysWOW64`，`SOFTWARE` 變 `SOFTWARE\WOW6432Node` |

## 本案例的專有名詞

| 名詞 | 意思 |
|---|---|
| **錯誤 A** | 啟動檢查階段，系統以使用者身分開啟框架資料夾被拒（事件 57、61，5961 存取被拒） |
| **錯誤 B** | App 程序建立後，在沙箱裡讀不到 .NET Native 框架的檔案（5961「應用程式未啟動」） |
| **Gaming Services** | `Microsoft.GamingServices`，Xbox 遊戲與 Minecraft 的底層服務。本案例中它占住 .NET Native 套件，讓 `Register` 失敗 |
