///|
pub(all) enum GroupMetric {
  RowCount
  SumInt64(String)
  MinInt64(String)
  MaxInt64(String)
  SumDecimal(String)
  MinDecimal(String)
  MaxDecimal(String)
}

///|
pub(all) struct Measure {
  name : String
  metric : GroupMetric
}

///|
priv struct Groups {
  keys : Array[Array[String]]
  membership : Array[Int32]
}

///|
fn key_groups(table : Table, keys : Array[String]) -> Groups raise LoomError {
  let indices = column_indices(table, keys)
  let groups : Array[Array[String]] = []
  let membership : Array[Int32] = []
  let seen : Map[String, Int32] = Map([])
  if keys.is_empty() {
    return { keys: [[]], membership: Array::make(table.rows.length(), 0), }
  }
  for row in table.rows {
    let key = indices.map(i => row[i])
    let encoded = Json(key).stringify()
    let id = match seen.get(encoded) {
      Some(id) => id
      None => {
        let id = groups.length()
        groups.push(key)
        seen[encoded] = id
        id
      }
    }
    membership.push(id)
  }
  { keys: groups, membership, }
}

///|
fn decimal_cell(s : String) -> Int64 raise LoomError {
  let digits = if s.has_prefix("-") || s.has_prefix("+") { s[1:] } else { s[:] }
  if digits.is_empty() || !digits.to_owned().all(c => c.is_ascii_digit()) {
    raise LoomError("expected a signed decimal integer")
  }
  @string.parse_int64(s[:], base=10) catch {
    _ => raise LoomError("integer outside Int64 range")
  }
}

///|
fn group_values(
  table : Table,
  groups : Groups,
  metric : GroupMetric,
) -> Array[String] raise LoomError {
  match metric {
    SumDecimal(c) => return decimal_group_values(table, groups, c, "sum")
    MinDecimal(c) => return decimal_group_values(table, groups, c, "min")
    MaxDecimal(c) => return decimal_group_values(table, groups, c, "max")
    _ => ()
  }
  let values : Array[Int64] = Array::make(groups.keys.length(), 0L)
  let column = match metric {
    MinInt64(s)
    | MaxInt64(s)
    | SumInt64(s)
    | SumDecimal(s)
    | MinDecimal(s)
    | MaxDecimal(s) => Some(column_index(table, s))
    RowCount => None
  }
  let present = Array::make(groups.keys.length(), false)
  for i, row in table.rows {
    let id = groups.membership[i]
    let n = match column {
      Some(col) =>
        decimal_cell(row[col]) catch {
          LoomError(msg) =>
            raise LoomError(
              "row \{i + 1}, column \{table.columns[col]}: \{msg}",
            )
        }
      None => 1L
    }
    let old = values[id]
    values[id] = match metric {
      RowCount | SumInt64(_) => {
        let total = old + n
        if (n > 0L && total < old) || (n < 0L && total > old) {
          raise LoomError("integer sum overflow at row \{i + 1}")
        }
        total
      }
      MinInt64(_) => if !present[id] || n < old { n } else { old }
      MaxInt64(_) => if !present[id] || n > old { n } else { old }
      SumDecimal(_) | MinDecimal(_) | MaxDecimal(_) =>
        raise LoomError("internal decimal dispatch mismatch")
    }
    present[id] = true
  }
  Array::makei(values.length(), i => {
    if present[i] || metric is RowCount {
      values[i].to_string()
    } else {
      ""
    }
  })
}

