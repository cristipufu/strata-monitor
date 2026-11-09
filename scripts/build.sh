#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
source scripts/signing.sh
python3 scripts/localize.py check
python3 scripts/readme-localize.py check
configuration="${1:-release}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    echo 'Usage: scripts/build.sh [debug|release]' >&2
    exit 2
fi
swift build -c "$configuration" --product StrataBar
swift build -c "$configuration" --product StrataBarHelper
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
application="$PWD/build/Strata Monitor.app"
signing_identity="$(signing_identity_for_build "$application")"
mkdir -p build
staging_directory="$(mktemp -d "$PWD/build/.package.XXXXXX")"
staged_application="$staging_directory/Strata Monitor.app"
published=false
cleanup() {
    if [[ -d "$staging_directory/previous.app" && "$published" != true ]]; then
        if [[ -e "$application" ]] || ! mv "$staging_directory/previous.app" "$application"; then
            echo "The previous build remains in $staging_directory/previous.app" >&2
            return 1
        fi
    fi
    rm -rf "$staging_directory"
}
trap cleanup EXIT
daemon_plist='Resources/dev.stratabar.helper.plist'
application_executable="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - Resources/Info.plist)"
helper_identifier="$(/usr/bin/plutil -extract Label raw -o - "$daemon_plist")"
helper_program="$(/usr/bin/plutil -extract BundleProgram raw -o - "$daemon_plist")"
mkdir -p "$staged_application/Contents/MacOS" "$staged_application/Contents/Resources" \
    "$staged_application/Contents/Library/LaunchDaemons"
cp "$binary_directory/StrataBar" "$staged_application/Contents/MacOS/$application_executable"
cp "$binary_directory/StrataBarHelper" "$staged_application/$helper_program"
cp Resources/Info.plist "$staged_application/Contents/Info.plist"
cp "$daemon_plist" "$staged_application/Contents/Library/LaunchDaemons/$helper_identifier.plist"
cp LICENSE "$staged_application/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$staged_application/Contents/Resources/THIRD_PARTY_NOTICES.md"
python3 scripts/localize.py build "$staged_application/Contents/Resources"
python3 - "$staged_application" <<'PY'
from pathlib import Path
import plistlib
import sys
application = Path(sys.argv[1])
path = application / 'Contents/Info.plist'
with path.open('rb') as file:
    info = plistlib.load(file)
info['CFBundleLocalizations'] = sorted(folder.stem for folder in (application / 'Contents/Resources').glob('*.lproj'))
with path.open('wb') as file:
    plistlib.dump(info, file)
PY
framework="$staged_application/Contents/Frameworks/Sparkle.framework"
mkdir -p "$staged_application/Contents/Frameworks"
/usr/bin/ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$framework"
# This app is not sandboxed; Sparkle's sandbox-only XPC services are unnecessary.
rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"
swift scripts/Icon.swift "$staged_application/Contents/Resources"
iconutil -c icns 'build/StrataBar.iconset' -o "$staged_application/Contents/Resources/StrataBar.icns"
signing_options=(--force --options runtime)
if [[ "$configuration" == release && "$signing_identity" != - ]]; then
    # Notarization requires a secure timestamp.
    signing_options+=(--timestamp)
fi
# Nested code is signed before the bundle that seals it.
codesign "${signing_options[@]}" --sign "$signing_identity" "$framework/Versions/B/Autoupdate"
codesign "${signing_options[@]}" --sign "$signing_identity" "$framework/Versions/B/Updater.app"
codesign "${signing_options[@]}" --sign "$signing_identity" "$framework"
codesign "${signing_options[@]}" --identifier "$helper_identifier" --sign "$signing_identity" \
    "$staged_application/$helper_program"
codesign "${signing_options[@]}" --sign "$signing_identity" "$staged_application"
codesign --verify --deep --strict "$staged_application"
swift scripts/CheckStoppedApp.swift "$application"
if [[ -e "$application" ]]; then
    mv "$application" "$staging_directory/previous.app"
fi
mv "$staged_application" "$application"
published=true
echo "Built $application"
