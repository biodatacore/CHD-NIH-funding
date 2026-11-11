"""14b_v2_scrub_names.py -- second-pass de-identification of the v2 BLIND workbook.
Masks PERSON entities (spaCy en_core_web_sm) and parenthetical surname lists in Title / Abstract / PHR with [NAME].
Run with a Python environment that has spaCy and en_core_web_sm:
  python3 R/14b_v2_scrub_names.py"""
import re, spacy
from openpyxl import load_workbook
import os
P = os.environ.get("CHD_BLIND", "outputs/v2/chd_v2_review_BLIND.xlsx"); nlp = spacy.load("en_core_web_sm", disable=["lemmatizer"])
KEEP = re.compile(r"(?i)^(fontan|norwood|glenn|ebstein|fallot|noonan|turner|digeorge|down|williams|marfan|alagille|holt|kawasaki|wnt|notch|hippo|yap|gata\d*|tbx\d*|nkx\d*|hand\d*|isl1|sox\d*|cre|crispr|cas9|aim|aims|heart|congenital)$")
SCI = {"drosophila","zebrafish","xenopus","mouse","mice","human","notch","hippo","nodal","sonic","hedgehog","fontan","norwood","glenn","ebstein","fallot","noonan","turner","down","marfan","alagille","williams","project","study","program","core","aims","phase","year","years"}
PAREN = re.compile(r"\((?:[A-Z][a-z'\-]+(?:\s*,\s*|\s*,?\s*(?:and|&)\s+)){1,}[A-Z][a-z'\-]+\)")
FULL = re.compile(r"\b[A-Z][a-z]+(?:\s+[A-Z]\.?)?(?:\s+[A-Z][a-z]+)?\s+[A-Z][a-z]+(?=\s*(?:-\s*[A-Z]{2,}|\((?:primary |co-?)?mentor|, (?:MD|PhD)))")
def scrub(t):
    if not t: return t
    t = PAREN.sub("([NAME])", t); t = FULL.sub("[NAME]", t)
    # "The Surname lab/laboratory/group", "Surname's lab"
    t = re.sub(r"\b([A-Z][a-z]{3,})(?:'s)?(?=\s+(?:lab|labs|laboratory|group|research group)\b)", lambda m: m.group(0) if m.group(1).lower() in SCI | {"the","our","this","their","core","nhlbi","his","her"} else "[NAME]", t)
    # single surname in parentheses after a lower-case field word, eg "pathology (Surname)"
    t = re.sub(r"(?<=[a-z] )\(([A-Z][a-z]{3,})\)", lambda m: m.group(0) if (KEEP.match(m.group(1)) or m.group(1).lower() in SCI) else "([NAME])", t)
    doc = nlp(t); out = []; last = 0
    for e in doc.ents:
        w = e.text.split()
        if (e.label_ == "PERSON" and 2 <= len(w) <= 4 and all(re.fullmatch(r"[A-Z][a-z'\-]+|[A-Z]\.?", x) for x in w)
                and not any(KEEP.match(x) for x in w)):
            out.append(t[last:e.start_char]); out.append("[NAME]"); last = e.end_char
    out.append(t[last:]); t = "".join(out)
    # surnames trailing a mask, incl. hyphenated names broken across lines ("[NAME] Surname, First-\nName Surname")
    t = re.sub(r"\[NAME\]\s+[A-Z][a-z'\-]+(?=\s*,)", "[NAME]", t)
    t = re.sub(r"(\[NAME\],\s*)[A-Z][a-z]+-\s*\n?\s*[A-Z][a-z]+\s+[A-Z][a-z]+", r"\1[NAME]", t)
    return re.sub(r"\[NAME\](?:(?:\s*,\s*|\s*,?\s+(?:and|&)\s+)\[NAME\])+", "[NAME]", t)
wb = load_workbook(P); ws = wb["CHD_review"]; hdr = [c.value for c in ws[1]]
cols = [hdr.index(h) + 1 for h in ("Abstract / project summary", "Public health narrative")]  # titles: regex pass only (NER over-masks gene/device names)
n = 0; n = 0
for r in range(2, ws.max_row + 1):
    for c in cols:
        v = ws.cell(r, c).value
        if isinstance(v, str): s = scrub(v); n += s.count("[NAME]") - v.count("[NAME]"); ws.cell(r, c).value = s
wb.properties.creator = ""; wb.properties.lastModifiedBy = ""; wb.save(P); print("new [NAME] masks:", n)
