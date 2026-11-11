"""13_v2_rules.py -- v2 CHD definitions (tier 1 'CHD-focused', tier 2 'CHD-related basic/developmental
science') and the simplified 4-level age focus. Applied to the CHD-signal pool built by
13a_v2_pool.py (project-years with any strong/weak CHD term or RCDC CHD flag)."""
import re, warnings, numpy as np, pandas as pd
warnings.filterwarnings("ignore", "This pattern")
I = re.I
def cnt(s, rx): return s.str.count(rx)
def hit(s, rx): return s.str.contains(rx, regex=True)
# strong-term fix: 'fontan' must not match 'fontana' / 'fontanel'
FONTAN_FIX = r"\bfontan(?!el|a)"
# acquired lesions that share CHD words (post-infarction VSD etc.)
ACQUIRED = r"(post-?infarction|post-?myocardial infarction|acquired (ventricular septal|vsd))"
# development vocabulary (tier 2)
DEV = (r"\b(neural crest|outflow tract|inflow tract|septation|endocardial cushion|cushion (formation|mesenchyme)"
       r"|valv(e|ular) (development|formation|morphogenesis|delamination|progenitor)|valvulogenesis|heart valve development"
       r"|heart tube|cardiac looping|heart looping|looping morphogenesis|second heart field|first heart field|heart field"
       r"|cardiac progenitors?|cardiac mesoderm|cardiogenesis|cardioblasts?|cardiac (development|morphogenesis|chamber)"
       r"|heart (development|morphogenesis|formation|regeneration and development)|chamber (formation|morphogenesis)"
       r"|ventricular (morphogenesis|compaction)|trabeculation|aortic arch arter|pharyngeal arch arter"
       r"|left-right (asymmetry|patterning|axis)|laterality|proepicardi|developing heart|embryonic heart|fetal heart development"
       r"|cardiovascular development|cardiac gene regulat)")
DEV_MODEL = r"\b(zebrafish|drosophila|mouse embryo|mice|murine|chick|xenopus|embryo|ipsc|organoid)"
DEVICE_T = (r"\b(stent|valve|valved conduit|conduit|graft|cannula|pump|lvad|vad|assist device|device|catheter|oximet|screening"
            r"|flow restrictor|banding|tissue[- ]engineered|bioprosthe|implant|shunt|patch)")
PED_T = r"\b(pediatric|paediatric|neonat|newborn|infant|baby|babies|child|children|fetal|fetus|congenital)"
CARD_T = r"(heart|cardi|valv|ventric|atri|aort|pulmonary arter|vascul|vessel|outflow|myocard)"
TRAINEE = {"F30", "F31"}
# broad-platform pattern (tighten tier 1 / exclude from tier 2)
CENTER_ACT = {"P20", "P30", "P60", "U54", "N01", "N02", "N43", "N44", "R50", "S10", "G20"}
PLATFORM_T = (r"\b(software|computing|artificial intelligence|deep learning|data science|cobre|genotyping|services|sbir topic"
              r"|imaging application|global network|brain age)")
CENTER_T = r"\b(cobre|center for|centre for|center of|research center|institutional development)"
CHD_TITLE_OK = r"(congenital|cchd|chds?\b|bicuspid|\bbav\b|birth defect|fontan(?!el|a)|single ventricle|hypoplastic|fallot|septal defect|heterotaxy|conotruncal|pediatric heart|pediatric cardi)"
HUMAN_AGE = dict(
  ped=r"\b(pediatric|paediatric|child|children|childhood|infan(t|ts|cy)|neonat(e|es|al)|newborns?|fetal|fetus(es)?|prenatal|perinatal|in utero|nicu|adolescen(t|ts|ce)|youth|preterm|toddlers?|school[- ]age|cicu|norwood|interstage)",
  adu=r"\b(achd|adult congenital|adults with|adult (patients|survivors|population|cohort|clinic|chd|care|outcomes|women|men)|young adults|older adults|adulthood|grown[- ]up congenital|guch|women with (congenital|chd|repaired)|aging with)",
  life=r"\b(children and adults|adults and children|pediatric and adult|adult and pediatric|lifespan|life course|from (childhood|infancy|birth) (to|through|into) adulthood|transition(ing)? (from pediatric|to adult))")
BASIC_RX = (r"\b(mice|mouse|murine|zebrafish|xenopus|chick|drosophila|embryos?|embryonic|organoids?|ipsc|induced pluripotent|stem cells?"
            r"|cardiomyocytes?|cardiac (development|progenitor|neural crest)|second heart field|heart (development|morphogenesis)"
            r"|transcription factor|gene regulatory|enhancers?|chromatin|signaling pathway|knockout|in vitro|in silico|computational model)")
