///|
/// Explicit multi-source execution, not example-based join inference.
pub(all) struct JoinSpec {
  left_keys : Array[String]
  right_keys : Array[String]
  kind : String
  relationship : String
  empty_keys : String
  right_suffix : String
  missing_value : String
  indicator : String
}

///|
pub fn default_join_spec(
  left_keys : Array[String],
  right_keys : Array[String],
) -> JoinSpec {
  {
    left_keys,
    right_keys,
    kind: "left",
    relationship: "many_to_one",
    empty_keys: "never",
    right_suffix: "_right",
    missing_value: "",
    indicator: "_match",
  }
}

///|
fn validate_sources(tables : Array[Table]) -> Unit raise LoomError {
  let mut cells = 0
  let mut units = 0
  for t in tables {
    validate_table(t)
    units += t.columns.fold(init=0, (n, s) => n + s.length())
    if units > 2000000 {
      raise LoomError("source tables exceed 2000000 combined UTF-16 units")
    }
    cells += t.rows.length() * t.columns.length()
    if cells > 200000 {
      raise LoomError("source tables exceed 200000 combined cells")
    }
    for row in t.rows {
      for value in row {
        units += value.length()
        if units > 2000000 {
          raise LoomError("source tables exceed 2000000 combined UTF-16 units")
        }
      }
    }
  }
}

///|
fn validate_join(spec : JoinSpec) -> Unit raise LoomError {
  validate_columns(spec.left_keys)
  validate_columns(spec.right_keys)
  if spec.left_keys.length() != spec.right_keys.length() ||
    spec.left_keys.length() > 8 {
    raise LoomError("join requires 1..8 paired keys")
  }
  if !["inner", "left", "full", "semi", "anti"].contains(spec.kind) ||
    !["one_to_one", "one_to_many", "many_to_one", "many_to_many"].contains(
      spec.relationship,
    ) ||
    !["never", "match"].contains(spec.empty_keys) {
    raise LoomError("invalid join kind, relationship or empty key policy")
  }
  validate_columns([spec.indicator])
  if spec.right_suffix.is_empty() ||
    spec.right_suffix.length() > 64 ||
    spec.missing_value.length() > 65536 {
    raise LoomError(
      "join suffix requires 1..64 units and missing value at most 65536",
    )
  }
}

///|
fn join_key(
  row : Array[String],
  indices : Array[Int32],
  policy : String,
) -> String? {
  let values = indices.map(i => row[i])
  if policy == "never" && values.any(s => s.is_empty()) {
    None
  } else {
    Some(Json(values).stringify())
  }
}

