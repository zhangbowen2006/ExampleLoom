#!/usr/bin/env node
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const help = `ExampleLoom 0.1.0 — examples to portable string programs

Build once: npm run build
node bin/exampleloom.mjs learn --data input.csv --examples examples.json --out candidates.json
node bin/exampleloom.mjs recipe --report candidates.json --choose 0 --name normalized --out recipe.json
node bin/exampleloom.mjs apply --data next.csv --recipe recipe.json --out result.csv
node bin/exampleloom.mjs run request.json

Examples: [{"row":0,"output":"0012"},{"row":1,"output":"0081"}]
--format csv|jsonl overrides extension inference. JSON reports go to stdout if --out is absent.
--choose is explicit: candidate rank is not confidence. CSV export stops if any row fails.
Saved recipes can contain several output fields; the workbench can construct them interactively.`;
const args = process.argv.slice(2);
if (!args.length || args.includes('--help')) { console.log(help); process.exit(0); }
try {
  const { handle } = await import('../dist/engine.js');
  const request = value => {
    const result = JSON.parse(handle(JSON.stringify(value)));
    if (!result.ok) throw new Error(result.error);
    return result;
  };
  const command = args.shift();
  const flags = {};
  if (command !== 'run') {
    for (let i = 0; i < args.length; i += 2) {
      if (!/^--[a-z]+$/.test(args[i]) || args[i + 1] == null || args[i + 1].startsWith('--')) throw new Error('Expected --flag value pairs');
      const key = args[i].slice(2);
      if (Object.hasOwn(flags, key)) throw new Error(`Duplicate flag: ${key}`);
      if (!['data', 'examples', 'out', 'report', 'choose', 'name', 'recipe', 'format'].includes(key)) throw new Error(`Unknown flag: ${key}`);
      flags[key] = args[i + 1];
    }
  }
  const requireFlag = key => { if (!flags[key]) throw new Error(`Missing --${key}`); return flags[key]; };
  const readJson = async path => JSON.parse(await readFile(path, 'utf8'));
  const readTable = async () => request({ op: 'parse', format: flags.format || (requireFlag('data').endsWith('.jsonl') ? 'jsonl' : 'csv'), text: await readFile(flags.data, 'utf8') }).table;
  const emit = async value => {
    const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n';
    if (flags.out) { await writeFile(flags.out, text, 'utf8'); console.error(`Wrote ${resolve(flags.out)}`); }
    else process.stdout.write(text);
  };
  if (command === 'run') {
    if (args.length !== 1) throw new Error('run requires one request JSON file');
    await emit(request(await readJson(args[0])));
  } else if (command === 'learn') {
    const table = await readTable();
    const labels = await readJson(requireFlag('examples'));
    if (!Array.isArray(labels)) throw new Error('Examples must be an array');
    const examples = labels.map(e => {
      if (!Number.isInteger(e.row) || e.row < 0 || e.row >= table.rows.length || typeof e.output !== 'string') throw new Error('Invalid row label');
      return { input: table.rows[e.row], output: e.output };
    });
    const result = request({ op: 'synthesize', examples, rows: table.rows.slice(0, 5000) });
    await emit({ ...result, columns: table.columns, probe_rows: Math.min(table.rows.length, 5000), total_rows: table.rows.length });
  } else if (command === 'recipe') {
    const report = await readJson(requireFlag('report'));
    const choice = Number(requireFlag('choose'));
    if (!Number.isInteger(choice) || choice < 0 || !report.candidates?.[choice]) throw new Error('Invalid candidate index');
    const recipe = { version: 1, columns: report.columns, outputs: [{ name: requireFlag('name'), expression: report.candidates[choice].expression }] };
    await emit(request({ op: 'validate_recipe', recipe }).recipe);
  } else if (command === 'apply') {
    const result = request({ op: 'apply', recipe: await readJson(requireFlag('recipe')), table: await readTable() });
    if (result.failures) {
      console.error(JSON.stringify(result, null, 2));
      throw new Error(`${result.failures} failed rows; no partial CSV written`);
    }
    await emit(result.csv);
  } else throw new Error(`Unknown command: ${command}`);
} catch (error) {
  console.error(`ExampleLoom: ${error.message}`);
  if (error.code === 'ERR_MODULE_NOT_FOUND') console.error(`Build the engine first: cd ${root} && npm run build`);
  process.exitCode = 1;
}
