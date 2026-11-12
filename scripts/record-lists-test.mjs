import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {handle} from '../dist/engine.js';
const run=r=>{const x=JSON.parse(handle(JSON.stringify(r)));assert.equal(x.ok,true,x.error);return x;};
let state=0x1126abc;
const rnd=n=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return state%n;};
const values=['','a,b','"quoted"','line\nnext','甲😀',';|[]','007'];
const pipeline={version:2,columns:['key','value'],steps:[['pivot_record_lists','key','value','name']]};
for(let i=0;i<250;i++){
 const records=Array.from({length:1+rnd(4)},(_,j)=>[['name',`r${i}-${j}`],...Array.from({length:rnd(10)},()=>[`field${rnd(4)}`,values[rnd(values.length)]])]);
 const labels=[...new Set(records.flat().map(([key])=>key))];
 const expected={columns:labels.map((_,j)=>`c${j}`),rows:[labels,...records.map(record=>labels.map(key=>JSON.stringify(record.filter(([k])=>k===key).map(([,v])=>v))))]};
 const table={columns:['key','value'],rows:records.flat()};
 assert.deepEqual(run({op:'transform',table,pipeline}).table,expected,`constructed list case ${i}`);
}
await mkdir('artifacts/record-lists',{recursive:true});
const demo=JSON.parse(await readFile('examples/structures/record-lists.json','utf8'));
const parse=text=>run({op:'parse',format:'csv',text}).table;
assert.deepEqual(run({op:'transform',table:parse(demo.next),pipeline:demo.pipeline}).table,demo.expected);
await writeFile('artifacts/record-lists/input.csv',demo.next);
await writeFile('artifacts/record-lists/pipeline.json',JSON.stringify(demo.pipeline));
execFileSync(process.execPath,['bin/exampleloom.mjs','transform','--data','artifacts/record-lists/input.csv','--pipeline','artifacts/record-lists/pipeline.json','--out','artifacts/record-lists/result.csv'],{stdio:'pipe'});
assert.deepEqual(parse(await readFile('artifacts/record-lists/result.csv','utf8')),demo.expected);
console.log('250 constructed multivalue record cases, explicit example and real CLI passed.');
