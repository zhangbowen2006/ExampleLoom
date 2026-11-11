///|
/// Structural operations bind by column name. All operations return a new table;
/// duplicates in pivot cells are errors, never silently aggregated or discarded.
pub(all) enum TableStep {
  PreserveExtraColumns
  SortRows(Array[SortKey])
  Select(Array[String], Array[String])
  Filter(Condition)
  MapRows(Recipe)
  UpdateColumns(Recipe)
  SplitColumn(String, String, Array[String])
  Explode(String, String)
  Unpivot(Array[String], Array[String], String, String)
  Fold(Array[String], Array[String], String)
  Melt(Array[String], Array[String], String, String, Bool)
  PackRows(Int32, Bool)
  GroupRows(Array[String], Array[String])
  Aggregate(Array[String], Array[Measure])
  Pivot(Array[String], String, String, Array[String])
  PivotGrid(Array[String], String, String)
  PivotRecords(String, String, String)
  CombineColumns(Array[String], String, String)
  SegmentRows(Condition, Bool)
  CarryContext(Condition, Array[String])
  Transpose
  PromoteHeaders
  DemoteHeaders
  FillDown(Array[String])
  Deduplicate(Array[String])
  DropRows(Int32)
}

///|
fn column_index(table : Table, name : String) -> Int32 raise LoomError {
  for i, col in table.columns {
    if col == name {
      return i
    }
  }
  raise LoomError("missing column: \{name}")
}

///|
fn column_indices(
  table : Table,
  names : Array[String],
) -> Array[Int32] raise LoomError {
  let seen : Map[String, Bool] = Map([])
  names.map(name => {
    if seen.contains(name) {
      raise LoomError("duplicate selected column: \{name}")
    }
    seen[name] = true
    column_index(table, name)
  })
}

///|
fn generic_columns(count : Int32) -> Array[String] {
  Array::makei(count, i => "c\{i}")
}

///|
fn check_growth(rows : Int32, width : Int32) -> Unit raise LoomError {
  if rows > 20000 || width < 1 || width > 64 || rows * width > 200000 {
    raise LoomError(
      "structural result exceeds 20000 rows, 64 columns or 200000 cells",
    )
  }
}

