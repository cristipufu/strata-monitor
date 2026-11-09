# Architecture and behavior

Strata Monitor is an original native macOS 26 menu-bar application, implemented in SwiftUI,
AppKit and public system interfaces. The [product plan](../../strata-bar-plan.md) describes
the intended feature set. Reference applications are not dependencies.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `StrataCore` | Measurements, process identities, search, presentation policy, profiles and pure geometry policies |
| `StrataSystem` | Public system collection, device operations, resource inspection, helper registration and client |
| `StrataInventory` | Process and descriptor readers shared by the app and the helper (`CSystem` + `StrataCore` only) |
| `StrataHelperInterface` | The helper's XPC protocol, versions, size limits, payload envelopes and signing requirements |
| `StrataBarHelper` | The optional root helper daemon; links Foundation, Security and `StrataInventory` only |
| `CSystem` | Small C/Objective-C bridges for native process and notification interfaces |
| `StrataBar` | Main-actor presentation, demand coordination, controls, native tables and windows |
| `StrataBenchmark` | Reproducible collection and cancellation benchmarks |

Blocking collection runs off the main actor. Each asynchronous operation owns its cancellation,
identity and publication lifecycle. Separate system and device schedules prevent slow device
queries from pausing CPU history. Resource inspection uses a separate inventory so manual scans
cannot alter periodic CPU-rate baselines. Missing or denied observations remain unavailable.

## Menu-bar interaction

The compact indicator combines a ring, center reading and four lower activity dots. The arc and
dots use one circular contour; stroke, dot diameter, positions and center scale together. Saved
profiles choose readings, colors, tracks and fill styles. Icon size uses discrete values that fit
the native status button; ring weight has Thin, Light, Regular, Bold and Heavy presets. Settings
uses the same drawing for its actual-size and enlarged previews.

Hover expands the ring in place and reveals the status items to its left without activating the
app. One empty owned status item sits immediately left of the ring. Stretching it pushes every item
to its left beyond the display edge; collapsing it to zero width brings them back in place. Its
position beside the ring must be confirmed before anything is hidden, and is confirmed again when
displays change. Preview runs never hide items. The optional Overview
setting also opens a nonactivating panel; disabling it closes a current hover peek. Space near the
notch limits unfolding width and never overrides that preference. Clicking opens an interactive
panel. Motion is interruptible and respects Reduce Motion. Native glass has transparent space
inside its borderless hosting window so its rounded edge does not meet the window boundary.

Power, low-battery, audio, connectivity, Bluetooth and drive changes can briefly replace the normal
reading. A plugged-in battery has a persistent AC badge even when it is not actively charging.
First observations establish event baselines; unavailable readings do not invent disconnects.
Public device notifications request coalesced refreshes, with independent polling as a fallback.

## Revealed item menus

Clicking a revealed item starts a short observation of on-screen window metadata. While a menu or
popover from another process sits at the bar's lower edge across the clicked point, the items stay
revealed; the observation ends when that window closes, or after a brief wait if none opens. It
reads no window contents and needs no Accessibility, Screen Recording or input-monitoring
permission. Strata Monitor never moves other applications' items: macOS Command-drag decides which
side of the ring each item is on.

## Measurements and exploration

CPU includes aggregate and per-core measurements. Process CPU uses 100% per logical core; aggregate
CPU uses 100% for the machine. Memory includes VM categories and swap availability. Network rates
count active physical `en*` interfaces and exclude tunnels to avoid double counting. They are not
per-process network throughput. Disk rates are subtotals of readable process I/O counters.

Every process comes from the kernel's process table (`sysctl` `KERN_PROC_ALL`), so other users'
processes and `kernel_task` are listed with their identity, parent, owner and run state. Usage
counters (task info and `proc_pid_rusage` v6) are read only where the caller may inspect the
process; elsewhere they stay unavailable. A second table read at the end of each scan drops any row
whose PID no longer names the process that was read. Rates come from consecutive scans keyed by
process identity: CPU, disk, power from the kernel's per-process energy counter, wakeups, and the
share of CPU time on performance cores. Per-process GPU time comes from the accelerator's user
clients, which every user may read; it is read only while process readings are wanted.

