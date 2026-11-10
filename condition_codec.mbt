///|
fn encode_condition(c : Condition) -> Json {
  match c {
    Equals(a, b) =>
      Json::array([Json("equals"), encode_expr(a), encode_expr(b)])
    Empty(e) => Json::array([Json("empty"), encode_expr(e)])
    Matches(e, p, full) =>
      Json::array([Json("matches"), encode_expr(e), Json(p), Json(full)])
    Not(c) => Json::array([Json("not"), encode_condition(c)])
    All(cs) => Json::array([Json("all"), Json::array(cs.map(encode_condition))])
    Any(cs) => Json::array([Json("any"), Json::array(cs.map(encode_condition))])
  }
}

///|
fn decode_condition(
  v : Json,
  depth : Int32,
  budget : NodeBudget,
) -> Condition raise LoomError {
  budget.used = budget.used + 1
  if depth > 16 || budget.used > 256 {
    raise LoomError("condition exceeds depth/node limits")
  }
  let a = j_array(v)
  if a.length() < 2 {
    raise LoomError("condition requires an operator and arguments")
  }
  let op = j_text(a[0])
  let arity = if op == "matches" { 4 } else if op == "equals" { 3 } else { 2 }
  if a.length() != arity {
    raise LoomError("wrong condition arity")
  }
  match op {
    "equals" =>
      Equals(
        decode_expr(a[1], depth + 1, budget),
        decode_expr(a[2], depth + 1, budget),
      )
    "empty" => Empty(decode_expr(a[1], depth + 1, budget))
    "matches" => {
      let p = j_text(a[2])
      let full = match a[3] {
        True => true
        False => false
        _ => raise LoomError("full must be boolean")
      }
      ignore(regex_test("", p, full))
      Matches(decode_expr(a[1], depth + 1, budget), p, full)
    }
    "not" => Not(decode_condition(a[1], depth + 1, budget))
    "all" | "any" => {
      let values = j_array(a[1])
      if values.length() > 16 {
        raise LoomError("boolean condition exceeds 16 children")
      }
      let cs = values.map(v => decode_condition(v, depth + 1, budget))
      if op == "all" {
        All(cs)
      } else {
        Any(cs)
      }
    }
    _ => raise LoomError("unknown condition")
  }
}

///|
fn check_condition(
  c : Condition,
  depth : Int32,
  budget : NodeBudget,
) -> Unit raise LoomError {
  budget.used = budget.used + 1
  if depth > 16 || budget.used > 256 {
    raise LoomError("condition exceeds depth/node limits")
  }
  match c {
    Equals(a, b) => {
      check_tree(a, depth + 1, budget)
      check_tree(b, depth + 1, budget)
    }
    Empty(e) => check_tree(e, depth + 1, budget)
    Matches(e, p, full) => {
      ignore(regex_test("", p, full))
      check_tree(e, depth + 1, budget)
    }
    Not(c) => check_condition(c, depth + 1, budget)
    All(cs) | Any(cs) => {
      if cs.length() > 16 {
        raise LoomError("boolean condition exceeds 16 children")
      }
      for c in cs {
        check_condition(c, depth + 1, budget)
      }
    }
  }
}

///|
fn condition_fields(c : Condition, width : Int32) -> Unit raise LoomError {
  match c {
    Equals(a, b) => {
      check_fields(a, width)
      check_fields(b, width)
    }
    Empty(e) | Matches(e, _, _) => check_fields(e, width)
    Not(c) => condition_fields(c, width)
    All(cs) | Any(cs) =>
      for c in cs {
        condition_fields(c, width)
      }
  }
}

///|
pub fn condition_from_json(v : Json) -> Condition raise LoomError {
  decode_condition(v, 0, { used: 0, })
}

///|
pub fn condition_to_json(c : Condition) -> Json raise LoomError {
  check_condition(c, 0, { used: 0, })
  let v = encode_condition(c)
  ignore(condition_from_json(v))
  v
}
