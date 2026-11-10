///|
test "table search learns real unpivot and works on a new row" {
  let input : Table = {
    columns: ["id", "Jan", "Feb"],
    rows: [["A", "1", "2"], ["B", "3", "4"]],
  }
  let output : Table = {
    columns: ["id", "month", "amount"],
    rows: [
      ["A", "Jan", "1"],
      ["A", "Feb", "2"],
      ["B", "Jan", "3"],
      ["B", "Feb", "4"],
    ],
  }
  let r = synthesize_table([{ before: input, after: output, }], options={
    ..default_table_options(),
    max_depth: 1,
  })
  assert_true(!r.candidates.is_empty())
  let learned = pipeline_from_json(pipeline_to_json(r.candidates[0]))
  let held : Table = {
    columns: ["Feb", "id", "Jan"],
    rows: [["9", "NEW", "07"]],
  }
  assert_eq(apply_pipeline(learned, held).rows, [
    ["NEW", "Jan", "07"],
    ["NEW", "Feb", "9"],
  ])
}

///|
test "table search validates all training pairs instead of one small example" {
  let a : Table = {
    columns: ["id", "color"],
    rows: [["A", "red"], ["A", "red"]],
  }
  let b : Table = {
    columns: ["id", "color"],
    rows: [["B", "blue"], ["B", "green"]],
  }
  let out_a : Table = { ..a, rows: [["A", "red"]], }
  let r = synthesize_table(
    [{ before: a, after: out_a, }, { before: b, after: b, }],
    options={ ..default_table_options(), max_depth: 1, },
  )
  assert_true(!r.candidates.is_empty())
  for p in r.candidates {
    assert_eq(apply_pipeline(p, a), out_a)
    assert_eq(apply_pipeline(p, b), b)
  }
}

///|
test "unsupported table goals return failure and budget exhaustion is explicit" {
  let a : Table = { columns: ["x"], rows: [["a"], ["b"]], }
  let b : Table = { columns: ["x"], rows: [["unrelated"], ["other"]], }
  let r = synthesize_table([{ before: a, after: b, }], options={
    max_depth: 4,
    max_states: 1,
    max_evaluations: 1,
    max_candidates: 1,
  })
  assert_true(r.candidates.is_empty())
  assert_true(r.truncated)
  assert_eq(r.evaluations, 1)
  assert_eq(r.states, 1)
}

///|
test "structural protocol is callable and rejects unknown pipeline fields" {
  let a = parse_json_text(
    handle(
      (
        #|{"op":"transform","pipeline":{"version":2,"columns":["x"],"steps":[["explode","x",";"]]},"table":{"columns":["x"],"rows":[["a;b"]]}}
      ),
    ),
  )
  assert_eq(required(j_object(a), "ok"), Json(true))
  let bad = parse_json_text(
    handle(
      (
        #|{"op":"validate_pipeline","pipeline":{"version":2,"columns":["x"],"steps":[],"surprise":true}}
      ),
    ),
  )
  assert_eq(required(j_object(bad), "ok"), Json(false))
}

///|
test "melt consumes header labels and makes skipping empty values explicit" {
  let table : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["", "House 1", "House 2"], ["A", "1", ""], ["B", "", "0"]],
  }
  let result = transform_table(table, [
    Melt(["c0"], ["c1", "c2"], "house", "value", true),
  ])
  assert_eq(result.rows, [["A", "House 1", "1"], ["B", "House 2", "0"]])
  assert_eq(
    transform_table(table, [Melt(["c0"], ["c1", "c2"], "house", "value", false)]).rows.length(),
    4,
  )
}

///|
test "record packing distinguishes row and column order and rejects tail loss" {
  let table : Table = {
    columns: ["a", "b"],
    rows: [["A", "B"], ["1", "2"], ["X", "Y"], ["3", "4"]],
  }
  assert_eq(transform_table(table, [PackRows(2, false)]).rows, [
    ["A", "B", "1", "2"],
    ["X", "Y", "3", "4"],
  ])
  assert_eq(transform_table(table, [PackRows(2, true)]).rows, [
    ["A", "1"],
    ["B", "2"],
    ["X", "3"],
    ["Y", "4"],
  ])
  let bad = try {
    ignore(transform_table(table, [PackRows(3, true)]))
    false
  } catch {
    LoomError(_) => true
  }
  assert_true(bad)
}

///|
test "grouping keeps duplicate observations and pads uneven groups explicitly" {
  let table : Table = {
    columns: ["id", "value"],
    rows: [["A", "1"], ["A", "1"], ["B", "2"]],
  }
  assert_eq(transform_table(table, [GroupRows(["id"], ["value"])]).rows, [
    ["A", "1", "1"],
    ["B", "2", ""],
  ])
}

///|
test "pipeline validation catches data independent malformed operators" {
  for
    step in [
      Json::array([Json("pack_rows"), Json(0), Json(false)]),
      Json::array([Json("select"), Json(["x"]), Json(["a", "b"])]),
      Json::array([Json("explode"), Json("x"), Json("")]),
    ] {
    let bad = try {
      ignore(table_step_from_json(step))
      false
    } catch {
      LoomError(_) => true
    }
    assert_true(bad)
  }
}
