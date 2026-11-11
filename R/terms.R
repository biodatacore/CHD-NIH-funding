#' terms.R -- keyword dictionaries (ICU regular expressions, matched case-insensitively on
#' lower-cased title / pooled title+abstract+public-health-relevance text).
#'
#' A. CHD terms. STRONG terms name a congenital heart lesion or CHD itself; they are specific
#'    enough to count on their own. WEAK terms are CHD-related but also used outside CHD
#'    (eg, bicuspid aortic valve aortopathy, preterm patent ductus arteriosus, 22q11 deletion,
#'    "heart defect" in a syndrome list) and only add support.
CHD_STRONG <- paste0("\\b(",
  "congenital (heart|cardiac|cardiovascular)( (disease|defect|malformation|anomal|lesion|surgery|surgical))?",
  "|(adults?|patients|children|infants|individuals|people) with (complex |critical |severe |repaired )?congenital heart",
  "|achd",                       # NB: bare 'chd' is NOT used (it also abbreviates coronary heart disease)
  "|fontan(?!el)|single[- ]ventricle|univentricular|functionally univentricular",
  "|hypoplastic left heart|tetralogy of fallot|tof repair|repaired tetralogy",
  "|transposition of the great (arteries|vessels)|\\bd-tga\\b|\\bl-tga\\b|\\bcc-?tga\\b|congenitally corrected transposition",
  "|coarctation of the aorta|aortic coarctation|interrupted aortic arch",
  "|(atrial|ventricular|atrioventricular) septal defects?|avsd|atrioventricular canal",
  "|ebstein'?s? anomaly|truncus arteriosus|double[- ]outlet right ventricle|dorv",
  "|pulmonary atresia|tricuspid atresia|total anomalous pulmonary venous|tapvr|tapvc",
  "|heterotaxy|conotruncal|outflow tract (defect|malformation|anomal)",
  "|(cardiac|heart|cardiovascular) (malformation|birth defect)s?|congenital cardiopathy",
  "|norwood|hybrid stage i|bidirectional glenn|cavopulmonary",
  ")")
CHD_WEAK <- paste0("\\b(bicuspid aortic valve|patent ductus arteriosus|\\bpda\\b|22q11|digeorge",
  "|heart defects?|cardiac defects?|valve malformation|septation defect|pediatric heart network",
  "|pediatric cardiac (genomics|surgery)|left ventricular outflow tract obstruction|lvoto|noonan syndrome|turner syndrome)")

#' B. Age-group terms (human populations).
PED <- paste0("\\b(pediatric|paediatric|child|children|childhood|infan(t|ts|cy)|neonat(e|es|al)|newborns?",
  "|fetal|fetus(es)?|prenatal(ly)?|perinatal|antenatal|in utero|nicu|toddlers?|school[- ]age|preschool",
  "|adolescen(t|ts|ce)|youth|kids|boys and girls|birth cohort|neurodevelopment(al)?|preterm|postnatal",
  "|cardiac intensive care unit|cicu|norwood|stage i palliation|interstage)")
# 'adult' only counts when it refers to people (not 'adult mice', 'adult zebrafish',
# 'adult stem cells', 'adult cardiomyocytes', 'adult heart' in animals).
ADULT <- paste0("\\b(achd|adult congenital|adults with|adult (patients|survivors|population|cohort|clinic|chd|care|outcomes|women|men)",
  "|young adults|older adults|adulthood|grown[- ]up congenital|guch|transition(ing)? (from pediatric|to adult)",
  "|pregnan(t|cy) (in|among) women with|women with (congenital|chd|repaired)|aging (with|fontan)|middle[- ]aged)")
LIFESPAN <- "\\b(children and adults|adults and children|pediatric and adult|adult and pediatric|from (childhood|infancy|birth) (to|through|into) adulthood|across the (lifespan|life course) (of|in) (patients|people|individuals) with)"
#' C. Basic / mechanistic science terms (non-age-specific when no human age group is named).
BASIC <- paste0("\\b(mice|mouse|murine|zebrafish|xenopus|chick|drosophila|embryos?|embryonic|organoids?",
  "|ipsc|induced pluripotent|stem cells?|cardiomyocytes?|cardiac (development|progenitor|neural crest)|second heart field",
  "|heart (development|morphogenesis)|transcription factor|gene regulatory|enhancers?|chromatin|signaling pathway|knockout|in vitro)")
#' D. Title phrases naming pediatric cardiology as the setting (used together with >= 1 strong term).
PED_CARD_TITLE <- "\\b(pediatric|paediatric|infant|neonatal|child(hood|ren)?'?s?) (heart|cardiac|cardiology|cardiovascular|cardiothoracic)"
#' E. Human / clinical-research terms; compared with BASIC to tell mechanistic from clinical work.
HUMAN <- paste0("\\b(patients?|surger(y|ies)|surgical|cohorts?|trials?|registry|registries|clinical|hospitali[sz]|hospitals?",
  "|survivors?|participants|enroll(ed|ment)?|outcomes|quality of life|catheteri[sz]ation|transplant(ation)?|echocardiogra)")
