<p align="center">
  <img src="../../docs/icon.png" width="120" height="120" alt="Strata Monitor アイコン: パルス ラインの周りの紫からミントのゲージ リング">
</p>

<h1 align="center">Strata Monitor</h1>

<!-- readme-languages:start -->
<p align="center">
  <a href="../../README.md">English</a> · 日本語 · <a href="README.ko.md">한국어</a> · <a href="README.ru.md">Русский</a> · <a href="README.uk.md">Українська</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a>
</p>
<!-- readme-languages:end -->

<p align="center">
  macOS メニュー バーにあるシステム モニター。<br>
  CPU、GPU、メモリ、ディスク、ネットワーク、バッテリー、デバイスと各読み取りの背後にあるプロセス。
</p>

<p align="center">
  <a href="https://github.com/cristipufu/strata-monitor/releases/latest"><img src="https://img.shields.io/github/v/release/cristipufu/strata-monitor?style=flat&amp;label=release&amp;color=8150cf" alt="最新リリース" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/macOS-26%2B-555555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 26 以降が必要" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/Apple%20silicon-555555?style=flat" alt="Apple シリコンを搭載した Mac の場合" height="20"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555?style=flat" alt="MITライセンス" height="20"></a>
</p>

<p align="center">
  <a href="#menu-bar">メニューバー</a> ·
  <a href="#panel">パネル</a> ·
  <a href="#explorer">エクスプローラ</a> ·
  <a href="#system-processes">システムプロセス</a> ·
  <a href="#privacy">プライバシー</a> ·
  <a href="#install">インストール</a>
</p>

<p align="center">
  <img src="../../docs/screenshots/menubar-unfold.gif" width="600" alt="メニュー バー項目が CPU、バッテリー、Wi-Fi 測定値に展開され、その横に非表示のメニュー バー項目が表示されます">
</p>

<p align="center">
  <img src="../../docs/screenshots/panel-cpu-light.png#gh-light-mode-only" width="260" align="top" alt="CPU タブ: 過去 1 分間の合計負荷、最もビジーなプロセス、コアごとの負荷、過去 1 時間"><img src="../../docs/screenshots/panel-cpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="CPU タブ: 過去 1 分間の合計負荷、最もビジーなプロセス、コアごとの負荷、過去 1 時間">&nbsp;
  <img src="../../docs/screenshots/panel-overview-light.png#gh-light-mode-only" width="260" align="top" alt="[概要] タブ: Mac ステータス、CPU、メモリとネットワーク タイル、最もビジーなプロセスとデバイス タイル"><img src="../../docs/screenshots/panel-overview-dark.png#gh-dark-mode-only" width="260" align="top" alt="[概要] タブ: Mac ステータス、CPU、メモリとネットワーク タイル、最もビジーなプロセスとデバイス タイル">&nbsp;
  <img src="../../docs/screenshots/panel-memory-light.png#gh-light-mode-only" width="260" align="top" alt="「メモリ」タブ: 使用されているメモリと負荷、最大プロセス、内訳と過去 1 時間"><img src="../../docs/screenshots/panel-memory-dark.png#gh-dark-mode-only" width="260" align="top" alt="「メモリ」タブ: 使用されているメモリと負荷、最大プロセス、内訳と過去 1 時間">
</p>

<a id="menu-bar"></a>

## メニューバー

- **1 つの項目で 3 つの測定値。** リング、中心値、バー。 [設定] でそれぞれに表示される内容を選択し、組み合わせをプロファイルとして保存します。
- **マウスを移動して展開します。** 項目が別の読み上げ形式で開き、それまで非表示だった左側のメニュー バー項目がその横に表示されます。アクセシビリティや画面録画へのアクセスは必要ありません。
- **Moments.** この項目は、変更された内容を簡単に示します: 電源の接続またはバッテリー駆動、バッテリー残量低下、新しいサウンド出力、ミュート、ドライブのマウントまたは取り外し、ネットワークの切断または復帰、Bluetooth デバイスの接続、またはプロセスが数分間重い状態にあること。オプション。

<p align="center">
  <img src="../../docs/screenshots/menubar-moments.gif" width="600" alt="メニュー バーの瞬間: 電源接続、ヘッドフォン、ミュート、ドライブのマウント、ビジー プロセス、ネットワーク利用不可、バッテリー残量低下">
