# 07 走錯的路、環境陷阱與留下的副作用

這一份最長，因為它最有用：後人最容易重複這些錯。標記：**C** = Claude，**G** = Grok，**U** = 使用者。

## 一、錯誤的判斷

| # | 誰 | 當時的判斷 | 為什麼錯 | 怎麼發現 |
|---|---|---|---|---|
| 1 | C | 「問題在使用者 `<USER>` 的設定檔，不是整台系統」 | 這是「全部移除」之後的新帳號，`test` 帳號症狀一樣；`%LOCALAPPDATA%\Microsoft\WindowsApps` 存在 | 使用者指出矛盾，也有實測 |
| 2 | C | 「最可能是安全軟體攔截」 | 保護歷程記錄是空的；AppLocker 與 CodeIntegrity 沒有封鎖記錄 | 使用者截圖 |
| 3 | C | 「MDM 殘留可能是原因」 | 23 筆註冊都沒有 `ProviderID` 與服務網址，裝置沒有加入 Azure AD 或網域 | 使用者質疑，查輸出證實 |
| 4 | G | 「缺的是 ALL APPLICATION PACKAGES 與受限 AAP，補上就能過信任檢查」 | 補了仍是 57。主因 A 的檢查以一般使用者身分進行，缺的是 `Users` | Claude 接手時撤回。注意：當時 Claude 的回覆寫成「我前面說…」，把 Grok 的結論當成自己的，歸屬以原始紀錄為準 |
| 5 | C | 診斷腳本標出 27 項「嚴重」 | 多數是腳本誤判：bundle 根目錄與框架套件本來就沒有 `AppxManifest.xml`／`resources.pri`；解析相依名稱出錯導致「相依沒註冊」；框架套件使用能力 SID，不是 AAP，所以「缺 ALL APPLICATION PACKAGES」沒有鑑別力；停止的服務與 0 位元組的 `.srd-wal` 是正常狀態 | 逐項對照原始輸出，撤回 |
| 6 | C、G | 「框架只有 SYSTEM 是 `Staged`，是原因」 | 註冊成 `Installed` 之後症狀不變，只是旁證 | 實測 |
| 7 | G | 重註冊框架就能修 | 狀態變 `Installed`，權限沒變 | 無效 |
| 8 | G | 讓 `CodeIntegrity.cat` 可讀 | 檔案可讀了，仍是 57 | Claude 分析 |
| 9 | G | restore-appx 能修 | 無效，且有副作用（見第三節） | 使用者實測 |
| 10 | G | Microsoft-Store-Fix 能修 | 把 Framework 1.7 硬塞進 Store 的相依，`0x80073CF3` | 使用者實測 |
| 11 | G | 對 `C:\Users` 遞迴授 ALL APPLICATION PACKAGES 讀取（依 KB 2798317 轉成的作法） | 與啟動鏈無關；讓所有 Store 沙箱程式能讀使用者資料夾 | Procmon 沒有任何與 `C:\Users` 有關的相關拒絕 |
| 12 | G | `takeown /f C:\Windows\System32\config\SOFTWARE`、`cacls /s` 覆寫 WindowsApps 根目錄 DACL | 前者改了登錄檔檔案的擁有者；後者是用網路文章的 SDDL 整個取代權限，沒有備份就無法回復 | Claude 審查。前者已執行；後者是否執行未確認 |
| 13 | C | 比對 `PackagedCom`、`ActivatableClasses` 登錄，找計算機缺什麼 | 計算機沒有 `comServer` 擴充點，本來就沒有；`ActivatableClasses` 路徑連 Store 也查不到 | 讀清單檔後撤回 |
| 14 | C | DistributedCOM 10016 是計算機的原因，建議改 Immersive Shell 的啟動權限 | 用 `shell:AppsFolder` 啟動時沒有這個事件，計算機照樣失敗 | 路徑對照測試 |
| 15 | G | 5961 的錯誤碼 `-2144927141` 是 `0x8027021B` | 換算錯誤，是 `0x8027025B` | 核對 |
| 16 | C | 用 `ms-windows-calculator:` 協定測試 | 在 SYSTEM 視窗會跳「需要新的應用程式」，與本問題無關 | 使用者截圖 |
| 17 | C | 「`icacls /save` 先做，再 `takeown`」 | 預設權限下，系統管理員讀不到大部分檔案的權限，備份會失敗。順序應該是先記擁有者、再 `takeown`、再備份、最後授權 | 整理本文件時重新推導，尚未在預設權限的機器上驗證 |

## 二、環境與工具的陷阱

