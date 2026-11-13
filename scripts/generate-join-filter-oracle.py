"""Generate deterministic SQL-reference cases for a learned join/filter/group job.

These are constructed cases, not independently sampled business data or blind
competition benchmarks. SQLite is used as a separate execution implementation.
"""
import json
import random
import sqlite3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'artifacts' / 'join-filter-oracle.json'
out.parent.mkdir(parents=True, exist_ok=True)
rng = random.Random(20261113)
db = sqlite3.connect(':memory:')
db.executescript('CREATE TABLE orders (seq INTEGER, sku TEXT, status TEXT, amount INTEGER);'
                 'CREATE TABLE catalog (sku TEXT PRIMARY KEY, category TEXT);')
cases = []
for case in range(40):
    db.execute('DELETE FROM orders')
    db.execute('DELETE FROM catalog')
    catalog = [(f'sku-{case}-{i}', f'category-{i % 3}') for i in range(4)]
    db.executemany('INSERT INTO catalog VALUES (?,?)', catalog)
    orders = []
    for i in range(case % 13):
        sku = rng.choice(catalog)[0] if i % 7 else f'unknown-{case}'
        status = rng.choice(['paid', 'pending', 'canceled', 'paid '])
        amount = rng.randint(-1000, 5000) if status == 'paid' else 'not-a-number'
        orders.append((i, sku, status, str(amount)))
    db.executemany('INSERT INTO orders VALUES (?,?,?,?)', orders)
    expected = [list(row) for row in db.execute(
        "SELECT c.category, CAST(SUM(o.amount) AS TEXT) "
        "FROM orders o JOIN catalog c ON o.sku=c.sku WHERE o.status=? "
        "GROUP BY c.category ORDER BY MIN(o.seq)", ('paid',))]
    if case % 2:
        order_table = {'columns': ['amount', 'sku', 'status'],
                       'rows': [[amount, sku, status] for _, sku, status, amount in orders]}
        catalog_table = {'columns': ['category', 'sku'],
                         'rows': [[category, sku] for sku, category in catalog]}
    else:
        order_table = {'columns': ['sku', 'status', 'amount'],
                       'rows': [[sku, status, amount] for _, sku, status, amount in orders]}
        catalog_table = {'columns': ['sku', 'category'], 'rows': [list(row) for row in catalog]}
    cases.append({'sources': [{'name': 'orders', 'table': order_table},
                              {'name': 'catalog', 'table': catalog_table}],
                  'expected': {'columns': ['category', 'total'], 'rows': expected}})
out.write_text(json.dumps({'sqlite_version': sqlite3.sqlite_version, 'cases': cases},
                          ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Generated {len(cases)} SQL-reference cases with SQLite {sqlite3.sqlite_version}.')
