///|
test "mixed empty and nonempty observations can infer a column" {
  let report = synthesize([
    { input: [""], output: "", },
    { input: ["abc"], output: "abc", },
  ])
  assert_true(report.candidates.length() > 0)
  assert_eq(evaluate(report.candidates[0].expression, ["new"]), "new")
}

///|
test "all empty observations yield a constant empty program without cycles" {
  let report = synthesize([
    { input: ["abc"], output: "", },
    { input: ["xyz"], output: "", },
  ])
  assert_eq(report.candidates.length(), 1)
  assert_eq(evaluate(report.candidates[0].expression, ["any"]), "")
}

///|
test "batch amplification is rejected before constructing oversized reports" {
  let recipe = {
    columns: ["x"],
    outputs: [{ name: "x", expression: Literal("a".repeat(65536)), }],
  }
  let table = { columns: ["x"], rows: Array::make(40, [""]), }
  let failed = try {
    ignore(apply_recipe(recipe, table))
    false
  } catch {
    LoomError(message) => message == "batch output exceeds 2000000 UTF-16 units"
  }
  assert_true(failed)
}

///|
test "public interpreter enforces expression node budget" {
  let expr = Concat(Array::make(32, Concat(Array::make(32, Literal("x")))))
  assert_true(attempt(expr, [""]) is Err(_))
}

///|
test "small generated samples always satisfy every returned program" {
  for width in 1..<8 {
    let samples = [
      {
        input: ["货号-" + "0".repeat(width) + "3"],
        output: "0".repeat(width) + "3",
      },
      {
        input: ["货号-" + "0".repeat(width) + "8"],
        output: "0".repeat(width) + "8",
      },
    ]
    let report = synthesize(samples)
    assert_true(report.candidates.length() > 0)
    for c in report.candidates {
      for sample in samples {
        assert_eq(evaluate(c.expression, sample.input), sample.output)
      }
    }
  }
}
