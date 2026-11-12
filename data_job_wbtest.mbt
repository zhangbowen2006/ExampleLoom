///|
test "named multi-source job composes union join and exact decimal aggregation" {
  let job : DataJob = {
    sources: ["jan", "feb", "catalog"],
    stages: [
      {
        name: "orders",
        operation: ConcatSources(["jan", "feb"], default_union_spec()),
      },
      {
        name: "enriched",
        operation: JoinSources(
          "orders",
          "catalog",
          default_join_spec(["sku"], ["sku"]),
        ),
      },
      {
        name: "total",
        operation: TransformSource("enriched", {
          columns: ["sku", "amount", "_source", "category", "_match"],
          steps: [
            Aggregate(["category"], [
              { name: "total", metric: SumDecimal("amount"), },
            ]),
          ],
        }),
      },
    ],
    output: "total",
  }
  let sources : Array[NamedTable] = [
    {
      name: "jan",
      table: { columns: ["sku", "amount"], rows: [["a", "0.1"]], },
    },
    {
      name: "feb",
      table: { columns: ["amount", "sku"], rows: [["0.2", "a"]], },
    },
    {
      name: "catalog",
      table: { columns: ["sku", "category"], rows: [["a", "food"]], },
    },
  ]
  let saved = data_job_from_json(data_job_to_json(job))
  assert_eq(run_data_job(saved, sources), {
    columns: ["category", "total"],
    rows: [["food", "0.3"]],
  })
  assert_eq(sources[1].table.columns, ["amount", "sku"])
  let duplicate = {
    ..job,
    stages: [
      {
        name: "orders",
        operation: ConcatSources(["jan", "jan"], default_union_spec()),
      },
    ],
    output: "orders",
  }
  assert_true(
    try {
      ignore(data_job_to_json(duplicate))
      false
    } catch {
      LoomError(_) => true
    },
  )
  let forward = {
    ..job,
    stages: [
      {
        name: "total",
        operation: TransformSource("future", { columns: ["sku"], steps: [], }),
      },
    ],
  }
  assert_true(
    try {
      ignore(data_job_to_json(forward))
      false
    } catch {
      LoomError(_) => true
    },
  )
  assert_true(
    try {
      ignore(run_data_job(saved, [sources[0], sources[1]]))
      false
    } catch {
      LoomError(_) => true
    },
  )
}

///|
test "job preserves first-step schema options and checks every intermediate" {
  let source : NamedTable = {
    name: "data",
    table: { columns: ["a", "b"], rows: [["1", "2"]], },
  }
  let preserved : DataJob = {
    sources: ["data"],
    stages: [
      {
        name: "out",
        operation: TransformSource("data", {
          columns: ["a"],
          steps: [PreserveExtraColumns, Select(["b"], ["extra"])],
        }),
      },
    ],
    output: "out",
  }
  assert_eq(run_data_job(preserved, [source]), {
    columns: ["extra"],
    rows: [["2"]],
  })
  let rules : Array[LayoutRule] = [
    {
      name: "old",
      when: Empty(Literal("")),
      recipe: {
        columns: ["old"],
        outputs: [{ name: "new", expression: Field(0), }],
      },
    },
  ]
  let normalized : DataJob = {
    sources: ["data"],
    stages: [
      {
        name: "out",
        operation: TransformSource("data", {
          columns: ["historic"],
          steps: [NormalizeLayouts(rules), Select(["new"], ["result"])],
        }),
      },
    ],
    output: "out",
  }
  assert_eq(
    run_data_job(normalized, [
      { name: "data", table: { columns: ["old"], rows: [["001"]], }, },
    ]),
    { columns: ["result"], rows: [["001"]], },
  )
  let large = Array::make(3000, "a").join("")
  let expanded : NamedTable = {
    name: "data",
    table: {
      columns: ["a", "b", "c", "d"],
      rows: Array::make(500, [large, "1", "2", "3"]),
    },
  }
  let job : DataJob = {
    sources: ["data"],
    stages: [
      {
        name: "out",
        operation: TransformSource("data", {
          columns: expanded.table.columns,
          steps: [
            Unpivot(["a"], ["b", "c", "d"], "key", "value"),
            Select(["value"], ["value"]),
          ],
        }),
      },
    ],
    output: "out",
  }
  assert_true(
    try {
      ignore(run_data_job(job, [expanded]))
      false
    } catch {
      LoomError(s) => s.contains("2000000")
    },
  )
}

///|
test "job bounds all resident tables rather than multiplying limits per stage" {
  let source : NamedTable = {
    name: "input",
    table: { columns: ["a", "b"], rows: Array::make(12000, ["x", "y"]), },
  }
  let stages = Array::makei(8, i => DataStage::{
    name: "s\{i}",
    operation: TransformSource(if i == 0 { "input" } else { "s\{i-1}" }, {
      columns: ["a", "b"],
      steps: [],
    }),
  })
  assert_true(
    try {
      ignore(
        run_data_job({ sources: ["input"], stages, output: "s7", }, [source]),
      )
      false
    } catch {
      LoomError(s) => s.contains("resident tables") && s.contains("200000")
    },
  )
  assert_eq(source.table.rows[0], ["x", "y"])
}
