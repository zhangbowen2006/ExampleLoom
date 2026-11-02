///|
test "invalid requests return structured errors" {
  for
    request in [
      "{", "[]", "{\"op\":\"unknown\"}", "{\"op\":\"parse\",\"format\":\"xml\",\"text\":\"x\"}",
    ] {
    let obj = j_object(parse_json_text(handle(request)))
    assert_true(required(obj, "ok") == Json(false))
    assert_true(!j_text(required(obj, "error")).is_empty())
  }
}

///|
test "protocol refuses a partial CSV when a row fails" {
  let recipe = recipe_to_json({
    columns: ["x"],
    outputs: [{ name: "suffix", expression: Token(Field(0), "-", 1), }],
  })
  let request = Json::object({
    "op": Json("apply"),
    "recipe": recipe,
    "table": table_json({ columns: ["x"], rows: [["a-b"], ["missing"]], }),
  })
  let result = j_object(parse_json_text(handle(request.stringify())))
  assert_eq(j_int(required(result, "failures")), 1)
  assert_true(required(result, "csv") == Json::null())
  assert_eq(j_array(required(result, "rows")).length(), 2)
}

///|
test "JSON protocol learns without executing any host code" {
  let request = "{\"op\":\"synthesize\",\"examples\":[{\"input\":[\"a-01\"],\"output\":\"01\"},{\"input\":[\"b-123\"],\"output\":\"123\"}],\"rows\":[[\"c-12345\"]]}"
  let result = j_object(parse_json_text(handle(request)))
  assert_true(required(result, "ok") == Json(true))
  assert_true(j_array(required(result, "candidates")).length() > 0)
}
