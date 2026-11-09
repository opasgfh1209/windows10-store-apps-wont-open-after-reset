# 11 證據節錄

已去識別：電腦名稱改成 `<COMPUTER>`、使用者名稱改成 `<USER>`、SID 的機器部分改成 `<…>`。其餘保留原文。標記：**C** = Claude 的腳本或指令，**G** = Grok 的腳本或指令，**U** = 使用者貼出的輸出。

## 1. 第一份診斷報告（2026-10-24 13:59:47，C 的腳本，U 輸出，逐字，已去識別）

**基本資訊與服務：**

```
系統：Microsoft Windows 10 專業版  build 19045
安裝／重置時間（之後的事件才看）：10/24/2026 06:12:40
C 槽剩餘：423.4 GB（共 464.5 GB）

AppXSvc          Stopped    啟動類型：Manual
ClipSVC          Stopped    啟動類型：Manual
InstallService   Running    啟動類型：Manual
StateRepository  Running    啟動類型：Manual
TokenBroker      Running    啟動類型：Manual
wlidsvc          Stopped    啟動類型：Manual
cryptsvc         Running    啟動類型：Automatic
DoSvc            Running    啟動類型：Automatic

AzureAdJoined : NO
DomainJoined : NO
發現政策：HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx
    MdmHosts = ^(?:[^\/]*)\.MANAGE[^\.]*\.(MICROSOFT\.(COM|US)|MICROSOFTONLINE\.CN)$
```

**內建 App 的註冊狀態（每個都是 Ok、使用者 Installed）：**

```
Microsoft.WindowsCalculator  版本 11.2607.0.0  Status=Ok
    安裝資料夾存在：True   清單檔存在：True
    S-1-5-18 [S-1-5-18]: Staged
    S-1-5-21-<…>-1001 [<USER>]: Installed
Microsoft.WindowsStore  版本 22609.1401.6.0  Status=Ok          （同上）
Microsoft.Windows.Photos  版本 2026.11090.22001.0  Status=Ok    （同上）
Microsoft.Windows.ShellExperienceHost  版本 10.0.19041.3636  Status=Ok
```

**重設之後的 App 相關錯誤與錯誤碼統計：**

```
Microsoft-Windows-AppXDeploymentServer/Operational：217 筆錯誤或警告
Microsoft-Windows-AppReadiness/Admin：106 筆錯誤或警告
Microsoft-Windows-AppModel-Runtime/Admin：沒有符合的錯誤或警告
錯誤代碼統計（次數多的在前）：
    0X80070005  x230
    0X80070015  x19
    0X80070057  x6
    0X80073CF9  x5
    0X8007010B  x5
    0X80073CF1  x4
    0X80070490  x2
    0X8007000D  x1
    0X80070002  x1
```

注意：**這份報告產生時（13:59），AppModel-Runtime 沒有符合條件的錯誤。** 事件 57、61 是之後才在記錄裡看到的。原因我們不確定：可能當時還沒有實際啟動過那些 App，也可能是報告的篩選條件沒有涵蓋。

**最近的事件原文（節錄）：**

```
2026/10/24 下午 01:38:17 | Microsoft-Windows-AppXDeploymentServer/Operational | 8761 | AppExecutionAlias 目錄遺失，錯誤碼為 0x8007010B。
2026/10/24 下午 01:37:08 | Microsoft-Windows-AppXDeploymentServer/Operational | 404 | 套件 Microsoft.WindowsStore_22609.1401.6.0_neutral_~_8wekyb3d8bbwe 的 AppX 部署操作失敗，錯誤為 0x80070005。此失敗的特定錯誤文字是: 來自…
2026/10/24 下午 01:37:08 | Microsoft-Windows-AppXDeploymentServer/Operational | 401 | 來自  (AppxBundleManifest.xml)  之套件 Microsoft.WindowsStore_22609.1401.6.0_neutral_~_8wekyb3d8bbwe 上使用目標磁碟區 C: 進行…
2026/10/24 下午 01:29:32 | Microsoft-Windows-AppXDeploymentServer/Operational | 404 | 套件 Microsoft.WindowsCalculator_2021.2607.0.0_neutral_~_8wekyb3d8bbwe 的 AppX 部署操作失敗，錯誤為 0x80070005。此失敗的特定錯誤文字是:
2026/10/24 下午 01:21:39 | Microsoft-Windows-AppReadiness/Admin | 214 | S-1-5-21-<…>-1001 的 'aimgr_8wekyb3d8bbwe' install 失敗。錯誤: '找不到套件。' (0 秒)
2026/10/24 下午 01:21:39 | Microsoft-Windows-AppXDeploymentServer/Operational | 404 | 套件 aimgr_0.20.61.0_x64__8wekyb3d8bbwe 的 AppX 部署操作失敗，錯誤為 0x80073CF1。此失敗的特定錯誤文字是: Windows 無法執行 StageUserData 操作，
2026/10/24 下午 01:21:39 | Microsoft-Windows-AppXDeploymentServer/Operational | 712 | Windows 無法執行 StageUserData 操作，因為在存放庫中找不到 aimgr_0.20.61.0_x64__8wekyb3d8bbwe。請確定 …
```

