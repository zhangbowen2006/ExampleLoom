///|
pub(all) enum DataOperation {
  JoinSources(String, String, JoinSpec)
  ConcatSources(Array[String], UnionSpec)
  TransformSource(String, Pipeline)
}

///|
pub(all) struct DataStage {
  name : String
  operation : DataOperation
}

///|
pub(all) struct DataJob {
  sources : Array[String]
  stages : Array[DataStage]
  output : String
}

///|
fn validate_data_job(job : DataJob) -> Unit raise LoomError {
  if job.sources.is_empty() ||
    job.sources.length() > 8 ||
    job.stages.is_empty() ||
    job.stages.length() > 8 {
    raise LoomError("job requires 1..8 sources and 1..8 stages")
  }
  validate_columns(job.sources + job.stages.map(s => s.name))
  let known = job.sources.copy()
  for stage in job.stages {
    let inputs = match stage.operation {
      JoinSources(left, right, spec) => {
        validate_join(spec)
        [left, right]
      }
      ConcatSources(inputs, spec) => {
        validate_union(spec)
        if inputs.is_empty() || inputs.length() > 8 {
          raise LoomError("concat stage requires 1..8 distinct sources")
        }
        validate_columns(inputs)
        inputs
      }
      TransformSource(source, pipeline) => {
        ignore(pipeline_to_json(pipeline))
        [source]
      }
    }
    if inputs.any(name => !known.contains(name)) {
      raise LoomError(
        "job contains unknown or forward source reference at stage \{stage.name}",
      )
    }
    known.push(stage.name)
  }
  if job.output != job.stages[job.stages.length() - 1].name {
    raise LoomError("job output must name the final stage")
  }
}

///|
pub fn data_job_to_json(job : DataJob) -> Json raise LoomError {
  validate_data_job(job)
  let value = Json::object({
    "version": Json(1),
    "sources": Json(job.sources),
    "output": Json(job.output),
    "stages": Json::array(
      job.stages.map(stage => {
        match stage.operation {
          JoinSources(left, right, spec) =>
            Json::object({
              "name": Json(stage.name),
              "kind": Json("join"),
              "left": Json(left),
              "right": Json(right),
              "spec": join_spec_to_json(spec),
            })
          ConcatSources(sources, spec) =>
            Json::object({
              "name": Json(stage.name),
              "kind": Json("concat"),
              "sources": Json(sources),
              "spec": union_spec_to_json(spec),
            })
          TransformSource(source, pipeline) =>
            Json::object({
              "name": Json(stage.name),
              "kind": Json("transform"),
              "source": Json(source),
              "pipeline": pipeline_to_json(pipeline),
            })
        }
      }),
    ),
  })
  if value.stringify().length() > 262144 {
    raise LoomError("job exceeds 262144 UTF-16 units")
  }
  value
}

///|
pub fn data_job_from_json(v : Json) -> DataJob raise LoomError {
  if v.stringify().length() > 262144 {
    raise LoomError("job exceeds 262144 UTF-16 units")
  }
  let obj = j_object(v)
  fields_only(obj, ["version", "sources", "stages", "output"])
  if j_int(required(obj, "version")) != 1 {
    raise LoomError("unsupported data job version")
  }
  let stages = j_array(required(obj, "stages")).map(v => {
    let s = j_object(v)
    let operation = match j_text(required(s, "kind")) {
      "join" => {
        fields_only(s, ["name", "kind", "left", "right", "spec"])
        JoinSources(
          j_text(required(s, "left")),
          j_text(required(s, "right")),
          join_spec_from_json(required(s, "spec")),
        )
      }
      "concat" => {
        fields_only(s, ["name", "kind", "sources", "spec"])
        ConcatSources(
          json_strings(required(s, "sources")),
          union_spec_from_json(required(s, "spec")),
        )
      }
      "transform" => {
        fields_only(s, ["name", "kind", "source", "pipeline"])
        TransformSource(
          j_text(required(s, "source")),
          pipeline_from_json(required(s, "pipeline")),
        )
      }
      _ => raise LoomError("unknown data job stage")
    }
    DataStage::{ name: j_text(required(s, "name")), operation, }
  })
  let job : DataJob = {
    sources: json_strings(required(obj, "sources")),
    stages,
    output: j_text(required(obj, "output")),
  }
  validate_data_job(job)
  job
}

///|
fn job_pipeline(p : Pipeline, source : Table) -> Table raise LoomError {
  if p.steps.is_empty() {
    return apply_pipeline(p, source)
  }
  let mut table = apply_pipeline(
    { columns: p.columns, steps: [p.steps[0]], },
    source,
  )
  validate_sources([table])
  for i = 1; i < p.steps.length(); i = i + 1 {
    table = transform_table(table, [p.steps[i]]) catch {
      LoomError(message) => raise LoomError("pipeline step \{i+1}: \{message}")
    }
    validate_sources([table])
  }
  table
}

///|
/// A pure named-table DAG. No files, URLs, credentials, shell or executable code.
/// Every stage is validated before any data executes; only the final table returns.
pub fn run_data_job(
  job : DataJob,
  sources : Array[NamedTable],
) -> Table raise LoomError {
  ignore(data_job_to_json(job))
  validate_columns(sources.map(s => s.name))
  if sources.length() != job.sources.length() ||
    sources.any(s => !job.sources.contains(s.name)) {
    raise LoomError("job source bindings must match the declared names exactly")
  }
  validate_sources(sources.map(s => s.table))
  let tables : Map[String, Table] = Map([])
  let resident = sources.map(s => s.table)
  for s in sources {
    tables[s.name] = s.table
  }
  fn get(name : String) -> Table raise LoomError {
    match tables.get(name) {
      Some(table) => table
      None => raise LoomError("missing job source \{name}")
    }
  }
  let mut result = sources[0].table
  for stage in job.stages {
    result = try {
      match stage.operation {
        JoinSources(left, right, spec) =>
          join_tables(get(left), get(right), spec)
        ConcatSources(names, spec) =>
          concat_tables(
            names.map(name => NamedTable::{ name, table: get(name), }),
            spec,
          )
        TransformSource(source, pipeline) => job_pipeline(pipeline, get(source))
      }
    } catch {
      LoomError(message) =>
        raise LoomError("job stage \{stage.name}: \{message}")
    }
    // Include all retained intermediates; do not multiply the resident budget
    // by the number of stages. No partial result escapes when a limit fails.
    validate_sources(resident + [result]) catch {
      LoomError(message) =>
        raise LoomError("job stage \{stage.name}, resident tables: \{message}")
    }
    resident.push(result)
    tables[stage.name] = result
  }
  { columns: result.columns.copy(), rows: result.rows.map(r => r.copy()), }
}
