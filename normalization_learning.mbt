///|
/// Infer a single token rewrite only when all the other tokens align with an
/// observed output segment. Neither task names nor future rows are available.
fn normalization_bases(
  examples : Array[Example],
  column : Int32,
) -> Array[Expr] {
  let base = Field(column)
  let result : Array[Expr] = [base]
  let seen : Map[String, Bool] = Map([])
  for separator in [",", ";", "|", "/"] {
    for e in examples {
      let before = e.input[column]
        .split(separator)
        .map(s => s.trim().to_owned())
        .collect()
      let after = e.output
        .split(separator)
        .map(s => s.trim().to_owned())
        .collect()
      if before.length() < 2 ||
        before.length() > 8 ||
        after.length() < before.length() {
        continue
      }
      for offset in 0..<(after.length() - before.length() + 1) {
        for index in 0..<before.length() {
          let from = before[index]
          let to = after[offset + index]
          if from == to ||
            from.is_empty() ||
            to.is_empty() ||
            from.length() > 32 ||
            to.length() > 32 {
            continue
          }
          let mut aligned = true
          for k in 0..<before.length() {
            if k != index && before[k] != after[offset + k] {
              aligned = false
              break
            }
          }
          if !aligned {
            continue
          }
          let sep = regex_literal(separator)
          let prefix = if index == 0 {
            ""
          } else {
            "(?:[^" + sep + "]*" + sep + "){" + index.to_string() + "}"
          }
          let pattern = "^(" +
            prefix +
            "[[:space:]]*)" +
            regex_literal(from) +
            "([[:space:]]*(?:" +
            sep +
            "|$))"
          let replacement = "$1" + to.replace(old="$", new="$$") + "$2"
          let key = pattern + "\n" + replacement
          if !seen.contains(key) {
            seen[key] = true
            result.push(RegexReplace(base, pattern, replacement))
            if result.length() >= 17 {
              return result
            }
          }
        }
      }
    }
  }
  result
}

///|
/// A shared output suffix can be an optional field suffix. A guard makes
/// applying the learned normalization twice idempotent.
fn learn_normalizations(
  pool : Pool,
  examples : Array[Example],
  column : Int32,
  options : SearchOptions,
) -> Unit {
  if examples.length() < 2 {
    return
  }
  let targets = examples.map(e => e.output.to_array())
  let first = targets[0]
  let suffixes : Array[String] = []
  for length in 1..<(Int32::min(32, first.length()) + 1) {
    let suffix = char_slice(first, first.length() - length, first.length())
    if !examples.all(e => e.output.has_suffix(suffix)) {
      break
    }
    suffixes.push(suffix)
  }
  let bases = normalization_bases(examples, column)
  if bases.length() >= 17 {
    pool.truncated = true
  }
  for base in bases {
    offer_atom(pool, base, expression_cost(base), examples, options)
    for suffix in suffixes {
      if pool.attempts >= options.max_atom_evaluations {
        pool.truncated = true
        return
      }
      let values : Array[String] = []
      for e in examples {
        match attempt(base, e.input) {
          Ok(value) => values.push(value)
          Err(_) => break
        }
      }
      if values.length() != examples.length() {
        continue
      }
      let present = values.filter(v => v.has_suffix(suffix)).length()
      if present == 0 || present == values.length() {
        continue
      }
      let expression = If(
        Matches(base, regex_literal(suffix) + "$", false),
        base,
        Concat([base, Literal(suffix)]),
      )
      offer_atom(
        pool,
        expression,
        12 + expression_cost(base) + suffix.char_length(),
        examples,
        options,
      )
    }
  }
}