重設後第一批部署失敗是 13:02:53（`Microsoft.VCLibs.140.00` x86 與 Realtek 音訊控制程式的 Register，錯誤 0x80070005）。這一筆是使用者另外查最早事件時看到的，原文沒有保留。

## 2. 啟動失敗時的事件

**5961（逐字）：**

```
Microsoft.WindowsStore_8wekyb3d8bbwe!App 啟用失敗。錯誤碼: 存取被拒。。啟用階段: COM ActivateExtension
```

**AppModel-Runtime 事件 57 與 61（整理）：** 原始事件文字沒有保留，下面是依使用者輸出整理的內容，「信任狀態」「完整性檢查」「存取被拒」「2147942405」與套件名稱是原文用字，標點可能略有差異。

```
ID 57：抓取套件 Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe 資料夾的信任狀態失敗，狀態 2147942405
ID 61：0x5: 無法建立套件 Microsoft.WindowsStore_22609.1401.6.0_x64__8wekyb3d8bbwe 的處理程序，因為執行完整性檢查…存取被拒
```

事件 61 也對 `Microsoft.WindowsCalculator`、`Microsoft.StorePurchaseApp` 出現。2026-10-24 22:31 的 Store 深入診斷與之後的每次啟動，都是 57 接 61。

## 3. Store 的相依（U，G 的腳本）

```
Dep : Microsoft.UI.Xaml.2.8    Min : 8.2501.31001.0     已安裝（x86、x64）
Dep : Microsoft.VCLibs.140.00  Min : 14.0.33519.0       已安裝（x86、x64）
```

相依都是 `Installed`，但事件 57 仍然點名 Xaml 2.8。這是「安裝狀態不是原因」的證據。

## 4. 權限清單對照（U，G 的腳本，2026-10-24 23:31）

**Edge（能啟動）** 資料夾，條目節錄：

```
BUILTIN\Users:(OI)(CI)(Rc,S,RD,REA,X,RA)
S-1-15-3-<…>:(OI)(CI)(RX)
APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES:(OI)(CI)(RX)
APPLICATION PACKAGE AUTHORITY\所以受限制的應用程式封包:(OI)(CI)(RX)
BUILTIN\Users:(OI)(CI)(RX)
BUILTIN\Users:(OI)(CI)(R)
NT SERVICE\TrustedInstaller:(I)(F)
NT SERVICE\TrustedInstaller:(I)(OI)(CI)(IO)(F)
NT AUTHORITY\SYSTEM:(I)(F)
NT AUTHORITY\SYSTEM:(I)(OI)(CI)(IO)(F)
BUILTIN\Administrators:(I)(CI)(RX)
NT AUTHORITY\LOCAL SERVICE:(I)(OI)(CI)(RX)
NT AUTHORITY\NETWORK SERVICE:(I)(OI)(CI)(RX)
```

**Xaml 2.8 x64（失敗）** 資料夾，修復前，全部條目：

```
NT SERVICE\TrustedInstaller:(I)(F)
NT SERVICE\TrustedInstaller:(I)(OI)(CI)(IO)(F)
S-1-15-3-1024-<…>:(I)(RX)
S-1-15-3-1024-<…>:(I)(OI)(CI)(IO)(GR,GE)
NT AUTHORITY\SYSTEM:(I)(F)
NT AUTHORITY\SYSTEM:(I)(OI)(CI)(IO)(F)
BUILTIN\Administrators:(I)(CI)(RX)
NT AUTHORITY\LOCAL SERVICE:(I)(OI)(CI)(RX)
NT AUTHORITY\NETWORK SERVICE:(I)(OI)(CI)(RX)
NT AUTHORITY\RESTRICTED:(I)(OI)(CI)(RX)
S-1-19-512-4096:(OI)(CI)(RX,D,WDAC,WO,WA)
```

簽章：`Microsoft.UI.Xaml.dll` `SigStatus=Valid`，簽署者 `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`；`AppxSignature.p7x` 存在。

## 5. Procmon（C，使用者的擷取，2026-10-25）