HUMAN_RX = (r"\b(patients?|surger(y|ies)|surgical|cohorts?|trials?|registry|registries|clinical|hospitali[sz]|hospitals?|survivors?"
            r"|participants|enroll(ed|ment)?|quality of life|catheteri[sz]ation|transplant(ation)?|echocardiogra|first-in-(baby|human))")

# v2.1: PDA and supravalvular aortic stenosis count as strong CHD lesion terms (bare "pda" stays weak: it also abbreviates
# pancreatic ductal adenocarcinoma). Counts are added to the v1 strong counts and the keyword rule is recomputed.
LESION_V21 = r"\b(patent ductus arteriosus|ductus arteriosus|supravalv(ular|ar) aortic stenosis|\bsvas\b)"
# v2.2 (user ruling): coarctation (any wording, incl. repaired coarctation in adults), congenital heart block
# (fetal/neonatal/autoimmune anti-Ro/SSA CHB) and pediatric pulmonary hypertension count as CHD.
COARC_V22 = r"(?<!aortic )\bcoarctation\b(?! of the aorta)"
CHB_V22 = r"\b((fetal|neonatal|autoimmune) (complete )?(congenital )?heart block|neonatal lupus|anti-?(ro|ssa)\b[^.]{0,80}heart block)"
PH_RX = r"\b(pulmonary (arterial )?hypertension|\bpah\b|\bpphn\b)"
PEDPH_TXT = r"\b((pediatric|paediatric|neonatal|infant|childhood|newborn|persistent) pulmonary (arterial )?hypertension|\bpphn\b|bronchopulmonary dysplasia[- ]associated pulmonary hypertension)"
PED_TITLE_PH = r"\b(pediatric|paediatric|neonat|newborn|infant|child|children|childhood|preterm|premature|fetal|bronchopulmonary dysplasia)"
CHD_STRONG_NOBLOCK = (r"\b(congenital (heart|cardiac|cardiovascular) (disease|defect|malformation|anomal|lesion|surgery|surgical)|congenital heart(?! block)|achd|fontan(?!el|a)|single[- ]ventricle|univentricular"
    r"|hypoplastic left heart|tetralogy|transposition of the great|septal defect|atrioventricular canal|ebstein|truncus arteriosus|double[- ]outlet"
    r"|pulmonary atresia|tricuspid atresia|anomalous pulmonary venous|heterotaxy|conotruncal|norwood|glenn|cavopulmonary|eisenmenger|shunt)")