///|
fn aggregate_rows(
  table : Table,
  keys : Array[String],
  measures : Array[Measure],
) -> Table raise LoomError {
  let decimals = measures.any(m => {
    m.metric is SumDecimal(_) ||
    m.metric is MinDecimal(_) ||
    m.metric is MaxDecimal(_)
  })
  if decimals {
    validate_sources([table])
  }
  let groups = key_groups(table, keys)
  let columns = keys + measures.map(m => m.name)
  check_growth(groups.keys.length(), columns.length())
  let mut output_units = columns.fold(init=0, (n, s) => n + s.length())
  if decimals {
    for row in groups.keys {
      for cell in row {
        output_units += cell.length()
      }
    }
  }
  for m in measures {
    let values = group_values(table, groups, m.metric)
    for i, row in groups.keys {
      if decimals {
        output_units += values[i].length()
        if output_units > 2000000 {
          raise LoomError(
            "decimal aggregate output exceeds 2000000 UTF-16 units",
          )
        }
      }
      row.push(values[i])
    }
  }
  let result : Table = { columns, rows: groups.keys, }
  if decimals {
    validate_sources([result])
  }
  result
}

///|
/// Infer ordered key columns from the output schema. Keep bounded alternative
/// metrics when one demonstration cannot distinguish e.g. count and sum.
fn aggregate_witnesses(
  tables : Array[Table],
  targets : Array[Table],
) -> (Array[TableStep], Bool) {
  let result : Array[TableStep] = []
  let mut contracted = None
  for i, t in tables {
    if !targets[i].rows.is_empty() && t.rows.length() > targets[i].rows.length() {
      contracted = Some(i)
      break
    }
  }
  guard contracted is Some(index) else { return (result, false) }
  let table = tables[index]
  let target = targets[index]
  let width = target.columns.length()
  if width > 16 || targets.any(t => t.columns != target.columns) {
    return (result, false)
  }
  // Every supported numeric result has a canonical base-ten representation.
  if !target.rows.all(r => {
      let value = r[width - 1]
      try decimal_text(exact_decimal(decimal_order(value))) == value catch {
        _ => false
      }
    }) {
    return (result, false)
  }
  let mut clipped = false
  for k in 0..<width {
    if k > 0 && !table.columns.contains(target.columns[k - 1]) {
      break
    }
    if width - k > 8 {
      continue
    }
    let keys = target.columns[:k].to_owned()
    let layouts : Array[Groups] = []
    for i, t in tables {
      let groups = key_groups(t, keys) catch { _ => break }
      if groups.keys != targets[i].rows.map(row => row[:k].to_owned()) {
        break
      }
      layouts.push(groups)
    }
    if layouts.length() != tables.length() {
      continue
    }
    let pool : Array[GroupMetric] = [RowCount]
    for col in table.columns {
      if !keys.contains(col) {
        pool.push_iter([SumInt64(col), MinInt64(col), MaxInt64(col)].iter())
        let has_decimal = tables.any(t => {
          let index = column_index(t, col) catch { _ => return false }
          t.rows.any(row => {
            try {
              ignore(decimal_order(row[index]))
              row[index].contains(".") ||
              (try {
                ignore(decimal_cell(row[index]))
                false
              } catch {
                _ => true
              })
            } catch {
              _ => false
            }
          })
        })
        if has_decimal {
          pool.push_iter(
            [SumDecimal(col), MinDecimal(col), MaxDecimal(col)].iter(),
          )
        }
      }
    }
    let fits : Array[Array[Measure]] = Array::makei(width - k, _ => [])
    let expected = Array::makei(width - k, offset => {
      targets.map(t => t.rows.map(row => row[k + offset]))
    })
    for metric in pool {
      let values : Array[Array[String]] = []
      for i, t in tables {
        let column = group_values(t, layouts[i], metric) catch { _ => break }
        values.push(column)
      }
      if values.length() != tables.length() {
        continue
      }
      for j in k..<width {
        if values == expected[j - k] {
          fits[j - k].push({ name: target.columns[j], metric, })
        }
      }
    }
    let mut combinations : Array[Array[Measure]] = [[]]
    for choices in fits {
      if choices.length() * combinations.length() > 8 {
        clipped = true
      }
      let next : Array[Array[Measure]] = []
      for prefix in combinations {
        for choice in choices {
          if next.length() >= 8 {
            break
          }
          next.push(prefix + [choice])
        }
      }
      combinations = next
    }
    for measures in combinations {
      result.push(Aggregate(keys, measures))
    }
  }
  (result, clipped)
}
