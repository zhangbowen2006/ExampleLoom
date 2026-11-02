import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { handle } from '../dist/engine.js';

const call = request => {
  const result = JSON.parse(handle(JSON.stringify(request)));
  assert.equal(result.ok, true, result.error);
  return result;
};
const evidence = { date: new Date().toISOString(), node: process.version, scenarios: [], checks: [] };
for (const name of ['products', 'labels', 'media', 'ambiguity']) {
  const scenario = JSON.parse(await readFile(`examples/${name}/scenario.json`, 'utf8'));
  const source = await readFile(`examples/${name}/${scenario.file}`, 'utf8');
  const table = call({ op: 'parse', format: 'csv', text: source }).table;
  const recipe = { version: 1, columns: table.columns, outputs: [] };
  for (const field of scenario.fields) {
    const start = performance.now();
    const report = call({ op: 'synthesize', examples: field.labels.map(e => ({ input: table.rows[e.row], output: e.output })), rows: table.rows });
    assert.ok(report.candidates.length > 0, `${name}/${field.name}: no candidates`);
    recipe.outputs.push({ name: field.name, expression: report.candidates[0].expression });
    evidence.scenarios.push({ scenario: name, field: field.name, milliseconds: Math.round(performance.now() - start), candidates: report.candidates.length, status: report.status, truncated: report.truncated, ...report.stats, selected: report.candidates[0].description, heldout_rows: table.rows.length - field.labels.length });
    if (name === 'ambiguity') {
      assert.ok(report.disagreements.some(d => d.row_index === 2));
      const refined = call({ op: 'synthesize', examples: [...field.labels, { row: 2, output: '123456' }].map(e => ({ input: table.rows[e.row], output: e.output })), rows: table.rows });
      assert.ok(refined.candidates.length);
      assert.ok(refined.candidates.every(c => {
        const r = call({ op: 'apply', recipe: { version: 1, columns: table.columns, outputs: [{ name: 'x', expression: c.expression }] }, table });
        return r.rows[2].ok && r.rows[2].values[0] === '123456';
      }));
    }
  }
  const result = call({ op: 'apply', recipe, table });
  assert.equal(result.failures, 0);
  assert.deepEqual(result.rows.map(r => r.values), table.rows.map((_, i) => scenario.fields.map(f => f.expected[i])));
  const reversed = { columns: [...table.columns].reverse(), rows: table.rows.map(r => [...r].reverse()) };
  assert.deepEqual(call({ op: 'apply', recipe, table: reversed }).rows, result.rows);
  const roundtrip = call({ op: 'validate_recipe', recipe: JSON.parse(JSON.stringify(recipe)) }).recipe;
  assert.deepEqual(call({ op: 'apply', recipe: roundtrip, table }).rows, result.rows);
  if (name === 'media') {
    const bad = call({ op: 'parse', format: 'csv', text: await readFile('examples/media/invalid.csv', 'utf8') }).table;
    const failed = call({ op: 'apply', recipe, table: bad });
    assert.equal(failed.failures, 1);
    assert.equal(failed.csv, null);
    evidence.checks.push('Impossible date retains row error and blocks partial CSV');
  }
  evidence.checks.push(`${name}: held-out outputs, schema rebinding, recipe roundtrip`);
}

await mkdir('artifacts', { recursive: true });
const cli = (...args) => {
  const r = spawnSync(process.execPath, ['bin/exampleloom.mjs', ...args], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
};
cli('learn', '--data', 'examples/products/input.csv', '--examples', 'examples/products/model-labels.json', '--out', 'artifacts/cli-candidates.json');
cli('recipe', '--report', 'artifacts/cli-candidates.json', '--choose', '0', '--name', 'model', '--out', 'artifacts/cli-recipe.json');
const csv = cli('apply', '--data', 'examples/products/input.csv', '--recipe', 'artifacts/cli-recipe.json');
assert.deepEqual(call({ op: 'parse', format: 'csv', text: csv }).table.rows, [['0012'], ['0081'], ['123456'], ['0007']]);
evidence.checks.push('CLI learn → explicit recipe selection → batch CSV');

// Deterministic independent CSV roundtrips exercise adversarial quoting and Unicode.
const cells = ['', '0012', '甲😀', 'a,b', 'a"b', 'a\r\nb', '=SUM(1)', '  x  ', 'x\ny'];
const table = { columns: ['value'], rows: Array.from({ length: 150 }, (_, i) => [cells[i % cells.length] + cells[(i * 7 + 2) % cells.length]]) };
const recipe = { version: 1, columns: ['value'], outputs: [{ name: 'value', expression: ['field', 0] }] };
const encoded = call({ op: 'apply', recipe, table, spreadsheet_safe: false });
assert.deepEqual(call({ op: 'parse', format: 'csv', text: encoded.csv }).table, table);
evidence.checks.push('150 quoted/Unicode CSV identity roundtrips');

const start = performance.now();
const large = { columns: ['value'], rows: Array.from({ length: 10000 }, (_, i) => [`项目-${String(i).padStart(6, '0')}`]) };
const largeRecipe = { version: 1, columns: ['value'], outputs: [{ name: 'id', expression: ['token', ['field', 0], '-', -1] }] };
const largeResult = call({ op: 'apply', recipe: largeRecipe, table: large });
assert.equal(largeResult.failures, 0);
assert.equal(largeResult.rows[9999].values[0], '009999');
evidence.batch_10000_ms = Math.round(performance.now() - start);
await writeFile('artifacts/integration-results.json', JSON.stringify(evidence, null, 2) + '\n');
console.log(JSON.stringify(evidence, null, 2));
console.log('PASS: all scenario, CLI, roundtrip and batch checks');
