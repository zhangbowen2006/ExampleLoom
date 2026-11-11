///|
test "decimal sorting is exact beyond Int64 and preserves source spellings" {
  let table : Table = {
    columns: ["n", "id"],
    rows: [
      ["10", "a"],
      ["2", "b"],
      ["-0.001", "c"],
      ["9007199254740993", "d"],
      ["9007199254740992", "e"],
      ["1.001", "f"],
      ["1.0001", "g"],
      ["01.00", "h"],
      ["+1", "i"],
    ],
  }
  let result = transform_table(table, [
    SortRows([{ column: "n", kind: Decimal, descending: false, }]),
  ])
  assert_eq(result.rows.map(r => r[1]), [
    "c", "h", "i", "g", "f", "b", "a", "e", "d",
  ])
  assert_eq(result.rows[1][0], "01.00")
  assert_eq(table.rows[0][1], "a")
}

///|
test "mixed directions use secondary keys and keep equal values stable" {
  let table : Table = {
    columns: ["region", "n", "id"],
    rows: [
      ["B", "2", "a"],
      ["A", "2", "b"],
      ["A", "10", "c"],
      ["A", "02.00", "d"],
      ["B", "10", "e"],
    ],
  }
  let result = transform_table(table, [
    SortRows([
      { column: "region", kind: Lexical, descending: false, },
      { column: "n", kind: Decimal, descending: true, },
    ]),
  ])
  assert_eq(result.rows.map(r => r[2]), ["c", "b", "d", "e", "a"])
}

///|
test "negative zero and normalized fractions compare equally in both directions" {
  let values = ["-0.00", "+0", "0", "-1.10", "-1.1", "-1.001", "-1.0001"]
  let table : Table = { columns: ["n"], rows: values.map(v => [v]), }
  let ascending = transform_table(table, [
    SortRows([{ column: "n", kind: Decimal, descending: false, }]),
  ])
  let descending = transform_table(table, [
    SortRows([{ column: "n", kind: Decimal, descending: true, }]),
  ])
  assert_eq(ascending.rows.map(r => r[0]), [
    "-1.10", "-1.1", "-1.001", "-1.0001", "-0.00", "+0", "0",
  ])
  assert_eq(descending.rows.map(r => r[0]), [
    "-0.00", "+0", "0", "-1.0001", "-1.001", "-1.10", "-1.1",
  ])
}

///|
test "numeric ordering rejects malformed or out-of-bound keys with row context" {
  for
    value in [
      "",
      " ",
      ".5",
      "1.",
      "+",
      "NaN",
      "1e3",
      "1,000",
      "1.2.3",
      "１２",
      "1".repeat(257),
    ] {
    let rejected = try {
      ignore(
        transform_table({ columns: ["amount"], rows: [["1"], [value]], }, [
          SortRows([{ column: "amount", kind: Decimal, descending: false, }]),
        ]),
      )
      false
    } catch {
      LoomError(message) => message.contains("row 2, column amount")
    }
    assert_true(rejected)
  }
  let large = "1".repeat(256)
  assert_eq(
    transform_table({ columns: ["n"], rows: [[large]], }, [
      SortRows([{ column: "n", kind: Decimal, descending: false, }]),
    ]).rows,
    [[large]],
  )
}

///|
test "text order is lexical by Unicode scalar, case sensitive and preserves blanks" {
  let values = ["😀", "中", "a", "A", "", "�", "z", "aa"]
  let result = transform_table(
    { columns: ["x"], rows: values.map(v => [v]), },
    [SortRows([{ column: "x", kind: Lexical, descending: false, }])],
  )
  assert_eq(result.rows.map(r => r[0]), [
    "", "A", "a", "aa", "z", "中", "�", "😀",
  ])
}

