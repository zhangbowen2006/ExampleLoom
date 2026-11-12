///|
test "declared transpose validates examples and handles a new row count" {
  let before : Table = {
    columns: ["c0", "c1"],
    rows: [["A", "B"], ["C", "D"]],
  }
  let after : Table = { columns: ["c0", "c1"], rows: [["A", "C"], ["B", "D"]], }
  let report = synthesize_table([{ before, after, }], intent="transpose_all")
  assert_eq(report.status, "intent_checked")
  assert_eq(report.candidates.length(), 1)
  assert_eq(report.candidates[0].steps.length(), 1)
  assert_true(report.candidates[0].steps[0] is Transpose)
  let next : Table = {
    columns: ["c0", "c1"],
    rows: [["X", "Y"], ["Z", "Q"], ["M", "N"]],
  }
  assert_eq(apply_pipeline(report.candidates[0], next), {
    columns: ["c0", "c1", "c2"],
    rows: [["X", "Z", "M"], ["Y", "Q", "N"]],
  })
  let no = synthesize_table(
    [{ before, after: before, }],
    intent="transpose_all",
  )
  assert_eq(no.status, "intent_inconsistent")
  assert_true(no.candidates.is_empty())
}

///|
test "declared transpose accepts the full 64-column table representation" {
  let wide : Table = {
    columns: Array::makei(64, i => "c\{i}"),
    rows: [Array::makei(64, i => "v\{i}")],
  }
  let tall : Table = {
    columns: ["c0"],
    rows: Array::makei(64, i => ["v\{i}"]),
  }
  let report = synthesize_table(
    [{ before: wide, after: tall, }],
    intent="transpose_all",
  )
  assert_eq(report.status, "intent_checked")
  assert_eq(apply_pipeline(report.candidates[0], wide), tall)
}
