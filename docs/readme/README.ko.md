<p align="center">
  <img src="../../docs/icon.png" width="120" height="120" alt="Strata Monitor 아이콘: 펄스 라인 주위에 보라색에서 민트색까지의 게이지 링">
</p>

<h1 align="center">Strata Monitor</h1>

<!-- readme-languages:start -->
<p align="center">
  <a href="../../README.md">English</a> · <a href="README.ja.md">日本語</a> · 한국어 · <a href="README.ru.md">Русский</a> · <a href="README.uk.md">Українська</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a>
</p>
<!-- readme-languages:end -->

<p align="center">
  macOS 메뉴 표시줄에 있는 시스템 모니터입니다.<br>
  CPU, GPU, 메모리, 디스크, 네트워크, 배터리 및 장치와 각 판독 이면의 프로세스.
</p>

<p align="center">
  <a href="https://github.com/cristipufu/strata-monitor/releases/latest"><img src="https://img.shields.io/github/v/release/cristipufu/strata-monitor?style=flat&amp;label=release&amp;color=8150cf" alt="최신 릴리스" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/macOS-26%2B-555555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 26 이상이 필요합니다." height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/Apple%20silicon-555555?style=flat" alt="Apple 실리콘이 탑재된 Mac의 경우" height="20"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555?style=flat" alt="MIT 라이센스" height="20"></a>
</p>

<p align="center">
  <a href="#menu-bar">메뉴바</a> ·
  <a href="#panel">패널</a> ·
  <a href="#explorer">탐침</a> ·
  <a href="#system-processes">시스템 프로세스</a> ·
  <a href="#privacy">은둔</a> ·
  <a href="#install">설치하다</a>
</p>

<p align="center">
  <img src="../../docs/screenshots/menubar-unfold.gif" width="600" alt="CPU, 배터리 및 Wi-Fi 판독값으로 펼쳐지는 메뉴 표시줄 항목과 그 옆에 숨겨진 메뉴 표시줄 항목이 표시됨">
</p>

<p align="center">
  <img src="../../docs/screenshots/panel-cpu-light.png#gh-light-mode-only" width="260" align="top" alt="CPU 탭: 마지막 순간의 총 로드, 가장 바쁜 프로세스, 코어당 로드 및 마지막 시간"><img src="../../docs/screenshots/panel-cpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="CPU 탭: 마지막 순간의 총 로드, 가장 바쁜 프로세스, 코어당 로드 및 마지막 시간">&nbsp;
  <img src="../../docs/screenshots/panel-overview-light.png#gh-light-mode-only" width="260" align="top" alt="개요 탭: Mac 상태, CPU, 메모리 및 네트워크 타일, 가장 바쁜 프로세스 및 장치 타일"><img src="../../docs/screenshots/panel-overview-dark.png#gh-dark-mode-only" width="260" align="top" alt="개요 탭: Mac 상태, CPU, 메모리 및 네트워크 타일, 가장 바쁜 프로세스 및 장치 타일">&nbsp;
  <img src="../../docs/screenshots/panel-memory-light.png#gh-light-mode-only" width="260" align="top" alt="메모리 탭: 사용된 메모리 및 압력, 가장 큰 프로세스, 고장 및 지난 시간"><img src="../../docs/screenshots/panel-memory-dark.png#gh-dark-mode-only" width="260" align="top" alt="메모리 탭: 사용된 메모리 및 압력, 가장 큰 프로세스, 고장 및 지난 시간">
</p>

<a id="menu-bar"></a>

## 메뉴바

- **한 항목에 세 개의 판독값이 있습니다.** 링, 중앙 값 및 막대입니다. 설정에서 각각 표시되는 내용을 선택하고 조합을 프로필로 저장하세요.
- **호버를 펼쳐 펼치세요.** 항목이 별도의 판독값으로 열리고 그때까지 숨겨져 있던 왼쪽의 메뉴 표시줄 항목이 옆에 나타납니다. 접근성이나 화면 녹화 액세스가 필요하지 않습니다.
- **Moments.** 이 항목은 전원 연결 또는 배터리 사용, 배터리 부족, 새 사운드 출력, 음소거, 드라이브 장착 또는 제거, 네트워크 끊김 또는 반환, Bluetooth 장치 연결 또는 몇 분 동안 계속 무거운 프로세스 등 방금 변경된 사항을 간략하게 보여줍니다. 선택 과목.

<p align="center">
  <img src="../../docs/screenshots/menubar-moments.gif" width="600" alt="메뉴 표시줄의 순간: 전원 연결됨, 헤드폰, 음소거, 드라이브 장착됨, 바쁜 프로세스, 네트워크 사용 불가 및 배터리 부족">
</p>

