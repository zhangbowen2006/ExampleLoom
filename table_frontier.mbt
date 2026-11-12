///|
priv struct RankedPipeline {
  pipeline : Pipeline
  cost : Int32
  key : String
}

///|
/// Preserve alternative structural hypotheses under a small candidate budget.
/// This is only a declared syntactic family, not semantic equivalence or truth.
fn pipeline_family(p : Pipeline) -> String {
  for step in p.steps {
    match step {
      FlattenRows => return "whole_table"
      PackRows(_, _) => return "fixed_records"
      GroupRows(_, _) | SegmentRows(_, _) | CarryContext(_, _) =>
        return "grouped_records"
      Pivot(_, _, _, _)
      | PivotGrid(_, _, _)
      | PivotRecords(_, _, _)
      | PivotRecordLists(_, _, _) => return "pivot"
      Unpivot(_, _, _, _) | Fold(_, _, _) | Melt(_, _, _, _, _) =>
        return "long_form"
      Aggregate(_, _) => return "aggregate"
      Transpose => return "transpose"
      SplitColumn(_, _, _) | SplitColumnPadded(_, _, _) | Explode(_, _) =>
        return "split"
      _ => ()
    }
  }
  if p.steps.any(s => s is MapRows(_) || s is UpdateColumns(_)) {
    "row_map"
  } else {
    "row_operations"
  }
}

///|
fn retain_pipeline(
  goals : Array[RankedPipeline],
  seen : Map[String, Bool],
  p : Pipeline,
  limit : Int32,
) -> Bool raise LoomError {
  let key = pipeline_to_json(p).stringify()
  if seen.contains(key) {
    return false
  }
  if seen.length() >= 512 {
    return true
  }
  seen[key] = true
  goals.push({ pipeline: p, cost: pipeline_cost(p), key, })
  goals.sort_by((a, b) => {
    if a.cost != b.cost {
      a.cost - b.cost
    } else {
      a.key.compare(b.key)
    }
  })
  if goals.length() > limit {
    // Keep the globally cheapest candidate at index zero. Prefer removing a
    // duplicate family, even when a new structural explanation costs more.
    let mut remove = goals.length() - 1
    for i = goals.length() - 1; i > 0; i = i - 1 {
      let family = pipeline_family(goals[i].pipeline)
      if goals.filter(g => pipeline_family(g.pipeline) == family).length() > 1 {
        remove = i
        break
      }
    }
    ignore(goals.remove(remove))
    true
  } else {
    false
  }
}

///|
fn pop_table_state(queue : Array[TableState]) -> TableState {
  let mut best = 0
  for i in 1..<queue.length() {
    if queue[i].priority < queue[best].priority ||
      (
        queue[i].priority == queue[best].priority &&
        queue[i].serial < queue[best].serial
      ) {
      best = i
    }
  }
  let chosen = queue[best]
  queue[best] = queue[queue.length() - 1]
  ignore(queue.pop())
  chosen
}

///|
fn retain_table_state(
  buffer : Array[TableState],
  next : TableState,
  limit : Int32,
) -> Bool {
  for i, old in buffer {
    if old.key == next.key {
      if next.priority < old.priority {
        buffer[i] = next
      }
      return false
    }
  }
  if buffer.length() < limit {
    buffer.push(next)
    return false
  }
  let mut worst = 0
  for i in 1..<buffer.length() {
    if buffer[i].priority > buffer[worst].priority ||
      (
        buffer[i].priority == buffer[worst].priority &&
        buffer[i].serial > buffer[worst].serial
      ) {
      worst = i
    }
  }
  if next.priority < buffer[worst].priority {
    buffer[worst] = next
  }
  true
}
