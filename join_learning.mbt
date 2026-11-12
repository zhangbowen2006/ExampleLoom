///|
/// One demonstrated result for two named source tables. Outputs are labels
/// supplied by the user; no unseen output is supplied to the learner.
pub(all) struct JoinExample {
  sources : Array[NamedTable]
  after : Table
}

///|
pub(all) struct JoinSearchOptions {
  max_evaluations : Int32
  max_candidates : Int32
  max_keys : Int32
}

///|
pub fn default_join_search_options() -> JoinSearchOptions {
  { max_evaluations: 1024, max_candidates: 8, max_keys: 2, }
}

///|
pub(all) struct JoinSearchReport {
  candidates : Array[DataJob]
  evaluations : Int32
  rejected : Int32
  truncated : Bool
  status : String
}

///|
priv struct RankedJoin {
  job : DataJob
  cost : Int32
  family : String
  key : String
}

///|
priv struct JoinWork {
  mut bounded_skips : Int32
}

///|
fn join_source(example : JoinExample, name : String) -> Table raise LoomError {
  for s in example.sources {
    if s.name == name {
      return s.table
    }
  }
  raise LoomError("missing named source: \{name}")
}

///|
fn join_projection(tables : Array[Table], targets : Array[Table]) -> TableStep? {
  if targets.any(t => t.columns != targets[0].columns) ||
    tables.any(t => t.columns != tables[0].columns) {
    return None
  }
  for i, t in tables {
    if t.rows.length() != targets[i].rows.length() {
      return None
    }
  }
  let selected : Array[String] = []
  for j, target in targets[0].columns {
    let mut found = -1
    // Prefer the same name, then a distinct column with identical values.
    for pass in 0..<2 {
      for i, name in tables[0].columns {
        if selected.contains(name) ||
          (pass == 0 && name != target) ||
          (pass == 1 && name == target) {
          continue
        }
        let mut fits = true
        for k, table in tables {
          for row, values in table.rows {
            if values[i] != targets[k].rows[row][j] {
              fits = false
              break
            }
          }
          if !fits {
            break
          }
        }
        if fits {
          found = i
          break
        }
      }
      if found >= 0 {
        break
      }
    }
    if found < 0 {
      return None
    }
    selected.push(tables[0].columns[found])
  }
  Some(Select(selected, targets[0].columns))
}

///|
fn job_stage_name(existing : Array[String], prefix : String) -> String {
  let mut n = 0
  while existing.contains("\{prefix}\{n}") {
    n += 1
  }
  "\{prefix}\{n}"
}

///|
/// Bound candidate intermediate rows, cells and text before materialization.
/// Explicit saved jobs have their separately documented, larger limits.
fn join_learning_within_limit(
  left : Table,
  right : Table,
  spec : JoinSpec,
) -> Bool raise LoomError {
  let li = column_indices(left, spec.left_keys)
  let ri = column_indices(right, spec.right_keys)
  let only_left = spec.kind == "semi" || spec.kind == "anti"
  let width = left.columns.length() +
    (if only_left { 0 } else { right.columns.length() - ri.length() }) +
    1
  let index : Map[String, Array[Int32]] = Map([])
  let right_units = right.rows.map(row => {
    let mut n = 0
    for i, cell in row {
      if !ri.contains(i) {
        n += cell.length()
      }
    }
    n
  })
  for i, row in right.rows {
    guard join_key(row, ri, spec.empty_keys) is Some(key) else { continue }
    match index.get(key) {
      Some(ids) => ids.push(i)
      None => index[key] = [i]
    }
  }
  let matched = Array::make(right.rows.length(), false)
  let mut rows = 0
  let mut units = 0
  for row in left.rows {
    let ids = match join_key(row, li, spec.empty_keys) {
      Some(key) => index.get(key).unwrap_or([])
      None => []
    }
    let left_units = row.fold(init=0, (n, cell) => n + cell.length())
    if only_left {
      if (spec.kind == "semi") == !ids.is_empty() {
        rows += 1
        units += left_units + 10
      }
    } else if ids.is_empty() {
      if spec.kind != "inner" {
        rows += 1
        units += left_units + 10
      }
    } else {
      for i in ids {
        if spec.kind == "full" {
          matched[i] = true
        }
        rows += 1
        units += left_units + right_units[i] + 10
        if rows > 512 || rows * width > 8192 || units > 250000 {
          return false
        }
      }
    }
    if rows > 512 || rows * width > 8192 || units > 250000 {
      return false
    }
  }
  if spec.kind == "full" {
    for i, row in right.rows {
      if !matched[i] {
        rows += 1
        // Right key text is copied into the left-key columns. The learning
        // spec uses an empty missing value for all other missing fields.
        units += row.fold(init=10, (n, cell) => n + cell.length())
        if rows > 512 || rows * width > 8192 || units > 250000 {
          return false
        }
      }
    }
  }
  true
}

