# 03 主因 A：框架資料夾沒有 `BUILTIN\Users` 的權限條目

## 一句話

Store、計算機等 App 啟動時，系統服務（`svchost.exe`）會以**使用者的身分**，去開這個 App 依賴的「框架套件」資料夾做檢查。這台機器上，那些資料夾的權限清單裡沒有 `BUILTIN\Users`，連「讀取權限設定」都被拒，所以 App 的程序根本沒有被建立。補上這一條，Store 立刻能開。

先讀 [00 名詞解釋](00-glossary.md) 會比較順。

## 一、啟動流程與每一步的記錄

這是依觀察推得的流程，不是微軟文件。表中「記錄」欄是這一步失敗時，會在哪裡留下痕跡。

| 步驟 | 誰做 | 做什麼 | 失敗時的記錄 | 這個案例 |
|---|---|---|---|---|
| 1 | 殼層（開始功能表、檔案總管） | 要求系統啟用這個 App | TWinUI 事件 5961 | 失敗，`ErrorCode` 存取被拒 |
| 2 | 系統 | 讀 App 的清單檔，找出依賴的框架 | 部署事件 | 正常 |
| 3 | `svchost.exe` 內的 AppX 元件，以使用者身分 | 開啟每個依賴的框架資料夾，檢查信任狀態與完整性 | AppModel-Runtime 事件 57、61 | **失敗** |
| 4 | 系統 | 建立 App 的程序，放進沙箱 | AppModel-Runtime 事件（程序建立） | 沒有發生 |
| 5 | App 程序 | 在沙箱裡載入需要的 DLL | 系統對話框、`Application` 記錄 | 沒有發生（錯誤 B 在這裡） |
| 6 | App | 視窗出現 | — | 沒有發生 |

第 3 步失敗，後面都不會發生。所以使用者看到的是「閃一下就沒了」，甚至連「閃一下」也未必有：被建立的往往只是啟動畫面，不是 App 本身。

## 二、證據鏈

### 證據 1：能啟動的與不能啟動的對照（證據包 B，10/24 20:53）

Edge 能啟動；Store、計算機不能。三者都是 AppX 套件，都是 `Status: Ok`。差別一定在啟動路徑上的某個東西。

### 證據 2：事件 57 每一次都點名同一個資料夾

```
抓取套件 Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe 資料夾的信任狀態失敗，狀態為 2147942405。
```

點名的是**框架**，不是 Store 本身。Store 的清單檔宣告它依賴 `Microsoft.UI.Xaml.2.8` 與 `Microsoft.VCLibs.140.00`；這兩個都顯示 `Installed`。

### 證據 3：權限清單對照

能啟動的 Edge 資料夾，有這些明確寫在資料夾上的條目：

```
BUILTIN\Users:(OI)(CI)(Rc,S,RD,REA,X,RA)
S-1-15-3-<套件專屬能力 SID>:(OI)(CI)(RX)
APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES:(OI)(CI)(RX)
APPLICATION PACKAGE AUTHORITY\所以受限制的應用程式封包:(OI)(CI)(RX)
BUILTIN\Users:(OI)(CI)(RX)
BUILTIN\Users:(OI)(CI)(R)
```

Xaml 2.8 x64 資料夾（修復前），只有從 `WindowsApps` 繼承來的條目，每一條都帶 `(I)`：

```
NT SERVICE\TrustedInstaller:(I)(F)
NT SERVICE\TrustedInstaller:(I)(OI)(CI)(IO)(F)
S-1-15-3-1024-…:(I)(RX)
S-1-15-3-1024-…:(I)(OI)(CI)(IO)(GR,GE)
NT AUTHORITY\SYSTEM:(I)(F)
NT AUTHORITY\SYSTEM:(I)(OI)(CI)(IO)(F)
BUILTIN\Administrators:(I)(CI)(RX)
NT AUTHORITY\LOCAL SERVICE:(I)(OI)(CI)(RX)
NT AUTHORITY\NETWORK SERVICE:(I)(OI)(CI)(RX)
NT AUTHORITY\RESTRICTED:(I)(OI)(CI)(RX)
S-1-19-512-4096:(OI)(CI)(RX,D,WDAC,WO,WA)
```

**沒有任何一條寫到 `BUILTIN\Users`。** 簽章與檔案本身都沒問題（`Microsoft.UI.Xaml.dll` 簽章 Valid，簽署者 Microsoft Corporation；`AppxSignature.p7x` 存在）。

