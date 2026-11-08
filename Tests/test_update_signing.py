import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SIGNER = ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'


@unittest.skipUnless(SIGNER.is_file(), 'Resolve the pinned Sparkle package before signature integration tests')
class UpdateSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swift = ('import CryptoKit; import Foundation; '
                 'let key = Curve25519.Signing.PrivateKey(); '
                 'let values = ["private": key.rawRepresentation.base64EncodedString(), '
                 '"public": key.publicKey.rawRepresentation.base64EncodedString()]; '
                 'print(String(data: try JSONSerialization.data(withJSONObject: values), encoding: .utf8)!)')
        cls.compiler_cache = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.compiler_cache.cleanup)
        cls.keys = json.loads(subprocess.check_output(
            ['swift', '-module-cache-path', cls.compiler_cache.name, '-e', swift], text=True, timeout=120))

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.application = self.directory / 'Fixture.app'
        contents = self.application / 'Contents'
        contents.mkdir(parents=True)
        self.info = {'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '10',
                     'LSMinimumSystemVersion': '26.0', 'SUPublicEDKey': self.keys['public']}
        self.write_info()
        self.archive = self.directory / 'StrataMonitor.zip'
        self.archive.write_bytes(b'An isolated archive signature fixture')
        self.environment = {**os.environ, 'SPARKLE_ED_PRIVATE_KEY': self.keys['private']}
        self.command = ['python3', 'scripts/appcast.py', '0.1.0', '--application', str(self.application),
                        '--directory', str(self.directory)]

    def write_info(self):
        with (self.application / 'Contents/Info.plist').open('wb') as file:
            plistlib.dump(self.info, file)

    def run_appcast(self):
        return subprocess.run(self.command, cwd=ROOT, env=self.environment, capture_output=True, text=True)

    def test_signed_feed_and_archive_reject_tampering(self):
        result = self.run_appcast()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        feed = self.directory / 'appcast.xml'
        original = feed.read_text()
        self.assertIn('sparkle-signatures:', original)
        feed.write_text(original.replace('Strata Monitor', 'Changed application'))
        verification = subprocess.run([str(SIGNER), '--verify', '--ed-key-file', '-', str(feed)],
                                      input=self.keys['private'], capture_output=True, text=True)
        self.assertNotEqual(0, verification.returncode)
        import xml.etree.ElementTree as XML
        signature = XML.fromstring(original).find('channel/item/enclosure').get(
            '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
        self.archive.write_bytes(b'Tampered archive')
        verification = subprocess.run(['swift', '-module-cache-path', self.compiler_cache.name,
                                       'scripts/VerifyUpdateSignature.swift', self.keys['public'],
                                       str(self.archive), signature], cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(0, verification.returncode)

    def test_wrong_embedded_public_key_fails_release_preparation(self):
        self.info['SUPublicEDKey'] = base64.b64encode(bytes(32)).decode()
        self.write_info()
        self.assertNotEqual(0, self.run_appcast().returncode)

    def test_missing_private_key_fails_without_an_appcast(self):
        self.environment.pop('SPARKLE_ED_PRIVATE_KEY')
        self.assertNotEqual(0, self.run_appcast().returncode)
        self.assertFalse((self.directory / 'appcast.xml').exists())


if __name__ == '__main__':
    unittest.main()
