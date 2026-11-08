# Contributing to Strata Monitor

Bug reports, ideas, translations and code are welcome. For vulnerabilities, use the
private reporting process in [SECURITY.md](SECURITY.md).

## Report an issue

[Open an issue](https://github.com/cristipufu/strata-monitor/issues/new) with the app and
macOS versions, the affected reading or Explorer view, steps to reproduce and the expected
result. Say whether the optional helper was enabled. Redact process names, arguments,
paths and addresses from screenshots and exports.

## Build and validate

Use an Apple silicon Mac with macOS 26 and full Xcode 26 with Swift 6.2 or later.

```sh
scripts/build.sh debug
scripts/test.sh
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 scripts/localize.py extract --check-source
python3 scripts/localize.py check
python3 scripts/readme-localize.py check
```

Read [AGENTS.md](AGENTS.md) and [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) before
changing code. Keep functions focused, name policy values, inject dependencies and give
cancellation and teardown an explicit owner. Validate failures and lifecycle behavior.

All automated tests are headless. Use Swift Testing for policies and services and
`CocoaTestCase` for AppKit control wiring with in-memory presentation and input backends.
Never display windows or status items, activate applications, post input events, or write
to the user's Library. Use temporary directories and dedicated test defaults suites.
Physical interaction and rendering checks run separately from the automated suite.

Keep UI work on the main actor and collection off it. Apple command-line tools must go
through `SystemTool`, with allowlisted paths, fixed arguments, bounded output, timeout
and cancellation. Do not use a shell for system queries. Do not change helper payloads
without updating `HelperContract.schemaVersion` and validating both sides.

## Translate

The app has 22 language catalogs in [Localization](Localization); the README has 7 in
[docs/readme/localization](docs/readme/localization). See the
[app translation guide](Localization/README.md) and
[README translation guide](docs/readme-localization.md).

Localize user-visible strings, including errors, menus, accessibility and permission
prompts. Preserve machine identifiers, saved enum values and search operators. Every
shipped catalog must contain every source message with matching format arguments and
plural forms. Commit catalog and generated README changes with the feature.

## Pull requests and licensing

Describe the user-visible problem, resulting behavior and relevant validation. Keep
session notes and local measurement logs out of the repository. README prose describes
what people can use and how to build it; architecture belongs in implementation docs.

Code and artwork must be original. Reference applications provide product inspiration,
not source code or assets. Declare any dependency and its license in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and preserve required notices in the app.
Contributions are licensed under the project's [MIT License](LICENSE).
