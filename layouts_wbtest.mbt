///|
fn person_layouts() -> Array[LayoutRule] {
  [
    {
      name: "legacy",
      when: Matches(Field(0), "^([^,]+),([^,]+)$", true),
      recipe: {
        columns: ["legacy"],
        outputs: [
          {
            name: "first",
            expression: Trim(RegexCapture(Field(0), "^([^,]+),([^,]+)$", 2, 0)),
          },
          {
            name: "last",
            expression: Trim(RegexCapture(Field(0), "^([^,]+),([^,]+)$", 1, 0)),
          },
        ],
      },
    },
    {
      name: "separate",
      when: All([Not(Empty(Field(0))), Not(Empty(Field(1)))]),
      recipe: {
        columns: ["first", "last"],
        outputs: [
          { name: "first", expression: Field(0), },
          { name: "last", expression: Field(1), },
        ],
      },
    },
  ]
}

///|
test "input probes expose structural disagreement without creating output labels" {
  let t : Table = { columns: ["c0"], rows: [["A"]], }
  let pipelines : Array[Pipeline] = [
    { columns: t.columns, steps: [], },
    { columns: t.columns, steps: [FlattenRows], },
  ]
  let r = propose_table_input(pipelines, [t])
  guard r.suggestion is Some(s) else { fail("expected a distinguishing input") }
  assert_eq(s.table.rows, [["A"], ["A"]])
  assert_eq(s.groups, [[0], [1]])
  assert_eq(s.score, 2)
  assert_true(r.attempted <= 8)
  assert_true(
    propose_table_input([pipelines[0], pipelines[0]], [t]).suggestion is None,
  )
  s.table.rows[0][0] = "changed"
  assert_eq(t.rows, [["A"]])
}

///|
test "bounded goal retention keeps the cheapest program and structural alternatives" {
  let goals : Array[RankedPipeline] = []
  let seen : Map[String, Bool] = Map([])
  for
    steps in [
      [],
      [Select(["c0"], ["c0"])],
      [FillDown(["c0"])],
      [Deduplicate(["c0"])],
      [FillDown(["c0"]), FillDown(["c0"])],
      [FlattenRows],
      [PackRows(1, false)],
      [Transpose],
    ] {
    ignore(retain_pipeline(goals, seen, { columns: ["c0"], steps, }, 4))
  }
  assert_eq(goals.length(), 4)
  assert_true(goals[0].pipeline.steps.is_empty())
  assert_true(goals.any(g => g.pipeline.steps.any(s => s is FlattenRows)))
  assert_true(goals.any(g => g.pipeline.steps.any(s => s is PackRows(_, _))))
  assert_true(goals.any(g => g.pipeline.steps.any(s => s is Transpose)))
}

///|
test "schema normalization composes with learning on every original training pair" {
  let raw : Array[TableExample] = [
    {
      before: { columns: ["legacy"], rows: [["House,Mia"], ["Park,Ada"]], },
      after: { columns: ["badge"], rows: [["Mia House"], ["Ada Park"]], },
    },
    {
      before: {
        columns: ["last", "first"],
        rows: [["Stone", "Bo"], ["Lee", "Yan"]],
      },
      after: { columns: ["badge"], rows: [["Bo Stone"], ["Yan Lee"]], },
    },
  ]
  let report = synthesize_table_with_layouts(raw, person_layouts())
  assert_true(!report.candidates.is_empty())
  let p = pipeline_from_json(pipeline_to_json(report.candidates[0]))
  for e in raw {
    assert_eq(apply_pipeline(p, e.before), e.after)
  }
  assert_eq(
    apply_pipeline(p, {
      columns: ["first", "legacy", "last"],
      rows: [["", "王,博文", ""], ["Mia", "", "Stone"]],
    }).rows,
    [["博文 王"], ["Mia Stone"]],
  )
  for
    options in [
      TableSearchOptions::{ ..default_table_options(), max_depth: 0, },
      TableSearchOptions::{ ..default_table_options(), max_depth: 1, },
      TableSearchOptions::{ ..default_table_options(), max_evaluations: 1, },
      TableSearchOptions::{ ..default_table_options(), max_states: 1, },
    ] {
    let r = synthesize_table_with_layouts(raw, person_layouts(), options~)
    assert_true(r.truncated && r.candidates.is_empty())
    assert_true(
      r.states <= options.max_states && r.evaluations <= options.max_evaluations,
    )
  }
}

