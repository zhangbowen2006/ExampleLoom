///|
pub(all) struct Pipeline {
  columns : Array[String]
  steps : Array[TableStep]
}

///|
pub fn table_step_to_json(step : TableStep) -> Json raise LoomError {
  match step {
    PreserveExtraColumns => Json::array([Json("preserve_extra_columns")])
    FlattenRows => Json::array([Json("flatten_rows")])
    SortRows(keys) =>
      Json::array([
        Json("sort_rows"),
        Json::array(
          keys.map(key => {
            Json([
              key.column,
              match key.kind {
                Lexical => "text"
                Decimal => "decimal"
              },
              if key.descending {
                "desc"
              } else {
                "asc"
              },
            ])
          }),
        ),
      ])
    Aggregate(keys, measures) =>
      Json::array([
        Json("aggregate"),
        Json(keys),
        Json::array(
          measures.map(m => {
            match m.metric {
              RowCount => Json([m.name, "count"])
              SumInt64(s) => Json([m.name, "sum", s])
              MinInt64(s) => Json([m.name, "min", s])
              MaxInt64(s) => Json([m.name, "max", s])
            }
          }),
        ),
      ])
    PivotGrid(keys, variable, value_name) =>
      Json::array([
        Json("pivot_grid"),
        Json(keys),
        Json(variable),
        Json(value_name),
      ])
    PivotRecords(variable, value_name, marker) =>
      Json::array([
        Json("pivot_records"),
        Json(variable),
        Json(value_name),
        Json(marker),
      ])
    PivotRecordLists(variable, value_name, marker) =>
      Json::array([
        Json("pivot_record_lists"),
        Json(variable),
        Json(value_name),
        Json(marker),
      ])
    CombineColumns(names, separator, output_name) =>
      Json::array([
        Json("combine_columns"),
        Json(names),
        Json(separator),
        Json(output_name),
      ])
    SegmentRows(c, starts) =>
      Json::array([Json("segment_rows"), condition_to_json(c), Json(starts)])
    CarryContext(c, columns) =>
      Json::array([Json("carry_context"), condition_to_json(c), Json(columns)])
    Select(names, output_names) =>
      Json::array([Json("select"), Json(names), Json(output_names)])
    Filter(c) => Json::array([Json("filter"), condition_to_json(c)])
    MapRows(r) => Json::array([Json("map_rows"), recipe_to_json(r)])
    UpdateColumns(r) => Json::array([Json("update_columns"), recipe_to_json(r)])
    SplitColumn(name, sep, names) =>
      Json::array([Json("split_column"), Json(name), Json(sep), Json(names)])
    SplitColumnPadded(name, sep, names) =>
      Json::array([
        Json("split_column_padded"),
        Json(name),
        Json(sep),
        Json(names),
      ])
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
    "select"
    | "explode"
    | "pack_rows"
    | "group_rows"
    | "aggregate"
    | "segment_rows"
    | "carry_context" => 3
    "melt" => 6
    "split_column"
    | "split_column_padded"
    | "fold"
    | "pivot_grid"
    | "pivot_records"
    | "pivot_record_lists"
    | "combine_columns" => 4
    "unpivot" | "pivot" => 5
    "transpose"
    | "flatten_rows"
    | "promote_headers"
    | "demote_headers"
    | "preserve_extra_columns" => 1
    _ => 2
  }
  if a.length() != arity {
    raise LoomError("wrong table operator arity")
  }
  let step = match op {
    "preserve_extra_columns" => PreserveExtraColumns
    "flatten_rows" => FlattenRows
    "sort_rows" =>
      SortRows(
        j_array(a[1]).map(value => {
          let fields = json_strings(value)
          if fields.length() != 3 {
            raise LoomError("sort key requires column, kind and direction")
          }
          SortKey::{
            column: fields[0],
            kind: match fields[1] {
              "text" => Lexical
              "decimal" => Decimal
              _ => raise LoomError("sort kind must be text or decimal")
            },
            descending: match fields[2] {
              "asc" => false
              "desc" => true
              _ => raise LoomError("sort direction must be asc or desc")
            },
          }
        }),
      )
    "pivot_grid" => PivotGrid(json_strings(a[1]), j_text(a[2]), j_text(a[3]))
    "pivot_records" => PivotRecords(j_text(a[1]), j_text(a[2]), j_text(a[3]))
    "pivot_record_lists" =>
      PivotRecordLists(j_text(a[1]), j_text(a[2]), j_text(a[3]))
    "split_column_padded" =>
      SplitColumnPadded(j_text(a[1]), j_text(a[2]), json_strings(a[3]))
    "combine_columns" =>
      CombineColumns(json_strings(a[1]), j_text(a[2]), j_text(a[3]))
    "segment_rows" => {
      let starts = match a[2] {
        True => true
        False => false
        _ => raise LoomError("segment_rows starts_record must be boolean")
      }
      SegmentRows(condition_from_json(a[1]), starts)
    }
    "carry_context" =>
      CarryContext(condition_from_json(a[1]), json_strings(a[2]))
    "select" => Select(json_strings(a[1]), json_strings(a[2]))
    "filter" => Filter(condition_from_json(a[1]))
    "map_rows" => MapRows(recipe_from_json(a[1]))
    "update_columns" => UpdateColumns(recipe_from_json(a[1]))
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
    "aggregate" => {
      let measures = j_array(a[2]).map(item => {
        let parts = json_strings(item)
        match parts {
          [name, "count"] => Measure::{ name, metric: RowCount, }
          [name, "sum", col] => { name, metric: SumInt64(col), }
          [name, "min", col] => { name, metric: MinInt64(col), }
          [name, "max", col] => { name, metric: MaxInt64(col), }
          _ => raise LoomError("invalid aggregate measure")
        }
      })
      Aggregate(json_strings(a[1]), measures)
    }
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
    SortRows(keys) => validate_sort_keys(keys)
    Aggregate(keys, measures) => {
      if measures.is_empty() {
        raise LoomError("aggregate requires at least one measure")
      }
      names(keys + measures.map(m => m.name), false)
      for m in measures {
        match m.metric {
          RowCount => ()
          SumInt64(col) | MinInt64(col) | MaxInt64(col) => names([col], false)
        }
      }
    }
    PivotGrid(keys, variable, value_name) => {
      names(keys, true)
      names(keys + [variable, value_name], false)
    }
    PivotRecords(variable, value_name, marker)
    | PivotRecordLists(variable, value_name, marker) => {
      names([variable, value_name], false)
      if marker.is_empty() || marker.length() > 256 {
        raise LoomError("pivot_records marker must contain 1..256 UTF-16 units")
      }
    }
    CombineColumns(values, sep, output) => {
      names(values, false)
      names([output], false)
      if values.length() < 2 || sep.char_length() > 16 {
        raise LoomError(
          "combine_columns requires at least two columns and a separator <=16 chars",
        )
      }
    }
    SegmentRows(c, _) => ignore(condition_to_json(c))
    CarryContext(c, values) => {
      ignore(condition_to_json(c))
      names(values, false)
    }
    Select(input, output) => {
      if input.is_empty() || input.length() > 64 {
        raise LoomError("select expects 1..64 input columns")
      }
      for name in input {
        names([name], false)
      }
      names(output, false)
      if input.length() != output.length() {
        raise LoomError("select names have different lengths")
      }
    }
    Filter(c) => ignore(condition_to_json(c))
    MapRows(r) => ignore(recipe_to_json(r))
    UpdateColumns(r) => ignore(recipe_to_json(r))
    SplitColumn(col, sep, output) | SplitColumnPadded(col, sep, output) => {
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
    Transpose
    | PromoteHeaders
    | DemoteHeaders
    | PreserveExtraColumns
    | FlattenRows => ()
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
  let steps = values.map(table_step_from_json)
  for i, step in steps {
    if step is PreserveExtraColumns && i != 0 {
      raise LoomError(
        "preserve_extra_columns must occur only as the first step",
      )
    }
  }
  { columns, steps, }
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
/// Additional incoming columns are ignored by default; a first-step
/// PreserveExtraColumns keeps them after the declared columns. Missing saved
/// columns always fail. Later projection or reshaping may still remove extras.
pub fn apply_pipeline(p : Pipeline, table : Table) -> Table raise LoomError {
  ignore(pipeline_to_json(p))
  let names = p.columns.copy()
  if !p.steps.is_empty() && p.steps[0] is PreserveExtraColumns {
    for name in table.columns {
      if !names.contains(name) {
        names.push(name)
      }
    }
  }
  let bound = transform_table(table, [Select(names, names)])
  transform_table(bound, p.steps)
}
