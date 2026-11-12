import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {handle} from '../dist/engine.js';
// A deliberately explicit, development-exposed intention manifest. These
// intentions are EXTRA human information; no score here is unassisted accuracy.
const manifest=[...[27,33,40].flatMap(f=>[1,2,4,5].map(n=>({task:`exp0_${f}_${n}.txt`,intention:'flatten_rows'}))),{task:'exp0_15_1.txt',intention:'group_c0_values_c5'}];
const run=q=>{const r=JSON.parse(handle(JSON.stringify(q)));assert.equal(r.ok,true,r.error);return r;};
const table=rows=>({columns:Array.from({length:rows[0].length},(_,i)=>`c${i}`),rows});
const reference=(input,intention)=>{
  if(intention==='flatten_rows')return table([input.rows.flat()]);
  const grouped=new Map();for(const row of input.rows){if(!grouped.has(row[0]))grouped.set(row[0],[row[0]]);grouped.get(row[0]).push(row[5]);}
  const rows=[...grouped.values()];assert.ok(rows.every(r=>r.length===rows[0].length));return table(rows);
};
const results=[];
for(const entry of manifest){
  const raw=JSON.parse(await readFile(`fixtures/foofah/${entry.task}`,'utf8'));
  const examples=[{input:table(raw.InputTable),output:table(raw.OutputTable)}];
  let learned=run({op:'synthesize_table',examples}),queries=[];
  for(let i=0;i<3&&examples.length<8&&learned.candidates.length;i++){
    const proposed=run({op:'propose_table_input',pipelines:learned.candidates.map(c=>c.pipeline),inputs:examples.map(e=>e.input)});
    if(!proposed.suggestion)break;
    let input=proposed.suggestion.input,output=reference(input,entry.intention),mutation=proposed.suggestion.mutation,source_index=proposed.suggestion.source_index;
    if(input.rows.length>128||output.columns.length>32){
      // User may reject an over-wide proposal. Use a small source-only batch
      // with a different record count; this is explicit extra assistance.
      const source=examples[0].input;
      const count=source.rows.length===3?2:3;
      input={columns:source.columns,rows:Array.from({length:count},(_,j)=>source.rows[j%source.rows.length])};
      output=reference(input,entry.intention);mutation='user_short_batch_from_known_rows';source_index=0;
    }
    if(examples.some(e=>JSON.stringify(e.input)===JSON.stringify(input)))break;
    queries.push({input,output,source_index,mutation,label_source:'Independent JS reference implementing the declared extra intention; never TestAnswer or engine predictions'});
    examples.push({input,output});learned=run({op:'synthesize_table',examples});
  }
  // Freeze top1 BEFORE TestAnswer is accessed for evaluation. No gold selection.
  const pipeline=learned.candidates[0]?.pipeline??null;
  const actual=pipeline?run({op:'transform',pipeline,table:table(raw.TestingTable)}).table:null;
  const passed=JSON.stringify(actual)===JSON.stringify(table(raw.TestAnswer));
  for(const c of learned.candidates)for(const e of examples)assert.deepEqual(run({op:'transform',pipeline:c.pipeline,table:e.input}).table,e.output);
  results.push({...entry,extra_queries:queries,training_pairs:examples.length,top1_pipeline:pipeline,top1_holdout:passed});
}
await mkdir('artifacts',{recursive:true});
const summary={tasks:results.length,assisted_top1:results.filter(r=>r.top1_holdout).length,extra_pairs:results.reduce((n,r)=>n+r.extra_queries.length,0)};
await writeFile('artifacts/assisted-diagnostic.json',JSON.stringify({timestamp:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,methodology:'Separate assisted diagnostic on a development-exposed, explicitly selected 13-task ambiguity subset. Extra intentions are prescribed in this script, not inferred. Up to three source-only input probes are labelled by independent JS references. Gold is only scored after top1 is frozen. Do not add this score to the unassisted 198/225, and do not describe this as independent human field validation.',summary,results},null,2)+'\n');
console.log(JSON.stringify(summary));
