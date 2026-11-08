<p align="center">
  <img src="docs/icon.png" width="120" height="120" alt="Strata Monitor icon: a violet-to-mint gauge ring around a pulse line">
</p>

<h1 align="center">Strata Monitor</h1>

<p align="center">
  A system monitor that lives in the macOS menu bar.<br>
  CPU, GPU, memory, disk, network, battery and devices, with the processes behind each reading.
</p>

<p align="center">
  <a href="https://github.com/cristipufu/strata-monitor/releases/latest"><img src="https://img.shields.io/github/v/release/cristipufu/strata-monitor?style=flat&amp;label=release&amp;color=8150cf" alt="Latest release" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/macOS-26%2B-555555?style=flat&amp;logo=apple&amp;logoColor=white" alt="Requires macOS 26 or later" height="20"></a>
  <a href="#install"><img src="https://img.shields.io/badge/Apple%20silicon-555555?style=flat" alt="For Macs with Apple silicon" height="20"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555?style=flat" alt="MIT license" height="20"></a>
</p>

<p align="center">
  <a href="#menu-bar">Menu bar</a> ·
  <a href="#panel">Panel</a> ·
  <a href="#explorer">Explorer</a> ·
  <a href="#system-processes">System processes</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#install">Install</a>
</p>

<p align="center">
  <img src="docs/screenshots/menubar-unfold.gif" width="600" alt="The menu bar item unfolding into CPU, battery and Wi-Fi readings, with hidden menu bar items appearing beside it">
</p>

<p align="center">
  <img src="docs/screenshots/panel-cpu-light.png#gh-light-mode-only" width="260" align="top" alt="CPU tab: total load with the last minute, the busiest processes, per-core load and the last hour"><img src="docs/screenshots/panel-cpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="CPU tab: total load with the last minute, the busiest processes, per-core load and the last hour">&nbsp;
  <img src="docs/screenshots/panel-overview-light.png#gh-light-mode-only" width="260" align="top" alt="Overview tab: Mac status, CPU, memory and network tiles, the busiest processes and device tiles"><img src="docs/screenshots/panel-overview-dark.png#gh-dark-mode-only" width="260" align="top" alt="Overview tab: Mac status, CPU, memory and network tiles, the busiest processes and device tiles">&nbsp;
  <img src="docs/screenshots/panel-memory-light.png#gh-light-mode-only" width="260" align="top" alt="Memory tab: memory used and pressure, the largest processes, the breakdown and the last hour"><img src="docs/screenshots/panel-memory-dark.png#gh-dark-mode-only" width="260" align="top" alt="Memory tab: memory used and pressure, the largest processes, the breakdown and the last hour">
</p>

## Menu bar

- **Three readings in one item.** A ring, a center value and a bar. Pick what each shows in
  Settings, and save combinations as profiles.
- **Hover to unfold.** The item opens into separate readings, and the menu bar items to its left,
  hidden until then, appear beside it. No Accessibility or Screen Recording access needed.
- **Moments.** The item briefly shows what just changed: power connected or on battery, low
  battery, a new sound output, mute, a drive mounted or removed, the network dropping or returning,
  a Bluetooth device connecting, or a process staying heavy for minutes. Optional.

<p align="center">
  <img src="docs/screenshots/menubar-moments.gif" width="600" alt="Moments in the menu bar: power connected, headphones, muted, a drive mounted, a busy process, network unavailable and low battery">
</p>

## Panel

Click the item for one tab per area. Every tab has the same layout, top to bottom: notices, the
current value and its last minute, the processes using the most, a breakdown, the last hour or
day, then the tab's lists and controls.

| Tab | Shows |
|---|---|
| **Overview** | Mac status (CPU, Memory, Temperature, Disk, GPU, Power), live tiles, busiest processes |
| **CPU** | Total load, busiest processes, per-core load, thermal pressure, history |
| **GPU** | GPU load, rendering and geometry, GPU memory, processes using the GPU, history |
| **Memory** | Used and pressure, largest processes, active, wired, compressed, cache, swap, history |
| **Disk** | Free space, processes writing the most, read and write rates, volumes |
| **Network** | Download and upload, processes using the network, interfaces, port lookup, history |
| **Battery** | Charge and time left, power by process, power source, health, what keeps the Mac awake |
| **Wi-Fi** | Network and signal, on/off, nearby networks |
| **Bluetooth** | Paired devices, connect/disconnect, accessory batteries |
| **Sound** | Volume, mute, output |
| **Displays** | Modes, resolution and mirroring previews with a 15-second undo, Keep Awake |

