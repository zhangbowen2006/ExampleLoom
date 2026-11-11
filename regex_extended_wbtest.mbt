///|
test "extended regex supports shorthand Unicode named groups flags and backreferences" {
  assert_true(regex_test("ABC-007", "(?rx)(?i:[a-z]+)-\\d+", true))
  assert_true(regex_test("甲😀", "(?rx)\\p{L}.", true))
  assert_eq(
    regex_capture("code=42", "(?rx)(?<key>\\w+)=(?<value>\\d+)", 2, 0),
    "42",
  )
  assert_eq(
    regex_replace(
      "id=42 n=8", "(?rx)(?<key>\\w+)=(?<value>\\d+)", "${value}:${key}",
    ),
    "42:id 8:n",
  )
  assert_true(regex_test("echo echo", "(?rx)(\\w+) \\1", true))
  assert_true(!regex_test("echo else", "(?rx)(?<x>\\w+) \\k<x>", true))
  assert_true(regex_test("a", "(?rx)(a*)\\1", true) == false)
  assert_true(regex_test("", "(?rx)(a*)\\1", true))
  assert_true(regex_test("aF", "(?rx)[\\x41-\\x61]\\x46", true))
  assert_true(regex_test("က", "(?rx)\\u{1000}", true))
  assert_true(regex_test("😀word😀", "(?rx)\\bword\\b", false))
  assert_true(regex_test("\u{0}", "(?rx)[\\0]", true))
  assert_true(
    attempt(RegexCapture(Field(0), "(?rx)(?mi:(a)\\1)", 0, 0), ["aa"]) is Err(_),
  )
}

///|
test "lookaround keeps absolute context during global replacement and scalar lookbehind" {
  assert_eq(
    regex_replace("ID12 USD34 ID56", "(?rx)(?<=ID)\\d+(?!\\d)", "#"),
    "ID# USD34 ID#",
  )
  assert_eq(
    regex_replace("甲1 😀2 甲3", "(?rx)(?<=甲|😀)\\d", "#"),
    "甲# 😀# 甲#",
  )
  assert_eq(regex_replace("a1 b2 a3", "(?rx)(?<!a)\\d", "#"), "a1 b# a3")
  assert_eq(regex_capture("id=42; x=9", "(?rx)(?=(\\d+);)\\d+", 1, 0), "42")
  assert_eq(regex_replace("甲😀", "(?rx)(?=.)", "-"), "-甲-😀")
  assert_true(!regex_test("ab", "(?rx)a|b", true))
  assert_true(!regex_test("a\n", "(?rx)a", true))
  assert_true(regex_test("a\nb", "(?rx)(?m:^b$)", false))
  assert_true(regex_test("a\nb", "(?rx)(?s:a.b)", true))
}

///|
test "extended regex rejects invalid syntax and bounds work as errors" {
  assert_true(
    attempt(RegexCapture(Field(0), "(?rx)(a|(b))*", 2, 0), ["aba"]) is Err(_),
  )
  assert_true(
    attempt(RegexCapture(Field(0), "(?rx)(?<=a+)b", 0, 0), ["ab"]) is Err(_),
  )
  assert_true(
    attempt(RegexReplace(Field(0), "(?rx)(?<n>\\d+)", "${missing}"), ["none"])
    is Err(_),
  )
  assert_true(
    attempt(RegexCapture(Field(0), "(?rx)\\k<missing>", 0, 0), ["a"]) is Err(_),
  )
  let mut limited = false
  let exhausted = compiled_regex("(?rx)^(a|aa)+\\1b$").execute(
    "a".repeat(30)[:],
  ) catch {
    LoomError(message) => {
      assert_true(message.contains("instruction"))
      limited = true
      None
    }
  }
  assert_true(limited)
  assert_true(exhausted is None)
}

///|
test "extended regex is portable through conditional recipes and PBE hints" {
  let expression = If(
    Matches(Field(0), "(?rx)ID\\d+", true),
    RegexReplace(Field(0), "(?rx)(?<=ID)\\d+", "#"),
    Literal("other"),
  )
  assert_eq(
    evaluate(expression_from_json(expression_to_json(expression)), ["ID87"]),
    "ID#",
  )
  assert_eq(evaluate(expression, ["bad"]), "other")
  let result = synthesize(
    [
      { input: ["ref=003;note=8"], output: "003", },
      { input: ["ref=1047;note=99"], output: "1047", },
    ],
    patterns=["(?rx)(?<=ref=)(\\d+)(?=;)"],
  )
  assert_true(
    result.candidates.any(c => {
      evaluate(c.expression, ["ref=80001;note=77"]) == "80001"
    }),
  )
}
