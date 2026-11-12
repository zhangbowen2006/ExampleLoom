///|
pub(all) struct ConfirmedTable {
  table : Table
  selection : String
  chosen : Int32?
}

///|
/// No target or confidence score is used. Observed consensus applies ONLY to
/// these retained programs and this complete batch, never to unknown data.
pub fn execute_table_candidates(
  candidates : Array[Pipeline],
  table : Table,
  chosen~ : Int32? = None,
) -> ConfirmedTable raise LoomError {
  if candidates.is_empty() || candidates.length() > 8 {
    raise LoomError("execution requires 1..8 retained pipelines")
  }
  for p in candidates {
    ignore(pipeline_to_json(p))
  }
  validate_sources([table])
  if chosen is Some(index) {
    if index < 0 || index >= candidates.length() {
      raise LoomError("chosen candidate index is outside the retained list")
    }
    let output = apply_pipeline(candidates[index], table)
    validate_sources([output])
    return { table: output, selection: "explicit_choice", chosen: Some(index), }
  }
  let comparison = compare_table_candidates(candidates, table)
  if comparison.status != "consistent" ||
    comparison.successful_candidates != candidates.length() {
    raise LoomError(
      "retained candidates disagree or fail on this batch; choose explicitly or add independently labelled examples",
    )
  }
  match comparison.groups[0].prediction {
    Ok(output) =>
      { table: output, selection: "observed_consensus", chosen: None, }
    Err(message) => raise LoomError(message)
  }
}
