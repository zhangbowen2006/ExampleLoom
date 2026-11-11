///|
test "table comparison distinguishes equal training programs on a new batch" {
  let packed : Pipeline = { columns: ["c0"], steps: [PackRows(2, false)], }
  let transposed : Pipeline = { columns: ["c0"], steps: [Transpose], }
  let small : Table = { columns: ["c0"], rows: [["A"], ["red"]], }
  assert_eq(apply_pipeline(packed, small), apply_pipeline(transposed, small))
  let batch : Table = { ..small, rows: [["B"], ["blue"], ["C"], ["green"]], }
  let before = table_json(batch).stringify()
  let r = compare_table_candidates([packed, transposed, packed], batch)
  assert_eq(r.status, "disagreement")
  assert_eq(r.successful_candidates, 3)
  assert_eq(r.groups.map(g => g.candidates), [[0, 2], [1]])
  assert_eq(r.first_difference, Some(ColumnNames))
  assert_eq(table_json(batch).stringify(), before)
  assert_eq(apply_pipeline(packed, batch).rows, [["B", "blue"], ["C", "green"]])
}

///|
test "table comparison includes cells beyond its UI preview and preserves zeros" {
  let table : Table = {
    columns: ["a", "b"],
    rows: [
      ["x", "x"],
      ["x", "x"],
      ["x", "x"],
      ["x", "x"],
      ["x", "x"],
      ["01", "1"],
    ],
  }
  let r = compare_table_candidates(
    [
      { columns: table.columns, steps: [Select(["a"], ["value"])], },
      { columns: table.columns, steps: [Select(["b"], ["value"])], },
    ],
    table,
  )
  assert_eq(r.status, "disagreement")
  assert_eq(r.first_difference, Some(Cell(5, 0)))
}

///|
test "table comparison treats schema and row count as semantic differences" {
  let table : Table = { columns: ["x"], rows: [["a"], ["b"]], }
  let identity : Pipeline = { columns: ["x"], steps: [], }
  let renamed : Pipeline = {
    columns: ["x"],
    steps: [Select(["x"], ["other"])],
  }
  let dropped : Pipeline = { columns: ["x"], steps: [DropRows(1)], }
  assert_eq(
    compare_table_candidates([identity, renamed], table).first_difference,
    Some(ColumnNames),
  )
  assert_eq(
    compare_table_candidates([identity, dropped], table).first_difference,
    Some(RowCount),
  )
}

///|
test "table comparison keeps failing candidates beside successful predictions" {
  let table : Table = { columns: ["x"], rows: [["a"], ["b"], ["c"]], }
  let packed : Pipeline = { columns: ["x"], steps: [PackRows(2, false)], }
  let identity : Pipeline = { columns: ["x"], steps: [], }
  let r = compare_table_candidates([packed, identity, packed], table)
  assert_eq(r.status, "disagreement")
  assert_eq(r.successful_candidates, 1)
  assert_eq(r.groups.map(g => g.candidates), [[0, 2], [1]])
  assert_eq(r.first_difference, Some(Execution))
  assert_true(r.groups[0].prediction is Err(_))
  assert_eq(r.groups[1].prediction, Ok(table))
}

///|
test "all failing table programs cannot report successful consensus" {
  let table : Table = { columns: ["x"], rows: [["a"]], }
  let bad : Pipeline = { columns: ["missing"], steps: [], }
  let r = compare_table_candidates([bad, bad], table)
  assert_eq(r.status, "all_failed")
  assert_eq(r.successful_candidates, 0)
  assert_eq(r.groups.length(), 1)
  assert_eq(r.first_difference, None)
}

///|
test "matching table predictions and empty results remain finite observations" {
  let table : Table = { columns: ["x"], rows: [], }
  let identity : Pipeline = { columns: ["x"], steps: [], }
  let r = compare_table_candidates([identity, identity], table)
  assert_eq(r.status, "consistent")
  assert_eq(r.groups[0].prediction, Ok(table))
  assert_eq(r.groups[0].candidates, [0, 1])
  assert_eq(r.first_difference, None)
}

///|
test "table comparison refuses oversized batches rather than truncating records" {
  let identity : Pipeline = { columns: ["x"], steps: [], }
  let rejected = try {
    ignore(
      compare_table_candidates([identity], {
        columns: ["x"],
        rows: Array::make(2001, [""]),
      }),
    )
    false
  } catch {
    LoomError(message) => message.contains("2000 rows")
  }
  assert_true(rejected)
  for candidates in [[], Array::make(9, identity)] {
    let rejected = try {
      ignore(
        compare_table_candidates(candidates, { columns: ["x"], rows: [], }),
      )
      false
    } catch {
      LoomError(message) => message.contains("1..8 pipelines")
    }
    assert_true(rejected)
  }
}

///|
test "comparison output limit aborts without misclassifying a valid program" {
  let table : Table = {
    columns: ["key", "tags"],
    rows: [["x".repeat(10000), "v,".repeat(39) + "v"]],
  }
  let pipeline : Pipeline = {
    columns: table.columns,
    steps: [Explode("tags", ",")],
  }
  assert_eq(apply_pipeline(pipeline, table).rows.length(), 40)
  let rejected = try {
    ignore(compare_table_candidates([pipeline], table))
    false
  } catch {
    LoomError(message) => message.contains("250000 UTF-16 units")
  }
  assert_true(rejected)
}

///|
test "table comparison protocol exposes error outcomes and rejects unknown fields" {
  let request =
    #|{"op":"compare_table_candidates","pipelines":[{"version":2,"columns":["x"],"steps":[]},{"version":2,"columns":["x"],"steps":[["pack_rows",2,false]]}],"table":{"columns":["x"],"rows":[["a"]]}}
  let result = j_object(parse_json_text(handle(request)))
  assert_eq(required(result, "ok"), Json(true))
  assert_eq(required(result, "status"), Json("disagreement"))
  assert_eq(required(result, "successful_candidates"), Json(1))
  let obj = j_object(parse_json_text(request))
  obj["unexpected"] = Json(true)
  assert_eq(
    required(
      j_object(parse_json_text(handle(Json::object(obj).stringify()))),
      "ok",
    ),
    Json(false),
  )
}
