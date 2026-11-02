import { spawnSync } from 'node:child_process';
import { cp, mkdir, rm } from 'node:fs/promises';
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
await cp(resolve(root, 'examples'), resolve(root, 'dist/examples'), { recursive: true });
await cp(resolve(root, 'LICENSE'), resolve(root, 'dist/LICENSE'));
await cp(resolve(root, 'LICENSES'), resolve(root, 'dist/LICENSES'), { recursive: true });
console.log('Built dist/ — MoonBit engine and standalone workbench.');
