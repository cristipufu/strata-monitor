# Strata Monitor engineering

Build the north star in `../strata-bar-plan.md`. Original implementation only;
the referenced applications are inspiration, never sources of code or assets.
Public MIT project. Minimum macOS 26.

## Code style

Follow Clean Code (Robert C. Martin): intention-revealing names, small functions that do one thing, explicit dependencies instead of hidden global state, no duplication, no dead code, and errors handled where they occur. Where this file is more specific, it wins.

Comment only what the code can't say: a decision that isn't obvious, or why something deliberately differs. Never write a comment that restates a name or the code beside it, doc comments on new properties and functions included. Use plain sentences in the app's own words (Trash, Put Back, Delete Immediately).

Keep review summaries and test-run results in the conversation or pull request. Do not commit session diaries, audit reports, temporary log paths or local process measurements unless explicitly requested. Repository docs describe current behavior, architecture and reproducible tooling.

## Architecture and validation

Keep README prose focused on user-visible behavior and reproducible usage/build instructions; do not add internal implementation details or change history.

Use `scripts/test.sh` (coverage enabled), `scripts/build.sh [debug|release]` and
`scripts/notarize.sh` for distribution builds.
These select the installed full Xcode toolchain locally. Keep UI on the main actor and collection off it. No shell
interpolation for system queries. No private APIs, credentials or telemetry. A denied
measurement is not zero.

Privileged access only through the optional, user-approved helper. The helper is
read-only and allowlisted (see docs/IMPLEMENTATION.md): it never sends signals, runs tools,
writes, or accepts paths, and it validates its caller's code signature. Bump
`HelperContract.schemaVersion` whenever an encoded helper payload changes.

Launch Apple tools only through the `SystemTool` launcher: an allowlisted absolute path, a
fixed argument template, no shell, a timeout, an output-size cap and cancellation.

Validate failure, cancellation, and teardown as well as success. Audit security,
functionality, performance, and real native rendering in multiple rounds.

All automated tests must be headless. Use injected in-memory presentation and input
backends; never display windows or status items, activate apps, or post mouse or
keyboard events. Tests write only to temporary directories and test defaults suites, never
to the user's Library. Keep visual and physical interaction checks outside the test suite.

Use `CocoaTestCase` for headless AppKit control wiring. Other tests use Swift Testing.
`scripts/test.sh` verifies both frameworks' execution
boundaries; exit code zero without completed tests is not a passing result.
