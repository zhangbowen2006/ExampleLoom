///|
test "stable explicit join distinguishes unmatched cells and coalesces full keys" {
  let a : Table = {
    columns: ["id", "value"],
    rows: [["A", "x"], ["B", ""], ["", "blank"]],
  }
  let b : Table = {
    columns: ["key", "value"],
    rows: [["B", ""], ["C", "z"], ["", "no"]],
  }
  let spec = { ..default_join_spec(["id"], ["key"]), kind: "full", }
  let saved = join_spec_from_json(join_spec_to_json(spec))
  let result = join_tables(a, b, saved)
  assert_eq(result.columns, ["id", "value", "value_right", "_match"])
  assert_eq(result.rows, [
    ["A", "x", "", "left_only"],
    ["B", "", "", "both"],
    ["", "blank", "", "left_only"],
    ["C", "", "z", "right_only"],
    ["", "", "no", "right_only"],
  ])
  assert_eq(a.rows[0], ["A", "x"])
  assert_eq(join_tables(a, b, { ..spec, kind: "semi", }).rows, [
    ["B", "", "both"],
  ])
  assert_eq(join_tables(a, b, { ..spec, kind: "anti", }).rows, [
    ["A", "x", "left_only"],
    ["", "blank", "left_only"],
  ])
  assert_eq(
    join_tables(a, b, { ..spec, kind: "inner", empty_keys: "match", }).rows.length(),
    2,
  )
}

///|
test "join checks relationship and expansion before result allocation" {
  let a : Table = { columns: ["k"], rows: [["A"], ["A"]], }
  assert_true(
    try {
      ignore(join_tables(a, a, default_join_spec(["k"], ["k"])))
      false
    } catch {
      LoomError(_) => true
    },
  )
  let spec = {
    ..default_join_spec(["k"], ["k"]),
    relationship: "many_to_many",
  }
  assert_eq(join_tables(a, a, spec).rows.length(), 4)
  let large : Table = { columns: ["k"], rows: Array::make(150, ["A"]), }
  assert_true(
    try {
      ignore(join_tables(large, large, spec))
      false
    } catch {
      LoomError(s) => s.contains("20000")
    },
  )
  let collide : Table = { columns: ["k", "k_right", "_match"], rows: [], }
  assert_true(
    try {
      ignore(join_tables(collide, a, spec))
      false
    } catch {
      LoomError(_) => true
    },
  )
  let key_a : Table = { columns: ["x", "y"], rows: [["a|b", "c"]], }
  let key_b : Table = { columns: ["x", "y"], rows: [["a", "b|c"]], }
  assert_eq(
    join_tables(key_a, key_b, {
      ..default_join_spec(["x", "y"], ["x", "y"]),
      kind: "inner",
    }).rows,
    [],
  )
}

///|
test "semi and anti joins do not enumerate duplicate Cartesian matches" {
  let source : Table = { columns: ["k"], rows: Array::make(20000, ["A"]), }
  let spec = {
    ..default_join_spec(["k"], ["k"]),
    kind: "semi",
    relationship: "many_to_many",
  }
  assert_eq(join_tables(source, source, spec).rows.length(), 20000)
  assert_eq(
    join_tables(source, source, { ..spec, kind: "anti", }).rows.length(),
    0,
  )
}
