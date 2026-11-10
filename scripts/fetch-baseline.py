"""Download and verify the immutable public v0.3.0 engine for comparison."""
from pathlib import Path
import hashlib,io,urllib.request,zipfile
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'artifacts/baselines/v0.3.0-engine.mjs'
engine_sha='8085e8ebfd6692d6bb2dc193eebb584c9302c90e3246ca54e9316e40005703c1'
if out.exists():
    assert hashlib.sha256(out.read_bytes()).hexdigest()==engine_sha
    print('Verified existing immutable v0.3.0 baseline')
else:
    url='https://github.com/zhangbowen2006/ExampleLoom/releases/download/v0.3.0/ExampleLoom-0.3.0-workbench.zip'
    blob=urllib.request.urlopen(url,timeout=90).read()
    assert hashlib.sha256(blob).hexdigest()=='78dc86407991e4ce7b7f0712eeee98237823c1d3faa8592009d6893672fec0e5'
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        engine=archive.read('ExampleLoom-0.3.0-workbench/dist/engine.js')
    assert hashlib.sha256(engine).hexdigest()==engine_sha
    out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(engine)
    print('Downloaded and verified immutable v0.3.0 baseline')
