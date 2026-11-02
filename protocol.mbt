///|
fn table_json(table : Table) -> Json {
  Json::object({ "columns": Json(table.columns), "rows": Json(table.rows) })
}

///|
fn table_from_json(value : Json) -> Table raise LoomError {
  let obj = j_object(value)
  let table = {
    columns: j_array(required(obj, "columns")).map(j_text),
    rows: j_array(required(obj, "rows")).map(r => j_array(r).map(j_text)),
  }
  validate_table(table)
  table
}

///|
fn prediction_json(prediction : Result[String, String]) -> Json {
  match prediction {
    Ok(value) => Json::object({ "ok": Json(true), "value": Json(value) })
    Err(message) => Json::object({ "ok": Json(false), "error": Json(message) })
  }
}

///|
fn option_int(
  obj : Map[String, Json],
  key : String,
  fallback : Int32,
) -> Int32 raise LoomError {
  match obj.get(key) {
    Some(v) => j_int(v)
    None => fallback
  }
}

///|
fn options_from_json(value : Json) -> SearchOptions raise LoomError {
  let obj = j_object(value)
  fields_only(obj, [
    "max_candidates", "max_parts", "max_atom_evaluations", "max_steps", "max_frontier",
  ])
  let defaults = default_options()
  {
    max_candidates: option_int(obj, "max_candidates", defaults.max_candidates),
    max_parts: option_int(obj, "max_parts", defaults.max_parts),
    max_atom_evaluations: option_int(
      obj,
      "max_atom_evaluations",
      defaults.max_atom_evaluations,
    ),
    max_steps: option_int(obj, "max_steps", defaults.max_steps),
    max_frontier: option_int(obj, "max_frontier", defaults.max_frontier),
  }
}

///|
fn dispatch(request : Json) -> Json raise LoomError {
  let obj = j_object(request)
  match j_text(required(obj, "op")) {
    "parse" => {
      let text = j_text(required(obj, "text"))
      let table = match j_text(required(obj, "format")) {
        "csv" => parse_csv(text)
        "jsonl" => parse_jsonl(text)
        _ => raise LoomError("format must be csv or jsonl")
      }
      Json::object({ "ok": Json(true), "table": table_json(table) })
    }
    "synthesize" => {
      let examples = j_array(required(obj, "examples")).map(v => {
        let e = j_object(v)
        Example::{
          input: j_array(required(e, "input")).map(j_text),
          output: j_text(required(e, "output")),
        }
      })
      let options = match obj.get("options") {
        Some(v) => options_from_json(v)
        None => default_options()
      }
      let rows = match obj.get("rows") {
        Some(v) => j_array(v).map(r => j_array(r).map(j_text))
        None => []
      }
      let report = synthesize(examples, options~)
      let suggestions = disagreements(report.candidates, rows)
      Json::object({
        "ok": Json(true),
        "status": Json(report.status),
        "truncated": Json(report.truncated),
        "stats": Json::object({
          "atom_evaluations": Json(report.atom_evaluations),
          "atoms": Json(report.atoms),
          "steps": Json(report.steps),
        }),
        "candidates": Json::array(
          report.candidates.map(c => {
            Json::object({
              "expression": expression_to_json(c.expression),
              "description": Json(explain(c.expression)),
              "cost": Json(c.cost),
            })
          }),
        ),
        "disagreements": Json::array(
          suggestions.map(s => {
            Json::object({
              "row_index": Json(s.row_index),
              "score": Json(s.score),
              "groups": Json::array(
                s.groups.map(g => {
                  Json::object({
                    "prediction": prediction_json(g.prediction),
                    "candidates": Json(g.candidates),
                  })
                }),
              ),
            })
          }),
        ),
      })
    }
    "validate_recipe" => {
      let recipe = recipe_from_json(required(obj, "recipe"))
      Json::object({
        "ok": Json(true),
        "recipe": recipe_to_json(recipe),
        "descriptions": Json(recipe.outputs.map(o => explain(o.expression))),
      })
    }
    "apply" => {
      let recipe = recipe_from_json(required(obj, "recipe"))
      let table = table_from_json(required(obj, "table"))
      let result = apply_recipe(recipe, table)
      let successful : Array[Array[String]] = []
      let rows = result.rows.map(r => {
        match r {
          Ok(values) => {
            successful.push(values)
            Json::object({ "ok": Json(true), "values": Json(values) })
          }
          Err(message) =>
            Json::object({ "ok": Json(false), "error": Json(message) })
        }
      })
      let safe = match obj.get("spreadsheet_safe") {
        Some(True) | None => true
        Some(False) => false
        _ => raise LoomError("spreadsheet_safe must be boolean")
      }
      // No partial CSV disguised as a complete result. JSON preserves row errors.
      let csv = if result.failures == 0 {
        Json(
          render_csv(
            { columns: recipe.outputs.map(o => o.name), rows: successful, },
            spreadsheet_safe=safe,
          ),
        )
      } else {
        Json::null()
      }
      Json::object({
        "ok": Json(true),
        "failures": Json(result.failures),
        "columns": Json(recipe.outputs.map(o => o.name)),
        "rows": Json::array(rows),
        "csv": csv,
      })
    }
    _ => raise LoomError("unknown operation")
  }
}

///|
/// Single JSON boundary shared by the Node CLI and browser worker. All data
/// parsing, search, recipe validation and transformation execute in MoonBit.
pub fn handle(request : String) -> String {
  try {
    if request.length() > 4000000 {
      raise LoomError("request exceeds 4000000 UTF-16 units")
    }
    dispatch(parse_json_text(request)).stringify()
  } catch {
    LoomError(message) =>
      Json::object({ "ok": Json(false), "error": Json(message) }).stringify()
  }
}
