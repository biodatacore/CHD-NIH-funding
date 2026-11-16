# Changelog

## v2 (2026-11-03)
Driven by the blind priority recheck (second reviewer, 129 grants): 36 confirmed keyword misses and 9 confirmed false positives (development cases).
- **Two-tier CHD definition** (`R/13_v2_rules.py`):
  - Tier 1 "CHD-focused" = the v1 keyword rule, with fixes: `fontan` no longer matches "Fontana"; post-infarction (acquired) VSD excluded; broad platforms/centers dropped when CHD is not in the title (software/AI/data-science/computing/genotyping-services/SBIR-topic titles, and P20/P30/P60/U54/R50/contract center titles such as "COBRE" or "Center for ...") unless the title names CHD, development, or a pediatric population.
  - Tier 2 "CHD-related basic/developmental science" (not tier 1), any of:
    (a) developmental-science vocabulary (neural crest, outflow/inflow tract, septation, endocardial cushion, valve formation/delamination, heart tube/looping, first/second heart field, cardiac progenitors/mesoderm, cardiogenesis, chamber/ventricular morphogenesis, trabeculation, pharyngeal/aortic arch arteries, left-right patterning, laterality...) scoring >= 3 (title hit = 2, text hit = 1), cardiac/developmental title, AND an anchor (RCDC CHD or any CHD mention);
    (b) pediatric CHD device: device term + pediatric/neonatal/congenital title + cardiac title (or pulse oximetry) + anchor;
    (c) trainee F30/F31 with a cardiac title + anchor.
    Exclusions: the platform/center pattern, acquired-disease titles (coronary, atherosclerosis, MI, HFpEF), arrhythmia/channel/sudden-death titles.
- **Age focus simplified** to Pediatric / Adult / Both / Not age-specific (basic/animal work and all formerly "Unclear" grants with no human age group -> Not age-specific; tier-2 developmental science without an age term in the title -> Not age-specific).
- **New outputs** in `outputs/v2/`: funding tables (tier 1, tier 2, combined vs v1 and RCDC), IN-SAMPLE rescore of the 833-grant sample, fresh 200-grant blinded review set + answer key + weights, scorer `R/15_v2_score_review.py`.
- v1 code and outputs are unchanged; assemble.py is not run.

## v2.1 (2026-11-04)
User-approved after the v2 fresh review (outputs of v2 kept in outputs/v2/ for comparison; v2.1 in outputs/v2.1/; v2.0 rules kept as R/13_v2_rules_v2.0.py, `classify(D, version="2.0")`).
- PDA ("patent ductus arteriosus", "ductus arteriosus") and supravalvular aortic stenosis ("supravalvular/supravalvar aortic stenosis", "SVAS") now count as strong CHD lesion terms (tier 1 keyword rule recomputed; bare "PDA" stays weak because it also means pancreatic ductal adenocarcinoma). The CHD-signal pool (13a) now also includes project-years that name these lesions.
- Tier 2 trainee route (F30/F31) now requires a CHD lesion term or a cardiac developmental term; RCDC membership alone no longer qualifies.
- Unchanged: MVP/mitral handling, broad networks/centers, all other rules.
- Scorer (15) and combined estimate (16) accept CHD_KEY / CHD_RELABEL / CHD_SCORE_OUT; 14 writes to outputs/v2.1 and no longer redraws the v2 set (DRAW_SAMPLE=1 to regenerate v2).
- New R/17_v3_sample.py: v3 200-grant blinded set covering all tiers and the rest of the NIH portfolio, with weights to all NIH core projects; previously reviewed grants allowed (shuffled, new V3 IDs).

## v2.2 (2026-11-04)
User ruling: coarctation, congenital heart block and pediatric pulmonary hypertension count as CHD. v2.1 outputs kept in outputs/v2.1/ (rules in R/13_v2_rules_v2.1.py); v2.2 outputs in outputs/v2.2/.
- Coarctation: any "coarctation" (eg "repaired coarctation of aorta" in adults) is now a strong lesion term (v1 required "coarctation of the aorta"/"aortic coarctation").
- Congenital heart block: "congenital heart block" was already strong; added fetal/neonatal/autoimmune heart block, neonatal lupus, and anti-Ro/SSA ... heart block. Plain "complete heart block" (often acquired) is not counted.
- Pediatric pulmonary hypertension (tier 1 route): PH/PAH/PPHN in the title with a pediatric/neonatal/infant/fetal/preterm/BPD title term, or >= 3 pediatric-PH phrases (pediatric/neonatal/infant/persistent PH, PPHN, BPD-associated PH) in the text; titles naming adults/older/COPD/scleroderma/left-heart disease/HFpEF are excluded (adult PAH not pulled in).
- Pool (13a) now also scans for coarctation, heart block, pulmonary hypertension and PPHN.
- Reference-label overrides per the ruling: data/validation/v2.2_reference_overrides.xlsx (3 applied in V3: V3-022, V3-065, V3-137; 1 considered and not applied: V3-112, a broad conference). None needed in the v1 833 or v2 200 reviews. Overridden V3 copy: data/validation/v3_review_returned_v2.2ref.xlsx (original file untouched).
- 18_v3_extras.py and 14 take CHD_V3_RETURNED / CHD_RELABEL / CHD_V2_OUT env overrides.

