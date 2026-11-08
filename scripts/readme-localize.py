#!/usr/bin/env python3
"""Build and check translated READMEs while preserving code, links and images."""
import argparse
from collections import Counter
from dataclasses import dataclass
import html
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'docs/readme'
CATALOGS = FOLDER / 'localization'
NAV = re.compile(r'<!-- readme-languages:start -->.*?<!-- readme-languages:end -->\n?', re.S)
TOKENS = re.compile(r'`+[^`\n]+`+|!?\[[^\]]*\]\(([^)]+)\)|<[^>]+>|\*\*')


@dataclass(frozen=True)
class Message:
    start: int
    end: int
    key: str
    attribute: bool = False


def normalized(text):
    return ' '.join(text.split())


def messages(source):
    result = []
    def add(start, end, attribute=False):
        raw = source[start:end]
        left = len(raw) - len(raw.lstrip())
        right = len(raw.rstrip())
        key = normalized(raw)
        if html.unescape(key).strip() and key != 'Strata Monitor':
            result.append(Message(start + left, start + right, key, attribute))
    lines = source.splitlines(keepends=True)
    offsets, position = [], 0
    for line in lines:
        offsets.append(position)
        position += len(line)
    index = 0
    while index < len(lines):
        line, start = lines[index], offsets[index]
        if line.startswith('<!-- readme-languages:start -->'):
            while index < len(lines) and 'readme-languages:end' not in lines[index]:
                index += 1
        elif re.match(r'^```', line):
            index += 1
            while index < len(lines) and not lines[index].startswith('```'):
                index += 1
        elif line.startswith('<p') or line.startswith('<h'):
            end = index
            tag = re.match(r'<(p|h\d)', line)[1]
            while end < len(lines) and f'</{tag}>' not in lines[end]:
                end += 1
            if end == len(lines):
                raise ValueError('Unclosed README HTML block')
            last = offsets[end] + len(lines[end])
            fragment = source[start:last]
            for match in re.finditer(r'\balt="([^"]*)"', fragment):
                add(start + match.start(1), start + match.end(1), True)
            for match in re.finditer(r'>([^<>]+)<', fragment):
                add(start + match.start(1), start + match.end(1))
            index = end
        elif not line.strip() or line.startswith('<'):
            pass
        elif line.startswith('|'):
            # Pipes inside inline code or escaped pipes are content, not table boundaries.
            code_spans = [m.span() for m in re.finditer(r'`[^`]+`', line)]
            borders = [i for i, c in enumerate(line) if c == '|' and (i == 0 or line[i-1] != '\\')
                       and not any(a <= i < b for a, b in code_spans)]
            for left, right in zip(borders, borders[1:]):
                if not re.fullmatch(r'[\s:-]+', line[left+1:right]):
                    add(start+left+1, start+right)
        else:
            prefix = re.match(r'^(?:#{1,6} |[-] )', line)
            first = start + (prefix.end() if prefix else 0)
            end = index
            if not (prefix and line.startswith('#')):
                while end + 1 < len(lines) and lines[end+1].strip() and not re.match(r'^(?:[-#|<]|```)', lines[end+1]):
                    end += 1
            add(first, offsets[end] + len(lines[end]))
            index = end
        index += 1
    return result


def protected(text):
    result = []
    for match in TOKENS.finditer(text):
        # Link labels are translated; destinations stay fixed.
        result.append(match[1] if match[1] is not None else match[0])
    return Counter(result)


def language_catalogs():
    return {path.stem: json.loads(path.read_text()) for path in sorted(CATALOGS.glob('*.json'))}


def language_navigation(catalogs, current):
    codes = ['en'] + sorted(set(catalogs) - {'en'})
    links = []
    for code in codes:
        app = json.loads((ROOT / 'Localization' / f'{code}.json').read_text())
        label = html.escape(app['language'])
        if code == current:
            links.append(label)
        else:
            path = 'README.md' if code == 'en' else f'README.{code}.md'
            if current == 'en' and code != 'en':
                path = 'docs/readme/' + path
            elif current != 'en' and code == 'en':
                path = '../../README.md'
            links.append(f'<a href="{html.escape(path, quote=True)}">{label}</a>')
    return ('<!-- readme-languages:start -->\n<p align="center">\n  ' + ' · '.join(links)
            + '\n</p>\n<!-- readme-languages:end -->\n')


def rewrite_links(source):
    def target(path):
        return path if re.match(r'(?:[a-z]+:|#|/)', path) else '../../' + path
    source = re.sub(r'((?:href|src)=")([^"]+)(")', lambda m: m[1]+target(m[2])+m[3], source)
    return re.sub(r'(!?\[[^\]]*\]\()([^\s)]+)(\))', lambda m: m[1]+target(m[2])+m[3], source)


def render(source, catalog, all_catalogs):
    text = source
    for message in reversed(messages(source)):
        value = catalog['strings'][message.key]
        if message.attribute:
            value = html.escape(value, quote=True)
        text = text[:message.start] + value + text[message.end:]
    text = rewrite_links(text)
    return NAV.sub(lambda _: language_navigation(all_catalogs, catalog['code']), text)


def check_catalogs(source, catalogs):
    expected = {m.key for m in messages(source)}
    errors = []
    for code, catalog in catalogs.items():
        if not (ROOT / 'Localization' / f'{code}.json').exists() or catalog.get('code') != code:
            errors.append(f'{code}: README language must match an app language')
        values = catalog.get('strings', {})
        if values.keys() != expected:
            errors.append(f'{code}: missing {sorted(expected-values.keys())}, obsolete {sorted(values.keys()-expected)}')
        for key, value in values.items():
            if not isinstance(value, str) or not value.strip():
                errors.append(f'{code}: blank README message: {key}')
            elif protected(key) != protected(value):
                errors.append(f'{code}: changed Markdown, code or links: {key}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['extract', 'build', 'check'])
    args = parser.parse_args()
    source = (ROOT / 'README.md').read_text()
    if args.command == 'extract':
        data = {'code': 'en', 'strings': {m.key: m.key for m in messages(source)}}
        CATALOGS.mkdir(parents=True, exist_ok=True)
        (CATALOGS / 'en.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
        print(f'{len(data["strings"])} README messages extracted')
        return
    catalogs = language_catalogs()
    errors = check_catalogs(source, catalogs)
    if errors:
        raise ValueError('\n'.join(errors))
    english = NAV.sub(lambda _: language_navigation(catalogs, 'en'), source)
    generated = {ROOT / 'README.md': english}
    for code, catalog in catalogs.items():
        if code != 'en':
            generated[FOLDER / f'README.{code}.md'] = render(english, catalog, catalogs)
    expected_files = {path for path in generated if path.parent == FOLDER}
    if set(FOLDER.glob('README.*.md')) - expected_files:
        raise ValueError('Obsolete generated README translation')
    for path, content in generated.items():
        if args.command == 'build':
            path.write_text(content)
        elif not path.exists() or path.read_text() != content:
            errors.append(f'{path.relative_to(ROOT)} is stale; run scripts/readme-localize.py build')
    if errors:
        raise ValueError('\n'.join(errors))
    print(f'{len(catalogs)} README languages checked')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
