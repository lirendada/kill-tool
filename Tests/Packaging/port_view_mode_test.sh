#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT_DIR/Sources/KillToolApp/ProcessStore.swift"

grep -Fq 'case port = "端口"' "$STORE"
grep -Fq 'sectionsByPort' "$STORE"
grep -Fq 'PortCategory.allCases' "$STORE"

echo "port_view_mode_test passed"
