///|
pub(all) struct Pipeline {
  columns : Array[String]
  steps : Array[TableStep]
}

///|
pub fn table_step_to_json(step : TableStep) -> Json raise LoomError {
  match step {
    Select(names, output_names) =>
      Json::array([Json("select"), Json(names), Json(output_names)])
    Filter(c) => Json::array([Json("filter"), condition_to_json(c)])
    MapRows(r) => Json::array([Json("map_rows"), recipe_to_json(r)])
    SplitColumn(name, sep, names) =>
      Json::array([Json("split_column"), Json(name), Json(sep), Json(names)])
    Explode(name, sep) => Json::array([Json("explode"), Json(name), Json(sep)])
    Unpivot(keys, values, variable, value_name) =>
      Json::array([
        Json("unpivot"),
        Json(keys),
        Json(values),
        Json(variable),
        Json(value_name),
      ])
    Melt(keys, values, variable, value_name, skip_empty) =>
      Json::array([
        Json("melt"),
        Json(keys),
        Json(values),
        Json(variable),
        Json(value_name),
        Json(skip_empty),
      ])
    PackRows(n, columnwise) =>
      Json::array([Json("pack_rows"), Json(n), Json(columnwise)])
    GroupRows(keys, values) =>
      Json::array([Json("group_rows"), Json(keys), Json(values)])
    Fold(keys, values, value_name) =>
      Json::array([Json("fold"), Json(keys), Json(values), Json(value_name)])
    Pivot(keys, variable, value_name, levels) =>
      Json::array([
        Json("pivot"),
        Json(keys),
        Json(variable),
        Json(value_name),
        Json(levels),
      ])
    Transpose => Json::array([Json("transpose")])
    PromoteHeaders => Json::array([Json("promote_headers")])
    DemoteHeaders => Json::array([Json("demote_headers")])
    FillDown(names) => Json::array([Json("fill_down"), Json(names)])
    Deduplicate(names) => Json::array([Json("deduplicate"), Json(names)])
    DropRows(n) => Json::array([Json("drop_rows"), Json(n)])
  }
}

///|
fn json_strings(v : Json) -> Array[String] raise LoomError {
  j_array(v).map(j_text)
}

///|
pub fn table_step_from_json(v : Json) -> TableStep raise LoomError {
  let a = j_array(v)
  if a.is_empty() {
    raise LoomError("empty table operator")
  }
  let op = j_text(a[0])
  let arity = match op {
    "select" | "explode" | "pack_rows" | "group_rows" => 3
    "melt" => 6
    "split_column" | "fold" => 4
    "unpivot" | "pivot" => 5
    "transpose" | "promote_headers" | "demote_headers" => 1
    _ => 2
  }
  if a.length() != arity {
    raise LoomError("wrong table operator arity")
  }
  let step = match op {
    "select" => Select(json_strings(a[1]), json_strings(a[2]))
    "filter" => Filter(condition_from_json(a[1]))
    "map_rows" => MapRows(recipe_from_json(a[1]))
    "split_column" =>
      SplitColumn(j_text(a[1]), j_text(a[2]), json_strings(a[3]))
    "explode" => Explode(j_text(a[1]), j_text(a[2]))
    "unpivot" =>
      Unpivot(
        json_strings(a[1]),
        json_strings(a[2]),
        j_text(a[3]),
        j_text(a[4]),
      )
    "fold" => Fold(json_strings(a[1]), json_strings(a[2]), j_text(a[3]))
    "melt" => {
      let skip = match a[5] {
        True => true
        False => false
        _ => raise LoomError("melt skip_empty must be boolean")
      }
      Melt(
        json_strings(a[1]),
        json_strings(a[2]),
        j_text(a[3]),
        j_text(a[4]),
        skip,
      )
    }
    "pack_rows" => {
      let columnwise = match a[2] {
        True => true
        False => false
        _ => raise LoomError("pack_rows columnwise must be boolean")
      }
      PackRows(j_int(a[1]), columnwise)
    }
    "group_rows" => GroupRows(json_strings(a[1]), json_strings(a[2]))
    "pivot" =>
      Pivot(json_strings(a[1]), j_text(a[2]), j_text(a[3]), json_strings(a[4]))
    "transpose" => Transpose
    "promote_headers" => PromoteHeaders
    "demote_headers" => DemoteHeaders
    "fill_down" => FillDown(json_strings(a[1]))
    "deduplicate" => Deduplicate(json_strings(a[1]))
    "drop_rows" => DropRows(j_int(a[1]))
    _ => raise LoomError("unknown table operator")
  }
  validate_step_static(step)
  step
}

