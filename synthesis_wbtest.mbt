///|
test "synthesis retains delimiter and suffix explanations of the same samples" {
  let report = synthesize([
    { input: ["订单-0012"], output: "0012", },
    { input: ["订单-0081"], output: "0081", },
  ])
  assert_true(report.candidates.length() > 1)
  assert_true(
    report.candidates.any(c => {
      attempt(c.expression, ["订单-123456"]) == Ok("123456")
    }),
  )
  assert_true(
    report.candidates.any(c => {
      attempt(c.expression, ["订单-123456"]) == Ok("3456")
    }),
  )
  for c in report.candidates {
    assert_eq(evaluate(c.expression, ["订单-0012"]), "0012")
    assert_eq(evaluate(c.expression, ["订单-0081"]), "0081")
  }
}

///|
test "extra example eliminates the four character suffix" {
  let report = synthesize([
    { input: ["订单-0012"], output: "0012", },
    { input: ["订单-123456"], output: "123456", },
  ])
  assert_true(report.candidates.length() > 0)
  assert_eq(
    evaluate(report.candidates[0].expression, ["订单-00987"]),
    "00987",
  )
}

///|
test "search composes fields and a learned literal" {
  let report = synthesize([
    { input: ["陈雨", "A1"], output: "A1 / 陈雨", },
    { input: ["王琪", "B12"], output: "B12 / 王琪", },
  ])
  assert_true(report.candidates.length() > 0)
  assert_eq(
    evaluate(report.candidates[0].expression, ["赵晨", "C20"]),
    "C20 / 赵晨",
  )
}

///|
test "date format inference validates a held-out leap day" {
  let report = synthesize([
    { input: ["20260112"], output: "2026-01-12", },
    { input: ["20231209"], output: "2023-12-09", },
  ])
  assert_true(report.candidates.length() > 0)
  assert_eq(
    evaluate(report.candidates[0].expression, ["20240229"]),
    "2024-02-29",
  )
}

///|
test "contradictions fail early" {
  let failed = try {
    ignore(
      synthesize([
        { input: ["same"], output: "a", },
        { input: ["same"], output: "b", },
      ]),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "resource exhaustion is not reported as uniqueness or impossibility" {
  let report = synthesize([{ input: ["a-b"], output: "b", }], options={
    max_candidates: 1,
    max_parts: 2,
    max_atom_evaluations: 1,
    max_steps: 1,
    max_frontier: 1,
  })
  assert_true(report.truncated)
  assert_true(report.status != "exhausted_observed_grammar")
}

///|
test "unsupported transform has no claimed solution" {
  let report = synthesize([
    { input: ["a"], output: "1", },
    { input: ["b"], output: "2", },
  ])
  assert_eq(report.candidates.length(), 0)
  assert_true(!report.truncated)
}

///|
test "deterministic search produces stable ordered candidates" {
  let examples = [
    { input: ["x-001"], output: "001", },
    { input: ["y-002"], output: "002", },
  ]
  assert_eq(
    synthesize(examples).candidates.map(c => explain(c.expression)),
    synthesize(examples).candidates.map(c => explain(c.expression)),
  )
}
