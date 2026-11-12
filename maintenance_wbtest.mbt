///|
test "whole table flattening uses the new batch size and preserves cells" {
  let before : Table = { columns: ["a", "b"], rows: [["A", ""], ["B", "007"]], }
  let after : Table = {
    columns: ["c0", "c1", "c2", "c3"],
    rows: [["A", "", "B", "007"]],
  }
  let other : Table = {
    columns: before.columns,
    rows: [["D", "1"], ["E", "2"], ["F", "3"]],
  }
  let other_target : Table = {
    columns: generic_columns(6),
    rows: [["D", "1", "E", "2", "F", "3"]],
  }
  let report = synthesize_table([
    { before, after, },
    { before: other, after: other_target, },
  ])
  assert_true(!report.candidates.is_empty())
  let saved = pipeline_from_json(pipeline_to_json(report.candidates[0]))
  let next : Table = {
    columns: ["b", "a"],
    rows: [["1", "X"], ["2", "Y"], ["3", "Z"]],
  }
  assert_eq(apply_pipeline(saved, next).rows, [["X", "1", "Y", "2", "Z", "3"]])
  assert_eq(before.rows, [["A", ""], ["B", "007"]])
  for
    t in [
      Table::{ columns: ["a"], rows: [], },
      Table::{ columns: ["a"], rows: Array::make(65, ["v"]), },
    ] {
    assert_true(
      try {
        ignore(transform_table(t, [FlattenRows]))
        false
      } catch {
        LoomError(_) => true
      },
    )
  }
}

///|
test "sparse routing learns a complete empty-state partition without losing fields" {
  let before : Table = {
    columns: ["name", "detail"],
    rows: [["Full name", ""], ["First", "Last"]],
  }
  let after : Table = {
    columns: ["full", "first", "last"],
    rows: [["Full name", "", ""], ["", "First", "Last"]],
  }
  let r = synthesize_table([{ before, after, }])
  assert_true(!r.candidates.is_empty())
  assert_true(
    sparse_routing_cost(
      match r.candidates[0].steps[0] {
        MapRows(r) => r
        _ => { columns: [], outputs: [], }
      },
    )
    is Some(_),
  )
  let next : Table = {
    columns: ["detail", "name"],
    rows: [["", "甲😀"], ["Family", "Other"], ["", "007"]],
  }
  assert_eq(
    apply_pipeline(pipeline_from_json(pipeline_to_json(r.candidates[0])), next).rows,
    [["甲😀", "", ""], ["", "Other", "Family"], ["007", "", ""]],
  )
  assert_true(
    sparse_routing_witness([before], [
      { ..after, rows: [["lost", "", ""], ["", "First", "Last"]], },
    ])
    is None,
  )
  assert_true(
    sparse_routing_witness([{ ..before, rows: [before.rows[0]], }], [
      { ..after, rows: [after.rows[0]], },
    ])
    is None,
  )
}
