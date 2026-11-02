///|
pub(all) struct PredictionGroup {
  prediction : Result[String, String]
  candidates : Array[Int32]
}

///|
pub(all) struct Disagreement {
  row_index : Int32
  groups : Array[PredictionGroup]
  // n^2 - sum(group_size^2): balanced splits rank higher, no probabilities.
  score : Int32
}

///|
/// Find actual rows on which retained candidates disagree. Consensus means
/// agreement among this finite set, never correctness outside the examples.
pub fn disagreements(
  candidates : Array[Candidate],
  rows : Array[Array[String]],
  limit~ : Int32 = 10,
) -> Array[Disagreement] raise LoomError {
  if candidates.length() > 256 ||
    rows.length() > 5000 ||
    limit < 0 ||
    limit > 100 {
    raise LoomError("disagreement input exceeds limits")
  }
  let result : Array[Disagreement] = []
  if candidates.length() < 2 {
    return result
  }
  for row_index, row in rows {
    let groups : Array[PredictionGroup] = []
    for index, candidate in candidates {
      let prediction = attempt(candidate.expression, row)
      let mut found = false
      for group in groups {
        if group.prediction == prediction {
          group.candidates.push(index)
          found = true
          break
        }
      }
      if !found {
        groups.push({ prediction, candidates: [index], })
      }
    }
    if groups.length() > 1 {
      let mut score = candidates.length() * candidates.length()
      for group in groups {
        score = score - group.candidates.length() * group.candidates.length()
      }
      result.push({ row_index, groups, score, })
    }
  }
  result.sort_by((a, b) => {
    if a.score == b.score {
      a.row_index.compare(b.row_index)
    } else {
      b.score.compare(a.score)
    }
  })
  result[:Int32::min(limit, result.length())].to_owned()
}
