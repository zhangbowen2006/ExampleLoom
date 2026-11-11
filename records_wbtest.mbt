///|
test "pivot repeated key value records with missing and newly observed fields" {
  let table : Table = {
    columns: ["value", "key"],
    rows: [
      ["Beta", "name"],
      ["East", "city"],
      ["8", "score"],
      ["Gamma", "name"],
      ["9", "score"],
      ["CN", "country"],
    ],
  }
  let p : Pipeline = {
    columns: ["key", "value"],
    steps: [PivotRecords("key", "value", "name")],
  }
  let restored = pipeline_from_json(pipeline_to_json(p))
  assert_eq(apply_pipeline(restored, table), {
    columns: ["c0", "c1", "c2", "c3"],
    rows: [
      ["name", "city", "score", "country"],
      ["Beta", "East", "8", ""],
      ["Gamma", "", "9", "CN"],
    ],
  })
}

///|
test "pivot repeated records rejects ambiguous duplicate keys and missing marker" {
  let p = PivotRecords("key", "value", "name")
  let cases : Array[Table] = [
    { columns: ["key", "value"], rows: [], },
    { columns: ["key", "value"], rows: [["city", "X"], ["name", "A"]], },
    { columns: ["key", "value"], rows: [["name", "A"], ["", "X"]], },
    {
      columns: ["key", "value"],
      rows: [["name", "A"], ["city", "X"], ["city", "Y"]],
    },
  ]
  for table in cases {
    let bad = try {
      ignore(transform_table(table, [p]))
      false
    } catch {
      LoomError(_) => true
    }
    assert_true(bad)
  }
}

///|
test "record synthesis learns marker from examples and generalizes to more records" {
  let before : Table = {
    columns: ["key", "value"],
    rows: [["name", "Alpha"], ["city", "North"], ["score", "7"]],
  }
  let after : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["name", "city", "score"], ["Alpha", "North", "7"]],
  }
  let r = synthesize_table([{ before, after, }])
  assert_true(!r.candidates.is_empty())
  let next : Table = {
    columns: before.columns,
    rows: [
      ["name", "Beta"],
      ["city", "East"],
      ["score", "8"],
      ["name", "Gamma"],
      ["score", "9"],
      ["country", "CN"],
    ],
  }
  assert_eq(apply_pipeline(r.candidates[0], next).rows, [
    ["name", "city", "score", "country"],
    ["Beta", "East", "8", ""],
    ["Gamma", "", "9", "CN"],
  ])
}
