///|
pub(all) struct TableProbe {
  table : Table
  source_index : Int32
  mutation : String
  score : Int32
  groups : Array[Array[Int32]]
}

///|
pub(all) struct TableProbeReport {
  suggestion : TableProbe?
  attempted : Int32
  skipped : Int32
}

///|
/// Suggest an input, never an output label. Only known training inputs are
/// repeated, shortened or reversed; at most eight complete probes are tried.
pub fn propose_table_input(
  candidates : Array[Pipeline],
  inputs : Array[Table],
) -> TableProbeReport raise LoomError {
  if candidates.is_empty() ||
    candidates.length() > 8 ||
    inputs.is_empty() ||
    inputs.length() > 8 {
    raise LoomError("probe requires 1..8 pipelines and 1..8 input tables")
  }
  for p in candidates {
    ignore(pipeline_to_json(p))
  }
  for t in inputs {
    validate_table(t)
    check_comparison_size(t)
    if t.rows.is_empty() || t.rows.length() > 128 || t.columns.length() > 16 {
      raise LoomError("probe source requires 1..128 rows and 1..16 columns")
    }
  }
  let mut best : TableProbe? = None
  let mut attempted = 0
  let mut skipped = 0
  let seen : Map[String, Bool] = Map([])
  for source_index, t in inputs {
    let mutations = [
      "duplicate_rows", "reverse_rows", "drop_first", "drop_last", "first_row",
    ]
    let probes : Array[Array[Array[String]]] = [t.rows + t.rows, t.rows.rev()]
    if t.rows.length() > 1 {
      probes.push(t.rows[1:].to_owned())
      probes.push(t.rows[:t.rows.length() - 1].to_owned())
      probes.push([t.rows[0]])
    }
    for mutation_index, rows in probes {
      if attempted >= 8 {
        break
      }
      let table : Table = { columns: t.columns, rows, }
      let key = table_json(table).stringify()
      if seen.contains(key) {
        continue
      }
      seen[key] = true
      attempted += 1
      let comparison = Some(compare_table_candidates(candidates, table)) catch {
        LoomError(_) => None
      }
      guard comparison is Some(comparison) else {
        skipped += 1
        continue
      }
      if comparison.status != "disagreement" {
        continue
      }
      let score = candidates.length() * candidates.length() -
        comparison.groups.fold(init=0, (n, g) => {
          n + g.candidates.length() * g.candidates.length()
        })
      if best is None || (best is Some(previous) && score > previous.score) {
        best = Some({
          source_index,
          mutation: mutations[mutation_index],
          table: {
            columns: table.columns.copy(),
            rows: table.rows.map(row => row.copy()),
          },
          score,
          groups: comparison.groups.map(g => g.candidates.copy()),
        })
      }
    }
  }
  { suggestion: best, attempted, skipped, }
}
