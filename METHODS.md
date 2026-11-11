# NIH funding for congenital heart disease (CHD) research, FY2013–2026: methods note

**Data and universe.** We reused the NIH grant records and the project-level build from our women's-health-research funding pipeline. These are the NIH ExPORTER project and abstract records for FY2013–2025 and RePORTER API v2 records for FY2026, retrieved October 20, 2026. FY2026 is a partial fiscal year. The universe is every project administered by an NIH Institute or Center. Records are collapsed to one record per full project number per fiscal year and valued at the parent award's total cost (direct plus indirect). When no parent record exists, the record is valued at the summed component costs, so multicomponent awards are never double counted. Dollars are nominal. The yearly NIH denominators are identical to those of the women's health research analysis. From the same raw files we added the NIH RCDC spending categories and the NIH project terms. FY2023 RCDC assignments came from the RePORTER API because the FY2023 bulk file has no RCDC field. The API and bulk-file RCDC flags disagreed on 1 of 575,846 project-years.

**CHD identification.** The primary definition is a transparent keyword classifier applied to the title and to the pooled abstract and public health relevance text. A project qualifies if it has:
- 1 or more strong CHD terms in the title; or
- 3 or more strong-term mentions; or
- 2 strong mentions plus 2 or more weak mentions; or
- 1 strong mention together with a pediatric-cardiac title.

Strong terms name CHD or a specific lesion or palliation, such as Fontan, single ventricle, hypoplastic left heart syndrome, tetralogy of Fallot, transposition, coarctation, septal defects, Ebstein anomaly, truncus arteriosus, double-outlet right ventricle, atresias, TAPVR, heterotaxy, conotruncal defects, Norwood, cavopulmonary and ACHD. Ambiguous abbreviations are excluded: CHD (coronary heart disease), ASD (autism), VSD (voltage-sensing domain) and HLHS (a library acronym). The comparator is the NIH RCDC category "Congenital Heart Disease" (RePORTER category 3533), which exists only for FY2016–2025.

**Age focus.** CHD projects are assigned one of five groups using human-population terms:
- **Basic/non-age-specific** (checked first): no age term in the title, and basic-science terms (animal models, embryos, iPSC, developmental pathways) outnumber clinical terms.
- **Pediatric:** a pediatric, fetal or neonatal term in the title, or 2 or more such mentions.
- **Adult:** an adult-CHD term in the title, or 2 or more adult-population mentions. Non-human uses such as "adult mice" and "adult stem cells" are excluded.
- **Both:** both the pediatric and adult criteria are met, or the text uses an explicit both-ages phrase.
- **Unclear:** all remaining projects.

All analyses are sex-pooled.

**Statistics.** For FY2013–2025 we report the compound annual growth rate and the log-linear regression slope, expressed as annual percentage change with a 95% CI. FY2026 is shown but excluded from the trend estimates.

**Validation.** One reviewer manually reviewed seeded random samples, with 1 project-year per core project:
- 50 keyword-positive projects;
- 25 projects flagged by RCDC only;
- 25 keyword-negative near misses;
- 47 age assignments, about 10 per group.

The full rules are in `R/terms.R` and `R/03_classify.R`, and the results are in the workbook's Validation sheets.

**Caveats.**
- The keyword classifier undercounts CHD work that does not name a lesion. RCDC is broader and also captures inherited arrhythmia, cardiomyopathy, valve and heart-development grants.
- The age rules depend on how the abstract is framed. Mechanistic grants often cite "1% of live births."
- The single-reviewer validation is limited.
- RePORTER FY2026 records continue to change.

Outputs contain no investigator names. The original unblinded text-bearing review workbook is not included in this repository.

**Cardiovascular (CVD) denominator.** Total NIH CVD funding uses the main CV definition from the women's CV funding analysis, so the numbers are consistent across projects. The project-level flags are read from that pipeline's cache and its code is not modified. A project counts as CV when CV is a substantive part of its parent record, meaning either:
- a CV term in the title; or
- repeated strong and weak CV terms in the abstract and public health relevance text.

Non-CV usages are removed first (eg, tumor angiogenesis, heart rate variability, intracranial or portal hypertension), and the definition's precision is about 84%. The project universe and dollars are the same as above. CHD as a percentage of CVD uses CHD projects that also meet the CVD definition (a nested numerator; 96–99% of CHD dollars each year). All-CHD divided by CVD is also reported. Trends use the same methods as above (FY2013–2025).