Processes use PID plus observed start time as identity. Native process, family and resource tables
preserve their column sort, selection, expansion and clicked-row context across updates. Optional
columns are shown from the table header's menu, and each table keeps its own widths, order and
shown columns. Filters (mine, other users, system, applications, active, paused) and search both
keep a match's ancestors in the family tree. Family search retains ancestors and
labels partial measured totals. Selected-process history starts at selection, rather than inventing
older observations. Inspectors retain context when a process ends or becomes unavailable.

Without the helper, `ProcessTableUsageSource` fills other users' CPU time and resident memory
from `/bin/ps` at most every five seconds while a process view is open; its CPU percentage
compares its own launches and is kept as given. Per-process traffic comes from `nettop` while
a Network view is open; sampling uses `/usr/bin/sample` on the user's own processes and checks
the process identity before and after. All three run only through `SystemTool`. Interpreters,
shells and build tools owned by the user are labelled with the project their working
directory belongs to; account names come from the password database and are cached.

`HistoryRecorder` writes readings through `HistoryStore` to day files under Application
Support: tiered system points (2 s, 10 s, 1 min, and 5 min with 7-day retention) and the top
ten processes per minute by CPU, memory, power, disk and network. With nothing open, processes
are read every 30 seconds for history, without `ps`, and rates span that interval.
`EpisodeDetector` turns sustained CPU, power, memory growth, wakeups and system pressure into
episodes for the Explorer timeline and rate-limited menu-bar moments; `DiagnosisEngine` ranks
causes over the last ten minutes for the Overview card. Previews and tests never create a
recorder.

The Battery page reads system power from the smart battery's power telemetry, falling back to the
public power-source interface, and lists sleep assertions per process. Both are read only while
that page is visible. Power telemetry and per-process GPU keys are undocumented, so missing keys
show Unavailable.

Resource inspection distinguishes TCP listeners/connections, bound UDP sockets, endpoints and
accessible files. Filesystem identity scopes are separate from literal path scopes. Signing facts,
arguments and executable mappings are shown where public access permits them. A dyld shared-cache
path does not enumerate every library inside it.

JSON export includes scope, observation times and availability reasons. Arguments require a separate
include-arguments action. Environment variables are not displayed or exported; transient native
argument buffers are scrubbed before release.

Normal Application Quit respects the application's veto. Terminate and Force Quit require a fresh
confirmation bound to the observed process generation through an audit token. No PID-only or forced
fallback silently replaces the requested action. Pause and Resume use the same audit-token path
without a confirmation, because they are reversible; pausing a few session processes (Dock, Finder,
loginwindow and similar) is refused because it freezes the desktop. Strata Monitor records what it
paused and resumes it when it quits, and at the next launch after an unexpected exit.

## Privileged helper

The optional helper (`dev.stratabar.helper`) exists so the Explorer can measure every process
and, for administrators, list other users' ports and open files. It is a launchd daemon registered with
`SMAppService.daemon(plistName:)`; macOS runs it as root only after an administrator approves it
in Login Items & Extensions. The bundle carries it at `Contents/MacOS/StrataBarHelper`, with
`Contents/Library/LaunchDaemons/dev.stratabar.helper.plist` naming it through `BundleProgram`
and advertising one Mach service. There is no `KeepAlive`: launchd starts the helper for the
first message, and it exits 30 seconds after its last request. An open but quiet connection
does not keep it running; the client resends once after the interruption that follows.

The XPC interface has three read-only calls, each answered exactly once with a versioned JSON
envelope (`HelperReply`):

| Call | Returns | Bounds |
| --- | --- | --- |
| `handshake` | helper version, schema version and effective user | per-connection rate limit |
| `processSnapshot` | every process's identity, parent, owner, path, CPU time, memory, disk, energy and activity counters | a snapshot younger than 900 ms is reused; one scan at a time; reply at most 16 MiB |
| `resources` | sockets and open files of the processes named in the request | at most 4,096 identities and 256 KiB per request, 20,000 descriptors per reply; each identity must still match its pid and start time before and after reading |

