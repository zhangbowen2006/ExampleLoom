import assert from 'node:assert/strict';
import {writeFile,mkdir,readFile} from 'node:fs/promises';
import {handle} from '../dist/engine.js';
const request=q=>JSON.parse(handle(JSON.stringify(q)));
const run=q=>{const r=request(q);assert.equal(r.ok,true,r.error);return r;};
let seed=0x131122;const rnd=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
const values=['','001','A','甲😀','a|b','"x"'];
const options={left_keys:['k','part'],right_keys:['key','section'],kind:'full',relationship:'many_to_many',empty_keys:'never'};
// Deliberately slow nested-loop independent reference, not the engine hash join.
const oracle=(left,right,s)=>{
  const rows=[],matched=new Set();
  const same=(l,r)=>(s.empty_keys==='match'||[l[0],l[1],r[0],r[1]].every(v=>v!==''))&&l[0]===r[0]&&l[1]===r[1];
  for(const l of left.rows){
    const matches=[];for(const [j,r] of right.rows.entries())if(same(l,r)){matches.push(r);matched.add(j);}
    if(s.kind==='semi'||s.kind==='anti'){
      if((s.kind==='semi')===!!matches.length)rows.push([...l,matches.length?'both':'left_only']);
    }else if(matches.length)for(const r of matches)rows.push([...l,r[2],'both']);
    else if(s.kind!=='inner')rows.push([...l,'','left_only']);
  }
  if(s.kind==='full')for(const [j,r] of right.rows.entries())if(!matched.has(j))rows.push([r[0],r[1],'',r[2],'right_only']);
  return {columns:['k','part','value',...(['semi','anti'].includes(s.kind)?[]:['value_right']),'_match'],rows};
};
for(let n=0;n<500;n++){
  const table=columns=>({columns,rows:Array.from({length:rnd(12)},()=>[values[rnd(values.length)],values[rnd(values.length)],values[rnd(values.length)]])});
  const left=table(['k','part','value']),right=table(['key','section','value']);
  const spec={...options,kind:['inner','left','full','semi','anti'][n%5],empty_keys:n%2?'never':'match'};
  const snapshot=JSON.stringify([left,right,spec]);
  assert.deepEqual(run({op:'join_tables',left,right,spec}).table,oracle(left,right,spec),`constructed join ${n}`);
  assert.equal(JSON.stringify([left,right,spec]),snapshot);
}
const a={columns:['id','a'],rows:[['x','1']]},b={columns:['id','b'],rows:[['x','2'],['x','3']]};
assert.equal(request({op:'join_tables',left:a,right:b,spec:{left_keys:['id'],right_keys:['id']}}).ok,false);
assert.equal(request({op:'join_tables',left:a,right:b,spec:{left_keys:['id'],right_keys:['id'],unknown:true}}).ok,false);
assert.equal(request({op:'join_tables',left:{columns:['x'],rows:[['a'.repeat(65536)],...Array.from({length:30},()=>['b'.repeat(65536)])]},right:b,spec:{left_keys:['x'],right_keys:['id']}}).ok,false);
for(let n=0;n<250;n++){
  const sources=Array.from({length:1+rnd(5)},(_,i)=>{
    const columns=['id',...['a','b','c'].filter(()=>rnd(2))];if(rnd(2))columns.reverse();
    return {name:`source${i}`,table:{columns,rows:Array.from({length:rnd(8)},()=>columns.map(()=>values[rnd(values.length)]))}};
  });
  const spec={mode:['strict','union','intersection'][n%3],missing_value:'<absent>',source_column:'origin'};
  let columns=[...sources[0].table.columns];
  if(spec.mode==='union')columns=[...new Set(sources.flatMap(s=>s.table.columns))];
  if(spec.mode==='intersection')columns=columns.filter(c=>sources.every(s=>s.table.columns.includes(c)));
  const actual=request({op:'concat_tables',sources,spec});
  if(spec.mode==='strict'&&sources.some(s=>s.table.columns.length!==columns.length||columns.some(c=>!s.table.columns.includes(c))))assert.equal(actual.ok,false);
  else {
    assert.equal(actual.ok,true,actual.error);
    const rows=sources.flatMap(s=>s.table.rows.map(r=>[...columns.map(c=>s.table.columns.includes(c)?r[s.table.columns.indexOf(c)]:spec.missing_value),s.name]));
    assert.deepEqual(actual.table,{columns:[...columns,'origin'],rows},`constructed concat ${n}`);
  }
}
const exact={columns:['x'],rows:[...Array.from({length:30},()=>['a'.repeat(65536)]),['a'.repeat(33919)]]};
assert.equal(request({op:'join_tables',left:exact,right:{columns:['y'],rows:[]},spec:{left_keys:['x'],right_keys:['y']}}).ok,false,'Header-only second source exceeds combined input budget');
await mkdir('artifacts',{recursive:true});await writeFile('artifacts/multisource-results.json',JSON.stringify({timestamp:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,constructed_join_cases:500,constructed_concat_cases:250,methodology:'Fixed-seed constructed tables checked against separate nested-loop join and by-name alignment references. This is not external or blind evaluation.'},null,2)+'\n');
console.log('500 independent join and 250 concat comparisons, source immutability and strict failures passed.');
