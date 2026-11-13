///|
test "learn join filter aggregate and replay a new batch with invalid excluded amounts" {
  let a : JoinExample = {
    sources: [
      {
        name: "orders",
        table: parse_csv(
          "sku,status,amount\nA,paid,100\nA,pending,900\nA,paid,200\nB,paid,125\nB,canceled,800\n",
        ),
      },
      { name: "catalog", table: parse_csv("sku,category\nA,food\nB,book\n"), },
    ],
    after: parse_csv("category,total\nfood,300\nbook,125\n"),
  }
  let b : JoinExample = {
    sources: [
      {
        name: "orders",
        table: parse_csv(
          "amount,sku,status\n55,C,paid\n99,C,pending\n25,C,paid\n13,D,paid\n88,D,canceled\n",
        ),
      },
      { name: "catalog", table: parse_csv("category,sku\ntool,C\nart,D\n"), },
    ],
    after: parse_csv("category,total\ntool,80\nart,13\n"),
  }
  let learned = synthesize_join_jobs([a, b])
  assert_true(!learned.candidates.is_empty())
  assert_true(learned.filter_evaluations > 0)
  assert_true(learned.filter_evaluations <= 2048)
  for job in learned.candidates {
    assert_eq(run_data_job(job, a.sources), a.after)
    assert_eq(run_data_job(job, b.sources), b.after)
  }
  let job = data_job_from_json(data_job_to_json(learned.candidates[0]))
  match job.stages[1].operation {
    TransformSource(_, pipeline) => {
      assert_eq(pipeline.steps.length(), 2)
      assert_true(pipeline.steps[0] is Filter(_))
      assert_true(pipeline.steps[1] is Aggregate(_, _))
    }
    _ => fail("expected a reusable filter and aggregate pipeline")
  }
  let next : Array[NamedTable] = [
    {
      name: "orders",
      table: parse_csv(
        "sku,status,amount\nE,paid,2\nE,pending,invalid\nE,paid,3\nF,paid,-20\nF,canceled,invalid\n",
      ),
    },
    { name: "catalog", table: parse_csv("sku,category\nE,toy\nF,media\n"), },
  ]
  assert_eq(
    run_data_job(job, next),
    parse_csv("category,total\ntoy,5\nmedia,-20\n"),
  )
}

///|
test "filter learning reports its local and shared search limits" {
  let t : Table = {
    columns: Array::makei(6, i => "c\{i}"),
    rows: Array::makei(9, i => Array::makei(6, j => "\{(i + j) % 3}")),
  }
  let target : Table = { columns: ["total"], rows: [["999999"]], }
  let local_work : JoinWork = { bounded_skips: 0, filter_evaluations: 0, }
  assert_true(join_filtered_aggregate([t], [target], local_work) is None)
  assert_eq(local_work.filter_evaluations, 32)
  assert_true(local_work.bounded_skips > 0)
  let shared : JoinWork = { bounded_skips: 0, filter_evaluations: 2048, }
  assert_true(join_filtered_aggregate([t], [target], shared) is None)
  assert_eq(shared.filter_evaluations, 2048)
  assert_true(shared.bounded_skips > 0)
  let high : Table = {
    columns: ["code"],
    rows: Array::makei(9, i => ["code-\{i}"]),
  }
  let skipped : JoinWork = { bounded_skips: 0, filter_evaluations: 0, }
  assert_true(join_filtered_aggregate([high], [target], skipped) is None)
  assert_eq(skipped.filter_evaluations, 0)
  assert_true(skipped.bounded_skips > 0)
}

///|
test "an empty first expected batch does not block filter aggregate learning" {
  let a = parse_csv("status,category,amount\npending,A,9\n")
  let b = parse_csv(
    "status,category,amount\npaid,B,2\npaid,B,3\npending,B,50\n",
  )
  let targets = [
    parse_csv("category,total\n"),
    parse_csv("category,total\nB,5\n"),
  ]
  let work : JoinWork = { bounded_skips: 0, filter_evaluations: 0, }
  guard join_filtered_aggregate([a, b], targets, work) is Some(steps) else {
    fail("expected learning from the second batch with nonempty target")
  }
  assert_eq(transform_table(a, steps), targets[0])
  assert_eq(transform_table(b, steps), targets[1])
}
