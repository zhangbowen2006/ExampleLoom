import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const moduleName = process.env.PLAYWRIGHT_MODULE ? pathToFileURL(process.env.PLAYWRIGHT_MODULE).href : 'playwright';
const { chromium } = await import(moduleName);
const browser = await chromium.launch({ headless: true, ...(process.env.BROWSER_EXECUTABLE ? { executablePath: process.env.BROWSER_EXECUTABLE } : {}) });
const issues = [], checks = [];
const baseUrl = process.env.BASE_URL || 'http://127.0.0.1:4173';
await mkdir('artifacts', { recursive: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1080 }, locale: 'zh-CN', acceptDownloads: true });
  page.on('pageerror', e => issues.push(e.message));
  const remoteRequests = [];
  page.on('request', request => { if (new URL(request.url()).origin !== new URL(baseUrl).origin) remoteRequests.push(request.url()); });
  await page.goto(baseUrl + '/');
  for (const scenario of ['products', 'labels', 'media']) {
    await page.locator(`[data-demo="${scenario}"]`).click();
    await page.waitForFunction(() => !document.querySelector('#learn').disabled);
    for (const field of [0, 1]) {
      if (field) await page.locator('#demo-field').selectOption('1');
      await page.locator('#learn').click();
      await page.locator('[data-choose="0"]').waitFor();
      await page.locator('[data-choose="0"]').click();
    }
    await page.locator('#apply').click();
    await page.waitForFunction(() => !document.querySelector('#download-csv').disabled);
    assert.match(await page.locator('#result-stats').innerText(), /4 行 · 0 行失败/);
    const expected = JSON.parse(await readFile(`examples/${scenario}/scenario.json`, 'utf8'));
    const visible = await page.locator('#results tbody tr').evaluateAll(rows => rows.map(tr => [...tr.querySelectorAll('td')].slice(1, -1).map(td => td.textContent)));
    assert.deepEqual(visible, Array.from({ length: 4 }, (_, i) => expected.fields.map(f => f.expected[i])));
    checks.push(`${scenario}: browser labels → synthesis → multi-output recipe → held-out preview`);
    if (scenario === 'products') {
      const downloadWait = page.waitForEvent('download');
      await page.locator('#save-recipe').click();
      const download = await downloadWait; await download.saveAs('artifacts/browser.recipe.json');
      assert.equal(JSON.parse(await readFile('artifacts/browser.recipe.json', 'utf8')).outputs.length, 2);
      await page.screenshot({ path: 'artifacts/workbench-desktop.png', fullPage: true });
      await page.locator('#demo-field').selectOption('0');
      await page.locator('#row-0 input[type=text]').fill('0012X');
      assert.equal(await page.locator('#download-csv').isDisabled(), true);
      assert.equal(await page.locator('#download-report').isDisabled(), true);
      assert.equal(await page.locator('#apply').isDisabled(), true);
      assert.equal(await page.locator('#save-recipe').isDisabled(), true);
      assert.match(await page.locator('#recipe-fields').innerText(), /样例已修改/);
      assert.equal(await page.locator('.recipe-field').count(), 2, 'Other field must be retained');
      await page.locator('#demo-field').selectOption('1');
      assert.equal(await page.locator('#apply').isDisabled(), true, 'Field switching must not bypass stale rules');
      await page.locator('#demo-field').selectOption('0');
      assert.equal(await page.locator('#row-0 input[type=text]').inputValue(), '0012X', 'Edited labels survive field switching');
      await page.locator('#row-0 input[type=text]').fill('0012');
      assert.equal(await page.locator('#apply').isDisabled(), true, 'Reselection is explicit');
      await page.locator('#learn').click();
      await page.locator('[data-choose="0"]').waitFor();
      await page.locator('[data-choose="0"]').click();
      await page.locator('#apply').click();
      await page.waitForFunction(() => !document.querySelector('#download-csv').disabled);
      assert.equal(await page.locator('.recipe-field').count(), 2);
      checks.push('Editing labels invalidates exports and the selected field; field switching preserves edits; explicit relearning restores multi-field export');
    }
    if (scenario === 'media') {
      await page.locator('#source').fill(await readFile('examples/media/invalid.csv', 'utf8'));
      assert.equal(await page.locator('#apply').isDisabled(), true);
      await page.locator('#parse').click();
      await page.waitForFunction(() => !document.querySelector('#apply').disabled);
      await page.locator('#apply').click();
      await page.waitForFunction(() => document.querySelector('#result-stats').textContent.includes('1 行失败'));
      assert.equal(await page.locator('#download-csv').isDisabled(), true);
      assert.equal(await page.locator('#download-report').isDisabled(), false);
      checks.push('Invalid date keeps indexed error and disables CSV; edited source invalidates stale preview');
    }
  }
  await page.locator('[data-demo="ambiguity"]').click();
  await page.waitForFunction(() => !document.querySelector('#learn').disabled);
  await page.locator('#learn').click();
  await page.locator('.disagreement').first().waitFor();
  assert.match(await page.locator('#disagreements').innerText(), /123456/);
  assert.match(await page.locator('#disagreements').innerText(), /3456/);
  await page.locator('#row-2 input[type=text]').fill('123456');
  await page.locator('#learn').click();
  await page.locator('[data-choose="0"]').waitFor();
  await page.locator('[data-choose="0"]').click();
  await page.locator('#apply').click();
  await page.waitForFunction(() => !document.querySelector('#download-csv').disabled);
  assert.match(await page.locator('#results').innerText(), /000007/);
  checks.push('Ambiguous suffix vs delimiter shown; third label refines actual candidates');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: 'artifacts/workbench-mobile.png', fullPage: true });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth), false, 'Mobile page overflows');
  checks.push('390px responsive page has no horizontal viewport overflow');
  assert.deepEqual(issues, []);
  assert.deepEqual(remoteRequests, [], 'Workbench unexpectedly sent a remote request');
  checks.push('No page errors; no remote network requests during data workflows');
  await writeFile('artifacts/browser-results.json', JSON.stringify({ date: new Date().toISOString(), browser: await browser.version(), checks }, null, 2));
  console.log(JSON.stringify({ checks, issues }, null, 2));
} finally { await browser.close(); }
