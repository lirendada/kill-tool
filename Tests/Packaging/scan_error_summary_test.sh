#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT_DIR/Sources/KillToolApp/ProcessStore.swift"

grep -Fq 'scanErrorSummary(for' "$STORE"
grep -Fq 'processCount:' "$STORE"
grep -Fq '扫描失败：无法读取进程列表' "$STORE"
grep -Fq '部分扫描信息不可用' "$STORE"

echo "scan_error_summary_test passed"
