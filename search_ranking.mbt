///|
fn condition_cost(c : Condition) -> Int32 {
  match c {
    Empty(_) => 2
    Equals(_, Literal(s)) | Equals(Literal(s), _) =>
      if s.is_empty() {
        3
      } else {
        12 + s.char_length()
      }
    Equals(_, _) => 8
    Matches(_, p, _) => 6 + p.char_length() / 8
    Not(c) => condition_cost(c) + 1
    All(cs) | Any(cs) => cs.fold(init=2, (n, c) => n + condition_cost(c))
  }
}

///|
fn expression_cost(e : Expr) -> Int32 {
  match e {
    Field(_) => 1
    Literal(s) => 40 + s.char_length()
    Trim(e) | Lower(e) | Upper(e) => 2 + expression_cost(e)
    Token(e, _, _) | Run(e, _, _) => 5 + expression_cost(e)
    Slice(e, _, _) => 12 + expression_cost(e)
    DateText(e, _, _) => 8 + expression_cost(e)
    RegexCapture(e, _, _, _) => 7 + expression_cost(e)
    RegexReplace(e, _, r) => 9 + r.char_length() + expression_cost(e)
    Concat(es) => es.fold(init=2, (n, e) => n + expression_cost(e))
    If(c, a, b) =>
      8 + condition_cost(c) + expression_cost(a) + expression_cost(b)
  }
}

///|
/// A declared simplicity/generalization prior, never a probability or proof.
pub fn pipeline_cost(p : Pipeline) -> Int32 {
  p.steps.fold(init=0, (cost, step) => {
    cost +
    (match step {
      SortRows(keys) => 18 + keys.length() * 3
      Select(_, _) => 3
      FillDown(_) => 4
      Filter(c) => 4 + condition_cost(c)
      Deduplicate(_) => 6
      DropRows(n) => 4 + n
      PackRows(n, _) => 10 + n / 16
      Transpose => 18
      PromoteHeaders | DemoteHeaders => 7
      Unpivot(_, _, _, _) | Fold(_, _, _) => 8
      Melt(_, _, _, _, _) => 12
      Pivot(_, _, _, levels) => 12 + levels.length() / 8
      PivotGrid(_, _, _) => 9
      GroupRows(_, _) => 9
      Aggregate(_, measures) => 11 + measures.length()
      SplitColumn(_, _, _) | Explode(_, _) => 7
      CombineColumns(names, sep, _) => 5 + names.length() + sep.char_length()
      SegmentRows(c, _) => 8 + condition_cost(c)
      CarryContext(c, _) => 9 + condition_cost(c)
      MapRows(r) =>
        r.outputs.fold(init=8, (n, o) => n + expression_cost(o.expression))
    })
  })
}

///|
priv struct TargetProfile {
  width : Int32
  height : Int32
  frequencies : Map[String, Int32]
  total : Int32
}

///|
fn target_profile(target : Table) -> TargetProfile {
  let wanted : Map[String, Int32] = Map([])
  let mut total = 0
  for row in target.rows {
    for value in row {
      if value.is_empty() {
        continue
      }
      wanted[value] = wanted.get(value).unwrap_or(0) + 1
      total = total + 1
    }
  }
  {
    width: target.columns.length(),
    height: target.rows.length(),
    frequencies: wanted,
    total,
  }
}

///|
fn table_distance(table : Table, target : TargetProfile) -> Int32 {
  let counts : Map[String, Int32] = Map([])
  let mut present = 0
  let mut cells = 0
  for row in table.rows {
    for value in row {
      if value.is_empty() {
        continue
      }
      cells = cells + 1
      let n = counts.get(value).unwrap_or(0)
      if n < target.frequencies.get(value).unwrap_or(0) {
        present = present + 1
        counts[value] = n + 1
      }
    }
  }
  let shape = (table.columns.length() - target.width).abs() * 4 +
    (table.rows.length() - target.height).abs() *
    20 /
    Int32::max(1, Int32::max(table.rows.length(), target.height))
  let missing = (target.total - present) * 100 / Int32::max(1, target.total)
  let extra = (cells - present) * 20 / Int32::max(1, cells)
  shape + missing + extra
}

///|
fn state_priority(
  tables : Array[Table],
  targets : Array[TargetProfile],
  steps : Array[TableStep],
) -> Int32 {
  let mut distance = 0
  for i, table in tables {
    distance = distance + table_distance(table, targets[i])
  }
  distance * 4 + pipeline_cost({ columns: tables[0].columns, steps, })
}

///|
fn regex_literal(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if "\\.^$|?*+()[]{}".contains(c.to_string()) {
      out.write_char('\\')
    }
    out.write_char(c)
  }
  out.to_string()
}