</p>

<a id="panel"></a>

## パネル

エリアごとに 1 つのタブの項目をクリックします。すべてのタブは上から下まで同じレイアウトになっています。通知、現在値とその直前の値、最も使用されているプロセス、内訳、過去 1 時間または 1 日、タブのリストとコントロールが表示されます。

| タブ | 番組 |
|---|---|
| **概要** | Mac ステータス (CPU、メモリ、温度、ディスク、GPU、電源)、ライブ タイル、最もビジーなプロセス |
| **CPU** | 総負荷、最もビジーなプロセス、コアごとの負荷、熱圧力、履歴 |
| **GPU** | GPU ロード、レンダリングとジオメトリ、GPU メモリ、GPU を使用したプロセス、履歴 |
| **メモリ** | 使用量と圧力、最大プロセス、アクティブ、有線、圧縮、キャッシュ、スワップ、履歴 |
| **ディスク** | 空き容量、最も多くの書き込みプロセス、読み取りおよび書き込み速度、ボリューム |
| **ネットワーク** | ダウンロードとアップロード、ネットワークを使用したプロセス、インターフェース、ポート検索、履歴 |
| **バッテリー** | 充電量と残り時間、プロセスごとの電力供給、電源、状態、Mac をスリープ状態に保つもの |
| **Wi-Fi** | ネットワークと信号、オン/オフ、近くのネットワーク |
| **Bluetooth** | ペアリングされたデバイス、接続/切断、付属バッテリー |
| **サウンド** | ボリューム、ミュート、出力 |
| **表示** | モード、解像度、15 秒間の元に戻すことができるミラーリング プレビュー、Keep Awake |

<p align="center">
  <img src="../../docs/screenshots/panel-gpu-light.png#gh-light-mode-only" width="260" align="top" alt="GPUタブ"><img src="../../docs/screenshots/panel-gpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="GPUタブ">&nbsp;
  <img src="../../docs/screenshots/panel-battery-light.png#gh-light-mode-only" width="260" align="top" alt="「バッテリー」タブ: 充電、プロセス別の電力使用、電源、バッテリーの状態、スリープ状態"><img src="../../docs/screenshots/panel-battery-dark.png#gh-dark-mode-only" width="260" align="top" alt="「バッテリー」タブ: 充電、プロセス別の電力使用、電源、バッテリーの状態、スリープ状態">&nbsp;
  <img src="../../docs/screenshots/panel-network-light.png#gh-light-mode-only" width="260" align="top" alt="「ネットワーク」タブ"><img src="../../docs/screenshots/panel-network-dark.png#gh-dark-mode-only" width="260" align="top" alt="「ネットワーク」タブ">
</p>

任意のタブで **View All** を実行すると、そのタブのメジャーで並べ替えられたエクスプローラーが開きます。まだ測定されていない値は「—」と表示され、macOS が提供していない値は「利用不可」と表示され、推定値は ≈ とマークされます。

<a id="explorer"></a>

## エクスプローラ

他のユーザーやシステム プロセス、ポートや開いているファイルを含む、Mac 上のすべてのプロセス。

- **プロセスまたはファミリー**: ファミリごとの合計を含むフラット リストまたはプロセス ツリー。
- **** を名前、`pid:123`、`uid:501`、`user:root`、または `port:3000` で検索します。 **Show** は、プロセス、他のユーザー、システム、アプリケーション、アクティブまたは一時停止にフィルターをかけます。
- **列** (CPU時間、スレッド、電力、ウェイクアップ、ディスク、GPU、状態、種類、開始時間)。
- 最近の履歴、パワー、GPU、署名、引数、ライブラリを備えた **Inspector**。インタプリタとビルド ツールは、`bun · api` などのプロジェクトを表示します。
- **Aアクション**: 一時停止と再開、終了、終了と強制終了 (確認済み)、3 秒間のサンプル、ポートを保持しているプロセスの停止、JSON エクスポート。 **Process** メニューのキーボード ショートカット。
- **タイムライン**、持続的なCPU、パワー、メモリの増加、目覚め、歴史から。

履歴はデフォルトで Mac に 24 時間保持され ([設定] ▸ [プライバシー] で [オフ]、24 時間または 7 日間)、読み取り値とプロセス名のみが保持され、パスや引数は保持されません。