| 擷取 | 時間 | 內容 | 結果 |
|---|---|---|---|
| 第 1 份（G 的指示） | 13:09:40 到 13:12:05 | 2,541 筆，全是 `ApplicationFrameHost.exe`；結果只有 SUCCESS、NAME NOT FOUND 等 | 沒有任何 ACCESS DENIED。擷取範圍太窄 |
| 第 2 份（C 的指示） | 18:10:47 到 18:11:00 | 22,510 筆；3 個處理序（`explorer.exe`、`ApplicationFrameHost.exe`、`Claude.exe`） | ACCESS DENIED 28 筆，全在 `explorer.exe`：`WindowsApps` 根目錄的列舉（13 筆，預設保護）、`HKLM\SOFTWARE\Microsoft\SecurityManager\CapAuthz` 的 `HasRepaired`（15 筆） |
| 第 3 份（同一次擷取、不同匯出） | 18:10 | 約 47 萬筆；含 `svchost.exe`、`StartMenuExperienceHost.exe`、`DllHost.exe` | ACCESS DENIED 37 筆。**新增的 9 筆：`svchost.exe` 3 次對 Xaml 2.8 x64 資料夾；`StartMenuExperienceHost.exe` 6 筆（建立 LocalLow 資料夾，與本問題無關）** |
| 第 4 份（補 Xaml 的 Users 之後） | 19:34:59 到 19:35:15 | 34 筆，全是 ACCESS DENIED | Xaml 的拒絕消失；`svchost.exe` 新的拒絕：NET Native Framework 2.2 x64（19:35:00）、VCLibs 140 x64（19:35:12） |

第 3 份中 `svchost.exe` 的拒絕（轉述；原始 `Detail` 欄未保留）：

```
Process Name : svchost.exe
Operation    : CreateFile
Path         : C:\Program Files\WindowsApps\microsoft.ui.xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe
Result       : ACCESS DENIED
Detail       : 要求讀取權限設定（Read Control）與讀取屬性；Impersonating: <COMPUTER>\<USER>
時間         : 18:10:48、18:10:54、18:10:57
```

同一份紀錄中，同一個 `svchost.exe` 以使用者身分開計算機與 Store 的資料夾，結果是**成功**。

## 6. 修復指令的輸出（U，C 的指令，2026-10-25 約 19:00 與 19:40）

**Xaml 2.8 x64（加 `BUILTIN\Users`）：**

```
已順利處理 16 個檔案; 0 個檔案處理失敗
```

**四個 x64 框架，第一次（沒有先 `takeown`）：** 大部分項目回「存取被拒」，例如

```
NET Native Framework 2.2 x64: 已順利處理 0 個檔案; 11 個檔案處理失敗
VCLibs 140 x64:               已順利處理 0 個檔案; 21 個檔案處理失敗
VCLibs UWPDesktop 14 x64:     已順利處理 6 個檔案; 29 個檔案處理失敗
```

**先 `takeown /a /r /d y` 再授權之後：**

```
== microsoft.net.native.framework.2.2_2.2.29512.0_x64__8wekyb3d8bbwe
已順利處理 11 個檔案; 0 個檔案處理失敗
根目錄 Users 條目: 1    AppxManifest.xml Users 條目: 1

== microsoft.net.native.runtime.2.2_2.2.28604.0_x64__8wekyb3d8bbwe
已順利處理 12 個檔案; 0 個檔案處理失敗
根目錄 Users 條目: 1    AppxManifest.xml Users 條目: 1

== microsoft.vclibs.140.00_14.0.33519.0_x64__8wekyb3d8bbwe
已順利處理 21 個檔案; 0 個檔案處理失敗
根目錄 Users 條目: 1    AppxManifest.xml Users 條目: 1

== microsoft.vclibs.140.00.uwpdesktop_14.0.33728.0_x64__8wekyb3d8bbwe
已順利處理 35 個檔案; 0 個檔案處理失敗
根目錄 Users 條目: 1    AppxManifest.xml Users 條目: 1
```

## 7. 驗證：Store 開啟（U，2026-10-25 19:53）

```
Name         Id StartTime
----         -- ---------
WinStore.App 14104 2026/10/25 下午 07:53:35
```

同時段 AppModel-Runtime 沒有 57 與 61。計算機的 5961：

```
TimeCreated : 2026/10/25 下午 07:53:14
Message     : Microsoft.WindowsCalculator_8wekyb3d8bbwe!App 啟用失敗。錯誤碼: 應用程式未啟動。。啟用階段: COM ActivateExtension
```

## 8. 主因 B：5961 的 XML（U，2026-10-26 00:58）

```xml
<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>
  <System>
    <Provider Name='Microsoft-Windows-Immersive-Shell' Guid='{315a8872-923e-4ea2-9889-33cd4754bf64}'/>
    <EventID>5961</EventID> <Level>2</Level>
    <Channel>Microsoft-Windows-TWinUI/Operational</Channel>
    <Computer><COMPUTER></Computer>
    <Security UserID='S-1-5-21-<…>-1001'/>
  </System>
  <EventData>
    <Data Name='AppId'>Microsoft.WindowsCalculator_8wekyb3d8bbwe!App</Data>
    <Data Name='ErrorCode'>-2144927141</Data>
    <Data Name='PhaseFlags'>34</Data>
  </EventData>
</Event>
```