**Mortality comparison (CDC WONDER).** We counted US deaths for 2013–2024 from final NCHS mortality files through the CDC WONDER API (national queries, retrieved October 26, 2026). There is one splice at 2018:
- 2013–2017 come from the bridged-race files: Underlying Cause D76 and Multiple Cause D77.
- 2018–2024 come from the single-race files: Underlying Cause D158 and Multiple Cause D157.

Race is not used, and counts for the overlap years 2018–2020 were identical in both file families. The 2024 data come from the final 2018–2024 files, not the provisional data. CHD deaths (ICD-10 Q20–Q26) are counted two ways: as the underlying cause, and as any mention on the death certificate (multiple cause). Because Q codes lie outside ICD-10 chapter I, the two denominators are:
- underlying-cause CVD (I00–I99) plus underlying-cause CHD;
- diseases of heart (113-cause list, I00–I09, I11, I13, I20–I51) plus underlying-cause CHD.

Pediatric deaths are those at ages 0–17. Adult deaths are all ages minus pediatric, so they include the few deaths with age not stated. Analyses are sex-pooled. Trends are log-linear (annual % change, 2013–2024).

**Caveats.**
- The underlying cause misses many adult CHD deaths, so any mention is the preferred measure for adults.
- A death with CHD mentioned can have a non-CVD underlying cause, so it is not a strict subset of the denominator. For children this makes the any-mention ratio meaningless as a share (87–94% of CVD+CHD deaths), so it is not plotted.
- WONDER suppresses counts of 1–9; no suppressed values were used or imputed.
- Coding and death certification vary.
- Funding (fiscal year) and mortality (calendar year) are ecological comparisons and imply no causal relation.

**Manual-check workbook.** The v1 manual-check pack shipped here is the blinded review workbook, its answer key, and the returned review (`outputs/chd_manual_check_BLIND.xlsx`, `outputs/chd_manual_check_ANSWER_KEY.xlsx`, `outputs/reviewer_returned.xlsx`). Review sheets use freeze panes, filters, wrap text, Arial 11, and Yes/Partly/No/Unsure dropdowns. It covers keyword CHD classification (all unique cores, with keyword-only and RCDC-only discordants and a near-miss sample), age focus, CVD-denominator membership, and a mortality ICD reference sheet. Each grant row has a clickable NIH RePORTER link for that application ID. Abstracts are scrubbed of common personal-name and publication-name patterns; scrubbing is imperfect. Prior single-reviewer judgments from the seeded sample are on the Prior_judgments sheet and in a Prior column where they apply.

