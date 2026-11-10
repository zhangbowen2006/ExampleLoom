///|
fn pivot_grid(
  table : Table,
  keys : Array[String],
  variable : String,
  value_name : String,
) -> Table raise LoomError {
  let vi = column_index(table, variable)
  let levels : Array[String] = []
  let level_indices : Map[String, Int32] = Map([])
  for row in table.rows {
    if !level_indices.contains(row[vi]) {
      level_indices[row[vi]] = levels.length()
      levels.push(row[vi])
    }
  }
  if levels.is_empty() {
    raise LoomError("pivot_grid requires at least one observed level")
  }
  let ki = column_indices(table, keys)
  let value_index = column_index(table, value_name)
  let width = keys.length() + levels.length()
  check_growth(1, width)
  let positions : Map[String, Int32] = Map([])
  let assigned : Map[String, Bool] = Map([])
  // Header labels are data; blank labels and labels colliding with internal
  // column names remain valid. Duplicate key-level cells still fail.
  let rows : Array[Array[String]] = [Array::make(keys.length(), "") + levels]
  for row in table.rows {
    let key = ki.map(i => row[i])
    let serialized = Json(key).stringify()
    let target = match positions.get(serialized) {
      Some(i) => i
      None => {
        check_growth(rows.length() + 1, width)
        let i = rows.length()
        positions[serialized] = i
        rows.push(key + Array::make(levels.length(), ""))
        i
      }
    }
    let level = level_indices[row[vi]]
    let cell_key = "\{target}:\{level}"
    if assigned.contains(cell_key) {
      raise LoomError("duplicate pivot_grid cell; aggregation is not implicit")
    }
    assigned[cell_key] = true
    rows[target][keys.length() + level] = row[value_index]
  }
  { columns: generic_columns(width), rows, }
}

///|
fn combine_columns(
  table : Table,
  names : Array[String],
  separator : String,
  output_name : String,
) -> Table raise LoomError {
  let indices = column_indices(table, names)
  let first = indices.fold(init=table.columns.length(), (a, b) => {
    Int32::min(a, b)
  })
  let columns : Array[String] = []
  for i, col in table.columns {
    if i == first {
      columns.push(output_name)
    }
    if !indices.contains(i) {
      columns.push(col)
    }
  }
  validate_columns(columns)
  let rows = table.rows.map(row => {
    let out : Array[String] = []
    for i, value in row {
      if i == first {
        let text = indices.map(j => row[j]).join(separator)
        if text.length() > 65536 {
          raise LoomError("combined cell exceeds cell limit")
        }
        out.push(text)
      }
      if !indices.contains(i) {
        out.push(value)
      }
    }
    out
  })
  { columns, rows, }
}

///|
fn segment_rows(
  table : Table,
  condition : Condition,
  starts_record : Bool,
) -> Table raise LoomError {
  ignore(condition_to_json(condition))
  condition_fields(condition, table.columns.length())
  let groups : Array[Array[String]] = []
  let mut current : Array[String] = []
  let mut width = 0
  for row in table.rows {
    let boundary = condition_at(condition, row, 0)
    if boundary && !current.is_empty() {
      width = Int32::max(width, current.length())
      groups.push(current)
      current = []
    }
    if starts_record {
      if current.is_empty() && !boundary {
        raise LoomError("record content precedes its starting marker")
      }
      current.push_iter(row.iter())
    } else if !boundary {
      current.push_iter(row.iter())
    }
    if current.length() > 64 {
      raise LoomError("segmented record exceeds 64 columns")
    }
  }
  if !current.is_empty() {
    width = Int32::max(width, current.length())
    groups.push(current)
  }
  if width == 0 {
    raise LoomError("segmentation produced no nonempty record")
  }
  check_growth(groups.length(), width)
  for row in groups {
    while row.length() < width {
      row.push("")
    }
  }
  { columns: generic_columns(width), rows: groups, }
}

///|
fn carry_context(
  table : Table,
  condition : Condition,
  names : Array[String],
) -> Table raise LoomError {
  let indices = column_indices(table, names)
  ignore(condition_to_json(condition))
  condition_fields(condition, table.columns.length())
  let columns = names.map(name => "context_" + name) + table.columns
  validate_columns(columns)
  let rows : Array[Array[String]] = []
  let mut context : Array[String]? = None
  for row in table.rows {
    if condition_at(condition, row, 0) {
      context = Some(indices.map(i => row[i]))
    } else {
      guard context is Some(values) else {
        raise LoomError("detail row precedes any context header")
      }
      check_growth(rows.length() + 1, columns.length())
      rows.push(values + row)
    }
  }
  { columns, rows, }
}
