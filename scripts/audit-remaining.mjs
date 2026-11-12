import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
const baseline=JSON.parse(await readFile('docs/evidence/round5-benchmark.json','utf8'));
const failures=baseline.results.filter(r=>r.holdout_available&&!r.top1_holdout);
assert.equal(failures.length,27);
const results=[];
for(const r of failures){
  const t=JSON.parse(await readFile(`fixtures/foofah/${r.task}`,'utf8'));
  const family=Number(r.task.split('_')[1]);
  const category=[27,33,40].includes(family)||family===15?'insufficient_intention_examples':[6,29].includes(family)?'training_test_layout_difference':family===34?'irregular_reference':'unseen_layout';
  const entry={task:r.task,category,training_shape:[t.InputTable.length,t.InputTable[0].length],output_shape:[t.OutputTable.length,t.OutputTable[0].length],testing_shape:[t.TestingTable.length,t.TestingTable[0].length],reference_shape:[t.TestAnswer.length,t.TestAnswer[0].length]};
  if(family===34){
    const grouped=new Map();
    for(const row of t.TestingTable){const key=JSON.stringify(row.slice(0,2));if(!grouped.has(key))grouped.set(key,row.slice(0,2));grouped.get(key).push(...row.slice(2));}
    entry.standard_group_widths=[...grouped.values()].map(r=>r.length);
    entry.reference_widths=t.TestAnswer.map(r=>r.length);
    entry.standard_first=[...grouped.values()][0];entry.reference_first=t.TestAnswer[0];
  }
  results.push(entry);
}
const counts={};for(const r of results)counts[r.category]=(counts[r.category]??0)+1;
assert.deepEqual(counts,{insufficient_intention_examples:13,training_test_layout_difference:10,irregular_reference:2,unseen_layout:2});
await mkdir('artifacts',{recursive:true});await writeFile('artifacts/remaining-27-audit.json',JSON.stringify({methodology:'Diagnostic categories for unchanged v0.11 failures, based on direct source inspection. This classification is not a corrected gold label or a proof that no arbitrary program can fit these tasks. All original tasks, scoring and references stay unchanged.',counts,results},null,2)+'\n');
console.log(JSON.stringify(counts));