## 9. 五個 App 對照（U，C 的腳本，2026-10-26 01:09 之後）

```
計算機    5961 錯誤: 1 筆
相片     5961 錯誤: 0 筆
時鐘     5961 錯誤: 1 筆
相機     5961 錯誤: 1 筆
便利貼    5961 錯誤: 1 筆
```

## 10. 被誤導的證據：DistributedCOM 10016（U，2026-10-26 00:58）

```
電腦預設 權限設定無法將含有 CLSID {C2F03A33-21F5-47FA-B4BB-156362A2F239} 與 APPID {316CDED5-E4AE-4B15-9113-7055D84DCC97} 之 COM 伺服器應用程式的 本機 啟用 權限授與來自位址 LocalHost (使用 LRPC) (在應用程式容器 Microsoft.Windows.ShellExperienceHost_10.0.19041.5072_neutral_neutral_cw5n1h2txyewy SID (S-1-15-2-…) 中執行) 的使用者 <COMPUTER>\<USER> SID (S-1-5-21-<…>-1001)。
```

後續：`DefaultLaunchPermission` 的 SDDL 是 `O:BAG:BAD:(A;;CCDCLCSWRP;;;BA)(A;;CCDCLCSWRP;;;IU)(A;;CCDCLCSWRP;;;SY)`，`IU` 有本機啟動與啟用；這個 AppID 沒有自己的 `LaunchPermission`；用 `shell:AppsFolder` 啟動時沒有 10016，計算機照樣失敗。

## 11. 主因 B：修復腳本的執行紀錄（G 的腳本，U 輸出）

```
[12:44:28] [INFO] FixAllNativeApps=False SkipGamingServicesRemoval=False
… （ACL 修復、框架註冊、使用者資料夾改名備份、重新註冊）
成功：CalculatorApp PID=5104                                   （約 12:44:52）

[13:15:26] [INFO] FixAllNativeApps=True SkipGamingServicesRemoval=False
… （計算機、鬧鐘、便利貼、相機各自備份使用者資料夾並重新註冊）
```

留下的備份資料夾：`Microsoft.WindowsCalculator_8wekyb3d8bbwe.bak_124442`、`…bak_131539`；`Microsoft.WindowsAlarms_8wekyb3d8bbwe.bak_131540`；`Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe.bak_131541`；`Microsoft.WindowsCamera_8wekyb3d8bbwe.bak_131543`。

## 12. 排除項目的輸出（U）

```
FriendlyName           MediaType HealthStatus OperationalStatus
WDC WDS500G2B0C-00PXH0 SSD       Healthy      OK
Temperature: 46    Wear: 0       （ReadErrorsTotal、WriteErrorsTotal、PowerOnHours 空白）

PS> Repair-Volume -DriveLetter C -Scan
NoErrorsFound

DISM:  未偵測到元件存放區損毀。操作順利完成。
sfc /verifyonly:  Windows 資源保護找不到任何完整性違規。

Windows 記憶體診斷已測試電腦的記憶體，且未偵測到問題   （事件 1101、1201，2026-10-25 01:22:49）

gpresult /h:  已套用的 GPO：（空）；設定：沒有設定定義。
Windows 安全性 → 保護歷程記錄：沒有任何最近的動作

CodeIntegrity/Operational:  Id 3084  Code Integrity will enable WHQL driver enforcement for this boot session.
AppIDSvc:  Stopped
```

## 13. 副作用的證據（U）

```
PS> takeown /f "C:\Windows\System32\config\SOFTWARE"
成功: 檔案 (或資料夾): "C:\Windows\System32\config\SOFTWARE" 目前已經由使用者 "<COMPUTER>\<USER>" 擁有。

PS> icacls C:\Users /grant "*S-1-15-2-1:(OI)(CI)(RX)" /T /C   （G 建議）
已順利處理 37433 個檔案; 3743 個檔案處理失敗
```

restore-appx 對 `C:\ProgramData\Packages` 的操作（節錄）：

```
[Warning] Detected potentially broken ACLs on C:\ProgramData\Packages (Owner=S-1-5-18). Attempting repair...
[Info] Backed up current ACLs: C:\Users\<USER>\AppData\Local\Temp\Restore-AppX\AclBackup_ProgramDataPackages_C__ProgramData_Packages_20261025_020600.txt
[Warning] Repairing ACLs for C:\ProgramData\Packages (root-only (then recursive grants))
[Success] ProgramData Packages ACL repair completed.
```
