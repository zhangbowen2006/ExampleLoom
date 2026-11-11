// Independent ECMAScript oracle only for the stated common syntax.
// Runtime execution below calls the MoonBit engine; Node is never a regex host.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {handle} from '../dist/engine.js';
const request=r=>JSON.parse(handle(JSON.stringify(r)));
const run=r=>{const x=request(r);assert.equal(x.ok,true,x.error);return x;};
const field=['field',0], literal=s=>['literal',s];
const apply=(text,expressions)=>run({op:'apply',table:{columns:['x'],rows:[[text]]},recipe:{version:1,columns:['x'],outputs:expressions.map((expression,i)=>({name:`v${i}`,expression}))}});
const textCases=['','a','aaab','abc abc','abc xyz','ababc','aba','ID12 USD34 ID56','id=42; x=9','a1 b2 a3','one,,two','x\ny','甲😀乙','甲1 😀2 甲3',' A\t7\n','AB-0042','a-b-c','<a><bc>','aaa aaa'];
const patterns=['','a|bc','(a|aa)+','a+?','[A-Z]{2,4}','\\d+','\\w+','\\W+','\\s+','\\S+','[\\dA-F]+','(\\w+) \\1','(?<x>\\w+) \\k<x>','(a*)\\1','(x)?y','a(?=b)','a(?!b)','(?<=ID)\\d+','(?<!a)\\d','(?<=甲|😀)\\d','(?=(\\d+);)\\d+','(?=.)','(?<=.)','\\b\\w+\\b','\\p{L}+','\\P{L}+','<(.+?)>','(?<word>[a-z]+)','(?:a|ab)*c','(a)?b\\1'];
patterns.push('(a|(b))*','(a(b)?)+','\\x41+','[\\x41-\\x61]','(?<a>a)(?<b>b)','\\u0041+');
const evidence={created_at:new Date().toISOString(),engine_sha256:createHash('sha256').update(await readFile('dist/engine.js')).digest('hex'),methodology:'Constructed differential cases against Node RegExp with Unicode scalar iteration, strict full-string end; not external or blind tasks and not PCRE/ECMAScript full conformance.',comparisons:0,scenarios:[]};
for(const flags of ['', 'i','s','m'])for(const source of patterns){
  // Case-insensitive backreferences are an explicit unsupported combination.
  if(flags==='i' && /\\(?:[1-9]|k<)/.test(source))continue;
  const pattern='(?rx)'+(flags?`(?${flags}:${source})`:source);
  for(const text of textCases){
    const oracle=[...text.matchAll(new RegExp(source,flags+'gu'))];
    const entire=new RegExp(`(?<![\\s\\S])(?:${source})(?![\\s\\S])`,flags+'u').exec(text);
    const full=entire?.index===0 && entire[0].length===text.length;
    const result=apply(text,[['if',['matches',field,pattern,false],literal('yes'),literal('no')],['if',['matches',field,pattern,true],literal('yes'),literal('no')],['replace',field,pattern,'<$0>|$1|$$']]);
    assert.equal(result.failures,0,JSON.stringify({source,flags,text,result}));
    assert.deepEqual(result.rows[0].values,[oracle.length?'yes':'no',full?'yes':'no',text.replace(new RegExp(source,flags+'gu'),(...args)=>{const named=typeof args.at(-1)==='object';const captures=args.slice(1,named?-3:-2);return `<${args[0]}>|${captures[0]??''}|$`;})],JSON.stringify({source,flags,text}));
    evidence.comparisons+=3;
    for(const occurrence of [0,-1]){
      const expected=occurrence===0?oracle[0]:oracle.at(-1);
      for(const group of [0,1,2]){
        const value=apply(text,[['capture',field,pattern,group,occurrence]]);
        if(expected?.[group]===undefined) assert.equal(value.failures,1,JSON.stringify({source,flags,text,group,occurrence}));
        else {assert.equal(value.failures,0);assert.equal(value.rows[0].values[0],expected[group],JSON.stringify({source,flags,text,group,occurrence}));}
        evidence.comparisons++;
      }
    }
  }
}
for(const name of ['conditional-regex','learned-assertions','wide-table-regex']){
  const scenario=JSON.parse(await readFile(`examples/regex-extended/${name}.json`,'utf8'));
  if(scenario.op==='synthesize'){
    const learned=run({op:'synthesize',examples:scenario.examples,patterns:scenario.patterns,rows:scenario.unseen.map(x=>x.input)});
    const candidate=learned.candidates.find(c=>c.expression[0]==='capture'&&c.expression[2].startsWith('(?rx)'));
    assert.ok(candidate,'Must actually learn the extended regex operation');
    for(const row of scenario.unseen){assert.deepEqual(apply(row.input[0],[candidate.expression]).rows[0].values,[row.output]);}
    evidence.scenarios.push({name,training:scenario.examples.length,heldout:scenario.unseen.length,expression:candidate.expression});
  }else if(scenario.op==='apply'){
    const response=run({op:'apply',table:scenario.table,recipe:scenario.recipe});
    assert.equal(response.failures,0);assert.deepEqual(response.rows.map(x=>x.values),scenario.expected);
    evidence.scenarios.push({name,rows:response.rows.length,recipe_roundtrip:true});
  }else{
    const response=run({op:'transform',table:scenario.table,pipeline:scenario.pipeline});
    assert.deepEqual(response.table,scenario.expected);
    // Name binding must survive a different source column order.
    const swapped={columns:[...scenario.table.columns].reverse(),rows:scenario.table.rows.map(r=>[...r].reverse())};
    assert.deepEqual(run({op:'transform',table:swapped,pipeline:scenario.pipeline}).table,scenario.expected);
    evidence.scenarios.push({name,steps:scenario.pipeline.steps.map(s=>s[0]),rows:response.table.rows.length,reordered_columns:true});
  }
}
for(const pattern of ['(?rx)[','(?rx)(?<=a+)b','(?rx)\\4294967296','(?rx)(?i:(a)\\1)']){
  const result=request({op:'apply',table:{columns:['x'],rows:[['a']]},recipe:{version:1,columns:['x'],outputs:[{name:'v',expression:['capture',field,pattern,0,0]}]}});
  assert.equal(result.ok,false,pattern);
}
await mkdir('artifacts/regex-extended',{recursive:true});
await writeFile('artifacts/regex-extended/evidence.json',JSON.stringify(evidence,null,2)+'\n');
console.log(`${evidence.comparisons} extended regex oracle comparisons and ${evidence.scenarios.length} complete workflows passed.`);
