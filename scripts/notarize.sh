#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
application="${1:-$PWD/build/Strata Monitor.app}"
profile="${STRATA_BAR_NOTARY_PROFILE:-strata-bar}"

fail() {
    echo "$1" >&2
    exit 1
}

require_distribution_signature() {
    local code="$1" signature
    signature="$(codesign -d --verbose=2 "$code" 2>&1)" || fail "$code is not signed."
    [[ "$signature" == *'Authority=Developer ID Application: '* ]] \
        || fail "$code needs a Developer ID Application signature for notarization."
    [[ "$signature" == *'Timestamp='* ]] \
        || fail "$code has no secure timestamp. Build with scripts/build.sh release."
    [[ "$signature" == *'(runtime)'* ]] || fail "$code is not signed with the hardened runtime."
}

[[ -d "$application" ]] || fail "No app at $application. Run scripts/build.sh release first."
codesign --verify --deep --strict "$application" || fail "The app's signature is not valid."
require_distribution_signature "$application"
require_distribution_signature "$application/Contents/MacOS/StrataBarHelper"

if ! profile_check="$(xcrun notarytool history --keychain-profile "$profile" 2>&1)"; then
    echo "$profile_check" >&2
    fail "No usable notarization credentials named \"$profile\". Create them once with an App Store
Connect API key:
    xcrun notarytool store-credentials $profile --key <AuthKey_ID.p8> --key-id <Key ID> --issuer <Issuer ID>
or with an Apple ID and an app-specific password:
    xcrun notarytool store-credentials $profile --apple-id <Apple ID> --team-id <Team ID>
or set STRATA_BAR_NOTARY_PROFILE to another keychain profile."
fi

work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT
archive="$work_directory/Strata Monitor.zip"
result="$work_directory/result.json"
/usr/bin/ditto -c -k --keepParent "$application" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait \
    --output-format json > "$result" || true
status="$(/usr/bin/plutil -extract status raw -o - "$result" 2>/dev/null)" || status='unknown'
if [[ "$status" != Accepted ]]; then
    cat "$result" >&2
    submission="$(/usr/bin/plutil -extract id raw -o - "$result" 2>/dev/null)" || submission='<id>'
    fail "Notarization ended with status $status. Read Apple's log with:
    xcrun notarytool log $submission --keychain-profile $profile"
fi
xcrun stapler staple "$application"
spctl --assess --type execute -vv "$application"
echo "Notarized and stapled $application"