## v2.3 (2026-11-04)
Expert-author ruling: EXCLUDE pediatric pulmonary hypertension (incl. neonatal/PPHN), congenital heart block and noncompaction cardiomyopathy. v2.2 rules saved as R/13_v2_rules_v2.2.py; v2.2 outputs kept in outputs/v2.2/; v2.3 outputs in outputs/v2.3/.
- Removed the v2.2 pediatric-PH tier-1 route and the v2.2 heart-block terms; "congenital heart block" no longer counts as a strong CHD term (it matched the generic "congenital heart" pattern since v1).
- New exclusion (tiers 1 and 2): titles naming pulmonary hypertension/PAH/PPHN, heart block/neonatal lupus, or noncompaction are not CHD unless the title also names another CHD lesion/palliation (eg "CHD-associated pulmonary hypertension", Fontan, septal defect, coarctation, PDA, SVAS).
- Kept: coarctation, PDA, supravalvular aortic stenosis as lesions; F30/F31 anchor rule.
- Reference labels: data/validation/v2.3_reference_overrides.xlsx — 3 v2.2 overrides reversed (V3-022, V3-065, V3-137) and 9 further labels recoded Yes/Partly -> No (7 in the v1 833 review, 2 in V3); 2 checked and not recoded (sheet Checked_not_recoded). Overridden V3 copy: data/validation/v3_review_returned_v2.3ref.xlsx; v1 overrides applied via CHD_REF_OVERRIDES in 14 and 16.
- Fix: R/18_v3_extras.py now relabels with CHD_RELABEL (previously it used the v2.1 key labels, so the v2.2 "without no-signal" weighted figures reported earlier were computed with v2.1 labels; corrected v2.2 values are in outputs/v2.2/chd_v3_review_scoring_v2.2.xlsx).

## V4 review set (2026-11-04)
R/19_v4_sample.py (seed 20261105) draws 200 grants under v2.3 rules, mostly clear cases: A1 clear tier-1 CHD lesion 85, A2 clear non-CHD cardiovascular 45, A3 clear non-CHD pediatric 35, A4 rest of portfolio 5; borderline B1 other tier 1 10, B2 tier 2 10, B3 non-CHD with CHD signal 10. Outputs: outputs/v2.3/chd_v4_review_BLIND.xlsx (name-scrubbed with R/14b) and chd_v4_review_ANSWER_KEY.xlsx (Key, Strata_weights). Unweighted metrics on this set describe clear cases; use weighted for portfolio inference.

## V4 scoring (2026-11-10)
Returned adjudication copied to data/validation/v4_review_adjudicated.csv and scored against the v2.3 pipeline with R/20_v4_score.py. Output: outputs/v2.3/chd_v4_review_scoring_v2.3.xlsx. Pipeline rules were not changed.

