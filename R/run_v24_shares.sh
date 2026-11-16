#!/bin/bash
# Rebuild v2.4 share, mortality, and figure tables from shipped inputs.
# Run from the repository root. Does not run assemble.py.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 R/21_v24_shares.py
python3 R/22_v24_figures.py
