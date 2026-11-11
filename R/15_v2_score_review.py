"""15_v2_score_review.py -- score the returned v2 blind review (200 fresh grants) against the v2 pipeline.
Usage (from project root):  python3 R/15_v2_score_review.py path/to/returned_BLIND.xlsx
Reviewer CHD truth = Yes|Partly (primary) and Yes only; Unsure rows excluded (reported).
Pipeline positive = v2 combined (tier 1 + tier 2); tier-2-only results also reported.
Weighted = inverse-probability weights from the answer key (N_frame / n_sample per stratum); CI = stratified bootstrap.
NOTE: tier-1 cores were all reviewed in v1, so this fresh set validates tier 2 and the negative boundary;
combine with the v1 833-grant results for tier 1. Output: outputs/v2/chd_v2_review_scoring.xlsx"""
import sys, numpy as np, pandas as pd
from math import sqrt
ret = sys.argv[1] if len(sys.argv) > 1 else "outputs/v2/chd_v2_review_RETURNED.xlsx"
CC, CA = "CHD focus (Yes / Partly / No / Unsure)", "Age population (Pediatric / Adult / Both / Neither / Unclear)"
import os
KEYP = os.environ.get("CHD_KEY", "outputs/v2/chd_v2_review_ANSWER_KEY.xlsx"); OUTP = os.environ.get("CHD_SCORE_OUT", "outputs/v2/chd_v2_review_scoring.xlsx")
R = pd.read_excel(ret, sheet_name="CHD_review"); K = pd.read_excel(KEYP, sheet_name="Key")
if os.environ.get("CHD_RELABEL"):   # rescore with labels from another rule version (eg v2.1) for the same project-years
    L = pd.read_pickle(os.environ["CHD_RELABEL"])[["FY", "FULL_PROJECT_NUM", "tier", "t2_route", "age_v2"]]
    K = K.drop(columns=["tier", "t2_route", "age_v2"]).merge(L, on=["FY", "FULL_PROJECT_NUM"], how="left"); K["tier"] = K.tier.fillna("Not CHD")
D = K.merge(R[["Review ID", "Project number", CC, CA, "Comments"]], on="Review ID", how="left")
bad = D[D["Project number"] != D.FULL_PROJECT_NUM]; assert bad.empty, f"ID/project mismatch: {bad['Review ID'].tolist()}"
D["rev"] = D[CC].astype(str).str.strip().str.capitalize()
done = D.rev.isin(["Yes", "Partly", "No"]); print(f"answered {done.sum()} / {len(D)}; Unsure {(D.rev=='Unsure').sum()}; blank {(~D.rev.isin(['Yes','Partly','No','Unsure'])).sum()}")
X = D[done].copy(); X["pp"] = X.tier != "Not CHD"
def metr(pp, rp, w):
    pp, rp, w = np.asarray(pp, bool), np.asarray(rp, bool), np.asarray(w, float)
    tp, fp, fn, tn = w[pp & rp].sum(), w[pp & ~rp].sum(), w[~pp & rp].sum(), w[~pp & ~rp].sum(); n = tp + fp + fn + tn
    po = (tp + tn) / n; pe = ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / n ** 2
    f = lambda a, b: a / (a + b) if a + b > 0 else np.nan
    return dict(Sensitivity=f(tp, fn), Specificity=f(tn, fp), PPV=f(tp, fp), NPV=f(tn, fn), Accuracy=po, Kappa=(po - pe) / (1 - pe) if pe < 1 else np.nan, TP=tp, FP=fp, FN=fn, TN=tn)
def wilson(k, n, z=1.96):
    if n == 0: return (np.nan, np.nan)
    p = k / n; d = 1 + z * z / n; c = (p + z * z / (2 * n)) / d; h = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d; return (c - h, c + h)
def boot(pp, rp, w, st, B=2000):
    g = [np.where(st == s)[0] for s in pd.unique(st)]; r = np.random.default_rng(1)
    o = [metr(pp[b], rp[b], w[b]) for b in (np.concatenate([r.choice(x, len(x)) for x in g]) for _ in range(B))]
    return pd.DataFrame(o).quantile([.025, .975])
rows = []
for truth, tf in [("Yes|Partly", lambda x: x.isin(["Yes", "Partly"])), ("Yes only", lambda x: x == "Yes")]:
    rp = tf(X.rev).values; pp = X.pp.values; st = X.stratum.values
    for wl, w in [("unweighted", np.ones(len(X))), ("weighted", X.weight.values)]:
        m = metr(pp, rp, w); q = boot(pp, rp, w, st)
        den = {"Sensitivity": m["TP"] + m["FN"], "Specificity": m["TN"] + m["FP"], "PPV": m["TP"] + m["FP"], "NPV": m["TN"] + m["FN"], "Accuracy": len(X)}
        for k in ["Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa"]:
            lo, hi = (wilson(m[k] * den[k], den[k]) if (wl == "unweighted" and k != "Kappa") else (q.loc[.025, k], q.loc[.975, k]))
            rows.append([truth, wl, k, m[k], lo, hi])
        rows.append([truth, wl, "TP/FP/FN/TN", "/".join(f"{m[k]:.1f}" for k in ["TP", "FP", "FN", "TN"]), None, None])
S = pd.DataFrame(rows, columns=["Reviewer CHD =", "Weighting", "Metric", "Estimate", "CI_low", "CI_high"])
BY = X.groupby("stratum").apply(lambda g: pd.Series({"n": len(g), "rev_Yes|Partly": g.rev.isin(["Yes", "Partly"]).sum(), "pct_Yes|Partly": g.rev.isin(["Yes", "Partly"]).mean(), "weight": g.weight.iloc[0]}))
amap = {"Neither": "Not age-specific"}
A = X[X.pp & X.rev.isin(["Yes", "Partly"])].copy(); A["rev_age"] = A[CA].replace(amap); A = A[A.rev_age.isin(["Pediatric", "Adult", "Both", "Not age-specific"])]
ct = pd.crosstab(A.rev_age, A.age_v2); po = (A.rev_age == A.age_v2).mean() if len(A) else np.nan
pe = sum(ct.sum(1).get(k, 0) * ct.sum(0).get(k, 0) for k in ct.index) / max(len(A), 1) ** 2
AG = pd.DataFrame([[len(A), po, (po - pe) / (1 - pe) if pe < 1 else np.nan]], columns=["n", "Agreement", "Kappa"])
DIS = X[X.pp != X.rev.isin(["Yes", "Partly"])][["Review ID", "FULL_PROJECT_NUM", "FY", "stratum", "tier", "t2_route", "title", "rev", "Comments", "USD"]]
with pd.ExcelWriter(OUTP) as xw:
    S.to_excel(xw, sheet_name="Summary", index=False); BY.to_excel(xw, sheet_name="By_stratum")
    AG.to_excel(xw, sheet_name="Age", index=False); ct.to_excel(xw, sheet_name="Age_confusion"); DIS.to_excel(xw, sheet_name="Disagreements", index=False)
print(S.to_string()); print(BY.to_string()); print(AG.to_string())
