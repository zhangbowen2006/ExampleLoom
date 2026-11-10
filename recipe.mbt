///|
pub(all) struct OutputField {
  name : String
  expression : Expr
}

///|
pub(all) struct Recipe {
  columns : Array[String]
  outputs : Array[OutputField]
}

///|
pub(all) struct BatchResult {
  rows : Array[Result[Array[String], String]]
  failures : Int32
}

///|
fn j_object(value : Json) -> Map[String, Json] raise LoomError {
  match value {
    Object(obj) => obj
    _ => raise LoomError("expected JSON object")
  }
}

///|
fn j_array(value : Json) -> Array[Json] raise LoomError {
  match value {
    Array(items) => items
    _ => raise LoomError("expected JSON array")
  }
}

///|
fn j_text(value : Json) -> String raise LoomError {
  match value {
    String(s) => s
    _ => raise LoomError("expected JSON string")
  }
}

///|
fn j_int(value : Json) -> Int32 raise LoomError {
  match value {
    Number(n, ..) => {
      if n < -1000000.0 || n > 1000000.0 || n != n.to_int().to_double() {
        raise LoomError("expected bounded integer")
      }
      n.to_int()
    }
    _ => raise LoomError("expected integer")
  }
}

///|
fn required(obj : Map[String, Json], name : String) -> Json raise LoomError {
  match obj.get(name) {
    Some(v) => v
    None => raise LoomError("missing field: " + name)
  }
}

///|
fn fields_only(
  obj : Map[String, Json],
  keys : Array[String],
) -> Unit raise LoomError {
  for k, _ in obj {
    if !keys.contains(k) {
      raise LoomError("unknown field: " + k)
    }
  }
}

///|
fn position_json(p : Position) -> Json {
  match p {
    Start(n) => Json::array([Json("start"), Json(n)])
    End(n) => Json::array([Json("end"), Json(n)])
  }
}

///|
fn read_position(value : Json) -> Position raise LoomError {
  let a = j_array(value)
  if a.length() != 2 {
    raise LoomError("position requires two elements")
  }
  let n = j_int(a[1])
  if n < 0 || n > 65536 {
    raise LoomError("invalid position")
  }
  match j_text(a[0]) {
    "start" => Start(n)
    "end" => End(n)
    _ => raise LoomError("unknown position anchor")
  }
}

///|
fn encode_expr(e : Expr) -> Json {
  match e {
    If(c, yes, no) =>
      Json::array([
        Json("if"),
        encode_condition(c),
        encode_expr(yes),
        encode_expr(no),
      ])
    RegexCapture(e, p, g, i) =>
      Json::array([Json("capture"), encode_expr(e), Json(p), Json(g), Json(i)])
    RegexReplace(e, p, r) =>
      Json::array([Json("replace"), encode_expr(e), Json(p), Json(r)])
    Field(i) => Json::array([Json("field"), Json(i)])
    Literal(s) => Json::array([Json("literal"), Json(s)])
    Trim(e) => Json::array([Json("trim"), encode_expr(e)])
    Lower(e) => Json::array([Json("lower"), encode_expr(e)])
    Upper(e) => Json::array([Json("upper"), encode_expr(e)])
    Slice(e, a, b) =>
      Json::array([
        Json("slice"),
        encode_expr(e),
        position_json(a),
        position_json(b),
      ])
    Token(e, s, i) =>
      Json::array([Json("token"), encode_expr(e), Json(s), Json(i)])
    Run(e, k, i) =>
      Json::array([Json("run"), encode_expr(e), Json(kind_text(k)), Json(i)])
    DateText(e, a, b) =>
      Json::array([Json("date"), encode_expr(e), Json(a), Json(b)])
    Concat(parts) =>
      Json::array([Json("concat"), Json::array(parts.map(encode_expr))])
  }
}

///|
priv struct NodeBudget {
  mut used : Int32
}

