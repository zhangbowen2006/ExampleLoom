const $ = id => document.getElementById(id);
let worker, serial = 0, pending = new Map();
let table = null, labels = new Map(), report = null, recipe = null, batch = null, demo = null;
let busy = false, sourceDirty = false;
let staleFields = new Set(), labelsByField = new Map();
function startWorker() {
  worker = new Worker('./worker.js', { type: 'module' });
  worker.onmessage = ({ data: { id, result } }) => {
    const pair = pending.get(id); if (!pair) return;
    pending.delete(id);
    if (result.ok) pair.resolve(result); else pair.reject(new Error(result.error));
  };
  worker.onerror = () => {
    for (const p of pending.values()) p.reject(new Error('核心加载失败，请先运行 node scripts/build.mjs，并通过本地 HTTP 地址打开。'));
    pending.clear();
  };
}
startWorker();
function call(request) {
  return new Promise((resolve, reject) => { const id = ++serial; pending.set(id, { resolve, reject }); worker.postMessage({ id, request }); });
}
function notice(text, error = false) { $('notice').textContent = text; $('notice').classList.toggle('error', error); }
function el(tag, text, className) { const e = document.createElement(tag); if (text != null) e.textContent = text; if (className) e.className = className; return e; }
function empty(id, text) { $(id).replaceChildren(el('div', text, 'empty')); }
function resetResults() {
  batch = null; $('download-csv').disabled = true; $('download-report').disabled = true; $('result-stats').textContent = '';
  empty('results', '规则或输入发生变化，请重新预览整批结果。');
}
function resetSearch() {
  report = null; $('candidate-count').textContent = ''; $('search-stats').textContent = ''; $('search-boundary').hidden = true; $('ambiguity-count').textContent = '';
  empty('candidates', '标注样例后，点击生成候选。'); empty('disagreements', '生成候选后检查歧义；共识不等于正确性。');
}
function updateControls() {
  $('label-count').textContent = `${labels.size} 个样例`;
  $('learn').disabled = !table || !labels.size || busy || sourceDirty;
  $('apply').disabled = !table || !recipe?.outputs.length || busy || sourceDirty || staleFields.size > 0;
  $('save-recipe').disabled = !recipe?.outputs.length || busy || staleFields.size > 0;
  $('download-csv').disabled = !batch || batch.failures > 0 || busy || staleFields.size > 0;
  $('download-report').disabled = !batch || busy || staleFields.size > 0;
}
function labelsChanged() {
  const name = $('output-name').value.trim();
  labelsByField.set(name, new Map(labels));
  if (recipe?.outputs.some(f => f.name === name)) {
    staleFields.add(name);
    notice(`字段 ${name} 的样例已修改，请重新生成候选并选定规则。其他字段已保留。`, true);
  }
  resetSearch(); resetResults(); renderRecipe();
}
async function task(fn) {
  if (busy) return;
  busy = true;
  const controls = [...document.querySelectorAll('button,input,select,textarea')].filter(e => e.id !== 'cancel').map(e => [e, e.disabled]);
  for (const [e] of controls) e.disabled = true;
  $('cancel').hidden = false;
  try { await fn(); } catch (e) { notice(e.message, true); }
  finally {
    busy = false; $('cancel').hidden = true;
    for (const [e, disabled] of controls) if (e.isConnected) e.disabled = disabled;
    updateControls();
  }
}
$('cancel').onclick = () => { worker.terminate(); for (const p of pending.values()) p.reject(new Error('操作已取消。')); pending.clear(); startWorker(); };
function dataGrid() {
  const grid = el('table'), head = el('tr'), body = el('tbody'), thead = el('thead');
  for (const title of ['样例', '#', ...table.columns, '期望输出']) head.append(el('th', title));
  thead.append(head); grid.append(thead);
  const visible = new Set(Array.from({ length: Math.min(table.rows.length, 200) }, (_, i) => i));
  for (const i of labels.keys()) visible.add(i);
  for (const i of [...visible].sort((a, b) => a - b)) {
    const tr = el('tr'); tr.id = `row-${i}`; tr.classList.toggle('labelled', labels.has(i));
    const check = el('input'); check.type = 'checkbox'; check.checked = labels.has(i); check.setAttribute('aria-label', `第 ${i + 1} 行用作样例`);
    const answer = el('input'); answer.type = 'text'; answer.value = labels.get(i) ?? ''; answer.setAttribute('aria-label', `第 ${i + 1} 行期望输出`);
    const changed = () => { if (check.checked) labels.set(i, answer.value); else labels.delete(i); tr.classList.toggle('labelled', check.checked); labelsChanged(); };
    check.onchange = changed; answer.oninput = () => { check.checked = true; changed(); };
    const checkCell = el('td'); checkCell.append(check); tr.append(checkCell, el('td', String(i + 1), 'row-no'));
    for (const value of table.rows[i]) tr.append(el('td', value));
    const cell = el('td'); cell.append(answer); tr.append(cell); body.append(tr);
  }
  grid.append(body); $('input-grid').replaceChildren(grid);
  if (table.rows.length > 200) $('input-grid').append(el('div', '显示前 200 行及已标注行；批量转换包含整表，歧义检查覆盖前 5000 行。', 'row-limit'));
  updateControls();
}
async function parseSource() {
  const parsed = await call({ op: 'parse', format: $('format').value, text: $('source').value });
  table = parsed.table; sourceDirty = false; labels = new Map(); labelsByField = new Map(); resetSearch(); resetResults();
  $('table-stats').textContent = `${table.rows.length} 行 · ${table.columns.length} 列`;
  dataGrid(); renderRecipe(); notice(`已导入 ${table.rows.length} 行。标注几个输出样例，或载入之前保存的配方。`);
}
function dirtySource() { sourceDirty = true; resetSearch(); resetResults(); updateControls(); notice('源文本或格式已更改，请点击“读取数据”。'); }
$('source').oninput = dirtySource; $('format').onchange = dirtySource;
$('parse').onclick = () => task(async () => { demo = null; $('demo-field').hidden = true; await parseSource(); });
$('data-file').onchange = e => task(async () => {
  const file = e.target.files[0]; if (!file) return;
  if (file.size > 8000000) throw new Error('文件过大，请先缩小到约 2 MB 文本规模。');
  $('source').value = await file.text(); $('format').value = /\.(jsonl|ndjson)$/i.test(file.name) ? 'jsonl' : 'csv';
  sourceDirty = true; demo = null; $('demo-field').hidden = true; await parseSource(); e.target.value = '';
});
function useDemoField(index) {
  const field = demo.fields[index]; $('output-name').value = field.name;
  labels = new Map(labelsByField.get(field.name) ?? field.labels.map(e => [e.row, e.output])); resetSearch(); dataGrid();
}
for (const button of document.querySelectorAll('[data-demo]')) button.onclick = () => task(async () => {
  const name = button.dataset.demo;
  const response = await fetch(`./examples/${name}/scenario.json`); if (!response.ok) throw new Error('示例加载失败');
  const scenario = await response.json();
  const source = await fetch(`./examples/${name}/${scenario.file}`); if (!source.ok) throw new Error('示例数据加载失败');
  $('source').value = await source.text(); $('format').value = 'csv'; recipe = null; staleFields.clear();
  await parseSource(); demo = scenario;
  $('demo-field').replaceChildren(...demo.fields.map((f, i) => { const option = el('option', f.name); option.value = String(i); return option; }));
  $('demo-field').hidden = demo.fields.length < 2; useDemoField(0);
  for (const b of document.querySelectorAll('[data-demo]')) b.classList.toggle('active', b === button);
  notice(`${scenario.title}：${scenario.description} 已填入两个样例；其他行为留出验证数据。`);
});
$('demo-field').onchange = () => useDemoField(Number($('demo-field').value));
$('output-name').oninput = () => resetSearch();
$('learn').onclick = () => task(async () => {
  if (!labels.size || labels.size > 32) throw new Error('请选择 1–32 个样例。');
  if (!$('output-name').value.trim()) throw new Error('请填写输出字段名。');
  notice('正在搜索与所有样例一致的程序…');
  const start = performance.now();
  report = await call({ op: 'synthesize', examples: [...labels].map(([i, output]) => ({ input: table.rows[i], output })), rows: table.rows.slice(0, 5000) });
  $('candidate-count').textContent = `${report.candidates.length} 个候选`;
  $('search-stats').textContent = `${Math.round(performance.now() - start)} ms · ${report.stats.atom_evaluations} 次原子尝试 · ${report.stats.steps} 次搜索步骤`;
  $('search-boundary').hidden = false;
  $('search-boundary').textContent = report.truncated ? `已触及搜索限额（${report.status}）。这里只显示部分候选，不能据此认定唯一解或无解。` : '已遍历本次观察到的有限搜索范围；不代表覆盖全部可能的程序，也不证明未见数据正确。';
  renderCandidates(); renderDisagreements();
  notice(report.candidates.length ? '候选已生成。先看不同解释，再明确选择一条规则加入配方。' : '当前范围内没有找到候选。请检查样例或缩小目标；本版本不支持任意转换。');
});
function renderCandidates() {
  if (!report.candidates.length) { empty('candidates', '没有找到候选。'); return; }
  $('candidates').replaceChildren();
  report.candidates.forEach((candidate, i) => {
    const box = el('div', null, 'candidate'), head = el('div', null, 'candidate-head'), choose = el('button', '选用此规则'); choose.dataset.choose = String(i);
    choose.onclick = () => {
      const name = $('output-name').value.trim();
      if (!name) { notice('请填写输出字段名。', true); return; }
      if (recipe?.outputs.length && JSON.stringify(recipe.columns) !== JSON.stringify(table.columns)) { notice('当前配方基于另一组输入列。请移除已有输出字段，再为这组列建立新配方。', true); return; }
      if (!recipe?.outputs.length) recipe = { version: 1, columns: [...table.columns], outputs: [] };
      recipe.outputs = [...recipe.outputs.filter(f => f.name !== name), { name, expression: candidate.expression }];
      staleFields.delete(name);
      renderRecipe(); resetResults(); notice(`已将候选 ${i + 1} 加入字段 ${name}。请预览整批结果，也可以再添加一个输出字段。`);
    };
    head.append(el('span', `候选 ${String(i + 1).padStart(2, '0')} · 复杂度 ${candidate.cost}`), choose);
    box.append(head, el('code', candidate.description)); $('candidates').append(box);
  });
}
function renderDisagreements() {
  const suggestions = report.disagreements.filter(d => !labels.has(d.row_index));
  $('ambiguity-count').textContent = `${suggestions.length} 个待检查行`;
  if (!suggestions.length) { empty('disagreements', '保留的候选在已检查行上没有未标注分歧。仍需检查新数据；这不是正确性证明。'); return; }
  $('disagreements').replaceChildren();
  for (const d of suggestions) {
    const box = el('div', null, 'disagreement');
    box.append(el('div', `第 ${d.row_index + 1} 行 · ${table.rows[d.row_index].join(' | ')}`, 'input'));
    const predictions = el('div', null, 'predictions');
    for (const g of d.groups) predictions.append(el('span', `${g.prediction.ok ? JSON.stringify(g.prediction.value) : '失败：' + g.prediction.error} · ${g.candidates.length} 个候选`, 'prediction'));
    const annotate = el('button', '↑ 标注这一行并重新搜索');
    annotate.onclick = () => {
      labels.set(d.row_index, labels.get(d.row_index) ?? ''); labelsChanged(); dataGrid();
      const row = $(`row-${d.row_index}`); row.classList.add('highlight'); row.scrollIntoView({ behavior: 'smooth', block: 'center' }); row.querySelector('input[type=text]').focus();
      resetSearch(); notice('请填写这一行的正确输出，再次生成候选。');
    };
    box.append(predictions, annotate); $('disagreements').append(box);
  }
}
function renderRecipe() {
  updateControls();
  if (!recipe?.outputs.length) { empty('recipe-fields', '选择候选后，规则会加入这里。可添加多个输出字段。'); return; }
  $('recipe-fields').replaceChildren();
  for (const output of recipe.outputs) {
    const row = el('div', null, 'recipe-field'), text = el('div');
    text.append(el('strong', output.name), el('code', JSON.stringify(output.expression)));
    if (staleFields.has(output.name)) text.append(el('span', '样例已修改：需要重新选定规则', 'error-cell'));
    const remove = el('button', '×'); remove.setAttribute('aria-label', `移除字段 ${output.name}`);
    remove.onclick = () => { recipe.outputs = recipe.outputs.filter(o => o !== output); staleFields.delete(output.name); renderRecipe(); resetResults(); };
    row.append(text, remove); $('recipe-fields').append(row);
  }
}
function download(text, name, type) {
  const url = URL.createObjectURL(new Blob([text], { type })), anchor = el('a'); anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
$('save-recipe').onclick = () => task(async () => { if (staleFields.size) throw new Error('请先重新选定已修改字段的规则。'); const validated = await call({ op: 'validate_recipe', recipe }); download(JSON.stringify(validated.recipe, null, 2), 'exampleloom.recipe.json', 'application/json'); });
$('recipe-file').onchange = e => task(async () => {
  const file = e.target.files[0]; if (!file) return;
  if (file.size > 1000000) throw new Error('配方文件过大。');
  const validated = await call({ op: 'validate_recipe', recipe: JSON.parse(await file.text()) });
  recipe = validated.recipe;
  staleFields = new Set(recipe.outputs.filter(f => (labelsByField.get(f.name)?.size ?? 0) > 0 || (f.name === $('output-name').value.trim() && labels.size > 0)).map(f => f.name));
  renderRecipe(); resetResults(); notice(staleFields.size ? '配方已载入，存在当前样例的字段需要重新生成候选并选定规则。' : `已载入 ${recipe.outputs.length} 个输出字段。导入下一批数据后可直接应用。`); e.target.value = '';
});
$('apply').onclick = () => task(async () => {
  if (staleFields.size) throw new Error('请先重新选定已修改字段的规则。');
  batch = await call({ op: 'apply', table, recipe });
  const grid = el('table'), head = el('tr'), body = el('tbody');
  for (const name of ['#', ...batch.columns, '状态']) head.append(el('th', name));
  const thead = el('thead'); thead.append(head); grid.append(thead);
  batch.rows.slice(0, 200).forEach((row, i) => {
    const tr = el('tr'); tr.append(el('td', String(i + 1), 'row-no'));
    for (const value of row.ok ? row.values : batch.columns.map(() => '—')) tr.append(el('td', value));
    tr.append(el('td', row.ok ? '已转换' : row.error, row.ok ? '' : 'error-cell')); body.append(tr);
  });
  grid.append(body); $('results').replaceChildren(grid);
  if (batch.rows.length > 200) $('results').append(el('div', '预览前 200 行；下载包含完整结果。失败位置请查看 JSON。', 'row-limit'));
  $('result-stats').textContent = `${batch.rows.length} 行 · ${batch.failures} 行失败`;
  notice(batch.failures ? `${batch.failures} 行转换失败，CSV 导出已停止。请查看错误或下载完整 JSON。` : `全部 ${batch.rows.length} 行已转换。请核对留出行，再导出使用。`, batch.failures > 0);
});
$('download-csv').onclick = () => batch?.csv != null && download(batch.csv, 'exampleloom.result.csv', 'text/csv;charset=utf-8');
$('download-report').onclick = () => batch && download(JSON.stringify(batch, null, 2), 'exampleloom.results.json', 'application/json');
