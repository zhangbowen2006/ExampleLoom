///|
pub(all) struct TableExample {
  before : Table
  after : Table
}

///|
pub(all) struct TableSearchOptions {
  max_depth : Int32
  max_states : Int32
  max_evaluations : Int32
  max_candidates : Int32
}

///|
pub fn default_table_options() -> TableSearchOptions {
  { max_depth: 4, max_states: 128, max_evaluations: 2000, max_candidates: 8, }
}

///|
pub(all) struct TableSearchReport {
  candidates : Array[Pipeline]
  truncated : Bool
  status : String
  states : Int32
  evaluations : Int32
  rejected : Int32
  row_searches : Int32
}

///|
priv struct TableState {
  tables : Array[Table]
  steps : Array[TableStep]
}

///|
fn tables_key(tables : Array[Table]) -> String {
  Json::array(tables.map(table_json)).stringify()
}

///|
fn projection_step(tables : Array[Table], targets : Array[Table]) -> TableStep? {
  if tables[0].rows.length() != targets[0].rows.length() {
    return None
  }
  let names : Array[String] = []
  for j in 0..<targets[0].columns.length() {
    let mut found = -1
    for i in 0..<tables[0].columns.length() {
      let mut same = true
      for k, table in tables {
        if table.rows.length() != targets[k].rows.length() {
          same = false
          break
        }
        for r, row in table.rows {
          if row[i] != targets[k].rows[r][j] {
            same = false
            break
          }
        }
      }
      if same && !names.contains(tables[0].columns[i]) {
        found = i
        break
      }
    }
    if found < 0 {
      return None
    }
    names.push(tables[0].columns[found])
  }
  Some(Select(names, targets[0].columns))
}

///|
fn structural_neighbors(
  table : Table,
  target : Table,
  separators : Array[String],
) -> Array[TableStep] {
  let result : Array[TableStep] = [Transpose, PromoteHeaders, DemoteHeaders]
  if !table.rows.is_empty() {
    result.push(DropRows(1))
  }
  result.push(FillDown(table.columns))
  result.push(Deduplicate(table.columns))
  for col in table.columns {
    result.push(FillDown([col]))
    result.push(Deduplicate([col]))
    for sep in separators {
      let i = column_index(table, col) catch { _ => continue }
      if !table.rows.any(row => row[i].contains(sep)) {
        continue
      }
      result.push(Explode(col, sep))
      let count = if table.rows.is_empty() {
        0
      } else {
        table.rows[0][i].split(sep).count()
      }
      if count >= 2 && count <= 8 {
        result.push(
          SplitColumn(col, sep, Array::makei(count, j => "\{col}_\{j}")),
        )
      }
    }
    let i = column_index(table, col) catch { _ => continue }
    result.push(Filter(Not(Empty(Field(i)))))
    let values : Array[String] = []
    for row in table.rows {
      if !values.contains(row[i]) && values.length() < 9 {
        values.push(row[i])
      }
    }
    if values.length() <= 8 {
      values.sort()
      for value in values {
        result.push(Filter(Equals(Field(i), Literal(value))))
        result.push(Filter(Not(Equals(Field(i), Literal(value)))))
      }
    }
  }
  let width = table.columns.length()
  for n in 2..<9 {
    result.push(PackRows(n, false))
    result.push(PackRows(n, true))
  }
  for n in 0..<width {
    let keys = table.columns[:n].to_owned()
    let values = table.columns[n:].to_owned()
    // Target names are example constraints, not hidden test answers.
    let variable = if target.columns.length() >= n + 2 {
      target.columns[n]
    } else {
      "variable"
    }
    let value_name = if target.columns.length() >= n + 2 {
      target.columns[n + 1]
    } else {
      "value"
    }
    result.push(Unpivot(keys, values, variable, value_name))
    let fold_value = if target.columns.length() > n {
      target.columns[n]
    } else {
      "value"
    }
    result.push(Fold(keys, values, fold_value))
    if !keys.is_empty() {
      result.push(GroupRows(keys, values))
    }
    result.push(Melt(keys, values, variable, value_name, false))
    result.push(Melt(keys, values, variable, value_name, true))
  }
  // Long-form tables use explicit key/variable/value roles. No implicit sum.
  if width >= 2 {
    for variable in 0..<width {
      for value in 0..<width {
        if variable == value {
          continue
        }
        let keys = table.columns.filter(n => {
          n != table.columns[variable] && n != table.columns[value]
        })
        let expected_levels = target.columns.filter(n => !keys.contains(n))
        let observed_levels : Array[String] = []
        for row in table.rows {
          if !observed_levels.contains(row[variable]) {
            observed_levels.push(row[variable])
          }
        }
        for levels in [expected_levels, observed_levels] {
          if levels.length() > 0 && levels.length() + keys.length() <= 64 {
            result.push(
              Pivot(keys, table.columns[variable], table.columns[value], levels),
            )
          }
        }
      }
    }
  }
  result
}

