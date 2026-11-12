import {parentPort,workerData} from 'node:worker_threads';
import {pathToFileURL} from 'node:url';
const {handle}=await import(pathToFileURL(workerData.engine).href);
const run=q=>{const r=JSON.parse(handle(JSON.stringify(q)));if(!r.ok)throw new Error(r.error);return r;};
const grid=rows=>({columns:Array.from({length:rows[0].length},(_,i)=>`c${i}`),rows});
try{
 const task=workerData.task,input=grid(task.input),output=grid(task.output);
 const query={op:'synthesize_table',examples:[{input,output}],options:{max_depth:4,max_states:128,max_evaluations:2000,max_candidates:8}};
 if(workerData.intent)query.intent=workerData.intent;
 const start=performance.now();const report=run(query);const ms=performance.now()-start;
 const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
 for(const c of report.candidates)if(!equal(run({op:'transform',pipeline:c.pipeline,table:input}).table,output))throw new Error('Returned candidate does not replay training');
 // The derived probe and expected output are used only after the ranking exists.
 const next=grid(task.holdout),expected=grid(task.holdout_output);
 const results=report.candidates.map(c=>{try{return equal(run({op:'transform',pipeline:c.pipeline,table:next}).table,expected);}catch{return false;}});
 parentPort.postMessage({training_solved:report.candidates.length>0,derived_probe_top1:results[0]??false,derived_probe_any:results.some(Boolean),candidates:report.candidates.length,truncated:report.truncated,synthesis_ms:ms});
}catch(error){parentPort.postMessage({error:error.message});}
