#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing.sh

development_a='1111111111111111111111111111111111111111'
development_b='2222222222222222222222222222222222222222'
distribution='3333333333333333333333333333333333333333'
identities="  1) $development_a \"Apple Development: Fixture (TEAM)\"
  2) $distribution \"Developer ID Application: Fixture (TEAM)\"
     2 valid identities found"

expect_identity() {
    local expected="$1"
    shift
    local actual
    actual="$("$@")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected signing identity $expected, received $actual" >&2
        exit 1
    fi
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        echo 'An invalid signing selection unexpectedly succeeded.' >&2
        exit 1
    fi
}

expect_identity "$development_a" select_signing_identity "$identities"
expect_identity "$distribution" select_signing_identity "$identities" 'Developer ID Application: Fixture (TEAM)'
expect_failure select_signing_identity "$identities" 'Missing certificate'
expect_identity "$distribution" select_signing_identity "  1) $distribution \"Developer ID Application: Fixture (TEAM)\""
expect_identity '-' select_signing_identity '     0 valid identities found' 2>/dev/null
expect_identity '-' select_signing_identity '  1) NOT-A-FINGERPRINT "Apple Development: Fixture"' 2>/dev/null
expect_failure select_signing_identity "$identities
  3) $development_b \"Apple Development: Other (OTHER)\""
expect_identity "$distribution" select_signing_identity "$identities
  3) $development_b \"Apple Development: Other (OTHER)\"" 'Developer ID Application: Fixture (TEAM)'
expect_identity "$development_a" select_signing_identity "$identities
  3) $development_a \"Apple Development: Fixture (TEAM)\""

STRATA_BAR_SIGNING_IDENTITY='Explicit identity'
expect_identity 'Explicit identity' signing_identity_for_build '/not/a/build.app'
STRATA_BAR_SIGNING_IDENTITY='-'
expect_identity '-' signing_identity_for_build '/not/a/build.app'
STRATA_BAR_SIGNING_IDENTITY=''
expect_failure signing_identity_for_build '/not/a/build.app'
unset STRATA_BAR_SIGNING_IDENTITY
echo 'Signing selection checks passed.'
