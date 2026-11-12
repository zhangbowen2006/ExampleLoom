const $ = id => document.getElementById(id);
const el = (tag,text) => {const node=document.createElement(tag); if(text!=null)node.textContent=text;return node;};
let worker, serial=0, pending=new Map(), busy=false, chosen=false, output=null, revision=0, retained=[], comparedInput=null;
const notice = (message,bad=false) => {$('notice').textContent=message;$('notice').classList.toggle('error',bad);};
const resetOutput=()=>{output=null;$('export').disabled=true;$('results').replaceChildren();$('result-stats').textContent='';};
const resetComparison=()=>{comparedInput=null;$('comparison-summary').textContent='';$('comparison-results').replaceChildren();$('refine-table').hidden=true;};
const controls=()=>{
  $('learn').disabled=busy;
  $('apply').disabled=busy||!chosen;
  $('save').disabled=busy||!chosen;
  $('load').disabled=busy;
  $('next-file').disabled=busy;
  $('cancel').hidden=!busy;
  $('compare-table').disabled=busy||!retained.length;
  $('apply-consensus').disabled=busy||!retained.length;
  $('suggest-table').disabled=busy||!retained.length;
  $('refine-table').disabled=busy||comparedInput===null||$('extra-pairs').children.length>=7;
};
function startWorker(){
  const active = new Worker('worker.js',{type:'module'});
  worker = active;
  active.onmessage=({data})=>{
    if(worker!==active)return;
    const p=pending.get(data.id);if(!p)return;
    pending.delete(data.id);
    data.result.ok?p.resolve(data.result):p.reject(new Error(data.result.error));
  };
  active.onerror=event=>{
    event.preventDefault();
    if(worker!==active)return;
    active.terminate();worker=null;
    for(const p of pending.values())p.reject(new Error('MoonBit Worker 加载或运行失败，请重试。'));
    pending.clear();
  };
}
startWorker();
const call=request=>new Promise((resolve,reject)=>{
  if(!worker)startWorker();
  const id=++serial;pending.set(id,{resolve,reject});
  try{worker.postMessage({id,request});}catch(error){pending.delete(id);reject(error);}
});
async function task(action){if(busy)return;busy=true;controls();try{await action();}catch(error){resetOutput();notice(error.message,true);}finally{busy=false;controls();}}
const invalidate=()=>{revision++;chosen=false;retained=[];$('pipeline').value='';$('candidates').replaceChildren();$('stats').textContent='';resetComparison();resetOutput();controls();};
for(const id of ['training','target','table-patterns','table-intent','layout-rules'])$(id).oninput=invalidate;
const extraPairs = $('extra-pairs');
function addPair(input = '', target = '') {
  if (extraPairs.children.length >= 7) return;
  const pair = el('fieldset');
  pair.append(el('legend', '补充训练表对'));
  for (const [title, value] of [['输入 CSV', input], ['期望输出 CSV', target]]) {
    const label = el('label', title);
    const area = el('textarea');
    area.rows = 3;
    area.spellcheck = false;
    area.value = value;
    area.oninput = invalidate;
    label.append(area);
    pair.append(label);
  }
  const remove = el('button', '移除此对');
  remove.className = 'secondary';
  remove.onclick = () => { pair.remove(); $('add-pair').disabled = false; invalidate(); };
  pair.append(remove);
  extraPairs.append(pair);
  $('add-pair').disabled = extraPairs.children.length === 7;
}
$('add-pair').onclick = () => { addPair(); invalidate(); };
$('next').oninput=()=>{revision++;resetComparison();resetOutput();controls();};
$('pipeline').oninput=()=>{revision++;chosen=Boolean($('pipeline').value.trim());resetComparison();resetOutput();controls();};
$('cancel').onclick=()=>{revision++;worker?.terminate();for(const p of pending.values())p.reject(new Error('操作已取消'));pending.clear();worker=null;};
const parse=async text=>(await call({op:'parse',format:'csv',text})).table;
function download(content,name,type){const link=el('a');const url=URL.createObjectURL(new Blob([content],{type}));link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
for(const button of document.querySelectorAll('[data-table-demo]'))button.onclick=()=>task(async()=>{
  const response=await fetch(`examples/structures/${button.dataset.tableDemo}.json`);if(!response.ok)throw new Error('示例加载失败');const demo=await response.json();
  extraPairs.replaceChildren();$('add-pair').disabled=false;
  for (const pair of demo.additional ?? []) addPair(pair.input, pair.target);
  $('table-intent').value=demo.intent??'infer';$('layout-rules').value=demo.layouts?JSON.stringify(demo.layouts,null,2):'';
  $('table-patterns').value=(demo.patterns ?? []).join('\n');
  invalidate();$('training').value=demo.input;$('target').value=demo.target;$('next').value=demo.next;notice(`${demo.title}：${demo.description}`);
});
for(const button of document.querySelectorAll('[data-pipeline-demo]'))button.onclick=()=>task(async()=>{
  const response=await fetch(`examples/structures/${button.dataset.pipelineDemo}.json`);if(!response.ok)throw new Error('示例加载失败');
  const demo=await response.json();
  extraPairs.replaceChildren();$('add-pair').disabled=false;$('table-patterns').value='';$('table-intent').value='infer';$('layout-rules').value='';
  invalidate();$('training').value=demo.input;$('target').value=demo.target;$('next').value=demo.next;
  $('pipeline').value=JSON.stringify(demo.pipeline,null,2);chosen=true;controls();
  notice(`${demo.title}：${demo.description}示例管道已经填好，请预览并核对。`);
});
$('learn').onclick=()=>task(async()=>{
  invalidate();
  const generation = revision;
  const pairs = [[$('training').value, $('target').value],
    ...[...extraPairs.children].map(pair => [...pair.querySelectorAll('textarea')].map(x => x.value))];
  const layouts = $('layout-rules').value.trim()?JSON.parse($('layout-rules').value):undefined;
  const patterns = $('table-patterns').value.split(/\r?\n/).filter(Boolean);
  const examples = [];
  for (const [input, target] of pairs) {
    if (!input.trim() || !target.trim()) throw new Error('请为每对训练表填写输入和期望输出。');
    examples.push({input: await parse(input), output: await parse(target)});
  }
  const start=performance.now();const report=await call({op:'synthesize_table',examples,patterns,layouts,intent:$('table-intent').value});
  if(revision!==generation){notice('数据已修改，请重新搜索。');return;}
  retained=report.candidates.map(candidate=>candidate.pipeline);
  chosen=false;$('pipeline').value='';resetOutput();$('candidates').replaceChildren();
  $('stats').textContent=`${Math.round(performance.now()-start)} ms · ${report.stats.states} 状态 · ${report.stats.evaluations} 次结构尝试 · ${report.stats.row_searches} 次行学习 · ${report.status}`;
  for(const [i,candidate]of report.candidates.entries()){
    const box=el('div');box.className='candidate';const code=el('code',JSON.stringify(candidate.description));const choose=el('button',`选用管道 ${i+1} · 成本 ${candidate.cost}`);choose.dataset.tableChoose=String(i);
    choose.onclick=()=>{revision++;$('pipeline').value=JSON.stringify(candidate.pipeline,null,2);chosen=true;resetOutput();controls();notice('已选用管道。请在下一批数据上预览并核对。');};box.append(code,choose);$('candidates').append(box);
  }
  notice(report.candidates.length?`${report.candidates.length} 个训练一致候选。${report.truncated?'已触及限额，候选不完整。':''}请明确选择并检查下一批数据。`:'预算内没有找到程序；可补充或简化样例，也可明确编写管道。');
});
$('suggest-table').onclick=()=>task(async()=>{
  const generation=revision,pipelines=retained.slice();
  const sources=[$('training').value,...[...extraPairs.children].map(p=>p.querySelector('textarea').value)];
  const inputs=[];for(const text of sources)inputs.push(await parse(text));
  const result=await call({op:'propose_table_input',pipelines,inputs});
  if(revision!==generation){notice('训练或候选已修改，请重新建议。');return;}
  if(!result.suggestion){notice('有限探针中未找到可用分歧，不证明候选普遍等价。');return;}
  revision++;resetComparison();resetOutput();chosen=false;$('pipeline').value='';
  $('next').value=result.suggestion.csv;
  const names={duplicate_rows:'重复整批行',reverse_rows:'反转行序',drop_first:'去掉首行',drop_last:'去掉末行',first_row:'仅取首行'};
  notice(`这是构造的补样输入，可跳过（训练表 ${result.suggestion.source_index+1}：${names[result.suggestion.mutation]}）。请先确认符合业务格式，再比较候选；正确目标需由你独立填写。`);
});
$('compare-table').onclick=()=>task(async()=>{
  resetComparison();resetOutput();
  const generation=revision, input=$('next').value, pipelines=retained.slice();
  const table=await parse(input);
  if(revision!==generation){notice('数据已修改，请重新比较。');return;}
  const result=await call({op:'compare_table_candidates',pipelines,table});
  if(revision!==generation){notice('数据或候选已修改，请重新比较。');return;}
  const messages={
    consistent:'保留候选在这批数据上结果相同。这不证明结果正确，请核对目标或补充样例。',
    disagreement:`发现 ${result.groups.length} 种不同结果（包含执行错误）。请核对意图，补充这批数据的正确目标表后重新搜索。`,
    all_failed:'这批数据上没有候选成功。请检查下方错误，补充完整训练表或编辑管道。',
  };
  $('comparison-summary').textContent=messages[result.status];
  const difference=result.first_difference;
  if(difference){
    let text={columns:'前两组结果的列名、列数或列顺序不同。',row_count:'前两组结果的行数不同。',error:'前两组结果的差异涉及执行错误，原因见下方。'}[difference.kind];
    if(difference.kind==='cell'){
      const values=result.groups.slice(0,2).map(group=>JSON.stringify(group.prediction.table.rows[difference.row_index][difference.column_index]).slice(0,140));
      text=`首个差异位于数据第 ${difference.row_index+1} 行、第 ${difference.column_index+1} 列：${values.join(' / ')}。`;
    }
    const line=el('p',text);line.className='hint';$('comparison-results').append(line);
  }
  for(const group of result.groups){
    const box=el('section');box.className='candidate comparison-group';
    box.append(el('h3',`候选 ${group.candidates.map(i=>i+1).join('、')}`));
    if(group.prediction.ok){
      const predicted=group.prediction.table;
      box.append(el('p',`${predicted.rows.length} 行 · ${predicted.columns.length} 列；预览前 5 行、8 列，比较使用全部单元格。`));
      const wrap=el('div'),grid=el('table'),head=el('thead'),tr=el('tr'),body=el('tbody');wrap.className='table-wrap';
      for(const name of predicted.columns.slice(0,8))tr.append(el('th',name));head.append(tr);grid.append(head);
      for(const row of predicted.rows.slice(0,5)){const line=el('tr');for(const value of row.slice(0,8))line.append(el('td',value));body.append(line);}
      grid.append(body);wrap.append(grid);box.append(wrap);
    }else{
      const message=el('p',group.prediction.error);message.className='error-cell';box.append(message);
    }
    $('comparison-results').append(box);
  }
  comparedInput=input;$('refine-table').hidden=false;
  notice('比较完成。结果没有自动选用，也没有作为正确答案加入训练。');
});
$('refine-table').onclick=()=>{
  if(busy||comparedInput===null||extraPairs.children.length>=7)return;
  const input=comparedInput;addPair(input,'');invalidate();
  const target=extraPairs.lastElementChild.querySelectorAll('textarea')[1];
  target.focus();target.scrollIntoView({block:'center',behavior:'smooth'});
  notice('已添加这批输入，请独立填写正确的期望输出，再搜索。');
};
function showTable(result){
  output=result;const grid=el('table'),thead=el('thead'),head=el('tr'),body=el('tbody');for(const name of result.table.columns)head.append(el('th',name));thead.append(head);grid.append(thead);
  for(const row of result.table.rows.slice(0,200)){const tr=el('tr');for(const value of row)tr.append(el('td',value));body.append(tr);}grid.append(body);$('results').replaceChildren(grid);
  $('result-stats').textContent=`${result.table.rows.length} 行 · ${result.table.columns.length} 列；预览前 200 行，下载包含全部记录。`;$('export').disabled=false;
}
$('apply').onclick=()=>task(async()=>{
  resetOutput();const generation=revision;const pipeline=JSON.parse($('pipeline').value), table=await parse($('next').value);
  const result=await call({op:'transform',pipeline,table});if(revision!==generation){notice('数据或管道已修改，请重新预览。');return;}
  showTable(result);notice('转换完成，请核对结果后下载。');
});
$('apply-consensus').onclick=()=>task(async()=>{
  resetOutput();const generation=revision,pipelines=retained.slice(),table=await parse($('next').value);
  const result=await call({op:'execute_table',pipelines,table});
  if(revision!==generation){notice('数据或候选已修改，请重新检查这一批。');return;}
  showTable(result);notice('所有保留候选在这一整批数据上执行成功且结果相同。请核对后下载；新批次必须重新检查。');
});
$('save').onclick=()=>task(async()=>{
  const generation=revision;
  const r=await call({op:'validate_pipeline',pipeline:JSON.parse($('pipeline').value)});
  if(revision!==generation){notice('数据或管道已修改，请重新选用后保存。');return;}
  download(JSON.stringify(r.pipeline,null,2),'exampleloom.pipeline.json','application/json');
});
$('export').onclick=()=>output&&download(output.csv,'exampleloom.structure.csv','text/csv;charset=utf-8');
$('load').onchange=e=>task(async()=>{
  const file=e.target.files[0];e.target.value='';if(!file)return;
  if(file.size>262144)throw new Error('管道文件过大');
  const generation=revision;
  const r=await call({op:'validate_pipeline',pipeline:JSON.parse(await file.text())});
  if(revision!==generation){notice('数据或管道已修改，请重新载入。');return;}
  invalidate();$('pipeline').value=JSON.stringify(r.pipeline,null,2);chosen=true;
  notice('已载入管道，请在下一批数据上预览。');
});
$('next-file').onchange=e=>task(async()=>{
  const file=e.target.files[0];e.target.value='';if(!file)return;
  if(file.size>4000000)throw new Error('CSV 文件过大');
  revision++;resetComparison();resetOutput();controls();const generation=revision;
  const text=await file.text();
  if(revision!==generation){notice('数据已修改，请重新打开 CSV。');return;}
  $('next').value=text;
});