///|
test "sort input validation covers no keys, duplicate keys and missing columns" {
  let table : Table = { columns: ["x"], rows: [], }
  let key : SortKey = { column: "x", kind: Lexical, descending: false, }
  for
    keys in [
      [],
      [key, key],
      Array::make(9, key),
      [{ ..key, column: "missing", }],
    ] {
    let rejected = try {
      ignore(transform_table(table, [SortRows(keys)]))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_eq(transform_table(table, [SortRows([key])]), table)
}

///|
test "sort pipeline roundtrips and rebinds reordered incoming columns by name" {
  let pipeline : Pipeline = {
    columns: ["id", "n"],
    steps: [SortRows([{ column: "n", kind: Decimal, descending: false, }])],
  }
  let saved = pipeline_from_json(pipeline_to_json(pipeline))
  let result = apply_pipeline(saved, {
    columns: ["n", "extra", "id"],
    rows: [["10", "x", "A"], ["2", "y", "B"]],
  })
  assert_eq(result.columns, ["id", "n"])
  assert_eq(result.rows, [["B", "2"], ["A", "10"]])
}

///|
test "sort protocol rejects unknown kind, direction and key arity" {
  for
    key in [
      Json(["x", "float", "asc"]),
      Json(["x", "text", "up"]),
      Json(["x", "text"]),
    ] {
    let rejected = try {
      ignore(
        table_step_from_json(
          Json::array([Json("sort_rows"), Json::array([key])]),
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "learner finds mixed-key ordering and generalizes to new numeric widths" {
  let before : Table = {
    columns: ["region", "n", "id"],
    rows: [
      ["B", "2", "u"],
      ["A", "2", "r"],
      ["A", "10", "s"],
      ["B", "10", "a"],
      ["A", "1", "h"],
    ],
  }
  let after : Table = {
    ..before,
    rows: [
      before.rows[2],
      before.rows[1],
      before.rows[4],
      before.rows[3],
      before.rows[0],
    ],
  }
  let report = synthesize_table([{ before, after, }], options={
    ..default_table_options(),
    max_depth: 1,
  })
  assert_true(!report.candidates.is_empty())
  let held : Table = {
    ..before,
    rows: [["C", "3", "a"], ["D", "20", "b"], ["C", "11", "c"], ["D", "1", "d"]],
  }
  assert_eq(apply_pipeline(report.candidates[0], held).rows.map(r => r[2]), [
    "c", "a", "b", "d",
  ])
}

///|
test "learned order uses all pairs to resolve text versus decimal ambiguity" {
  let a : Table = { columns: ["n"], rows: [["2"], ["1"]], }
  let b : Table = { columns: ["n"], rows: [["2"], ["10"], ["1"]], }
  let report = synthesize_table(
    [
      { before: a, after: { ..a, rows: [["1"], ["2"]], }, },
      { before: b, after: { ..b, rows: [["1"], ["2"], ["10"]], }, },
    ],
    options={ ..default_table_options(), max_depth: 1, },
  )
  assert_true(!report.candidates.is_empty())
  assert_eq(
    apply_pipeline(report.candidates[0], { ..a, rows: [["20"], ["3"]], }).rows,
    [["3"], ["20"]],
  )
}

///|
test "sort witness cannot drop or duplicate rows to match a target" {
  let before : Table = { columns: ["x"], rows: [["B"], ["A"], ["A"]], }
  let wrong : Table = { ..before, rows: [["A"], ["B"], ["B"]], }
  let (steps, _) = sort_witnesses([before], [wrong])
  assert_true(steps.is_empty())
  let (identity, _) = sort_witnesses([before], [before])
  assert_true(identity.is_empty())
}

///|
test "sort inference can require three ordered keys" {
  let sorted = Array::makei(8, i => {
    [(i / 4).to_string(), (i / 2 % 2).to_string(), (i % 2).to_string()]
  })
  let before : Table = {
    columns: ["a", "b", "c"],
    rows: Array::makei(8, i => sorted[7 - i]),
  }
  let after : Table = { ..before, rows: sorted, }
  let report = synthesize_table([{ before, after, }], options={
    ..default_table_options(),
    max_depth: 1,
  })
  assert_true(!report.candidates.is_empty())
  assert_eq(apply_pipeline(report.candidates[0], before), after)
  assert_true(
    report.candidates[0].steps[0] is SortRows(keys) && keys.length() == 3,
  )
}

///|
test "runtime supports eight distinct sort keys including a decisive last key" {
  let columns = Array::makei(8, i => "c" + i.to_string())
  let row = Array::make(8, "0")
  let later = row.copy()
  later[7] = "1"
  let table : Table = { columns, rows: [later, row], }
  let keys = columns.map(column => SortKey::{
    column,
    kind: Decimal,
    descending: false,
  })
  let pipeline : Pipeline = { columns, steps: [SortRows(keys)], }
  assert_eq(
    apply_pipeline(pipeline_from_json(pipeline_to_json(pipeline)), table).rows,
    [row, later],
  )
}

///|
test "structural search composes wide-to-long conversion with numeric ordering" {
  let before : Table = {
    columns: ["id", "Jan", "Feb"],
    rows: [["B", "8", "2"], ["A", "1", "10"]],
  }
  let after : Table = {
    columns: ["id", "month", "value"],
    rows: [
      ["A", "Jan", "1"],
      ["B", "Feb", "2"],
      ["B", "Jan", "8"],
      ["A", "Feb", "10"],
    ],
  }
  let report = synthesize_table([{ before, after, }], options={
    ..default_table_options(),
    max_depth: 2,
  })
  assert_true(!report.candidates.is_empty())
  let held : Table = { ..before, rows: [["C", "30", "4"], ["D", "2", "12"]], }
  assert_eq(apply_pipeline(report.candidates[0], held).rows, [
    ["D", "Jan", "2"],
    ["C", "Feb", "4"],
    ["D", "Feb", "12"],
    ["C", "Jan", "30"],
  ])
}
