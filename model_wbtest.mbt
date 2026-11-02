///|
test "unicode slicing counts scalar values and preserves supplementary chars" {
  assert_eq(
    evaluate(Slice(Field(0), Start(1), End(1)), ["甲😀乙尾"]),
    "😀乙",
  )
}

///|
test "relative and absolute positions express distinct hypotheses" {
  assert_eq(
    evaluate(Slice(Field(0), End(4), End(0)), ["订单-123456"]),
    "3456",
  )
  assert_eq(evaluate(Token(Field(0), "-", -1), ["订单-123456"]), "123456")
}

///|
test "tokens preserve empty cells and repeated delimiters" {
  assert_eq(evaluate(Token(Field(0), "::", 1), ["a::::b"]), "")
  assert_eq(evaluate(Token(Field(0), "::", -1), ["a::::b"]), "b")
}

///|
test "composition handles multiple columns and keeps leading zeros" {
  let e = Concat([Upper(Trim(Field(0))), Literal("/"), Run(Field(1), Digits, 0)])
  assert_eq(evaluate(e, [" xl ", "item-0012"]), "XL/0012")
}

///|
test "ASCII folding leaves Chinese and non-ASCII letters intact" {
  assert_eq(evaluate(Lower(Field(0)), ["AB张É"]), "ab张É")
}

///|
test "invalid selectors return typed errors" {
  let result = attempt(Slice(Field(0), End(5), End(0)), ["abc"])
  assert_true(result is Err(_))
  assert_true(attempt(Field(2), ["abc"]) is Err(_))
  assert_true(attempt(Token(Field(0), "", 0), ["abc"]) is Err(_))
}

///|
test "expression depth is bounded" {
  let mut expr = Field(0)
  for _ in 0..<18 {
    expr = Trim(expr)
  }
  assert_true(attempt(expr, ["abc"]) is Err(_))
}
