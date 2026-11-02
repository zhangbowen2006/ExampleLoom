///|
fn main {
  let tasks : Array[(String, Array[@loom.Example], Array[String])] = [
    (
      "product model",
      [
        { input: ["ACME-0012-red-L"], output: "0012", },
        { input: ["ACME-0081-blue-M"], output: "0081", },
      ],
      ["ACME-123456-green-XL"],
    ),
    (
      "event label",
      [
        { input: ["陈雨", "A1"], output: "A1 / 陈雨", },
        { input: ["王琪", "B12"], output: "B12 / 王琪", },
      ],
      ["赵晨", "C20"],
    ),
    (
      "media date",
      [
        { input: ["采访_20261009_take03.wav"], output: "2026-10-09", },
        { input: ["讲座_20261102_take12.wav"], output: "2026-11-02", },
      ],
      ["纪录片_20240229_take105.wav"],
    ),
  ]
  try {
    for task in tasks {
      let (name, examples, heldout) = task
      let report = @loom.synthesize(examples)
      if report.candidates.is_empty() {
        abort("demo did not find a program")
      }
      let expr = report.candidates[0].expression
      println(name + ": " + @loom.explain(expr))
      println("  held-out output: " + @loom.evaluate(expr, heldout))
      println("  search status: " + report.status)
    }
  } catch {
    @loom.LoomError(message) => abort(message)
  }
}
