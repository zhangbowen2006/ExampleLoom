///|
pub(all) struct TablePredictionGroup {
  prediction : Result[Table, String]
  candidates : Array[Int32]
}

///|
/// Coordinates refer to data cells, excluding the header, and are zero-based.
pub(all) enum TableDifference {
  ColumnNames
  RowCount
  Cell(Int32, Int32)
  Execution
} derive(Eq, Debug)

///|
pub extend TableDifference with Eq::{equal, not_equal}

///|
pub extend TableDifference with @debug.Debug::{to_repr}

///|
pub(all) struct TableComparison {
  groups : Array[TablePredictionGroup]
  status : String
  successful_candidates : Int32
  first_difference : TableDifference?
}

///|
fn check_comparison_size(table : Table) -> Unit raise LoomError {
  if table.rows.length() > 2000 ||
    table.rows.length() * table.columns.length() > 20000 {
    raise LoomError(
      "comparison table exceeds 2000 rows or 20000 cells; use a smaller complete batch",
    )
  }
  let mut units = table.columns.fold(init=0, (n, c) => n + c.length())
  for row in table.rows {
    for value in row {
      units = units + value.length()
      if units > 250000 {
        raise LoomError(
          "comparison table exceeds 250000 UTF-16 units; use a smaller complete batch",
        )
      }
    }
  }
}

///|
fn first_table_difference(
  a : Result[Table, String],
  b : Result[Table, String],
) -> TableDifference? {
  match (a, b) {
    (Ok(a), Ok(b)) => {
      if a.columns != b.columns {
        return Some(ColumnNames)
      }
      if a.rows.length() != b.rows.length() {
        return Some(RowCount)
      }
      for i, row in a.rows {
        for j, value in row {
          if value != b.rows[i][j] {
            return Some(Cell(i, j))
          }
        }
      }
      None
    }
    _ => Some(Execution)
  }
}

///|
/// Replay retained programs on a complete, unlabelled batch. Compare every cell,
/// header and row position, and keep execution failures as distinct outcomes.
/// This does not change ranking, select a program or establish correctness.
/// The comparison limits apply to input and each successful output; exceeding
/// them aborts comparison rather than silently sampling an incomplete record.
pub fn compare_table_candidates(
  candidates : Array[Pipeline],
  table : Table,
) -> TableComparison raise LoomError {
  if candidates.is_empty() || candidates.length() > 8 {
    raise LoomError("comparison requires 1..8 pipelines")
  }
  validate_table(table)
  check_comparison_size(table)
  let groups : Array[TablePredictionGroup] = []
  let mut successful_candidates = 0
  for i, pipeline in candidates {
    let prediction = Ok(apply_pipeline(pipeline, table)) catch {
      LoomError(message) => Err(message)
    }
    if prediction is Ok(output) {
      // A comparison resource limit is not a program-execution failure.
      check_comparison_size(output)
      successful_candidates = successful_candidates + 1
    }
    let mut found = false
    for group in groups {
      if group.prediction == prediction {
        group.candidates.push(i)
        found = true
        break
      }
    }
    if !found {
      groups.push({ prediction, candidates: [i], })
    }
  }
  {
    groups,
    successful_candidates,
    status: if successful_candidates == 0 {
      "all_failed"
    } else if groups.length() == 1 {
      "consistent"
    } else {
      "disagreement"
    },
    first_difference: if groups.length() < 2 {
      None
    } else {
      first_table_difference(groups[0].prediction, groups[1].prediction)
    },
  }
}