The helper never sends signals, runs tools or a shell, writes anywhere, accepts a path, or reads
file contents, arguments or environment variables. Release builds dead-strip the shared C
signal and argument readers from its binary.

Trust boundary and checks:

- The listener requires `identifier "dev.stratabar.app" and anchor apple generic and
  certificate leaf[subject.OU] = "<team>"`; the client requires the same of
  `dev.stratabar.helper`. Each side takes the team from its own signature, so the signing
  identity chosen at build time sets it once. Ad-hoc builds have no team and never connect.
- The helper refuses callers whose effective user is root (so it cannot become a relay) or
  whose process has already ended, and accepts at most eight connections.
- Each connection has its own token-bucket limits for queries and resource requests.
- The client checks that the helper runs as root and that its versions match this build. A
  mismatch asks the app to unregister and register the bundled helper again. Every reply is
  size-checked before decoding, and resource results are filtered to the requested identities.
- Any user session on the Mac that runs a correctly signed Strata Monitor can use an approved
  helper. It then sees the process metadata and counters above for every process, as Activity
  Monitor shows every user. Descriptor paths and endpoints are returned only for the caller's own
  processes, or for any process when the caller belongs to the admin group; the helper checks
  each requested process's owner itself and marks a partly refused result as restricted.

`MergedProcessInventory` uses the helper's snapshot whenever the helper answers. Otherwise the
current user's own scan is used, with an optional `OtherUsersUsageSource` filling other users'
CPU time and resident memory; values no source provides stay unavailable. `ProcessCoverage`
names the result: "All processes", "Own processes; CPU and memory for others" or "Own
processes; others listed". `MergedResourceInspector` uses the helper for explicit inspections
and falls back to the current user's access.

## Device controls

- Sound controls bind edits to the observed Core Audio object ID and public device UID. Output
  replacement or page closure cancels volume editing. Unsupported controls remain disabled.
- Wi-Fi discovery is explicit. Experimental direct joining supports identified unprotected
  infrastructure networks, with a short-lived scan identity and fresh security/adapter checks.
  Credentials, missing identities and administrator-restricted changes use System Settings.
- Bluetooth observation follows visible-page or indicator demand. Authorization has an explicit
  page action. Experimental paired-device controls use public Classic Bluetooth APIs.
- Accessory batteries use an explicit one-shot standard BLE service read on connected candidates.
  Classic and BLE identities are separate; names never establish a device match. Levels remain
  separate and timestamped. Page closure cancels the request, and new operations wait for cleanup.
- Battery absence, failed observation and partial readings are distinct. First-run selection waits
  for known battery presence. Health is available only from comparable nominal/design capacities.
- Experimental display resolution/mirroring uses public Core Graphics with hardware identities,
  short-lived catalogs, captured baselines and a separate Keep/Revert window. A preview has a
  rollback deadline; Keep lasts for the login session. Recovery survives panel closure and suspension.
- Keep Awake is explicit and finite. Sleep, display/session suspension and shutdown have owned
  cancellation and recovery paths.

## Reproducible tooling

Use a full Xcode installation with the required macOS SDK:

```sh
scripts/test.sh
scripts/build.sh debug
open 'build/Strata Monitor.app'
```

The scripts select the toolchain locally. Packaging preserves an available existing
signer, otherwise selects a single Apple Development or Developer ID Application
identity. `STRATA_BAR_SIGNING_IDENTITY` overrides that selection; `-` requests ad-hoc
signing. Multiple matching identities or an unavailable existing signer require an explicit choice. Ad-hoc rebuilds
can invalidate macOS permission grants. `bash scripts/test-signing.sh` validates
selection policy without using private keys. Distribution also requires notarization:
`scripts/notarize.sh` checks the Developer ID signature, timestamp and hardened runtime of the
app and helper, submits a zip with `notarytool` using the `STRATA_BAR_NOTARY_PROFILE`
keychain profile (default `strata-bar`), staples the ticket and runs a Gatekeeper assessment.
Packaging signs the helper with its own identifier before the app that seals it.
Packaging signs and verifies a staged bundle, checks that the destination app has
stopped, and preserves the previous build if replacement fails.

