import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE).href:'playwright');
const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const checks=[],errors=[],remote=[];const base=process.env.BASE_URL??'http://127.0.0.1:4173';
try{
 const page=await browser.newPage({acceptDownloads:true});page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).origin!==new URL(base).origin)remote.push(r.url());});
 await page.addInitScript(()=>{const Original=window.Worker;window.Worker=class extends Original{};const send=Worker.prototype.postMessage;window.holdJobs=false;window.heldJobs=[];Worker.prototype.postMessage=function(m,...args){if(window.holdJobs&&m.request?.op==='run_data_job')window.heldJobs.push(()=>send.call(this,m,...args));else send.call(this,m,...args);};});
 await page.goto(base+'/jobs.html');
 const load=async name=>{await page.locator(`[data-job-demo="${name}"]`).click();await page.waitForFunction(()=>!document.querySelector('#run-job').disabled);};
 const run=async()=>{await page.locator('#run-job').click();await page.waitForFunction(()=>!document.querySelector('#export-job').disabled);};
 for(const name of ['product-enrichment','monthly-settlement','catalogue-reconcile']){
  const demo=JSON.parse(await readFile(`examples/jobs/${name}.json`,'utf8'));await load(name);await run();
  assert.deepEqual(await page.locator('#results tbody tr').evaluateAll(rows=>rows.map(r=>[...r.children].map(c=>c.textContent))),demo.expected.rows);
  const waiting=page.waitForEvent('download');await page.locator('#export-job').click();const csv=await waiting;await csv.saveAs(`artifacts/jobs/browser-${name}.csv`);
  assert.equal(await readFile(`artifacts/jobs/browser-${name}.csv`,'utf8'),await readFile(`artifacts/jobs/${name}-result.csv`,'utf8'));
  const savedWait=page.waitForEvent('download');await page.locator('#save-job').click();const saved=await savedWait;await saved.saveAs(`artifacts/jobs/browser-${name}.job.json`);
  await page.locator('#load-job').setInputFiles(`artifacts/jobs/browser-${name}.job.json`);await page.waitForFunction(()=>!document.querySelector('#run-job').disabled);assert.equal(await page.locator('#export-job').isDisabled(),true);await run();
  checks.push(`${name}: real Worker, complete expected rows, downloaded CSV and saved/reloaded task.`);
 }
 await load('product-enrichment');
 const catalog=page.locator('textarea[data-source="catalog"]');await catalog.fill((await catalog.inputValue())+'001,W1,duplicate\n');await page.locator('#run-job').click();await page.waitForFunction(()=>document.querySelector('#cancel').hidden);
 assert.equal(await page.locator('#export-job').isDisabled(),true);assert.match(await page.locator('#notice').innerText(),/unique right/);
 checks.push('Duplicate master keys fail without partial export.');
 await load('monthly-settlement');await page.evaluate(()=>{window.holdJobs=true;});await page.locator('#run-job').click();await page.waitForFunction(()=>window.heldJobs.length>0);
 assert.equal(await page.locator('#sources input[type=file]').first().isDisabled(),true);
 await page.locator('textarea[data-source="jan"]').fill('supplier,currency,amount\nnew,CNY,1\n');await page.evaluate(()=>{window.holdJobs=false;for(const send of window.heldJobs.splice(0))send();});await page.waitForFunction(()=>document.querySelector('#cancel').hidden);
 assert.equal(await page.locator('#export-job').isDisabled(),true);assert.match(await page.locator('#notice').innerText(),/重新运行/);
 checks.push('An edited source invalidates an in-flight result.');
 await load('monthly-settlement');await page.evaluate(()=>{window.holdJobs=true;});await page.locator('#run-job').click();await page.waitForFunction(()=>window.heldJobs.length>0);await page.locator('#cancel').click();await page.waitForFunction(()=>document.querySelector('#cancel').hidden);assert.equal(await page.locator('#export-job').isDisabled(),true);
 await page.evaluate(()=>{window.holdJobs=false;window.heldJobs=[];});await run();
 checks.push('Cancel terminates the Worker; retry starts a new Worker and succeeds.');
 await page.locator('#job').evaluate(e=>{e.closest('details').open=true;});await page.locator('#job').fill('{invalid');assert.equal(await page.locator('#run-job').isDisabled(),true);assert.equal(await page.locator('#save-job').isDisabled(),true);assert.equal(await page.locator('#export-job').isDisabled(),true);
 await page.locator('#configure').click();await page.waitForFunction(()=>document.querySelector('#cancel').hidden);assert.equal(await page.locator('#run-job').isDisabled(),true);
 checks.push('Dirty or invalid configurations cannot reuse old task results.');
 await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);assert.deepEqual(errors,[]);assert.deepEqual(remote,[]);
 checks.push('390px page fits and sends no source data off-origin.');
 await writeFile('artifacts/data-job-browser-results.json',JSON.stringify({timestamp:new Date().toISOString(),browser:await browser.version(),checks},null,2)+'\n');console.log(JSON.stringify({checks}));
}finally{await browser.close();}
