import {readFile,writeFile}from'node:fs/promises';
import assert from'node:assert/strict';
import {createHash}from'node:crypto';
import {handle}from'../dist/engine.js';
const input=JSON.parse(await readFile('artifacts/oracle-cases.json','utf8'));
const run=r=>{const out=JSON.parse(handle(JSON.stringify(r)));assert.equal(out.ok,true,out.error);return out;};
const results=[];
for(const c of input.cases){
  assert.deepEqual(run({op:'transform',table:c.training.input,pipeline:c.program}).table,c.training.output,`${c.name} reference training semantics`);
  assert.deepEqual(run({op:'transform',table:c.testing,pipeline:c.program}).table,c.answer,`${c.name} reference held-out semantics`);
  const report=run({op:'synthesize_table',examples:[c.training]});
  const predictions=report.candidates.map(p=>{try{return JSON.stringify(run({op:'transform',table:c.testing,pipeline:p.pipeline}).table)===JSON.stringify(c.answer);}catch{return false;}});
  results.push({name:c.name,training_solved:report.candidates.length>0,top1:predictions[0]??false,any:predictions.some(Boolean),truncated:report.truncated,selected:report.candidates[0]?.pipeline??null});
}
const record={date:new Date().toISOString(),engine_sha256:createHash('sha256').update(await readFile('dist/engine.js')).digest('hex'),reference:input.reference,reference_version:input.version,scope:input.scope,seed:input.seed,explicit_programs_checked:input.cases.length*2,learned_top1:results.filter(r=>r.top1).length,tasks:results.length,results};
await writeFile('artifacts/oracle-results.json',JSON.stringify(record,null,2)+'\n');
console.log(JSON.stringify({...record,results:undefined},null,2));
