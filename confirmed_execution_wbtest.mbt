///|
test "unattended execution requires all successful candidates to agree on this entire batch" {
  let identity : Pipeline = { columns: ["x"], steps: [], }
  let flatten : Pipeline = { columns: ["x"], steps: [FlattenRows], }
  let t : Table = { columns: ["x"], rows: [["A"], ["B"]], }
  assert_true(
    try {
      ignore(execute_table_candidates([identity, flatten], t))
      false
    } catch {
      LoomError(_) => true
    },
  )
  let selected = execute_table_candidates(
    [identity, flatten],
    t,
    chosen=Some(1),
  )
  assert_eq(selected.selection, "explicit_choice")
  assert_eq(selected.table.rows, [["A", "B"]])
  let agreed = execute_table_candidates([identity, identity], t)
  assert_eq(agreed.selection, "observed_consensus")
  assert_true(agreed.chosen is None)
  assert_eq(agreed.table, t)
  let bad : Pipeline = { columns: ["missing"], steps: [], }
  assert_true(
    try {
      ignore(execute_table_candidates([identity, bad], t))
      false
    } catch {
      LoomError(_) => true
    },
  )
  assert_true(
    try {
      ignore(execute_table_candidates([bad, bad], t))
      false
    } catch {
      LoomError(_) => true
    },
  )
  let single : Table = { columns: ["c0"], rows: [["A"]], }
  let p : Pipeline = { columns: ["c0"], steps: [], }
  let f : Pipeline = { columns: ["c0"], steps: [FlattenRows], }
  assert_eq(
    execute_table_candidates([p, f], single).selection,
    "observed_consensus",
  )
  assert_true(
    try {
      ignore(
        execute_table_candidates([p, f], { ..single, rows: [["A"], ["B"]], }),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
}