///|
fn validate_step_static(step : TableStep) -> Unit raise LoomError {
  fn names(values : Array[String], allow_empty : Bool) -> Unit raise LoomError {
    if !values.is_empty() || !allow_empty {
      validate_columns(values)
    }
  }
  fn separator(value : String) -> Unit raise LoomError {
    if value.is_empty() || value.char_length() > 16 {
      raise LoomError("separator requires 1..16 characters")
    }
  }
  match step {
    Select(input, output) => {
      names(input, false)
      names(output, false)
      if input.length() != output.length() {
        raise LoomError("select names have different lengths")
      }
    }
    Filter(c) => ignore(condition_to_json(c))
    MapRows(r) => ignore(recipe_to_json(r))
    SplitColumn(col, sep, output) => {
      names([col], false)
      separator(sep)
      names(output, false)
    }
    Explode(col, sep) => {
      names([col], false)
      separator(sep)
    }
    Unpivot(keys, values, variable, value_name)
    | Melt(keys, values, variable, value_name, _) => {
      names(keys, true)
      names(values, false)
      names(keys + [variable, value_name], false)
      if values.any(v => keys.contains(v)) {
        raise LoomError("value columns overlap keys")
      }
    }
    Fold(keys, values, value_name) => {
      names(keys, true)
      names(values, false)
      names(keys + [value_name], false)
      if values.any(v => keys.contains(v)) {
        raise LoomError("value columns overlap keys")
      }
    }
    Pivot(keys, variable, value_name, levels) => {
      names(keys, true)
      names(keys + [variable, value_name], false)
      names(keys + levels, false)
      names(levels, false)
    }
    GroupRows(keys, values) => {
      names(keys, false)
      names(values, false)
      names(keys + values, false)
    }
    FillDown(values) => names(values, true)
    Deduplicate(values) => names(values, false)
    PackRows(n, _) =>
      if n < 1 || n > 64 {
        raise LoomError("pack_rows size must be 1..64")
      }
    DropRows(n) =>
      if n < 0 || n > 20000 {
        raise LoomError("drop_rows count outside 0..20000")
      }
    Transpose | PromoteHeaders | DemoteHeaders => ()
  }
}

///|
pub fn pipeline_from_json(v : Json) -> Pipeline raise LoomError {
  let o = j_object(v)
  fields_only(o, ["version", "columns", "steps"])
  if j_int(required(o, "version")) != 2 {
    raise LoomError("unsupported pipeline version")
  }
  let columns = json_strings(required(o, "columns"))
  validate_columns(columns)
  let values = j_array(required(o, "steps"))
  if values.length() > 16 {
    raise LoomError("pipeline exceeds 16 steps")
  }
  { columns, steps: values.map(table_step_from_json), }
}

///|
pub fn pipeline_to_json(p : Pipeline) -> Json raise LoomError {
  let v = Json::object({
    "version": Json(2),
    "columns": Json(p.columns),
    "steps": Json::array(p.steps.map(table_step_to_json)),
  })
  ignore(pipeline_from_json(v))
  v
}

///|
/// Rebind the saved input schema by name before running a version-2 pipeline.
/// Additional incoming columns are ignored; missing saved columns fail.
pub fn apply_pipeline(p : Pipeline, table : Table) -> Table raise LoomError {
  ignore(pipeline_to_json(p))
  let bound = transform_table(table, [Select(p.columns, p.columns)])
  transform_table(bound, p.steps)
}