///|
fn infer_job_hypothesis(
  examples : Array[JoinExample],
  names : Array[String],
  work : JoinWork,
  left : String,
  right : String,
  left_keys : Array[String],
  right_keys : Array[String],
  kind : String,
) -> DataJob? raise LoomError {
  let first_left = join_source(examples[0], left)
  let first_right = join_source(examples[0], right)
  let existing = first_left.columns + first_right.columns
  let indicator = if !existing.contains("_match") {
    "_match"
  } else {
    job_stage_name(existing, "__match")
  }
  let mut spec = {
    ..default_join_spec(left_keys, right_keys),
    kind,
    indicator,
  }
  for example in examples {
    if !join_learning_within_limit(
        join_source(example, left),
        join_source(example, right),
        spec,
      ) {
      work.bounded_skips += 1
      return None
    }
  }
  let mut joined : Array[Table] = []
  for example in examples {
    match
      (Some(
        join_tables(
          join_source(example, left),
          join_source(example, right),
          spec,
        ),
      ) catch {
        LoomError(_) => None
      }) {
      None => {
        joined = []
        break
      }
      Some(t) => joined.push(t)
    }
  }
  if joined.length() != examples.length() {
    // Allow duplicate lookup keys only if examples demonstrate them. The
    // relation stays explicit in the returned job and is never silently reset.
    spec = { ..spec, relationship: "many_to_many", }
    joined = []
    for example in examples {
      match
        (Some(
          join_tables(
            join_source(example, left),
            join_source(example, right),
            spec,
          ),
        ) catch {
          LoomError(_) => None
        }) {
        None => {
          joined = []
          break
        }
        Some(t) => joined.push(t)
      }
    }
  }
  if joined.length() != examples.length() {
    return None
  }
  let targets = examples.map(e => e.after)
  let join_name = job_stage_name(names, "__join")
  let output_name = job_stage_name(names + [join_name], "__output")
  let prefix : DataStage = {
    name: join_name,
    operation: JoinSources(left, right, spec),
  }
  if joined == targets {
    return Some({ sources: names, stages: [prefix], output: join_name, })
  }
  // Bind the same named join output columns before inspecting a second batch.
  // The saved pipeline performs this identical name binding on replay.
  let schema = joined[0].columns
  joined = joined.map(t => transform_table(t, [Select(schema, schema)]))
  let downstream : Array[TableStep] = []
  if join_projection(joined, targets) is Some(step) {
    downstream.push(step)
  }
  let (aggregates, _) = aggregate_witnesses(joined, targets)
  downstream.push_iter(aggregates.iter())
  let (sorts, _) = sort_witnesses(joined, targets)
  downstream.push_iter(sorts.iter())
  for step in downstream {
    let pipeline : Pipeline = { columns: joined[0].columns, steps: [step], }
    let matches = examples.all(e => {
      let job : DataJob = {
        sources: names,
        stages: [
          prefix,
          {
            name: output_name,
            operation: TransformSource(join_name, pipeline),
          },
        ],
        output: output_name,
      }
      (Some(run_data_job(job, e.sources)) catch { LoomError(_) => None }) ==
      Some(e.after)
    })
    if matches {
      return Some({
        sources: names,
        stages: [
          prefix,
          {
            name: output_name,
            operation: TransformSource(join_name, pipeline),
          },
        ],
        output: output_name,
      })
    }
  }
  None
}

