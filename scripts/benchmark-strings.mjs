import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { cpus } from 'node:os';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isMainThread, parentPort, Worker, workerData } from 'node:worker_threads';

const options = {max_candidates: 8, max_parts: 6, max_atom_evaluations: 4000, max_steps: 30000, max_frontier: 1024};
const timeoutMs = 5000;
const hash = value => createHash('sha256').update(value).digest('hex');

async function evaluate({engine, train, holdout}) {
  const {handle} = await import(pathToFileURL(engine).href);
  const run = req => {
    const result = JSON.parse(handle(JSON.stringify(req)));
    if (!result.ok) throw new Error(result.error);
    return result;
  };
  const start = performance.now();
  const report = run({op: 'synthesize', examples: train, options});
  const ms = performance.now() - start;
  const columns = train[0].input.map((_, i) => 'c' + i);
  const passes = (expression, examples) => {
    const recipe = {version: 1, columns, outputs: [{name: 'out', expression}]};
    const result = run({op: 'apply', recipe, table: {columns, rows: examples.map(x => x.input)}});
    return result.failures === 0 && result.rows.length === examples.length &&
      result.rows.every((row, i) => row.values[0] === examples[i].output);
  };
  const predictions = report.candidates.map(c => {
    assert.ok(passes(c.expression, train), 'Inconsistent learned candidate');
    return passes(c.expression, holdout);
  });
  return {training: predictions.length > 0, top1: predictions[0] ?? false, any: predictions.includes(true),
    candidates: predictions.length, truncated: report.truncated, steps: report.stats.steps,
    atom_evaluations: report.stats.atom_evaluations, synthesis_ms: ms};
}

async function runTask(engine, task) {
  const worker = new Worker(new URL(import.meta.url), {workerData: {engine, train: task.train, holdout: task.holdout}});
  let timer;
  try {
    return await new Promise(done => {
      timer = setTimeout(() => done({timeout: true}), timeoutMs);
      worker.once('message', done);
      worker.once('error', err => done({error: err.message}));
      worker.once('exit', code => done({error: 'Worker exited with code ' + code}));
    });
  } finally {
    clearTimeout(timer);
    await worker.terminate();
  }
}

function summarize(results) {
  const latency = results.map(r => r.synthesis_ms).filter(Number.isFinite).sort((a,b) => a-b);
  const quantile = p => latency[Math.ceil(latency.length * p) - 1] ?? null;
  const count = key => results.filter(r => r[key]).length;
  return {files: results.length, training: count('training'), top1: count('top1'),
    any: count('any'), truncated: count('truncated'), timeouts: count('timeout'), errors: count('error'),
    p50_ms: quantile(0.5), p95_ms: quantile(0.95)};
}

async function benchmark() {
  const dataset = JSON.parse(await readFile('artifacts/sygus-2017/tasks.json'));
  const {version} = JSON.parse(await readFile('package.json'));
  const variants = [{version, path: resolve('dist/engine.js')}];
  if (process.argv.includes('--paired')) {
    const old = process.env.BASELINE_VERSION ?? '0.5.0';
    const path = resolve('artifacts/baselines/v' + old + '-engine.mjs');
    const known = JSON.parse(await readFile('scripts/baselines.json'))[old];
    assert.equal(hash(await readFile(path)), known.engine);
    variants.unshift({version: old, path});
  }
  const results = [];
  for (const [index, task] of dataset.tasks.entries()) {
    const row = {name: task.name, sha256: task.sha256};
    results.push(row);
    if (task.excluded) { row.excluded = task.excluded; continue; }
    const inputs = new Set(task.train.map(e => JSON.stringify(e.input)));
    assert.ok(task.holdout.length && task.holdout.every(e => !inputs.has(JSON.stringify(e.input))));
    row.split_sha256 = hash(JSON.stringify([task.train, task.holdout]));
    row.training_rows = task.train.length;
    row.heldout_rows = task.holdout.length;
    row.engines = {};
    for (const v of index % 2 ? [...variants].reverse() : variants) {
      row.engines[v.version] = await runTask(v.path, task);
    }
  }
  const eligible = results.filter(r => r.engines);
  const unique = [...new Map(eligible.map(r => [r.split_sha256, r])).values()];
  const engines = {};
  for (const v of variants) {
    engines[v.version] = {sha256: hash(await readFile(v.path)),
      by_file: summarize(eligible.map(r => r.engines[v.version])),
      unique_splits: summarize(unique.map(r => r.engines[v.version]))};
  }
  const record = {date: new Date().toISOString(), upstream: dataset.revision, track: '2017/PBE_Strings_Track',
    methodology: 'Entire pinned track. Deduplicate identical inputs per file, exclude contradictory targets. Order inputs by SHA-256 of the compact JSON UTF-8 input tuple. Train on the first min(6,n-1,ceil(2n/3)); withhold all others. No gold or probes are sent to synthesis. One task passes only if all withheld outputs match. Any is an oracle diagnostic. Variants can share constraints; exact duplicate splits are also reported once. This is an I/O transformation study; the competition grammar is not enforced. Latency is one timed synthesis invocation per file and engine; wall-clock timeout includes worker startup and replay.',
    options, timeout_ms: timeoutMs, machine: {cpu: cpus()[0].model, node: process.version, platform: process.platform},
    inventory: results.length, eligible: eligible.length, distinct_splits: unique.length, engines, results};
  console.log(JSON.stringify({inventory: record.inventory, eligible: record.eligible, engines}, null, 2));
  await writeFile('artifacts/sygus-2017-results.json', JSON.stringify(record, null, 2) + '\n');
  if (Object.values(engines).some(v => v.by_file.errors)) process.exitCode = 1;
}

if (isMainThread) {
  await benchmark();
} else {
  try { parentPort.postMessage(await evaluate(workerData)); }
  catch (error) { parentPort.postMessage({error: error.message}); }
}