Tests use Swift Testing for domain/system/controller behavior and `CocoaTestCase` for native status
control wiring. All automated tests are headless: presentation and event-monitor backends are
in-memory fixtures, with no displayed windows, native status items, app activation or synthetic input.
The test script verifies that
both frameworks completed, rather than treating exit status zero alone as a passing run.

Focused and sanitizer runs use the same entry point:

```sh
scripts/test.sh --filter 'Glyph|hover|Hover'
scripts/test.sh --sanitize address --filter SystemIntegrationTests
scripts/benchmark.sh
```

Benchmarks measure collection and cancellation, not rendering cost. Physical device behavior,
permissions and live visual quality require separate interactive checks. Keep run results and review
summaries in the conversation or pull request.

Preview runs isolate preferences and window placement:

```sh
'build/Strata Monitor.app/Contents/MacOS/Strata Monitor' --preview-page overview --appearance dark
'build/Strata Monitor.app/Contents/MacOS/Strata Monitor' --preview --preview-self --preview-families
```

`--render-glyphs /absolute/path.png`
uses the actual SwiftUI glyph drawing with illustrative readings and does not start collectors or windows.
A still image does not establish animation, focus or physical display quality.

## Current limitations

The complete product remains in development. Native group layout depends on available menu-bar
space; notch overflow and display changes need broader validation. Explorer, inspector and the rest of Settings still need the revised
visual language. Full loaded-library visibility depends on public access. Experimental device
controls require physical validation, including permissions, removal, cancellation and recovery.
No private API, credential collection, account or telemetry service is included. Helper
approval, upgrade re-registration and removal need manual checks on a notarized build.


## Updates and localization

The app owns one `ApplicationUpdates` instance. Production app bundles with a valid
Ed25519 public key and HTTPS feed start Sparkle; previews and command-line builds do not.
Sparkle owns the update schedule and preferences. The app exposes manual checking and
opt-in automatic checking and installation through the menu and General settings.
No monitoring values are included in update requests. Feed signatures are required, and
archive signatures are verified before extraction.

`Package.resolved` pins Sparkle and its binary artifact checksum. `scripts/build.sh`
embeds the framework, removes sandbox-only XPC services, signs its nested updater code
before signing the framework and app, and packages MIT and third-party notices. Release
build numbers come from the monotonically increasing workflow run number. The release
job signs the already notarized ZIP and generates a signed `appcast.xml` with
`scripts/appcast.py`; an independent CryptoKit check verifies that the archive signing
key matches the public key embedded in the app. The stable feed uses GitHub's latest
non-prerelease release asset.

The update private key is stored under the `dev.stratabar.app` account in the maintainer's
login Keychain and as `SPARKLE_ED_PRIVATE_KEY` in repository Actions secrets. Apple signing
and notarization use the separate secrets documented in `.github/workflows/release.yml`.
Do not change `SUPublicEDKey` without a key-migration plan for installed copies. To export
the key for another release environment, use the pinned Sparkle distribution's
`bin/generate_keys --account dev.stratabar.app -x <private-file>`, transfer it securely,
then remove the export. Never commit the file or print its contents.

`Localization/<code>.json` is the app translation source. The compiler extracts native
SwiftUI literals and explicit `String(localized:)` values; permission descriptions come
from Info.plist. Custom UI components receive already localized strings. Packaging
validates all 22 catalogs and writes `.strings`, `.stringsdict` and `InfoPlist.strings`
into the app bundle, declaring the same language set in `CFBundleLocalizations`.
Plural resources retain positional types when a process name precedes a count.
`ApplicationLanguage` owns the optional app-level `AppleLanguages` preference and only
writes after an explicit supported choice; a change takes effect after reopening.
Preview instances have no defaults store. Persisted enum and resource-state identifiers
stay unchanged; localized display titles do not affect queries, sorting or helper data.

The README uses seven message catalogs under `docs/readme/localization`. Its generator
preserves code blocks, markup and links, adjusts relative asset paths, and retains
explicit section anchors. Both catalog checks, generated README validation and the
headless regression tests run in CI and before release signing.