| 陷阱 | 說明 | 避開方法 |
|---|---|---|
| **SYSTEM 視窗不是使用者** | `PsExec -s` 開的視窗是 SYSTEM，`whoami` 回 `nt authority\system`。SYSTEM 啟動不了使用者的 UWP App；`Get-AppxPackage`、`HKCU` 看到的是 SYSTEM 的，不是你的。我們有兩次測試因此作廢（19:05、19:23），第一份 ACL 備份也寫進了 SYSTEM 的桌面 | 測試前先 `whoami`。需要提權時，用「以系統管理員身分執行」，不要用 `PsExec -s` |
| **32 位元的 PowerShell** | 沒有 `PsExec64` 時，`PsExec` 開的 PowerShell 是 32 位元。`$env:ProgramFiles` 變成 `C:\Program Files (x86)`；登錄寫入被導到 `WOW6432Node`；`C:\Windows\System32` 被導到 `SysWOW64`。restore-appx 因此去 `takeown` 一個不存在的 `C:\Program Files (x86)\WindowsApps`；它建立的 `PackageRepository` 機碼，在 64 位元視窗裡 `Test-Path` 永遠是 False。（依多個現象的推測，沒有逐一驗證） | `[Environment]::Is64BitProcess` 要是 True |
| **Procmon 的處理序篩選** | 第 1 次只看 `ApplicationFrameHost.exe`，拒絕發生在 `svchost.exe`，完全看不到 | 只篩 `Result is ACCESS DENIED`，不加處理序條件 |
| **沒有 `takeown` 就 `icacls /grant`** | `WindowsApps` 底下的資料夾擁有者是 TrustedInstaller 或 SYSTEM，系統管理員沒有 `WRITE_DAC` | 先 `takeown /a`，用 SID 不用名稱 |
| **`icacls /save` 的還原要對父資料夾** | 備份檔裡的名稱是相對於父資料夾 | `icacls "<父資料夾>" /restore <備份檔>` |
| **`icacls /save` 只存 DACL，不存擁有者** | 擁有者要另外記錄與還原 | 備份時另存擁有者 |
| **PowerShell 變數不分大小寫** | Grok 的腳本裡 `$Log` 與迴圈裡的 `$log` 是同一個變數，後半寫檔全部失敗 | 用不同名稱 |
| **指令寫錯** | `Get-AppxPackageLog` 不存在，正確是 `Get-AppPackageLog`（還要活動識別碼）；教學裡有一處用了未定義的 `$appx` | 先試跑再貼 |
| **貼上多行指令** | 換行被吃掉，變成 `Format-List$t0` | 分段貼 |
| **兩個 AI 互相貼對話** | 結論的歸屬會混淆 | 這份文件的 [08](08-who-said-what.md) 重新歸屬 |
| **非英文系統的群組名稱** | `BUILTIN\Users` 在不同語系可能顯示不同；受限應用程式封包在中文系統顯示為「所以受限制的應用程式封包」 | 用 SID：Users `S-1-5-32-545`、Administrators `S-1-5-32-544`、AAP `S-1-15-2-1`、受限 AAP `S-1-15-2-2` |
| **網路上的「還原預設權限」教學** | `icacls /reset` 會把明確寫的條目清掉，包括我們補上的 `Users` | 先備份，修好之後不要再 `/reset` |

## 三、留下的副作用

修好之後我們沒有立刻清理，盤點出下列變更。處理方式見 [10](10-cleanup-and-rollback.md)。

| # | 變更 | 來源 | 風險 | 建議 |
|---|---|---|---|---|
| 1 | `C:\Users` 底下幾萬個物件被加上 ALL APPLICATION PACKAGES 讀取（37,433 處理、3,743 失敗） | G 建議、U 執行 | **高**：所有 Store 沙箱程式能讀你的使用者資料夾 | 移除；先備份、測試、失敗自動還原 |
| 2 | 登錄檔檔案 `C:\Windows\System32\config\SOFTWARE` 的擁有者被改成使用者 | G 建議、U 執行 | 中 | 改回（參考同資料夾其他登錄檔的擁有者） |
| 3 | 框架與 App 資料夾：擁有者改成 Administrators 群組、多了 Administrators 完全控制 | C、G | 低到中 | 選擇性還原；留著風險最小 |
| 4 | `C:\ProgramData\Packages` 的權限被 restore-appx 「修復」；它在 `Temp\Restore-AppX` 留了修改前的備份檔 | G、U | 中 | 用備份還原根目錄；子項目沒有備份 |
| 5 | AppX 資料庫（`StateRepository-*.srd`）被重建，系統 App 與 WindowsApps 套件被重新註冊 | G、U | 無法還原 | 不處理，已和修復混在一起 |
| 6 | 空的 `PackageRepository` 登錄機碼（可能在 `WOW6432Node`） | G、U | 低 | 刪除或留著 |
| 7 | 執行原則曾設成 `Unrestricted` | C、U | 中 | 改回預設 |
| 8 | PsExec（`C:\Windows\PSTools`、`PSEXESVC` 服務）、Procmon 驅動（`PROCMON24`）、Pester 5.9.1、Sysinternals 的 EULA 登錄值 | U | 低 | 刪除 |
| 9 | restore-appx 停止了幾個服務，「還原狀態」失敗 | G、U | 低到中 | 對照預設啟動類型 |
| 10 | `%LOCALAPPDATA%\Packages\*.bak_*`（修復腳本改名備份的 App 使用者資料） | G | 低 | 確認 App 正常後刪 |
| 11 | 測試檔、輸出、下載的安裝檔與工具（桌面、Downloads、Temp、SYSTEM 設定檔桌面） | C、G、U | 低 | 證據封存，工具刪除 |
| 12 | `Microsoft.GamingServices` 被停止或移除 | G | 中（影響 Xbox、Minecraft） | 從 Store 裝回 |
| 13 | `cacls /s` 是否執行過，**不確定** | G | 高（若執行過） | 檢查 `WindowsApps` 根目錄的 DACL 與擁有者 |
| 14 | 更舊的相依資料夾（Xaml 2.0、NET Native 1.7、Store.Engagement、WebpImageExtension 等）被 `takeown` 並授權 | G、U | 低到中 | 與第 3 項相同，選擇性還原 |

## 四、給之後的人

1. 動 `WindowsApps` 之前，記下擁有者，`takeown` 之後再 `icacls /save`。
2. 一次只動被 Procmon 指到的資料夾；每一步重測。
3. **不要**對整個 `C:\Program Files\WindowsApps` 做 `takeown /r`、`icacls /T` 或 `/setowner`。
4. 測試前 `whoami`；視窗要是 64 位元。
5. 不要因為「有人建議」就套用範圍更大的授權。我們的 `C:\Users` 遞迴授權沒有幫助，還留下安全副作用。
6. 修好之後，立刻把留下的副作用列成清單。我們拖了好幾天才清。