///|
test "a layout-only goal succeeds within one step and one evaluation" {
  let raw : Table = { columns: ["legacy"], rows: [["Family,First"]], }
  let target : Table = {
    columns: ["first", "last"],
    rows: [["First", "Family"]],
  }
  let r = synthesize_table_with_layouts(
    [{ before: raw, after: target, }],
    person_layouts(),
    options={
      max_depth: 1,
      max_states: 1,
      max_evaluations: 1,
      max_candidates: 1,
    },
  )
  assert_eq(r.status, "normalization_checked")
  assert_eq(r.evaluations, 1)
  assert_eq(r.states, 1)
  assert_eq(apply_pipeline(r.candidates[0], raw), target)
}

///|
test "named layouts adapt schemas and route mixed rows without altering inputs" {
  let rules = person_layouts()
  let p : Pipeline = { columns: ["legacy"], steps: [NormalizeLayouts(rules)], }
  let saved = pipeline_from_json(pipeline_to_json(p))
  assert_eq(
    apply_pipeline(saved, { columns: ["legacy"], rows: [["Family, First"]], }).rows,
    [["First", "Family"]],
  )
  assert_eq(
    apply_pipeline(saved, {
      columns: ["last", "first"],
      rows: [["House", "Name"]],
    }).rows,
    [["Name", "House"]],
  )
  let mixed : Table = {
    columns: ["last", "legacy", "first"],
    rows: [["", "王, 博文", ""], ["Family", "", "😀"]],
  }
  assert_eq(apply_pipeline(saved, mixed), {
    columns: ["first", "last"],
    rows: [["博文", "王"], ["😀", "Family"]],
  })
  assert_eq(mixed.rows[0], ["", "王, 博文", ""])
}

///|
test "layout overlap absence predicate errors and invalid declarations fail" {
  let rules = person_layouts()
  for
    t in [
      Table::{
        columns: ["legacy", "first", "last"],
        rows: [["House,Name", "Other", "Family"]],
      },
      Table::{ columns: ["legacy", "first", "last"], rows: [["", "", ""]], },
      Table::{ columns: ["unknown"], rows: [["X"]], },
    ] {
    assert_true(
      try {
        ignore(transform_table(t, [NormalizeLayouts(rules)]))
        false
      } catch {
        LoomError(_) => true
      },
    )
  }
  let invalid : Array[Array[LayoutRule]] = [
    [],
    [rules[0], rules[0]],
    [
      rules[0],
      {
        ..rules[1],
        recipe: {
          ..rules[1].recipe,
          outputs: [{ name: "different", expression: Field(0), }],
        },
      },
    ],
    [{ ..rules[0], when: Empty(Field(9)), }],
  ]
  for r in invalid {
    assert_true(
      try {
        ignore(table_step_to_json(NormalizeLayouts(r)))
        false
      } catch {
        LoomError(_) => true
      },
    )
  }
  let bad : LayoutRule = {
    name: "error",
    when: Matches(RegexCapture(Field(0), "^z$", 0, 0), "x", true),
    recipe: rules[0].recipe,
  }
  assert_true(
    try {
      ignore(
        transform_table({ columns: ["legacy"], rows: [["a"]], }, [
          NormalizeLayouts([bad]),
        ]),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
  let misplaced : Pipeline = {
    columns: ["legacy"],
    steps: [PreserveExtraColumns, NormalizeLayouts(rules)],
  }
  assert_true(
    try {
      ignore(pipeline_to_json(misplaced))
      false
    } catch {
      LoomError(_) => true
    },
  )
}

///|
test "layout evaluation is bounded before processing and empty tables have canonical schema" {
  let r = person_layouts()[0]
  let many = Array::makei(13, i => LayoutRule::{ ..r, name: "rule\{i}", })
  let large : Table = {
    columns: ["legacy"],
    rows: Array::make(20000, ["House,Name"]),
  }
  assert_true(
    try {
      ignore(transform_table(large, [NormalizeLayouts(many)]))
      false
    } catch {
      LoomError(message) => {
        assert_true(message.contains("200000"))
        true
      }
    },
  )
  assert_eq(
    transform_table({ columns: ["legacy"], rows: [], }, [NormalizeLayouts([r])]),
    { columns: ["first", "last"], rows: [], },
  )
}
