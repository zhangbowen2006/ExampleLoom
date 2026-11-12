import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {handle} from '../dist/engine.js';
const run=r=>{const out=JSON.parse(handle(JSON.stringify(r)));assert.equal(out.ok,true,out.error);return out;};
const parse=text=>run({op:'parse',format:'csv',text}).table;
const evidence={date:new Date().toISOString(),scenarios:[],checks:[]};
await mkdir('artifacts/advanced',{recursive:true});
for(const name of ['conditional','regex','rewrite','initials','normalize','atomic-regex']){
  const scenario=JSON.parse(await readFile(`examples/${name}/scenario.json`,'utf8'));
  const table=parse(await readFile(`examples/${name}/input.csv`,'utf8'));
  const field=scenario.fields[0];
  const report=run({op:'synthesize',patterns:scenario.patterns??[],examples:field.labels.map(e=>({input:table.rows[e.row],output:e.output})),rows:table.rows});
  assert.ok(report.candidates.length>0,name);
  if(name==='rewrite')assert.equal(report.candidates[0].expression[0],'replace');
  if(name==='regex')assert.equal(report.candidates[0].expression[0],'capture','Regex scenario must actually learn regex semantics');
  if(name==='atomic-regex')assert.equal(report.candidates[0].expression[0],'capture','Possessive regex scenario must actually learn regex semantics');
  const recipe={version:1,columns:table.columns,outputs:[{name:field.name,expression:report.candidates[0].expression}]};
  const applied=run({op:'apply',table,recipe});
  assert.equal(applied.failures,0);
  assert.deepEqual(applied.rows.map(r=>r.values[0]),field.expected,name);
  evidence.scenarios.push({name,selected:report.candidates[0].description,training:field.labels.length,heldout:table.rows.length-field.labels.length,all_values_match:true});
}
for(const name of ['unpivot','records','melt','dynamic-pivot','header-details','labelled-grid','mixed-tags','regional-totals','record-grid','variable-records','context-metrics','labelled-contacts','key-value-records','flatten-batch','sparse-names','flatten-intent','optional-parts']){
  const demo=JSON.parse(await readFile(`examples/structures/${name}.json`,'utf8'));
  const input=parse(demo.input), output=parse(demo.target);
  const extra=(demo.additional??[]).map(pair=>({input:parse(pair.input),output:parse(pair.target)}));
  const report=run({op:'synthesize_table',examples:[{input,output},...extra],intent:demo.intent??'infer'});
  assert.ok(report.candidates.length>0,name);
  const pipeline=report.candidates[0].pipeline;
  if(name==='key-value-records')assert.equal(pipeline.steps[0][0],'pivot_records');
  assert.deepEqual(run({op:'transform',pipeline,table:input}).table,output,`${name} training`);
  for (const pair of extra) assert.deepEqual(run({op:'transform',pipeline,table:pair.input}).table,pair.output);
  const actual=run({op:'transform',pipeline,table:parse(demo.next)});
  assert.deepEqual(actual.table,demo.expected,`${name} unseen table`);
  await writeFile(`artifacts/advanced/${name}.pipeline.json`,JSON.stringify(pipeline,null,2));
  await writeFile(`artifacts/advanced/${name}.csv`,actual.csv);
  evidence.scenarios.push({name,selected:pipeline.steps,heldout_rows:actual.table.rows.length,all_values_match:true});
}
// Run the real CLI with explicit candidate selection, using generated files.
const demo=JSON.parse(await readFile('examples/structures/unpivot.json','utf8'));
for(const [name,text]of Object.entries({input:demo.input,target:demo.target,next:demo.next}))await writeFile(`artifacts/advanced/${name}.csv`,text);
const cli=(...args)=>execFileSync(process.execPath,['bin/exampleloom.mjs',...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
const preserve=JSON.parse(await readFile('examples/structures/preserve-columns.json','utf8'));
assert.deepEqual(run({op:'transform',pipeline:preserve.pipeline,table:parse(preserve.next)}).table,preserve.expected);
await writeFile('artifacts/advanced/preserve-input.csv',preserve.next);
await writeFile('artifacts/advanced/preserve.pipeline.json',JSON.stringify(preserve.pipeline));
cli('transform','--data','artifacts/advanced/preserve-input.csv','--pipeline','artifacts/advanced/preserve.pipeline.json','--out','artifacts/advanced/preserve-result.csv');
assert.deepEqual(parse(await readFile('artifacts/advanced/preserve-result.csv','utf8')),preserve.expected);
evidence.checks.push('Opt-in extra input columns survive explicit recipe and real CLI CSV export');
cli('learn-table','--data','artifacts/advanced/input.csv','--target','artifacts/advanced/target.csv','--out','artifacts/advanced/report.json');
cli('pipeline','--report','artifacts/advanced/report.json','--choose','0','--out','artifacts/advanced/selected.json');
cli('transform','--data','artifacts/advanced/next.csv','--pipeline','artifacts/advanced/selected.json','--out','artifacts/advanced/result.csv');
assert.deepEqual(parse(await readFile('artifacts/advanced/result.csv','utf8')),demo.expected);
evidence.checks.push('CLI learn-table → explicit pipeline selection → transform CSV → independent expected rows');
// Differential regex checks use JS only as an oracle for shared syntax. The
// implementation still executes entirely in MoonBit, across all backends.
const cases=[['([[:digit:]]+)','([0-9]+)'],['([[:alpha:]]+)','([A-Za-z]+)'],['(a|bc)+','(a|bc)+'],['([A-Z]{2,4})','([A-Z]{2,4})'],['(a+?)','(a+?)'],['^(.+)$','^(.+)$'],['(甲|😀)+','(甲|😀)+'],['',''],['[^,]+','[^,]+'],['([[:space:]]+)','([\\t\\n\\r\\f\\v ]+)']];
const texts=['','a','aaabc','xx12-003y','ABBCDE','甲😀乙','x\ny','one,,two','a12 b34 c56','  \t '];
let comparisons=0;
for(const [moon,js]of cases)for(const text of texts)for(const occurrence of [0,-1]){
  const expected=[...text.matchAll(new RegExp(js,'gsu'))];
  const wanted=expected.length?(occurrence===0?expected[0][0]:expected.at(-1)[0]):null;
  const r=run({op:'apply',recipe:{version:1,columns:['x'],outputs:[{name:'capture',expression:['capture',['field',0],moon,0,occurrence]}]},table:{columns:['x'],rows:[[text]]}});
  if(wanted===null)assert.equal(r.failures,1,`${moon}/${JSON.stringify(text)}`);
  else{assert.equal(r.failures,0);assert.equal(r.rows[0].values[0],wanted,`${moon}/${JSON.stringify(text)}`);}
  comparisons++;
}
evidence.checks.push(`${comparisons} regex captures checked against JavaScript shared-syntax oracle, including Unicode/empty matches and no-match failures`);
let predicatesAndRewrites = 0;
for (const [moon, js] of cases) {
  for (const text of [...texts, 'a\n']) {
    const yes = ['literal','yes'], no = ['literal','no'], field = ['field',0];
    const recipe = {version:1,columns:['x'],outputs:[
      {name:'full',expression:['if',['matches',field,moon,true],yes,no]},
      {name:'search',expression:['if',['matches',field,moon,false],yes,no]},
      {name:'rewrite',expression:['replace',field,moon,'<$0>|$1|$$']},
    ]};
    // The final negative assertion forces the actual end including a trailing newline.
    const full = new RegExp('^(?:'+js+')(?![\\s\\S])','su').test(text);
    const search = new RegExp(js,'su').test(text);
    const replacement = text.replace(new RegExp(js,'gsu'),(...args) =>
      '<'+args[0]+'>|'+(args.length>3 ? args[1]??'' : '')+'|$');
    const actual = run({op:'apply',recipe,table:{columns:['x'],rows:[[text]]}});
    assert.equal(actual.failures,0);
    assert.deepEqual(actual.rows[0].values,[full?'yes':'no',search?'yes':'no',replacement],
      'Shared regex semantics: '+moon+' / '+JSON.stringify(text));
    predicatesAndRewrites += 3;
  }
}
evidence.checks.push(`${predicatesAndRewrites} full-match, substring-match and global group replacement results checked against JavaScript on the common dialect`);
await writeFile('artifacts/advanced-results.json',JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence,null,2));
