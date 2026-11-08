<p align="center">
  <img src="../../docs/icon.png" width="120" height="120" alt="Strata Monitor 圖示：脈衝線周圍有一個紫羅蘭色到薄荷色的儀表環">
</p>

<h1 align="center">Strata Monitor</h1>

<!-- readme-languages:start -->
<p align="center">
  <a href="../../README.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.ru.md">Русский</a> · <a href="README.uk.md">Українська</a> · <a href="README.zh-Hans.md">简体中文</a> · 繁體中文
</p>
<!-- readme-languages:end -->

<p align="center">
  位於 macOS 功能表列中的系統監視器。<br>
  CPU、GPU、記憶體、磁碟、網路、電池和設備，以及每次讀取背後的進程。
</p>

<p align="center">
  <a href="https://github.com/cristipufu/strata-monitor/releases/latest"><img src="https://img.shields.io/github/v/release/cristipufu/strata-monitor?style=flat&amp;label=release&amp;color=8150cf" alt="最新發布" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/macOS-26%2B-555555?style=flat&amp;logo=apple&amp;logoColor=white" alt="需要 macOS 26 或更高版本" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/Apple%20silicon-555555?style=flat" alt="適用於配備 Apple 晶片的 Mac" height="20"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555?style=flat" alt="麻省理工學院許可證" height="20"></a>
</p>

<p align="center">
  <a href="#menu-bar">選單列</a> ·
  <a href="#panel">控制板</a> ·
  <a href="#explorer">探險家</a> ·
  <a href="#system-processes">系統流程</a> ·
  <a href="#privacy">隱私</a> ·
  <a href="#install">安裝</a>
</p>

<p align="center">
  <img src="../../docs/screenshots/menubar-unfold.gif" width="600" alt="選單列項目展開為 CPU、電池和 Wi-Fi 讀數，隱藏的選單列項目出現在其旁邊">
</p>

<p align="center">
  <img src="../../docs/screenshots/panel-cpu-light.png#gh-light-mode-only" width="260" align="top" alt="CPU 選項卡：最後一分鐘的總負載、最繁忙的進程、每個核心負載和最後一小時"><img src="../../docs/screenshots/panel-cpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="CPU 選項卡：最後一分鐘的總負載、最繁忙的進程、每個核心負載和最後一小時">&nbsp;
  <img src="../../docs/screenshots/panel-overview-light.png#gh-light-mode-only" width="260" align="top" alt="概覽標籤：Mac 狀態、CPU、記憶體和網路圖塊、最繁忙的進程和裝置圖塊"><img src="../../docs/screenshots/panel-overview-dark.png#gh-dark-mode-only" width="260" align="top" alt="概覽標籤：Mac 狀態、CPU、記憶體和網路圖塊、最繁忙的進程和裝置圖塊">&nbsp;
  <img src="../../docs/screenshots/panel-memory-light.png#gh-light-mode-only" width="260" align="top" alt="記憶體標籤：已使用的記憶體和壓力、最大進程、故障和最後一小時"><img src="../../docs/screenshots/panel-memory-dark.png#gh-dark-mode-only" width="260" align="top" alt="記憶體標籤：已使用的記憶體和壓力、最大進程、故障和最後一小時">
</p>

<a id="menu-bar"></a>

## 選單列

- ** 一個項目三個讀數。 ** 一個環、一個中心值和一個條。選擇每個在「設定」中顯示的內容，並將組合儲存為設定檔。
- **H 翻轉以展開。 ** 此項目將開啟為單獨的讀數，並且其左側的功能表列項目（在此之前隱藏）出現在其旁邊。無需輔助使用或螢幕錄製存取權限。
- **Moments.** 本專案簡要顯示了剛剛發生的變更：已連接電源或使用電池、電池電量低、新的聲音輸出、靜音、安裝或移除驅動器、網路斷線或恢復、Bluetooth 設備連接或進程持續很長時間。選修的。

