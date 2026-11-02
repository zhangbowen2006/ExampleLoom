///|
test "CSV quotes, CRLF, multiline and empty trailing cell roundtrip" {
  let s = "id,note,empty\r\n0012,\"a,\"\"b\"\"\nnext\",\r\n"
  let table = parse_csv(s)
  assert_eq(table.rows[0], ["0012", "a,\"b\"\nnext", ""])
  assert_true(parse_csv(render_csv(table, spreadsheet_safe=false)) == table)
}

///|
test "CSV unicode and BOM" {
  let bom = (65279).unsafe_to_char().to_string()
  assert_eq(parse_csv(bom + "姓名,标记\n小张,😀\n").rows[0], [
    "小张", "😀",
  ])
}

///|
test "CSV malformed inputs are rejected" {
  for
    source in [
      "", "a,a\n1,2", "a,b\n1", "a\n\"bad", "a\na\"b", "a\n\"a\"tail", ",b\n1,2",
    ] {
    let failed = try {
      ignore(parse_csv(source))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "CSV formula escaping is explicit and headers are protected" {
  let table = { columns: ["=header"], rows: [["  +SUM(1)"], ["0012"]], }
  assert_true(render_csv(table).has_prefix("'=header"))
  assert_eq(parse_csv(render_csv(table)).rows[0][0], "'  +SUM(1)")
  assert_true(parse_csv(render_csv(table, spreadsheet_safe=false)) == table)
}

///|
test "JSONL retains IDs and canonicalizes field order" {
  let table = parse_jsonl(
    "{\"z\":\"0012\",\"a\":null}\n{\"a\":\"甲\",\"z\":\"0088\"}",
  )
  assert_eq(table.columns, ["a", "z"])
  assert_eq(table.rows, [["", "0012"], ["甲", "0088"]])
}

///|
test "JSONL rejects numeric fields, duplicates, missing and nested values" {
  for
    source in [
      "{\"a\":1}", "{\"a\":\"x\",\"a\":\"y\"}", "{\"a\":\"x\"}\n{\"b\":\"y\"}", "{\"a\":{}}",
    ] {
    let failed = try {
      ignore(parse_jsonl(source))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}
