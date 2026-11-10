import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

const {chromium} = await import(process.env.PLAYWRIGHT_MODULE
  ? pathToFileURL(process.env.PLAYWRIGHT_MODULE).href : 'playwright');
const browser = await chromium.launch({headless:true, ...(process.env.BROWSER_EXECUTABLE
  ? {executablePath:process.env.BROWSER_EXECUTABLE} : {})});
const base = process.env.BASE_URL ?? 'http://127.0.0.1:4173';
const checks = [];
const errors = [];

try {
  const page = await browser.newPage({acceptDownloads:true});
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    const Original = window.Worker;
    window.Worker = class extends Original {
      constructor(...args) {
        super(...args);
        window.loomTestWorker = this;
      }
    };
    window.loomTestQueue = [];
    window.loomTestHeldOperation = null;
    const send = Worker.prototype.postMessage;
    Worker.prototype.postMessage = function(message, ...args) {
      if (message.request?.op === window.loomTestHeldOperation) {
        window.loomTestQueue.push(() => send.call(this, message, ...args));
      } else {
        send.call(this, message, ...args);
      }
    };
  });
  await page.goto(base + '/structure.html');
  await page.locator('[data-table-demo="mixed-tags"]').click();
  await page.waitForFunction(() => !document.querySelector('#learn').disabled);
  const training = await page.locator('#training').inputValue();
  const target = await page.locator('#target').inputValue();

  async function learnAndChoose() {
    await page.locator('#learn').click();
    await page.locator('[data-table-choose="0"]').waitFor();
    await page.locator('[data-table-choose="0"]').click();
  }
  async function hold(operation) {
    await page.evaluate(op => {window.loomTestHeldOperation = op;}, operation);
  }
  async function waitForHeldRequest() {
    await page.waitForFunction(() => window.loomTestQueue.length > 0);
  }
  async function resume() {
    await page.evaluate(() => {
      window.loomTestHeldOperation = null;
      for (const send of window.loomTestQueue.splice(0)) send();
    });
    await page.waitForFunction(() => document.querySelector('#cancel').hidden);
  }

  await learnAndChoose();
  const downloads = [];
  page.on('download', item => downloads.push(item.suggestedFilename()));
  await hold('validate_pipeline');
  await page.locator('#save').click();
  await waitForHeldRequest();
  assert.equal(await page.locator('#load').isDisabled(), true);
  assert.equal(await page.locator('#next-file').isDisabled(), true);
  await page.locator('#training').fill(training + 'C55,new\n');
  await resume();
  assert.deepEqual(downloads, []);
  assert.match(await page.locator('#notice').innerText(), /重新选用/);
  assert.equal(await page.locator('#load').isEnabled(), true);
  assert.equal(await page.locator('#next-file').isEnabled(), true);
  assert.equal(await page.locator('#pipeline').inputValue(), '');
  checks.push('Editing training data during save prevents downloading a stale pipeline');

  const pipeline = await readFile('artifacts/advanced/mixed-tags.pipeline.json');
  await hold('validate_pipeline');
  await page.locator('#load').setInputFiles({name:'pipeline.json',mimeType:'application/json',buffer:pipeline});
  await waitForHeldRequest();
  await page.locator('#target').fill(target + 'IN/55,new\n');
  await resume();
  assert.equal(await page.locator('#pipeline').inputValue(), '');
  assert.equal(await page.locator('#apply').isDisabled(), true);
  assert.match(await page.locator('#notice').innerText(), /重新载入/);
  checks.push('An in-flight load cannot replace a pipeline after the user changes the target');

  await page.locator('[data-table-demo="mixed-tags"]').click();
  await page.waitForFunction(() => !document.querySelector('#learn').disabled);
  await learnAndChoose();
  await hold('synthesize_table');
  await page.locator('#learn').click();
  await waitForHeldRequest();
  await page.locator('#cancel').click();
  await page.waitForFunction(() => document.querySelector('#cancel').hidden);
  assert.equal(await page.locator('[data-table-choose]').count(), 0);
  assert.equal(await page.locator('#apply').isDisabled(), true);
  await page.evaluate(() => {window.loomTestHeldOperation = null;window.loomTestQueue = [];});
  await learnAndChoose();
  checks.push('Cancelling a repeated search clears old candidates and a new search succeeds');

  await page.evaluate(() => {
    window.loomTestPreviousWorker = window.loomTestWorker;
    window.loomTestWorker.dispatchEvent(new ErrorEvent('error', {cancelable:true}));
  });
  await page.locator('#apply').click();
  await page.waitForFunction(() => !document.querySelector('#export').disabled);
  assert.equal(await page.evaluate(() => window.loomTestPreviousWorker !== window.loomTestWorker), true);
  const actual = await page.locator('#results tbody tr').evaluateAll(rows =>
    rows.map(row => [...row.children].map(cell => cell.textContent)));
  const demo = JSON.parse(await readFile('examples/structures/mixed-tags.json'));
  assert.deepEqual(actual, demo.expected.rows);
  checks.push('After a simulated Worker error, the next operation creates a Worker and replays correctly');
  assert.deepEqual(errors, []);

  await mkdir('artifacts', {recursive:true});
  await writeFile('artifacts/browser-recovery-results.json', JSON.stringify({
    date:new Date().toISOString(), browser:await browser.version(), checks,
  }, null, 2) + '\n');
  console.log(JSON.stringify({checks}, null, 2));
} finally {
  await browser.close();
}
