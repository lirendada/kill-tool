#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT_DIR/Sources/KillToolApp/ProcessStore.swift"
DASHBOARD="$ROOT_DIR/Sources/KillToolApp/Views/ProcessDashboardView.swift"

grep -Fq 'var hasWarnSelected' "$STORE"
grep -Fq 'var warnSelectedCount' "$STORE"
grep -Fq 'showStopConfirmation' "$DASHBOARD"
grep -Fq '停止谨慎进程？' "$DASHBOARD"
grep -Fq 'store.hasWarnSelected' "$DASHBOARD"

echo "warn_confirmation_test passed"
