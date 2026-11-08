# App translations

Each `<code>.json` contains a language's native name, language code, CLDR plural categories
and `strings`. English (`en.json`) is extracted from the Swift compiler and permission
texts in `Resources/Info.plist`. The app currently ships the same 22 languages as
[Strata Files](https://github.com/cristipufu/strata-files/tree/main/Localization).

To change user-visible text:

```sh
python3 scripts/localize.py extract
# Translate each new or changed entry in every language catalog.
python3 scripts/localize.py check
python3 scripts/localize.py build /tmp/strata-monitor-translations
```

Use `String(localized:)` for strings handed to AppKit or returned as presentation values.
SwiftUI string literals and parameters typed as `LocalizedStringKey` are extracted too.
Do not localize identifiers, raw enum values, paths, format units or system query keys.
Interpolate identifiers such as a PID, port or system error code as `String(number)` so
localization never adds grouping separators. Use a named key and `defaultValue:` when
one English word has different meanings, such as light appearance and light ring weight.
Translate an enum's display title instead. A permission prompt uses the named key
`infoplist.<UsageDescription>` and becomes `InfoPlist.strings`.

Keys are the exact English text with placeholders: `%@` for text, `%lld` for an integer,
and `%lf` for a decimal. Preserve their types and number; numbered placeholders such as
`%2$@` allow changing their order. A plural entry has one translation per category listed
in the catalog's `plurals`. Counts with supported plural nouns are extracted as plural
entries; review the English singular when adding a new noun. Packaging writes native
`Localizable.strings` and `Localizable.stringsdict`, including positional arguments.

Keep Strata Monitor, macOS, CPU, GPU, Wi-Fi, Bluetooth, process names and search operators
such as `pid:`, `uid:` and `port:` recognizable. Use macOS terminology for Quit, Force Quit,
System Settings and accessibility. The initial translations are machine-assisted and
welcome native-speaker review, especially technical terms and plural wording.

Choose a language in Settings ▸ General ▸ Language, then quit and reopen the app. System
Default follows macOS's preferred app languages. Preview mode does not persist a choice.

CI checks completeness, format arguments, plural forms and agreement with compiler
extraction. Release packaging repeats the checks before signing.
