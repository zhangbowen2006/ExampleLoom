const $ = id => document.getElementById(id);
const el = (tag,text) => {const node=document.createElement(tag); if(text!=null)node.textContent=text;return node;};
let worker, serial=0, pending=new Map(), busy=false, chosen=false, output=null, revision=0;
const notice = (message,bad=false) => {$('notice').textContent=message;$('notice').classList.toggle('error',bad);};
const resetOutput=()=>{output=null;$('export').disabled=true;$('results').replaceChildren();$('result-stats').textContent='';};
const controls=()=>{$('learn').disabled=busy;$('apply').disabled=busy||!chosen;$('save').disabled=busy||!chosen;$('cancel').hidden=!busy;};
function startWorker(){worker=new Worker('worker.js',{type:'module'});worker.onmessage=({data})=>{const p=pending.get(data.id);if(!p)return;pending.delete(data.id);data.result.ok?p.resolve(data.result):p.reject(new Error(data.result.error));};worker.onerror=()=>{for(const p of pending.values())p.reject(new Error('MoonBit Worker 加载或运行失败'));pending.clear();};}
startWorker();
const call=request=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});worker.postMessage({id,request});});
async function task(action){if(busy)return;busy=true;controls();try{await action();}catch(error){resetOutput();notice(error.message,true);}finally{busy=false;controls();}}
const invalidate=()=>{revision++;chosen=false;$('pipeline').value='';$('candidates').replaceChildren();$('stats').textContent='';resetOutput();controls();};
for(const id of ['training','target'])$(id).oninput=invalidate;
$('next').oninput=()=>{revision++;resetOutput();};
$('pipeline').oninput=()=>{revision++;chosen=Boolean($('pipeline').value.trim());resetOutput();controls();};
$('cancel').onclick=()=>{revision++;worker.terminate();for(const p of pending.values())p.reject(new Error('操作已取消'));pending.clear();startWorker();};
const parse=async text=>(await call({op:'parse',format:'csv',text})).table;
function download(content,name,type){const link=el('a');const url=URL.createObjectURL(new Blob([content],{type}));link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
for(const button of document.querySelectorAll('[data-table-demo]'))button.onclick=()=>task(async()=>{
  const response=await fetch(`examples/structures/${button.dataset.tableDemo}.json`);if(!response.ok)throw new Error('示例加载失败');const demo=await response.json();
  invalidate();$('training').value=demo.input;$('target').value=demo.target;$('next').value=demo.next;notice(`${demo.title}：${demo.description}`);
});
$('learn').onclick=()=>task(async()=>{
  const generation=revision;const input=await parse($('training').value), target=await parse($('target').value);
  const start=performance.now();const report=await call({op:'synthesize_table',examples:[{input,output:target}]});
  if(revision!==generation){notice('数据已修改，请重新搜索。');return;}
  chosen=false;$('pipeline').value='';resetOutput();$('candidates').replaceChildren();
  $('stats').textContent=`${Math.round(performance.now()-start)} ms · ${report.stats.states} 状态 · ${report.stats.evaluations} 次结构尝试 · ${report.stats.row_searches} 次行学习 · ${report.status}`;
  for(const [i,candidate]of report.candidates.entries()){
    const box=el('div');box.className='candidate';const code=el('code',JSON.stringify(candidate.description));const choose=el('button',`选用管道 ${i+1}`);choose.dataset.tableChoose=String(i);
    choose.onclick=()=>{revision++;$('pipeline').value=JSON.stringify(candidate.pipeline,null,2);chosen=true;resetOutput();controls();notice('已选用管道。请在下一批数据上预览并核对。');};box.append(code,choose);$('candidates').append(box);
  }
  notice(report.candidates.length?`${report.candidates.length} 个训练一致候选。${report.truncated?'已触及限额，候选不完整。':''}请明确选择并检查下一批数据。`:'预算内没有找到程序；可补充或简化样例，也可明确编写管道。');
});
$('apply').onclick=()=>task(async()=>{
  resetOutput();const generation=revision;const pipeline=JSON.parse($('pipeline').value), table=await parse($('next').value);
  const result=await call({op:'transform',pipeline,table});if(revision!==generation){notice('数据或管道已修改，请重新预览。');return;}
  output=result;const grid=el('table'),thead=el('thead'),head=el('tr'),body=el('tbody');for(const name of result.table.columns)head.append(el('th',name));thead.append(head);grid.append(thead);
  for(const row of result.table.rows.slice(0,200)){const tr=el('tr');for(const value of row)tr.append(el('td',value));body.append(tr);}grid.append(body);$('results').replaceChildren(grid);
  $('result-stats').textContent=`${result.table.rows.length} 行 · ${result.table.columns.length} 列；预览前 200 行，下载包含全部记录。`;$('export').disabled=false;notice('转换完成，请核对结果后下载。');
});
$('save').onclick=()=>task(async()=>{const r=await call({op:'validate_pipeline',pipeline:JSON.parse($('pipeline').value)});download(JSON.stringify(r.pipeline,null,2),'exampleloom.pipeline.json','application/json');});
$('export').onclick=()=>output&&download(output.csv,'exampleloom.structure.csv','text/csv;charset=utf-8');
$('load').onchange=e=>task(async()=>{const file=e.target.files[0];if(!file)return;if(file.size>262144)throw new Error('管道文件过大');const r=await call({op:'validate_pipeline',pipeline:JSON.parse(await file.text())});invalidate();$('pipeline').value=JSON.stringify(r.pipeline,null,2);chosen=true;e.target.value='';notice('已载入管道，请在下一批数据上预览。');});
$('next-file').onchange=e=>task(async()=>{const file=e.target.files[0];if(!file)return;if(file.size>4000000)throw new Error('CSV 文件过大');revision++;resetOutput();$('next').value=await file.text();e.target.value='';});
