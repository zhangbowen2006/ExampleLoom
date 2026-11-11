///|
/// Infer a small regular capture grammar from shared literal context. This is
/// deliberately not arbitrary regex synthesis: output characters must all
/// belong to a supported ASCII class and at least one context must be shared.
fn inferred_capture_patterns(
  examples : Array[Example],
  column : Int32,
) -> Array[String] {
  if examples.any(e => e.output.is_empty()) {
    return []
  }
  let mut digits = true
  let mut letters = true
  let mut alnum = true
  let lefts : Array[Array[Char]] = []
  let rights : Array[Array[Char]] = []
  for e in examples {
    digits = digits && e.output.all(c => c.is_ascii_digit())
    letters = letters && e.output.all(c => c.is_ascii_alphabetic())
    alnum = alnum &&
      e.output.all(c => c.is_ascii_alphabetic() || c.is_ascii_digit())
    let input = e.input[column].to_array()
    let output = e.output.to_array()
    let mut position = -1
    for i = 0; i + output.length() <= input.length(); i = i + 1 {
      if char_slice(input, i, i + output.length()) == e.output {
        position = i
        break
      }
    }
    if position < 0 {
      return []
    }
    lefts.push(input[:position].to_owned())
    rights.push(input[position + output.length():].to_owned())
  }
  let kind = if digits {
    "[[:digit:]]+"
  } else if letters {
    "[[:alpha:]]+"
  } else if alnum {
    "[[:alnum:]]+"
  } else {
    return []
  }
  let mut before = 0
  let mut after = 0
  for n in 1..<17 {
    if lefts.all(s => {
        s.length() >= n && s[s.length() - n] == lefts[0][lefts[0].length() - n]
      }) {
      before = n
    } else {
      break
    }
  }
  for n in 1..<17 {
    if rights.all(s => s.length() >= n && s[n - 1] == rights[0][n - 1]) {
      after = n
    } else {
      break
    }
  }
  if before == 0 && after == 0 {
    return []
  }
  let left = regex_literal(
    char_slice(lefts[0], lefts[0].length() - before, lefts[0].length()),
  )
  let right = regex_literal(char_slice(rights[0], 0, after))
  let patterns = [left + "(" + kind + ")" + right]
  if before > 0 {
    patterns.push(left + "(" + kind + ")")
  }
  if after > 0 {
    patterns.push("(" + kind + ")" + right)
  }
  patterns
}

///|
/// Describe observed ASCII letter/digit runs and literal separators. Each
/// dynamic run is one group. Other alphabets can use an explicit regex hint.
fn capture_shape(text : String) -> String? {
  let out = StringBuilder()
  let mut previous = 0
  let mut groups = 0
  for c in text {
    let kind = if c.is_ascii_digit() {
      1
    } else if c.is_ascii_alphabetic() {
      2
    } else {
      0
    }
    if kind == 0 {
      if c.to_int() < 32 || c.to_int() > 126 {
        return None
      }
      out.write_string(regex_literal(c.to_string()))
    } else if kind != previous {
      groups = groups + 1
      if groups > 8 {
        return None
      }
      out.write_string(if kind == 1 { "([0-9]+)" } else { "([A-Za-z]+)" })
    }
    previous = kind
  }
  let pattern = out.to_string()
  if groups == 0 || pattern.length() > 180 {
    None
  } else {
    Some(pattern)
  }
}

///|
priv struct CaptureWitness {
  group : Int32
  values : Array[Array[Char]]
}

///|
/// Match all output cursors at once. Varying captures have priority over
/// literals. Revisiting the same cursors and reference count has the same
/// continuation. Capping that count at two keeps repeated references legal.
fn replacement_suffix(
  positions : Array[Int32],
  targets : Array[Array[Char]],
  witnesses : Array[CaptureWitness],
  references : Int32,
  visited : Map[String, Bool],
) -> String? {
  if finished(positions, targets) {
    return if references >= 2 { Some("") } else { None }
  }
  let key = Json(positions).stringify() + references.to_string()
  if visited.length() >= 256 || visited.contains(key) {
    return None
  }
  visited[key] = true
  for w in witnesses {
    if advance(positions, w.values, targets) is Some(next) {
      if replacement_suffix(
          next,
          targets,
          witnesses,
          Int32::min(2, references + 1),
          visited,
        )
        is Some(suffix) {
        return Some("$" + w.group.to_string() + suffix)
      }
    }
  }
  if positions[0] >= targets[0].length() {
    return None
  }
  let c = targets[0][positions[0]]
  for i, p in positions {
    if p >= targets[i].length() || targets[i][p] != c {
      return None
    }
  }
  replacement_suffix(
    positions.map(p => p + 1),
    targets,
    witnesses,
    references,
    visited,
  ).map(s => (if c == '$' { "$$" } else { c.to_string() }) + s)
}

///|
fn learn_replacements(
  pool : Pool,
  examples : Array[Example],
  col : Int32,
  hints : Array[String],
  options : SearchOptions,
) -> Unit {
  if examples.length() < 2 || examples.all(e => e.input[col] == e.output) {
    return
  }
  let patterns = hints.copy()
  if capture_shape(examples[0].input[col]) is Some(shape) &&
    examples.all(e => capture_shape(e.input[col]) == Some(shape)) &&
    !patterns.contains(shape) {
    patterns.push(shape)
  }
  let targets = examples.map(e => e.output.to_array())
  for pat in patterns {
    if pool.attempts >= options.max_atom_evaluations {
      pool.truncated = true
      break
    }
    if pat.length() > 248 {
      continue
    }
    let pattern = anchored_pattern(pat)
    let regex = compiled_regex(pattern) catch { _ => continue }
    let matches : Array[RegexMatch] = []
    for e in examples {
      let matched = regex.execute(e.input[col][:]) catch { _ => break }
      if matched is Some(m) {
        matches.push(m)
      } else {
        break
      }
    }
    if matches.length() != examples.length() {
      continue
    }
    let witnesses : Array[CaptureWitness] = []
    for g in 1..<10 {
      let values : Array[Array[Char]] = []
      for m in matches {
        if m.group(g) is Some(s) && !s.is_empty() {
          values.push(s.to_owned().to_array())
        } else {
          break
        }
      }
      if values.length() == matches.length() && values.any(v => v != values[0]) {
        witnesses.push({ group: g, values, })
      }
    }
    if witnesses.is_empty() {
      continue
    }
    let visited : Map[String, Bool] = Map([])
    let template = replacement_suffix(
      Array::make(examples.length(), 0),
      targets,
      witnesses,
      0,
      visited,
    )
    if visited.length() >= 256 {
      pool.truncated = true
    }
    if template is Some(t) {
      offer_atom(
        pool,
        RegexReplace(Field(col), pattern, t),
        10,
        examples,
        options,
      )
    }
  }
}
