import { parentPort, workerData } from 'node:worker_threads';
import { performance } from 'node:perf_hooks';
import { handle } from '../dist/engine.js';

const run = request => {
  const answer = JSON.parse(handle(JSON.stringify(request)));
  if (!answer.ok) throw new Error(answer.error);
  return answer;
};
try {
  const { task, options } = workerData;
  const table = grid => {
    if (!Array.isArray(grid) || !grid.length || !grid[0].length) throw new Error('Empty upstream table');
    const width = grid[0].length;
    if (grid.some(row => !Array.isArray(row) || row.length !== width || row.some(v => typeof v !== 'string'))) throw new Error('Ragged/non-string upstream table');
    return { columns: Array.from({length: width}, (_, i) => `c${i}`), rows: grid };
  };
  const input = table(task.InputTable), output = table(task.OutputTable);
  const start = performance.now();
  const report = run({op:'synthesize_table', examples:[{input, output}], options});
  const synthesis_ms = performance.now() - start;
  // TestAnswer is never passed to the learner or used for ranking.
  const testing = table(task.TestingTable), answer = table(task.TestAnswer);
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const training = report.candidates.map(c => same(run({op:'transform', table:input, pipeline:c.pipeline}).table, output));
  if (training.some(ok => !ok)) throw new Error('Learner returned inconsistent candidate');
  const predictions = report.candidates.map(c => {
    try { return {pass: same(run({op:'transform', table:testing, pipeline:c.pipeline}).table, answer)}; }
    catch (error) { return {pass:false, error:error.message}; }
  });
  const trainingRows = new Set(input.rows.map(JSON.stringify));
  parentPort.postMessage({synthesis_ms, training_solved:report.candidates.length > 0,
    top1_holdout:predictions[0]?.pass ?? false, any_holdout:predictions.some(p => p.pass),
    candidates:report.candidates.length, status:report.status, truncated:report.truncated,
    stats:report.stats, top1_pipeline:report.candidates[0]?.pipeline ?? null,
    top1_error:predictions[0]?.error ?? null, training_rows:input.rows.length,
    testing_rows:testing.rows.length, overlapping_input_rows:testing.rows.filter(r => trainingRows.has(JSON.stringify(r))).length});
} catch (error) { parentPort.postMessage({error:error.message}); }
