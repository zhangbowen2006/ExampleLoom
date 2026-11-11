import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {handle} from '../dist/engine.js';

// Fixed-seed, constructed cases: generate complete records first, then turn
// them into an input stream. Expected tables come from those original records,
// not from the implementation's streaming state machine.
let state = 0x6e624531;
const random = limit => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state % limit; };
const labels = ['city', 'score', 'country', 'mail', 'phone', '标签', 'emoji'];
const values = ['', '0', '007', 'a,b', '中 文', '😀', 'x=y', 'line\nnext'];
const pipeline = {version:2, columns:['key','value'], steps:[['pivot_records','key','value','name']]};
const request = table => JSON.parse(handle(JSON.stringify({op:'transform',pipeline,table})));
let cases = 0;
for (let trial = 0; trial < 250; trial++) {
  const sourceRecords = Array.from({length:1 + random(5)}, (_, index) => {
    const entries = [['name', `id-${trial}-${index}`]];
    // Rotate label order between records so header ordering is exercised.
    const start = random(labels.length);
    for (let offset = 0; offset < labels.length; offset++) {
      const label = labels[(start + offset) % labels.length];
      if (random(3) !== 0) entries.push([label, values[random(values.length)]]);
    }
    return entries;
  });
  const orderedLabels = [...new Set(sourceRecords.flatMap(record => record.map(([key]) => key)))];
  const expected = {
    columns:orderedLabels.map((_, i) => `c${i}`),
    rows:[orderedLabels, ...sourceRecords.map(record => {
      const original = new Map(record);
      return orderedLabels.map(label => original.get(label) ?? '');
    })],
  };
  const keyValueRows = sourceRecords.flat();
  const reordered = trial % 2 === 0;
  const table = reordered
    ? {columns:['extra','value','key'], rows:keyValueRows.map(([key,value])=>['ignored',value,key])}
    : {columns:['key','value'], rows:keyValueRows};
  const result = request(table);
  assert.equal(result.ok, true, result.error);
  assert.deepEqual(result.table, expected, `constructed case ${trial}`);
  cases++;
}
const invalid = [
  {columns:['key','value'],rows:[]},
  {columns:['key','value'],rows:[['city','East'],['name','A']]},
  {columns:['key','value'],rows:[['name','A'],['city','East'],['city','West']]},
  {columns:['key','value'],rows:[['name','A'],['','blank']]},
  {columns:['key','value'],rows:[['name','A'],...Array.from({length:64},(_,i)=>[`field-${i}`,'v'])]},
];
for (const table of invalid) assert.equal(request(table).ok, false);
const evidence = {
  date:new Date().toISOString(),seed:'0x6e624531',constructed_cases:cases,
  rejected_invalid_cases:invalid.length,
  engine_sha256:createHash('sha256').update(await readFile('dist/engine.js')).digest('hex'),
  scope:'Constructed independently from original records; no external or blind benchmark claim.',
};
await mkdir('artifacts',{recursive:true});
await writeFile('artifacts/record-pivot-results.json',JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence,null,2));