///|
fn decode_expr(
  value : Json,
  depth : Int32,
  budget : NodeBudget,
) -> Expr raise LoomError {
  budget.used = budget.used + 1
  if depth > 16 || budget.used > 256 {
    raise LoomError("expression exceeds depth/node limits")
  }
  let a = j_array(value)
  if a.length() < 2 {
    raise LoomError("expression requires an operator and arguments")
  }
  let op = j_text(a[0])
  let arity = if op == "capture" {
    5
  } else if ["slice", "token", "run", "date", "if", "replace"].contains(op) {
    4
  } else {
    2
  }
  if a.length() != arity {
    raise LoomError("wrong expression arity")
  }
  match op {
    "if" =>
      If(
        decode_condition(a[1], depth + 1, budget),
        decode_expr(a[2], depth + 1, budget),
        decode_expr(a[3], depth + 1, budget),
      )
    "capture" => {
      let p = j_text(a[2])
      ignore(compiled_regex(p))
      let g = j_int(a[3])
      let i = j_int(a[4])
      if g < 0 || g > 32 || i < -4096 || i >= 4096 {
        raise LoomError("regex group/occurrence outside limits")
      }
      RegexCapture(decode_expr(a[1], depth + 1, budget), p, g, i)
    }
    "replace" => {
      let p = j_text(a[2])
      let r = j_text(a[3])
      ignore(regex_replace("", p, r))
      RegexReplace(decode_expr(a[1], depth + 1, budget), p, r)
    }
    "field" => {
      let i = j_int(a[1])
      if i < 0 || i >= 64 {
        raise LoomError("invalid field index")
      }
      Field(i)
    }
    "literal" => {
      let text = j_text(a[1])
      if text.length() > 65536 {
        raise LoomError("literal too long")
      }
      Literal(text)
    }
    "trim" => Trim(decode_expr(a[1], depth + 1, budget))
    "lower" => Lower(decode_expr(a[1], depth + 1, budget))
    "upper" => Upper(decode_expr(a[1], depth + 1, budget))
    "slice" =>
      Slice(
        decode_expr(a[1], depth + 1, budget),
        read_position(a[2]),
        read_position(a[3]),
      )
    "token" => {
      let separator = j_text(a[2])
      if separator.is_empty() || separator.char_length() > 16 {
        raise LoomError("separator requires 1..16 characters")
      }
      Token(decode_expr(a[1], depth + 1, budget), separator, j_int(a[3]))
    }
    "run" => {
      let k = match j_text(a[2]) {
        "digits" => Digits
        "letters" => Letters
        _ => raise LoomError("unknown run class")
      }
      Run(decode_expr(a[1], depth + 1, budget), k, j_int(a[3]))
    }
    "date" => {
      let source = j_text(a[2])
      let target = j_text(a[3])
      if !date_formats().contains(source) || !date_formats().contains(target) {
        raise LoomError("unsupported date format")
      }
      DateText(decode_expr(a[1], depth + 1, budget), source, target)
    }
    "concat" => {
      let parts = j_array(a[1])
      if parts.length() > 32 {
        raise LoomError("too many concatenation parts")
      }
      Concat(parts.map(v => decode_expr(v, depth + 1, budget)))
    }
    _ => raise LoomError("unknown expression operator")
  }
}

///|
/// Stable version-1 AST data. This parser never evaluates host code.
pub fn expression_from_json(value : Json) -> Expr raise LoomError {
  decode_expr(value, 0, { used: 0, })
}

