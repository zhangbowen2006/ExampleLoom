///|
/// Rules are supplied by the caller; only the canonical downstream program is
/// learned. The normalization prefix shares depth/state/evaluation budgets.
pub fn synthesize_table_with_layouts(
  examples : Array[TableExample],
  rules : Array[LayoutRule],
  options~ : TableSearchOptions = default_table_options(),
  separators~ : Array[String] = default_table_separators(),
  patterns~ : Array[String] = [],
  intent~ : String = "infer",
) -> TableSearchReport raise LoomError {
  validate_table_search_config(options, separators, patterns, intent)
  validate_layout_rules(rules)
  if examples.is_empty() || examples.length() > 8 {
    raise LoomError("expected 1..8 table pairs")
  }
  for e in examples {
    validate_table(e.before)
    validate_table(e.after)
    if e.before.rows.length() > 128 ||
      e.before.columns.length() > 16 ||
      e.after.rows.length() > 512 ||
      e.after.columns.length() > 32 {
      raise LoomError(
        "layout training limit: 128 input rows, 512 output rows, 16 input/32 output columns",
      )
    }
  }
  let limited : TableSearchReport = {
    candidates: [],
    truncated: true,
    status: "table_search_limit",
    states: 1,
    evaluations: 0,
    rejected: 0,
    row_searches: 0,
  }
  if options.max_depth == 0 {
    return limited
  }
  let normalized : Array[TableExample] = []
  for i, e in examples {
    let table = transform_table(e.before, [NormalizeLayouts(rules)]) catch {
      LoomError(message) =>
        raise LoomError("training pair \{i+1} normalization: \{message}")
    }
    normalized.push({ before: table, after: e.after, })
  }
  let prefix : Pipeline = {
    columns: examples[0].before.columns,
    steps: [NormalizeLayouts(rules)],
  }
  if intent == "infer" && normalized.all(e => e.before == e.after) {
    return {
      ..limited,
      candidates: [prefix],
      truncated: false,
      status: "normalization_checked",
      evaluations: 1,
    }
  }
  if options.max_depth == 1 ||
    options.max_states == 1 ||
    options.max_evaluations == 1 {
    return { ..limited, evaluations: 1, }
  }
  let report = synthesize_table(
    normalized,
    options={
      ..options,
      max_depth: options.max_depth - 1,
      max_states: options.max_states - 1,
      max_evaluations: options.max_evaluations - 1,
    },
    separators~,
    patterns~,
    intent~,
  )
  let candidates = report.candidates.map(p => Pipeline::{
    columns: prefix.columns,
    steps: prefix.steps + p.steps,
  })
  for p in candidates {
    for e in examples {
      if apply_pipeline(p, e.before) != e.after {
        raise LoomError("internal layout pipeline replay mismatch")
      }
    }
  }
  {
    ..report,
    candidates,
    states: report.states + 1,
    evaluations: report.evaluations + 1,
  }
}
