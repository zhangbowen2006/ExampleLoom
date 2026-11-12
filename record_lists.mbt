///|
/// Explicit multivalue record policy. Values are JSON array strings to avoid
/// losing separator characters, empty values or duplicate occurrence order.
fn pivot_record_lists(
  table : Table,
  variable : String,
  value_name : String,
  marker : String,
) -> Table raise LoomError {
  let indices = column_indices(table, [variable, value_name])
  let key_index = indices[0]
  let value_index = indices[1]
  if table.rows.is_empty() || table.rows[0][key_index] != marker {
    raise LoomError(
      "pivot_record_lists requires the starting marker in the first row",
    )
  }
  let labels : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  let records : Array[Map[String, Array[String]]] = []
  let encoded_sizes : Array[Map[String, Int32]] = []
  for row in table.rows {
    let key = row[key_index]
    if key.is_empty() {
      raise LoomError("pivot_record_lists keys must be nonempty")
    }
    if key == marker {
      records.push(Map([]))
      encoded_sizes.push(Map([]))
    }
    if !seen.contains(key) {
      seen[key] = true
      labels.push(key)
    }
    check_growth(records.length() + 1, labels.length())
    let current = records[records.length() - 1]
    let sizes = encoded_sizes[encoded_sizes.length() - 1]
    let previous = sizes.get(key).unwrap_or(2)
    let encoded = Json(row[value_index]).stringify().length()
    let total = previous + encoded + (if current.contains(key) { 1 } else { 0 })
    if total > 65536 {
      raise LoomError("record list cell exceeds 65536 UTF-16 units")
    }
    sizes[key] = total
    match current.get(key) {
      Some(values) => values.push(row[value_index])
      None => current[key] = [row[value_index]]
    }
  }
  let rows : Array[Array[String]] = [labels.copy()]
  for record in records {
    rows.push(
      labels.map(label => {
        let text = Json(record.get(label).unwrap_or([])).stringify()
        if text.length() > 65536 {
          raise LoomError("record list cell exceeds 65536 UTF-16 units")
        }
        text
      }),
    )
  }
  { columns: generic_columns(labels.length()), rows, }
}
