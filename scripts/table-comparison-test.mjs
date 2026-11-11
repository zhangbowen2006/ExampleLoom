import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {handle} from '../dist/engine.js';

const call = request => {
  const result = JSON.parse(handle(JSON.stringify(request)));
  assert.equal(result.ok, true, result.error);
  return result;
};
const parse = text => call({op:'parse', format:'csv', text}).table;
const demo = JSON.parse(await readFile('examples/structures/ambiguous-records.json', 'utf8'));
const examples = [{input:parse(demo.input), output:parse(demo.target)}];
const first = call({op:'synthesize_table', examples});
assert.ok(first.candidates.length > 1);
const candidateSnapshot = JSON.stringify(first.candidates);
const compared = call({op:'compare_table_candidates', pipelines:first.candidates.map(c => c.pipeline), table:parse(demo.next)});
assert.equal(compared.status, 'disagreement');
assert.ok(compared.groups.length >= 2);
assert.equal(JSON.stringify(first.candidates), candidateSnapshot);
assert.ok(compared.groups.some(g => g.prediction.ok && JSON.stringify(g.prediction.table) === JSON.stringify(demo.expected)));

// The reference is supplied only now, by the simulated user. The comparison
// itself receives no target, and never turns a prediction into a label.
examples.push({input:parse(demo.next), output:parse(demo.refinement_target)});
const refined = call({op:'synthesize_table', examples});
assert.ok(refined.candidates.length > 0);
for (const candidate of refined.candidates) {
  for (const example of examples) {
    assert.deepEqual(call({op:'transform', pipeline:candidate.pipeline, table:example.input}).table, example.output);
  }
}
const unseen = parse(demo.after_refinement.input);
const selected = call({op:'validate_pipeline', pipeline:refined.candidates[0].pipeline}).pipeline;
assert.deepEqual(call({op:'transform', pipeline:selected, table:unseen}).table, demo.after_refinement.expected);

const odd = {columns:['c0'], rows:[['one'],['two'],['three']]};
const packed = {version:2, columns:['c0'], steps:[['pack_rows',2,false]]};
const identity = {version:2, columns:['c0'], steps:[]};
const errors = call({op:'compare_table_candidates', pipelines:[packed,identity,packed], table:odd});
assert.equal(errors.status, 'disagreement');
assert.deepEqual(errors.groups.map(g => g.candidates), [[0,2],[1]]);
assert.equal(errors.groups[0].prediction.ok, false);
assert.match(errors.groups[0].prediction.error, /complete blocks/);
assert.equal(call({op:'compare_table_candidates', pipelines:[packed,packed], table:odd}).status, 'all_failed');

const external = [];
const grid = rows => ({columns:Array.from({length:rows[0].length}, (_,i)=>`c${i}`), rows});
for (const name of ['exp0_27_4.txt','exp0_25_1.txt']) {
  const task = JSON.parse(await readFile(`fixtures/foofah/${name}`, 'utf8'));
  const report = call({op:'synthesize_table', examples:[{input:grid(task.InputTable), output:grid(task.OutputTable)}]});
  const result = call({op:'compare_table_candidates', pipelines:report.candidates.map(c=>c.pipeline), table:grid(task.TestingTable)});
  assert.equal(result.status, 'disagreement');
  assert.ok(result.groups.some(g=>!g.prediction.ok));
  // Oracle checking is done after comparison and never selects a candidate.
  assert.ok(result.groups.some(g=>g.prediction.ok && JSON.stringify(g.prediction.table.rows)===JSON.stringify(task.TestAnswer)));
  external.push({task:name,groups:result.groups.length,successful_candidates:result.successful_candidates,exposes_execution_failure:true,oracle_correct_group_present:true});
}

const checks = [
  'One training record permits multiple programs; a complete unlabelled batch exposes different predictions without changing ranking.',
  'Only a separately supplied correct target refines the version space; every retained program fits both training pairs.',
  'The selected refined pipeline survives serialization and transforms a third batch with an unseen record count.',
  'Execution failures remain explicit prediction groups; identical failures cannot masquerade as successful consensus.',
  'Two unchanged Foofah tasks expose fixed-pack/pivot failures alongside alternative successful outcomes; oracle validation never chooses the program.',
];
await mkdir('artifacts', {recursive:true});
await writeFile('artifacts/table-comparison-results.json', JSON.stringify({date:new Date().toISOString(), engine:(JSON.parse(await readFile('dist/BUILD.json','utf8'))).engine_sha256, checks, initial_candidates:first.candidates.length, initial_prediction_groups:compared.groups.length, refined_candidates:refined.candidates.length, selected, expected:demo.after_refinement.expected, external}, null, 2)+'\n');
console.log(JSON.stringify({checks, initial_candidates:first.candidates.length, initial_prediction_groups:compared.groups.length, refined_candidates:refined.candidates.length}, null, 2));
