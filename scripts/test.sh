#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mkdir -p build
test_events_path="$(mktemp "$PWD/build/test-events.XXXXXX")"
test_native_events_path="$(mktemp "$PWD/build/test-native-events.XXXXXX")"
trap 'rm -f "$test_events_path" "$test_native_events_path"' EXIT
test_exit_status=0
# Coverage builds keep their own folder, so they and plain builds both stay incremental.
STRATA_XCTEST_EVENTS_PATH="$test_native_events_path" swift test --enable-code-coverage \
    --scratch-path .build/coverage \
    --event-stream-output-path "$test_events_path" --event-stream-version 0 "$@" || test_exit_status=$?
mv "$test_events_path" build/test-events.jsonl
mv "$test_native_events_path" build/test-native-events.jsonl
trap - EXIT
if [[ "$test_exit_status" -ne 0 ]]; then
    exit "$test_exit_status"
fi
verifier=.build/tools/VerifyTestResults
if [[ ! -x "$verifier" || scripts/VerifyTestResults.swift -nt "$verifier" ]]; then
    mkdir -p .build/tools
    swiftc -O scripts/VerifyTestResults.swift -o "$verifier"
fi
"$verifier" build/test-events.jsonl build/test-native-events.jsonl
