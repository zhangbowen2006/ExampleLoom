///|
fn packed_projection(
  tables : Array[Table],
  targets : Array[Table],
) -> Array[TableStep] {
  let table = tables[0]
  let target = targets[0]
  if target.rows.is_empty() ||
    table.rows.length() % target.rows.length() != 0 ||
    targets.any(t => t.columns != target.columns) ||
    tables.any(t => t.columns != table.columns) {
    return []
  }
  let size = table.rows.length() / target.rows.length()
  let width = table.columns.length()
  if size < 2 || size > 64 || width * size > 64 {
    return []
  }
  for k, t in tables {
    if t.rows.length() != targets[k].rows.length() * size {
      return []
    }
  }
  let names : Array[String] = []
  for j in 0..<target.columns.length() {
    let mut found = None
    for i in 0..<(width * size) {
      let mut matches = true
      for k, t in tables {
        for r in 0..<targets[k].rows.length() {
          if t.rows[r * size + i / width][i % width] != targets[k].rows[r][j] {
            matches = false
            break
          }
        }
        if !matches {
          break
        }
      }
      if matches {
        found = Some("c" + i.to_string())
        break
      }
    }
    guard found is Some(name) else { return [] }
    names.push(name)
  }
  [PackRows(size, false), Select(names, target.columns)]
}

