import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {handle} from '../dist/engine.js';
const call = request => {const result=JSON.parse(handle(JSON.stringify(request)));assert.equal(result.ok,true,result.error);return result;};
const parse = text => call({op:'parse',format:'csv',text}).table;
const oracle = JSON.parse(await readFile('artifacts/sort-oracle.json','utf8'));
for(const task of oracle.cases){
  const pipeline={version:2,columns:task.table.columns,steps:[['sort_rows',task.keys]]};
  assert.deepEqual(call({op:'transform',pipeline,table:task.table}).table,task.expected,task.name);
}
const scenarios=[];
for(const name of ['sorted-invoices','sorted-catalog','sorted-measurements']){
  const demo=JSON.parse(await readFile(`examples/structures/${name}.json`,'utf8'));
  const examples=[{input:parse(demo.input),output:parse(demo.target)},...(demo.additional??[]).map(pair=>({input:parse(pair.input),output:parse(pair.target)}))];
  const report=call({op:'synthesize_table',examples});
  assert.ok(report.candidates.length>0,name);
  const pipeline=call({op:'validate_pipeline',pipeline:report.candidates[0].pipeline}).pipeline;
  assert.ok(pipeline.steps.some(step=>step[0]==='sort_rows'),name);
  const result=call({op:'transform',pipeline,table:parse(demo.next)});
  assert.deepEqual(result.table,demo.expected,name);
  assert.equal(result.csv,demo.expected_csv,name+' spreadsheet-safe CSV');
  await mkdir('artifacts/sorting',{recursive:true});
  await writeFile(`artifacts/sorting/${name}.csv`,result.csv);
  scenarios.push({name,pipeline,training_pairs:examples.length,heldout_rows:demo.expected.rows.length,all_cells_match:true});
}
const evidence={date:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,reference:oracle.reference,reference_python:oracle.python,scope:oracle.scope,explicit_reference_cases:oracle.cases.length,scenarios};
await writeFile('artifacts/sorting-results.json',JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify({reference_cases:oracle.cases.length,scenarios},null,2));
