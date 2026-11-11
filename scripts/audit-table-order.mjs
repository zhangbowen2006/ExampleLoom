// Descriptive error analysis only. TestAnswer is read after a stored top-1
// pipeline has been selected; it is never passed to synthesis or ranking.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {handle} from '../dist/engine.js';
const results=JSON.parse(await readFile(process.env.TABLE_BENCHMARK??'artifacts/benchmark-results.json','utf8'));
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const rowsEqualAsMultisets=(a,b)=>a.length===b.length && a.every((row,i)=>same([...row].sort(),[...b[i]].sort()));
const suspicious=[];
for(const result of results.results){
  if(!result.holdout_available || result.top1_holdout || !result.top1_pipeline)continue;
  const task=JSON.parse(await readFile(`fixtures/foofah/${result.task}`,'utf8'));
  const width=task.TestingTable[0].length;
  const table={columns:Array.from({length:width},(_,i)=>`c${i}`),rows:task.TestingTable};
  const actual=JSON.parse(handle(JSON.stringify({op:'transform',table,pipeline:result.top1_pipeline})));
  if(actual.ok && actual.table.rows.length===task.TestAnswer.length &&
    rowsEqualAsMultisets(actual.table.rows,task.TestAnswer) &&
    !same(actual.table.rows,task.TestAnswer)){
    suspicious.push({task:result.task,family:result.family,rows:actual.table.rows.length,description:'Every predicted row has the same cell multiset as its corresponding reference row, but at least one cell position differs.'});
  }
}
const record={engine_sha256:results.engine_sha256,methodology:'Post-hoc order-only diagnosis using held-out reference; no ground truth enters training or ranking. Equality of row multisets does not prove reference error or establish an intended order.',failures:results.summary.holdout_available-results.summary.top1_holdout,order_only_count:suspicious.length,tasks:suspicious};
await mkdir('artifacts/table-order-audit',{recursive:true});
await writeFile('artifacts/table-order-audit/results.json',JSON.stringify(record,null,2)+'\n');
console.log(`${suspicious.length} top-1 failures have matching row cell multisets but different cell order.`);