## v2 definitions and validation (2026-11-03)
**CHD tiers.** Tier 1 (CHD-focused) keeps the v1 keyword rule (strong CHD term in the title, or repeated strong/weak mentions in the text) with three corrections identified by blinded re-review: the Fontan pattern excludes "Fontana"; post-infarction ventricular septal defect is excluded; and grants whose title describes a broad platform or center (software, AI or data-science, computing, genotyping services, COBRE/center titles under P20/P30/P60/U54/R50 or contracts) are excluded unless the title names CHD, cardiac development or a pediatric population. Tier 2 (CHD-related basic/developmental science) adds grants not in tier 1 that (a) use cardiac developmental vocabulary repeatedly (score >= 3; title hits count double) with a cardiac or developmental title and an anchor (RCDC "Congenital Heart Disease" membership or any CHD mention), (b) develop a pediatric cardiac device with an anchor, or (c) are F30/F31 trainee awards with a cardiac title and an anchor; acquired-disease, arrhythmia/channel and platform titles are excluded. Combined CHD = tier 1 + tier 2. RCDC CHD (FY2016–2025) is reported as a cross-check band.
**Age focus.** Pediatric / Adult / Both / Not age-specific, from human-population terms in the title or repeated in the text; work without a human age target (animal, embryo, iPSC, computational) is Not age-specific.
**In-sample check.** v1/v2 definitions were rescored on the 833-grant v1 review (round-1 labels, replaced by the second reviewer's blind labels on the 57 rechecked CHD rows and 14 age rows). Because these grants were used to develop v2, the results are labelled in-sample and are optimistic. Weighted estimates use inverse-probability weights to the v1 frame (keyword 690/689, RCDC-only 459/95, near-miss 429/49) with stratified bootstrap CIs (2,000 draws).
**Fresh validation set.** 200 core projects never previously sampled (957 prior cores excluded), one most-recent project-year with an abstract per core, seed 20261103, stratified: tier 2 developmental (45 of 104), tier 2 device/trainee (30 of 45), RCDC CHD not v2 (45 of 236), 1–2 strong terms or developmental title not v2 (45 of 245), other CHD-signal negatives (35 of 642). Every v1 keyword-positive core (hence every tier-1 core) was already reviewed in v1, so tier 1 has no fresh frame; tier-1 accuracy rests on the v1 review. Weights = N_frame / n_sample. The blind workbook has the v1 review columns and no pipeline labels; abstracts were de-identified by pattern rules plus named-entity masking ([NAME]).

## v2.1 and the v3 validation set (2026-11-04)
v2.1 adds patent ductus arteriosus and supravalvular aortic stenosis as CHD lesions and requires a CHD lesion or cardiac developmental term for F30/F31 trainee awards. Both earlier reviews are now in-sample for v2.1 (the v2 fresh review identified these changes). The v3 set samples NIH core projects (one most-recent project-year with an abstract) from seven strata spanning tier 1, tier 2 developmental, tier 2 device/trainee, RCDC-only, near-boundary, other CHD-signal negatives and all remaining NIH projects; weights are N/n per stratum so weighted metrics refer to the whole NIH portfolio. Previously reviewed grants were eligible.

## v2.2 (2026-11-04)
In v2.2, coarctation (including repaired coarctation in adults), congenital heart block (including maternal anti-Ro/SSA autoimmune heart block) and pediatric pulmonary hypertension were added to the CHD definition (tier 1). Pediatric pulmonary hypertension requires a pediatric population in the title or repeated pediatric-PH phrases, and adult-population titles are excluded. Reference labels in the reviews were recoded to Yes where a grant whose title names one of these conditions had been labelled No or Unsure (3 grants, all in the V3 review; documented in data/validation/v2.2_reference_overrides.xlsx). All reviews are in-sample for v2.2.

## v2.3 (2026-11-04)
On expert advice, pediatric (including neonatal) pulmonary hypertension, congenital heart block and noncompaction cardiomyopathy are excluded from the CHD definition unless the grant also names another CHD lesion; coarctation, patent ductus arteriosus and supravalvular aortic stenosis remain CHD lesions. Reference labels whose positive status rested only on the excluded conditions were recoded to No (12 changes, documented in data/validation/v2.3_reference_overrides.xlsx).

## v2.4 (2026-11-10)
Two conservative refinements of the v2.3 definition; coarctation, patent ductus arteriosus and supravalvular aortic stenosis remain CHD lesions, the F30/F31 anchor is unchanged, and pediatric pulmonary hypertension, congenital heart block and noncompaction remain excluded unless another CHD lesion is also named. Reference labels were not changed.

**Laterality.** In the Tier 2 developmental-science route, the terms "left-right asymmetry/patterning/axis" and "laterality" are counted (title hit = 2, text hit = 1; and they may satisfy the cardiac/developmental title gate) only if the same grant also names a cardiac or CHD link: heart, cardiac, a kept lesion, or cardiac/heart/c-looping. Bare "heterotaxy" or "chromatin looping" is not a cardiac link. Organ-specific laterality work that never names the heart, such as left-right curvature of the stomach, is therefore not classified as CHD.

**Study aim.** A grant reaches Tier 1 through the keyword rule only if congenital heart disease is a study aim, not merely an associated phenotype of a gene or protein under study. The exact gate, applied only to keyword-positive grants, is:

- The grant stays Tier 1 if the title names CHD, a kept lesion (including coarctation, patent or arterial ductus, or supravalvular aortic stenosis), a pediatric-cardiac setting, or cardiac situs.
- Otherwise it stays if, after associated-phenotype tails are stripped from the abstract (clauses such as "mutations in X lead to development of … and congenital heart defects" or "which are the sites of mutations that cause … and congenital heart defects"), a CHD or lesion term remains in aims, objective or hypothesis language, or in at least two sentences.
- It is demoted only if those conditions fail and at least one associated-phenotype mention is present. Two safety nets prevent over-demotion: a kept lesion anywhere in the title or text, and a cardiogenesis safety net (developmental-science vocabulary score ≥ 3 plus a CHD or lesion mention). Bare "CHD" is counted in this scan only when the text already names congenital heart disease, so the gene symbol CHD7 is not treated as CHD.

A grant demoted from Tier 1 can still be Tier 2 if it meets a Tier 2 route. The two grants this version removes from the combined definition are the stomach-laterality R21 and the polycystic-kidney-protein structural study; both had been reviewer-labelled No.
