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
fn default_table_separators() -> Array[String] {
  [",", ";", ":", "|", "/", "_", "-", " ", "\t", "="]
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
  priority : Int32
  serial : Int32
  key : String
}

///|
fn tables_key(tables : Array[Table]) -> String {
  Json::array(tables.map(table_json)).stringify()
}

///|
fn projection_step(tables : Array[Table], targets : Array[Table]) -> TableStep? {
  if targets.any(t => t.columns != targets[0].columns) ||
    tables.any(t => t.columns != tables[0].columns) {
    return None
  }
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
      if same {
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
  let result : Array[TableStep] = [
    Transpose,
    PromoteHeaders,
    DemoteHeaders,
    FlattenRows,
  ]
  let wanted : Map[String, Bool] = Map([])
  for row in target.rows {
    for value in row {
      wanted[value] = true
    }
  }
  let useful : Array[String] = []
  let nonempty : Array[String] = []
  for i, col in table.columns {
    if table.rows.any(row => !row[i].is_empty()) {
      nonempty.push(col)
    }
    if table.rows.any(row => !row[i].is_empty() && wanted.contains(row[i])) {
      useful.push(col)
    }
  }
  for names in [useful, nonempty] {
    if !names.is_empty() && names.length() < table.columns.length() {
      result.push(Select(names, names))
    }
  }
  result.push(
    Filter(Not(All(Array::makei(table.columns.length(), i => Empty(Field(i)))))),
  )
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
    result.push(SegmentRows(Empty(Field(i)), false))
    let context_width = target.columns.length() - table.columns.length()
    if context_width > 0 && context_width <= table.columns.length() {
      result.push(
        CarryContext(Empty(Field(i)), table.columns[:context_width].to_owned()),
      )
    }
    if !table.rows.is_empty() {
      let chars = table.rows[0][i].to_array()
      if !chars.is_empty() &&
        chars[0].to_int() < 128 &&
        !(chars[0].is_ascii_alphabetic() || chars[0].is_ascii_digit()) &&
        !chars[0].is_whitespace() {
        result.push(
          SegmentRows(
            Matches(Field(i), "^" + regex_literal(chars[0].to_string()), false),
            true,
          ),
        )
      }
    }
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
  for n in [target.columns.length(), target.columns.length() / width] {
    if n > 8 && n <= 64 {
      result.push(PackRows(n, false))
      result.push(PackRows(n, true))
    }
  }
  for i in 0..<width {
    for j in (i + 1)..<width {
      for sep in ["", " ", "-"] {
        if table.rows.any(row => wanted.contains(row[i] + sep + row[j])) {
          result.push(
            CombineColumns(
              [table.columns[i], table.columns[j]],
              sep,
              "merged_\{i}_\{j}",
            ),
          )
        }
      }
    }
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
        result.push(
          PivotGrid(keys, table.columns[variable], table.columns[value]),
        )
        if !table.rows.is_empty() &&
          !target.rows.is_empty() &&
          !table.rows[0][variable].is_empty() &&
          table.rows[0][variable] == target.rows[0][0] {
          let labels : Array[String] = []
          for row in table.rows {
            if !labels.contains(row[variable]) {
              labels.push(row[variable])
            }
          }
          if labels == target.rows[0] {
            result.push(
              PivotRecords(
                table.columns[variable],
                table.columns[value],
                labels[0],
              ),
            )
          }
        }
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
  memo : Map[String, Expr?],
) -> TableStep? {
  if targets.any(t => t.columns != targets[0].columns) ||
    tables.any(t => t.columns != tables[0].columns) {
    return None
  }
  if tables[0].columns.length() > 16 {
    return None
  }
  let count = tables.fold(init=0, (n, t) => n + t.rows.length())
  if count < 1 || targets[0].columns.length() > 16 {
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
    if examples.any(e => {
        e.output.char_length() > 128 || e.input.any(s => s.char_length() > 128)
      }) {
      return None
    }
    let mut copied = None
    for i, column in tables[0].columns {
      if (copied is None || column == name) &&
        examples.all(e => e.input[i] == e.output) {
        copied = Some(i)
        if column == name {
          break
        }
      }
    }
    if copied is Some(i) {
      outputs.push({ name, expression: Field(i), })
      continue
    }
    let key = Json::array(
      examples.map(e => Json::array([Json(e.input), Json(e.output)])),
    ).stringify()
    let expression = match memo.get(key) {
      Some(None) => return None
      Some(Some(e)) => e
      None => {
        let canonical = canonical_examples(examples)
        let samples = if canonical.length() <= 32 {
          canonical
        } else {
          Array::makei(32, i => canonical[i * (canonical.length() - 1) / 31])
        }
        let observed = separators.filter(s => {
          samples.any(e => e.input.any(cell => cell.contains(s)))
        })
        let r = synthesize(
          samples,
          branch_depth=1,
          separators=observed,
          patterns~,
          options={
            max_candidates: 4,
            max_parts: 4,
            max_atom_evaluations: if samples.length() < 4 {
              800
            } else {
              1600
            },
            max_steps: if samples.length() < 4 {
              6000
            } else {
              12000
            },
            max_frontier: 256,
          },
        ) catch {
          _ => return None
        }
        let mut selected : Expr? = None
        for c in r.candidates {
          if examples.all(e => attempt(c.expression, e.input) == Ok(e.output)) {
            selected = Some(c.expression)
            break
          }
        }
        if memo.length() < 64 && key.length() <= 16384 {
          memo[key] = selected
        }
        match selected {
          Some(e) => e
          None => return None
        }
      }
    }
    outputs.push({ name, expression, })
  }
  Some(MapRows({ columns: tables[0].columns, outputs, }))
}

///|
/// Bounded best-first search over structural programs with observational state
/// deduplication on every training table. No test/holdout rows are inspected.
pub fn synthesize_table(
  examples : Array[TableExample],
  options~ : TableSearchOptions = default_table_options(),
  separators~ : Array[String] = default_table_separators(),
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
    if e.before.columns != examples[0].before.columns {
      raise LoomError("training pairs require consistent input schemas")
    }
  }
  let inputs = examples.map(e => e.before)
  let targets = examples.map(e => e.after)
  let profiles = targets.map(target_profile)
  let input_key = tables_key(inputs)
  let queue : Array[TableState] = [
    {
      tables: inputs,
      steps: [],
      priority: state_priority(inputs, profiles, []),
      serial: 0,
      key: input_key,
    },
  ]
  let seen : Map[String, Bool] = Map([(input_key, true)])
  let goals : Array[RankedPipeline] = []
  let goal_keys : Map[String, Bool] = Map([])
  let row_memo : Map[String, Expr?] = Map([])
  let mut evaluations = 0
  let mut rejected = 0
  let mut row_searches = 0
  let mut serial = 1
  let mut retained_cells = inputs.fold(init=0, (n, t) => {
    n + t.rows.length() * t.columns.length()
  })
  let mut retained_units = input_key.length()
  let mut truncated = false
  while !queue.is_empty() {
    let state = pop_table_state(queue)
    if state.tables == targets {
      truncated = retain_pipeline(
          goals,
          goal_keys,
          { columns: inputs[0].columns, steps: state.steps, },
          options.max_candidates,
        ) ||
        truncated
    }
    if state.steps.length() >= options.max_depth {
      continue
    }
    let neighbors : Array[TableStep] = []
    let (aggregates, clipped) = aggregate_witnesses(state.tables, targets)
    truncated = truncated || clipped
    neighbors.push_iter(aggregates.iter())
    let (sorts, sort_clipped) = sort_witnesses(state.tables, targets)
    truncated = truncated || sort_clipped
    neighbors.push_iter(sorts.iter())
    if projection_step(state.tables, targets) is Some(step) {
      neighbors.push(step)
    }
    if sparse_routing_witness(state.tables, targets) is Some(step) {
      neighbors.push(step)
    }
    if neighbors.is_empty() &&
      row_searches < 16 &&
      state.tables[0].rows.length() == targets[0].rows.length() {
      row_searches = row_searches + 1
      if learned_map(state.tables, targets, separators, patterns, row_memo)
        is Some(step) {
        if step is MapRows(recipe) &&
          state.steps.any(s => {
            match s {
              SegmentRows(_, _) | PivotGrid(_, _, _) | Transpose => true
              _ => false
            }
          }) {
          if update_witness(recipe, state.tables[0].columns) is Some(update) {
            neighbors.push(UpdateColumns(update))
          }
        }
        neighbors.push(step)
      }
    }
    neighbors.push_iter(
      structural_neighbors(state.tables[0], targets[0], separators).iter(),
    )
    let plans : Array[Array[TableStep]] = neighbors.map(step => [step])
    let packed = packed_projection(state.tables, targets)
    if !packed.is_empty() {
      plans.push(packed)
    }
    plans.push_iter(
      structural_completions(state.tables[0], targets[0], separators).iter(),
    )
    let next_states : Array[TableState] = []
    for plan in plans {
      if state.steps.length() + plan.length() > options.max_depth {
        continue
      }
      if evaluations >= options.max_evaluations {
        truncated = true
        break
      }
      if evaluations + plan.length() > options.max_evaluations {
        truncated = true
        continue
      }
      evaluations = evaluations + plan.length()
      let tables = state.tables.map(t => transform_table(t, plan)) catch {
        LoomError(_) => {
          rejected = rejected + 1
          continue
        }
      }
      let steps = state.steps + plan
      if tables == targets {
        truncated = retain_pipeline(
            goals,
            goal_keys,
            { columns: inputs[0].columns, steps, },
            options.max_candidates,
          ) ||
          truncated
        continue
      }
      let key = tables_key(tables)
      if seen.contains(key) {
        continue
      }
      truncated = retain_table_state(
          next_states,
          {
            tables,
            steps,
            priority: state_priority(tables, profiles, steps),
            serial,
            key,
          },
          Int32::min(8, options.max_states),
        ) ||
        truncated
      serial = serial + 1
    }
    next_states.sort_by((a, b) => {
      if a.priority != b.priority {
        a.priority - b.priority
      } else {
        a.serial - b.serial
      }
    })
    // Keep the original lifetime state budget. A bounded beam per expansion
    // avoids spending it on every unpromising root mutation.
    let beam = Int32::min(8, options.max_states)
    if next_states.length() > beam {
      truncated = true
    }
    for next in next_states[:Int32::min(beam, next_states.length())] {
      let key = next.key
      if seen.contains(key) {
        continue
      }
      let cells = next.tables.fold(init=0, (n, t) => {
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
      queue.push(next)
    }
    if evaluations >= options.max_evaluations {
      break
    }
  }
  let candidates = goals.map(g => g.pipeline)
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
