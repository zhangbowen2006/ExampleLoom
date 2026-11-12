import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {handle} from '../dist/engine.js';
const call=r=>JSON.parse(handle(JSON.stringify(r)));
const input={columns:['c0'],rows:[['A']]};
const examples=[{input,output:input}];
const yes=call({op:'synthesize_table',examples,intent:'flatten_all'});
assert.equal(yes.status,'intent_checked');
assert.equal(yes.candidates[0].pipeline.steps[0][0],'flatten_rows');
assert.equal(call({op:'synthesize_table',examples}).candidates[0].pipeline.steps.length,0);
assert.equal(call({op:'synthesize_table',examples,intent:'invalid'}).ok,false);
assert.equal(call({op:'synthesize_table',examples,unknown:true}).ok,false);
const training={columns:['c0','c1'],rows:[['A','B'],['C','D']]};
const transposed={columns:['c0','c1'],rows:[['A','C'],['B','D']]};
const transpose=call({op:'synthesize_table',examples:[{input:training,output:transposed}],intent:'transpose_all'});
assert.equal(transpose.status,'intent_checked');
assert.equal(transpose.candidates[0].pipeline.steps[0][0],'transpose');
const next={columns:['c0','c1'],rows:[['X','Y'],['Z','Q'],['M','N']]};
assert.deepEqual(call({op:'transform',pipeline:transpose.candidates[0].pipeline,table:next}).table,
  {columns:['c0','c1','c2'],rows:[['X','Z','M'],['Y','Q','N']]});
assert.equal(call({op:'synthesize_table',examples:[{input:training,output:training}],intent:'transpose_all'}).status,'intent_inconsistent');
const limited=call({op:'synthesize_table',examples:[{input:training,output:transposed}],intent:'transpose_all',options:{max_depth:0}});
assert.equal(limited.truncated,true);
assert.equal(limited.candidates.length,0);
// A declared transpose does not perform the combinatorial search and can
// accept the full supported 64-column representation. Its boundary is still
// enforced and cannot be confused with the smaller automatic-search limit.
const wide={columns:Array.from({length:64},(_,i)=>`c${i}`),rows:[Array.from({length:64},(_,i)=>`v${i}`)]};
const tall={columns:['c0'],rows:wide.rows[0].map(value=>[value])};
assert.equal(call({op:'synthesize_table',examples:[{input:wide,output:tall}],intent:'transpose_all'}).status,'intent_checked');
assert.equal(call({op:'synthesize_table',examples:[{input:wide,output:tall}]}).ok,false);
const tooTall={columns:['c0'],rows:Array.from({length:65},(_,i)=>[`v${i}`])};
assert.equal(call({op:'synthesize_table',examples:[{input:tooTall,output:tooTall}],intent:'transpose_all'}).ok,false);
await mkdir('artifacts/intent',{recursive:true});
await writeFile('artifacts/intent/a.csv','c0\nA\n');
const cli=(...a)=>execFileSync(process.execPath,['bin/exampleloom.mjs',...a],{encoding:'utf8'});
const result=JSON.parse(cli('learn-table','--data','artifacts/intent/a.csv','--target','artifacts/intent/a.csv','--intent','flatten_all'));
assert.equal(result.candidates[0].pipeline.steps[0][0],'flatten_rows');
await writeFile('artifacts/intent/transpose-in.csv','c0,c1\nA,B\nC,D\n');
await writeFile('artifacts/intent/transpose-out.csv','c0,c1\nA,C\nB,D\n');
const transposeCli=JSON.parse(cli('learn-table','--data','artifacts/intent/transpose-in.csv','--target','artifacts/intent/transpose-out.csv','--intent','transpose_all'));
assert.equal(transposeCli.candidates[0].pipeline.steps[0][0],'transpose');
assert.throws(()=>cli('learn-table','--data','artifacts/intent/a.csv','--target','artifacts/intent/a.csv','--intent','unknown'));
console.log('Explicit intent API, default ambiguity, rejection and real CLI passed.');
