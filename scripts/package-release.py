"""Package a clean, identified source revision and its compiled workbench."""
import argparse, hashlib, json, re, subprocess, tomllib, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()

parser=argparse.ArgumentParser()
parser.add_argument('--moon-zip',type=Path)
args=parser.parse_args()
assert Path(git('rev-parse','--show-toplevel')).resolve()==ROOT, 'The project needs its own Git repository'
assert git('status','--porcelain')=='', 'Commit or resolve pending changes before packaging'
version=json.loads((ROOT/'package.json').read_text('utf-8'))['version']
assert re.fullmatch(r'\d+\.\d+\.\d+',version)
assert tomllib.loads((ROOT/'moon.mod').read_text('utf-8'))['version']==version
build=json.loads((ROOT/'dist/BUILD.json').read_text('utf-8'))
assert build['git_head']==git('rev-parse','HEAD') and build['dirty'] is False and build['version']==version, 'Rebuild the committed revision'
assert build['engine_sha256']==hashlib.sha256((ROOT/'dist/engine.js').read_bytes()).hexdigest()
out=ROOT/'artifacts'
out.mkdir(exist_ok=True)
source=out/f'ExampleLoom-{version}-source.zip'
subprocess.run(['git','archive','--format=zip','--prefix',f'ExampleLoom-{version}/','--output',str(source),'HEAD'],cwd=ROOT,check=True)
runtime=out/f'ExampleLoom-{version}-workbench.zip'
prefix=f'ExampleLoom-{version}-workbench/'
with zipfile.ZipFile(runtime,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((ROOT/'dist').rglob('*')):
        if path.is_file(): archive.write(path,prefix+path.relative_to(ROOT).as_posix())
    archive.write(ROOT/'scripts/serve.mjs',prefix+'scripts/serve.mjs')
    archive.writestr(prefix+'START-HERE.md',f'# ExampleLoom {version}\n\nRequires Node.js >=20. Run from this folder:\n\n    node scripts/serve.mjs\n\nOpen http://127.0.0.1:4173/ for row programs or /structure.html for table programs. BUILD.json identifies the source revision. Licenses are in dist/LICENSE and dist/LICENSES. Data is processed locally.\n')
files=[source,runtime]
if args.moon_zip:
    moon=args.moon_zip.resolve()
    with zipfile.ZipFile(moon) as archive:
        manifest=tomllib.loads(archive.read('moon.mod').decode('utf-8'))
        assert manifest['name']=='zhangbowen2006/exampleloom' and manifest['version']==version
        for info in archive.infolist():
            if info.is_dir(): continue
            original=(ROOT/info.filename).resolve()
            assert original.is_relative_to(ROOT) and original.is_file(), 'Unexpected package path'
            assert original.read_bytes()==archive.read(info), 'Stale packaged file: '+info.filename
    files.append(moon)
hashes={}
for path in files:
    with zipfile.ZipFile(path) as archive:
        assert not any('artifacts/' in name or 'github-auth' in name for name in archive.namelist())
    hashes[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
record={'version':version,'git_head':build['git_head'],'engine_sha256':build['engine_sha256'],'sha256':hashes}
(out/'release-sha256.json').write_bytes((json.dumps(record,indent=2)+'\n').encode())
print(json.dumps(record,indent=2))
