"""Consume the actual exported CSV files with Python csv + SQLite independently."""
import csv
import json
import sqlite3
from pathlib import Path

root = Path(__file__).resolve().parent.parent
out = root / 'artifacts' / 'public-data'
database = out / 'catalogs.sqlite3'
con = sqlite3.connect(database)
results = []
for name in ('public-zones', 'public-locales', 'public-templates'):
    scenario = json.loads((root / 'examples' / name / 'scenario.json').read_text(encoding='utf-8'))
    with (out / (name + '.csv')).open(encoding='utf-8', newline='') as stream:
        rows = list(csv.reader(stream))
    header, values = rows[0], rows[1:]
    assert header == [field['name'] for field in scenario['fields']]
    expected = list(zip(*(field['expected'] for field in scenario['fields'])))
    assert [tuple(row) for row in values] == expected
    # All identifiers come from the fixed scenario definitions above.
    table = name.replace('-', '_')
    con.execute(f'DROP TABLE IF EXISTS {table}')
    columns = ', '.join('"' + column + '" TEXT NOT NULL' for column in header)
    con.execute(f'CREATE TABLE {table} ({columns})')
    con.executemany(f'INSERT INTO {table} VALUES (?, ?, ?)', values)
    assert con.execute(f'SELECT * FROM {table} ORDER BY rowid').fetchall() == expected
    count = con.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
    distinct = con.execute(f'SELECT count(DISTINCT "{header[0]}") FROM {table}').fetchone()[0]
    results.append({'dataset': name, 'rows': count, 'distinct_first_field': distinct, 'all_values_equal': True})
assert con.execute("SELECT location FROM public_zones WHERE zone = 'America/Argentina/Buenos_Aires'").fetchone() == ('Buenos_Aires',)
assert con.execute("SELECT bundle FROM public_locales WHERE locale = 'zh-Hant-HK'").fetchone() == ('locales/zh-Hant-HK.json',)
assert con.execute("SELECT template FROM public_templates WHERE path = 'community/AWS/CDK.gitignore'").fetchone() == ('CDK',)
con.commit()
con.close()
report = {'sqlite_version': sqlite3.sqlite_version, 'datasets': results, 'queries': 3, 'scope': 'local SQLite integration, not a customer deployment'}
(out / 'sqlite-results.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))
