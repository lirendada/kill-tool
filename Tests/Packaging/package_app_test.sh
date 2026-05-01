#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIST_DIR="$ROOT_DIR/.build/package-test"
APP_PATH="$TEST_DIST_DIR/KillTool.app"

rm -rf "$TEST_DIST_DIR"

CONFIGURATION=debug DIST_DIR="$TEST_DIST_DIR" "$ROOT_DIR/scripts/package-app.sh" >/tmp/kill-tool-package-test.log

test -d "$APP_PATH"
test -x "$APP_PATH/Contents/MacOS/KillTool"
test -f "$APP_PATH/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_PATH/Contents/Info.plist" | grep -qx "KillTool"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" | grep -qx "com.lirendada.KillTool"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_PATH/Contents/Info.plist" | grep -qx "true"

codesign --verify "$APP_PATH"

echo "package_app_test passed"
