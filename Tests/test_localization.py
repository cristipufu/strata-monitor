import copy
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / file)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


localize = module('monitor_localize', 'localize.py')
readme = module('monitor_readme', 'readme-localize.py')
appcast = module('monitor_appcast', 'appcast.py')


class LocalizationTests(unittest.TestCase):
    def test_every_shipped_language_is_complete(self):
        self.assertEqual(22, len(localize.catalogs()))
        self.assertEqual([], localize.validate(localize.catalogs()))

    def test_reordered_arguments_are_valid_and_missing_wrong_or_duplicate_arguments_fail(self):
        source = {'en': {'code': 'en', 'language': 'English', 'plurals': ['one', 'other'],
                         'strings': {'%@ has %lld files': '%@ has %lld files'}}}
        sample = {'code': 'ro', 'language': 'Română', 'plurals': ['one', 'few', 'other'],
                  'strings': {'%@ has %lld files': '%2$lld fișiere pentru %1$@'}}
        self.assertEqual([], localize.validate({**source, 'ro': sample}))
        for invalid in ['%lld files', '%@ has %@ files', '%1$@ %1$@ has %2$lld files', '   ']:
            changed = copy.deepcopy(sample)
            changed['strings']['%@ has %lld files'] = invalid
            self.assertTrue(localize.validate({**source, 'ro': changed}))

    def test_missing_plural_forms_fail(self):
        sample = copy.deepcopy(localize.catalogs())
        plural = next(key for key, value in sample['ro']['strings'].items() if isinstance(value, dict))
        sample['ro']['strings'][plural].pop('few')
        self.assertTrue(localize.validate(sample))

    def test_native_resources_include_permissions_and_positional_plurals(self):
        with tempfile.TemporaryDirectory() as folder:
            localize.build(Path(folder))
            self.assertEqual(22, len(list(Path(folder).glob('*.lproj'))))
            for code in localize.catalogs():
                resource = Path(folder) / f'{code}.lproj'
                self.assertIn('NSBluetoothAlwaysUsageDescription', (resource/'InfoPlist.strings').read_text())
                with (resource/'Localizable.stringsdict').open('rb') as file:
                    plurals = plistlib.load(file)
                mixed = plurals['%@ · %lld processes']
                self.assertEqual('%2$#@count@', mixed['NSStringLocalizedFormatKey'])
                self.assertEqual('lld', mixed['count']['NSStringFormatValueTypeKey'])
                self.assertIn('%1$@', mixed['count']['other'])


    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swift'), 'Native Foundation formatting requires macOS')
    def test_native_plural_formatting_preserves_name_and_count(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            localize.build(directory)
            fixture = directory / 'Format.swift'
            fixture.write_text(r'''
import Foundation
let directory = CommandLine.arguments[1]
let name = "Example"
for code in ["en", "ro", "ja"] {
  let bundle = Bundle(path: "\(directory)/\(code).lproj")!
  for count: Int64 in [1, 2, 20] {
    print(String(localized: "\(name) · \(count) processes", bundle: bundle, locale: Locale(identifier: code)))
  }
}
''')
            result = subprocess.run(['swift', '-module-cache-path', str(directory/'cache'), str(fixture), folder],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(['Example · 1 process', 'Example · 2 processes', 'Example · 20 processes',
                              'Example · 1 proces', 'Example · 2 procese', 'Example · 20 de procese',
                              'Example · 1 プロセス', 'Example · 2 プロセス', 'Example · 20 プロセス'],
                             result.stdout.splitlines())


class ReadmeTests(unittest.TestCase):
    def test_shipped_readmes_are_complete(self):
        catalogs = readme.language_catalogs()
        self.assertEqual({'en', 'ja', 'ko', 'ru', 'uk', 'zh-Hans', 'zh-Hant'}, set(catalogs))
        self.assertEqual([], readme.check_catalogs((ROOT/'README.md').read_text(), catalogs))

    def test_render_keeps_code_and_fixes_relative_links(self):
        source = ('<!-- readme-languages:start -->\nEnglish\n<!-- readme-languages:end -->\n'
                  '## Install\n\nOpen [the app](README.md).\n\n```sh\nopen "Strata Monitor.app"\n```\n'
                  '<p><img src="docs/icon.png" alt="App icon"></p>\n')
        catalog = {'code': 'ja', 'strings': {'Install': 'インストール',
                   'Open [the app](README.md).': '[アプリ](README.md)を開きます。', 'App icon': 'アプリアイコン'}}
        result = readme.render(source, catalog, {'en': {}, 'ja': catalog})
        self.assertIn('```sh\nopen "Strata Monitor.app"\n```', result)
        self.assertIn('src="../../docs/icon.png"', result)
        self.assertIn('[アプリ](../../README.md)', result)
        self.assertIn('## インストール', result)

    def test_html_spacing_entities_are_not_translatable_messages(self):
        source = '<p><img src="docs/icon.png" alt="Icon">&nbsp;<img src="docs/icon.png" alt="Icon"></p>\n'
        self.assertEqual(['Icon', 'Icon'], [message.key for message in readme.messages(source)])

    def test_changed_link_or_code_is_rejected(self):
        source = 'Read [the app](LICENSE) with `port:3000`.\n'
        catalog = {'code': 'ja', 'strings': {source.strip(): 'Read [アプリ](SECURITY.md) with `port:3001`.'}}
        self.assertTrue(readme.check_catalogs(source, {'ja': catalog}))


class AppcastTests(unittest.TestCase):
    def test_feed_describes_only_the_matching_archive(self):
        info = {'CFBundleVersion': '42', 'LSMinimumSystemVersion': '26.0'}
        xml = appcast.XML.fromstring(appcast.feed(info, '0.2.0', 'signature', 123))
        item = xml.find('channel/item')
        self.assertEqual('42', item.findtext('{'+appcast.SPARKLE+'}version'))
        enclosure = item.find('enclosure')
        self.assertEqual('123', enclosure.get('length'))
        self.assertEqual('signature', enclosure.get('{'+appcast.SPARKLE+'}edSignature'))
        self.assertEqual('https://github.com/cristipufu/strata-monitor/releases/download/v0.2.0/StrataMonitor.zip',
                         enclosure.get('url'))


if __name__ == '__main__':
    unittest.main()
