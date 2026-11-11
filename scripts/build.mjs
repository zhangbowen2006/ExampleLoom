import { spawnSync } from 'node:child_process';
import { cp, mkdir, rm, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve, dirname, basename } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const result = spawnSync('moon', ['build', '--target', 'js', '--release'], { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
const dist = resolve(root, 'dist');
if (dirname(dist) !== root || basename(dist) !== 'dist') throw new Error('Refusing to clean outside the generated dist directory');
await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
await cp(resolve(root, '_build/js/release/build/api/api.js'), resolve(root, 'dist/engine.js'));
await cp(resolve(root, 'web'), resolve(root, 'dist'), { recursive: true });
const version=JSON.parse(await readFile(resolve(root,'package.json'),'utf8')).version;
for (const name of ['index.html', 'structure.html']) {
  const page = resolve(dist, name);
  const html = await readFile(page, 'utf8');
  await writeFile(page, html.replaceAll('{{VERSION}}', version));
}

await cp(resolve(root, 'examples'), resolve(root, 'dist/examples'), { recursive: true });
await cp(resolve(root, 'LICENSE'), resolve(root, 'dist/LICENSE'));
await cp(resolve(root, 'LICENSES'), resolve(root, 'dist/LICENSES'), { recursive: true });
const git = args => {
  const result = spawnSync('git', args, {cwd:root,encoding:'utf8'});
  return result.status===0 ? result.stdout.trim() : null;
};
const top=git(['rev-parse','--show-toplevel']);
const ownsRepository=top!==null && resolve(top)===root;
const status=ownsRepository?git(['status','--porcelain']):null;
const metadata={version,built_at:new Date().toISOString(),git_head:ownsRepository?git(['rev-parse','HEAD']):null,dirty:status===null?null:status!=='',engine_sha256:createHash('sha256').update(await readFile(resolve(dist,'engine.js'))).digest('hex')};
await writeFile(resolve(dist,'BUILD.json'),JSON.stringify(metadata,null,2)+'\n');
console.log('Built dist/ — MoonBit engine and standalone workbench.');
