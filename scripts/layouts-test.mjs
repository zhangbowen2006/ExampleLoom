import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {handle} from '../dist/engine.js';
const request=q=>JSON.parse(handle(JSON.stringify(q)));
const run=q=>{const r=request(q);assert.equal(r.ok,true,r.error);return r;};
const parse=text=>run({op:'parse',format:'csv',text}).table;
const cli=(...args)=>execFileSync(process.execPath,['bin/exampleloom.mjs',...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
await mkdir('artifacts/layouts',{recursive:true});
const workflows=[];
for(const name of ['layout-people','layout-inventory','layout-readings']){
  const d=JSON.parse(await readFile(`examples/structures/${name}.json`,'utf8'));
  const pairs=[{input:d.input,target:d.target},...d.additional];
  const examples=pairs.map(p=>({input:parse(p.input),output:parse(p.target)}));
  const learned=run({op:'synthesize_table',examples,layouts:d.layouts});
  assert.ok(learned.candidates.length,name);
  for(const c of learned.candidates)for(const e of examples)assert.deepEqual(run({op:'transform',pipeline:c.pipeline,table:e.input}).table,e.output);
  const pipeline=run({op:'validate_pipeline',pipeline:learned.candidates[0].pipeline}).pipeline;
  assert.equal(pipeline.steps[0][0],'normalize_layouts');
  assert.deepEqual(run({op:'transform',pipeline,table:parse(d.next)}).table,d.expected,name);
  const paths=[];
  for(const [i,p] of pairs.entries()){
    await writeFile(`artifacts/layouts/${name}-${i}.csv`,p.input);
    await writeFile(`artifacts/layouts/${name}-${i}-target.csv`,p.target);
    paths.push({data:`${name}-${i}.csv`,target:`${name}-${i}-target.csv`});
  }
  const stem=`artifacts/layouts/${name}`;
  await writeFile(`${stem}-pairs.json`,JSON.stringify(paths));
  await writeFile(`${stem}-rules.json`,JSON.stringify(d.layouts));
  await writeFile(`${stem}-next.csv`,d.next);
  cli('learn-table','--pairs',`${stem}-pairs.json`,'--layouts',`${stem}-rules.json`,'--out',`${stem}-report.json`);
  cli('pipeline','--report',`${stem}-report.json`,'--choose','0','--out',`${stem}-pipeline.json`);
  cli('transform','--data',`${stem}-next.csv`,'--pipeline',`${stem}-pipeline.json`,'--out',`${stem}-result.csv`);
  assert.deepEqual(parse(await readFile(`${stem}-result.csv`,'utf8')),d.expected);
  workflows.push({name,pipeline,training_pairs:examples.length,new_batch_rows:d.expected.rows.length});
}
const d=JSON.parse(await readFile('examples/structures/layout-people.json','utf8'));
const pipeline={version:2,columns:['legacy'],steps:[['normalize_layouts',d.layouts]]};
let state=0x12001112;const rnd=n=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return state%n;};
const firsts=['Mia','博文','😀','Anne Marie','A"B'];const lasts=['Stone','王','Family Name','Q"R'];
for(let n=0;n<250;n++){
  const columns=n%2?['last','legacy','first','ignored']:['first','ignored','last','legacy'];
  const people=Array.from({length:1+rnd(20)},()=>[firsts[rnd(firsts.length)],lasts[rnd(lasts.length)],rnd(2)]);
  const rows=people.map(([first,last,legacy])=>columns.map(c=>c==='legacy'?(legacy?` ${last}, ${first} `:''):c==='first'?(!legacy?first:''):c==='last'?(!legacy?last:''):'not forwarded'));
  const table={columns,rows},snapshot=JSON.stringify(table);
  const expected={columns:['first','last'],rows:people.map(([first,last])=>[first,last])};
  assert.deepEqual(run({op:'transform',pipeline,table}).table,expected,`constructed layout ${n}`);
  assert.equal(JSON.stringify(table),snapshot);
}
for(const table of [
  {columns:['legacy','first','last'],rows:[['House,Name','Other','Family']]},
  {columns:['legacy','first','last'],rows:[['','','']]},
  {columns:['unknown'],rows:[['x']]},
])assert.equal(request({op:'transform',pipeline,table}).ok,false);
const invalid=structuredClone(pipeline);invalid.steps[0][1][1].when=['empty',['field',99]];
assert.equal(request({op:'transform',pipeline:invalid,table:{columns:['legacy'],rows:[['House,Name']]}}).ok,false,'Unavailable rules are still validated');
const huge={version:2,columns:['x'],steps:[['normalize_layouts',[{name:'large',when:['empty',['literal','']],recipe:{version:1,columns:['x'],outputs:[{name:'x',expression:['literal','x'.repeat(128)]}]}}]]]};
const overflow=request({op:'transform',pipeline:huge,table:{columns:['x'],rows:Array.from({length:20000},()=>[''])}});
assert.equal(overflow.ok,false);assert.match(overflow.error,/2000000/);
await writeFile('artifacts/layouts-results.json',JSON.stringify({timestamp:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,methodology:'250 seeded constructed cases independently expected from conceptual person records, not blind external tasks. Rules are explicitly supplied, never claimed inferred. Three complete multi-schema workflows replay every training pair and a new batch through API, serialization and CLI.',constructed_cases:250,workflows},null,2)+'\n');
console.log('250 independent constructed layout cases, three multi-schema API/CLI workflows, strict routing and output budgets passed.');
