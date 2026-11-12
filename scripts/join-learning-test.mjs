import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {handle} from '../dist/engine.js';
const call=q=>JSON.parse(handle(JSON.stringify(q)));
const run=q=>{const r=call(q);assert.equal(r.ok,true,r.error);return r;};
const parse=text=>run({op:'parse',format:'csv',text}).table;
const cli=(...args)=>{const r=spawnSync(process.execPath,['bin/exampleloom.mjs',...args],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout;};
await mkdir('artifacts/join-learning',{recursive:true});const workflows=[];
for(const name of ['warehouse','settlement']){
 const d=JSON.parse(await readFile(`examples/join-learning/${name}.json`,'utf8'));
 const examples=d.examples.map(e=>({sources:e.sources.map(s=>({name:s.name,table:parse(s.csv)})),output:parse(e.output)}));
 const before=JSON.stringify(examples);const report=run({op:'synthesize_join_jobs',examples});assert.ok(report.candidates.length,name);
 assert.equal(JSON.stringify(examples),before,'learning must not mutate examples');
 for(const candidate of report.candidates)for(const e of examples)assert.deepEqual(run({op:'run_data_job',job:candidate.job,sources:e.sources}).table,e.output);
 const sources=d.next.map(s=>({name:s.name,table:parse(s.csv)}));
 const chosen=run({op:'validate_data_job',job:report.candidates[0].job}).job;
 assert.deepEqual(run({op:'run_data_job',job:chosen,sources}).table,d.expected,`${name} unseen batch`);
 const pairs=[];
 for(const [i,e] of d.examples.entries()){
  const bindings=[];for(const s of e.sources){const file=`${name}-${i}-${s.name}.csv`;await writeFile(`artifacts/join-learning/${file}`,s.csv);bindings.push({name:s.name,file});}
  const target=`${name}-${i}-target.csv`;await writeFile(`artifacts/join-learning/${target}`,e.output);pairs.push({sources:bindings,target});
 }
 await writeFile(`artifacts/join-learning/${name}-pairs.json`,JSON.stringify(pairs));
 const next=[];for(const s of d.next){const file=`${name}-next-${s.name}.csv`;await writeFile(`artifacts/join-learning/${file}`,s.csv);next.push({name:s.name,file});}
 await writeFile(`artifacts/join-learning/${name}-next.json`,JSON.stringify(next));
 cli('learn-join','--pairs',`artifacts/join-learning/${name}-pairs.json`,'--out',`artifacts/join-learning/${name}-report.json`);
 cli('job','--report',`artifacts/join-learning/${name}-report.json`,'--choose','0','--out',`artifacts/join-learning/${name}-job.json`);
 cli('run-job','--job',`artifacts/join-learning/${name}-job.json`,'--sources',`artifacts/join-learning/${name}-next.json`,'--out',`artifacts/join-learning/${name}-output.csv`);
 assert.deepEqual(parse(await readFile(`artifacts/join-learning/${name}-output.csv`,'utf8')),d.expected);
 workflows.push({name,examples:examples.length,candidates:report.candidates.length,evaluations:report.evaluations,status:report.status,top1_new_batch:true});
 const cut=run({op:'synthesize_join_jobs',examples,options:{max_evaluations:1,max_candidates:1,max_keys:1}});assert.equal(cut.evaluations,1);assert.equal(cut.truncated,true);
 assert.equal(call({op:'synthesize_join_jobs',examples,unknown:true}).ok,false);
 assert.equal(call({op:'synthesize_join_jobs',examples,options:{max_keys:3}}).ok,false);
 const bad=structuredClone(examples);bad[1].sources[0].table.rows[0][0]='x'.repeat(1025);
 assert.match(call({op:'synthesize_join_jobs',examples:bad}).error,/1024/);
}
const e={sources:[{name:'a',table:{columns:['id'],rows:[['1']]}},{name:'b',table:{columns:['id','value'],rows:[['1','x']]}}],output:{columns:['value'],rows:[['x']]}};
const ambiguous=run({op:'synthesize_join_jobs',examples:[e]});
assert.ok(ambiguous.candidates.length>1,'Under-specified examples must retain different plausible jobs');
const contradicted=structuredClone(e);contradicted.output.rows[0][0]='not-in-any-input';
assert.equal(run({op:'synthesize_join_jobs',examples:[e,contradicted]}).candidates.length,0);
await writeFile('artifacts/join-learning-results.json',JSON.stringify({timestamp:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,workflows,methodology:'Two constructed multi-batch examples; all candidate jobs replay training, and separately specified next batches test generalization. These demonstrations are not external or blind benchmarks.'},null,2)+'\n');
console.log(JSON.stringify({workflows,additional:['ambiguity retained','contradictions produce no job','limits and invalid requests rejected','real CLI save and replay']}));
