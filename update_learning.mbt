///| Rebind expression indices while collecting only the input names that an

///|
/// update actually reads. Unknown added columns can then survive replay.
fn compact_condition(
  c : Condition,
  columns : Array[String],
  used : Array[String],
) -> Condition {
  match c {
    Equals(a, b) =>
      Equals(compact_expr(a, columns, used), compact_expr(b, columns, used))
    Matches(e, p, full) => Matches(compact_expr(e, columns, used), p, full)
    Empty(e) => Empty(compact_expr(e, columns, used))
    Not(c) => Not(compact_condition(c, columns, used))
    All(cs) => All(cs.map(c => compact_condition(c, columns, used)))
    Any(cs) => Any(cs.map(c => compact_condition(c, columns, used)))
  }
}

///|
fn compact_expr(
  e : Expr,
  columns : Array[String],
  used : Array[String],
) -> Expr {
  match e {
    Field(i) => {
      let name = columns[i]
      let mut index = -1
      for j, n in used {
        if n == name {
          index = j
          break
        }
      }
      if index < 0 {
        index = used.length()
        used.push(name)
      }
      Field(index)
    }
    Literal(s) => Literal(s)
    Slice(e, a, b) => Slice(compact_expr(e, columns, used), a, b)
    Token(e, s, i) => Token(compact_expr(e, columns, used), s, i)
    Run(e, kind, i) => Run(compact_expr(e, columns, used), kind, i)
    Trim(e) => Trim(compact_expr(e, columns, used))
    Lower(e) => Lower(compact_expr(e, columns, used))
    Upper(e) => Upper(compact_expr(e, columns, used))
    Concat(parts) => Concat(parts.map(p => compact_expr(p, columns, used)))
    DateText(e, src, dst) => DateText(compact_expr(e, columns, used), src, dst)
    If(c, a, b) =>
      If(
        compact_condition(c, columns, used),
        compact_expr(a, columns, used),
        compact_expr(b, columns, used),
      )
    RegexCapture(e, p, g, i) =>
      RegexCapture(compact_expr(e, columns, used), p, g, i)
    RegexReplace(e, p, r) => RegexReplace(compact_expr(e, columns, used), p, r)
  }
}

///| When the observed output schema is unchanged, retain an alternative that

///|
/// modifies only changed columns and leaves future extra fields intact.
fn update_witness(recipe : Recipe, columns : Array[String]) -> Recipe? {
  if recipe.columns != columns || recipe.outputs.length() != columns.length() {
    return None
  }
  for i, output in recipe.outputs {
    if output.name != columns[i] {
      return None
    }
  }
  let used : Array[String] = []
  let outputs : Array[OutputField] = []
  for i, output in recipe.outputs {
    if output.expression != Field(i) {
      outputs.push({
        name: output.name,
        expression: compact_expr(output.expression, columns, used),
      })
    }
  }
  if outputs.is_empty() {
    return None
  }
  // Literal-only edits still require an existing table schema for a recipe.
  if used.is_empty() {
    used.push(columns[0])
  }
  Some({ columns: used, outputs, })
}
