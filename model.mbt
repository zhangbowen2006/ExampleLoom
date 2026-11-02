///|
/// A position counts Unicode scalar values, not UTF-16 units or graphemes.
pub(all) enum Position {
  Start(Int32)
  End(Int32)
} derive(Eq, Debug)

///|
/// ASCII run classes are deliberate; non-ASCII letters are not folded.
pub(all) enum RunKind {
  Digits
  Letters
} derive(Eq, Debug)

///|
/// Pure, finite-data expressions. No eval, I/O, regex execution or host calls.
pub(all) enum Expr {
  Field(Int32)
  Literal(String)
  Slice(Expr, Position, Position)
  Token(Expr, String, Int32)
  Run(Expr, RunKind, Int32)
  Trim(Expr)
  Lower(Expr)
  Upper(Expr)
  Concat(Array[Expr])
  DateText(Expr, String, String)
} derive(Eq, Debug)

///|
pub(all) suberror LoomError {
  LoomError(String)
} derive(Eq, Debug)

///|
pub(all) struct Example {
  input : Array[String]
  output : String
} derive(Eq, Debug)

///|
pub(all) struct Table {
  columns : Array[String]
  rows : Array[Array[String]]
} derive(Eq, Debug)

///|
fn char_slice(chars : Array[Char], start : Int32, end : Int32) -> String {
  String::from_array(chars[start:end])
}

///|
fn resolve(pos : Position, len : Int32) -> Int32 raise LoomError {
  let n = match pos {
    Start(n) | End(n) => n
  }
  if n < 0 || n > len {
    raise LoomError("slice position outside input")
  }
  match pos {
    Start(n) => n
    End(n) => len - n
  }
}

///|
fn select_part(parts : Array[String], index : Int32) -> String raise LoomError {
  let i = if index < 0 { parts.length() + index } else { index }
  if i < 0 || i >= parts.length() {
    raise LoomError("token or run index outside input")
  }
  parts[i]
}

///|
fn runs(text : String, kind : RunKind) -> Array[String] {
  let chars = text.to_array()
  let result : Array[String] = []
  let mut start = -1
  for i = 0; i <= chars.length(); i = i + 1 {
    let yes = i < chars.length() &&
      (match kind {
        Digits => chars[i].is_ascii_digit()
        Letters => chars[i].is_ascii_alphabetic()
      })
    if yes && start < 0 {
      start = i
    }
    if !yes && start >= 0 {
      result.push(char_slice(chars, start, i))
      start = -1
    }
  }
  result
}

///|
/// Evaluate one row. A malformed selector fails instead of silently padding.
pub fn evaluate(expr : Expr, row : Array[String]) -> String raise LoomError {
  check_tree(expr, 0, { used: 0, })
  eval_at(expr, row, 0)
}

///|
fn eval_at(
  expr : Expr,
  row : Array[String],
  depth : Int32,
) -> String raise LoomError {
  if depth > 16 {
    raise LoomError("expression depth exceeds 16")
  }
  let value = match expr {
    Field(i) => {
      if i < 0 || i >= row.length() {
        raise LoomError("missing input column")
      }
      row[i]
    }
    Literal(s) => s
    DateText(e, source, target) =>
      convert_date(eval_at(e, row, depth + 1), source, target)
    Slice(e, from, to) => {
      let chars = eval_at(e, row, depth + 1).to_array()
      let start = resolve(from, chars.length())
      let end = resolve(to, chars.length())
      if start > end {
        raise LoomError("slice start exceeds end")
      }
      char_slice(chars, start, end)
    }
    Token(e, separator, index) => {
      if separator.is_empty() {
        raise LoomError("empty separator")
      }
      select_part(
        eval_at(e, row, depth + 1)
        .split(separator)
        .map(v => v.to_owned())
        .collect(),
        index,
      )
    }
    Run(e, kind, index) =>
      select_part(runs(eval_at(e, row, depth + 1), kind), index)
    Trim(e) => eval_at(e, row, depth + 1).trim().to_owned()
    Lower(e) =>
      String::from_iter(
        eval_at(e, row, depth + 1).iter().map(c => c.to_ascii_lowercase()),
      )
    Upper(e) =>
      String::from_iter(
        eval_at(e, row, depth + 1).iter().map(c => c.to_ascii_uppercase()),
      )
    Concat(parts) => {
      if parts.length() > 32 {
        raise LoomError("concatenation exceeds 32 parts")
      }
      let out = StringBuilder()
      for part in parts {
        out.write_string(eval_at(part, row, depth + 1))
        if out.to_string().length() > 65536 {
          raise LoomError("output exceeds 65536 UTF-16 units")
        }
      }
      out.to_string()
    }
  }
  if value.length() > 65536 {
    raise LoomError("output exceeds 65536 UTF-16 units")
  }
  value
}

///|
/// A stable readable description; it is not executable host code.
pub fn explain(expr : Expr) -> String {
  match expr {
    Field(i) => "column[\{i}]"
    Literal(s) => Json(s).stringify()
    DateText(e, source, target) => "date(\{explain(e)}, \{source}, \{target})"
    Slice(e, a, b) =>
      "slice(\{explain(e)}, \{position_text(a)}, \{position_text(b)})"
    Token(e, s, i) => "token(\{explain(e)}, \{Json(s).stringify()}, \{i})"
    Run(e, k, i) => "run(\{explain(e)}, \{kind_text(k)}, \{i})"
    Trim(e) => "trim(\{explain(e)})"
    Lower(e) => "ascii_lower(\{explain(e)})"
    Upper(e) => "ascii_upper(\{explain(e)})"
    Concat(parts) => "concat(" + parts.map(explain).join(", ") + ")"
  }
}

///|
pub extend Position with Eq::{equal, not_equal}

///|
pub extend RunKind with Eq::{equal, not_equal}

///|
pub extend Expr with Eq::{equal, not_equal}

///|
pub extend LoomError with Eq::{equal, not_equal}

///|
pub extend Example with Eq::{equal, not_equal}

///|
pub extend Table with Eq::{equal, not_equal}

///|
fn position_text(p : Position) -> String {
  match p {
    Start(n) => "start+\{n}"
    End(n) => "end-\{n}"
  }
}

///|
fn kind_text(k : RunKind) -> String {
  match k {
    Digits => "digits"
    Letters => "letters"
  }
}

///|
/// Convert a typed evaluation failure to a value for batch processing.
pub fn attempt(expr : Expr, row : Array[String]) -> Result[String, String] {
  Ok(evaluate(expr, row)) catch {
    LoomError(message) => Err(message)
  }
}

///|
pub extend Position with @debug.Debug::{to_repr}

///|
pub extend RunKind with @debug.Debug::{to_repr}

///|
pub extend Expr with @debug.Debug::{to_repr}

///|
pub extend LoomError with @debug.Debug::{to_repr}

///|
pub extend Example with @debug.Debug::{to_repr}

///|
pub extend Table with @debug.Debug::{to_repr}
