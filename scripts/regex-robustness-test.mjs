import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {handle} from '../dist/engine.js';
// Constructed boundary inputs; not an external task set or a fuzzer guarantee.
let seed=72613;
const pick=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
const pieces=['a','b','(',')','[',']','*','+','?','|','\\d','(?=a)','(?<=a)','.','{2}','\\','(?i:','\\p{L}'];
let accepted=0,rejected=0;
for(let i=0;i<500;i++){
  let pattern='(?rx)';
  for(let j=0,n=3+pick(6);j<n;j++)pattern+=pieces[pick(pieces.length)];
  const result=JSON.parse(handle(JSON.stringify({op:'apply',table:{columns:['x'],rows:[['aaabb 17'],['abc😀']]},recipe:{version:1,columns:['x'],outputs:[{name:'v',expression:['capture',['field',0],pattern,0,0]}]}})));
  assert.equal(typeof result.ok,'boolean');
  if(result.ok)accepted++;else rejected++;
}
// Grammar can legitimately expand over time; verify both paths ran and
// every generated request returned a structured result without a host panic.
assert.equal(accepted+rejected,500);assert.ok(accepted>0&&rejected>0);
await mkdir('artifacts/regex-extended',{recursive:true});
await writeFile('artifacts/regex-extended/robustness.json',JSON.stringify({constructed_patterns:500,accepted,rejected,host_panics:0,seed:72613},null,2)+'\n');
console.log('500 constructed regex boundary cases passed without a host panic.');
