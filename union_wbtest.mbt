///|
test "by-name concat aligns reordered schemas with explicit policies and provenance" {
  let sources : Array[NamedTable] = [
    { name: "old", table: { columns: ["id", "a"], rows: [["001", "x"]], }, },
    { name: "new", table: { columns: ["b", "id"], rows: [["y", "002"]], }, },
  ]
  let spec = { ..default_union_spec(), mode: "union", }
  assert_eq(
    concat_tables(sources, union_spec_from_json(union_spec_to_json(spec))),
    {
      columns: ["id", "a", "b", "_source"],
      rows: [["001", "x", "", "old"], ["002", "", "y", "new"]],
    },
  )
  assert_eq(concat_tables(sources, { ..spec, mode: "intersection", }), {
    columns: ["id", "_source"],
    rows: [["001", "old"], ["002", "new"]],
  })
  assert_true(
    try {
      ignore(concat_tables(sources, default_union_spec()))
      false
    } catch {
      LoomError(_) => true
    },
  )
  assert_eq(
    concat_tables(
      [
        { name: "a", table: { columns: ["x", "y"], rows: [["1", "2"]], }, },
        { name: "b", table: { columns: ["y", "x"], rows: [["4", "3"]], }, },
      ],
      default_union_spec(),
    ).rows,
    [["1", "2", "a"], ["3", "4", "b"]],
  )
  assert_eq(sources[1].table.columns, ["b", "id"])
}

///|
test "concat rejects lossy hidden policies names conflicts and empty intersection" {
  let a : NamedTable = { name: "a", table: { columns: ["x"], rows: [], }, }
  assert_true(
    try {
      ignore(concat_tables([a, a], default_union_spec()))
      false
    } catch {
      LoomError(_) => true
    },
  )
  assert_true(
    try {
      ignore(
        concat_tables([a], { ..default_union_spec(), source_column: "x", }),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
  assert_true(
    try {
      ignore(
        concat_tables(
          [a, { name: "b", table: { columns: ["y"], rows: [], }, }],
          { ..default_union_spec(), mode: "intersection", },
        ),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
}

///|
test "source provenance cannot overwrite a column hidden by intersection" {
  let sources : Array[NamedTable] = [
    { name: "a", table: { columns: ["x", "_source"], rows: [], }, },
    { name: "b", table: { columns: ["x"], rows: [], }, },
  ]
  assert_true(
    try {
      ignore(
        concat_tables(sources, { ..default_union_spec(), mode: "intersection", }),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
}