///|
/// Search a bounded language: two source tables; one- or two-column equijoin;
/// inner/left/full/semi/anti; optional learned projection, aggregate or sort.
/// Every returned job is replayed on every demonstration. Candidate rank is a
/// syntactic prior, never a confidence score or proof of unseen behavior.
pub fn synthesize_join_jobs(
  examples : Array[JoinExample],
  options~ : JoinSearchOptions = default_join_search_options(),
) -> JoinSearchReport raise LoomError {
  if options.max_evaluations < 1 ||
    options.max_evaluations > 4096 ||
    options.max_candidates < 1 ||
    options.max_candidates > 8 ||
    options.max_keys < 1 ||
    options.max_keys > 2 {
    raise LoomError("invalid join search limits")
  }
  if examples.is_empty() ||
    examples.length() > 4 ||
    examples[0].sources.length() != 2 {
    raise LoomError(
      "join learning requires 1..4 examples and exactly 2 sources",
    )
  }
  let names = examples[0].sources.map(s => s.name)
  validate_columns(names)
  let mut training_units = 0
  for e in examples {
    validate_columns(e.sources.map(s => s.name))
    if e.sources.length() != 2 || e.sources.any(s => !names.contains(s.name)) {
      raise LoomError("each example requires the same two named sources")
    }
    validate_sources(e.sources.map(s => s.table) + [e.after])
    for table in e.sources.map(s => s.table) + [e.after] {
      for row in table.rows {
        for cell in row {
          if cell.length() > 1024 {
            raise LoomError("join training cell exceeds 1024 UTF-16 units")
          }
          training_units += cell.length()
          if training_units > 100000 {
            raise LoomError("join training examples exceed 100000 UTF-16 units")
          }
        }
      }
    }
    for name in names {
      let t = join_source(e, name)
      let expected = join_source(examples[0], name)
      if t.rows.length() > 64 ||
        t.columns.length() > 8 ||
        t.columns.length() != expected.columns.length() ||
        t.columns.any(c => !expected.columns.contains(c)) {
        raise LoomError(
          "each source needs matching column names, at most 64 rows and 8 columns",
        )
      }
    }
    if e.after.rows.length() > 256 || e.after.columns.length() > 16 {
      raise LoomError("target exceeds 256 rows or 16 columns")
    }
  }
  let hypotheses : Array[(Int32, Int32, Int32?, Int32?)] = []
  let left0 = join_source(examples[0], names[0])
  let right0 = join_source(examples[0], names[1])
  for i in 0..<left0.columns.length() {
    for j in 0..<right0.columns.length() {
      hypotheses.push((i, j, None, None))
    }
  }
  if options.max_keys == 2 {
    for i in 0..<left0.columns.length() {
      for k in (i + 1)..<left0.columns.length() {
        for j in 0..<right0.columns.length() {
          for l in 0..<right0.columns.length() {
            if j != l {
              hypotheses.push((i, j, Some(k), Some(l)))
            }
          }
        }
      }
    }
  }
  let ranked : Array[RankedJoin] = []
  let seen : Map[String, Bool] = Map([])
  let mut evaluations = 0
  let mut rejected = 0
  let mut truncated = options.max_evaluations < hypotheses.length() * 10
  let work : JoinWork = { bounded_skips: 0, }
  for (i, j, k, l) in hypotheses {
    for orientation in 0..<2 {
      let left_name = names[orientation]
      let right_name = names[1 - orientation]
      let lk = if orientation == 0 {
        [left0.columns[i]]
      } else {
        [right0.columns[j]]
      }
      let rk = if orientation == 0 {
        [right0.columns[j]]
      } else {
        [left0.columns[i]]
      }
      if k is Some(a) && l is Some(b) {
        lk.push(
          if orientation == 0 {
            left0.columns[a]
          } else {
            right0.columns[b]
          },
        )
        rk.push(
          if orientation == 0 {
            right0.columns[b]
          } else {
            left0.columns[a]
          },
        )
      }
      for kind in ["inner", "left", "full", "semi", "anti"] {
        if evaluations >= options.max_evaluations {
          truncated = true
          break
        }
        evaluations += 1
        let candidate = infer_job_hypothesis(
          examples, names, work, left_name, right_name, lk, rk, kind,
        )
        guard candidate is Some(job) else {
          rejected += 1
          continue
        }
        // Direct equality must also obey full job validation and resource caps.
        if !examples.all(e => {
            (Some(run_data_job(job, e.sources)) catch { LoomError(_) => None }) ==
            Some(e.after)
          }) {
          rejected += 1
          continue
        }
        let key = data_job_to_json(job).stringify()
        if seen.contains(key) {
          continue
        }
        seen[key] = true
        let mut name_mismatches = 0
        for index, name in lk {
          if name != rk[index] {
            name_mismatches += 1
          }
        }
        let kind_cost = match kind {
          "inner" => 0
          "left" => 2
          "full" => 4
          "semi" => 3
          _ => 5
        }
        let cost = lk.length() * 10 +
          name_mismatches * 2 +
          kind_cost +
          job.stages.length()
        ranked.push({
          job,
          cost,
          family: "\{left_name}:\{right_name}:\{kind}",
          key,
        })
        ranked.sort_by((a, b) => {
          if a.cost != b.cost {
            a.cost - b.cost
          } else {
            a.key.compare(b.key)
          }
        })
        if ranked.length() > options.max_candidates {
          truncated = true
          let mut remove = ranked.length() - 1
          for idx = ranked.length() - 1; idx > 0; idx = idx - 1 {
            let family = ranked[idx].family
            if ranked.filter(x => x.family == family).length() > 1 {
              remove = idx
              break
            }
          }
          ignore(ranked.remove(remove))
        }
      }
      if evaluations >= options.max_evaluations {
        break
      }
    }
    if evaluations >= options.max_evaluations {
      break
    }
  }
  truncated = truncated || work.bounded_skips > 0
  {
    candidates: ranked.map(c => c.job),
    evaluations,
    rejected,
    truncated,
    status: if truncated {
      "join_search_limit"
    } else if ranked.is_empty() {
      "no_consistent_job"
    } else {
      "bounded_hypotheses_checked"
    },
  }
}
