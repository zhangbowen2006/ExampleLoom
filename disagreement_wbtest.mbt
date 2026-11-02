///|
test "select a real row exposing suffix overfit" {
  let report = synthesize([
    { input: ["订单-0012"], output: "0012", },
    { input: ["订单-0081"], output: "0081", },
  ])
  let rows = [["订单-0099"], ["订单-123456"], ["订单-0031"]]
  let suggestions = disagreements(report.candidates, rows)
  assert_true(suggestions.length() > 0)
  assert_eq(suggestions[0].row_index, 1)
  assert_true(suggestions[0].groups.any(g => g.prediction == Ok("123456")))
  assert_true(suggestions[0].groups.any(g => g.prediction == Ok("3456")))
}

///|
test "prediction failures are a separate outcome" {
  let candidates = [
    { expression: Token(Field(0), "-", 1), cost: 5, },
    { expression: Field(0), cost: 2, },
  ]
  let suggestions = disagreements(candidates, [["plain"]])
  assert_eq(suggestions.length(), 1)
  assert_true(suggestions[0].groups.any(g => g.prediction is Err(_)))
}

///|
test "balanced split outranks one against three and ties are stable" {
  let candidates = [
    { expression: Token(Field(0), "-", 0), cost: 1, },
    { expression: Token(Field(0), "-", 1), cost: 1, },
    { expression: Token(Field(0), "-", 2), cost: 1, },
    { expression: Token(Field(0), "-", 3), cost: 1, },
  ]
  let suggestions = disagreements(candidates, [
    ["a-a-a-b"],
    ["a-a-b-b"],
    ["c-c-d-d"],
  ])
  assert_eq(suggestions.map(s => s.row_index), [1, 2, 0])
  assert_eq(suggestions[0].score, 8)
}