<a id="panel"></a>

## 패널

영역당 하나의 탭에 대한 항목을 클릭합니다. 모든 탭에는 위에서 아래로 동일한 레이아웃이 있습니다. 알림, 현재 값 및 마지막 순간, 가장 많이 사용하는 프로세스, 분석, 지난 시간 또는 날짜, 탭 목록 및 컨트롤이 포함됩니다.

| 꼬리표 | 쇼 |
|---|---|
| **개요** | Mac 상태(CPU, 메모리, 온도, 디스크, GPU, 전원), 라이브 타일, 가장 바쁜 프로세스 |
| **CPU** | 총 부하, 가장 바쁜 프로세스, 코어당 부하, 열 압력, 기록 |
| **GPU** | GPU 로드, 렌더링 및 형상, GPU 메모리, GPU를 사용한 프로세스, 기록 |
| **메모리** | 사용 및 압력, 최대 프로세스, 활성, 유선, 압축, 캐시, 스왑, 기록 |
| **디스크** | 여유 공간, 가장 많이 쓰는 프로세스, 읽기 및 쓰기 속도, 볼륨 |
| **네트워크** | 다운로드 및 업로드, 네트워크를 이용한 프로세스, 인터페이스, 포트 조회, 히스토리 |
| **배터리** | 충전 및 남은 시간, 프로세스별 전원, 전원, 상태, Mac을 깨우게 하는 요소 |
| **Wi-Fi** | 네트워크 및 신호, 온/오프, 주변 네트워크 |
| **Bluetooth** | 페어링된 장치, 연결/연결 해제, 액세서리 배터리 |
| **사운드** | 볼륨, 음소거, 출력 |
| **디스플레이** | 15초 실행 취소를 통한 모드, 해상도 및 미러링 미리보기, Keep Awake |

<p align="center">
  <img src="../../docs/screenshots/panel-gpu-light.png#gh-light-mode-only" width="260" align="top" alt="GPU 탭"><img src="../../docs/screenshots/panel-gpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="GPU 탭">&nbsp;
  <img src="../../docs/screenshots/panel-battery-light.png#gh-light-mode-only" width="260" align="top" alt="배터리 탭: 충전, 프로세스별 전력 사용량, 전원, 배터리 상태 및 절전 상태"><img src="../../docs/screenshots/panel-battery-dark.png#gh-dark-mode-only" width="260" align="top" alt="배터리 탭: 충전, 프로세스별 전력 사용량, 전원, 배터리 상태 및 절전 상태">&nbsp;
  <img src="../../docs/screenshots/panel-network-light.png#gh-light-mode-only" width="260" align="top" alt="네트워크 탭"><img src="../../docs/screenshots/panel-network-dark.png#gh-dark-mode-only" width="260" align="top" alt="네트워크 탭">
</p>

**View All**는 탭에서 해당 탭의 측정값별로 정렬된 탐색기를 엽니다. 아직 측정되지 않은 값은 "—"로 표시되고, macOS 값은 사용할 수 없음 표시를 제공하지 않으며 추정치는 ≈로 표시됩니다.

<a id="explorer"></a>

## 탐침

다른 사용자 및 시스템 프로세스, 포트 및 열린 파일을 포함한 Mac의 모든 프로세스.

- **Processes 또는 Families**: 계열당 합계가 포함된 단순 목록 또는 프로세스 트리입니다.
- ****를 이름(`pid:123`, `uid:501`, `user:root` 또는 `port:3000`)으로 검색합니다. **Show** 필터를 프로세스, 다른 사용자, 시스템, 애플리케이션, 활성 또는 일시 중지로 필터링합니다.
- CPU 시간, 스레드, 전원, 웨이크업, 디스크, GPU, 상태, 종류 및 시작 시간에 대한 **Columns**입니다.
- 최근 역사, 성능, GPU, 서명, 인수 및 라이브러리가 포함된 **Inspector**. 통역사 및 빌드 도구는 `bun · api`와 같은 프로젝트를 보여줍니다.
- **Actions**: 일시 중지 및 재개, 종료, 종료 및 강제 종료(확인됨), 3초 동안 샘플, 포트를 보유하고 있는 프로세스 중지, JSON 내보내기. **Process** 메뉴의 키보드 단축키.
- **Timeline**의 지속적인 CPU, 전력, 메모리 성장 및 깨우기, 역사에서.

기록은 기본적으로 24시간 동안 Mac에 유지되며(설정 ▸ 개인 정보 보호에서 끄기, 24시간 또는 7일) 판독값과 프로세스 이름만 보관하며 경로나 인수는 보관하지 않습니다.

<a id="system-processes"></a>

## 시스템 프로세스

