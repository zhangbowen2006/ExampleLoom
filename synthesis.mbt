///|
/// All limits are deterministic. Hitting a resource limit is reported, never
/// interpreted as proof that the retained program is unique.
pub(all) struct SearchOptions {
  max_candidates : Int32
  max_parts : Int32
  max_atom_evaluations : Int32
  max_steps : Int32
  max_frontier : Int32
}

///|
pub fn default_options() -> SearchOptions {
  {
    max_candidates: 64,
    max_parts: 6,
    max_atom_evaluations: 30000,
    max_steps: 200000,
    max_frontier: 2048,
  }
}

///|
pub(all) struct Candidate {
  expression : Expr
  cost : Int32
}

///|
pub(all) struct SearchReport {
  candidates : Array[Candidate]
  status : String
  truncated : Bool
  atom_evaluations : Int32
  atoms : Int32
  steps : Int32
}

///|
priv struct Atom {
  expression : Expr
  values : Array[Array[Char]]
  cost : Int32
}

///|
priv struct Pool {
  atoms : Array[Atom]
  seen : Map[String, Bool]
  mut attempts : Int32
  mut truncated : Bool
}

///|
fn offer_atom(
  pool : Pool,
  expression : Expr,
  cost : Int32,
  examples : Array[Example],
  options : SearchOptions,
) -> Unit {
  if pool.attempts >= options.max_atom_evaluations {
    pool.truncated = true
    return
  }
  let key = explain(expression)
  if pool.seen.contains(key) {
    return
  }
  pool.seen[key] = true
  pool.attempts = pool.attempts + 1
  let values : Array[Array[Char]] = []
  let mut progresses = false
  for e in examples {
    match attempt(expression, e.input) {
      Ok(value) => {
        if !e.output.contains(value) {
          return
        }
        if !value.is_empty() {
          progresses = true
        }
        values.push(value.to_array())
      }
      Err(_) => return
    }
  }
  if progresses {
    pool.atoms.push({ expression, values, cost, })
  }
}

///|
fn offer_variants(
  pool : Pool,
  expression : Expr,
  cost : Int32,
  examples : Array[Example],
  options : SearchOptions,
) -> Unit {
  offer_atom(pool, expression, cost, examples, options)
  // Identity variants are omitted from the observed grammar when their first
  // example does not change. This is a search restriction, not equivalence.
  match attempt(expression, examples[0].input) {
    Ok(text) => {
      if text.trim().to_owned() != text {
        offer_atom(pool, Trim(expression), cost + 1, examples, options)
      }
      if text.any(c => c.is_ascii_uppercase()) {
        offer_atom(pool, Lower(expression), cost + 2, examples, options)
      }
      if text.any(c => c.is_ascii_lowercase()) {
        offer_atom(pool, Upper(expression), cost + 2, examples, options)
      }
    }
    Err(_) => ()
  }
}

///|
fn build_atoms(examples : Array[Example], options : SearchOptions) -> Pool {
  let pool = { atoms: [], seen: Map([]), attempts: 0, truncated: false, }
  // Structural selectors before positional slices prevents the latter from
  // exhausting the atom budget before the more general selectors are tried.
  for col in 0..<examples[0].input.length() {
    let base = Field(col)
    let text = examples[0].input[col]
    let structural : Array[(Expr, Int32)] = [(base, 2), (Trim(base), 3)]
    for separator in ["-", "_", " ", "/", ".", ":", "|", ",", "::", " / "] {
      let parts = text.split(separator).collect()
      if parts.length() <= 1 {
        continue
      }
      for k in 0..<parts.length() {
        structural.push((Token(base, separator, k), 5))
        structural.push((Token(base, separator, k - parts.length()), 5))
      }
    }
    for kind in [Digits, Letters] {
      let count = runs(text, kind).length()
      for k in 0..<count {
        structural.push((Run(base, kind, k), 6))
        structural.push((Run(base, kind, k - count), 6))
      }
    }
    for pair in structural {
      let (expr, cost) = pair
      offer_variants(pool, expr, cost, examples, options)
      for source in date_formats() {
        // Date validation is attempted explicitly; never infer debug-like
        // claims from a proxy. Invalid calendar inputs cannot yield programs.
        let valid = try {
          ignore(
            convert_date(evaluate(expr, examples[0].input), source, "YYYYMMDD"),
          )
          true
        } catch {
          _ => false
        }
        if valid {
          for target in date_formats() {
            if source != target {
              offer_atom(
                pool,
                DateText(expr, source, target),
                cost + 4,
                examples,
                options,
              )
            }
          }
        }
      }
    }
  }
  for col in 0..<examples[0].input.length() {
    let n = examples[0].input[col].char_length()
    for a in 0..<n {
      for b = a + 1; b <= n; b = b + 1 {
        if pool.attempts >= options.max_atom_evaluations {
          pool.truncated = true
          return pool
        }
        for from in [Start(a), End(n - a)] {
          for to in [Start(b), End(n - b)] {
            offer_variants(
              pool,
              Slice(Field(col), from, to),
              12,
              examples,
              options,
            )
          }
        }
      }
    }
  }
  pool
}

///|
priv struct SearchNode {
  positions : Array[Int32]
  parts : Array[Expr]
  cost : Int32
  serial : Int32
}

///|
fn node_before(a : SearchNode, b : SearchNode) -> Bool {
  a.cost < b.cost || (a.cost == b.cost && a.serial < b.serial)
}

// A small deterministic min heap; the frontier itself is strictly bounded.

