#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

swift build
swift run KillToolCoreBehaviorTests

for test_script in "$ROOT_DIR"/Tests/Packaging/*.sh; do
    echo "==> $(basename "$test_script")"
    bash "$test_script"
done

echo "All tests passed"
