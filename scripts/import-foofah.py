"""Fetch MIT-licensed upstream tests at a fixed revision, without executing them.

The separate foofah_benchmarks repository has no detected license; instead use
the identical-purpose tests/data corpus distributed in the licensed main repo.
All exp0_*.txt files are included, regardless of expected solver support.
"""
from pathlib import Path
import hashlib, io, json, urllib.request, zipfile

ROOT = Path(__file__).resolve().parents[1]
REV = '970864cd53b4c774a3dbdf4589d207f57ec63208'
URL = f'https://codeload.github.com/umich-dbgroup/foofah/zip/{REV}'
dest = ROOT / 'fixtures' / 'foofah'
dest.mkdir(exist_ok=True)
manifest_path = dest / 'manifest.json'
if manifest_path.exists():
    manifest = json.loads(manifest_path.read_text('utf-8'))
    for item in manifest['files']:
        assert hashlib.sha256((dest/item['name']).read_bytes()).hexdigest() == item['sha256'], item['name']
    print(f"Verified {len(manifest['files'])} pinned upstream files offline")
else:
    archive = urllib.request.urlopen(URL, timeout=120).read()
    files = []
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        for info in sorted(z.infolist(), key=lambda item: item.filename):
            path = Path(info.filename)
            if path.name == 'LICENSE.md' and len(path.parts) == 2 or (
                '/tests/data/exp0_' in info.filename and path.suffix == '.txt'):
                data = z.read(info)
                (dest/path.name).write_bytes(data)
                files.append({'name': path.name, 'upstream_path': '/'.join(path.parts[1:]), 'sha256': hashlib.sha256(data).hexdigest()})
    assert any(f['name'] == 'LICENSE.md' for f in files)
    manifest = {'repository': 'https://github.com/umich-dbgroup/foofah', 'revision': REV,
                'archive_url': URL, 'archive_sha256': hashlib.sha256(archive).hexdigest(),
                'selection': 'Every tests/data/exp0_*.txt file in this revision; no success-based exclusions.',
                'license': 'MIT, Copyright (c) 2017 University of Michigan', 'files': files}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', 'utf-8')
    print(f"Imported {len(files)-1} upstream tasks and full MIT license")
