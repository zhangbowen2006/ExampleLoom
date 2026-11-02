///|
test "every expression operator roundtrips in versioned data" {
  let expressions = [
    Field(0),
    Literal("😀"),
    Slice(Field(0), Start(1), End(0)),
    Token(Field(0), "-", -1),
    Run(Field(0), Digits, 0),
    Trim(Field(0)),
    Lower(Field(0)),
    Upper(Field(0)),
    DateText(Field(0), "YYYYMMDD", "YYYY-MM-DD"),
    Concat([Field(0), Literal("/")]),
  ]
  for e in expressions {
    assert_true(expression_from_json(expression_to_json(e)) == e)
  }
}

///|
test "recipe rebinds named columns and handles multiple outputs" {
  let recipe = {
    columns: ["id", "name"],
    outputs: [
      { name: "label", expression: Concat([Field(0), Literal("/"), Field(1)]), },
      { name: "id_copy", expression: Field(0), },
    ],
  }
  let table = {
    columns: ["name", "unused", "id"],
    rows: [["小陈", "x", "001"]],
  }
  assert_true(
    apply_recipe(recipe_from_json(recipe_to_json(recipe)), table).rows[0] ==
    Ok(["001/小陈", "001"]),
  )
}

///|
test "batch errors retain their original row index" {
  let recipe = {
    columns: ["date"],
    outputs: [
      {
        name: "date",
        expression: DateText(Field(0), "YYYYMMDD", "YYYY-MM-DD"),
      },
    ],
  }
  let result = apply_recipe(recipe, {
    columns: ["date"],
    rows: [["20240229"], ["20260229"], ["20260101"]],
  })
  assert_eq(result.failures, 1)
  assert_true(result.rows[1] is Err(_))
  assert_true(result.rows[2] == Ok(["2026-01-01"]))
}

///|
test "unknown versions and operators fail closed" {
  for
    source in [
      "{\"version\":2,\"columns\":[\"a\"],\"outputs\":[]}", "{\"version\":1,\"columns\":[\"a\"],\"outputs\":[{\"name\":\"x\",\"expression\":[\"eval\",\"bad\"]}]}",
      "{\"version\":1,\"columns\":[\"a\"],\"outputs\":[{\"name\":\"x\",\"expression\":[\"field\",1]}]}",
    ] {
    let failed = try {
      ignore(recipe_from_json(parse_json_text(source)))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "deep and oversized imported expression rejected before evaluation" {
  let mut value = Json::array([Json("field"), Json(0)])
  for _ in 0..<20 {
    value = Json::array([Json("trim"), value])
  }
  let failed = try {
    ignore(expression_from_json(value))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
