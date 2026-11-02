///|
fn validate_columns(columns : Array[String]) -> Unit raise LoomError {
  if columns.is_empty() || columns.length() > 64 {
    raise LoomError("expected 1..64 columns")
  }
  let seen : Map[String, Bool] = Map([])
  for name in columns {
    if name.trim().is_empty() || seen.contains(name) {
      raise LoomError("column names must be nonempty and unique")
    }
    seen[name] = true
  }
}

///|
/// Reject ragged rows rather than shifting or guessing column alignment.
pub fn validate_table(table : Table) -> Unit raise LoomError {
  validate_columns(table.columns)
  if table.rows.length() > 20000 {
    raise LoomError("table exceeds 20000 rows")
  }
  for i, row in table.rows {
    if row.length() != table.columns.length() {
      raise LoomError("row \{i + 1} has incorrect column count")
    }
    for value in row {
      if value.length() > 65536 {
        raise LoomError("cell exceeds 65536 UTF-16 units")
      }
    }
  }
}

///|
/// Strict comma CSV with headers, doubled quotes, quoted newlines and optional BOM.
pub fn parse_csv(source : String) -> Table raise LoomError {
  if source.length() > 2000000 {
    raise LoomError("input exceeds 2000000 UTF-16 units")
  }
  let c = source.to_array()
  let records : Array[Array[String]] = []
  let mut row : Array[String] = []
  let field = StringBuilder()
  // 0: field start; 1: unquoted; 2: quoted; 3: closed quote.
  let mut state = 0
  let mut i = if c.length() > 0 && c[0].to_int() == 65279 { 1 } else { 0 }
  while i < c.length() {
    let ch = c[i]
    if state == 2 {
      if ch == '"' {
        if i + 1 < c.length() && c[i + 1] == '"' {
          field.write_char('"')
          i = i + 1
        } else {
          state = 3
        }
      } else {
        field.write_char(ch)
      }
    } else if ch == ',' || ch == '\n' || ch == '\r' {
      row.push(field.to_string())
      field.reset()
      state = 0
      if ch != ',' {
        records.push(row)
        row = []
        if ch == '\r' && i + 1 < c.length() && c[i + 1] == '\n' {
          i = i + 1
        }
      }
    } else if state == 3 {
      raise LoomError("unexpected text after closing CSV quote")
    } else if ch == '"' {
      if state != 0 {
        raise LoomError("quote inside unquoted CSV field")
      }
      state = 2
    } else {
      field.write_char(ch)
      state = 1
    }
    i = i + 1
  }
  if state == 2 {
    raise LoomError("unterminated CSV quote")
  }
  if state != 0 || !row.is_empty() {
    row.push(field.to_string())
    records.push(row)
  }
  if records.is_empty() {
    raise LoomError("CSV requires a header")
  }
  let table = { columns: records[0], rows: records[1:].to_owned(), }
  validate_table(table)
  table
}

///|
fn csv_cell(value : String, spreadsheet_safe : Bool) -> String {
  let first = value.trim().to_owned().to_array()
  let needs_escape = spreadsheet_safe &&
    first.length() > 0 &&
    (first[0] == '=' || first[0] == '+' || first[0] == '-' || first[0] == '@')
  let s = if needs_escape { "'" + value } else { value }
  if s.contains_char(',') ||
    s.contains_char('"') ||
    s.contains_char('\n') ||
    s.contains_char('\r') {
    "\"" + s.replace_all(old="\"", new="\"\"") + "\""
  } else {
    s
  }
}

///|
/// Spreadsheet-safe output prefixes formula-like cells with an apostrophe.
/// Disable only when exact machine-readable round trips are intended.
pub fn render_csv(
  table : Table,
  spreadsheet_safe~ : Bool = true,
) -> String raise LoomError {
  validate_table(table)
  let out = StringBuilder()
  out.write_string(
    table.columns.map(v => csv_cell(v, spreadsheet_safe)).join(","),
  )
  out.write_string("\r\n")
  for row in table.rows {
    out.write_string(row.map(v => csv_cell(v, spreadsheet_safe)).join(","))
    out.write_string("\r\n")
  }
  out.to_string()
}

///|
fn parse_json_text(source : String) -> Json raise LoomError {
  @json.parse(source, max_nesting_depth=32, reject_duplicate_keys=true) catch {
    _ => raise LoomError("invalid JSON (or duplicate key / depth limit)")
  }
}

///|
/// JSONL accepts string/null-valued objects. Numbers are rejected to avoid
/// rounding identifiers and losing leading zeros. Null is explicitly empty.
pub fn parse_jsonl(source : String) -> Table raise LoomError {
  if source.length() > 2000000 {
    raise LoomError("input exceeds 2000000 UTF-16 units")
  }
  let columns : Array[String] = []
  let rows : Array[Array[String]] = []
  for line in source.split("\n") {
    if line.trim().is_empty() {
      continue
    }
    let obj = match parse_json_text(line.to_owned()) {
      Object(obj) => obj
      _ => raise LoomError("JSONL rows must be objects")
    }
    if rows.is_empty() {
      for key, _ in obj {
        columns.push(key)
      }
      columns.sort()
      validate_columns(columns)
    }
    if obj.length() != columns.length() {
      raise LoomError("JSONL schema differs between rows")
    }
    let row : Array[String] = []
    for name in columns {
      match obj.get(name) {
        Some(String(value)) => row.push(value)
        Some(Null) => row.push("")
        _ =>
          raise LoomError(
            "JSONL requires the same string/null fields on every row",
          )
      }
    }
    rows.push(row)
  }
  let table = { columns, rows, }
  validate_table(table)
  table
}
