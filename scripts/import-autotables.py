"""Fetch pinned external Auto-Tables examples for an isolated evaluation.

Do not copy upstream tables into the package. The complete transpose category
is selected before scoring; malformed or over-limit cases remain in inventory.
"""
from pathlib import Path
import csv, hashlib, io, json, urllib.request, zipfile

ROOT = Path(__file__).resolve().parents[1]
REV = '45f91a7c9b7665690d2dfdce0c27fc777896bdab'
ARCHIVE_SHA = '2ffac26151cbcb3396fc355b6522595a76bdfd1e1a2ac901491540f5f771ceb4'
URL = f'https://codeload.github.com/LiPengCS/Auto-Tables-Benchmark/zip/{REV}'
OUT = ROOT/'artifacts'/'autotables'
OUT.mkdir(parents=True, exist_ok=True)
archive = ROOT/'artifacts'/'auto-tables-reference.zip'
if not archive.exists():
    with urllib.request.urlopen(URL, timeout=120) as response:
        archive.write_bytes(response.read())
data = archive.read_bytes()
assert hashlib.sha256(data).hexdigest() == ARCHIVE_SHA, 'Pinned archive hash mismatch'
csv.field_size_limit(1_000_000)
def parse(blob):
    with io.StringIO(blob.decode('utf-8-sig'), newline='') as source:
        return list(csv.reader(source, strict=True))
def rectangular(rows):
    return bool(rows) and bool(rows[0]) and all(len(r)==len(rows[0]) for r in rows)
with zipfile.ZipFile(io.BytesIO(data)) as z:
    prefix=f'Auto-Tables-Benchmark-{REV}/ATBench/transpose/'
    names=sorted(x for x in z.namelist() if x.startswith(prefix) and x.endswith('/info.json'))
    assert len(names)==28, 'Unexpected upstream category inventory'
    tasks=[]
    for name in names:
        directory=name.rsplit('/',1)[0]; task=directory.rsplit('/',1)[1]
        raw_in=z.read(directory+'/data.csv');raw_out=z.read(directory+'/result.csv');info=json.loads(z.read(name))
        entry={'name':task,'source':info.get('source'),'input_sha256':hashlib.sha256(raw_in).hexdigest(),'output_sha256':hashlib.sha256(raw_out).hexdigest()}
        try:
            rows=parse(raw_in); expected=parse(raw_out)
            if not rectangular(rows) or not rectangular(expected):raise ValueError('empty or ragged CSV')
            # This extra probe is a mathematical transpose on modified source
            # rows, not a second upstream gold example or real user validation.
            changed=[['probe:'+v for v in row] for row in rows[:min(4,len(rows))]]
            changed.append(['new:'+v for v in rows[-1]])
            if len(changed)==len(rows):
                changed.append(['extra:'+v for v in rows[0]])
            assert len(changed)!=len(rows), 'Probe must change the source row count'
            heldout=[list(row) for row in zip(*changed)]
            entry.update(input=rows,output=expected,holdout=changed,holdout_output=heldout,
                         upstream_matches_transpose=(expected==[list(row) for row in zip(*rows)]))
        except (UnicodeError,csv.Error,ValueError) as error:
            entry['parse_error']=str(error)
        tasks.append(entry)
manifest={'repository':'https://github.com/LiPengCS/Auto-Tables-Benchmark','revision':REV,'license':'MIT repository license; raw data is downloaded for local evaluation, not redistributed here','archive_url':URL,'archive_sha256':ARCHIVE_SHA,'selection':'All 28 upstream ATBench/transpose tasks at the pinned revision, with no outcome-based exclusions','tasks':tasks}
(OUT/'tasks.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')),'utf-8')
print(f'Verified pinned external archive and prepared all {len(tasks)} transpose tasks (including errors).')
