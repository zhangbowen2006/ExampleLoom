///|
test "learn optional suffixes within a longer concatenated result" {
  let r = synthesize([
    {
      input: ["Unit A", "Harbor; NW; READY"],
      output: "Unit A, Harbor; NW; READY",
    },
    { input: ["Unit BBB", "Hill; SE"], output: "Unit BBB, Hill; SE; READY", },
    { input: ["Unit C", "Lake; NE; READY"], output: "Unit C, Lake; NE; READY", },
  ])
  assert_true(!r.candidates.is_empty())
  let expr = r.candidates[0].expression
  assert_eq(
    evaluate(expr, ["New unit", "Ridge; SW"]),
    "New unit, Ridge; SW; READY",
  )
  assert_eq(
    evaluate(expr, ["New unit", "Ridge; SW; READY"]),
    "New unit, Ridge; SW; READY",
  )
}

///|
test "token normalization keeps an equal city token and escapes literal dollars" {
  let r = synthesize([
    { input: ["North West, North West, LIVE"], output: "North West, NW, LIVE", },
    { input: ["Lake, North West, LIVE"], output: "Lake, NW, LIVE", },
    { input: ["Hill, SE"], output: "Hill, SE, LIVE", },
  ])
  assert_true(!r.candidates.is_empty())
  assert_eq(
    evaluate(r.candidates[0].expression, ["Other, North West"]),
    "Other, NW, LIVE",
  )
  assert_eq(
    evaluate(r.candidates[0].expression, ["New, SW, LIVE"]),
    "New, SW, LIVE",
  )
  let dollar = synthesize([
    { input: ["A; Long Name"], output: "A; $Q", },
    { input: ["B; Long Name"], output: "B; $Q", },
    { input: ["C; Short"], output: "C; Short", },
  ])
  assert_true(!dollar.candidates.is_empty())
  assert_eq(
    evaluate(dollar.candidates[0].expression, ["Next; Long Name"]),
    "Next; $Q",
  )
}

///|
test "packing followed by projection learns from every paired table" {
  let one : Table = {
    columns: ["id", "label", "detail"],
    rows: [
      ["A", "Alpha", ""],
      ["", "IGNORE", "03"],
      ["B", "Beta", ""],
      ["", "DROP", "07"],
    ],
  }
  let expected : Table = {
    columns: ["id", "label", "quantity"],
    rows: [["A", "Alpha", "03"], ["B", "Beta", "07"]],
  }
  let other : Table = { ..one, rows: [["C", "Gamma", ""], ["", "SKIP", "14"]], }
  let other_target : Table = { ..expected, rows: [["C", "Gamma", "14"]], }
  let r = synthesize_table([
    { before: one, after: expected, },
    { before: other, after: other_target, },
  ])
  assert_true(!r.candidates.is_empty())
  let held : Table = {
    ..one,
    rows: [["D", "Delta", ""], ["", "UNUSED", "99"]],
  }
  assert_eq(apply_pipeline(r.candidates[0], held).rows, [["D", "Delta", "99"]])
}

///|
test "split and fold turn independent delimited records into long tables" {
  let input : Table = {
    columns: ["reading"],
    rows: [["10:00 3 4"], ["10:01 7 8"]],
  }
  let output : Table = {
    columns: ["time", "value"],
    rows: [["10:00", "3"], ["10:00", "4"], ["10:01", "7"], ["10:01", "8"]],
  }
  let r = synthesize_table([{ before: input, after: output, }])
  assert_true(!r.candidates.is_empty())
  assert_eq(
    apply_pipeline(r.candidates[0], { ..input, rows: [["11:27 -19 004"]], }).rows,
    [["11:27", "-19"], ["11:27", "004"]],
  )
}

///|
test "one delimited record learns per-record keys instead of a constant header" {
  let input : Table = { columns: ["reading"], rows: [["10:00 3 4"]], }
  let output : Table = {
    columns: ["time", "value"],
    rows: [["10:00", "3"], ["10:00", "4"]],
  }
  let r = synthesize_table([{ before: input, after: output, }])
  assert_true(!r.candidates.is_empty())
  assert_eq(
    apply_pipeline(r.candidates[0], {
      ..input,
      rows: [["11:27 -19 004"], ["11:28 7 8"]],
    }).rows,
    [["11:27", "-19"], ["11:27", "004"], ["11:28", "7"], ["11:28", "8"]],
  )
}

///|
test "grouping by an observed key takes precedence over fixed record packing" {
  let input : Table = {
    columns: ["account", "sequence", "amount"],
    rows: [["A", "1", "x"], ["A", "2", "y"], ["A", "3", "z"]],
  }
  let output : Table = {
    columns: ["c0", "c1", "c2", "c3"],
    rows: [["A", "x", "y", "z"]],
  }
  let r = synthesize_table([{ before: input, after: output, }])
  assert_true(!r.candidates.is_empty())
  assert_true(r.candidates[0].steps.any(step => step is GroupRows(_, _)))
  assert_eq(
    apply_pipeline(r.candidates[0], {
      ..input,
      rows: [["B", "1", "02"], ["B", "2", "04"], ["C", "1", "07"]],
    }).rows,
    [["B", "02", "04"], ["C", "07", ""]],
  )
}

///|
test "a single table example can learn selectors with different future widths" {
  let input : Table = { columns: ["raw"], rows: [["price=42;items=3"]], }
  let output : Table = { columns: ["amount", "items"], rows: [["42", "3"]], }
  let r = synthesize_table([{ before: input, after: output, }])
  assert_true(!r.candidates.is_empty())
  assert_eq(
    apply_pipeline(r.candidates[0], { ..input, rows: [["price=314;items=27"]], }).rows,
    [["314", "27"]],
  )
}

///|
test "key-value record blocks become a labelled grid on a new batch" {
  let input : Table = {
    columns: ["line"],
    rows: [
      ["ID=A"],
      ["weight=03"],
      ["color=red"],
      ["ID=B"],
      ["weight=7"],
      ["color=blue"],
    ],
  }
  let output : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["ID", "weight", "color"], ["A", "03", "red"], ["B", "7", "blue"]],
  }
  let r = synthesize_table([{ before: input, after: output, }])
  assert_true(!r.candidates.is_empty())
  assert_eq(
    apply_pipeline(r.candidates[0], {
      ..input,
      rows: [["ID=C"], ["weight=0"], ["color=green"]],
    }).rows,
    [["ID", "weight", "color"], ["C", "0", "green"]],
  )
}
