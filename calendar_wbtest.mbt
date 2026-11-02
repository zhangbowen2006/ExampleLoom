///|
test "calendar validates leap centuries" {
  assert_eq(convert_date("20000229", "YYYYMMDD", "YYYY-MM-DD"), "2000-02-29")
  assert_true(
    attempt(DateText(Field(0), "YYYYMMDD", "YYYY-MM-DD"), ["19000229"])
    is Err(_),
  )
  assert_true(
    attempt(DateText(Field(0), "YYYYMMDD", "YYYY-MM-DD"), ["20260229"])
    is Err(_),
  )
}

///|
test "day and month require a declared order" {
  assert_eq(
    convert_date("03/04/2026", "DD/MM/YYYY", "YYYY-MM-DD"),
    "2026-04-03",
  )
  assert_eq(
    convert_date("03/04/2026", "MM/DD/YYYY", "YYYY-MM-DD"),
    "2026-03-04",
  )
  assert_true(
    attempt(DateText(Field(0), "auto", "YYYY-MM-DD"), ["03/04/2026"]) is Err(_),
  )
}

///|
test "date roundtrips every supported format" {
  for format in date_formats() {
    let converted = convert_date("2024-02-29", "YYYY-MM-DD", format)
    assert_eq(convert_date(converted, format, "YYYY-MM-DD"), "2024-02-29")
  }
}

///|
test "invalid dates fail instead of normalizing" {
  for
    input in [
      "2026-13-01", "2026-00-10", "2026-04-31", "0000-01-01", "2026-1-01", "2026/01/01",
      "abcd-01-01",
    ] {
    assert_true(
      attempt(DateText(Field(0), "YYYY-MM-DD", "YYYYMMDD"), [input]) is Err(_),
    )
  }
}
