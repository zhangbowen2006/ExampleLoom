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
await mkdir('artifacts',{recursive:true});await writeFile('artifacts/multisource-results.json',JSON.stringify({timestamp:new Date().toISOString(),engine_sha256:JSON.parse(await readFile('dist/BUILD.json','utf8')).engine_sha256,constructed_join_cases:500,methodology:'Fixed-seed constructed tables checked against a separate nested-loop reference. This is not external or blind evaluation.'},null,2)+'\n');
console.log('500 independent nested-loop join comparisons, source immutability and strict failures passed.');
