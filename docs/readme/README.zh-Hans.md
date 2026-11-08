<p align="center">
  <img src="../../docs/icon.png" width="120" height="120" alt="Strata Monitor 图标：脉冲线周围有一个紫罗兰色到薄荷色的仪表环">
</p>

<h1 align="center">Strata Monitor</h1>

<!-- readme-languages:start -->
<p align="center">
  <a href="../../README.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.ru.md">Русский</a> · <a href="README.uk.md">Українська</a> · 简体中文 · <a href="README.zh-Hant.md">繁體中文</a>
</p>
<!-- readme-languages:end -->

<p align="center">
  位于 macOS 菜单栏中的系统监视器。<br>
  CPU、GPU、内存、磁盘、网络、电池和设备，以及每次读取背后的进程。
</p>

<p align="center">
  <a href="https://github.com/cristipufu/strata-monitor/releases/latest"><img src="https://img.shields.io/github/v/release/cristipufu/strata-monitor?style=flat&amp;label=release&amp;color=8150cf" alt="最新发布" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/macOS-26%2B-555555?style=flat&amp;logo=apple&amp;logoColor=white" alt="需要 macOS 26 或更高版本" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/Apple%20silicon-555555?style=flat" alt="适用于配备 Apple 芯片的 Mac" height="20"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555?style=flat" alt="麻省理工学院许可证" height="20"></a>
</p>

<p align="center">
  <a href="#menu-bar">菜单栏</a> ·
  <a href="#panel">控制板</a> ·
  <a href="#explorer">探险家</a> ·
  <a href="#system-processes">系统流程</a> ·
  <a href="#privacy">隐私</a> ·
  <a href="#install">安装</a>
</p>

<p align="center">
  <img src="../../docs/screenshots/menubar-unfold.gif" width="600" alt="菜单栏项目展开为 CPU、电池和 Wi-Fi 读数，隐藏的菜单栏项目出现在其旁边">
</p>

<p align="center">
  <img src="../../docs/screenshots/panel-cpu-light.png#gh-light-mode-only" width="260" align="top" alt="CPU 选项卡：最后一分钟的总负载、最繁忙的进程、每个核心负载和最后一小时"><img src="../../docs/screenshots/panel-cpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="CPU 选项卡：最后一分钟的总负载、最繁忙的进程、每个核心负载和最后一小时">&nbsp;
  <img src="../../docs/screenshots/panel-overview-light.png#gh-light-mode-only" width="260" align="top" alt="概览选项卡：Mac 状态、CPU、内存和网络图块、最繁忙的进程和设备图块"><img src="../../docs/screenshots/panel-overview-dark.png#gh-dark-mode-only" width="260" align="top" alt="概览选项卡：Mac 状态、CPU、内存和网络图块、最繁忙的进程和设备图块">&nbsp;
  <img src="../../docs/screenshots/panel-memory-light.png#gh-light-mode-only" width="260" align="top" alt="内存选项卡：已使用的内存和压力、最大进程、故障和最后一小时"><img src="../../docs/screenshots/panel-memory-dark.png#gh-dark-mode-only" width="260" align="top" alt="内存选项卡：已使用的内存和压力、最大进程、故障和最后一小时">
</p>

<a id="menu-bar"></a>

## 菜单栏

- ** 一个项目三个读数。** 一个环、一个中心值和一个条。选择每个在“设置”中显示的内容，并将组合保存为配置文件。
- **H 翻转以展开。** 该项目将打开为单独的读数，并且其左侧的菜单栏项目（在此之前隐藏）出现在其旁边。无需辅助功能或屏幕录制访问权限。
- **Moments.** 该项目简要显示了刚刚发生的变化：已连接电源或使用电池、电池电量低、新的声音输出、静音、安装或移除驱动器、网络掉线或恢复、Bluetooth 设备连接或进程持续很长时间。选修的。

<p align="center">
  <img src="../../docs/screenshots/menubar-moments.gif" width="600" alt="菜单栏中的时刻：已连接电源、耳机、静音、已安装驱动器、进程繁忙、网络不可用和电池电量低">
</p>

<a id="panel"></a>

## 控制板

单击每个区域一个选项卡的项目。每个选项卡都有相同的布局，从上到下：通知、当前值及其最后一分钟、使用最多的进程、细分、最后一小时或一天，然后是选项卡的列表和控件。

| 选项卡 | 演出 |
|---|---|
| **概述** | Mac 状态（CPU、内存、温度、磁盘、GPU、电源）、动态磁贴、最繁忙的进程 |
| **CPU** | 总负载、最繁忙的进程、每核负载、热压力、历史记录 |
| **GPU** | GPU 加载、渲染和几何、GPU 内存、使用 GPU 的进程、历史记录 |
| **内存** | 使用和压力、最大进程、活动、有线、压缩、缓存、交换、历史记录 |
| **磁盘** | 可用空间、写入次数最多的进程、读写速率、卷 |
| **网络** | 下载和上传、使用网络的进程、接口、端口查找、历史记录 |
| **电池** | 电量和剩余时间、按进程计算的电量、电源、运行状况、使 Mac 保持唤醒状态的因素 |
| **Wi-Fi** | 网络和信号、开/关、附近网络 |
| **Bluetooth** | 配对设备、连接/断开、配件电池 |
| **声音** | 音量、静音、输出 |
| **显示器** | 模式、分辨率和镜像预览，可在 15 秒内撤消，保持清醒 |

