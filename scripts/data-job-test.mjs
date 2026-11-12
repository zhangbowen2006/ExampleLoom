import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile,readdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {handle} from '../dist/engine.js';
const call=q=>JSON.parse(handle(JSON.stringify(q)));
const run=q=>{const r=call(q);assert.equal(r.ok,true,r.error);return r;};
const parse=text=>run({op:'parse',format:'csv',text}).table;
const cli=(...args)=>{const r=spawnSync(process.execPath,['bin/exampleloom.mjs',...args],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r;};
await mkdir('artifacts/jobs',{recursive:true});const results=[];
for(const name of ['product-enrichment','monthly-settlement','catalogue-reconcile']){
 const d=JSON.parse(await readFile(`examples/jobs/${name}.json`,'utf8'));
 const job=run({op:'validate_data_job',job:d.job}).job,sources=d.sources.map(s=>({name:s.name,table:parse(s.csv)}));
 const snapshot=JSON.stringify(sources);
 assert.deepEqual(run({op:'run_data_job',job,sources}).table,d.expected,name);
 assert.equal(JSON.stringify(sources),snapshot);
 const reordered=sources.toReversed().map(s=>({name:s.name,table:{columns:s.table.columns.toReversed(),rows:s.table.rows.map(r=>r.toReversed())}}));
 assert.deepEqual(run({op:'run_data_job',job,sources:reordered}).table,d.expected,'source binding and column name order independence');
 await writeFile(`artifacts/jobs/${name}.json`,JSON.stringify(job));const files=[];
 for(const s of d.sources){const file=`${name}-${s.name}.csv`;await writeFile(`artifacts/jobs/${file}`,s.csv);files.push({name:s.name,file});}
 await writeFile(`artifacts/jobs/${name}-files.json`,JSON.stringify(files));
 cli('validate-job','--job',`artifacts/jobs/${name}.json`,'--out',`artifacts/jobs/${name}-saved.json`);
 cli('run-job','--job',`artifacts/jobs/${name}-saved.json`,'--sources',`artifacts/jobs/${name}-files.json`,'--out',`artifacts/jobs/${name}-result.csv`);
 assert.deepEqual(parse(await readFile(`artifacts/jobs/${name}-result.csv`,'utf8')),d.expected);
 results.push({name,stages:job.stages.length,rows:d.expected.rows.length,api:true,real_cli:true,reordered_sources:true});
 const forward=structuredClone(job);forward.stages[0].left='future';if(forward.stages[0].kind==='join')assert.equal(call({op:'validate_data_job',job:forward}).ok,false);
 assert.equal(call({op:'run_data_job',job,sources:sources.slice(1)}).ok,false);
 const invalid=structuredClone(job);invalid.stages.at(-1).hidden='ignored';assert.equal(call({op:'validate_data_job',job:invalid}).ok,false);
}
await mkdir('artifacts/jobs/occupied-output',{recursive:true});
await writeFile('artifacts/jobs/occupied-output/sentinel','keep');
const failedWrite=spawnSync(process.execPath,['bin/exampleloom.mjs','run-job','--job','artifacts/jobs/product-enrichment-saved.json','--sources','artifacts/jobs/product-enrichment-files.json','--out','artifacts/jobs/occupied-output'],{encoding:'utf8'});
assert.notEqual(failedWrite.status,0);assert.equal(await readFile('artifacts/jobs/occupied-output/sentinel','utf8'),'keep');
assert.equal((await readdir('artifacts/jobs')).some(n=>n.startsWith('.occupied-output.')&&n.endsWith('.tmp')),false,'Owned temporary files are removed after rename failure');
await writeFile('artifacts/data-job-results.json',JSON.stringify({timestamp:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,results,methodology:'Three complete constructed multi-source workflows, explicit specifications rather than learned joins. No external adoption or blind-evaluation claim.'},null,2)+'\n');
console.log('Three complete saved multi-source jobs passed API, column/source reordering and real CLI replay.');
