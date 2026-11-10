import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir}from'node:fs/promises';
import {pathToFileURL}from'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE).href:'playwright');
const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const base=process.env.BASE_URL??'http://127.0.0.1:4173',checks=[],errors=[],remote=[];
await mkdir('artifacts/advanced',{recursive:true});
try{
  const page=await browser.newPage({viewport:{width:1440,height:1000},acceptDownloads:true});
  page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).origin!==new URL(base).origin)remote.push(r.url());});
  await page.goto(base+'/');
  await page.locator('details').evaluate(e=>{e.open=true;});
  for(const name of ['conditional','regex']){
    const scenario=JSON.parse(await readFile(`examples/${name}/scenario.json`,'utf8'));
    await page.locator(`[data-demo="${name}"]`).click();await page.waitForFunction(()=>!document.querySelector('#learn').disabled);
    await page.locator('#learn').click();await page.locator('[data-choose="0"]').waitFor();
    if(name==='regex')assert.match(await page.locator('.candidate').first().innerText(),/capture/);
    if(name==='conditional')assert.match(await page.locator('.candidate').first().innerText(),/if\(/);
    await page.locator('[data-choose="0"]').click();await page.locator('#apply').click();await page.waitForFunction(()=>!document.querySelector('#download-csv').disabled);
    const rows=await page.locator('#results tbody tr').evaluateAll(rows=>rows.map(tr=>tr.children[1].textContent));assert.deepEqual(rows,scenario.fields[0].expected);
    if(name==='regex'){
      await page.locator('#regex-hints').fill('ref=([[:digit:]]{2,})');
      assert.equal(await page.locator('#download-csv').isDisabled(),true);assert.equal(await page.locator('#apply').isDisabled(),true);
    }
    checks.push(`${name}: real Worker learning, top1 program, all held-out rows and stale-hint invalidation`);
  }
  await page.goto(base+'/structure.html');
  for(const name of ['unpivot','records','melt','dynamic-pivot','header-details','labelled-grid']){
    const demo=JSON.parse(await readFile(`examples/structures/${name}.json`,'utf8'));
    await page.locator(`[data-table-demo="${name}"]`).click();await page.waitForFunction(()=>!document.querySelector('#learn').disabled);
    await page.locator('#learn').click();await page.locator('[data-table-choose="0"]').waitFor();await page.locator('[data-table-choose="0"]').click();
    await page.locator('#apply').click();await page.waitForFunction(()=>!document.querySelector('#export').disabled);
    const rows=await page.locator('#results tbody tr').evaluateAll(rows=>rows.map(tr=>[...tr.children].map(td=>td.textContent)));assert.deepEqual(rows,demo.expected.rows,name);
    const wait=page.waitForEvent('download');await page.locator('#export').click();const download=await wait;await download.saveAs(`artifacts/advanced/browser-${name}.csv`);
    assert.equal(await readFile(`artifacts/advanced/browser-${name}.csv`,'utf8'),await readFile(`artifacts/advanced/${name}.csv`,'utf8'));
    if(name==='records'){
      await page.locator('#next').fill('c0\nmissing\nrow\n');assert.equal(await page.locator('#export').isDisabled(),true);
      await page.locator('#apply').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('complete blocks'));
      assert.equal(await page.locator('#export').isDisabled(),true);
    }
    if(name==='melt'){
      await page.screenshot({path:'artifacts/advanced/table-workbench.png',fullPage:true});
      await page.locator('#target').fill(demo.target+'X,Qual 1,9\n');assert.equal(await page.locator('#apply').isDisabled(),true);assert.equal(await page.locator('#save').isDisabled(),true);assert.equal(await page.locator('#export').isDisabled(),true);
    }
    checks.push(`${name}: real table search, explicit choice, unseen table, downloaded CSV; invalid/stale results cannot export`);
  }
  await page.setViewportSize({width:390,height:844});await page.screenshot({path:'artifacts/advanced/table-mobile.png',fullPage:true});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'Table workbench mobile overflow');
  assert.deepEqual(errors,[]);assert.deepEqual(remote,[]);
  checks.push('390px table page has no overflow; no browser errors or remote data requests');
  await writeFile('artifacts/advanced-browser-results.json',JSON.stringify({date:new Date().toISOString(),browser:await browser.version(),checks},null,2)+'\n');
  console.log(JSON.stringify({checks},null,2));
}finally{await browser.close();}
