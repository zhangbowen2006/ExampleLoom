///|
pub(all) enum GroupMetric {
  RowCount
  SumInt64(String)
  MinInt64(String)
  MaxInt64(String)
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
  let values : Array[Int64] = Array::make(groups.keys.length(), 0L)
  let column = match metric {
    MinInt64(s) | MaxInt64(s) | SumInt64(s) => Some(column_index(table, s))
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
  let groups = key_groups(table, keys)
  let columns = keys + measures.map(m => m.name)
  check_growth(groups.keys.length(), columns.length())
  for m in measures {
    let values = group_values(table, groups, m.metric)
    for i, row in groups.keys {
      row.push(values[i])
    }
  }
  { columns, rows: groups.keys, }
}

///|
/// Infer ordered key columns from the output schema. Keep bounded alternative
/// metrics when one demonstration cannot distinguish e.g. count and sum.
fn aggregate_witnesses(table : Table, target : Table) -> Array[TableStep] {
  let result : Array[TableStep] = []
  let width = target.columns.length()
  if target.rows.is_empty() ||
    table.rows.length() <= target.rows.length() ||
    width > 16 {
    return result
  }
  // Every supported numeric result has a canonical base-ten representation.
  if !target.rows.all(r => {
      let value = r[width - 1]
      try decimal_cell(value).to_string() == value catch {
        _ => false
      }
    }) {
    return result
  }
  for k in 0..<width {
    if k > 0 && !table.columns.contains(target.columns[k - 1]) {
      break
    }
    if width - k > 8 {
      continue
    }
    let keys = target.columns[:k].to_owned()
    let groups = key_groups(table, keys) catch { _ => continue }
    if groups.keys.length() != target.rows.length() {
      continue
    }
    let aligned = groups.keys.mapi((i, key) => {
      key == target.rows[i][:k].to_owned()
    })
    if !aligned.all(x => x) {
      continue
    }
    let pool : Array[GroupMetric] = [RowCount]
    for col in table.columns {
      if !keys.contains(col) {
        pool.push_iter([SumInt64(col), MinInt64(col), MaxInt64(col)].iter())
      }
    }
    let fits : Array[Array[Measure]] = Array::makei(width - k, _ => [])
    for metric in pool {
      let values = group_values(table, groups, metric) catch { _ => continue }
      for j in k..<width {
        if values == target.rows.map(r => r[j]) {
          fits[j - k].push({ name: target.columns[j], metric, })
        }
      }
    }
    let mut combinations : Array[Array[Measure]] = [[]]
    for choices in fits {
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
  result
}
