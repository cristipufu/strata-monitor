#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mkdir -p build
swift run -c release StrataBenchmark build/benchmark.json
