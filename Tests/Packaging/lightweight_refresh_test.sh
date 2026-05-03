#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT_DIR/Sources/KillToolApp/ProcessStore.swift"
APP_DELEGATE="$ROOT_DIR/Sources/KillToolApp/KillToolMain.swift"

grep -Fq 'static let autoRefreshInterval: TimeInterval = 15' "$STORE"
grep -Fq 'Timer.scheduledTimer(withTimeInterval: Self.autoRefreshInterval' "$STORE"

if grep -Fq 'store.startAutoRefresh()' "$APP_DELEGATE"; then
    echo "AppDelegate should not start auto refresh; view lifecycle owns polling" >&2
    exit 1
fi

echo "lightweight_refresh_test passed"
