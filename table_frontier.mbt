///|
priv struct RankedPipeline {
  pipeline : Pipeline
  cost : Int32
  key : String
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
    ignore(goals.pop())
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
