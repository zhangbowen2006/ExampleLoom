///|
test "learn a whole-cell regex replacement with reordered variable groups and a literal dollar" {
  let examples : Array[Example] = [
    { input: ["AB-001/XY"], output: "XY:$001/AB", },
    { input: ["L-82/KLM"], output: "KLM:$82/L", },
    { input: ["XYZ-7/QR"], output: "QR:$7/XYZ", },
  ]
  let expr = synthesize(examples, branch_depth=0).candidates[0].expression
  assert_true(expr is RegexReplace(_, _, _))
  assert_eq(
    evaluate(expression_from_json(expression_to_json(expr)), ["PQR-00097/Q"]),
    "Q:$00097/PQR",
  )
  assert_eq(evaluate(expr, ["invalid"]), "invalid")
}

///|
test "regex hint learns repeated Unicode captures by example" {
  let r = synthesize(
    [
      { input: ["甲·蓝"], output: "蓝甲蓝", },
      { input: ["乙乙·绿"], output: "绿乙乙绿", },
    ],
    patterns=["([^·]+)·([^·]+)"],
  )
  assert_true(r.candidates[0].expression is RegexReplace(_, _, _))
  assert_eq(
    evaluate(r.candidates[0].expression, ["丁·灯火"]),
    "灯火丁灯火",
  )
}

///|
test "class ending in a colon does not bypass numeric repeat limits" {
  assert_true(
    try {
      regex_complexity("[:]a{800}")
      false
    } catch {
      _ => true
    },
  )
  assert_true(regex_test("42:", "[[:digit:]]{2}[:]", true))
}

///|
test "replacement rejects a backreference expansion and counts supplementary characters" {
  let source = "ab".repeat(2048)
  assert_true(
    attempt(RegexReplace(Field(0), "(.+)", "$1".repeat(32)), [source]) is Err(_),
  )
  assert_eq(
    evaluate(RegexReplace(Field(0), "X", "😀"), ["X" + "a".repeat(65534)]).length(),
    65536,
  )
  assert_true(
    attempt(RegexReplace(Field(0), "X", "😀"), ["X" + "a".repeat(65535)])
    is Err(_),
  )
}

///|
test "learn a shape branch after expanding a delimited column using default table search" {
  let before : Table = {
    columns: ["raw", "tag"],
    rows: [
      ["A17", "red;cyan"],
      ["B839", "teal"],
      ["405-xy", "olive"],
      ["71-z", "blue;gold"],
    ],
  }
  let after : Table = {
    columns: ["kind", "tag"],
    rows: [
      ["IN/17", "red"],
      ["IN/17", "cyan"],
      ["IN/839", "teal"],
      ["OUT/405", "olive"],
      ["OUT/71", "blue"],
      ["OUT/71", "gold"],
    ],
  }
  let report = synthesize_table([{ before, after, }])
  assert_true(!report.candidates.is_empty())
  let learned = pipeline_from_json(pipeline_to_json(report.candidates[0]))
  assert_true(learned.steps is [Explode(_, _), MapRows(_)])
  let next : Table = {
    columns: ["tag", "raw"],
    rows: [["alpha;beta", "ZZ9530"], ["k", "8042-NEW"]],
  }
  assert_eq(apply_pipeline(learned, next).rows, [
    ["IN/9530", "alpha"],
    ["IN/9530", "beta"],
    ["OUT/8042", "k"],
  ])
}

///|
test "group measures preserve key order and exact decimal arithmetic across backends" {
  let step = Aggregate(["dept"], [
    { name: "n", metric: RowCount, },
    { name: "net", metric: SumInt64("cents"), },
    { name: "lo", metric: MinInt64("cents"), },
    { name: "hi", metric: MaxInt64("cents"), },
  ])
  let t : Table = {
    columns: ["cents", "dept"],
    rows: [["+09007199254740993", "B"], ["-5", "A"], ["-12", "B"], ["10", "A"]],
  }
  let actual = transform_table(t, [
    table_step_from_json(table_step_to_json(step)),
  ])
  assert_eq(actual.rows, [
    ["B", "2", "9007199254740981", "-12", "9007199254740993"],
    ["A", "2", "5", "-5", "10"],
  ])
  assert_eq(transform_table({ ..t, rows: [], }, [step]).rows, [])
  assert_eq(
    transform_table({ ..t, rows: [], }, [
      Aggregate([], [
        { name: "n", metric: RowCount, },
        { name: "sum", metric: SumInt64("cents"), },
      ]),
    ]).rows,
    [["0", ""]],
  )
}

///|
test "group sum rejects malformed input and intermediate overflow in both directions" {
  let sum = Aggregate([], [{ name: "n", metric: SumInt64("v"), }])
  for
    cells in [
      ["9223372036854775807", "1"],
      ["-9223372036854775808", "-1"],
      ["9223372036854775808"],
      ["1.2"],
      [""],
      [" 3"],
      ["0x20"],
      ["1_2"],
    ] {
    let t : Table = { columns: ["v"], rows: cells.map(x => [x]), }
    assert_true(
      try {
        ignore(transform_table(t, [sum]))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        table_step_from_json(
          @json.parse("[\"aggregate\",[\"a\"],[[\"a\",\"count\"]]]"),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "learn count and sum together from two tables including a new group on replay" {
  let input : Table = {
    columns: ["amount", "region"],
    rows: [["12", "N"], ["3", "S"], ["-4", "N"]],
  }
  let target : Table = {
    columns: ["region", "orders", "net"],
    rows: [["N", "2", "8"], ["S", "1", "3"]],
  }
  let other : Table = { ..input, rows: [["8", "E"], ["9", "E"]], }
  let other_target : Table = { ..target, rows: [["E", "2", "17"]], }
  let r = synthesize_table(
    [{ before: input, after: target, }, { before: other, after: other_target, }],
    options={ ..default_table_options(), max_depth: 1, },
  )
  assert_true(
    !r.candidates.is_empty() && r.candidates[0].steps is [Aggregate(_, _)],
  )
  let next : Table = {
    ..input,
    rows: [["9", "X"], ["8", "Y"], ["-3", "Y"], ["2", "X"]],
  }
  assert_eq(apply_pipeline(r.candidates[0], next).rows, [
    ["X", "2", "11"],
    ["Y", "2", "5"],
  ])
}