<a id="system-processes"></a>

## システムプロセス

macOS は、アプリ自身のユーザーのプロセスについてのみ正確な読み取り値をアプリに提供します。助けがなければ、Strata Monitor は他のプロセスの CPU と Apple の `ps` (≈ とマーク) のメモリを表示します。

**Show Exact Readings** は、残りのオプションのヘルパーを追加します。

- 測定値が欠落している場合は 1 回クリックし、システム設定で管理者が 1 回承認します。
- 読み取り専用: ファイルの内容、引数、環境、シグナル、その他のツール、または書き込みはありません。
- 同じチームによって署名された Strata Monitor のみに回答し、完全な読み取り値は管理者にのみ提供され、30 秒のアイドル状態後に終了します。 [設定] ▸ [プライバシー] でオフにします。

<a id="privacy"></a>

## プライバシー

- アカウント、追跡、分析、パケット キャプチャはありません。
- パブリック macOS インターフェイスのみ。
- 履歴は Mac に残ります。
- 手動でチェックする場合、または自動チェックを許可する場合、更新チェックは GitHub に連絡します。システム測定値は送信されません。
- 場所 (Wi-Fi 名) と Bluetooth アクセスは、タブからのみ要求されます。

<a id="install"></a>

## インストール

[最新リリース](https://github.com/cristipufu/strata-monitor/releases/latest) をダウンロードし、Strata Monitor をアプリケーションに移動します。 macOS 26 を搭載した Apple シリコン Mac が必要です。リリースは署名され、公証されています。

Xcode 26 または Swift 6.2 を使用してソースからビルドします。

```sh
git clone https://github.com/cristipufu/strata-monitor.git
cd strata-monitor
scripts/build.sh release
open "build/Strata Monitor.app"
```

<a id="updates-and-languages"></a>

## アップデートと言語

Strata Monitor メニューの **Check for Updates…** を使用するか、**Settings ▸ General ▸ Updates** で毎日のチェックと自動インストールを有効にします。更新と更新フィードは署名されています。アプリの終了時に自動インストールが行われます。

アプリは 22 の言語をサポートしています。 [**設定] ▸ [一般] ▸ [言語]** でいずれかを選択し、アプリを終了して再度開くか、macOS で選択した言語を使用します。この README は、英語、日本語、韓国語、ロシア語、ウクライナ語、簡体字中国語、繁体字中国語で利用できます。

<a id="development"></a>

## 発達

```sh
scripts/test.sh            # all tests, with coverage
scripts/build.sh debug     # debug build in build/
scripts/benchmark.sh       # collection timings in build/benchmark.json
```

| 発射フラグ | 開く |
|---|---|
| `--preview` | エクスプローラー (`--preview-self`、`--preview-families`) |
| `--preview-page <tab>` | 1 つのタブ上のパネル |
| `--preview-strip` | 展開されたメニューバー項目 |
| `--demo` | プレビューあり: この Mac の代わりに作成されたデータ |
| `--appearance light\|dark` | プレビューあり: 固定された外観 |
| `--render-glyphs <file.png>` | メニューバー項目の研究を書きます |
| `--render-unfold <file.gif>` | メニューバーの展開アニメーションを書き込みます |
| `--render-moments <file.gif>` | 瞬間のアニメーションを書きます |

プレビューによって設定が変更されることはありません。アーキテクチャについては、[docs/IMPLEMENTATION.md](../../docs/IMPLEMENTATION.md) を参照してください。

<a id="releasing"></a>

## 解放する

アプリのバージョンに一致するタグ (`v0.1.0` など) をプッシュします。 [リリース ワークフロー](../../.github/workflows/release.yml) は、ディスク イメージと zip をテスト、署名、公証し、公開します。

<a id="contributing-and-security"></a>

## 貢献とセキュリティ

バグレポート、翻訳、コードは大歓迎です。セットアップとチェックについては [CONTRIBUTING.md](../../CONTRIBUTING.md) を参照し、脆弱性を非公開で報告するには [SECURITY.md](../../SECURITY.md) を参照してください。

<a id="license"></a>

## ライセンス

[MIT](../../LICENSE)。バンドル ソフトウェアについては、[サードパーティに関する通知](../../THIRD_PARTY_NOTICES.md) を参照してください。