<p align="center">
  <img src="../../docs/screenshots/menubar-moments.gif" width="600" alt="選單列中的時刻：已連接電源、耳機、靜音、已安裝驅動器、進程繁忙、網路不可用和電池電量低">
</p>

<a id="panel"></a>

## 控制板

按一下每個區域一個標籤的項目。每個選項卡都有相同的佈局，從上到下：通知、當前值及其最後一分鐘、使用最多的進程、細分、最後一小時或一天，然後是選項卡的列表和控制項。

| 選項卡 | 演出 |
|---|---|
| **概述** | Mac 狀態（CPU、記憶體、溫度、磁碟、GPU、電源）、動態磁貼、最繁忙的進程 |
| **CPU** | 總負載、最繁忙的進程、每核心負載、熱壓力、歷史記錄 |
| **GPU** | GPU 載入、渲染與幾何、GPU 記憶體、使用 GPU 的進程、歷史記錄 |
| **內存** | 使用與壓力、最大進程、活動、有線、壓縮、快取、交換、歷史記錄 |
| **磁碟** | 可用空間、寫入次數最多的行程、讀寫速率、卷 |
| **網路** | 下載與上傳、使用網路的進程、介面、連接埠查找、歷史記錄 |
| **電池** | 電量和剩餘時間、按進程計算的電量、電源、運作狀況、使 Mac 保持喚醒狀態的因素 |
| **Wi-Fi** | 網路與訊號、開/關、附近網絡 |
| **Bluetooth** | 配對裝置、連接/斷開、配件電池 |
| **聲音** | 音量、靜音、輸出 |
| **顯示器** | 模式、解析度和鏡像預覽，可在 15 秒內撤消，保持清醒 |

<p align="center">
  <img src="../../docs/screenshots/panel-gpu-light.png#gh-light-mode-only" width="260" align="top" alt="GPU 選項卡"><img src="../../docs/screenshots/panel-gpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="GPU 選項卡">&nbsp;
  <img src="../../docs/screenshots/panel-battery-light.png#gh-light-mode-only" width="260" align="top" alt="電池標籤：充電、進程用電量、電源、電池健康狀況和睡眠狀態"><img src="../../docs/screenshots/panel-battery-dark.png#gh-dark-mode-only" width="260" align="top" alt="電池標籤：充電、進程用電量、電源、電池健康狀況和睡眠狀態">&nbsp;
  <img src="../../docs/screenshots/panel-network-light.png#gh-light-mode-only" width="260" align="top" alt="網路選項卡"><img src="../../docs/screenshots/panel-network-dark.png#gh-dark-mode-only" width="260" align="top" alt="網路選項卡">
</p>

任何選項卡上的 ** 查看全部 ** 都會開啟按該選項卡的度量排序的資源管理器。尚未測量的值顯示“—”，未提供的值 macOS 顯示“不可用”，估計值標記為 ≈。

<a id="explorer"></a>

## 探險家

Mac 上的每個進程，包括其他使用者和系統進程，以及連接埠和開啟的檔案。

- **進程或族**：包含每個族總數的平面列表或進程樹。
- ** 依名稱搜尋 **、`pid:123`、`uid:501`、`user:root` 或 `port:3000`。 **Show** 過濾您的流程、其他使用者、系統、應用程式、活動或暫停。
- ** 欄位 ** 用於 CPU 時間、執行緒、電源、喚醒、磁碟、GPU、狀態、種類和啟動時間。
- **Inspector** 具有最近的歷史記錄、功能、GPU、簽章、參數和函式庫。解譯器和建造工具展示了他們的項目，例如`bun · api`。
- **Actions**：暫停和恢復、退出、終止和強制退出（已確認）、取樣 3 秒、停止持有連接埠的進程、JSON 匯出。 **Process** 選單中的鍵盤快速鍵。
- **時間軸**持續的CPU、功率、記憶體成長與喚醒，來自歷史。

預設情況下，歷史記錄會在 Mac 上保留 24 小時（在「設定」▸「隱私」中關閉、24 小時或 7 天），並且僅儲存讀數和進程名稱，而不儲存路徑或參數。

