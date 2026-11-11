"""13a_v2_pool.py -- CHD-signal pool for v2: project-years with any strong/weak CHD term or the RCDC CHD flag (from data/work/C.rds),
with pooled text from the WHR project tables (same FY2020/2024 intramural replacement as 02_build.R).
Output: data/work/v2_pool.pkl"""
import os,pyreadr,pandas as pd,numpy as np
WHR=os.environ.get('CHD_WHR_WORK', 'data/raw/whr_work')
C=pyreadr.read_r('data/work/C.rds')[None]
print(C.shape, list(C.columns)); print(C.dtypes.value_counts())
pool=C[(C.rcdc==True)|(C.t_str+C.s_str+C.s_weak>0)].copy()
extra=[]  # v2.1: also rows whose text names PDA / supravalvular aortic stenosis but had no v1 CHD signal
print(len(pool))

txt=[]
for fy in range(2013,2027):
    P=pyreadr.read_r(WHR+f'/proj/proj_{fy}.rds')[None]
    if fy in (2020,2024):
        Z=pyreadr.read_r(WHR+f'/proj/projz_{fy}.rds')[None]
        P=pd.concat([P[~P.FULL_PROJECT_NUM.isin(Z.FULL_PROJECT_NUM)],Z])
    xt=P[P.text.str.lower().str.contains(r'ductus arteriosus|supravalv(?:ular|ar) aortic stenosis|\bsvas\b|coarctation|heart block|pulmonary (?:arterial )?hypertension|\bpphn\b',regex=True,na=False)].FULL_PROJECT_NUM
    add=C[(C.FY==fy)&C.FULL_PROJECT_NUM.isin(xt)&~C.FULL_PROJECT_NUM.isin(pool[pool.FY==fy].FULL_PROJECT_NUM)]
    pool=pd.concat([pool,add]); s=pool[pool.FY==fy]
    t=P[P.FULL_PROJECT_NUM.isin(s.FULL_PROJECT_NUM)][['FULL_PROJECT_NUM','text']].drop_duplicates('FULL_PROJECT_NUM'); t['FY']=fy; txt.append(t)
    if fy==2013: print(P.columns.tolist())
T=pd.concat(txt); pool=pool.merge(T,on=['FY','FULL_PROJECT_NUM'],how='left'); print(pool.text.isna().sum())
pool.to_pickle('data/work/v2_pool.pkl')
