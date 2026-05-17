#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT_DIR/Sources/KillToolApp/ProcessStore.swift"

grep -Fq 'failedActionDetails' "$STORE"
grep -Fq 'PID \($0.pid)：\($0.errorMessage ?? "未知错误")' "$STORE"

if grep -Fq '"\(verb) \(succeeded) 个进程，\(failed) 个失败"' "$STORE"; then
    echo "Action failures should include PID-level error details" >&2
    exit 1
fi

echo "action_feedback_test passed"
