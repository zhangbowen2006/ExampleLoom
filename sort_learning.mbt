///|
priv struct SortWitnessKey {
  key : SortKey
  prepared : Array[PreparedSortColumn]
}

///|
// Match duplicate rows by occurrence, so a target cannot fabricate/drop rows.
fn permutation_ordinals(before : Table, after : Table) -> Array[Int32]? {
  if before.columns != after.columns ||
    before.rows.length() != after.rows.length() {
    return None
  }
  let positions : Map[String, Array[Int32]] = Map([])
  for i, row in before.rows {
    let key = Json(row).stringify()
    match positions.get(key) {
      Some(indices) => indices.push(i)
      None => positions[key] = [i]
    }
  }
  let consumed : Map[String, Int32] = Map([])
  let result : Array[Int32] = []
  for row in after.rows {
    let key = Json(row).stringify()
    guard positions.get(key) is Some(indices) else { return None }
    let offset = consumed.get(key).unwrap_or(0)
    if offset >= indices.length() {
      return None
    }
    result.push(indices[offset])
    consumed[key] = offset + 1
  }
  Some(result)
}

///|
fn target_tied(
  prefix : Array[Int32],
  variants : Array[SortWitnessKey],
  pair : Int32,
  row : Int32,
) -> Bool {
  prefix.all(i => {
    compare_sort_rows(variants[i].prepared[pair], variants[i].key, row - 1, row) ==
    0
  })
}

///|
fn useful_sort_extension(
  prefix : Array[Int32],
  candidate : Int32,
  variants : Array[SortWitnessKey],
  targets : Array[Table],
) -> Bool {
  let variant = variants[candidate]
  if prefix.any(i => variants[i].key.column == variant.key.column) {
    return false
  }
  let mut distinguishes = false
  for p, target in targets {
    for row in 1..<target.rows.length() {
      if target_tied(prefix, variants, p, row) {
        let order = compare_sort_rows(
          variant.prepared[p],
          variant.key,
          row - 1,
          row,
        )
        if order > 0 {
          return false
        }
        distinguishes = distinguishes || order < 0
      }
    }
  }
  distinguishes
}

///|
fn stable_target_order(
  prefix : Array[Int32],
  variants : Array[SortWitnessKey],
  targets : Array[Table],
  ordinals : Array[Array[Int32]],
) -> Bool {
  for p, target in targets {
    for row in 1..<target.rows.length() {
      if target_tied(prefix, variants, p, row) &&
        ordinals[p][row - 1] > ordinals[p][row] {
        return false
      }
    }
  }
  true
}

///|
/// Infer at most three ordered keys using target monotonicity inside prefix
/// ties, then check original ordinals for stable ties. Runtime supports eight.
/// Only training permutations participate. Outer search replays every returned
/// step on all training pairs and charges it to its existing evaluation budget.
fn sort_witnesses(
  tables : Array[Table],
  targets : Array[Table],
) -> (Array[TableStep], Bool) {
  let ordinals : Array[Array[Int32]] = []
  let mut changed = false
  for i, table in tables {
    if table.columns != tables[0].columns {
      return ([], false)
    }
    guard permutation_ordinals(table, targets[i]) is Some(order) else {
      return ([], false)
    }
    changed = changed || table.rows != targets[i].rows
    ordinals.push(order)
  }
  if !changed {
    return ([], false)
  }
  let variants : Array[SortWitnessKey] = []
  for column in tables[0].columns {
    for kind in [Lexical, Decimal] {
      let key : SortKey = { column, kind, descending: false, }
      let prepared = targets.map(t => prepare_sort_column(t, key)) catch {
        _ => continue
      }
      variants.push({ key, prepared, })
      variants.push({ key: { ..key, descending: true, }, prepared, })
    }
  }
  let frontier : Array[Array[Int32]] = [[]]
  let result : Array[TableStep] = []
  let mut index = 0
  let mut clipped = false
  while index < frontier.length() {
    let prefix = frontier[index]
    index = index + 1
    for candidate in 0..<variants.length() {
      if !useful_sort_extension(prefix, candidate, variants, targets) {
        continue
      }
      let extended = prefix + [candidate]
      if stable_target_order(extended, variants, targets, ordinals) {
        // Limit this added operator family to two completions per state so
        // correlated sort keys do not crowd out existing structural witnesses.
        if result.length() == 2 {
          return (result, true)
        }
        result.push(SortRows(extended.map(i => variants[i].key)))
      } else if extended.length() < 3 && frontier.length() < 32 {
        frontier.push(extended)
      } else {
        clipped = true
      }
    }
  }
  (result, clipped)
}
