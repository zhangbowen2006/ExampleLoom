///|
pub(all) enum SortKind {
  Lexical
  Decimal
} derive(Eq, Debug)

///|
pub extend SortKind with Eq::{equal, not_equal}

///|
pub extend SortKind with @debug.Debug::{to_repr}

///|
pub(all) struct SortKey {
  column : String
  kind : SortKind
  descending : Bool
}

///|
priv struct DecimalOrder {
  negative : Bool
  whole : Array[Char]
  fraction : Array[Char]
}

///|
fn lexical_chars(a : Array[Char], b : Array[Char]) -> Int32 {
  for i in 0..<Int32::min(a.length(), b.length()) {
    let order = a[i].to_int().compare(b[i].to_int())
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
// Compare exact plain decimal strings without floating point or scaling into a
// machine integer. Original cell spelling, including zero padding, is retained.
fn decimal_order(source : String) -> DecimalOrder raise LoomError {
  if source.is_empty() || source.length() > 256 {
    raise LoomError("decimal sort key requires 1..256 ASCII characters")
  }
  let chars = source.to_array()
  let negative = chars[0] == '-'
  let start = if negative || chars[0] == '+' { 1 } else { 0 }
  let mut point = chars.length()
  for i in start..<chars.length() {
    if chars[i] == '.' && point == chars.length() {
      point = i
    } else if !chars[i].is_ascii_digit() {
      raise LoomError(
        "expected plain signed decimal without spaces, exponent or separators",
      )
    }
  }
  if start == point || point == chars.length() - 1 || start == chars.length() {
    raise LoomError("expected digits before and after a decimal point")
  }
  let mut first = start
  while first + 1 < point && chars[first] == '0' {
    first = first + 1
  }
  let whole = chars[first:point].to_owned()
  let mut last = chars.length()
  if point < chars.length() {
    while last > point + 1 && chars[last - 1] == '0' {
      last = last - 1
    }
  }
  let fraction = if point == chars.length() {
    []
  } else {
    chars[point + 1:last].to_owned()
  }
  {
    negative: negative &&
    !(whole.length() == 1 && whole[0] == '0' && fraction.is_empty()),
    whole,
    fraction,
  }
}

///|
fn compare_decimal(a : DecimalOrder, b : DecimalOrder) -> Int32 {
  if a.negative != b.negative {
    return if a.negative { -1 } else { 1 }
  }
  let mut order = a.whole.length().compare(b.whole.length())
  if order == 0 {
    order = lexical_chars(a.whole, b.whole)
  }
  if order == 0 {
    // With trailing zeroes removed, lexical fraction order is equivalent to
    // right-padding both fractions with zeroes, including proper prefixes.
    order = lexical_chars(a.fraction, b.fraction)
  }
  if a.negative {
    -order
  } else {
    order
  }
}

///|
fn validate_sort_keys(keys : Array[SortKey]) -> Unit raise LoomError {
  if keys.is_empty() || keys.length() > 8 {
    raise LoomError("sort_rows requires 1..8 distinct keys")
  }
  validate_columns(keys.map(k => k.column))
}

///|
priv struct PreparedSortColumn {
  numbers : Array[DecimalOrder]
  letters : Array[Array[Char]]
}

///|
fn prepare_sort_column(
  table : Table,
  key : SortKey,
) -> PreparedSortColumn raise LoomError {
  let index = column_index(table, key.column)
  let numbers = match key.kind {
    Lexical => []
    Decimal =>
      table.rows.mapi((i, row) => {
        decimal_order(row[index]) catch {
          LoomError(message) =>
            raise LoomError("row \{i + 1}, column \{key.column}: \{message}")
        }
      })
  }
  let letters = match key.kind {
    Lexical => table.rows.map(row => row[index].to_array())
    Decimal => []
  }
  { numbers, letters, }
}

///|
fn compare_sort_rows(
  column : PreparedSortColumn,
  key : SortKey,
  a : Int32,
  b : Int32,
) -> Int32 {
  let order = match key.kind {
    Lexical => lexical_chars(column.letters[a], column.letters[b])
    Decimal => compare_decimal(column.numbers[a], column.numbers[b])
  }
  let normalized = if order < 0 { -1 } else if order > 0 { 1 } else { 0 }
  if key.descending {
    -normalized
  } else {
    normalized
  }
}

///|
fn sort_rows(table : Table, keys : Array[SortKey]) -> Table raise LoomError {
  validate_sort_keys(keys)
  let prepared = keys.map(key => prepare_sort_column(table, key))
  let order = Array::makei(table.rows.length(), i => i)
  order.sort_by((a, b) => {
    for i, key in keys {
      let result = compare_sort_rows(prepared[i], key, a, b)
      if result != 0 {
        return result
      }
    }
    // An explicit input ordinal guarantees stable ties on every backend.
    a.compare(b)
  })
  { columns: table.columns.copy(), rows: order.map(i => table.rows[i].copy()), }
}
