#!/usr/bin/env bash
# v2 steps (after the v1 pipeline has produced data/work/C.rds). Run from the project root.
set -euo pipefail
python3 R/13a_v2_pool.py            # CHD-signal pool + text -> data/work/v2_pool.pkl
python3 R/14_v2_run.py              # rules, FY tables, in-sample rescore, fresh blind set + key
"${NER_PYTHON:-python3}" R/14b_v2_scrub_names.py   # 2nd-pass name masking (spaCy)
# after the reviewer returns the blind file:
# python3 R/15_v2_score_review.py outputs/v2/chd_v2_review_RETURNED.xlsx
