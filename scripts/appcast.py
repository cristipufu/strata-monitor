#!/usr/bin/env python3
"""Sign a release archive and the Sparkle feed that describes it."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as XML

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
REPOSITORY = 'cristipufu/strata-monitor'
XML.register_namespace('sparkle', SPARKLE)


def feed(info, version, signature, size):
    root = XML.Element('rss', {'version': '2.0'})
    channel = XML.SubElement(root, 'channel')
    XML.SubElement(channel, 'title').text = 'Strata Monitor'
    item = XML.SubElement(channel, 'item')
    XML.SubElement(item, 'title').text = 'Strata Monitor ' + version
    XML.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
    values = {'version': info['CFBundleVersion'], 'shortVersionString': version,
              'minimumSystemVersion': info['LSMinimumSystemVersion'],
              'releaseNotesLink': f'https://github.com/{REPOSITORY}/releases/tag/v{version}'}
    for key, value in values.items():
        XML.SubElement(item, '{'+SPARKLE+'}'+key).text = value
    XML.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{REPOSITORY}/releases/download/v{version}/StrataMonitor.zip',
        '{'+SPARKLE+'}edSignature': signature, 'length': str(size), 'type': 'application/octet-stream'})
    XML.indent(root)
    return XML.tostring(root, encoding='utf-8', xml_declaration=True)


def sign(tool, path, key):
    result = subprocess.run([str(tool), '--ed-key-file', '-', '--disable-signing-warning', str(path)],
                            input=key, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise ValueError('Sparkle could not sign ' + path.name)
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('--application', type=Path, default=Path('build/Strata Monitor.app'))
    parser.add_argument('--directory', type=Path, default=Path('dist'))
    parser.add_argument('--tool', type=Path, default=Path('.build/artifacts/sparkle/Sparkle/bin/sign_update'))
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.]+)?', args.version):
        raise ValueError('Invalid release version')
    with (args.application / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    if args.version.split('-')[0] != info['CFBundleShortVersionString']:
        raise ValueError('Release version does not match the application')
    key = os.environ.get('SPARKLE_ED_PRIVATE_KEY')
    if not key:
        raise ValueError('SPARKLE_ED_PRIVATE_KEY is required')
    archive = args.directory / 'StrataMonitor.zip'
    attributes = sign(args.tool, archive, key)
    match = re.fullmatch(r'sparkle:edSignature="([A-Za-z0-9+/=]+)" length="(\d+)"', attributes)
    if not match or int(match[2]) != archive.stat().st_size:
        raise ValueError('Unexpected archive signature or length')
    appcast = args.directory / 'appcast.xml'
    appcast.write_bytes(feed(info, args.version, match[1], match[2]))
    sign(args.tool, appcast, key)
    # Verify with the public key in the app, rather than only the private key used to sign.
    with tempfile.TemporaryDirectory() as module_cache:
        subprocess.run(['/usr/bin/swift', '-module-cache-path', module_cache,
                        'scripts/VerifyUpdateSignature.swift', info['SUPublicEDKey'],
                        str(archive), match[1]], check=True, timeout=120)
    subprocess.run([str(args.tool), '--verify', '--ed-key-file', '-', str(appcast)],
                   input=key, text=True, check=True, stdout=subprocess.DEVNULL, timeout=120)
    print('Signed and verified update archive and appcast.xml')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
