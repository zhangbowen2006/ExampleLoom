///|
priv struct LearningBudget {
  mut atoms : Int32
  mut steps : Int32
  mut calls : Int32
  mut cached : Int32
  mut hits : Int32
  mut retained_atoms : Int32
  mut truncated : Bool
}

///|
fn predicate_pool(
  examples : Array[Example],
  patterns : Array[String],
) -> Array[Condition] {
  let result : Array[Condition] = []
  for col in 0..<examples[0].input.length() {
    result.push(Empty(Field(col)))
    for p in patterns {
      result.push(Matches(Field(col), p, false))
    }
    let values : Array[String] = []
    for e in examples {
      if !values.contains(e.input[col]) {
        values.push(e.input[col])
      }
    }
    values.sort()
    // High-cardinality columns should not induce a lookup table of row IDs.
    if values.length() <= 8 {
      for value in values {
        result.push(Equals(Field(col), Literal(value)))
      }
    }
  }
  result
}

///|
fn learn_branches(
  examples : Array[Example],
  options : SearchOptions,
  separators : Array[String],
  patterns : Array[String],
  depth : Int32,
  budget : LearningBudget,
) -> Array[Candidate] raise LoomError {
  if budget.calls >= 64 ||
    budget.atoms >= options.max_atom_evaluations ||
    budget.steps >= options.max_steps {
    budget.truncated = true
    return []
  }
  budget.calls = budget.calls + 1
  let atom_left = options.max_atom_evaluations - budget.atoms
  let step_left = options.max_steps - budget.steps
  let child_options : SearchOptions = {
    ..options,
    max_candidates: Int32::min(8, options.max_candidates),
    max_atom_evaluations: Int32::min(
      atom_left,
      if depth > 0 {
        3000
      } else {
        6000
      },
    ),
    max_steps: Int32::min(step_left, if depth > 0 { 15000 } else { 30000 }),
  }
  let report = synthesize_flat(
    examples,
    options=child_options,
    separators~,
    patterns~,
  )
  budget.atoms = budget.atoms + report.atom_evaluations
  budget.steps = budget.steps + report.steps
  budget.cached = budget.cached + report.cached_states
  budget.hits = budget.hits + report.cache_hits
  budget.retained_atoms = budget.retained_atoms + report.atoms
  budget.truncated = budget.truncated || report.truncated
  if !report.candidates.is_empty() || depth == 0 {
    return report.candidates
  }
  let candidates : Array[Candidate] = []
  let partitions : Map[String, Bool] = Map([])
  for condition in predicate_pool(examples, patterns) {
    let yes : Array[Example] = []
    let no : Array[Example] = []
    let mask : Array[Bool] = []
    for e in examples {
      let value = condition_at(condition, e.input, 0)
      mask.push(value)
      if value {
        yes.push(e)
      } else {
        no.push(e)
      }
    }
    // A singleton branch is an example lookup, not useful evidence of a rule.
    // Require two observations on each side; users can still author such a
    // conditional explicitly when the intended semantics are known.
    if yes.length() < 2 || no.length() < 2 {
      continue
    }
    let key = Json(mask).stringify()
    if partitions.contains(key) {
      continue
    }
    partitions[key] = true
    let left = learn_branches(
      yes,
      options,
      separators,
      patterns,
      depth - 1,
      budget,
    )
    if left.is_empty() {
      continue
    }
    let right = learn_branches(
      no,
      options,
      separators,
      patterns,
      depth - 1,
      budget,
    )
    if right.is_empty() {
      continue
    }
    for a in left[:Int32::min(2, left.length())] {
      for b in right[:Int32::min(2, right.length())] {
        candidates.push({
          expression: If(condition, a.expression, b.expression),
          cost: a.cost + b.cost + 8,
        })
        if candidates.length() >= options.max_candidates {
          budget.truncated = true
          return candidates
        }
      }
    }
  }
  candidates.sort_by((a, b) => {
    if a.cost != b.cost {
      a.cost - b.cost
    } else {
      explain(a.expression).compare(explain(b.expression))
    }
  })
  candidates
}

///|
/// Output-guided flat search with fallback decision-tree induction. Limits are
/// shared across all branch learners; a consistent program is not a guarantee
/// of generalization. Regex hints use the MoonBit core/lexmatch dialect.
pub fn synthesize(
  examples : Array[Example],
  options~ : SearchOptions = default_options(),
  separators~ : Array[String] = [],
  patterns~ : Array[String] = [],
  branch_depth~ : Int32 = 2,
) -> SearchReport raise LoomError {
  if options.max_candidates < 1 ||
    options.max_candidates > 256 ||
    options.max_parts < 1 ||
    options.max_parts > 8 ||
    options.max_atom_evaluations < 1 ||
    options.max_atom_evaluations > 100000 ||
    options.max_steps < 1 ||
    options.max_steps > 1000000 ||
    options.max_frontier < 1 ||
    options.max_frontier > 8192 {
    raise LoomError("invalid search limits")
  }
  if branch_depth < 0 || branch_depth > 3 {
    raise LoomError("branch_depth must be 0..3")
  }
  if patterns.length() > 16 {
    raise LoomError("expected at most 16 regex hints")
  }
  let patterns = patterns.copy()
  patterns.sort()
  for p in patterns {
    ignore(compiled_regex(p))
  }
  // Validate the same input and option contract even with no search budget.
  if branch_depth == 0 || examples.length() < 2 {
    return synthesize_flat(examples, options~, separators~, patterns~)
  }
  let first = synthesize_flat(
    examples,
    options={
      ..options,
      max_atom_evaluations: Int32::max(1, options.max_atom_evaluations / 2),
      max_steps: Int32::max(1, options.max_steps / 2),
    },
    separators~,
    patterns~,
  )
  // A flat solution takes precedence. Do not hide ambiguity behind a branch.
  if !first.candidates.is_empty() {
    return first
  }
  let budget = {
    atoms: first.atom_evaluations,
    steps: first.steps,
    calls: 1,
    cached: first.cached_states,
    hits: first.cache_hits,
    retained_atoms: first.atoms,
    truncated: first.truncated,
  }
  let candidates = learn_branches(
    canonical_examples(examples),
    options,
    separators,
    patterns,
    branch_depth,
    budget,
  )
  {
    candidates,
    status: if budget.truncated {
      "bounded_branch_search"
    } else {
      "exhausted_branch_grammar"
    },
    truncated: budget.truncated,
    atom_evaluations: budget.atoms,
    atoms: budget.retained_atoms,
    steps: budget.steps,
    cached_states: budget.cached,
    cache_hits: budget.hits,
  }
}
