import {readFile,writeFile,mkdir,copyFile}from'node:fs/promises';
import {spawn}from'node:child_process';
import {resolve,dirname}from'node:path';
import {fileURLToPath}from'node:url';
import {createHash}from'node:crypto';
import assert from'node:assert/strict';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const baselineVersion = process.env.BASELINE_VERSION ?? '0.5.1';
const currentVersion = JSON.parse(await readFile(resolve(root, 'package.json'))).version;
const metadata = JSON.parse(await readFile(resolve(root, 'scripts/baselines.json')))[baselineVersion];
assert.ok(metadata && baselineVersion !== currentVersion, 'Choose a distinct recorded release');
const baseline=resolve(root,process.env.BASELINE_ENGINE_PATH??`artifacts/baselines/v${baselineVersion}-engine.mjs`);
const expected=metadata.engine;
assert.equal(createHash('sha256').update(await readFile(baseline)).digest('hex'),expected,'Use the immutable published engine');
const repeats=Number(process.env.BENCHMARK_REPEATS??3);
assert.ok(Number.isSafeInteger(repeats)&&repeats>=1&&repeats<=5);
await mkdir(resolve(root,'artifacts/comparison'),{recursive:true});
const reports={baseline:[],current:[]};
for(let round=0;round<repeats;round++)for(const variant of round%2===0?['baseline','current']:['current','baseline']){
  const path=`artifacts/comparison/${variant}-${round+1}.json`;
  const env={...process.env,BENCHMARK_RESULTS:path,ENGINE_LABEL:'v'+(variant==='baseline'?baselineVersion:currentVersion)};
  delete env.ENGINE_PATH;
  if(variant==='baseline')env.ENGINE_PATH=baseline;
  await new Promise((done,fail)=>{const child=spawn(process.execPath,['scripts/benchmark.mjs'],{cwd:root,env,stdio:'inherit'});child.on('error',fail);child.on('exit',code=>code===0?done():fail(new Error(`${variant} failed: ${code}`)));});
  reports[variant].push(JSON.parse(await readFile(resolve(root,path),'utf8')));
}
const median=values=>{const sorted=values.toSorted((a,b)=>a-b);return sorted[Math.floor(sorted.length/2)];};
for(const [name,runs]of Object.entries(reports)){
  const choices=runs[0].results.map(r=>[r.task,!!r.training_solved,r.top1_holdout,r.any_holdout]);
  for(const run of runs){assert.deepEqual(run.options,runs[0].options);assert.deepEqual(run.results.map(r=>[r.task,!!r.training_solved,r.top1_holdout,r.any_holdout]),choices,`${name} outcome changed across runs`);}
}
assert.deepEqual(reports.baseline[0].options,reports.current[0].options);
const old=new Map(reports.baseline[0].results.map(r=>[r.task,r]));
const gained=[],regressed=[];
for(const r of reports.current[0].results){const was=old.get(r.task);if(r.top1_holdout&&!was.top1_holdout)gained.push(r.task);if(was.top1_holdout&&!r.top1_holdout)regressed.push(r.task);}
const summarize=runs=>({...runs[0].summary,p50_ms:median(runs.map(r=>r.summary.p50_ms)),p95_ms:median(runs.map(r=>r.summary.p95_ms)),max_ms:Math.max(...runs.map(r=>r.summary.max_ms))});
const record={schema:1,date:new Date().toISOString(),repeats,paired_order:'alternating baseline/current then current/baseline',options:reports.current[0].options,baseline_engine_sha256:expected,current_engine_sha256:reports.current[0].engine_sha256,baseline_version:baselineVersion,current_version:currentVersion,baseline_source_commit:metadata.commit,current_source_commit:reports.current[0].environment.git_head,baseline:summarize(reports.baseline),current:summarize(reports.current),per_run:{baseline:reports.baseline.map(r=>r.summary),current:reports.current.map(r=>r.summary)},gained,regressed,notes:'Identical corrected 225-gold/250-inventory evaluator, parameters, timeout and machine. Workload/grammar/ranking changed, not just tuning a budget. Tasks have participated in development; not blind. p50/p95 are medians of per-run quantiles, max_ms is maximum across runs; not cross-tool performance claims.'};
await writeFile(resolve(root,'artifacts/comparison-results.json'),JSON.stringify(record,null,2)+'\n');
await copyFile(resolve(root,`artifacts/comparison/current-${repeats}.json`),resolve(root,'artifacts/benchmark-results.json'));
console.log(JSON.stringify(record,null,2));
