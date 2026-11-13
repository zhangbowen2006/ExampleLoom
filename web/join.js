const $=id=>document.getElementById(id),el=(tag,text)=>{const n=document.createElement(tag);if(text!=null)n.textContent=text;return n;};
let worker=null,serial=0,pending=new Map(),busy=false,revision=0,selected=null,output=null;
const notice=(message,bad=false)=>{$('notice').textContent=message;$('notice').classList.toggle('error',bad);};
const resetOutput=()=>{output=null;$('export-join').disabled=true;$('results').replaceChildren();$('result-stats').textContent='';};
const controls=()=>{$('learn-join').disabled=busy;$('add-example').disabled=busy||$('examples').children.length>=4;$('apply-join').disabled=busy||!selected;$('save-job').disabled=busy||!selected;$('cancel').hidden=!busy;for(const e of document.querySelectorAll('input[type=file],[data-join-demo],.remove-example'))e.disabled=busy;};
const invalidateTraining=()=>{revision++;selected=null;$('candidates').replaceChildren();$('stats').textContent='';resetOutput();controls();};
const invalidateNext=()=>{revision++;resetOutput();controls();};
function startWorker(){const active=new Worker('worker.js',{type:'module'});worker=active;active.onmessage=({data})=>{if(worker!==active)return;const p=pending.get(data.id);if(!p)return;pending.delete(data.id);data.result.ok?p.resolve(data.result):p.reject(new Error(data.result.error));};active.onerror=e=>{if(worker!==active)return;active.terminate();worker=null;for(const p of pending.values())p.reject(new Error(e.message||'执行进程异常'));pending.clear();};}
const call=request=>{if(!worker)startWorker();return new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});worker.postMessage({id,request});});};
async function task(fn){if(busy)return;busy=true;controls();try{await fn();}catch(e){resetOutput();notice(e.message,true);}finally{busy=false;controls();}}
const parse=async text=>(await call({op:'parse',format:'csv',text})).table;
const download=(text,name,type)=>{const a=el('a'),url=URL.createObjectURL(new Blob([text],{type}));a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
function addExample(values={}){
 const fieldset=el('fieldset'),legend=el('legend',`示例 ${$('examples').children.length+1}`),wrap=el('div');wrap.className='workspace';fieldset.append(legend,wrap);
 for(const [key,label] of [['left','第一张源表 CSV'],['right','第二张源表 CSV'],['output','期望输出 CSV']]){
  const group=el('section'),heading=el('label',label),area=el('textarea');area.rows=5;area.dataset.part=key;area.setAttribute('aria-label',`${label}（${legend.textContent}）`);area.spellcheck=false;area.value=values[key]??'';area.oninput=invalidateTraining;group.append(heading,area);wrap.append(group);
 }
 const remove=el('button','删除这批示例');remove.className='secondary remove-example';remove.onclick=()=>{if($('examples').children.length<=1)return;fieldset.remove();invalidateTraining();};fieldset.append(remove);$('examples').append(fieldset);controls();
}
for(const id of ['left-name','right-name'])$(id).oninput=invalidateTraining;
for(const id of ['next-left','next-right'])$(id).oninput=invalidateNext;
$('add-example').onclick=()=>{if($('examples').children.length<4){addExample();invalidateTraining();}};
for(const side of ['left','right'])$(`file-${side}`).onchange=()=>task(async()=>{const input=$(`file-${side}`),file=input.files[0];input.value='';if(!file)return;if(file.size>4000000)throw new Error('CSV 文件过大');invalidateNext();const generation=revision,text=await file.text();if(generation!==revision)return;$(`next-${side}`).value=text;notice('已打开新表，请运行并核对结果。');});
for(const button of document.querySelectorAll('[data-join-demo]'))button.onclick=()=>task(async()=>{
 invalidateTraining();const generation=revision,response=await fetch(`examples/join-learning/${button.dataset.joinDemo}.json`);if(!response.ok)throw new Error('案例加载失败');const demo=await response.json();if(generation!==revision)return;
 const names=demo.examples[0].sources.map(s=>s.name);$('left-name').value=names[0];$('right-name').value=names[1];$('examples').replaceChildren();
 for(const e of demo.examples){const map=new Map(e.sources.map(s=>[s.name,s.csv]));addExample({left:map.get(names[0]),right:map.get(names[1]),output:e.output});}
 const next=new Map(demo.next.map(s=>[s.name,s.csv]));$('next-left').value=next.get(names[0]);$('next-right').value=next.get(names[1]);notice(`${demo.title}：${demo.description}`);
});
$('learn-join').onclick=()=>task(async()=>{
 invalidateTraining();const generation=revision,left=$('left-name').value.trim(),right=$('right-name').value.trim();
 if(!left||!right||left===right)throw new Error('请输入两个不同的源表名称');
 const snapshots=[...$('examples').children].map(e=>Object.fromEntries([...e.querySelectorAll('textarea')].map(t=>[t.dataset.part,t.value])));
 const examples=[];for(const pair of snapshots){if(!pair.left.trim()||!pair.right.trim()||!pair.output.trim())throw new Error('请填写每批的两张输入和期望输出');examples.push({sources:[{name:left,table:await parse(pair.left)},{name:right,table:await parse(pair.right)}],output:await parse(pair.output)});}
 const start=performance.now(),report=await call({op:'synthesize_join_jobs',examples});if(generation!==revision){notice('示例已修改，请重新搜索。');return;}
 $('stats').textContent=`${Math.round(performance.now()-start)} ms · ${report.evaluations} 种连接假设 · ${report.filter_evaluations} 次筛选尝试 · ${report.truncated?'搜索或候选受限':'已检查有限假设'}`;
 for(const [i,c] of report.candidates.entries()){
  const box=el('div');box.className='candidate';const join=c.job.stages[0],code=el('code',JSON.stringify({left:join.left,right:join.right,keys:[join.spec.left_keys,join.spec.right_keys],kind:join.spec.kind,relationship:join.spec.relationship,after:c.job.stages.slice(1)}));
  const choose=el('button',`选用任务 ${i+1}`);choose.dataset.chooseJoin=String(i);choose.onclick=()=>{revision++;selected=c.job;resetOutput();controls();notice('已选用任务。请在下一批数据上检查后下载。');};box.append(code,choose);$('candidates').append(box);
 }
 notice(report.candidates.length?`找到 ${report.candidates.length} 个与所有示例一致的候选。请检查连接键和未匹配行为。`:'有限搜索内没有找到一致任务，请补充或调整示例。');
});
$('apply-join').onclick=()=>task(async()=>{
 resetOutput();const generation=revision,job=selected,left=$('left-name').value.trim(),right=$('right-name').value.trim(),a=$('next-left').value,b=$('next-right').value;
 const sources=[{name:left,table:await parse(a)},{name:right,table:await parse(b)}],result=await call({op:'run_data_job',job,sources});if(generation!==revision){notice('数据或任务已修改，请重新运行。');return;}
 output=result;const grid=el('table'),head=el('thead'),tr=el('tr'),body=el('tbody');for(const name of result.table.columns)tr.append(el('th',name));head.append(tr);grid.append(head);
 for(const row of result.table.rows.slice(0,200)){const line=el('tr');for(const value of row)line.append(el('td',value));body.append(line);}grid.append(body);$('results').replaceChildren(grid);$('result-stats').textContent=`${result.table.rows.length} 行 · ${result.table.columns.length} 列，预览前200行。`;$('export-join').disabled=false;notice('任务已运行，请核对结果后下载。');
});
$('save-job').onclick=()=>selected&&download(JSON.stringify(selected,null,2),'exampleloom.inferred-job.json','application/json');
$('export-join').onclick=()=>output&&download(output.csv,'exampleloom.join-result.csv','text/csv;charset=utf-8');
$('cancel').onclick=()=>{revision++;worker?.terminate();worker=null;for(const p of pending.values())p.reject(new Error('已取消，请重新操作'));pending.clear();resetOutput();};
addExample();controls();
