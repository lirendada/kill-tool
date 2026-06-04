#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT_DIR/Sources/KillToolApp/ProcessStore.swift"
APP_DELEGATE="$ROOT_DIR/Sources/KillToolApp/KillToolMain.swift"
DASHBOARD="$ROOT_DIR/Sources/KillToolApp/Views/ProcessDashboardView.swift"

# 面板打开时按较短间隔实时刷新;刷新仍由 view 生命周期拥有,AppDelegate 不参与
grep -Fq 'static let autoRefreshInterval: TimeInterval = 3' "$STORE"
grep -Fq 'Timer.scheduledTimer(withTimeInterval: Self.autoRefreshInterval' "$STORE"
# 首次加载用 hasLoadedOnce 区分"加载中"与"确实没有",避免首开闪空状态
grep -Fq '@Published private(set) var hasLoadedOnce' "$STORE"
grep -Fq 'loadingState' "$DASHBOARD"

if grep -Fq 'store.startAutoRefresh()' "$APP_DELEGATE"; then
    echo "AppDelegate should not start auto refresh; view lifecycle owns polling" >&2
    exit 1
fi

echo "realtime_refresh_test passed"