///|
/// Finite, compositional witnesses built from observed input structure. Every
/// primitive is charged to the normal evaluation/depth budgets and the whole
/// program is verified on every training pair before it can become a goal.
fn structural_completions(
  table : Table,
  target : Table,
  separators : Array[String],
) -> Array[Array[TableStep]] {
  let plans : Array[Array[TableStep]] = []
  let width = table.columns.length()
  // A common report format uses a header row to identify an entity, blank
  // separators, and subsequent key/value detail rows. Learn this composition
  // only when the observed target header is exactly the detail-key sequence.
  if width == 2 &&
    !table.rows.is_empty() &&
    target.rows.length() >= 2 &&
    target.columns.length() >= 3 &&
    target.rows[0][0].is_empty() {
    for key in 0..<2 {
      let value = 1 - key
      if table.rows[0][key].is_empty() || !table.rows[0][value].is_empty() {
        continue
      }
      let levels : Array[String] = []
      for row in table.rows {
        if !row[key].is_empty() &&
          !row[value].is_empty() &&
          !levels.contains(row[key]) {
          levels.push(row[key])
        }
      }
      if levels != target.rows[0][1:].to_owned() {
        continue
      }
      let marker = All([Not(Empty(Field(key))), Empty(Field(value))])
      let context_plan = [
        CarryContext(marker, [table.columns[key]]),
        Filter(Not(Empty(Field(value + 1)))),
        PivotGrid(
          ["context_" + table.columns[key]],
          table.columns[key],
          table.columns[value],
        ),
      ]
      plans.push(context_plan)
      // If the demonstrated title is a contiguous substring of its header,
      // retain the pivot's blank header row and extract the same slice from
      // each data row. The full four-step plan is replayed on all examples.
      let source = table.rows[0][key].to_array()
      let wanted = target.rows[1][0].to_array()
      if !wanted.is_empty() && wanted.length() <= source.length() {
        for start in 0..<(source.length() - wanted.length() + 1) {
          if source[start:start + wanted.length()].to_owned() == wanted {
            let end = source.length() - start - wanted.length()
            let recipe : Recipe = {
              columns: ["c0"],
              outputs: [
                {
                  name: "c0",
                  expression: If(
                    Empty(Field(0)),
                    Literal(""),
                    Slice(Field(0), Start(start), End(end)),
                  ),
                },
              ],
            }
            plans.push(context_plan + [UpdateColumns(recipe)])
            break
          }
        }
      }
    }
  }
  // Another recurring report format keeps the entity only on the first row
  // and stores named measurements as "label:value" on successive rows.
  // Learn fill-down -> filter -> split -> pivot from observed target labels.
  if width == 2 &&
    !table.rows.is_empty() &&
    target.rows.length() >= 2 &&
    target.columns.length() >= 3 &&
    target.rows[0][0].is_empty() {
    for key in 0..<2 {
      let value = 1 - key
      for sep in separators {
        let levels : Array[String] = []
        let mut valid = true
        for row in table.rows {
          if row[value].contains(sep) {
            let parts = row[value].split(sep).map(v => v.to_owned()).collect()
            if parts.length() != 2 || parts[0].is_empty() {
              valid = false
              break
            }
            if !levels.contains(parts[0]) {
              levels.push(parts[0])
            }
          }
        }
        if !valid || levels != target.rows[0][1:].to_owned() {
          continue
        }
        let label = "__loom_measure"
        let payload = "__loom_payload"
        if table.columns.contains(label) || table.columns.contains(payload) {
          continue
        }
        plans.push([
          FillDown([table.columns[key]]),
          Filter(Matches(Field(value), regex_literal(sep), false)),
          SplitColumn(table.columns[value], sep, [label, payload]),
          PivotGrid([table.columns[key]], label, payload),
        ])
      }
    }
  }
  if width == 1 &&
    !table.rows.is_empty() &&
    !target.rows.is_empty() &&
    target.columns.length() <= 16 {
    let labels = target.rows[0]
    for sep in separators {
      let first = table.rows[0][0].split(sep).map(s => s.to_owned()).collect()
      if first.length() != 2 ||
        first[0] != labels[0] ||
        !table.rows.all(r => r[0].split(sep).count() == 2) {
        continue
      }
      let key = "__loom_key"
      let value = "__loom_value"
      let context = "context_" + value
      let marker = Equals(Field(0), Literal(first[0]))
      let columns = generic_columns(target.columns.length())
      let header = All(
        Array::makei(target.columns.length(), i => {
          if i == 0 {
            Empty(Field(0))
          } else {
            Equals(Field(i), Literal(labels[i]))
          }
        }),
      )
      let outputs = target.columns.mapi((i, name) => OutputField::{
        name,
        expression: if i == 0 {
          If(header, Literal(first[0]), Field(0))
        } else {
          Field(i)
        },
      })
      plans.push([
        SplitColumn(table.columns[0], sep, [key, value]),
        CarryContext(marker, [value]),
        PivotGrid([context], key, value),
        MapRows({ columns, outputs, }),
      ])
    }
  }
  if width == 1 &&
    !table.rows.is_empty() &&
    target.columns.length() >= 2 &&
    target.rows.length() % table.rows.length() == 0 {
    let values = target.rows.length() / table.rows.length()
    let keys = target.columns.length() - 1
    let parts = keys + values
    if values >= 2 && parts <= 16 {
      for sep in separators {
        if table.rows.all(r => r[0].split(sep).count() == parts) {
          let names = Array::makei(parts, i => "__loom_part_" + i.to_string())
          let key_names = names[:keys].to_owned()
          plans.push([
            SplitColumn(table.columns[0], sep, names),
            Fold(key_names, names[keys:].to_owned(), "__loom_value"),
            Select(key_names + ["__loom_value"], target.columns),
          ])
        }
      }
    }
  }
  let wanted : Map[String, Bool] = Map([])
  for row in target.rows {
    for value in row {
      wanted[value] = true
    }
  }
  let relevant : Array[String] = []
  for i, name in table.columns {
    if table.rows.any(row => !row[i].is_empty() && wanted.contains(row[i])) {
      relevant.push(name)
    }
  }
  for n in 1..<relevant.length() {
    plans.push([
      Select(relevant, relevant),
      GroupRows(relevant[:n].to_owned(), relevant[n:].to_owned()),
    ])
  }
  if width >= 3 {
    for variable in 0..<width {
      for value in 0..<width {
        if variable == value {
          continue
        }
        let keys = table.columns.filter(n => {
          n != table.columns[variable] && n != table.columns[value]
        })
        if !keys.is_empty() &&
          keys.any(name => {
            let i = column_index(table, name) catch { _ => return false }
            table.rows.any(row => row[i].is_empty())
          }) {
          plans.push([
            FillDown(keys),
            PivotGrid(keys, table.columns[variable], table.columns[value]),
          ])
        }
      }
    }
  }
  for n in 0..<width {
    let keys = table.columns[:n].to_owned()
    let values = table.columns[n:].to_owned()
    for sep in separators {
      if table.rows.is_empty() ||
        !table.rows.all(row => {
          values.all(name => {
            let i = column_index(table, name) catch { _ => return false }
            row[i].split(sep).count() == 2
          })
        }) {
        continue
      }
      let value_name = "__loom_value"
      let label = "__loom_label"
      let payload = "__loom_payload"
      if keys.contains(value_name) ||
        keys.contains(label) ||
        keys.contains(payload) {
        continue
      }
      plans.push([
        Fold(keys, values, value_name),
        SplitColumn(value_name, sep, [label, payload]),
        PivotGrid(keys, label, payload),
      ])
    }
  }
  plans
}