macOS는 앱 자체 사용자 프로세스에 대해서만 정확한 판독값을 제공합니다. 도움 없이 Strata Monitor는 다른 프로세스의 CPU와 Apple의 `ps`(≈로 표시)의 메모리를 표시합니다.

**Show Exact Readings**는 나머지 부분에 대한 선택적 도우미를 추가합니다.

- 판독값이 누락된 부분을 한 번 클릭하면 시스템 설정에서 관리자가 한 번 승인할 수 있습니다.
- 읽기 전용: 파일 내용, 인수, 환경, 신호, 기타 도구 또는 쓰기가 없습니다.
- 동일한 팀이 서명한 Strata Monitor에만 응답하고 전체 내용은 관리자에게만 제공하며 30초의 유휴 시간 후에 종료됩니다. 설정 ▸ 개인정보 보호에서 끄세요.

<a id="privacy"></a>

## 은둔

- 계정, 추적, 분석 또는 패킷 캡처가 없습니다.
- 공용 macOS 인터페이스만 해당됩니다.
- 기록은 Mac에 유지됩니다.
- 업데이트 확인은 수동으로 확인하거나 자동 확인을 허용하는 경우 GitHub에 문의하세요. 시스템 판독값은 전송되지 않습니다.
- 위치(Wi-Fi 이름) 및 Bluetooth 액세스는 해당 탭에서만 요청됩니다.

<a id="install"></a>

## 설치하다

[최신 릴리스](https://github.com/cristipufu/strata-monitor/releases/latest)를 다운로드하고 Strata Monitor를 애플리케이션으로 이동하세요. macOS 26이 포함된 Apple 실리콘 Mac이 필요합니다. 릴리스는 서명되고 공증됩니다.

Xcode 26 또는 Swift 6.2를 사용하여 소스에서 빌드:

```sh
git clone https://github.com/cristipufu/strata-monitor.git
cd strata-monitor
scripts/build.sh release
open "build/Strata Monitor.app"
```

<a id="updates-and-languages"></a>

## 업데이트 및 언어

Strata Monitor 메뉴에서 **업데이트 확인…**를 사용하거나 **설정 ▸ 일반 ▸ 업데이트**에서 일일 확인 및 자동 설치를 활성화합니다. 업데이트 및 업데이트 피드가 서명되었습니다. 앱이 종료되면 자동 설치가 발생합니다.

이 앱은 22개 언어를 지원합니다. **설정 ▸ 일반 ▸ 언어**에서 하나를 선택한 다음 앱을 종료했다가 다시 열거나 macOS에서 선택한 언어를 사용하세요. 이 README는 영어, 일본어, 한국어, 러시아어, 우크라이나어, 중국어 간체 및 중국어 번체로 제공됩니다.

<a id="development"></a>

## 개발

```sh
scripts/test.sh            # all tests, with coverage
scripts/build.sh debug     # debug build in build/
scripts/benchmark.sh       # collection timings in build/benchmark.json
```

| 발사 플래그 | 열림 |
|---|---|
| `--preview` | 익스플로러(`--preview-self`, `--preview-families`) |
| `--preview-page <tab>` | 하나의 탭에 있는 패널 |
| `--preview-strip` | 펼쳐진 메뉴바 항목 |
| `--demo` | 미리보기가 있는 경우: 이 Mac의 데이터 대신 구성 데이터 |
| `--appearance light\|dark` | 미리보기 사용 시: 고정된 모양 |
| `--render-glyphs <file.png>` | 메뉴바 항목에 대한 연구를 작성합니다. |
| `--render-unfold <file.gif>` | 메뉴바 펼치기 애니메이션을 작성합니다. |
| `--render-moments <file.gif>` | 순간의 애니메이션을 씁니다 |

미리보기는 설정을 변경하지 않습니다. 아키텍처는 [docs/IMPLEMENTATION.md](../../docs/IMPLEMENTATION.md)를 참조하세요.

<a id="releasing"></a>

## 출시

`v0.1.0`와 같이 앱 버전과 일치하는 태그를 푸시합니다. [릴리스 워크플로](../../.github/workflows/release.yml)는 디스크 이미지와 zip을 테스트, 서명, 공증 및 게시합니다.

<a id="contributing-and-security"></a>

## 기여 및 보안

버그 보고서, 번역 및 코드를 환영합니다. 설정 및 확인은 [CONTRIBUTING.md](../../CONTRIBUTING.md)를 참조하고, 비공개적으로 취약점을 보고하려면 [SECURITY.md](../../SECURITY.md)를 참조하세요.

<a id="license"></a>

## 특허

[MIT](../../LICENSE). 번들 소프트웨어는 [타사 고지 사항](../../THIRD_PARTY_NOTICES.md)을 참조하세요.
