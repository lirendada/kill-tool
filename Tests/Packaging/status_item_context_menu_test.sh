#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DELEGATE="$ROOT_DIR/Sources/KillToolApp/KillToolMain.swift"

grep -Fq 'sendAction(on: [.leftMouseUp, .rightMouseUp])' "$APP_DELEGATE"
grep -Fq '退出 KillTool' "$APP_DELEGATE"
grep -Fq 'NSApp.terminate(nil)' "$APP_DELEGATE"

echo "status_item_context_menu_test passed"
