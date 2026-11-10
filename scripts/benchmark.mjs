import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { Worker } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';
import { resolve, dirname, sep } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import {auditTask} from './benchmark-data.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const engine_path=resolve(root,process.env.ENGINE_PATH??'dist/engine.js');
const results_path=resolve(root,process.env.BENCHMARK_RESULTS??'artifacts/benchmark-results.json');
if(!results_path.startsWith(resolve(root,'artifacts')+sep))throw new Error('Benchmark output must remain in artifacts/');
const manifest = JSON.parse(await readFile(resolve(root, 'fixtures/foofah/manifest.json'), 'utf8'));
const options = {max_depth:4, max_states:128, max_evaluations:2000, max_candidates:8};
const timeout_ms = Number(process.env.BENCHMARK_TIMEOUT_MS ?? 5000);
if (!Number.isSafeInteger(timeout_ms) || timeout_ms < 100 || timeout_ms > 60000) throw new Error('Invalid timeout');
const rows = [];
const selected = manifest.files.filter(f => f.name.startsWith('exp0_') && f.name.endsWith('.txt'));
if(selected.length!==250)throw new Error('Expected the complete pinned 250-task corpus');
for (const source of selected) {
  const bytes = await readFile(resolve(root,'fixtures/foofah',source.name));
  if (createHash('sha256').update(bytes).digest('hex') !== source.sha256) throw new Error(`Fixture hash mismatch: ${source.name}`);
  const task = JSON.parse(bytes);
  const outcome = await new Promise(resolveResult => {
    const worker = new Worker(new URL('./benchmark-worker.mjs', import.meta.url), {workerData:{task,options,engine_path}});
    const finish = value => { clearTimeout(timer); worker.terminate(); resolveResult(value); };
    const timer = setTimeout(() => finish({timeout:true, error:'Per-task wall-clock budget exceeded'}), timeout_ms);
    worker.once('message', finish); worker.once('error', error => finish({error:error.message}));
    worker.once('exit', code => { if (code !== 0) finish({error:`Worker exit ${code}`}); });
  });
  rows.push({task:source.name, family:task.TestName, sha256:source.sha256,...auditTask(task), ...outcome});
  if (rows.length % 25 === 0) console.log(`${rows.length}/${selected.length}: training ${rows.filter(r=>r.training_solved).length}, held-out top1 ${rows.filter(r=>r.top1_holdout).length}, timeouts ${rows.filter(r=>r.timeout).length}`);
}
const latencies = rows.map(r=>r.synthesis_ms).filter(Number.isFinite).sort((a,b)=>a-b);
const percentile = p => latencies.length ? latencies[Math.min(latencies.length-1,Math.ceil(p*latencies.length)-1)] : null;
const families = [...new Set(rows.map(r=>r.family))].sort().map(family => {
  const part = rows.filter(r=>r.family === family);
  return {family,total:part.length,holdout_available:part.filter(r=>r.holdout_available).length,training:part.filter(r=>r.training_solved).length,top1:part.filter(r=>r.top1_holdout).length,any:part.filter(r=>r.any_holdout).length};
});
const count = key => rows.filter(r=>r[key]).length;
const unexpected_errors=rows.filter(r=>r.error&&!r.timeout&&!r.error.startsWith('table training limit:'));
const git = args => { try{return execFileSync('git',args,{cwd:root,encoding:'utf8'}).trim();}catch{return null;} };
const coreFiles=(await readdir(root)).filter(name=>name.endsWith('.mbt')&&!name.includes('test')).sort();
const source_sha256={};
for(const name of [...coreFiles,'moon.mod','moon.pkg','scripts/benchmark.mjs','scripts/benchmark-worker.mjs','dist/engine.js'])source_sha256[name]=createHash('sha256').update(await readFile(resolve(root,name))).digest('hex');
const evidence = {schema:1, timestamp:new Date().toISOString(), engine_label:process.env.ENGINE_LABEL??'working-tree',engine_sha256:createHash('sha256').update(await readFile(engine_path)).digest('hex'), source_revision:manifest.revision,
  selection:manifest.selection, options, timeout_ms,
  methodology:'All 250 upstream exp0 tasks retained. 25 sentinel TestAnswer values NOT AVAILABLE, SORRY are marked missing gold, not prediction failures. Report success counts out of both 250 inventory tasks and 225 gold-available tasks. All grid rows are data with generated c0.. names. Only InputTable/OutputTable train. Top1 is fixed before TestingTable/TestAnswer evaluation. Any is an oracle upper bound. Row/cell order and empties are significant. Input overlaps and reference warnings are retained. Errors and timeouts remain in gold-available denominator. No Foofah or PROSE executable comparison was performed.',
  environment:{platform:os.platform(),release:os.release(),cpu:os.cpus()[0]?.model,node:process.version,git_head:git(['rev-parse','HEAD']),dirty:git(['status','--porcelain']) !== ''},source_sha256:process.env.ENGINE_PATH?null:source_sha256,
  summary:{tasks:rows.length,families:families.length,holdout_available:count('holdout_available'),missing_holdout_gold:rows.filter(r=>!r.holdout_available).length,reference_conflicts:rows.filter(r=>r.reference_warnings.includes('identical_input_conflicting_reference')).length,training_solved:count('training_solved'),top1_holdout:count('top1_holdout'),any_holdout:count('any_holdout'),timeouts:count('timeout'),errors:rows.filter(r=>r.error&&!r.timeout).length,unexpected_errors:unexpected_errors.length,truncated:count('truncated'),p50_ms:percentile(.5),p95_ms:percentile(.95),max_ms:latencies.at(-1)??null}, families, results:rows};
await mkdir(resolve(root,'artifacts'),{recursive:true});
await mkdir(dirname(results_path),{recursive:true});
await writeFile(results_path,JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence.summary,null,2));
if(unexpected_errors.length)process.exitCode=1;
