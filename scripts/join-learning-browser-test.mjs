import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE).href:'playwright');
const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const base=process.env.BASE_URL??'http://127.0.0.1:4173',checks=[],errors=[],remote=[];
try{
 const page=await browser.newPage({acceptDownloads:true});page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).origin!==new URL(base).origin)remote.push(r.url());});
 await page.addInitScript(()=>{const Original=window.Worker;window.Worker=class extends Original{};const send=Worker.prototype.postMessage;window.holdJoin=false;window.heldJoin=[];Worker.prototype.postMessage=function(m,...args){if(window.holdJoin&&m.request?.op==='synthesize_join_jobs')window.heldJoin.push(()=>send.call(this,m,...args));else send.call(this,m,...args);};});
 await page.goto(base+'/join.html');
 for(const name of ['warehouse','settlement']){
  const demo=JSON.parse(await readFile(`examples/join-learning/${name}.json`,'utf8'));await page.locator(`[data-join-demo="${name}"]`).click();await page.waitForFunction(()=>!document.querySelector('#learn-join').disabled);
  assert.equal(await page.locator('#examples fieldset').count(),2);await page.locator('#learn-join').click();await page.locator('[data-choose-join="0"]').waitFor();await page.locator('[data-choose-join="0"]').click();
  await page.locator('#apply-join').click();await page.waitForFunction(()=>!document.querySelector('#export-join').disabled);
  assert.deepEqual(await page.locator('#results tbody tr').evaluateAll(rows=>rows.map(row=>[...row.children].map(c=>c.textContent))),demo.expected.rows);
  const waiting=page.waitForEvent('download');await page.locator('#export-join').click();const output=await waiting;await output.saveAs(`artifacts/join-learning/browser-${name}.csv`);
  assert.equal(await readFile(`artifacts/join-learning/browser-${name}.csv`,'utf8'),await readFile(`artifacts/join-learning/${name}-output.csv`,'utf8'));
  const save=page.waitForEvent('download');await page.locator('#save-job').click();const job=await save;await job.saveAs(`artifacts/join-learning/browser-${name}.json`);
  const saved=JSON.parse(await readFile(`artifacts/join-learning/browser-${name}.json`,'utf8'));assert.equal(saved.stages[0].kind,'join');
  await page.locator('#next-left').fill((await page.locator('#next-left').inputValue())+'\n');assert.equal(await page.locator('#export-join').isDisabled(),true);
  checks.push(`${name}: multi-batch learning, explicit choice, unseen batch, CSV download and portable job`);
 }
 await page.locator('[data-join-demo="warehouse"]').click();await page.waitForFunction(()=>!document.querySelector('#learn-join').disabled);
 await page.evaluate(()=>{window.holdJoin=true;});await page.locator('#learn-join').click();await page.waitForFunction(()=>window.heldJoin.length>0);
 await page.locator('#examples textarea').first().fill('sku,warehouse,qty\nchanged,W1,1\n');
 await page.evaluate(()=>{window.holdJoin=false;for(const send of window.heldJoin.splice(0))send();});await page.waitForFunction(()=>document.querySelector('#cancel').hidden);
 assert.equal(await page.locator('[data-choose-join]').count(),0);assert.equal(await page.locator('#apply-join').isDisabled(),true);assert.match(await page.locator('#notice').innerText(),/重新搜索/);
 checks.push('A delayed search result cannot survive a training edit.');
 await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);assert.deepEqual(errors,[]);assert.deepEqual(remote,[]);
 checks.push('390px page fits and does not send data off-origin.');
 await writeFile('artifacts/join-learning-browser-results.json',JSON.stringify({timestamp:new Date().toISOString(),browser:await browser.version(),checks},null,2)+'\n');console.log(JSON.stringify({checks}));
}finally{await browser.close();}
