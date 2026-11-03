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

///|
test "all example permutations learn the same case and trim rule" {
  let samples : Array[Example] = [
    { input: ["x-abc"], output: "abc", },
    { input: ["x-DeF"], output: "def", },
    { input: ["xx- GhiJ "], output: "ghij", },
  ]
  let reference = synthesize(samples)
  assert_true(reference.candidates.length() > 0)
  assert_eq(
    evaluate(reference.candidates[0].expression, ["long- KlMnO "]),
    "klmno",
  )
  for
    order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
    let actual = synthesize(order.map(i => samples[i]))
    assert_eq(
      actual.candidates.map(c => explain(c.expression)),
      reference.candidates.map(c => explain(c.expression)),
    )
    assert_eq(actual.steps, reference.steps)
    assert_eq(actual.status, reference.status)
  }
}

///|
test "duplicate observations do not change a bounded search" {
  let a : Example = { input: ["x-abc"], output: "abc", }
  let b : Example = { input: ["x-DeF"], output: "def", }
  let first = synthesize([a, b])
  let second = synthesize([b, a, b, a])
  assert_eq(
    first.candidates.map(c => explain(c.expression)),
    second.candidates.map(c => explain(c.expression)),
  )
  assert_eq(first.atom_evaluations, second.atom_evaluations)
}

///|
test "observed punctuation generalizes variable width fields" {
  for separator in ["#", "；", "=>", "::", " / "] {
    let report = synthesize([
      {
        input: ["东区" + separator + "张三" + separator + "一班"],
        output: "张三",
      },
      {
        input: [
          "华北新区" + separator + "李小明" + separator + "实验班",
        ],
        output: "李小明",
      },
    ])
    assert_true(report.candidates.length() > 0)
    assert_eq(
      evaluate(report.candidates[0].expression, [
        "西南" + separator + "赵晓晨" + separator + "毕业班",
      ]),
      "赵晓晨",
    )
  }
}

///|
test "explicit textual separators are available to library callers" {
  let report = synthesize(
    [
      { input: ["张三来自东区"], output: "东区", },
      { input: ["李小明来自华北新区"], output: "华北新区", },
    ],
    separators=["来自"],
  )
  assert_true(report.candidates.length() > 0)
  assert_eq(
    evaluate(report.candidates[0].expression, ["赵晨来自西南"]),
    "西南",
  )
}

///|
test "extra separators validate their resource bounds" {
  for separators in [[""], ["abcdefghijklmnopq"], Array::make(17, "#")] {
    let failed = try {
      ignore(synthesize([{ input: ["x#y"], output: "y", }], separators~))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "tokens can exist only in later observations without order dependence" {
  let report = synthesize([
    { input: ["en"], output: "en", },
    { input: ["zh-Hans-CN"], output: "zh", },
  ])
  assert_true(report.candidates.length() > 0)
  assert_eq(evaluate(report.candidates[0].expression, ["fil-PH"]), "fil")
}

///|
test "shared suffix states retain distinct predictions with bounded work" {
  let report = synthesize([
    { input: ["采访_20261009_take03.wav"], output: "2026-10-09", },
    { input: ["讲座_20261102_take12.wav"], output: "2026-11-02", },
  ])
  assert_true(report.cache_hits > 0)
  assert_true(report.cached_states > 0 && report.cached_states <= 1024)
  assert_true(report.steps < 200000)
  assert_eq(
    evaluate(report.candidates[0].expression, ["纪录片_20240229_take105.wav"]),
    "2024-02-29",
  )
  assert_true(
    attempt(report.candidates[0].expression, ["采访_20260229_take03.wav"])
    is Err(_),
  )
}
