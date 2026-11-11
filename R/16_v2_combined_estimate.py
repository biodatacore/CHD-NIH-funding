"""16_v2_combined_estimate.py -- portfolio estimate pairing the v1 review (tier-1 census) with the fresh v2 set.
Frame = CHD-signal core projects. Part A: every tier-1 core was reviewed in v1 (census, weight 1; adjudicated labels,
second reviewer where rechecked). Part B: the fresh 200-grant set, weighted to its frame (cores never previously sampled).
Not covered: non-tier-1 cores reviewed in v1 (RCDC-only / near-miss samples), which are excluded from both parts.
Output: sheet Combined_estimate appended to outputs/v2/chd_v2_review_scoring.xlsx"""
import os, sys, numpy as np, pandas as pd, importlib.util
from openpyxl import load_workbook
ret = sys.argv[1] if len(sys.argv) > 1 else "data/validation/v2_review_returned.xlsx"
CC = "CHD focus (Yes / Partly / No / Unsure)"
# Part A rows: reuse the in-sample rescore inputs
key = pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name="Key_CHD")
r1 = pd.read_excel("outputs/reviewer_returned.xlsx", sheet_name="CHD_review")
rc = pd.read_excel("outputs/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx", sheet_name="Map_CHD")
rb = pd.read_excel("data/validation/priority_recheck_returned.xlsx", sheet_name="CHD_review")
rc = rc.merge(rb[["Review ID", CC]], left_on="Priority_ID", right_on="Review ID", suffixes=("", "_r2"))
o = rc[rc.Internal_Tier.isin([1, 2]) & (rc[CC] != "Unsure")].set_index("Round1_Review_ID")[CC]
S = key[["Review ID", "Project number", "Fiscal year"]].merge(r1[["Review ID", CC]], on="Review ID")
S["rev"] = S["Review ID"].map(o).fillna(S[CC]).astype(str).str.strip().str.capitalize()
_ov = os.environ.get("CHD_REF_OVERRIDES")
if _ov:  # reference-label overrides for the v1 833 review (eg v2.3 expert exclusions)
    _o = pd.read_excel(_ov, sheet_name="Overrides"); _o = _o[_o.review.str.startswith("v1")].set_index("Review ID")["new label"]
    S["rev"] = S["Review ID"].map(_o).fillna(S["rev"])
D = pd.read_pickle(os.environ.get("CHD_RELABEL", "data/work/v2.0_classified.pkl"))
S = S.merge(D[["FY", "FULL_PROJECT_NUM", "tier"]], left_on=["Fiscal year", "Project number"], right_on=["FY", "FULL_PROJECT_NUM"], how="left")
A = S[S.tier == "Tier 1 CHD-focused"].assign(pp=True, w=1.0, st="A tier-1 census (v1 review)")
K = pd.read_excel("outputs/v2/chd_v2_review_ANSWER_KEY.xlsx", sheet_name="Key")
K = K.drop(columns=["tier"]).merge(D[["FY", "FULL_PROJECT_NUM", "tier"]], on=["FY", "FULL_PROJECT_NUM"], how="left"); K["tier"] = K.tier.fillna("Not CHD"); R = pd.read_excel(ret, sheet_name="CHD_review")
B = K.merge(R[["Review ID", CC]], on="Review ID"); B["rev"] = B[CC].astype(str).str.strip().str.capitalize()
B = B.assign(pp=B.tier != "Not CHD", w=B.weight, st=B.stratum)
X = pd.concat([A[["pp", "rev", "w", "st"]], B[["pp", "rev", "w", "st"]]], ignore_index=True)
X = X[X.rev.isin(["Yes", "Partly", "No"])]
def metr(pp, rp, w):
    tp, fp, fn, tn = w[pp & rp].sum(), w[pp & ~rp].sum(), w[~pp & rp].sum(), w[~pp & ~rp].sum(); n = tp + fp + fn + tn
    po = (tp + tn) / n; pe = ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / n ** 2
    return dict(Sensitivity=tp / (tp + fn), Specificity=tn / (tn + fp), PPV=tp / (tp + fp), NPV=tn / (tn + fn), Accuracy=po, Kappa=(po - pe) / (1 - pe), TP=tp, FP=fp, FN=fn, TN=tn)
rows = []
for truth, f in [("Yes|Partly", lambda x: x.isin(["Yes", "Partly"])), ("Yes only", lambda x: x == "Yes")]:
    pp, rp, w, st = X.pp.values, f(X.rev).values, X.w.values, X.st.values
    m = metr(pp, rp, w); g = [np.where(st == s)[0] for s in pd.unique(st)]; r = np.random.default_rng(1)
    q = pd.DataFrame([metr(pp[b], rp[b], w[b]) for b in (np.concatenate([r.choice(x, len(x)) for x in g]) for _ in range(2000))]).quantile([.025, .975])
    for k in ["Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa"]: rows.append([truth, k, m[k], q.loc[.025, k], q.loc[.975, k]])
    rows.append([truth, "TP/FP/FN/TN (weighted)", "/".join(f"{m[k]:.1f}" for k in ["TP", "FP", "FN", "TN"]), None, None])
    # dollar-free share of true CHD cores that are tier 2
CE = pd.DataFrame(rows, columns=["Reviewer CHD =", "Metric", "Estimate", "CI_low", "CI_high"])
note = pd.DataFrame({"Combined estimate (v2 combined definition)": [
  f"Part A: {len(A)} tier-1 core project-years from the v1 833-grant review (census of tier-1 cores; weight 1).",
  f"Part B: {len(B)} fresh v2 grants weighted to their strata (frame excludes all 957 previously sampled cores).",
  "Excluded from both: non-tier-1 cores already reviewed in v1 (RCDC-only / near-miss samples) -> the estimate covers the CHD-signal frame minus those cores.",
  "Different reviewers in A and B; CI = stratified bootstrap (2,000) with A as one stratum. Grants with no CHD signal at all are outside the frame."]})
p = os.environ.get("CHD_SCORE_OUT", "outputs/v2/chd_v2_review_scoring.xlsx")
with pd.ExcelWriter(p, mode="a", engine="openpyxl", if_sheet_exists="replace") as xw:
    note.to_excel(xw, sheet_name="Combined_notes", index=False); CE.to_excel(xw, sheet_name="Combined_estimate", index=False)
print(note.to_string()); print(CE.to_string())