## v2.4 (2026-11-10)
User-approved after the V4 review. v2.3 rules saved as R/13_v2_rules_v2.3.py; v2.3 outputs kept in outputs/v2.3/; v2.4 outputs in outputs/v2.4/. Reference labels were not changed (v2.3 overrides still applied).
- **Laterality/heterotaxy (Tier 2):** left-right asymmetry/patterning/axis and laterality terms count toward the developmental-science score and title gate only when the same grant also has a cardiac/CHD link (heart, cardiac, a kept lesion, cardiac/heart/c-looping, etc.). Bare heterotaxy or organ-specific non-cardiac laterality does not count. Drops V4-129 / V2-148 (glycolysis and stomach curvature). Cardiac looping, Pitx2 laterality with heart defects, and left-right organizer work with a cardiac title stay.
- **CHD as a study aim (Tier 1):** keyword-positive grants whose title does not name CHD, a kept lesion (coarctation, PDA / arterial ductus, SVAS), a pediatric-cardiac setting or cardiac situs are demoted only if CHD/strong terms appear solely as an associated phenotype of a gene or protein under study. Associated-phenotype tails (e.g. "mutations in X lead to / which are the sites of mutations that cause ... biliary atresia and congenital heart defects") are stripped; the grant stays if CHD remains in aims/objective language or in at least two other sentences. Safety nets: a kept lesion in the title or text, or substantial cardiogenesis vocabulary plus a CHD/lesion mention, so the gate stays conservative. Drops V4-188 / B-CHD-751 (structural mechanisms of polycystic kidney disease proteins). V4-115 (CHD in the title) and V4-116 (cardiac morphogenesis) stay positive.
- Unchanged: v2.3 exclusions (pediatric PH, heart block, noncompaction) and inclusions (coarctation, PDA, SVAS, F30/F31 anchor).
- Portfolio impact is two cores (5 project-years, $2.42M): the PKD grant (FY2024–2026, Tier 1 → not CHD) and the stomach-laterality R21 (FY2023–2024, Tier 2 → not CHD). No new false negatives in V3, V4, the v2 fresh set or the 833-grant review; both dropped review-set grants were already reviewer No (corrected false positives).
- Outputs: outputs/v2.4/chd_v2_funding.xlsx, chd_v2_insample_rescore.xlsx, chd_v3_review_scoring_v2.4.xlsx, chd_v4_review_scoring_v2.4.xlsx, chd_v2.4_score_v2set.xlsx (combined estimate), chd_v2.4_label_changes.xlsx.

## v2.4 shares, mortality comparison, and figures (2026-11-16)

Adds yearly v2.4 combined CHD shares of NIH CVD funding and of all NIH funding,
age-group dollars and shares with APC and CAGR (FY2013–2025), overlap with the
RCDC “Congenital Heart Disease” category, a funding-vs-mortality comparison
using the cached CDC WONDER death counts, figures, and a key-numbers table.
Classifier rules are unchanged. Scripts: `R/21_v24_shares.py`,
`R/22_v24_figures.py`, `R/run_v24_shares.sh`. Outputs:
`outputs/v2.4/figures_tables/`. Denominator and overlap inputs are the compact
tables in `data/work/` and the aggregated series `data/wonder/wonder_long.csv`.

## v2.4 R reproduction (2026-11-16)

Adds an R port of the v2.4 Python steps so the published classification,
funding tables, validation scores, share/mortality workbook, and figures can
be reproduced with `Rscript R/run_v2.4_all.R`. Classifier rules are unchanged.
Python scripts remain in place as an alternative.

- Scripts: `R/23_v24_classify.R`, `R/24_v24_funding.R`, `R/25_v24_score.R`,
  `R/26_v24_shares.R`, `R/27_v24_figures.R`, `R/chd_v24_metrics.R`, and the
  entry point `R/run_v2.4_all.R`.
- R-readable pool: `data/work/v2_pool.tsv.xz`, generated from
  `data/work/v2_pool.pkl.gz` and verified row-for-row. The pickle is kept.
- Bootstrap indices: `data/bootstrap/*.idx.xz` are the NumPy `default_rng(1)`
  resampling draws used by the Python scorer, so R confidence intervals match
  the shipped tables.
- Default R outputs go to `outputs/v2.4/r/` and do not overwrite the shipped
  Python tables. Comparison: `tests/r_vs_python_report.md`.

## Self-contained R rebuild (2026-11-16)

The repository now ships the de-identified NIH IC project-year universe
used for the v2.4 denominators and the CHD-signal pool (retrieved 20
October 2026), plus the CDC WONDER XML behind `data/wonder/wonder_long.csv`,
so a clone can rebuild every v2.4 result in R from files in the repository.

- Shipped extract: `data/shipped/` (per-year universe and candidate text,
  MD5 checksums, WONDER XML). No investigator or contact fields; names
  that appear only as part of NIH abstract text are left verbatim.
- New or extended R steps: `R/02_load_shipped.R`, `R/13a_v2_pool.R`,
  `R/04_write_denominators.R`, and the entry point `R/run_all_v2.4.R`.
  `R/08_wonder.R --parse-only` rebuilds the long table from the shipped XML.
- Expected-value tests: `tests/test_v24_expected.R`,
  `tests/expected_values.csv`, `tests/expected_key_numbers.csv`.
- Classifier rules are unchanged. `Rscript R/run_v2.4_all.R` still starts
  from already-built intermediates. assemble.py is not run.