# v2.3 (expert author): EXCLUDE pediatric pulmonary hypertension (incl. neonatal/PPHN), congenital heart block and
# noncompaction cardiomyopathy. Coarctation, PDA and supravalvular aortic stenosis stay CHD lesions; F30/F31 anchor rule kept.
EXCL_V23 = r"(heart block|neonatal lupus|non-?compaction|noncompact|pulmonary (arterial )?hypertension|\bpphn\b|\bpah\b)"
CHB_RX = r"\bcongenital (heart|cardiac) block"
VERSION = "2.3"
def classify(D, version=VERSION):
    D = D.copy()
    tl = D.title.fillna("").str.lower(); tx = D.text.fillna("").str.lower()
    if version != "2.0":
        xt, xs = cnt(tl, LESION_V21), cnt(tx, LESION_V21)
        D["s_weak"] = (D.s_weak - cnt(tx, r"\bpatent ductus arteriosus")).clip(lower=0)
        D["t_str"] = D.t_str + xt; D["s_str"] = D.s_str + xs
        D["kw_v1"] = D.kw.astype(bool)
        if version not in ("2.0", "2.1"):
            if version == "2.2":
                D["t_str"] = D.t_str + cnt(tl, COARC_V22) + cnt(tl, CHB_V22); D["s_str"] = D.s_str + cnt(tx, COARC_V22) + cnt(tx, CHB_V22)
            else:  # v2.3: coarctation kept; "congenital heart block" no longer counts as a strong CHD term
                D["t_str"] = (D.t_str + cnt(tl, COARC_V22) - cnt(tl, CHB_RX)).clip(lower=0); D["s_str"] = (D.s_str + cnt(tx, COARC_V22) - cnt(tx, CHB_RX)).clip(lower=0)
        D["kw"] = (D.t_str >= 1) | (D.s_str >= 3) | ((D.s_str >= 2) & (D.s_weak >= 2)) | ((D.s_str >= 1) & (D.t_pedcard.astype(bool) | (D.t_ped.astype(bool) & hit(tl, r"(heart|cardi)"))))
    # --- tier 1 = original keyword rule, with two fixes and the platform exclusion
    fontana_only = hit(tl + " " + tx, r"\bfontana\b") & ~hit(tl + " " + tx, FONTAN_FIX)
    acquired = hit(tl, ACQUIRED)
    platform = (~hit(tl, CHD_TITLE_OK)) & ~hit(tl, DEV) & ~hit(tl, PED_T) & (hit(tl, PLATFORM_T) | (D.ACT.isin(CENTER_ACT) & (hit(tl, CENTER_T) | D.ACT.str.startswith("N"))))
    # text-only matches in grants whose title is not cardiac/pediatric at all (eg kidney/brain projects)
    D["t1_drop"] = np.select([fontana_only, acquired, platform & (D.t_str == 0)],
                             ["fontana", "acquired", "platform/center"], "")
    D["tier1"] = D.kw.astype(bool) & (D.t1_drop == "")
    D["pedph"] = False
    if version == "2.2":   # pediatric PH: PH in the title with a pediatric title term, or repeated pediatric-PH phrases; adult PAH excluded
        adult_t = hit(tl, r"\b(adult|adults|older|elderly|veteran|copd|scleroderma|systemic sclerosis|left heart disease|hfpef)")
        pedph = (hit(tl, PH_RX) & hit(tl, PED_TITLE_PH)) | (cnt(tx, PEDPH_TXT) >= 3)
        D["pedph"] = pedph & ~adult_t & ~acquired & ~fontana_only
        D["tier1"] = D.tier1 | D.pedph
    # --- tier 2 candidates (not tier 1)
    chd_mention = (D.s_str + D.s_weak + D.t_str > 0) | hit(tx, r"congenital heart|heart defect|cardiac defect|birth defect")
    anchor = D.rcdc.astype(bool) | chd_mention
    ndev = cnt(tl, DEV) * 2 + cnt(tx, DEV)
    devsci = anchor & (ndev >= 3) & hit(tl, CARD_T + "|" + DEV)
    device = anchor & hit(tl, DEVICE_T) & (hit(tl, PED_T) | (D.s_ped >= 2)) & (hit(tl, CARD_T) | hit(tl, r"oximet"))
    if version == "2.0":
        trainee = D.ACT.isin(TRAINEE) & anchor & hit(tl, CARD_T) & ((D.s_str >= 1) | D.rcdc.astype(bool) | (ndev >= 1))
    else:  # v2.1: trainee awards need a CHD lesion term or a cardiac developmental term in the title/text (RCDC alone is not enough)
        trainee = D.ACT.isin(TRAINEE) & hit(tl, CARD_T) & ((D.s_str >= 1) | (ndev >= 1))
    excl = platform | acquired | fontana_only | hit(tl, r"\b(coronary|atherosclero|myocardial infarction|heart failure with preserved|arrhythm|channel|sudden cardiac death)")
    D["t2_route"] = np.select([devsci, device, trainee], ["developmental science", "pediatric device", "trainee F30/F31"], "")
    D["tier2"] = ~D.tier1 & (D.t2_route != "") & ~excl
    if version not in ("2.0", "2.1", "2.2"):
        # excluded conditions: title names PH / heart block / noncompaction and no other CHD lesion or palliation term
        D["excl_v23"] = hit(tl, EXCL_V23) & ~hit(tl, CHD_STRONG_NOBLOCK) & ~hit(tl, COARC_V22) & ~hit(tl, LESION_V21)
        D["tier1"] = D.tier1 & ~D.excl_v23; D["tier2"] = D.tier2 & ~D.excl_v23
    D["chd_v2"] = D.tier1 | D.tier2
    D["tier"] = np.select([D.tier1, D.tier2], ["Tier 1 CHD-focused", "Tier 2 CHD-related basic/developmental"], "Not CHD")
    # --- simplified age: Pediatric / Adult / Both / Not age-specific
    ped = hit(tl, HUMAN_AGE["ped"]) | (cnt(tx, HUMAN_AGE["ped"]) >= 2)
    adu = hit(tl, HUMAN_AGE["adu"]) | (cnt(tx, HUMAN_AGE["adu"]) >= 2)
    life = cnt(tx, HUMAN_AGE["life"]) >= 1
    nb = cnt(tx, BASIC_RX); nh = cnt(tx, HUMAN_RX)
    tage = hit(tl, HUMAN_AGE["ped"]) | hit(tl, HUMAN_AGE["adu"])
    basic = (~tage & (nb >= 3) & (nb > nh)) | (D.t2_route == "developmental science") & ~tage
    D["age_v2"] = np.select([basic, (ped & adu) | (life & (ped | adu)), ped, adu], ["Not age-specific", "Both", "Pediatric", "Adult"], "Not age-specific")
    return D
