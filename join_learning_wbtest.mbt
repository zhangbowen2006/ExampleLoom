///|
test "learn composite join and projection from multiple independently labelled batches" {
  let a : JoinExample = {
    sources: [
      {
        name: "orders",
        table: {
          columns: ["sku", "warehouse", "qty"],
          rows: [["A", "W1", "3"], ["A", "W2", "7"], ["B", "W1", "5"]],
        },
      },
      {
        name: "catalog",
        table: {
          columns: ["sku", "warehouse", "category"],
          rows: [["A", "W1", "food"], ["A", "W2", "book"], ["B", "W1", "tool"]],
        },
      },
    ],
    after: {
      columns: ["sku", "category", "qty"],
      rows: [["A", "food", "3"], ["A", "book", "7"], ["B", "tool", "5"]],
    },
  }
  let b : JoinExample = {
    sources: [
      {
        name: "catalog",
        table: {
          columns: ["category", "warehouse", "sku"],
          rows: [["tool", "W2", "C"], ["art", "W1", "C"], ["other", "W4", "E"]],
        },
      },
      {
        name: "orders",
        table: {
          columns: ["warehouse", "qty", "sku"],
          rows: [["W1", "11", "C"], ["W2", "12", "C"], ["W3", "13", "D"]],
        },
      },
    ],
    after: {
      columns: ["sku", "category", "qty"],
      rows: [["C", "art", "11"], ["C", "tool", "12"], ["D", "", "13"]],
    },
  }
  let result = synthesize_join_jobs([a, b])
  assert_true(!result.candidates.is_empty())
  for job in result.candidates {
    assert_eq(run_data_job(job, a.sources), a.after)
    assert_eq(run_data_job(job, b.sources), b.after)
  }
  let next : Array[NamedTable] = [
    {
      name: "orders",
      table: {
        columns: ["qty", "sku", "warehouse"],
        rows: [["4", "F", "W1"], ["8", "F", "W2"], ["9", "Z", "W3"]],
      },
    },
    {
      name: "catalog",
      table: {
        columns: ["sku", "category", "warehouse"],
        rows: [["F", "music", "W2"], ["F", "paint", "W1"]],
      },
    },
  ]
  assert_eq(
    run_data_job(
      data_job_from_json(data_job_to_json(result.candidates[0])),
      next,
    ),
    {
      columns: ["sku", "category", "qty"],
      rows: [["F", "paint", "4"], ["F", "music", "8"], ["Z", "", "9"]],
    },
  )
}

///|
test "join learning validates input, budget and all demonstrated examples" {
  let a : JoinExample = {
    sources: [
      { name: "a", table: { columns: ["id"], rows: [["1"]], }, },
      { name: "b", table: { columns: ["id", "value"], rows: [["1", "yes"]], }, },
    ],
    after: { columns: ["value"], rows: [["yes"]], },
  }
  let limited = synthesize_join_jobs([a], options={
    ..default_join_search_options(),
    max_evaluations: 1,
  })
  assert_eq(limited.evaluations, 1)
  assert_true(limited.truncated)
  assert_true(
    try {
      ignore(
        synthesize_join_jobs([a], options={
          ..default_join_search_options(),
          max_keys: 3,
        }),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
  assert_true(
    try {
      ignore(
        synthesize_join_jobs([{ ..a, sources: [a.sources[0], a.sources[0]], }]),
      )
      false
    } catch {
      LoomError(_) => true
    },
  )
  let impossible = {
    ..a,
    after: { columns: ["value"], rows: [["not present"]], },
  }
  assert_true(synthesize_join_jobs([a, impossible]).candidates.is_empty())
}

///|
test "learning preflights Cartesian growth without blocking bounded semi joins" {
  let left : Table = { columns: ["id"], rows: Array::make(30, ["k"]), }
  let right : Table = {
    columns: ["id", "v"],
    rows: Array::make(30, ["k", "x"]),
  }
  let spec = {
    ..default_join_spec(["id"], ["id"]),
    relationship: "many_to_many",
    kind: "inner",
  }
  assert_false(join_learning_within_limit(left, right, spec))
  assert_true(
    join_learning_within_limit(left, right, { ..spec, kind: "semi", }),
  )
  let e : JoinExample = {
    sources: [{ name: "a", table: left, }, { name: "b", table: right, }],
    after: { columns: ["id"], rows: [["not-present"]], },
  }
  let r = synthesize_join_jobs([e], options={
    ..default_join_search_options(),
    max_evaluations: 20,
  })
  assert_true(r.truncated)
  assert_eq(r.evaluations, 20)
}
