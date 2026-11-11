import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ? pathToFileURL(process.env.PLAYWRIGHT_MODULE).href : 'playwright');
const browser = await chromium.launch({headless:true, ...(process.env.BROWSER_EXECUTABLE ? {executablePath:process.env.BROWSER_EXECUTABLE} : {})});
const base = process.env.BASE_URL ?? 'http://127.0.0.1:4173';
const demo = JSON.parse(await readFile('examples/structures/ambiguous-records.json', 'utf8'));
const checks = [], errors = [], remote = [];
try {
  const page = await browser.newPage({acceptDownloads:true});
  page.on('pageerror', e => errors.push(e.message));
  page.on('request', r => {if(new URL(r.url()).origin!==new URL(base).origin)remote.push(r.url());});
  await page.addInitScript(() => {
    const Original = window.Worker;
    window.Worker = class extends Original {};
    window.heldComparisons = [];
    window.holdComparisons = false;
    const send = Worker.prototype.postMessage;
    Worker.prototype.postMessage = function(message, ...args) {
      if(window.holdComparisons && message.request?.op === 'compare_table_candidates') {
        window.heldComparisons.push(() => send.call(this, message, ...args));
      } else {send.call(this, message, ...args);}
    };
  });
  await page.goto(base+'/structure.html');
  await page.locator('[data-table-demo="ambiguous-records"]').click();
  await page.waitForFunction(() => !document.querySelector('#learn').disabled);
  await page.locator('#learn').click();
  await page.locator('[data-table-choose="0"]').waitFor();
  await page.locator('#compare-table').click();
  await page.locator('.comparison-group').first().waitFor();
  assert.ok(await page.locator('.comparison-group').count() >= 2);
  assert.match(await page.locator('#comparison-summary').innerText(), /不同结果/);
  assert.equal(await page.locator('#pipeline').inputValue(), '');
  assert.equal(await page.locator('#apply').isDisabled(), true);
  assert.equal(await page.locator('#export').isDisabled(), true);
  checks.push('Real Worker compares all retained table programs on an unlabelled batch without choosing or exporting a result.');

  await page.locator('#refine-table').click();
  const pair = page.locator('#extra-pairs fieldset').last();
  assert.equal(await pair.locator('textarea').first().inputValue(), demo.next);
  assert.equal(await pair.locator('textarea').last().inputValue(), '');
  assert.equal(await page.locator('#candidates').innerText(), '');
  assert.equal(await page.locator('#compare-table').isDisabled(), true);
  assert.equal(await page.locator('#refine-table').isVisible(), false);
  await pair.locator('textarea').last().fill(demo.refinement_target);
  await page.locator('#learn').click();
  await page.locator('[data-table-choose="0"]').waitFor();
  await page.locator('#next').fill(demo.after_refinement.input);
  await page.locator('[data-table-choose="0"]').click();
  await page.locator('#apply').click();
  await page.waitForFunction(() => !document.querySelector('#export').disabled);
  const actual = await page.locator('#results tbody tr').evaluateAll(rows => rows.map(row => [...row.children].map(c => c.textContent)));
  assert.deepEqual(actual, demo.after_refinement.expected.rows);
  await mkdir('artifacts', {recursive:true});
  const wait = page.waitForEvent('download');
  await page.locator('#export').click();
  const download = await wait;
  await download.saveAs('artifacts/table-comparison-browser.csv');
  const expectedCsv = [demo.after_refinement.expected.columns, ...demo.after_refinement.expected.rows].map(row => row.join(',')).join('\r\n')+'\r\n';
  assert.equal(await readFile('artifacts/table-comparison-browser.csv','utf8'), expectedCsv);
  checks.push('Refinement copies only the input, leaves the target blank, invalidates old programs, relearns from the supplied target and downloads the correct third batch.');

  await page.evaluate(() => {window.holdComparisons = true;});
  await page.locator('#compare-table').click();
  await page.waitForFunction(() => window.heldComparisons.length > 0);
  await page.locator('#next').fill('c0\nnew\nvalue\n');
  await page.evaluate(() => {window.holdComparisons=false;for(const send of window.heldComparisons.splice(0))send();});
  await page.waitForFunction(() => document.querySelector('#cancel').hidden);
  assert.equal(await page.locator('.comparison-group').count(), 0);
  assert.equal(await page.locator('#refine-table').isVisible(), false);
  assert.equal(await page.locator('#export').isDisabled(), true);
  assert.match(await page.locator('#notice').innerText(), /重新比较/);
  checks.push('A delayed comparison cannot restore stale predictions or labels after the incoming batch changes.');

  await page.locator('#next').fill(demo.after_refinement.input);
  await page.locator('#compare-table').click();
  await page.locator('.comparison-group').first().waitFor();
  await page.locator('#training').fill(demo.input+'changed\n');
  assert.equal(await page.locator('.comparison-group').count(), 0);
  assert.equal(await page.locator('#compare-table').isDisabled(), true);
  await page.setViewportSize({width:390,height:844});
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth>innerWidth), false);
  assert.deepEqual(errors, []);
  assert.deepEqual(remote, []);
  checks.push('Training edits invalidate comparisons; the 390px page has no overflow, browser errors or off-origin data requests.');
  await writeFile('artifacts/table-comparison-browser-results.json', JSON.stringify({date:new Date().toISOString(),browser:await browser.version(),checks},null,2)+'\n');
  console.log(JSON.stringify({checks},null,2));
} finally {await browser.close();}
