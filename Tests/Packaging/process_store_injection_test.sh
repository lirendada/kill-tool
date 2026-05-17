#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT_DIR/Sources/KillToolApp/ProcessStore.swift"

if grep -Fq 'ProcessScanner(currentUser:' "$STORE"; then
    echo "ProcessStore.refresh should reuse the injected scanner instead of constructing a new one" >&2
    exit 1
fi

grep -Fq 'let scanner = scanner' "$STORE"

echo "process_store_injection_test passed"