<a id="system-processes"></a>

## 系統流程

macOS 僅為應用程式提供其自身使用者流程的精確讀數。在沒有幫助的情況下，Strata Monitor 顯示其他進程的 CPU 和 Apple 的 `ps`（標記為 ≈）的記憶體。

**Show Exact Readings** 為其餘部分添加了一個可選的助手：

- 在讀數缺失的地方單擊一下，即可在系統設定中獲得管理員的批准。
- 唯讀：無文件內容、參數、環境、訊號、其他工具或寫入。
- 僅回答由同一團隊簽署的 Strata Monitor，僅向管理員提供完整讀數，並在 30 秒空閒秒後退出。在「設定」▸「隱私」中將其關閉。

<a id="privacy"></a>

## 隱私

- 沒有帳戶、追蹤、分析或資料包擷取。
- 僅限公共 macOS 介面。
- 歷史留在 Mac 上。
- 當您手動檢查或允許自動檢查時，更新檢查請聯絡 GitHub。不發送系統讀數。
- 僅從其選項卡請求位置（Wi-Fi 名稱）和 Bluetooth 存取。

<a id="install"></a>

## 安裝

下載[最新版本](https://github.com/cristipufu/strata-monitor/releases/latest) 並將 Strata Monitor 移至應用程式。需配備 macOS 26 的 Apple 矽 Mac。發布已簽署並經公證。

使用 Xcode 26 或 Swift 6.2 從原始碼建構：

```sh
git clone https://github.com/cristipufu/strata-monitor.git
cd strata-monitor
scripts/build.sh release
open "build/Strata Monitor.app"
```

<a id="updates-and-languages"></a>

## 更新和語言

使用Strata Monitor選單中的**檢查更新…**，或在**設定▸常規▸更新**中啟用日常檢查和自動安裝。更新和更新來源已簽署。應用程式退出時會自動安裝。

該應用程式支援 22 種語言。在 ** 設定 ▸ 常規 ▸ 語言 ** 中選擇一項，然後退出並重新開啟應用程序，或使用在 macOS 中選擇的語言。本自述文件有英文、日文、韓文、俄文、烏克蘭文、簡體中文和繁體中文版本。

<a id="development"></a>

## 發展

```sh
scripts/test.sh            # all tests, with coverage
scripts/build.sh debug     # debug build in build/
scripts/benchmark.sh       # collection timings in build/benchmark.json
```

| 發射旗 | 打開 |
|---|---|
| `--preview` | 探索者 (`--preview-self`、`--preview-families`) |
| `--preview-page <tab>` | 面板位於一個標籤上 |
| `--preview-strip` | 展開的選單列項 |
| `--demo` | 任何預覽：都是虛構的數據，而不是本機的數據 |
| `--appearance light\|dark` | 任何預覽：固定外觀 |
| `--render-glyphs <file.png>` | 寫一篇關於選單列專案的研究 |
| `--render-unfold <file.gif>` | 編寫選單列展開動畫 |
| `--render-moments <file.gif>` | 寫下精彩瞬間的動畫 |

預覽永遠不會改變您的設定。請參閱 [docs/IMPLMENTATION.md](../../docs/IMPLEMENTATION.md) 以了解架構。

<a id="releasing"></a>

## 釋放

推送與應用程式版本相符的標籤，如`v0.1.0`。 [發布工作流程](../../.github/workflows/release.yml) 測試、簽署、公證並發布磁碟映像和 zip。

<a id="contributing-and-security"></a>

## 貢獻和安全

歡迎錯誤報告、翻譯和代碼。請參閱 [CONTRIBUTING.md](../../CONTRIBUTING.md) 進行設定和檢查，並參閱 [SECURITY.md](../../SECURITY.md) 私下報告漏洞。

<a id="license"></a>

## 執照

[麻省理工學院](../../LICENSE)。有關捆綁軟體，請參閱[第三方聲明](../../THIRD_PARTY_NOTICES.md)。
