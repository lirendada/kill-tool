#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_SCRIPT="$ROOT_DIR/scripts/test.sh"

test -x "$TEST_SCRIPT"
grep -Fq 'swift build' "$TEST_SCRIPT"
grep -Fq 'swift run KillToolCoreBehaviorTests' "$TEST_SCRIPT"
grep -Fq 'Tests/Packaging' "$TEST_SCRIPT"

echo "test_entrypoint_test passed"