<p align="center">
  <img src="docs/screenshots/panel-gpu-light.png#gh-light-mode-only" width="260" align="top" alt="GPU tab"><img src="docs/screenshots/panel-gpu-dark.png#gh-dark-mode-only" width="260" align="top" alt="GPU tab">&nbsp;
  <img src="docs/screenshots/panel-battery-light.png#gh-light-mode-only" width="260" align="top" alt="Battery tab: charge, power use by process, power source, battery health and sleep status"><img src="docs/screenshots/panel-battery-dark.png#gh-dark-mode-only" width="260" align="top" alt="Battery tab: charge, power use by process, power source, battery health and sleep status">&nbsp;
  <img src="docs/screenshots/panel-network-light.png#gh-light-mode-only" width="260" align="top" alt="Network tab"><img src="docs/screenshots/panel-network-dark.png#gh-dark-mode-only" width="260" align="top" alt="Network tab">
</p>

**View All** on any tab opens the Explorer sorted by that tab's measure. Values not measured yet
show "—", values macOS doesn't provide show Unavailable, and estimates are marked ≈.

## Explorer

Every process on the Mac, including other users' and system processes, plus ports and open files.

- **Processes or Families**: a flat list or a process tree with totals per family.
- **Search** by name, `pid:123`, `uid:501`, `user:root` or `port:3000`. **Show** filters to your
  processes, other users, system, applications, active or paused.
- **Columns** for CPU time, threads, power, wakeups, disk, GPU, state, kind and start time.
- **Inspector** with recent history, power, GPU, signing, arguments and libraries. Interpreters
  and build tools show their project, such as `bun · api`.
- **Actions**: Pause and Resume, Quit, Terminate and Force Quit (confirmed), Sample for 3 Seconds,
  stop the process holding a port, JSON export. Keyboard shortcuts in the **Process** menu.
- **Timeline** of sustained CPU, power, memory growth and wakeups, from history.

History stays on the Mac for 24 hours by default (Off, 24 hours or 7 days in Settings ▸ Privacy)
and holds readings and process names only, never paths or arguments.

## System processes

macOS gives an app exact readings only for its own user's processes. Without help, Strata Monitor
shows other processes' CPU and memory from Apple's `ps` (marked ≈).

**Show Exact Readings** adds an optional helper for the rest:

- One click where readings are missing, one approval by an administrator in System Settings.
- Read-only: no file contents, arguments, environment, signals, other tools or writes.
- Answers only Strata Monitor signed by the same team, gives full readings only to administrators,
  and exits after 30 idle seconds. Turn it off in Settings ▸ Privacy.

## Privacy

- No account, tracking, analytics or packet capture.
- Public macOS interfaces only.
- History stays on the Mac.
- Location (Wi-Fi names) and Bluetooth access are requested only from their tabs.

## Install

Download the [latest release](https://github.com/cristipufu/strata-monitor/releases/latest) and move
Strata Monitor to Applications. Requires an Apple silicon Mac with macOS 26. Releases are signed
and notarized.

Build from source with Xcode 26 or Swift 6.2:

```sh
git clone https://github.com/cristipufu/strata-monitor.git
cd strata-monitor
scripts/build.sh release
open "build/Strata Monitor.app"
```

## Development

```sh
scripts/test.sh            # all tests, with coverage
scripts/build.sh debug     # debug build in build/
scripts/benchmark.sh       # collection timings in build/benchmark.json
```

| Launch flag | Opens |
|---|---|
| `--preview` | The Explorer (`--preview-self`, `--preview-families`) |
| `--preview-page <tab>` | The panel on one tab |
| `--preview-strip` | The unfolded menu bar item |
| `--demo` | With any preview: made-up data instead of this Mac's |
| `--appearance light\|dark` | With any preview: a fixed appearance |
| `--render-glyphs <file.png>` | Writes a study of the menu bar item |
| `--render-unfold <file.gif>` | Writes the menu bar unfold animation |
| `--render-moments <file.gif>` | Writes the moments animation |

Previews never change your settings. See
[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for the architecture.

## Releasing

Push a tag matching the app version, such as `v0.1.0`. The [release workflow](.github/workflows/release.yml)
tests, signs, notarizes and publishes a disk image and a zip.

## License

[MIT](LICENSE)
