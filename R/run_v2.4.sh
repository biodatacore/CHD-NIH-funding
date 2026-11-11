#!/usr/bin/env bash
# Reproduce the v2.4 fiscal-year totals from the repository root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec python3 R/14_v2_run.py "$@"
