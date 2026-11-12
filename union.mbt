///|
pub(all) struct NamedTable {
  name : String
  table : Table
}

///|
pub(all) struct UnionSpec {
  mode : String
  missing_value : String
  source_column : String
}

///|
pub fn default_union_spec() -> UnionSpec {
  { mode: "strict", missing_value: "", source_column: "_source", }
}

///|
fn validate_union(spec : UnionSpec) -> Unit raise LoomError {
  if !["strict", "union", "intersection"].contains(spec.mode) ||
    spec.missing_value.length() > 65536 {
    raise LoomError("invalid concat mode or missing value")
  }
  validate_columns([spec.source_column])
}

///|
/// By-name alignment with explicit schema policy, stable source/row order and
/// a mandatory source label. Empty strings are not SQL nulls.
pub fn concat_tables(
  sources : Array[NamedTable],
  spec : UnionSpec,
) -> Table raise LoomError {
  validate_union(spec)
  if sources.is_empty() || sources.length() > 8 {
    raise LoomError("concat requires 1..8 named sources")
  }
  validate_columns(sources.map(s => s.name))
  validate_sources(sources.map(s => s.table))
  if sources.any(s => s.table.columns.contains(spec.source_column)) {
    raise LoomError("concat source column conflicts with an input column")
  }
  let columns = sources[0].table.columns.copy()
  if spec.mode == "union" {
    for s in sources {
      for c in s.table.columns {
        if !columns.contains(c) {
          columns.push(c)
        }
      }
    }
  } else if spec.mode == "intersection" {
    for i = columns.length() - 1; i >= 0; i = i - 1 {
      if sources.any(s => !s.table.columns.contains(columns[i])) {
        ignore(columns.remove(i))
      }
    }
  } else {
    for s in sources {
      if s.table.columns.length() != columns.length() ||
        columns.any(c => !s.table.columns.contains(c)) {
        raise LoomError("strict concat requires identical column sets")
      }
    }
  }
  validate_columns(columns)
  columns.push(spec.source_column)
  validate_columns(columns)
  let total = sources.fold(init=0, (n, s) => n + s.table.rows.length())
  check_growth(total, columns.length())
  let rows : Array[Array[String]] = []
  let mut units = columns.fold(init=0, (n, s) => n + s.length())
  for s in sources {
    let indices = columns[:columns.length() - 1].map(c => {
      Some(column_index(s.table, c)) catch {
        LoomError(_) => None
      }
    })
    for row in s.table.rows {
      let out = indices.map(i => {
          match i {
            Some(j) => row[j]
            None => spec.missing_value
          }
        }) +
        [s.name]
      for cell in out {
        units += cell.length()
        if units > 2000000 {
          raise LoomError("concat output exceeds 2000000 UTF-16 units")
        }
      }
      rows.push(out)
    }
  }
  { columns, rows, }
}

///|
pub fn union_spec_to_json(spec : UnionSpec) -> Json raise LoomError {
  validate_union(spec)
  Json::object({
    "mode": Json(spec.mode),
    "missing_value": Json(spec.missing_value),
    "source_column": Json(spec.source_column),
  })
}

///|
pub fn union_spec_from_json(v : Json) -> UnionSpec raise LoomError {
  let obj = j_object(v)
  fields_only(obj, ["mode", "missing_value", "source_column"])
  let spec : UnionSpec = {
    mode: optional_text(obj, "mode", "strict"),
    missing_value: optional_text(obj, "missing_value", ""),
    source_column: optional_text(obj, "source_column", "_source"),
  }
  validate_union(spec)
  spec
}