### 證據 4：Process Monitor 抓到被拒的當下（決定性）

篩選條件只有 `Result is ACCESS DENIED`、不篩處理序。第 3 份匯出（約 47 萬筆，ACCESS DENIED 共 37 筆）裡：

| 欄位 | 內容 |
|---|---|
| 時間 | 18:10:48、18:10:54、18:10:57（共 3 次，與使用者的三次點擊吻合） |
| 處理序 | `svchost.exe` |
| 操作 | `CreateFile`（開啟資料夾） |
| 路徑 | `C:\Program Files\WindowsApps\microsoft.ui.xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe` |
| 結果 | `ACCESS DENIED` |
| 詳細 | 要求讀取權限設定與讀取屬性；`Impersonating: <電腦>\<使用者>` |

（詳細欄為轉述，原文未保留。）

同一份紀錄中，同一個 `svchost.exe` 以使用者身分開計算機、Store 的資料夾，**結果是成功**。只有框架資料夾被拒。

### 證據 5：補上權限後，拒絕消失，下一個冒出來

對 Xaml 2.8 x64 補 `BUILTIN\Users:(OI)(CI)(RX)` 之後重抓（19:34 到 19:35，34 筆全是 ACCESS DENIED）：

- Xaml 2.8 的拒絕**不見了**。
- 新的拒絕：`svchost.exe` 對 `Microsoft.NET.Native.Framework.2.2` x64（19:35:00）與 `Microsoft.VCLibs.140.00` x64（19:35:12）。

### 證據 6：全部補完，Store 開了

四個 x64 框架補完（第一次因為沒有先 `takeown` 失敗，補上之後 0 失敗），Store 在 19:53:35 啟動，AppModel-Runtime 沒有新的 57 或 61。

## 三、權限清單怎麼讀

以 Xaml 2.8 修復前的清單為例：

| 條目 | 意思 | 對 App 啟動有用嗎 |
|---|---|---|
| `NT SERVICE\TrustedInstaller:(I)(F)` | TrustedInstaller 完全控制 | 沒有，只有維護服務用 |
| `NT AUTHORITY\SYSTEM:(I)(F)` | SYSTEM 完全控制 | 沒有，系統自己用 |
| `S-1-15-3-1024-…:(I)(RX)` | 一個能力 SID 可讀取執行 | 不是一般使用者 |
| `BUILTIN\Administrators:(I)(CI)(RX)` | Administrators 可讀取；`(CI)` 表示只適用於子**資料夾**，不適用於檔案；而且是 `(I)` 繼承來的 | **不夠**，見下面第四節 |
| `NT AUTHORITY\LOCAL SERVICE`、`NETWORK SERVICE`、`RESTRICTED` | 服務帳號可讀取 | 不是一般使用者 |
| `S-1-19-512-4096:(OI)(CI)(RX,D,WDAC,WO,WA)` | 處理序信任標籤，限制誰能改這些檔案 | 與讀取無關 |

**沒有任何一條適用於一般使用者帳號。**

## 四、為什麼管理員帳號也被擋（推論）

使用者的帳號是管理員，他一度認為「我已經提權了還被拒，就不是權限問題」。這個想法不對，原因是推論如下，我們沒有另外驗證：

1. 開啟 UAC 時，管理員帳號登入後拿到兩個權杖：未提升的（平常用）與提升的（按「以系統管理員身分執行」才用）。
2. 未提升的權杖裡，Administrators 群組只會用來**拒絕**，不會用來**允許**。
3. App 啟用走的是平常的權杖。所以清單裡「Administrators 可以讀」這條，對它沒有幫助。
4. 能讓這個權杖通過的，只有直接寫給 `BUILTIN\Users`（或寫給使用者本人）的條目。

這解釋了為什麼我們用系統管理員視窗去 `icacls` 看起來一切正常，卻怎麼都修不好，也解釋了為什麼 `takeown`、`CodeIntegrity.cat` 變可讀這些動作對症狀沒有影響。

## 五、為什麼補一個、冒一個

一個 App 往往依賴好幾個框架，系統**依序**檢查。第一個被拒，後面的根本不會被檢查，所以在 Procmon 裡只看得到第一個。補好第一個，第二個才露出來。

這台機器的順序是：Xaml 2.8 → NET Native Framework 2.2 → VCLibs 140，其餘兩個（NET Native Runtime 2.2、VCLibs UWPDesktop 14）以及 x86 版本一併處理。**缺口是整批框架，不是單一資料夾。**