///|
fn heap_push(heap : Array[SearchNode], node : SearchNode) -> Unit {
  heap.push(node)
  let mut i = heap.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if !node_before(heap[i], heap[parent]) {
      break
    }
    let tmp = heap[parent]
    heap[parent] = heap[i]
    heap[i] = tmp
    i = parent
  }
}

///|
fn heap_pop(heap : Array[SearchNode]) -> SearchNode {
  let result = heap[0]
  let last = heap.pop().unwrap()
  if heap.is_empty() {
    return result
  }
  heap[0] = last
  let mut i = 0
  while 2 * i + 1 < heap.length() {
    let left = 2 * i + 1
    let right = left + 1
    let child = if right < heap.length() && node_before(heap[right], heap[left]) {
      right
    } else {
      left
    }
    if !node_before(heap[child], heap[i]) {
      break
    }
    let tmp = heap[i]
    heap[i] = heap[child]
    heap[child] = tmp
    i = child
  }
  result
}

///|
fn advance(
  positions : Array[Int32],
  values : Array[Array[Char]],
  targets : Array[Array[Char]],
) -> Array[Int32]? {
  let next : Array[Int32] = []
  for i in 0..<targets.length() {
    let p = positions[i]
    if p + values[i].length() > targets[i].length() {
      return None
    }
    for j in 0..<values[i].length() {
      if values[i][j] != targets[i][p + j] {
        return None
      }
    }
    next.push(p + values[i].length())
  }
  Some(next)
}

///|
fn finished(positions : Array[Int32], targets : Array[Array[Char]]) -> Bool {
  for i in 0..<positions.length() {
    if positions[i] != targets[i].length() {
      return false
    }
  }
  true
}

///|
fn common_literals(
  positions : Array[Int32],
  targets : Array[Array[Char]],
) -> Array[Atom] {
  let atoms : Array[Atom] = []
  let start = positions[0]
  for n = 1; start + n <= targets[0].length(); n = n + 1 {
    let value = char_slice(targets[0], start, start + n)
    let values = Array::make(targets.length(), value.to_array())
    if advance(positions, values, targets) is None {
      break
    }
    atoms.push({ expression: Literal(value), values, cost: 40 + n, })
  }
  atoms
}

///|
/// Enumerate a ranked subset of programs consistent with every example.
/// Ranking is a simplicity preference, never a statistical confidence score.
pub fn synthesize(
  examples : Array[Example],
  options~ : SearchOptions = default_options(),
) -> SearchReport raise LoomError {
  if examples.is_empty() || examples.length() > 32 {
    raise LoomError("expected 1..32 examples")
  }
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
  let width = examples[0].input.length()
  if width < 1 || width > 16 {
    raise LoomError("synthesis expects 1..16 input columns")
  }
  for i, e in examples {
    if e.input.length() != width {
      raise LoomError("example column counts differ")
    }
    if e.output.char_length() > 128 {
      raise LoomError("example output exceeds 128 characters")
    }
    for cell in e.input {
      if cell.char_length() > 128 {
        raise LoomError("example input exceeds 128 characters")
      }
    }
    for j in 0..<i {
      if e.input == examples[j].input && e.output != examples[j].output {
        raise LoomError(
          "contradictory examples: identical input has different outputs",
        )
      }
    }
  }
  let pool = build_atoms(examples, options)
  let targets = examples.map(e => e.output.to_array())
  let frontier : Array[SearchNode] = [
    {
      positions: Array::make(examples.length(), 0),
      parts: [],
      cost: 0,
      serial: 0,
    },
  ]
  let candidates : Array[Candidate] = []
  let seen : Map[String, Bool] = Map([])
  let mut steps = 0
  let mut serial = 1
  let mut truncated = pool.truncated
  let mut status = if pool.truncated {
    "atom_limit"
  } else {
    "exhausted_observed_grammar"
  }
  while !frontier.is_empty() {
    let node = heap_pop(frontier)
    if finished(node.positions, targets) {
      let expression = if node.parts.is_empty() {
        Literal("")
      } else if node.parts.length() == 1 {
        node.parts[0]
      } else {
        Concat(node.parts)
      }
      let key = explain(expression)
      if !seen.contains(key) {
        seen[key] = true
        candidates.push({ expression, cost: node.cost, })
        if candidates.length() == options.max_candidates {
          if !frontier.is_empty() {
            truncated = true
            status = "candidate_limit"
          }
          break
        }
      }
      continue
    }
    if node.parts.length() >= options.max_parts {
      continue
    }
    let transitions = pool.atoms.copy()
    // Adjacent literals have a canonical merged spelling; don't enumerate
    // their exponentially many equivalent segmentations.
    if node.parts.is_empty() ||
      !(node.parts[node.parts.length() - 1] is Literal(_)) {
      transitions.push_iter(common_literals(node.positions, targets).iter())
    }
    for atom in transitions {
      if steps >= options.max_steps {
        truncated = true
        status = "step_limit"
        break
      }
      steps = steps + 1
      if advance(node.positions, atom.values, targets) is Some(positions) {
        if frontier.length() >= options.max_frontier {
          truncated = true
          status = "frontier_limit"
          continue
        }
        let parts = node.parts.copy()
        parts.push(atom.expression)
        heap_push(frontier, {
          positions,
          parts,
          cost: node.cost + atom.cost,
          serial,
        })
        serial = serial + 1
      }
    }
    if status == "step_limit" {
      break
    }
  }
  {
    candidates,
    status,
    truncated,
    atom_evaluations: pool.attempts,
    atoms: pool.atoms.length(),
    steps,
  }
}
