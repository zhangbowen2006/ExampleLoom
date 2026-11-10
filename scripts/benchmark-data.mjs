// Dataset validation is separate from the engine and never changes examples.
export const hasHoldoutGold = task => JSON.stringify(task.TestAnswer)!=='[["NOT AVAILABLE, SORRY"]]';
export function auditTask(task){
  const warnings=[];
  if(!hasHoldoutGold(task))warnings.push('missing_holdout_gold');
  if(hasHoldoutGold(task)&&JSON.stringify(task.InputTable)===JSON.stringify(task.TestingTable)&&JSON.stringify(task.OutputTable)!==JSON.stringify(task.TestAnswer))warnings.push('identical_input_conflicting_reference');
  return {holdout_available:hasHoldoutGold(task),reference_warnings:warnings};
}