///|
/// Stable left-row/right-match order; full join appends unmatched right rows.
/// The mandatory indicator distinguishes filled missing cells from real empties.
pub fn join_tables(
  left : Table,
  right : Table,
  spec : JoinSpec,
) -> Table raise LoomError {
  validate_join(spec)
  validate_sources([left, right])
  let li = column_indices(left, spec.left_keys)
  let ri = column_indices(right, spec.right_keys)
  let right_values : Array[Int32] = []
  let columns = left.columns.copy()
  let only_left = spec.kind == "semi" || spec.kind == "anti"
  if !only_left {
    for i, name in right.columns {
      if !ri.contains(i) {
        right_values.push(i)
        columns.push(
          if columns.contains(name) {
            name + spec.right_suffix
          } else {
            name
          },
        )
      }
    }
  }
  columns.push(spec.indicator)
  validate_columns(columns)
  let index : Map[String, Array[Int32]] = Map([])
  let right_unique = spec.relationship == "many_to_one" ||
    spec.relationship == "one_to_one"
  for i, row in right.rows {
    guard join_key(row, ri, spec.empty_keys) is Some(key) else { continue }
    match index.get(key) {
      None => index[key] = [i]
      Some(ids) => {
        if right_unique {
          raise LoomError("join relationship requires unique right keys")
        }
        ids.push(i)
      }
    }
  }
  let left_seen : Map[String, Bool] = Map([])
  let left_unique = spec.relationship == "one_to_many" ||
    spec.relationship == "one_to_one"
  let matches : Array[Array[Int32]] = []
  let matched_right = Array::make(right.rows.length(), false)
  let mut count = 0
  // Preflight all multiplicities before allocating any result rows.
  for row in left.rows {
    let ids = match join_key(row, li, spec.empty_keys) {
      None => []
      Some(key) => {
        if left_unique && left_seen.contains(key) {
          raise LoomError("join relationship requires unique left keys")
        }
        left_seen[key] = true
        index.get(key).unwrap_or([])
      }
    }
    matches.push(ids)
    if spec.kind == "full" {
      for i in ids {
        matched_right[i] = true
      }
    }
    count += if only_left {
      if (spec.kind == "semi") == !ids.is_empty() {
        1
      } else {
        0
      }
    } else if ids.is_empty() {
      if spec.kind == "inner" {
        0
      } else {
        1
      }
    } else {
      ids.length()
    }
    check_growth(count, columns.length())
  }
  if spec.kind == "full" {
    for matched in matched_right {
      if !matched {
        count += 1
        check_growth(count, columns.length())
      }
    }
  }
  let rows : Array[Array[String]] = []
  let mut units = columns.fold(init=0, (n, s) => n + s.length())
  fn append(row : Array[String]) -> Unit raise LoomError {
    for s in row {
      units += s.length()
      if units > 2000000 {
        raise LoomError("join output exceeds 2000000 UTF-16 units")
      }
    }
    rows.push(row)
  }
  for i, row in left.rows {
    let ids = matches[i]
    if only_left {
      if (spec.kind == "semi") == !ids.is_empty() {
        append(row + [if ids.is_empty() { "left_only" } else { "both" }])
      }
    } else if ids.is_empty() {
      if spec.kind != "inner" {
        append(
          row +
          Array::make(right_values.length(), spec.missing_value) +
          ["left_only"],
        )
      }
    } else {
      for j in ids {
        append(row + right_values.map(k => right.rows[j][k]) + ["both"])
      }
    }
  }
  if spec.kind == "full" {
    for j, row in right.rows {
      if !matched_right[j] {
        let values = Array::make(left.columns.length(), spec.missing_value)
        for i, target in li {
          values[target] = row[ri[i]]
        }
        append(values + right_values.map(k => row[k]) + ["right_only"])
      }
    }
  }
  { columns, rows, }
}

///|
pub fn join_spec_to_json(spec : JoinSpec) -> Json raise LoomError {
  validate_join(spec)
  Json::object({
    "left_keys": Json(spec.left_keys),
    "right_keys": Json(spec.right_keys),
    "kind": Json(spec.kind),
    "relationship": Json(spec.relationship),
    "empty_keys": Json(spec.empty_keys),
    "right_suffix": Json(spec.right_suffix),
    "missing_value": Json(spec.missing_value),
    "indicator": Json(spec.indicator),
  })
}

///|
fn optional_text(
  obj : Map[String, Json],
  key : String,
  fallback : String,
) -> String raise LoomError {
  match obj.get(key) {
    None => fallback
    Some(v) => j_text(v)
  }
}

///|
pub fn join_spec_from_json(v : Json) -> JoinSpec raise LoomError {
  let obj = j_object(v)
  fields_only(obj, [
    "left_keys", "right_keys", "kind", "relationship", "empty_keys", "right_suffix",
    "missing_value", "indicator",
  ])
  let spec : JoinSpec = {
    left_keys: json_strings(required(obj, "left_keys")),
    right_keys: json_strings(required(obj, "right_keys")),
    kind: optional_text(obj, "kind", "left"),
    relationship: optional_text(obj, "relationship", "many_to_one"),
    empty_keys: optional_text(obj, "empty_keys", "never"),
    right_suffix: optional_text(obj, "right_suffix", "_right"),
    missing_value: optional_text(obj, "missing_value", ""),
    indicator: optional_text(obj, "indicator", "_match"),
  }
  validate_join(spec)
  spec
}
