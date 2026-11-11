///|
test "update columns preserves extra fields and evaluates all edits simultaneously" {
  let recipe : Recipe = {
    columns: ["a", "b"],
    outputs: [
      { name: "a", expression: Field(1), },
      { name: "b", expression: Field(0), },
    ],
  }
  let table : Table = {
    columns: ["b", "extra", "a"],
    rows: [["B", "unchanged", "A"], ["D", "", "C"]],
  }
  let step = table_step_from_json(table_step_to_json(UpdateColumns(recipe)))
  assert_eq(transform_table(table, [step]), {
    columns: ["b", "extra", "a"],
    rows: [["A", "unchanged", "B"], ["C", "", "D"]],
  })
  let missing = Some(
    transform_table({ columns: ["a"], rows: [["x"]], }, [step]),
  ) catch {
    _ => None
  }
  assert_true(missing is None)
  let failure = UpdateColumns({
    columns: ["a"],
    outputs: [{ name: "a", expression: Token(Field(0), ":", 1), }],
  })
  let failed = Some(transform_table(table, [failure])) catch { _ => None }
  assert_true(failed is None)
}

///|
test "learning keeps variable-width fields after marker-based record segmentation" {
  let before : Table = {
    columns: ["line"],
    rows: [["*Alpha"], ["Main Street"], ["North"]],
  }
  let after : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["Alpha", "Main Street", "North"]],
  }
  let r = synthesize_table([{ before, after, }])
  let newer : Table = {
    columns: ["line"],
    rows: [
      ["*Beta"],
      ["Second Road"],
      ["*Gamma"],
      ["Third Road"],
      ["West"],
      ["Phone"],
    ],
  }
  let expected : Table = {
    columns: ["c0", "c1", "c2", "c3"],
    rows: [
      ["Beta", "Second Road", "", ""],
      ["Gamma", "Third Road", "West", "Phone"],
    ],
  }
  assert_true(!r.candidates.is_empty())
  assert_eq(
    apply_pipeline(pipeline_from_json(pipeline_to_json(r.candidates[0])), newer),
    expected,
  )
}

///|
test "learned field updates rebind only the columns used by the expression" {
  let columns = ["id", "left", "right"]
  let learned : Recipe = {
    columns,
    outputs: [
      { name: "id", expression: Lower(Field(0)), },
      { name: "left", expression: Field(1), },
      { name: "right", expression: Field(2), },
    ],
  }
  guard update_witness(learned, columns) is Some(compact) else {
    abort("expected update witness")
  }
  let step = UpdateColumns(compact)
  let newer : Table = {
    columns: ["right", "id", "new"],
    rows: [["3", "C", "keep"]],
  }
  assert_eq(transform_table(newer, [step]), {
    columns: ["right", "id", "new"],
    rows: [["3", "c", "keep"]],
  })
}

///|
test "compacted conditional retains cross-column references after reordering" {
  let columns = ["unused", "id", "category"]
  let learned : Recipe = {
    columns,
    outputs: [
      { name: "unused", expression: Field(0), },
      {
        name: "id",
        expression: If(
          Matches(Field(2), "(?rx)(?i:vip)", true),
          Concat([Field(2), Literal(":"), Field(1)]),
          Lower(Field(1)),
        ),
      },
      { name: "category", expression: Field(2), },
    ],
  }
  guard update_witness(learned, columns) is Some(compact) else {
    abort("expected update witness")
  }
  assert_eq(compact.columns, ["category", "id"])
  let newer : Table = {
    columns: ["category", "extra", "id"],
    rows: [["VIP", "preserve", "007"], ["normal", "other", "ABC"]],
  }
  assert_eq(transform_table(newer, [UpdateColumns(compact)]).rows, [
    ["VIP", "preserve", "VIP:007"],
    ["normal", "other", "abc"],
  ])
}

///|
test "header context and dynamic detail levels form a reusable table" {
  let before : Table = {
    columns: ["label", "value"],
    rows: [
      ["Region: North Coast", ""],
      ["", ""],
      ["2024", "10"],
      ["2025", "20"],
    ],
  }
  let after : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["", "2024", "2025"], ["North Coast", "10", "20"]],
  }
  let result = synthesize_table([{ before, after, }])
  assert_true(!result.candidates.is_empty())
  let newer : Table = {
    columns: ["value", "label"],
    rows: [
      ["", "Region: East Bay"],
      ["", ""],
      ["3", "2024"],
      ["4", "2025"],
      ["5", "2026"],
      ["", ""],
      ["", "Region: West Ridge"],
      ["", ""],
      ["-2", "2024"],
      ["6", "2025"],
      ["8", "2026"],
    ],
  }
  let expected : Table = {
    columns: ["c0", "c1", "c2", "c3"],
    rows: [
      ["", "2024", "2025", "2026"],
      ["East Bay", "3", "4", "5"],
      ["West Ridge", "-2", "6", "8"],
    ],
  }
  let selected = pipeline_from_json(pipeline_to_json(result.candidates[0]))
  assert_eq(apply_pipeline(selected, newer), expected)
}

///|
test "header witness validates all supplied training tables" {
  let a : Table = {
    columns: ["label", "value"],
    rows: [["Region: North", ""], ["2024", "1"], ["2025", "2"]],
  }
  let b : Table = {
    columns: a.columns,
    rows: [["District - South", ""], ["2024", "3"], ["2025", "4"]],
  }
  let x : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["", "2024", "2025"], ["North", "1", "2"]],
  }
  let y : Table = {
    columns: x.columns,
    rows: [["", "2024", "2025"], ["South", "3", "4"]],
  }
  let result = synthesize_table([
    { before: a, after: x, },
    { before: b, after: y, },
  ])
  for candidate in result.candidates {
    assert_eq(apply_pipeline(candidate, a), x)
    assert_eq(apply_pipeline(candidate, b), y)
  }
}

///|
test "learn fill-down and split before a dynamic pivot of labelled details" {
  let before : Table = {
    columns: ["name", "detail"],
    rows: [
      ["Directory", ""],
      ["Name", "Contact"],
      ["Alice", "phone:123"],
      ["", "mail:alice"],
    ],
  }
  let after : Table = {
    columns: ["c0", "c1", "c2"],
    rows: [["", "phone", "mail"], ["Alice", "123", "alice"]],
  }
  let result = synthesize_table([{ before, after, }])
  assert_true(!result.candidates.is_empty())
  let selected = pipeline_from_json(pipeline_to_json(result.candidates[0]))
  let newer : Table = {
    columns: ["detail", "name"],
    rows: [
      ["", "Directory"],
      ["Contact", "Name"],
      ["phone:456", "Bob"],
      ["mail:bob", ""],
      ["", ""],
      ["phone:789", "Carol"],
      ["chat:carol", ""],
      ["mail:carol", ""],
    ],
  }
  assert_eq(apply_pipeline(selected, newer), {
    columns: ["c0", "c1", "c2", "c3"],
    rows: [
      ["", "phone", "mail", "chat"],
      ["Bob", "456", "bob", ""],
      ["Carol", "789", "carol", "carol"],
    ],
  })
  let duplicate : Table = {
    columns: ["name", "detail"],
    rows: [["Alice", "phone:1"], ["", "phone:2"]],
  }
  let failed = Some(apply_pipeline(selected, duplicate)) catch { _ => None }
  assert_true(failed is None)
}
