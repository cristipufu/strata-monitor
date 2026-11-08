#!/bin/bash

signing_candidates() {
    local identities="$1"
    local category="$2"
    local previous_authority="${3:-}"
    printf '%s\n' "$identities" | awk -F '"' -v category="$category" -v previous="$previous_authority" '
        {
            split($1, fields, /[[:space:]]+/)
            fingerprint = ""
            for (field in fields) {
                if (length(fields[field]) == 40 && fields[field] ~ /^[[:xdigit:]]+$/) {
                    fingerprint = fields[field]
                }
            }
            if (fingerprint == "") next
            if ((category == "previous" && $2 == previous) ||
                (category == "development" && $2 ~ /^(Apple Development|Mac Developer): /) ||
                (category == "distribution" && $2 ~ /^Developer ID Application: /)) {
                print fingerprint
            }
        }
    ' | sort -u
}

select_signing_identity() {
    local identities="$1"
    local previous_authority="${2:-}"
    local category candidates
    for category in previous development distribution; do
        if [[ "$category" == previous && -z "$previous_authority" ]]; then
            continue
        fi
        candidates="$(signing_candidates "$identities" "$category" "$previous_authority")"
        if [[ "$candidates" == *$'\n'* ]]; then
            echo 'Several signing identities match. Set STRATA_BAR_SIGNING_IDENTITY explicitly.' >&2
            return 1
        fi
        if [[ -n "$candidates" ]]; then
            printf '%s\n' "$candidates"
            return
        fi
        if [[ "$category" == previous ]]; then
            echo 'The existing signer is unavailable. Set STRATA_BAR_SIGNING_IDENTITY to change it explicitly.' >&2
            return 1
        fi
    done
    echo 'No signing certificate is available. Ad-hoc rebuilds may require permissions again.' >&2
    printf '%s\n' '-'
}

signing_identity_for_build() {
    local application="$1"
    if [[ "${STRATA_BAR_SIGNING_IDENTITY+x}" == x ]]; then
        if [[ -z "$STRATA_BAR_SIGNING_IDENTITY" ]]; then
            echo 'STRATA_BAR_SIGNING_IDENTITY must name an identity or be - for ad-hoc signing.' >&2
            return 1
        fi
        printf '%s\n' "$STRATA_BAR_SIGNING_IDENTITY"
        return
    fi
    local identities description previous_authority
    if ! identities="$(/usr/bin/security find-identity -v -p codesigning)"; then
        echo 'Could not read available signing identities.' >&2
        return 1
    fi
    description="$(/usr/bin/codesign -d --verbose=2 "$application" 2>&1)" || description=''
    previous_authority="$(printf '%s\n' "$description" | sed -n '/^Authority=/{s/^Authority=//;p;q;}')"
    select_signing_identity "$identities" "$previous_authority"
}
