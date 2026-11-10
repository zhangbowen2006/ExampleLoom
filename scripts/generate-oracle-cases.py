"""Constructed differential cases using pandas as the semantic reference.

This is not an external/untouched benchmark. Train/test IDs and random values
are separate, and expected tables are produced by pandas, not MoonBit.
"""
from pathlib import Path
import json, random
import pandas as pd

ROOT=Path(__file__).resolve().parents[1]
cases=[]
def table(frame):
    return {'columns':list(frame.columns),'rows':frame.fillna('').astype(str).values.tolist()}
def grid(frame):
    frame=frame.fillna('').astype(str)
    return {'columns':[f'c{i}' for i in range(len(frame.columns))],'rows':frame.values.tolist()}
def pivot(frame):
    keys=frame['id'].drop_duplicates().tolist()
    levels=frame['kind'].drop_duplicates().tolist()
    wide=frame.pivot(index='id',columns='kind',values='value').reindex(index=keys,columns=levels).fillna('')
    return {'columns':[f'c{i}' for i in range(len(levels)+1)],'rows':[['']+levels]+[[key]+wide.loc[key].tolist() for key in keys]}
def build(family,seed,held):
    rng=random.Random(seed+(10000 if held else 0)); count=5 if held else 3
    ids=[f'{"H" if held else "T"}{seed}-{i}' for i in range(count)]
    def value():return f'{rng.randrange(1000):04d}'
    if family=='dynamic_pivot':
        kinds=['temperature','c0','']+(['unseen'] if held else [])
        frame=pd.DataFrame([(key,k,value()) for key in ids for k in kinds],columns=['id','kind','value'])
        return table(frame),pivot(frame),[['pivot_grid',['id'],'kind','value']]
    if family=='carried_context':
        rows=[]
        for key in ids:
            rows.append([key,'header '+key,''])
            rows.extend([['item-'+str(j),'detail',value()] for j in range(rng.randrange(1,4))])
        frame=pd.DataFrame(rows,columns=['id','label','amount']); headers=frame['amount'].eq('')
        context=frame[['id','label']].where(headers).ffill().rename(columns=lambda s:'context_'+s)
        output=pd.concat([context,frame],axis=1).loc[~headers].reset_index(drop=True)
        return table(frame),table(output),[['carry_context',['empty',['field',2]],['id','label']]]
    if family in ['marker_records','blank_records']:
        rows=[]
        for key in ids:
            rows.extend(['*'+key if family=='marker_records' else key]+[value() for _ in range(rng.randrange(2,5))])
            if family=='blank_records': rows.append('')
        frame=pd.DataFrame({'line':rows})
        if family=='marker_records':
            group=frame['line'].str.startswith('*').cumsum(); keep=~frame['line'].isna()
            steps=[['segment_rows',['matches',['field',0],'^\\*',False],True]]
        else:
            group=frame['line'].eq('').cumsum();keep=frame['line'].ne('')
            steps=[['segment_rows',['empty',['field',0]],False]]
        output=frame.loc[keep].groupby(group[keep],sort=False)['line'].agg(list)
        padded=pd.DataFrame({i:pd.Series(values) for i,values in enumerate(output.tolist())}).T
        return table(frame),grid(padded),steps
    if family=='labelled_cells':
        frame=pd.DataFrame([[key,'low:'+value(),'high:'+value()] for key in ids],columns=['id','m1','m2'])
        melted=frame.melt(id_vars='id',value_vars=['m1','m2'],value_name='packed')
        parts=melted['packed'].str.split(':',n=1,expand=True)
        long=pd.DataFrame({'id':melted['id'],'kind':parts[0],'value':parts[1]})
        return table(frame),pivot(long),[['fold',['id'],['m1','m2'],'__payload'],['split_column','__payload',':',['kind','value']],['pivot_grid',['id'],'kind','value']]
    if family=='combined_labels':
        rows=[[key,left,right,value()] for key in ids for left,right in [('01','small'),('02','large')]]
        frame=pd.DataFrame(rows,columns=['id','left','right','value'])
        long=frame.assign(kind=frame['left'].str.cat(frame['right']))[['id','kind','value']]
        return table(frame),pivot(long),[['combine_columns',['left','right'],'','kind'],['pivot_grid',['id'],'kind','value']]
    raise ValueError(family)
for family in ['dynamic_pivot','carried_context','marker_records','blank_records','labelled_cells','combined_labels']:
    for seed in range(6):
        before,after,steps=build(family,20261110+seed,False)
        testing,answer,_=build(family,20261110+seed,True)
        cases.append({'name':family+'-'+str(seed),'family':family,'training':{'input':before,'output':after},'testing':testing,'answer':answer,'program':{'version':2,'columns':before['columns'],'steps':steps}})
out=ROOT/'artifacts/oracle-cases.json';out.parent.mkdir(exist_ok=True)
out.write_bytes((json.dumps({'reference':'pandas','version':pd.__version__,'seed':20261110,'scope':'constructed differential validation, not external independent tasks','cases':cases},ensure_ascii=False,indent=2)+'\n').encode())
print(f'Generated {len(cases)} paired cases with pandas {pd.__version__}')