<p align="center">
  <img src="../../docs/screenshots/panel-gpu-light.png#gh-light-mode-only" width="260" align="top" alt="GPU 选项卡"><img src="../../docs/screenshots/panel-gpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="GPU 选项卡">&nbsp;
  <img src="../../docs/screenshots/panel-battery-light.png#gh-light-mode-only" width="260" align="top" alt="电池选项卡：充电、进程用电量、电源、电池健康状况和睡眠状态"><img src="../../docs/screenshots/panel-battery-dark.png#gh-dark-mode-only" width="260" align="top" alt="电池选项卡：充电、进程用电量、电源、电池健康状况和睡眠状态">&nbsp;
  <img src="../../docs/screenshots/panel-network-light.png#gh-light-mode-only" width="260" align="top" alt="网络选项卡"><img src="../../docs/screenshots/panel-network-dark.png#gh-dark-mode-only" width="260" align="top" alt="网络选项卡">
</p>

任何选项卡上的 ** 查看全部 ** 都会打开按该选项卡的度量排序的资源管理器。尚未测量的值显示“—”，未提供的值 macOS 显示“不可用”，估计值标记为 ≈。

<a id="explorer"></a>

## 探险家

Mac 上的每个进程，包括其他用户和系统进程，以及端口和打开的文件。

- **进程或族**：包含每个族总数的平面列表或进程树。
- ** 按名称搜索 **、`pid:123`、`uid:501`、`user:root` 或 `port:3000`。 **Show** 过滤您的进程、其他用户、系统、应用程序、活动或暂停。
- ** 列 ** 用于 CPU 时间、线程、电源、唤醒、磁盘、GPU、状态、种类和启动时间。
- **Inspector** 具有最近的历史记录、功能、GPU、签名、参数和库。解释器和构建工具展示了他们的项目，例如`bun · api`。
- **Actions**：暂停和恢复、退出、终止和强制退出（已确认）、采样 3 秒、停止持有端口的进程、JSON 导出。 **Process** 菜单中的键盘快捷键。
- **时间线**持续的CPU、功率、内存增长和唤醒，来自历史。

默认情况下，历史记录会在 Mac 上保留 24 小时（在“设置”▸“隐私”中关闭、24 小时或 7 天），并且仅保存读数和进程名称，而不保存路径或参数。

<a id="system-processes"></a>

## 系统流程

macOS 仅为应用程序提供其自身用户进程的精确读数。在没有帮助的情况下，Strata Monitor 显示其他进程的 CPU 和 Apple 的 `ps`（标记为 ≈）的内存。

**Show Exact Readings** 为其余部分添加了一个可选的助手：

- 在读数缺失的地方单击一下，即可在系统设置中获得管理员的批准。
- 只读：无文件内容、参数、环境、信号、其他工具或写入。
- 仅回答由同一团队签名的 Strata Monitor，仅向管理员提供完整读数，并在 30 秒空闲秒后退出。在“设置”▸“隐私”中将其关闭。

<a id="privacy"></a>

## 隐私

- 没有帐户、跟踪、分析或数据包捕获。
- 仅限公共 macOS 接口。
- 历史留在 Mac 上。
- 当您手动检查或允许自动检查时，更新检查请联系 GitHub。不发送系统读数。
- 仅从其选项卡请求位置（Wi-Fi 名称）和 Bluetooth 访问。

<a id="install"></a>

## 安装

下载[最新版本](https://github.com/cristipufu/strata-monitor/releases/latest) 并将 Strata Monitor 移至应用程序。需要配备 macOS 26 的 Apple 硅 Mac。发布已签名并经过公证。

使用 Xcode 26 或 Swift 6.2 从源代码构建：

```sh
git clone https://github.com/cristipufu/strata-monitor.git
cd strata-monitor
scripts/build.sh release
open "build/Strata Monitor.app"
```

<a id="updates-and-languages"></a>

## 更新和语言

使用Strata Monitor菜单中的**检查更新…**，或在**设置▸常规▸更新**中启用日常检查和自动安装。更新和更新源已签名。应用程序退出时会自动安装。

该应用程序支持 22 种语言。在 ** 设置 ▸ 常规 ▸ 语言 ** 中选择一项，然后退出并重新打开应用程序，或使用在 macOS 中选择的语言。本自述文件有英语、日语、韩语、俄语、乌克兰语、简体中文和繁体中文版本。

<a id="development"></a>

## 发展

```sh
scripts/test.sh            # all tests, with coverage
scripts/build.sh debug     # debug build in build/
scripts/benchmark.sh       # collection timings in build/benchmark.json
```

| 发射旗 | 打开 |
|---|---|
| `--preview` | 探索者 (`--preview-self`、`--preview-families`) |
| `--preview-page <tab>` | 面板位于一个选项卡上 |
| `--preview-strip` | 展开的菜单栏项 |
| `--demo` | 任何预览：都是虚构的数据，而不是本机的数据 |
| `--appearance light\|dark` | 任何预览：固定外观 |
| `--render-glyphs <file.png>` | 写一篇关于菜单栏项目的研究 |
| `--render-unfold <file.gif>` | 编写菜单栏展开动画 |
| `--render-moments <file.gif>` | 写下精彩瞬间的动画 |

预览永远不会改变您的设置。请参阅 [docs/IMPLMENTATION.md](../../docs/IMPLEMENTATION.md) 了解架构。

<a id="releasing"></a>

## 释放

推送与应用版本匹配的标签，如`v0.1.0`。 [发布工作流程](../../.github/workflows/release.yml) 测试、签名、公证并发布磁盘映像和 zip。

<a id="contributing-and-security"></a>

## 贡献和安全

欢迎错误报告、翻译和代码。请参阅 [CONTRIBUTING.md](../../CONTRIBUTING.md) 进行设置和检查，并参阅 [SECURITY.md](../../SECURITY.md) 私下报告漏洞。

<a id="license"></a>

## 执照

[麻省理工学院](../../LICENSE)。有关捆绑软件，请参阅[第三方声明](../../THIRD_PARTY_NOTICES.md)。
