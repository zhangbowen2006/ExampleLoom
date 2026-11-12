///|
test "decimal aggregation is exact canonical and independent of Int64 or float" {
  let table : Table = {
    columns: ["category", "amount"],
    rows: [
      ["A", "0.1"],
      ["A", "0.20"],
      ["B", "9007199254740993.01"],
      ["B", "-0.01"],
      ["C", "-000.000"],
    ],
  }
  let step = Aggregate(["category"], [
    { name: "sum", metric: SumDecimal("amount"), },
    { name: "min", metric: MinDecimal("amount"), },
    { name: "max", metric: MaxDecimal("amount"), },
    { name: "n", metric: RowCount, },
  ])
  assert_eq(
    transform_table(table, [table_step_from_json(table_step_to_json(step))]).rows,
    [
      ["A", "0.3", "0.1", "0.2", "2"],
      ["B", "9007199254740993", "-0.01", "9007199254740993.01", "2"],
      ["C", "0", "0", "0", "1"],
    ],
  )
  let empty : Table = { columns: ["amount"], rows: [], }
  assert_eq(
    transform_table(empty, [
      Aggregate([], [
        { name: "sum", metric: SumDecimal("amount"), },
        { name: "n", metric: RowCount, },
      ]),
    ]).rows,
    [["", "0"]],
  )
}

///|
test "signed decimal carry borrow and exact cancellation preserve arbitrary precision" {
  for
    (a, b, c) in [
      ("999.99", "0.01", "1000"),
      ("1", "-0.0001", "0.9999"),
      ("-10.1", "1.11", "-8.99"),
      ("-0.1", "0.1", "0"),
    ] {
    assert_eq(
      decimal_text(
        add_decimal(
          exact_decimal(decimal_order(a)),
          exact_decimal(decimal_order(b)),
        ),
      ),
      c,
    )
  }
  for text in ["", "1e2", " 0.1", ".1", "1.", "NaN"] {
    assert_true(
      try {
        ignore(
          transform_table({ columns: ["a"], rows: [[text]], }, [
            Aggregate([], [{ name: "s", metric: SumDecimal("a"), }]),
          ]),
        )
        false
      } catch {
        LoomError(s) => s.contains("row 1, column a")
      },
    )
  }
}

///|
test "table examples learn decimal sums and replay unseen rows" {
  let before : Table = {
    columns: ["group", "amount"],
    rows: [["A", "0.1"], ["A", "0.2"], ["B", "2.1"], ["B", "0.15"]],
  }
  let after : Table = {
    columns: ["group", "total"],
    rows: [["A", "0.3"], ["B", "2.25"]],
  }
  let report = synthesize_table([{ before, after, }])
  assert_true(!report.candidates.is_empty())
  assert_eq(
    apply_pipeline(report.candidates[0], {
      ..before,
      rows: [["Z", "999.99"], ["Z", "0.01"]],
    }).rows,
    [["Z", "1000"]],
  )
}

///|
test "decimal output limit is checked while appending each measure" {
  let value = Array::make(256, "9").join("")
  let table : Table = {
    columns: ["key", "amount"],
    rows: Array::makei(3000, i => [i.to_string(), value]),
  }
  let measures = Array::makei(63, i => Measure::{
    name: "s\{i}",
    metric: SumDecimal("amount"),
  })
  assert_true(
    try {
      ignore(transform_table(table, [Aggregate(["key"], measures)]))
      false
    } catch {
      LoomError(s) => s.contains("decimal aggregate output exceeds")
    },
  )
}
