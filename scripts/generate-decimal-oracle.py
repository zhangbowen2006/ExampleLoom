"""Independent constructed reference; no host float and no default-28-digit rounding."""
from decimal import Decimal, localcontext, Inexact
from pathlib import Path
import random,json
rng=random.Random(131122)
def canonical(n):
 if n==0:return '0'
 s=format(n,'f')
 return s.rstrip('0').rstrip('.') if '.' in s else s
cases=[]
with localcontext() as context:
 context.prec=1024
 context.traps[Inexact]=True
 for i in range(350):
  rows=[]
  for j in range(rng.randint(1,30)):
   whole=str(rng.randrange(10**rng.randint(1,60)))
   scale=rng.randint(0,40)
   fraction=''.join(str(rng.randrange(10)) for _ in range(scale))
   text=('-' if rng.randrange(2) else '+')+'0'*rng.randrange(3)+whole+('.'+fraction if scale else '')
   rows.append([chr(65+rng.randrange(4)),text])
  if i==0:rows=[['A','9'*256],['A','1'],['B','0.'+'0'*252+'1'],['B','-0.'+'0'*252+'1']]
  groups={}
  for key,text in rows:groups.setdefault(key,[]).append(Decimal(text))
  expected=[[k,canonical(sum(v)),canonical(min(v)),canonical(max(v)),str(len(v))] for k,v in groups.items()]
  cases.append({'input':{'columns':['group','amount'],'rows':rows},'expected':{'columns':['group','total','min','max','n'],'rows':expected}})
out=Path(__file__).resolve().parents[1]/'artifacts/decimal-oracle.json'
out.parent.mkdir(exist_ok=True);out.write_text(json.dumps({'precision':1024,'inexact_trapped':True,'cases':cases},ensure_ascii=False),'utf-8')
print(f'{len(cases)} constructed Decimal references generated at precision 1024 with Inexact trapped.')
