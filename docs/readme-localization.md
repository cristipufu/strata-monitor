# README translations

`README.md` is the English source. The README supports English, Japanese, Korean, Russian,
Ukrainian, Simplified Chinese and Traditional Chinese, matching Strata Files. App language
support is broader: see [Localization](../Localization).

Translations are complete message catalogs in `docs/readme/localization/<code>.json`.
The generator writes `docs/readme/README.<code>.md` and language links in every README.
Images, badges, code blocks and relative links share the English source.

```sh
python3 scripts/readme-localize.py extract
# Translate changed source messages in the other six catalogs.
python3 scripts/readme-localize.py build
python3 scripts/readme-localize.py check
```

Keep English keys unchanged. Translate every heading, paragraph, table cell and image
description. Preserve inline code, Markdown emphasis, HTML and link destinations. Keep
product names and working search examples as written; menu labels should agree with the
app translation. Edit catalogs, not generated Markdown. The initial translations are
machine-assisted; corrections from native speakers are welcome.

The checker rejects empty or obsolete messages, altered code and link destinations,
unsupported app language codes and stale generated files. Explicit section anchors keep
README navigation stable across translated headings.
