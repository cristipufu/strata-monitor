#!/usr/bin/env python3
"""Extract, validate and package Strata Monitor's app translations."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / 'Localization'
FORMAT = re.compile(r'%(?:(\d+)\$)?(?:lld|llu|ld|lu|lf|[diufg@%])')
PLURAL_WORDS = {'processes': 'process', 'resources': 'resource', 'displays': 'display',
                'devices': 'device', 'drives': 'drive', 'cores': 'core', 'points': 'point',
                'seconds': 'second', 'accessories': 'accessory', 'wakeups': 'wakeup'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def catalogs():
    return {path.stem: read(path) for path in sorted(CATALOGS.glob('*.json'))}


def arguments(text):
    result = []
    for match in FORMAT.finditer(text):
        if match[0] == '%%':
            continue
        kind = re.sub(r'^%(?:\d+\$)?', '', match[0])
        result.append((int(match[1]) if match[1] else len(result) + 1, kind))
    return Counter(result)


def validate(data):
    source = data['en']['strings']
    errors = []
    for code, catalog in data.items():
        if catalog.get('code') != code or not catalog.get('language'):
            errors.append(f'{code}: invalid language metadata')
        strings = catalog.get('strings', {})
        if strings.keys() != source.keys():
            errors.append(f'{code}: missing {sorted(source.keys() - strings.keys())}, obsolete {sorted(strings.keys() - source.keys())}')
        for key, english in source.items():
            value = strings.get(key)
            forms = value if isinstance(value, dict) else {'other': value}
            expected = set(catalog['plurals']) if isinstance(english, dict) else {'other'}
            if set(forms) != expected:
                errors.append(f'{code}: {key!r}: expected forms {sorted(expected)}')
            for form, text in forms.items():
                original = english.get('other') if isinstance(english, dict) else english
                if not isinstance(text, str) or not text.strip():
                    errors.append(f'{code}: {key!r} [{form}]: empty translation')
                elif arguments(text) != arguments(original):
                    errors.append(f'{code}: {key!r} [{form}]: changed format arguments')
    return errors


def english_value(key):
    integers = [m for m in FORMAT.finditer(key) if re.search(r'[diu]$', m[0])]
    if len(integers) != 1:
        return key
    singular = key
    for plural, one in PLURAL_WORDS.items():
        singular = re.sub(r'\b' + plural + r'\b', one, singular)
    return {'one': singular, 'other': key} if singular != key else key


def extracted_strings():
    environment = dict(os.environ)
    xcode = Path('/Applications/Xcode.app/Contents/Developer')
    if 'DEVELOPER_DIR' not in environment and xcode.is_dir():
        environment['DEVELOPER_DIR'] = str(xcode)
    with tempfile.TemporaryDirectory() as folder:
        command = ['swift', 'build', '--product', 'StrataBar', '--scratch-path', '.build/localization',
                   '-Xswiftc', '-emit-localized-strings', '-Xswiftc', '-emit-localized-strings-path', '-Xswiftc', folder]
        result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True)
        if result.returncode:
            raise ValueError('String extraction build failed:\n' + result.stdout[-8000:] + result.stderr[-8000:])
        found = {}
        for path in sorted(Path(folder).rglob('*.stringsdata')):
            for entry in read(path).get('tables', {}).get('Localizable', []):
                key = entry['key']
                found[key] = english_value(entry.get('value') or key)
    with (ROOT / 'Resources/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    found.update({'infoplist.' + key: value for key, value in info.items() if key.endswith('UsageDescription')})
    if not found:
        raise ValueError('The compiler did not extract any strings')
    return dict(sorted(found.items()))


def extract(check_only=False):
    path = CATALOGS / 'en.json'
    catalog = read(path)
    strings = extracted_strings()
    if check_only:
        if catalog['strings'] != strings:
            raise ValueError('English strings changed. Run scripts/localize.py extract and translate every language.')
    else:
        catalog['strings'] = strings
        write(path, catalog)
    print(f'{len(strings)} app messages extracted')


def positional(text):
    index = 0
    def replace(match):
        nonlocal index
        if match[0] == '%%':
            return match[0]
        index += 1
        return match[0] if match[1] else '%' + str(index) + '$' + match[0][1:]
    return FORMAT.sub(replace, text)


def strings_file(values):
    def quoted(text):
        return json.dumps(text, ensure_ascii=False)
    return '\n'.join(f'{quoted(key)} = {quoted(value)};' for key, value in sorted(values.items())) + '\n'


def build(destination):
    data = catalogs()
    errors = validate(data)
    if errors:
        raise ValueError('\n'.join(errors))
    for code, catalog in data.items():
        folder = destination / f'{code}.lproj'
        folder.mkdir(parents=True, exist_ok=True)
        strings, plurals, permissions = {}, {}, {}
        for key, value in catalog['strings'].items():
            if key.startswith('infoplist.'):
                permissions[key.removeprefix('infoplist.')] = value
            elif isinstance(value, dict):
                arguments_in_key = [m for m in FORMAT.finditer(positional(key)) if m[0] != '%%']
                count = next(m for m in arguments_in_key if re.search(r'[diu]$', m[0]))
                kind = re.sub(r'^%\d+\$', '', count[0])
                plurals[key] = {'NSStringLocalizedFormatKey': f'%{count[1]}$#@count@',
                                'count': {'NSStringFormatSpecTypeKey': 'NSStringPluralRuleType',
                                          'NSStringFormatValueTypeKey': kind,
                                          **{form: positional(text) for form, text in value.items()}}}
            else:
                strings[key] = value
        (folder / 'Localizable.strings').write_text(strings_file(strings), encoding='utf-8')
        (folder / 'InfoPlist.strings').write_text(strings_file(permissions), encoding='utf-8')
        with (folder / 'Localizable.stringsdict').open('wb') as file:
            plistlib.dump(plurals, file)
    print(' '.join(data))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['extract', 'check', 'build', 'stats'])
    parser.add_argument('destination', nargs='?', type=Path)
    parser.add_argument('--check-source', action='store_true')
    args = parser.parse_args()
    if args.command == 'extract':
        extract(args.check_source)
    elif args.command == 'build':
        if args.destination is None:
            parser.error('build needs an output directory')
        build(args.destination)
    else:
        data = catalogs()
        errors = validate(data)
        if errors:
            raise ValueError('\n'.join(errors))
        for code, catalog in data.items():
            print(f'{code}: {len(catalog["strings"])} messages')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
