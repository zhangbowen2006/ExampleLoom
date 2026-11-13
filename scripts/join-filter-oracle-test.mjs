import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {handle} from '../dist/engine.js';

const request=q=>JSON.parse(handle(JSON.stringify(q)));
const run=q=>{const r=request(q);assert.equal(r.ok,true,r.error);return r;};
const parse=text=>run({op:'parse',format:'csv',text}).table;
const demo=JSON.parse(await readFile('examples/join-learning/paid-orders.json','utf8'));
const examples=demo.examples.map(e=>({
  sources:e.sources.map(s=>({name:s.name,table:parse(s.csv)})),output:parse(e.output),
}));
const report=run({op:'synthesize_join_jobs',examples});
assert.ok(report.candidates.length>0);
const job=report.candidates[0].job;
assert.deepEqual(job.stages[1].pipeline.steps.map(s=>s[0]),['filter','aggregate']);
for(const candidate of report.candidates)for(const example of examples)
  assert.deepEqual(run({op:'run_data_job',job:candidate.job,sources:example.sources}).table,example.output);
const oracle=JSON.parse(await readFile('artifacts/join-filter-oracle.json','utf8'));
for(const [index,fixture] of oracle.cases.entries()){
  const snapshot=JSON.stringify(fixture.sources);
  assert.deepEqual(run({op:'run_data_job',job,sources:fixture.sources}).table,fixture.expected,`SQLite case ${index}`);
  assert.equal(JSON.stringify(fixture.sources),snapshot,'execution must not mutate input');
}
const bad=structuredClone(oracle.cases[1].sources);
bad[0].table.rows=[['not-an-integer','sku-1-0','paid']];
const failure=request({op:'run_data_job',job,sources:bad});
assert.equal(failure.ok,false,'A paid row with invalid amount must fail, not silently export');
const decimalExamples=structuredClone(examples);
for(const example of decimalExamples){
  const orders=example.sources.find(s=>s.name==='orders').table;
  const index=orders.columns.indexOf('amount');
  for(const row of orders.rows){const cents=Number(row[index]);row[index]=`${Math.trunc(cents/100)}.${String(cents%100).padStart(2,'0')}`;}
}
decimalExamples[0].output={columns:['category','total'],rows:[['food','3'],['book','1.25']]};
decimalExamples[1].output={columns:['category','total'],rows:[['tool','0.8'],['art','0.13']]};
const decimals=run({op:'synthesize_join_jobs',examples:decimalExamples});
assert.ok(decimals.candidates.length>0);
assert.match(JSON.stringify(decimals.candidates[0].job),/sum_decimal/);
const decimalNext=[
 {name:'orders',table:parse('sku,status,amount\nE,paid,0.1\nE,pending,invalid\nE,paid,0.2\nF,paid,123456789012345678901234567890.01\nF,canceled,invalid\n')},
 {name:'catalog',table:parse('sku,category\nE,toy\nF,media\n')},
];
assert.deepEqual(run({op:'run_data_job',job:decimals.candidates[0].job,sources:decimalNext}).table,
 {columns:['category','total'],rows:[['toy','0.3'],['media','123456789012345678901234567890.01']]});
const evidence={timestamp:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,
  sqlite_version:oracle.sqlite_version,cases:oracle.cases.length,
  all_passed:true,training_examples:examples.length,filter_evaluations:report.filter_evaluations,
  additional_checks:['A paid row with invalid amount fails without partial output.','A separately learned filter plus sum_decimal produces 0.3 for 0.1 + 0.2 and preserves a value beyond Int64.'],
  methodology:'One job learned from two constructed examples; 40 separately generated constructed batches checked against a SQLite inner join, exact status predicate and integer SUM. Includes empty inputs, missing keys, filtered invalid numbers, negative values and reordered source columns. Not a blind benchmark, large-scale performance test or production dataset.'};
await writeFile('artifacts/join-filter-oracle-results.json',JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence));
