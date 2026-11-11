"""Fetch a published workbench and verify the archive and embedded engine."""
import hashlib
import io
import json
import os
from pathlib import Path
from urllib.request import urlopen
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
version = os.environ.get("BASELINE_VERSION", "0.5.1")
record = json.loads((root / "scripts/baselines.json").read_text())[version]
destination = root / f"artifacts/baselines/v{version}-engine.mjs"
if destination.exists():
    assert hashlib.sha256(destination.read_bytes()).hexdigest() == record["engine"]
else:
    prefix = f"ExampleLoom-{version}-workbench"
    url = f"https://github.com/zhangbowen2006/ExampleLoom/releases/download/v{version}/{prefix}.zip"
    with urlopen(url, timeout=90) as response:
        archive = response.read()
    assert hashlib.sha256(archive).hexdigest() == record["archive"]
    with ZipFile(io.BytesIO(archive)) as bundle:
        engine = bundle.read(f"{prefix}/dist/engine.js")
    assert hashlib.sha256(engine).hexdigest() == record["engine"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(engine)
print(f"Verified v{version} baseline")
