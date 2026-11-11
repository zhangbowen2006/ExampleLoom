import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {handle} from '../dist/engine.js';
const corpus=JSON.parse(await readFile('artifacts/regex-extended/pcre2-cases.json','utf8'));
const field=['field',0], run=r=>JSON.parse(handle(JSON.stringify(r)));
const apply=(text,expression)=>run({op:'apply',table:{columns:['x'],rows:[[text]]},recipe:{version:1,columns:['x'],outputs:[{name:'result',expression}]}});
let comparisons=0;
for(const {pattern,text,full,matches,replacement} of corpus.cases){
  const regex='(?rx)'+pattern;
  const predicate=apply(text,['if',['matches',field,regex,false],['literal','yes'],['literal','no']]);
  assert.equal(predicate.ok,true,predicate.error);assert.equal(predicate.failures,0);
  assert.equal(predicate.rows[0].values[0],matches.length?'yes':'no',JSON.stringify({pattern,text}));comparisons++;
  const entire=apply(text,['if',['matches',field,regex,true],['literal','yes'],['literal','no']]);
  assert.equal(entire.ok,true,entire.error);assert.equal(entire.failures,0);
  assert.equal(entire.rows[0].values[0],full?'yes':'no',JSON.stringify({pattern,text}));comparisons++;
  const rewritten=apply(text,['replace',field,regex,'<$0>|<$1>|<$2>']);
  assert.equal(rewritten.ok,true,rewritten.error);assert.equal(rewritten.failures,0);
  assert.equal(rewritten.rows[0].values[0],replacement,JSON.stringify({pattern,text}));comparisons++;
  for(const occurrence of [0,-1]){
    const match=occurrence===0?matches[0]:matches.at(-1);
    for(const group of [0,1,2]){
      const result=apply(text,['capture',field,regex,group,occurrence]);
      assert.equal(result.ok,true,result.error);
      if(match?.[group]===undefined || match[group]===null)assert.equal(result.failures,1,JSON.stringify({pattern,text,group,occurrence}));
      else {assert.equal(result.failures,0);assert.equal(result.rows[0].values[0],match[group],JSON.stringify({pattern,text,group,occurrence}));}
      comparisons++;
    }
  }
}
for(const {pattern,text,full} of corpus.fold_cases){
  const result=apply(text,['if',['matches',field,'(?rx)'+pattern,true],['literal','yes'],['literal','no']]);
  assert.equal(result.ok,true,result.error);assert.equal(result.failures,0);
  assert.equal(result.rows[0].values[0],full?'yes':'no',JSON.stringify({pattern,text}));comparisons++;
}
const evidence={generated_at:new Date().toISOString(),wrapper:corpus.wrapper,pcre2:corpus.pcre2,options:corpus.options,cases:corpus.cases.length,fold_pairs:corpus.fold_cases.length,comparisons,engine_sha256:createHash('sha256').update(await readFile('dist/engine.js')).digest('hex'),methodology:'Constructed shared supported syntax, compared against PCRE2 search/full match, capture and replacement. Additional pairs are drawn from the vendored simple-fold table and independently checked against PCRE2. No claim of full compatibility or external blind evaluation.'};
await writeFile('artifacts/regex-extended/pcre2-results.json',JSON.stringify(evidence,null,2)+'\n');
console.log(`${comparisons} constructed PCRE2 comparisons passed (library ${corpus.pcre2}).`);