///|
fn apply_step_unchecked(
  step : TableStep,
  table : Table,
) -> Table raise LoomError {
  match step {
    PreserveExtraColumns =>
      {
        columns: table.columns.copy(),
        rows: table.rows.map(row => row.copy()),
      }
    SortRows(keys) => sort_rows(table, keys)
    Aggregate(keys, measures) => aggregate_rows(table, keys, measures)
    PivotGrid(keys, variable, value_name) =>
      pivot_grid(table, keys, variable, value_name)
    PivotRecords(variable, value_name, marker) =>
      pivot_records(table, variable, value_name, marker)
    CombineColumns(names, separator, output_name) =>
      combine_columns(table, names, separator, output_name)
    SegmentRows(condition, starts_record) =>
      segment_rows(table, condition, starts_record)
    CarryContext(condition, names) => carry_context(table, condition, names)
    Select(names, output_names) => {
      let indices = names.map(name => column_index(table, name))
      validate_columns(output_names)
      if indices.length() != output_names.length() {
        raise LoomError("select names have different lengths")
      }
      {
        columns: output_names.copy(),
        rows: table.rows.map(row => indices.map(i => row[i])),
      }
    }
    Filter(condition) => {
      ignore(condition_to_json(condition))
      condition_fields(condition, table.columns.length())
      {
        columns: table.columns.copy(),
        rows: table.rows
        .filter(row => condition_at(condition, row, 0))
        .map(row => row.copy()),
      }
    }
    MapRows(recipe) => {
      check_growth(table.rows.length(), recipe.outputs.length())
      let result = apply_recipe(recipe, table)
      if result.failures > 0 {
        raise LoomError(
          "map_rows has \{result.failures} failed rows; no partial table returned",
        )
      }
      let rows : Array[Array[String]] = []
      for row in result.rows {
        match row {
          Ok(v) => rows.push(v)
          Err(e) => raise LoomError(e)
        }
      }
      { columns: recipe.outputs.map(o => o.name), rows, }
    }
    UpdateColumns(recipe) => {
      // Each expression observes the original row; apply only after every
      // output succeeds, and retain all columns that the recipe does not edit.
      let destinations = column_indices(table, recipe.outputs.map(o => o.name))
      let result = apply_recipe(recipe, table)
      if result.failures > 0 {
        raise LoomError(
          "update_columns has \{result.failures} failed rows; no partial table returned",
        )
      }
      let rows : Array[Array[String]] = []
      for i, row in table.rows {
        let changed = row.copy()
        match result.rows[i] {
          Ok(values) =>
            for j, index in destinations {
              changed[index] = values[j]
            }
          Err(message) => raise LoomError(message)
        }
        rows.push(changed)
      }
      { columns: table.columns.copy(), rows, }
    }
    SplitColumn(name, separator, names) => {
      if separator.is_empty() || separator.char_length() > 16 {
        raise LoomError("split requires a literal separator of 1..16 chars")
      }
      validate_columns(names)
      let col = column_index(table, name)
      let columns : Array[String] = []
      for i, old in table.columns {
        if i == col {
          columns.push_iter(names.iter())
        } else {
          columns.push(old)
        }
      }
      check_growth(table.rows.length(), columns.length())
      validate_columns(columns)
      let rows = table.rows.map(row => {
        let parts = row[col].split(separator).map(v => v.to_owned()).collect()
        if parts.length() != names.length() {
          raise LoomError("split row has unexpected number of fields")
        }
        let result : Array[String] = []
        for i, value in row {
          if i == col {
            result.push_iter(parts.iter())
          } else {
            result.push(value)
          }
        }
        result
      })
      { columns, rows, }
    }
    Explode(name, separator) => {
      if separator.is_empty() || separator.char_length() > 16 {
        raise LoomError("explode requires a separator of 1..16 chars")
      }
      let col = column_index(table, name)
      let rows : Array[Array[String]] = []
      for row in table.rows {
        for value in row[col].split(separator) {
          check_growth(rows.length() + 1, table.columns.length())
          let next = row.copy()
          next[col] = value.to_owned()
          rows.push(next)
        }
      }
      { columns: table.columns.copy(), rows, }
    }
    Unpivot(keys, values, variable, value_name) => {
      let ki = column_indices(table, keys)
      let vi = column_indices(table, values)
      if values.is_empty() || values.any(v => keys.contains(v)) {
        raise LoomError(
          "unpivot value columns must be nonempty and disjoint from keys",
        )
      }
      let columns = keys.copy()
      columns.push(variable)
      columns.push(value_name)
      validate_columns(columns)
      check_growth(table.rows.length() * vi.length(), columns.length())
      let rows : Array[Array[String]] = []
      for row in table.rows {
        for j, i in vi {
          let next = ki.map(k => row[k])
          next.push(values[j])
          next.push(row[i])
          rows.push(next)
        }
      }
      { columns, rows, }
    }
    Fold(keys, values, value_name) => {
      let ki = column_indices(table, keys)
      let vi = column_indices(table, values)
      if values.is_empty() || values.any(v => keys.contains(v)) {
        raise LoomError(
          "fold value columns must be nonempty and disjoint from keys",
        )
      }
      let columns = keys + [value_name]
      validate_columns(columns)
      check_growth(table.rows.length() * vi.length(), columns.length())
      let rows : Array[Array[String]] = []
      for row in table.rows {
        for i in vi {
          rows.push(ki.map(k => row[k]) + [row[i]])
        }
      }
      { columns, rows, }
    }
    Melt(keys, values, variable, value_name, skip_empty) => {
      if table.rows.is_empty() {
        raise LoomError("melt requires a header row")
      }
      let ki = column_indices(table, keys)
      let vi = column_indices(table, values)
      if values.is_empty() || values.any(v => keys.contains(v)) {
        raise LoomError("melt columns must be nonempty and disjoint")
      }
      let columns = keys + [variable, value_name]
      validate_columns(columns)
      check_growth((table.rows.length() - 1) * vi.length(), columns.length())
      let rows : Array[Array[String]] = []
      for row in table.rows[1:] {
        for i in vi {
          if !skip_empty || !row[i].is_empty() {
            rows.push(ki.map(k => row[k]) + [table.rows[0][i], row[i]])
          }
        }
      }
      { columns, rows, }
    }
    PackRows(size, columnwise) => {
      if size < 1 || size > 64 || table.rows.length() % size != 0 {
        raise LoomError("pack_rows requires complete blocks of 1..64 rows")
      }
      let width = if columnwise { size } else { size * table.columns.length() }
      let count = table.rows.length() /
        size *
        (if columnwise { table.columns.length() } else { 1 })
      check_growth(count, width)
      let rows : Array[Array[String]] = []
      for block in 0..<(table.rows.length() / size) {
        if columnwise {
          for j in 0..<table.columns.length() {
            rows.push(Array::makei(size, i => table.rows[block * size + i][j]))
          }
        } else {
          let row : Array[String] = []
          for i in 0..<size {
            row.push_iter(table.rows[block * size + i].iter())
          }
          rows.push(row)
        }
      }
      { columns: generic_columns(width), rows, }
    }
    GroupRows(keys, values) => {
      let ki = column_indices(table, keys)
      let vi = column_indices(table, values)
      if keys.is_empty() ||
        values.is_empty() ||
        values.any(v => keys.contains(v)) {
        raise LoomError("group_rows requires nonempty disjoint keys and values")
      }
      let positions : Map[String, Int32] = Map([])
      let groups : Array[Array[String]] = []
      let mut width = keys.length()
      for row in table.rows {
        let key = ki.map(i => row[i])
        let serialized = Json(key).stringify()
        let i = match positions.get(serialized) {
          Some(i) => i
          None => {
            let i = groups.length()
            positions[serialized] = i
            groups.push(key)
            i
          }
        }
        check_growth(groups.length(), groups[i].length() + vi.length())
        groups[i].push_iter(vi.map(i => row[i]).iter())
        width = Int32::max(width, groups[i].length())
      }
      check_growth(groups.length(), width)
      for row in groups {
        while row.length() < width {
          row.push("")
        }
      }
      { columns: generic_columns(width), rows: groups, }
    }
    Pivot(keys, variable, value_name, levels) => {
      let ki = column_indices(table, keys)
      let variable_index = column_index(table, variable)
      let value_index = column_index(table, value_name)
      if variable == value_name ||
        keys.contains(variable) ||
        keys.contains(value_name) {
        raise LoomError("pivot columns must be disjoint")
      }
      validate_columns(levels)
      let columns = keys.copy()
      columns.push_iter(levels.iter())
      validate_columns(columns)
      let indices : Map[String, Int32] = Map([])
      let assigned : Map[String, Bool] = Map([])
      let rows : Array[Array[String]] = []
      for row in table.rows {
        let key = ki.map(i => row[i])
        let serialized = Json(key).stringify()
        let target = match indices.get(serialized) {
          Some(i) => i
          None => {
            check_growth(rows.length() + 1, columns.length())
            let i = rows.length()
            indices[serialized] = i
            rows.push(key + Array::make(levels.length(), ""))
            i
          }
        }
        let mut level = -1
        for j, name in levels {
          if name == row[variable_index] {
            level = j
          }
        }
        if level < 0 {
          raise LoomError(
            "pivot encountered undeclared level: \{row[variable_index]}",
          )
        }
        let cell_key = "\{target}:\{level}"
        if assigned.contains(cell_key) {
          raise LoomError("duplicate pivot cell; aggregation is not implicit")
        }
        assigned[cell_key] = true
        rows[target][keys.length() + level] = row[value_index]
      }
      { columns, rows, }
    }
    Transpose => {
      check_growth(table.columns.length(), table.rows.length())
      {
        columns: generic_columns(table.rows.length()),
        rows: Array::makei(table.columns.length(), j => {
          table.rows.map(row => row[j])
        }),
      }
    }
    PromoteHeaders => {
      if table.rows.is_empty() {
        raise LoomError("cannot promote empty table")
      }
      validate_columns(table.rows[0])
      {
        columns: table.rows[0].copy(),
        rows: table.rows[1:].map(row => row.copy()),
      }
    }
    DemoteHeaders => {
      check_growth(table.rows.length() + 1, table.columns.length())
      {
        columns: generic_columns(table.columns.length()),
        rows: [table.columns.copy()] + table.rows.map(row => row.copy()),
      }
    }
    FillDown(names) => {
      let indices = column_indices(table, names)
      let previous = Array::make(table.columns.length(), "")
      let rows = table.rows.map(row => {
        let next = row.copy()
        for i in indices {
          if next[i].is_empty() {
            next[i] = previous[i]
          } else {
            previous[i] = next[i]
          }
        }
        next
      })
      { columns: table.columns.copy(), rows, }
    }
    Deduplicate(names) => {
      let indices = column_indices(table, names)
      if names.is_empty() {
        raise LoomError("deduplicate requires at least one key")
      }
      let seen : Map[String, Bool] = Map([])
      let rows : Array[Array[String]] = []
      for row in table.rows {
        let key = Json(indices.map(i => row[i])).stringify()
        if !seen.contains(key) {
          seen[key] = true
          rows.push(row.copy())
        }
      }
      { columns: table.columns.copy(), rows, }
    }
    DropRows(count) => {
      if count < 0 || count > table.rows.length() {
        raise LoomError("drop_rows count outside table")
      }
      {
        columns: table.columns.copy(),
        rows: table.rows[count:].map(row => row.copy()),
      }
    }
  }
}

///|
pub fn transform_table(
  table : Table,
  steps : Array[TableStep],
) -> Table raise LoomError {
  validate_table(table)
  check_growth(table.rows.length(), table.columns.length())
  if steps.length() > 16 {
    raise LoomError("pipeline exceeds 16 steps")
  }
  let mut result = {
    columns: table.columns.copy(),
    rows: table.rows.map(row => row.copy()),
  }
  for i, step in steps {
    result = try {
      validate_step_static(step)
      apply_step_unchecked(step, result)
    } catch {
      LoomError(message) => raise LoomError("step \{i + 1}: \{message}")
    }
    validate_table(result)
    check_growth(result.rows.length(), result.columns.length())
  }
  result
}
