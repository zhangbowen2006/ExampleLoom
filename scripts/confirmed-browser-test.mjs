import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE).href:'playwright');
const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const checks=[];try{
 const page=await browser.newPage();
 await page.addInitScript(()=>{const Original=window.Worker;window.Worker=class extends Original{};const send=Worker.prototype.postMessage;window.holdExecution=false;window.heldExecution=[];Worker.prototype.postMessage=function(m,...args){if(window.holdExecution&&m.request?.op==='execute_table')window.heldExecution.push(()=>send.call(this,m,...args));else send.call(this,m,...args);};});
 await page.goto((process.env.BASE_URL??'http://127.0.0.1:4173')+'/structure.html');
 await page.locator('#training').fill('c0\nA\n');await page.locator('#target').fill('c0\nA\n');await page.locator('#learn').click();await page.locator('[data-table-choose="0"]').waitFor();
 await page.locator('#next').fill('c0\nA\n');await page.locator('#apply-consensus').click();await page.waitForFunction(()=>!document.querySelector('#export').disabled);
 assert.equal(await page.locator('#pipeline').inputValue(),'');assert.equal(await page.locator('#save').isDisabled(),true);
 assert.match(await page.locator('#notice').innerText(),/新批次必须重新检查/);
 checks.push('Observed batch consensus exports without silently selecting or saving a program.');
 await page.locator('#next').fill('c0\nA\nB\n');assert.equal(await page.locator('#export').isDisabled(),true);
 await page.locator('#apply-consensus').click();await page.waitForFunction(()=>document.querySelector('#cancel').hidden);
 assert.equal(await page.locator('#export').isDisabled(),true);assert.match(await page.locator('#notice').innerText(),/disagree/);
 checks.push('Different new-batch predictions block unattended export.');
 await page.locator('#next').fill('c0\nA\n');await page.evaluate(()=>{window.holdExecution=true;});await page.locator('#apply-consensus').click();await page.waitForFunction(()=>window.heldExecution.length>0);
 await page.locator('#next').fill('c0\nnew\nrows\n');await page.evaluate(()=>{window.holdExecution=false;for(const send of window.heldExecution.splice(0))send();});await page.waitForFunction(()=>document.querySelector('#cancel').hidden);
 assert.equal(await page.locator('#export').isDisabled(),true);assert.match(await page.locator('#notice').innerText(),/重新检查/);
 checks.push('An in-flight old consensus cannot restore export after a batch edit.');
 await page.locator('[data-table-choose="0"]').click();await page.locator('#apply').click();await page.waitForFunction(()=>!document.querySelector('#export').disabled);
 checks.push('Explicit user selection remains available for a disagreeing batch.');
 await writeFile('artifacts/confirmed-browser-results.json',JSON.stringify({browser:await browser.version(),checks},null,2)+'\n');console.log(JSON.stringify({checks}));
}finally{await browser.close();}
