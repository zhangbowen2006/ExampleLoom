///|
test "dynamic grid pivots preserve blank labels and accept unseen categories" {
  let input : Table = {
    columns: ["id", "kind", "value"],
    rows: [["A", "", "0"], ["A", "c0", "007"], ["B", "c0", "9"]],
  }
  let result = transform_table(input, [PivotGrid(["id"], "kind", "value")])
  assert_eq(result.rows, [["", "", "c0"], ["A", "0", "007"], ["B", "", "9"]])
  let next : Table = { columns: input.columns, rows: [["C", "new", "x"]], }
  assert_eq(transform_table(next, [PivotGrid(["id"], "kind", "value")]).rows, [
    ["", "new"],
    ["C", "x"],
  ])
  let duplicate = { ..input, rows: input.rows + [input.rows[0]], }
  let bad = try {
    ignore(transform_table(duplicate, [PivotGrid(["id"], "kind", "value")]))
    false
  } catch {
    LoomError(_) => true
  }
  assert_true(bad)
}

///|
test "combining named columns follows explicit order and never mutates input" {
  let input : Table = {
    columns: ["left", "keep", "right"],
    rows: [["001", "x", "Z"]],
  }
  assert_eq(
    transform_table(input, [CombineColumns(["right", "left"], "/", "code")]),
    { columns: ["code", "keep"], rows: [["Z/001", "x"]], },
  )
  assert_eq(input.rows, [["001", "x", "Z"]])
  let p : Pipeline = {
    columns: input.columns,
    steps: [CombineColumns(["left", "right"], "", "code")],
  }
  assert_eq(
    apply_pipeline(pipeline_from_json(pipeline_to_json(p)), input).rows,
    [["001Z", "x"]],
  )
}

///|
test "segmented records handle repeated separators and variable record sizes" {
  let input : Table = {
    columns: ["line"],
    rows: [[""], ["A"], ["1"], [""], [""], ["B"], ["2"], ["3"], [""]],
  }
  assert_eq(
    transform_table(input, [SegmentRows(Empty(Field(0)), false)]).rows,
    [["A", "1", ""], ["B", "2", "3"]],
  )
  let marked : Table = {
    columns: ["line"],
    rows: [["*A"], ["1"], ["*B"], ["2"], ["3"]],
  }
  assert_eq(
    transform_table(marked, [
      SegmentRows(Matches(Field(0), "^\\*", false), true),
    ]).rows,
    [["*A", "1", ""], ["*B", "2", "3"]],
  )
  let invalid : Table = { columns: ["line"], rows: [["orphan"], ["*A"]], }
  assert_true(
    try {
      ignore(
        transform_table(invalid, [
          SegmentRows(Matches(Field(0), "^\\*", false), true),
        ]),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
}

///|
test "carried context is replaced at every header and orphans are errors" {
  let input : Table = {
    columns: ["id", "label", "amount"],
    rows: [
      ["P1", "parent one", ""],
      ["a", "item", "0"],
      ["P2", "parent two", ""],
      ["b", "other", "007"],
    ],
  }
  let p : Pipeline = {
    columns: input.columns,
    steps: [CarryContext(Empty(Field(2)), ["id", "label"])],
  }
  assert_eq(apply_pipeline(p, input).rows, [
    ["P1", "parent one", "a", "item", "0"],
    ["P2", "parent two", "b", "other", "007"],
  ])
  let orphan = { ..input, rows: [["a", "item", "1"]], }
  assert_true(
    try {
      ignore(apply_pipeline(p, orphan))
      false
    } catch {
      LoomError(_) => true
    },
  )
}

///|
test "repeated source columns can have distinct output aliases" {
  let input : Table = { columns: ["code"], rows: [["001"]], }
  let p : Pipeline = {
    columns: ["code"],
    steps: [Select(["code", "code"], ["primary", "backup"])],
  }
  assert_eq(
    apply_pipeline(pipeline_from_json(pipeline_to_json(p)), input).rows,
    [["001", "001"]],
  )
}

///|
test "ranked learning prefers a stateful fill over coincidental string arithmetic" {
  let before : Table = {
    columns: ["region", "year", "amount"],
    rows: [["A", "2020", "100"], ["A", "2021", ""]],
  }
  let after : Table = {
    ..before,
    rows: [["A", "2020", "100"], ["A", "2021", "100"]],
  }
  let r = synthesize_table([{ before, after, }])
  assert_true(!r.candidates.is_empty())
  let next : Table = {
    columns: before.columns,
    rows: [["B", "2030", "007"], ["B", "2031", ""]],
  }
  assert_eq(apply_pipeline(r.candidates[0], next).rows, [
    ["B", "2030", "007"],
    ["B", "2031", "007"],
  ])
  for i in 1..<r.candidates.length() {
    assert_true(
      pipeline_cost(r.candidates[i - 1]) <= pipeline_cost(r.candidates[i]),
    )
  }
}

///|
test "fixed record packing ranks before dimension dependent whole-table transpose" {
  let before : Table = { columns: ["c0"], rows: [["A"], ["team"], ["001"]], }
  let after : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["A", "team", "001"]],
  }
  let r = synthesize_table([{ before, after, }])
  let next : Table = {
    columns: ["c0"],
    rows: [["B"], ["new"], ["002"], ["C"], ["other"], ["003"]],
  }
  assert_eq(apply_pipeline(r.candidates[0], next).rows, [
    ["B", "new", "002"],
    ["C", "other", "003"],
  ])
}

///|
test "compositional search fills keys before a dynamic pivot" {
  let before : Table = {
    columns: ["id", "kind", "amount"],
    rows: [["A", "x", "1"], ["", "y", "2"], ["B", "x", "3"], ["", "y", "4"]],
  }
  let after : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["", "x", "y"], ["A", "1", "2"], ["B", "3", "4"]],
  }
  let r = synthesize_table([{ before, after, }])
  assert_true(!r.candidates.is_empty())
  assert_eq(apply_pipeline(r.candidates[0], before), after)
  assert_true(r.evaluations <= default_table_options().max_evaluations)
  assert_true(r.states <= default_table_options().max_states)
}

///|
test "capture contexts can be inferred without supplied regex hints" {
  let r = synthesize([
    { input: ["ref=009;note=77"], output: "009", },
    { input: ["noise 12 ref=4812;note=5 extra=6"], output: "4812", },
  ])
  assert_true(!r.candidates.is_empty())
  assert_eq(
    evaluate(r.candidates[0].expression, ["noise 32 ref=007001;note=4 more=8"]),
    "007001",
  )
}

///|
test "literal replacement witnesses learn normalization with variable text" {
  let r = synthesize([
    { input: ["Subject 1"], output: "Subject1", },
    { input: ["Other 25"], output: "Other25", },
  ])
  assert_true(!r.candidates.is_empty())
  assert_eq(evaluate(r.candidates[0].expression, ["Longer 007"]), "Longer007")
}
