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
