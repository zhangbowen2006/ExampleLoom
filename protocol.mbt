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
    "synthesize_join_jobs" => {
      fields_only(obj, ["op", "examples", "options"])
      let examples = j_array(required(obj, "examples")).map(v => {
        let e = j_object(v)
        fields_only(e, ["sources", "output"])
        let sources = j_array(required(e, "sources")).map(v => {
          let s = j_object(v)
          fields_only(s, ["name", "table"])
          NamedTable::{
            name: j_text(required(s, "name")),
            table: table_from_json(required(s, "table")),
          }
        })
        JoinExample::{ sources, after: table_from_json(required(e, "output")), }
      })
      let defaults = default_join_search_options()
      let options = match obj.get("options") {
        None => defaults
        Some(v) => {
          let o = j_object(v)
          fields_only(o, ["max_evaluations", "max_candidates", "max_keys"])
          JoinSearchOptions::{
            max_evaluations: option_int(
              o,
              "max_evaluations",
              defaults.max_evaluations,
            ),
            max_candidates: option_int(
              o,
              "max_candidates",
              defaults.max_candidates,
            ),
            max_keys: option_int(o, "max_keys", defaults.max_keys),
          }
        }
      }
      let report = synthesize_join_jobs(examples, options~)
      Json::object({
        "ok": Json(true),
        "status": Json(report.status),
        "truncated": Json(report.truncated),
        "evaluations": Json(report.evaluations),
        "filter_evaluations": Json(report.filter_evaluations),
        "rejected": Json(report.rejected),
        "candidates": Json::array(
          report.candidates.map(job => {
            Json::object({ "job": data_job_to_json(job) })
          }),
        ),
      })
    }
    "validate_data_job" => {
      fields_only(obj, ["op", "job"])
      Json::object({
        "ok": Json(true),
        "job": data_job_to_json(data_job_from_json(required(obj, "job"))),
      })
    }
    "run_data_job" => {
      fields_only(obj, ["op", "job", "sources"])
      let sources = j_array(required(obj, "sources")).map(v => {
        let s = j_object(v)
        fields_only(s, ["name", "table"])
        NamedTable::{
          name: j_text(required(s, "name")),
          table: table_from_json(required(s, "table")),
        }
      })
      let job = data_job_from_json(required(obj, "job"))
      let table = run_data_job(job, sources)
      Json::object({
        "ok": Json(true),
        "table": table_json(table),
        "csv": Json(render_csv(table)),
        "completed_stages": Json(job.stages.length()),
      })
    }
    "execute_table" => {
      fields_only(obj, ["op", "pipelines", "table", "chosen"])
      let chosen = match obj.get("chosen") {
        None => None
        Some(v) => Some(j_int(v))
      }
      let result = execute_table_candidates(
        j_array(required(obj, "pipelines")).map(pipeline_from_json),
        table_from_json(required(obj, "table")),
        chosen~,
      )
      Json::object({
        "ok": Json(true),
        "table": table_json(result.table),
        "csv": Json(render_csv(result.table)),
        "selection": Json(result.selection),
        "chosen": match result.chosen {
          None => Json::null()
          Some(i) => Json(i)
        },
      })
    }
    "concat_tables" => {
      fields_only(obj, ["op", "sources", "spec"])
      let sources = j_array(required(obj, "sources")).map(v => {
        let s = j_object(v)
        fields_only(s, ["name", "table"])
        NamedTable::{
          name: j_text(required(s, "name")),
          table: table_from_json(required(s, "table")),
        }
      })
      let table = concat_tables(
        sources,
        union_spec_from_json(required(obj, "spec")),
      )
      Json::object({
        "ok": Json(true),
        "table": table_json(table),
        "csv": Json(render_csv(table)),
      })
    }
    "join_tables" => {
      fields_only(obj, ["op", "left", "right", "spec"])
      let table = join_tables(
        table_from_json(required(obj, "left")),
        table_from_json(required(obj, "right")),
        join_spec_from_json(required(obj, "spec")),
      )
      Json::object({
        "ok": Json(true),
        "table": table_json(table),
        "csv": Json(render_csv(table)),
      })
    }
    "parse" => {
      let text = j_text(required(obj, "text"))
      let table = match j_text(required(obj, "format")) {
        "csv" => parse_csv(text)
        "jsonl" => parse_jsonl(text)
        _ => raise LoomError("format must be csv or jsonl")
      }
      Json::object({ "ok": Json(true), "table": table_json(table) })
    }
    "synthesize_table" => {
      fields_only(obj, [
        "op", "examples", "options", "patterns", "separators", "intent", "layouts",
      ])
      let examples = j_array(required(obj, "examples")).map(v => {
        let e = j_object(v)
        TableExample::{
          before: table_from_json(required(e, "input")),
          after: table_from_json(required(e, "output")),
        }
      })
      let defaults = default_table_options()
      let options = match obj.get("options") {
        None => defaults
        Some(v) => {
          let o = j_object(v)
          fields_only(o, [
            "max_depth", "max_states", "max_evaluations", "max_candidates",
          ])
          TableSearchOptions::{
            max_depth: option_int(o, "max_depth", defaults.max_depth),
            max_states: option_int(o, "max_states", defaults.max_states),
            max_evaluations: option_int(
              o,
              "max_evaluations",
              defaults.max_evaluations,
            ),
            max_candidates: option_int(
              o,
              "max_candidates",
              defaults.max_candidates,
            ),
          }
        }
      }
      let patterns = match obj.get("patterns") {
        Some(v) => json_strings(v)
        None => []
      }
      let separators = match obj.get("separators") {
        Some(v) => json_strings(v)
        None => default_table_separators()
      }
      let intent = match obj.get("intent") {
        Some(v) => j_text(v)
        None => "infer"
      }
      let r = match obj.get("layouts") {
        None =>
          synthesize_table(examples, options~, separators~, patterns~, intent~)
        Some(v) =>
          synthesize_table_with_layouts(
            examples,
            layout_rules_from_json(v),
            options~,
            separators~,
            patterns~,
            intent~,
          )
      }
      Json::object({
        "ok": Json(true),
        "status": Json(r.status),
        "truncated": Json(r.truncated),
        "stats": Json::object({
          "states": Json(r.states),
          "evaluations": Json(r.evaluations),
          "rejected": Json(r.rejected),
          "row_searches": Json(r.row_searches),
        }),
        "candidates": Json::array(
          r.candidates.map(p => {
            Json::object({
              "pipeline": pipeline_to_json(p),
              "cost": Json(pipeline_cost(p)),
              "description": Json::array(p.steps.map(table_step_to_json)),
            })
          }),
        ),
      })
    }
    "propose_table_input" => {
      fields_only(obj, ["op", "pipelines", "inputs"])
      let report = propose_table_input(
        j_array(required(obj, "pipelines")).map(pipeline_from_json),
        j_array(required(obj, "inputs")).map(table_from_json),
      )
      Json::object({
        "ok": Json(true),
        "attempted": Json(report.attempted),
        "skipped": Json(report.skipped),
        "suggestion": match report.suggestion {
          None => Json::null()
          Some(s) =>
            Json::object({
              "source_index": Json(s.source_index),
              "mutation": Json(s.mutation),
              "input": table_json(s.table),
              "csv": Json(render_csv(s.table, spreadsheet_safe=false)),
              "score": Json(s.score),
              "groups": Json(s.groups),
            })
        },
      })
    }
    "compare_table_candidates" => {
      fields_only(obj, ["op", "pipelines", "table"])
      let r = compare_table_candidates(
        j_array(required(obj, "pipelines")).map(pipeline_from_json),
        table_from_json(required(obj, "table")),
      )
      let first_difference = match r.first_difference {
        None => Json::null()
        Some(ColumnNames) => Json::object({ "kind": Json("columns") })
        Some(RowCount) => Json::object({ "kind": Json("row_count") })
        Some(Cell(row, column)) =>
          Json::object({
            "kind": Json("cell"),
            "row_index": Json(row),
            "column_index": Json(column),
          })
        Some(Execution) => Json::object({ "kind": Json("error") })
      }
      Json::object({
        "ok": Json(true),
        "status": Json(r.status),
        "successful_candidates": Json(r.successful_candidates),
        "first_difference": first_difference,
        "groups": Json::array(
          r.groups.map(g => {
            let prediction = match g.prediction {
              Ok(table) =>
                Json::object({ "ok": Json(true), "table": table_json(table) })
              Err(message) =>
                Json::object({ "ok": Json(false), "error": Json(message) })
            }
            Json::object({
              "candidates": Json(g.candidates),
              "prediction": prediction,
            })
          }),
        ),
      })
    }
    "validate_pipeline" =>
      Json::object({
        "ok": Json(true),
        "pipeline": pipeline_to_json(
          pipeline_from_json(required(obj, "pipeline")),
        ),
      })
    "transform" => {
      let p = pipeline_from_json(required(obj, "pipeline"))
      let output = apply_pipeline(p, table_from_json(required(obj, "table")))
      let safe = match obj.get("spreadsheet_safe") {
        Some(False) => false
        Some(True) | None => true
        _ => raise LoomError("spreadsheet_safe must be boolean")
      }
      Json::object({
        "ok": Json(true),
        "table": table_json(output),
        "csv": Json(render_csv(output, spreadsheet_safe=safe)),
      })
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
      let separators = match obj.get("separators") {
        Some(v) => j_array(v).map(j_text)
        None => []
      }
      let patterns = match obj.get("patterns") {
        Some(v) => j_array(v).map(j_text)
        None => []
      }
      let branch_depth = option_int(obj, "branch_depth", 2)
      let report = synthesize(
        examples,
        options~,
        separators~,
        patterns~,
        branch_depth~,
      )
      let suggestions = disagreements(report.candidates, rows)
      Json::object({
        "ok": Json(true),
        "status": Json(report.status),
        "truncated": Json(report.truncated),
        "stats": Json::object({
          "atom_evaluations": Json(report.atom_evaluations),
          "atoms": Json(report.atoms),
          "steps": Json(report.steps),
          "cached_states": Json(report.cached_states),
          "cache_hits": Json(report.cache_hits),
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
