const $=id=>document.getElementById(id),el=(tag,text)=>{const e=document.createElement(tag);if(text!=null)e.textContent=text;return e;};
let worker=null,serial=0,pending=new Map(),busy=false,revision=0,job=null,dirty=true,output=null;
const notice=(text,bad=false)=>{$('notice').textContent=text;$('notice').classList.toggle('error',bad);};
const controls=()=>{$('run-job').disabled=busy||dirty||!job;$('save-job').disabled=busy||dirty||!job;$('load-job').disabled=busy;$('configure').disabled=busy;$('cancel').hidden=!busy;for(const e of document.querySelectorAll('input[type=file], [data-job-demo]'))e.disabled=busy;};
const reset=()=>{output=null;$('export-job').disabled=true;$('results').replaceChildren();$('stats').textContent='';};
const invalidate=(configuration=false)=>{revision++;reset();dirty=dirty||configuration;controls();};
function startWorker(){
 const active=new Worker('worker.js',{type:'module'});worker=active;
 active.onmessage=({data})=>{if(worker!==active)return;const p=pending.get(data.id);if(!p)return;pending.delete(data.id);data.result.ok?p.resolve(data.result):p.reject(new Error(data.result.error));};
 active.onerror=e=>{if(worker!==active)return;active.terminate();worker=null;for(const p of pending.values())p.reject(new Error(e.message||'执行进程异常，请重试'));pending.clear();};
}
const call=request=>{if(!worker)startWorker();return new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});worker.postMessage({id,request});});};
async function task(fn){if(busy)return;busy=true;controls();try{await fn();}catch(e){reset();notice(e.message,true);}finally{busy=false;controls();}}
const download=(text,name,type)=>{const a=el('a');const url=URL.createObjectURL(new Blob([text],{type}));a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
function configure(value,csv){
 job=value;dirty=false;$('job').value=JSON.stringify(value,null,2);$('sources').replaceChildren();$('stages').replaceChildren();
 for(const stage of value.stages){const line=el('p',`${stage.name} · ${{join:'按键连接',concat:'按列名合表',transform:'运行表格程序'}[stage.kind]}`);line.className='hint';$('stages').append(line);}
 for(const name of value.sources){
  const panel=el('section'),title=el('h3',name),area=el('textarea'),label=el('label','打开 CSV'),file=el('input');panel.className='panel';area.rows=7;area.dataset.source=name;area.setAttribute('aria-label',`源表 ${name}`);area.spellcheck=false;area.value=csv.get(name)??'';area.oninput=()=>invalidate();
  file.type='file';file.accept='.csv,.txt';label.className='file-button';label.append(file);
  file.onchange=()=>task(async()=>{const selected=file.files[0];file.value='';if(!selected)return;if(selected.size>4000000)throw new Error('CSV 文件过大');invalidate();const generation=revision,text=await selected.text();if(generation!==revision)return;area.value=text;notice(`已打开源表 ${name}，请运行任务。`);});
  panel.append(title,area,label);$('sources').append(panel);
 }
 controls();
}
const sourceText=()=>new Map([...$('sources').querySelectorAll('textarea')].map(e=>[e.dataset.source,e.value]));
for(const button of document.querySelectorAll('[data-job-demo]'))button.onclick=()=>task(async()=>{
 invalidate(true);const generation=revision,response=await fetch(`examples/jobs/${button.dataset.jobDemo}.json`);if(!response.ok)throw new Error('案例加载失败');const demo=await response.json(),validated=await call({op:'validate_data_job',job:demo.job});if(generation!==revision)return;
 configure(validated.job,new Map(demo.sources.map(s=>[s.name,s.csv])));$('job-description').textContent=demo.description;notice('案例已填入。可以替换各张源表，再运行并核对结果。');
});
$('job').oninput=()=>invalidate(true);
$('configure').onclick=()=>task(async()=>{const generation=revision,validated=await call({op:'validate_data_job',job:JSON.parse($('job').value)});if(generation!==revision)return;configure(validated.job,sourceText());notice('任务配置已应用，源表按名称保留。');});
$('load-job').onchange=()=>task(async()=>{const file=$('load-job').files[0];$('load-job').value='';if(!file)return;if(file.size>1048576)throw new Error('任务文件过大');invalidate(true);const generation=revision,validated=await call({op:'validate_data_job',job:JSON.parse(await file.text())});if(generation!==revision)return;configure(validated.job,sourceText());notice('任务规则已载入，请填写或确认源表。');});
$('save-job').onclick=()=>{if(job&&!dirty)download(JSON.stringify(job,null,2),'exampleloom.job.json','application/json');};
$('run-job').onclick=()=>task(async()=>{
 reset();const generation=revision,configuration=job,inputs=sourceText(),sources=[];
 for(const name of configuration.sources){const parsed=await call({op:'parse',format:'csv',text:inputs.get(name)});sources.push({name,table:parsed.table});}
 const result=await call({op:'run_data_job',job:configuration,sources});if(generation!==revision){notice('源表或任务已修改，请重新运行。');return;}
 output=result;const grid=el('table'),thead=el('thead'),head=el('tr'),body=el('tbody');for(const name of result.table.columns)head.append(el('th',name));thead.append(head);grid.append(thead);
 for(const row of result.table.rows.slice(0,200)){const tr=el('tr');for(const value of row)tr.append(el('td',value));body.append(tr);}grid.append(body);$('results').replaceChildren(grid);
 $('stats').textContent=`完成 ${result.completed_stages} 个阶段 · ${result.table.rows.length} 行 · ${result.table.columns.length} 列；预览前200行，下载包含完整结果。`;$('export-job').disabled=false;notice('任务已完成。请核对匹配状态、金额及行列，再下载。');
});
$('export-job').onclick=()=>output&&download(output.csv,'exampleloom.job-result.csv','text/csv;charset=utf-8');
$('cancel').onclick=()=>{invalidate();worker?.terminate();worker=null;for(const p of pending.values())p.reject(new Error('已取消，请重新运行'));pending.clear();};
controls();
