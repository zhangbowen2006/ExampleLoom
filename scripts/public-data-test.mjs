// Project-defined transforms on pinned public records, not a blind benchmark.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { performance } from 'node:perf_hooks';
const { handle } = await import(pathToFileURL(resolve(process.env.ENGINE_PATH || 'dist/engine.js')));
const call = request => {
  const response = JSON.parse(handle(JSON.stringify(request)));
  assert.equal(response.ok, true, response.error);
  return response;
};
const baseline = Boolean(process.env.ENGINE_PATH);
const evidence = { date: new Date().toISOString(), node: process.version, baseline, data_kind: 'public records; project-defined tasks; not blind or customer evaluation', datasets: [] };
let failures = 0;
await mkdir('artifacts/public-data', { recursive: true });
for (const name of ['public-zones', 'public-locales', 'public-templates']) {
  const scenario = JSON.parse(await readFile(`examples/${name}/scenario.json`, 'utf8'));
  const table = call({ op: 'parse', format: 'csv', text: await readFile(`examples/${name}/input.csv`, 'utf8') }).table;
  const recipe = { version: 1, columns: table.columns, outputs: [] };
  const dataset = { name, source: scenario.source, rows: table.rows.length, tasks: [] };
  for (const field of scenario.fields) {
    const started = performance.now();
    const labels = [...field.labels], refinements = [];
    const learn = () => call({ op: 'synthesize', examples: labels.map(label => ({ input: table.rows[label.row], output: label.output })), rows: table.rows });
    let report = learn();
    // A fixed two-round interaction budget for template names; select rows only
    // by model disagreement, then emulate the user's answer with the task oracle.
    for (let round = 0; round < (field.refinement_rounds || 0); round++) {
      const next = report.disagreements.find(d => !labels.some(label => label.row === d.row_index));
      if (!next) break;
      const row = next.row_index;
      refinements.push({ row, input: table.rows[row], answer: field.expected[row], previous_top: report.candidates[0]?.description, score: next.score });
      labels.push({ row, output: field.expected[row] });
      report = learn();
    }
    const item = { field: field.name, initial_training: field.labels.length, training: labels.length, refinements, heldout: table.rows.length - labels.length, candidates: report.candidates.length, status: report.status, truncated: report.truncated, stats: report.stats, milliseconds: Math.round((performance.now() - started) * 100) / 100, correct: 0, errors: [] };
    const candidate = report.candidates[0];
    if (candidate) {
      item.selected = candidate.description;
      recipe.outputs.push({ name: field.name, expression: candidate.expression });
      const result = call({ op: 'apply', recipe: { ...recipe, outputs: [recipe.outputs.at(-1)] }, table, spreadsheet_safe: false });
      for (let i = 0; i < table.rows.length; i++) {
        if (labels.some(label => label.row === i)) continue;
        if (result.rows[i].ok && result.rows[i].values[0] === field.expected[i]) item.correct++;
        else item.errors.push({ row: i, input: table.rows[i], expected: field.expected[i], actual: result.rows[i] });
      }
    }
    if (item.correct !== item.heldout) failures++;
    dataset.tasks.push(item);
    console.log(`${name}/${field.name}: ${item.correct}/${item.heldout} held-out values; ${item.status}`);
  }
  // No oracle-based selection: always use rank 0, and preserve all failures.
  if (recipe.outputs.length === scenario.fields.length) {
    const restored = call({ op: 'validate_recipe', recipe: JSON.parse(JSON.stringify(recipe)) }).recipe;
    const result = call({ op: 'apply', recipe: restored, table, spreadsheet_safe: false });
    // Insert an unrelated column ahead of the source to exercise name rebinding.
    const rebound = call({ op: 'apply', recipe: restored, table: { columns: ['unrelated', ...table.columns], rows: table.rows.map(row => ['ignore', ...row]) }, spreadsheet_safe: false });
    assert.deepEqual(rebound.rows, result.rows);
    if (!baseline && result.csv) {
      await writeFile(`artifacts/public-data/${name}.csv`, result.csv);
      await writeFile(`artifacts/public-data/${name}.recipe.json`, JSON.stringify(restored, null, 2) + '\n');
      assert.equal(call({ op: 'parse', format: 'csv', text: result.csv }).table.rows.length, table.rows.length);
    }
  }
  evidence.datasets.push(dataset);
}
evidence.failed_tasks = failures;
await writeFile(`artifacts/public-data/${baseline ? 'baseline-0.1.0' : 'results'}.json`, JSON.stringify(evidence, null, 2) + '\n');
if (!baseline) assert.equal(failures, 0, 'All public tasks must report every held-out value correctly; inspect results.json');