///|
fn learned_map(
  tables : Array[Table],
  targets : Array[Table],
  separators : Array[String],
  patterns : Array[String],
) -> TableStep? {
  if tables[0].columns.length() > 16 {
    return None
  }
  let count = tables.fold(init=0, (n, t) => n + t.rows.length())
  if count < 2 || count > 32 || targets[0].columns.length() > 16 {
    return None
  }
  for k, t in tables {
    if t.rows.length() != targets[k].rows.length() {
      return None
    }
  }
  let outputs : Array[OutputField] = []
  for j, name in targets[0].columns {
    let examples : Array[Example] = []
    for k, t in tables {
      for r, row in t.rows {
        examples.push({ input: row, output: targets[k].rows[r][j], })
      }
    }
    let r = synthesize(examples, branch_depth=0, separators~, patterns~, options={
      max_candidates: 1,
      max_parts: 4,
      max_atom_evaluations: 800,
      max_steps: 6000,
      max_frontier: 256,
    }) catch {
      _ => return None
    }
    if r.candidates.is_empty() {
      return None
    }
    outputs.push({ name, expression: r.candidates[0].expression, })
  }
  Some(MapRows({ columns: tables[0].columns, outputs, }))
}

///|
/// Breadth-first search over structural programs with observational state
/// deduplication on every training table. No test/holdout rows are inspected.
pub fn synthesize_table(
  examples : Array[TableExample],
  options~ : TableSearchOptions = default_table_options(),
  separators~ : Array[String] = [",", ";", ":", "|", "/", "_", "-", " ", "\t"],
  patterns~ : Array[String] = [],
) -> TableSearchReport raise LoomError {
  if examples.is_empty() || examples.length() > 8 {
    raise LoomError("expected 1..8 table pairs")
  }
  if options.max_depth < 0 ||
    options.max_depth > 6 ||
    options.max_states < 1 ||
    options.max_states > 2048 ||
    options.max_evaluations < 1 ||
    options.max_evaluations > 100000 ||
    options.max_candidates < 1 ||
    options.max_candidates > 32 {
    raise LoomError("invalid table search limits")
  }
  if separators.length() > 16 ||
    separators.any(s => s.is_empty() || s.char_length() > 16) ||
    patterns.length() > 16 {
    raise LoomError("invalid table search hints")
  }
  for p in patterns {
    ignore(compiled_regex(p))
  }
  for e in examples {
    validate_table(e.before)
    validate_table(e.after)
    if e.before.rows.length() > 128 ||
      e.after.rows.length() > 512 ||
      e.before.columns.length() > 16 ||
      e.after.columns.length() > 32 {
      raise LoomError(
        "table training limit: 128 input rows, 512 output rows, 16 input/32 output columns",
      )
    }
    if e.before.columns != examples[0].before.columns ||
      e.after.columns != examples[0].after.columns {
      raise LoomError(
        "training pairs require consistent input and output schemas",
      )
    }
  }
  let inputs = examples.map(e => e.before)
  let targets = examples.map(e => e.after)
  let queue : Array[TableState] = [{ tables: inputs, steps: [], }]
  let seen : Map[String, Bool] = Map([(tables_key(inputs), true)])
  let candidates : Array[Pipeline] = []
  let mut cursor = 0
  let mut evaluations = 0
  let mut rejected = 0
  let mut row_searches = 0
  let mut retained_cells = inputs.fold(init=0, (n, t) => {
    n + t.rows.length() * t.columns.length()
  })
  let mut retained_units = tables_key(inputs).length()
  let mut truncated = false
  while cursor < queue.length() {
    let state = queue[cursor]
    cursor = cursor + 1
    if state.tables == targets {
      candidates.push({ columns: inputs[0].columns, steps: state.steps, })
      if candidates.length() >= options.max_candidates {
        truncated = truncated || cursor < queue.length()
        break
      }
      continue
    }
    if state.steps.length() >= options.max_depth {
      continue
    }
    let neighbors : Array[TableStep] = []
    if projection_step(state.tables, targets) is Some(step) {
      neighbors.push(step)
    }
    // Try a row learner at most 16 times in the entire table search. Its
    // separate fixed budget is reported through row_searches, not hidden in
    // the structural operator-evaluation counter.
    if neighbors.is_empty() &&
      row_searches < 16 &&
      state.tables[0].rows.length() == targets[0].rows.length() {
      row_searches = row_searches + 1
      if learned_map(state.tables, targets, separators, patterns) is Some(step) {
        neighbors.push(step)
      }
    }
    neighbors.push_iter(
      structural_neighbors(state.tables[0], targets[0], separators).iter(),
    )
    for step in neighbors {
      if evaluations >= options.max_evaluations {
        truncated = true
        break
      }
      evaluations = evaluations + 1
      let tables = state.tables.map(t => transform_table(t, [step])) catch {
        LoomError(_) => {
          rejected = rejected + 1
          continue
        }
      }
      let steps = state.steps + [step]
      if tables == targets {
        candidates.push({ columns: inputs[0].columns, steps, })
        if candidates.length() >= options.max_candidates {
          truncated = true
          break
        }
        continue
      }
      let key = tables_key(tables)
      if seen.contains(key) {
        continue
      }
      let cells = tables.fold(init=0, (n, t) => {
        n + t.rows.length() * t.columns.length()
      })
      if seen.length() >= options.max_states ||
        retained_cells + cells > 1000000 ||
        retained_units + key.length() > 8000000 {
        truncated = true
        continue
      }
      seen[key] = true
      retained_cells = retained_cells + cells
      retained_units = retained_units + key.length()
      queue.push({ tables, steps, })
    }
    if evaluations >= options.max_evaluations ||
      candidates.length() >= options.max_candidates {
      break
    }
  }
  {
    candidates,
    truncated,
    status: if truncated {
      "table_search_limit"
    } else {
      "exhausted_table_grammar"
    },
    states: seen.length(),
    evaluations,
    rejected,
    row_searches,
  }
}
