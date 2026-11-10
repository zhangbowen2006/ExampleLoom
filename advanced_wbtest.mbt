///|
test "conditional evaluates only its selected branch and boolean short circuits" {
  let e = If(
    Empty(Field(0)),
    Literal("missing"),
    RegexCapture(Field(0), "id=([[:digit:]]+)", 1, 0),
  )
  assert_eq(evaluate(e, [""]), "missing")
  assert_eq(evaluate(e, ["id=0098"]), "0098")
  assert_true(test_condition(Any([Empty(Field(0)), Empty(Field(9))]), [""]))
  assert_true(
    !test_condition(All([Not(Empty(Field(0))), Empty(Field(9))]), [""]),
  )
  assert_eq(expression_from_json(expression_to_json(e)), e)
}

///|
test "regular expressions handle alternation repeats boundaries and captures" {
  assert_eq(
    evaluate(RegexCapture(Field(0), "(?:code|id)=([[:digit:]]{2,4})", 1, -1), [
      "id=003;code=0042",
    ]),
    "0042",
  )
  assert_eq(
    evaluate(RegexCapture(Field(0), "(甲|😀)+", 0, 0), ["前甲😀后"]),
    "甲😀",
  )
  assert_true(test_condition(Matches(Field(0), "a|b", true), ["b"]))
  assert_true(!test_condition(Matches(Field(0), "a|b", true), ["ab"]))
  assert_true(test_condition(Matches(Field(0), "(?i:abc)", true), ["AbC"]))
  assert_true(
    test_condition(Matches(Field(0), "[[:digit:]]+", false), ["abc007"]),
  )
  assert_true(attempt(RegexCapture(Field(0), "[", 0, 0), ["x"]) is Err(_))
  assert_true(attempt(RegexCapture(Field(0), "(x)?y", 1, 0), ["y"]) is Err(_))
}

///|
test "regex replacement references and empty matches make Unicode progress" {
  let e = RegexReplace(Field(0), "([[:alpha:]]+)=([[:digit:]]+)", "$2:$1:$$")
  assert_eq(evaluate(e, ["id=007 n=8"]), "007:id:$ 8:n:$")
  assert_eq(
    evaluate(RegexReplace(Field(0), "", "-"), ["甲😀"]),
    "-甲-😀-",
  )
  assert_true(attempt(RegexReplace(Field(0), "never", "$x"), ["abc"]) is Err(_))
  assert_true(
    attempt(RegexReplace(Field(0), "a", "x".repeat(65536)), ["aa"]) is Err(_),
  )
}

///|
test "branch learner generalizes repeated categories and keeps budget" {
  let samples : Array[Example] = [
    { input: ["local", "订单-001"], output: "CN/001", },
    { input: ["local", "订单-0482"], output: "CN/0482", },
    { input: ["global", "sku:98"], output: "INT/98", },
    { input: ["global", "sku:601"], output: "INT/601", },
  ]
  let r = synthesize(samples)
  assert_true(!r.candidates.is_empty())
  assert_true(r.candidates[0].expression is If(_, _, _))
  assert_eq(
    evaluate(r.candidates[0].expression, ["local", "订单-0777"]),
    "CN/0777",
  )
  assert_eq(
    evaluate(r.candidates[0].expression, ["global", "sku:45001"]),
    "INT/45001",
  )
  assert_true(r.steps <= default_options().max_steps)
  assert_true(r.atom_evaluations <= default_options().max_atom_evaluations)
  let order = synthesize(samples.rev())
  assert_eq(
    r.candidates.map(c => explain(c.expression)),
    order.candidates.map(c => explain(c.expression)),
  )
}

///|
test "regex hints are learned and not merely interpreted" {
  let r = synthesize(
    [
      { input: ["ref=009;note=77"], output: "009", },
      { input: ["noise 12 ref=4812;note=5"], output: "4812", },
    ],
    patterns=["ref=([[:digit:]]+)"],
  )
  assert_true(
    r.candidates.any(c => {
      evaluate(c.expression, ["noise 89 ref=70004;note=5"]) == "70004"
    }),
  )
}

///|
test "regex resource limits reject nested expansion before compiling an NFA" {
  assert_true(
    attempt(RegexCapture(Field(0), "((a{256}){256}){256}", 0, 0), ["a"])
    is Err(_),
  )
  assert_eq(
    evaluate(RegexCapture(Field(0), "[[:digit:]]{2,4}", 0, 0), ["x0012y"]),
    "0012",
  )
  assert_eq(
    evaluate(RegexCapture(Field(0), "\\{9999\\}", 0, 0), ["{9999}"]),
    "{9999}",
  )
}

///|
test "structural transforms preserve empties and reject lossy pivots" {
  let wide : Table = {
    columns: ["id", "Jan", "Feb"],
    rows: [["A", "0", ""], ["B", "5", "8"]],
  }
  let long = transform_table(wide, [
    Unpivot(["id"], ["Jan", "Feb"], "month", "value"),
  ])
  assert_eq(long.rows.length(), 4)
  assert_eq(
    transform_table(long, [Pivot(["id"], "month", "value", ["Jan", "Feb"])]),
    wide,
  )
  let duplicate : Table = { ..long, rows: long.rows + [long.rows[0]], }
  let result = try {
    ignore(
      transform_table(duplicate, [
        Pivot(["id"], "month", "value", ["Jan", "Feb"]),
      ]),
    )
    false
  } catch {
    LoomError(_) => true
  }
  assert_true(result)
  assert_eq(wide.rows[0], ["A", "0", ""])
}

///|
test "pipeline rebinds reordered names and round trips" {
  let p : Pipeline = {
    columns: ["id", "tags"],
    steps: [Explode("tags", ";"), Select(["tags", "id"], ["tag", "record"])],
  }
  let table : Table = { columns: ["tags", "id"], rows: [["a;;b", "007"]], }
  let saved = pipeline_from_json(pipeline_to_json(p))
  assert_eq(apply_pipeline(saved, table), {
    columns: ["tag", "record"],
    rows: [["a", "007"], ["", "007"], ["b", "007"]],
  })
}

///|
test "split errors, transpose, fill and stable dedup have explicit semantics" {
  let table : Table = {
    columns: ["name", "code"],
    rows: [["A", "x:y"], ["", "z:w"], ["A", "x:y"]],
  }
  let transformed = transform_table(table, [
    FillDown(["name"]),
    Deduplicate(["name", "code"]),
    SplitColumn("code", ":", ["left", "right"]),
  ])
  assert_eq(transformed.rows, [["A", "x", "y"], ["A", "z", "w"]])
  assert_eq(transform_table(transformed, [Transpose]).rows, [
    ["A", "A"],
    ["x", "z"],
    ["y", "w"],
  ])
  let bad = try {
    ignore(transform_table(table, [SplitColumn("code", "never", ["a", "b"])]))
    false
  } catch {
    LoomError(_) => true
  }
  assert_true(bad)
}