///|
fn check_tree(
  e : Expr,
  depth : Int32,
  budget : NodeBudget,
) -> Unit raise LoomError {
  budget.used = budget.used + 1
  if depth > 16 || budget.used > 256 {
    raise LoomError("expression exceeds depth/node limits")
  }
  match e {
    If(c, yes, no) => {
      check_condition(c, depth + 1, budget)
      check_tree(yes, depth + 1, budget)
      check_tree(no, depth + 1, budget)
    }
    Field(_) | Literal(_) => ()
    Slice(e, _, _)
    | Token(e, _, _)
    | Run(e, _, _)
    | Trim(e)
    | Lower(e)
    | Upper(e)
    | DateText(e, _, _) => check_tree(e, depth + 1, budget)
    RegexCapture(e, _, _, _) | RegexReplace(e, _, _) =>
      check_tree(e, depth + 1, budget)
    Concat(parts) =>
      for part in parts {
        check_tree(part, depth + 1, budget)
      }
  }
}

///|
pub fn expression_to_json(e : Expr) -> Json raise LoomError {
  check_tree(e, 0, { used: 0, })
  let json = encode_expr(e)
  ignore(expression_from_json(json))
  json
}

///|
fn check_fields(e : Expr, width : Int32) -> Unit raise LoomError {
  match e {
    If(c, yes, no) => {
      condition_fields(c, width)
      check_fields(yes, width)
      check_fields(no, width)
    }
    Field(i) =>
      if i >= width {
        raise LoomError("expression refers to undeclared input column")
      }
    Literal(_) => ()
    Slice(e, _, _)
    | Token(e, _, _)
    | Run(e, _, _)
    | Trim(e)
    | Lower(e)
    | Upper(e)
    | DateText(e, _, _) => check_fields(e, width)
    RegexCapture(e, _, _, _) | RegexReplace(e, _, _) => check_fields(e, width)
    Concat(parts) =>
      for part in parts {
        check_fields(part, width)
      }
  }
}

///|
pub fn recipe_from_json(value : Json) -> Recipe raise LoomError {
  let obj = j_object(value)
  fields_only(obj, ["version", "columns", "outputs"])
  if j_int(required(obj, "version")) != 1 {
    raise LoomError("unsupported recipe version")
  }
  let columns = j_array(required(obj, "columns")).map(j_text)
  validate_columns(columns)
  let outputs = j_array(required(obj, "outputs")).map(v => {
    let o = j_object(v)
    fields_only(o, ["name", "expression"])
    let name = j_text(required(o, "name"))
    let expression = expression_from_json(required(o, "expression"))
    check_fields(expression, columns.length())
    OutputField::{ name, expression, }
  })
  validate_columns(outputs.map(o => o.name))
  { columns, outputs, }
}

///|
pub fn recipe_to_json(recipe : Recipe) -> Json raise LoomError {
  let json = Json::object({
    "version": Json(1),
    "columns": Json(recipe.columns),
    "outputs": Json::array(
      recipe.outputs.map(o => {
        Json::object({
          "name": Json(o.name),
          "expression": expression_to_json(o.expression),
        })
      }),
    ),
  })
  ignore(recipe_from_json(json))
  json
}

///|
/// Bind saved input column names to each new table. Column reordering is safe;
/// missing required names fail the batch, and individual row failures persist.
pub fn apply_recipe(
  recipe : Recipe,
  table : Table,
) -> BatchResult raise LoomError {
  validate_table(table)
  ignore(recipe_to_json(recipe))
  let indices : Array[Int32] = []
  for name in recipe.columns {
    let mut index = -1
    for i, column in table.columns {
      if column == name {
        index = i
        break
      }
    }
    if index < 0 {
      raise LoomError("missing required column: " + name)
    }
    indices.push(index)
  }
  let rows : Array[Result[Array[String], String]] = []
  let mut failures = 0
  let mut output_units = 0
  for row in table.rows {
    let input = indices.map(i => row[i])
    let result = Ok(recipe.outputs.map(o => evaluate(o.expression, input))) catch {
      LoomError(message) => {
        failures = failures + 1
        Err(message)
      }
    }
    if result is Ok(values) {
      for value in values {
        output_units = output_units + value.length()
      }
      if output_units > 2000000 {
        raise LoomError("batch output exceeds 2000000 UTF-16 units")
      }
    }
    rows.push(result)
  }
  { rows, failures, }
}
