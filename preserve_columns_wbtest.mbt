///|
test "preserve extra input columns binds declared schema first and updates atomically" {
  let recipe : Recipe = {
    columns: ["code"],
    outputs: [{ name: "code", expression: Upper(Trim(Field(0))), }],
  }
  let p : Pipeline = {
    columns: ["code", "qty"],
    steps: [PreserveExtraColumns, UpdateColumns(recipe)],
  }
  let table : Table = {
    columns: ["warehouse", "qty", "code", "owner"],
    rows: [["A", "12", " ab-7 ", "team1"], ["B", "2", " cd-8 ", "team2"]],
  }
  let saved = pipeline_from_json(pipeline_to_json(p))
  assert_eq(apply_pipeline(saved, table), {
    columns: ["code", "qty", "warehouse", "owner"],
    rows: [["AB-7", "12", "A", "team1"], ["CD-8", "2", "B", "team2"]],
  })
  let old : Pipeline = { ..p, steps: [UpdateColumns(recipe)], }
  assert_eq(apply_pipeline(old, table).columns, ["code", "qty"])
}

///|
test "extra-column marker is explicit and only valid as the first step" {
  let p : Pipeline = {
    columns: ["id"],
    steps: [PreserveExtraColumns, Select(["id"], ["id"])],
  }
  let input : Table = { columns: ["id", "extra"], rows: [["1", "keep"]], }
  assert_eq(apply_pipeline(p, input).columns, ["id"])
  let missing : Table = { columns: ["other"], rows: [["x"]], }
  let no_required = Some(apply_pipeline(p, missing)) catch { _ => None }
  assert_true(no_required is None)
  let invalid : Pipeline = {
    columns: ["id"],
    steps: [DropRows(0), PreserveExtraColumns],
  }
  let misplaced = Some(pipeline_to_json(invalid)) catch { _ => None }
  assert_true(misplaced is None)
  let duplicate : Pipeline = {
    columns: ["id"],
    steps: [PreserveExtraColumns, PreserveExtraColumns],
  }
  let duplicated = Some(pipeline_to_json(duplicate)) catch { _ => None }
  assert_true(duplicated is None)
}
