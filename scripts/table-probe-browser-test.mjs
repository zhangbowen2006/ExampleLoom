import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE).href:'playwright');
const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const base=process.env.BASE_URL??'http://127.0.0.1:4173';const checks=[],errors=[];
try{
  const page=await browser.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{
    const Original=window.Worker;window.Worker=class extends Original{};
    window.holdProbes=false;window.heldProbes=[];
    const send=Worker.prototype.postMessage;
    Worker.prototype.postMessage=function(message,...args){
      if(window.holdProbes&&message.request?.op==='propose_table_input')window.heldProbes.push(()=>send.call(this,message,...args));
      else send.call(this,message,...args);
    };
  });
  await page.goto(base+'/structure.html');
  await page.locator('#layout-rules').evaluate(e=>{e.closest('details').open=true;});
  const learn=async()=>{await page.locator('#learn').click();await page.locator('[data-table-choose="0"]').waitFor();};
  await page.locator('#training').fill('c0\nA\n');await page.locator('#target').fill('c0\nA\n');
  await learn();
  await page.locator('#suggest-table').click();
  await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('构造的补样输入'));
  assert.equal((await page.locator('#next').inputValue()).replaceAll('\r',''),'c0\nA\nA\n');
  assert.equal(await page.locator('#pipeline').inputValue(),'');assert.equal(await page.locator('#apply').isDisabled(),true);
  assert.equal(await page.locator('#export').isDisabled(),true);assert.equal(await page.locator('#extra-pairs fieldset').count(),0);
  checks.push('Input-only constructed suggestion leaves target, choice and export untouched.');
  await page.locator('#compare-table').click();await page.locator('.comparison-group').first().waitFor();
  await page.locator('#refine-table').click();
  const pair=page.locator('#extra-pairs fieldset').last();
  assert.equal(await pair.locator('textarea').last().inputValue(),'');
  await pair.locator('textarea').last().fill('c0,c1\nA,A\n');
  await learn();await page.locator('[data-table-choose="0"]').click();
  await page.locator('#next').fill('c0\nX\nY\nZ\n');await page.locator('#apply').click();
  await page.waitForFunction(()=>!document.querySelector('#export').disabled);
  assert.deepEqual(await page.locator('#results tbody tr').evaluateAll(rows=>rows.map(r=>[...r.children].map(c=>c.textContent))),[['X','Y','Z']]);
  checks.push('Independent target refinement learns a reusable whole-table program and runs an unseen third batch.');
  for(const edit of ['training','layout-rules','table-intent']){
    await page.locator('[data-table-demo="layout-people"]').click();await learn();
    const rules=await page.locator('#layout-rules').inputValue();
    await page.evaluate(()=>{window.holdProbes=true;});await page.locator('#suggest-table').click();
    await page.waitForFunction(()=>window.heldProbes.length>0);
    if(edit==='table-intent')await page.locator('#table-intent').selectOption('flatten_all');
    else await page.locator('#'+edit).fill((await page.locator('#'+edit).inputValue())+' ');
    const before=await page.locator('#next').inputValue();
    await page.evaluate(()=>{window.holdProbes=false;for(const send of window.heldProbes.splice(0))send();});
    await page.waitForFunction(()=>document.querySelector('#cancel').hidden);
    assert.equal(await page.locator('#next').inputValue(),before);
    assert.equal(await page.locator('#suggest-table').isDisabled(),true);
    assert.match(await page.locator('#notice').innerText(),/重新建议/);
    if(edit!=='layout-rules')assert.equal(await page.locator('#layout-rules').inputValue(),rules);
  }
  checks.push('Delayed suggestions cannot survive training, explicit layout or intent edits.');
  await page.locator('[data-table-demo="layout-people"]').click();await learn();
  const rules=await page.locator('#layout-rules').inputValue();
  await page.locator('#compare-table').click();await page.locator('.comparison-group').first().waitFor();
  await page.locator('#refine-table').click();assert.equal(await page.locator('#layout-rules').inputValue(),rules);
  assert.equal(await page.locator('#extra-pairs fieldset').last().locator('textarea').last().inputValue(),'');
  checks.push('Multi-schema refinement preserves explicit rules and always leaves a new target blank.');
  assert.deepEqual(errors,[]);
  await mkdir('artifacts',{recursive:true});await writeFile('artifacts/table-probe-browser-results.json',JSON.stringify({timestamp:new Date().toISOString(),browser:await browser.version(),checks},null,2)+'\n');
  console.log(JSON.stringify({checks}));
}finally{await browser.close();}
