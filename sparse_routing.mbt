///|
/// Recognize an exact complementary copy-or-blank routing program. This is a
/// simplicity prior, never proof that a user's intended predicate is correct.
fn sparse_routing_cost(recipe : Recipe) -> Int32? {
  let plain : Array[Int32] = []
  let mut yes : (Int32, Int32)? = None
  let mut no : (Int32, Int32)? = None
  for output in recipe.outputs {
    match output.expression {
      Field(i) => {
        if plain.contains(i) {
          return None
        }
        plain.push(i)
      }
      If(Empty(Field(k)), Field(i), Literal("")) if yes is None =>
        yes = Some((k, i))
      If(Empty(Field(k)), Literal(""), Field(i)) if no is None =>
        no = Some((k, i))
      _ => return None
    }
  }
  guard yes is Some((k, i)) &&
    no == yes &&
    k < recipe.columns.length() &&
    !plain.contains(i) &&
    plain.length() + 1 == recipe.columns.length() else {
    return None
  }
  Some(12 + recipe.outputs.length())
}

///|
fn copy_or_blank(samples : Array[Example]) -> Expr? {
  if samples.all(e => e.output.is_empty()) {
    return Some(Literal(""))
  }
  for i in 0..<samples[0].input.length() {
    if samples.all(e => e.input[i] == e.output) {
      return Some(Field(i))
    }
  }
  None
}

///|
/// Finite empty/nonempty routing truth table; no literal-string guessing or
/// relaxation of the general string synthesizer's branch evidence rule.
fn sparse_routing_witness(
  tables : Array[Table],
  targets : Array[Table],
) -> TableStep? {
  let columns = tables[0].columns
  if columns.length() > 8 ||
    targets[0].columns.length() != columns.length() + 1 ||
    tables.any(t => t.columns != columns) ||
    targets.any(t => t.columns != targets[0].columns) {
    return None
  }
  for b, t in tables {
    if t.rows.length() != targets[b].rows.length() {
      return None
    }
    for r, row in t.rows {
      let original = row.filter(v => !v.is_empty())
      let target = targets[b].rows[r].filter(v => !v.is_empty())
      original.sort()
      target.sort()
      if original != target {
        return None
      }
    }
  }
  for k in 0..<columns.length() {
    let mut has_yes = false
    let mut has_no = false
    for t in tables {
      for row in t.rows {
        if row[k].is_empty() {
          has_yes = true
        } else {
          has_no = true
        }
      }
    }
    if !has_yes || !has_no {
      continue
    }
    let outputs : Array[OutputField] = []
    let mut valid = true
    for j, name in targets[0].columns {
      let all : Array[Example] = []
      for b, t in tables {
        for r, row in t.rows {
          all.push({ input: row, output: targets[b].rows[r][j], })
        }
      }
      if copy_or_blank(all) is Some(Field(i)) {
        outputs.push({ name, expression: Field(i), })
        continue
      }
      let a = copy_or_blank(all.filter(e => e.input[k].is_empty()))
      let b = copy_or_blank(all.filter(e => !e.input[k].is_empty()))
      guard a is Some(a) && b is Some(b) else {
        valid = false
        break
      }
      outputs.push({ name, expression: If(Empty(Field(k)), a, b), })
    }
    let recipe : Recipe = { columns, outputs, }
    if valid && sparse_routing_cost(recipe) is Some(_) {
      return Some(MapRows(recipe))
    }
  }
  None
}