## 六、影響範圍

在這台機器上，後來還有一批更舊的相依資料夾需要同樣處理，因為某些 App（螢幕剪取、錄音機、Xbox 相關）依賴它們，`Register` 時回 `0x80073D04`（簽章無效，實際上是相依資料夾讀不到）：

- `Microsoft.UI.Xaml.2.0`（x64、x86）
- `Microsoft.NET.Native.Runtime.1.7`、`Framework.1.7`（x64）
- `Microsoft.Services.Store.Engagement`
- `Microsoft.WebpImageExtension`

規則一樣：App 依賴什麼，就看那個框架資料夾。

## 七、為什麼其他做法沒用

| 做法 | 為什麼對這個案例無效 |
|---|---|
| `wsreset`、重設 App、重新註冊 Store | 不改框架資料夾的權限 |
| `Add-AppxPackage -Register` 註冊框架 | 只把使用者的安裝狀態從 `Staged` 改成 `Installed`，不補權限條目。狀態變漂亮了，症狀沒變 |
| 用官方 appx 重裝同版本 Xaml 2.8 | `Remove-AppxPackage` 對框架套件沒有真的移除（之後 `Get-AppxPackage` 仍列出），重裝等於沒做 |
| 補 ALL APPLICATION PACKAGES 與受限 AAP | 這個檢查是以**一般使用者**身分做的，缺的是 `Users`。AAP 是給沙箱程式用的，在主因 B 才派上用場 |
| 讓 `CodeIntegrity.cat` 可讀 | 檔案可讀了，缺口不在檔案 |
| 補 `C:\Users` 的 AAP | 與啟動鏈無關，而且讓所有 Store 沙箱程式能讀你的使用者資料夾 |
| restore-appx 重建資料庫、補 `PackageRepository` | 資料庫沒壞；`PackageRepository` 不是微軟文件裡的機碼，是工具自己的檢查（官方疑難排解頁提到的是 `PackageRepositoryRoot`，而且只在 `0x80073CFE` 時有關） |
| `sfc`、`DISM`、重設、就地升級 | 系統檔案沒壞；重設後的映像本身就沒有這些權限條目，而就地升級保留現有權限 |
| 「還原預設權限」（`icacls /reset`） | 這個缺口**不是**有人改壞權限，而是條目從來沒有。`/reset` 只會把明確寫的條目清掉，會把我們補上的 `Users` 一起清掉 |

## 八、沒有解釋的部分與可能的假設

1. **為什麼這個映像的框架資料夾沒有這些條目。** 我們沒有健康機器可以對照，也不確定正常的框架資料夾是否有 `BUILTIN\Users`。假設：映像以 `Staged` 方式放好框架，正常登入時的部署流程會為使用者加上條目，但這台機器的首次部署（13:02）就失敗了，條目沒有補上。這個假設有兩個漏洞：不知道為什麼首次部署失敗；也不知道為什麼之後的 `-Register` 不補條目。
2. **重設後第一次登入的 0x80070005 與這個缺口的因果順序。** 可能是缺口造成了失敗，也可能是別的原因先造成缺口。
3. **其他機器會不會一樣。** 只有一台機器的證據。

## 九、與官方文件的關係

- **KB 2798317**（Microsoft Store Apps fail to start if default registry or file permissions modified）：描述預設權限被改而 App 啟動失敗，症狀也有 TWinUI 5961。它要求 ALL APPLICATION PACKAGES 在 `C:\Program Files`、`C:\Windows` 等位置有讀取權限，我們這台那些都在（只有 `C:\Users` 沒有，補了也沒用）。它沒有提到框架資料夾與 `BUILTIN\Users`。
- 搜尋過程的紀錄見 [09](09-search-notes-and-keywords.md)。

## 十、如果你想幫忙驗證

我們最需要的資料：

1. 一台**沒有這個問題**的 Windows 10 機器上，`icacls` 對 `Microsoft.UI.Xaml.2.8`（或任何框架）資料夾的輸出：有沒有 `BUILTIN\Users`？這能回答「正常情況是什麼」。
2. 一台**有同樣症狀**的機器上，[`Detect-FrameworkFolderAcl.ps1`](../scripts/Detect-FrameworkFolderAcl.ps1) 的輸出。
3. 修復後，你的 Procmon 是不是也出現「補一個冒一個」。

請先去識別（電腦名稱、使用者名稱、SID）再貼出。
