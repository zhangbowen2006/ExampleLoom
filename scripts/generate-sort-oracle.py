"""Independent exact-decimal/stable-sort reference; no engine code is imported."""
import json, random, sys
from decimal import Decimal
from pathlib import Path

rng = random.Random(20261111)
root = Path(__file__).resolve().parents[1]
cases = []
for case in range(128):
    columns = ['text', 'amount', 'aux', 'id']
    def number():
        if rng.randrange(4) == 0:
            return rng.choice(['-0.00', '0', '+1', '01.00', '-1.10', '-1.001'])
        whole = ''.join(str(rng.randrange(10)) for _ in range(rng.randint(1, 65)))
        fraction = ''.join(str(rng.randrange(10)) for _ in range(rng.randint(1, 18)))
        return rng.choice(['', '+', '-']) + whole + ('.'+fraction if rng.randrange(2) else '')
    rows = [[rng.choice(['', 'a', 'aa', 'z', 'A', '中', '😀', '�', ' x']), number(), str(rng.randrange(6)), str(i)] for i in range(rng.randrange(61))]
    keys = [[column, 'text' if column == 'text' else rng.choice(['text','decimal']), rng.choice(['asc','desc'])] for column in rng.sample(columns[:3], rng.randint(1,3))]
    expected = list(rows)
    # Python's built-in stable sorting, from the last key to the first; Decimal
    # comparisons use original strings without rounding or binary floats.
    for column, kind, direction in reversed(keys):
        index = columns.index(column)
        expected = sorted(expected, key=lambda row: Decimal(row[index]) if kind == 'decimal' else row[index], reverse=direction == 'desc')
    cases.append({'name':f'exact-stable-sort-{case}', 'table':{'columns':columns,'rows':rows}, 'keys':keys, 'expected':{'columns':columns,'rows':expected}})
out = root/'artifacts/sort-oracle.json'
out.parent.mkdir(exist_ok=True)
out.write_bytes((json.dumps({'seed':20261111,'reference':'Python stable sorted + decimal.Decimal','python':sys.version.split()[0],'scope':'constructed differential validation, not independent external tasks','cases':cases},ensure_ascii=False,indent=2)+'\n').encode())
print(f'Generated {len(cases)} exact sorting reference cases')
