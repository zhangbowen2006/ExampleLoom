import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,sep} from 'node:path';
import {Worker} from 'node:worker_threads';
const input=JSON.parse(await readFile('artifacts/autotables/tasks.json','utf8'));
if(input.tasks.length!==28)throw new Error('Full category inventory is required');
const engine=resolve(process.env.ENGINE_PATH??'dist/engine.js');
const results=[];
for(const task of input.tasks){
 const {input:rawInput,output,holdout,holdout_output,...metadata}=task;
 if(task.parse_error){results.push({...metadata,error:task.parse_error});continue;}
 const outcome=await new Promise(done=>{
  const worker=new Worker(new URL('./autotables-worker.mjs',import.meta.url),{workerData:{engine,task}});
  let finished=false;const finish=value=>{if(finished)return;finished=true;clearTimeout(timer);worker.terminate();done(value);};
  const timer=setTimeout(()=>finish({timeout:true,error:'Per-task wall-clock budget exceeded'}),5000);
  worker.once('message',finish);worker.once('error',e=>finish({error:e.message}));worker.once('exit',code=>{if(code!==0)finish({error:`Worker exit ${code}`});});
 });
 results.push({...metadata,...outcome});
}
const times=results.map(r=>r.synthesis_ms).filter(Number.isFinite).sort((a,b)=>a-b);
const percentile=p=>times.length?times[Math.min(times.length-1,Math.ceil(times.length*p)-1)]:null;
const summary={tasks:results.length,training_solved:results.filter(r=>r.training_solved).length,derived_probe_top1:results.filter(r=>r.derived_probe_top1).length,derived_probe_any:results.filter(r=>r.derived_probe_any).length,upstream_reference_mismatch:results.filter(r=>r.upstream_matches_transpose===false).length,errors:results.filter(r=>r.error&&!r.timeout).length,timeouts:results.filter(r=>r.timeout).length,p50_ms:percentile(.5),p95_ms:percentile(.95)};
const report={timestamp:new Date().toISOString(),engine_sha256:createHash('sha256').update(await readFile(engine)).digest('hex'),source_revision:input.revision,source_archive_sha256:input.archive_sha256,selection:input.selection,methodology:'All 28 external Auto-Tables transpose tasks remain in denominator. The entire original input and output are supplied as a single training demonstration; training success is not held-out accuracy. A separate synthetic probe rearranges/modifies input values and its expected output is computed by mathematical transpose, not upstream held-out gold. This category was selected for its known operator before scoring; the format was inspected during development, so it is not a blind or representative full-suite result. No Foofah, PROSE or Auto-Tables executable is run for a performance comparison. Errors, out-of-range inputs and timeouts count as failures.',options:{max_depth:4,max_states:128,max_evaluations:2000,max_candidates:8,timeout_ms:5000},summary,results};
const outputPath=resolve(process.env.AUTO_BENCHMARK_RESULTS??'artifacts/autotables/benchmark.json');
if(!outputPath.startsWith(resolve('artifacts')+sep))throw new Error('Results must remain in artifacts');
await writeFile(outputPath,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(summary,null,2));
