///|
let regex_cache : Map[String, @string.Regex] = Map([])

///|
fn regex_complexity(pattern : String) -> Unit raise LoomError {
  // Numeric repeat bounds multiply when nested. Bound their conservative
  // product before core lazily builds the NFA, without using private APIs.
  let chars = pattern.to_array()
  let mut product = 1
  let mut in_class = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' {
      i = i + 2
      continue
    }
    if in_class && c == '[' && i + 1 < chars.length() && chars[i + 1] == ':' {
      let mut j = i + 2
      while j < chars.length() && chars[j].is_ascii_alphabetic() {
        j = j + 1
      }
      if j + 1 < chars.length() && chars[j] == ':' && chars[j + 1] == ']' {
        i = j + 2
        continue
      }
    }
    if c == '[' {
      in_class = true
    }
    if c == ']' {
      in_class = false
    }
    if !in_class && c == '{' {
      let mut j = i + 1
      let mut n = 0
      let mut largest = 0
      let mut digits = false
      while j < chars.length() && chars[j] != '}' {
        if chars[j].is_ascii_digit() {
          n = n * 10 + chars[j].to_int() - '0'.to_int()
          if n > 256 {
            raise LoomError("regex numeric repeat exceeds 256")
          }
          largest = Int32::max(largest, n)
          digits = true
        } else if chars[j] == ',' {
          n = 0
        } else {
          break
        }
        j = j + 1
      }
      if digits && j < chars.length() && chars[j] == '}' {
        product = product * (largest + 1)
        if product > 4096 || product * Int32::max(1, pattern.length()) > 16384 {
          raise LoomError("regex repeat expansion exceeds resource budget")
        }
      }
    }
    i = i + 1
  }
}

///|
fn compiled_regex(pattern : String) -> @string.Regex raise LoomError {
  if pattern.length() > 256 {
    raise LoomError("regex pattern exceeds 256 UTF-16 units")
  }
  match regex_cache.get(pattern) {
    Some(regex) => regex
    None => {
      regex_complexity(pattern)
      let regex = @string.Regex(pattern[:]) catch {
        _ => raise LoomError("invalid MoonBit regular expression: \{pattern}")
      }
      if regex_cache.length() >= 64 {
        regex_cache.clear()
      }
      regex_cache[pattern] = regex
      regex
    }
  }
}

///|
fn regex_test(
  text : String,
  pattern : String,
  full : Bool,
) -> Bool raise LoomError {
  // Anchoring the entire alternation matters: ^a|b$ is not a full match.
  if full {
    if pattern.length() > 248 {
      raise LoomError("full regex pattern exceeds 248 units")
    }
    compiled_regex("^(?:" + pattern + ")$").execute(text[:]) is Some(_)
  } else {
    compiled_regex(pattern).execute(text[:]) is Some(_)
  }
}

///|
fn regex_capture(
  text : String,
  pattern : String,
  group : Int32,
  occurrence : Int32,
) -> String raise LoomError {
  if group < 0 || group > 32 || occurrence < -4096 || occurrence >= 4096 {
    raise LoomError("regex group/occurrence outside limits")
  }
  let matches : Array[@string.MatchResult] = []
  for m in compiled_regex(pattern).find(text[:]) {
    if matches.length() == 4096 {
      raise LoomError("regex exceeds 4096 matches")
    }
    matches.push(m)
    if occurrence >= 0 && matches.length() > occurrence {
      break
    }
  }
  let i = if occurrence < 0 {
    matches.length() + occurrence
  } else {
    occurrence
  }
  if i < 0 || i >= matches.length() {
    raise LoomError("regex occurrence not found")
  }
  match matches[i].group(group) {
    Some(value) => value.to_owned()
    None =>
      raise LoomError("regex capture did not participate or does not exist")
  }
}

///|
fn replacement_text(
  template : String,
  m : @string.MatchResult,
  remaining : Int32,
) -> String raise LoomError {
  let chars = template.to_array()
  let out = StringBuilder()
  let mut i = 0
  let mut length = 0
  while i < chars.length() {
    if chars[i] != '$' {
      length = length + (if chars[i].to_int() > 0xffff { 2 } else { 1 })
      if length > remaining {
        raise LoomError("regex replacement exceeds cell limit")
      }
      out.write_char(chars[i])
      i = i + 1
      continue
    }
    if i + 1 >= chars.length() {
      raise LoomError("replacement ends with bare dollar")
    }
    let next = chars[i + 1]
    if next == '$' {
      length = length + 1
      if length > remaining {
        raise LoomError("regex replacement exceeds cell limit")
      }
      out.write_char('$')
    } else if next.is_ascii_digit() {
      if m.group(next.to_int() - '0'.to_int()) is Some(value) {
        length = length + value.length()
        if length > remaining {
          raise LoomError("regex replacement exceeds cell limit")
        }
        out.write_string(value.to_owned())
      }
    } else {
      raise LoomError("replacement supports only $$ and $0..$9")
    }
    i = i + 2
  }
  out.to_string()
}

///|
fn regex_replace(
  text : String,
  pattern : String,
  template : String,
) -> String raise LoomError {
  if text.length() > 65536 || template.length() > 65536 {
    raise LoomError("regex input/template exceeds cell limit")
  }
  // Validate replacement even if no match would execute it.
  let chars = template.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '$' {
      if i + 1 >= chars.length() ||
        !(chars[i + 1] == '$' || chars[i + 1].is_ascii_digit()) {
        raise LoomError("replacement supports only $$ and $0..$9")
      }
      i = i + 1
    }
    i = i + 1
  }
  let out = StringBuilder()
  let mut end = 0
  let mut count = 0
  let mut written = 0
  for m in compiled_regex(pattern).find(text[:]) {
    count = count + 1
    if count > 4096 {
      raise LoomError("regex exceeds 4096 matches")
    }
    let start = m.before().length()
    written = written + (start - end)
    if written > 65536 {
      raise LoomError("regex replacement exceeds cell limit")
    }
    out.write_string(text[end:start].to_owned())
    let chunk = replacement_text(template, m, 65536 - written)
    out.write_string(chunk)
    written = written + chunk.length()
    end = start + m.content().length()
  }
  if written + (text.length() - end) > 65536 {
    raise LoomError("regex replacement exceeds cell limit")
  }
  out.write_string(text[end:].to_owned())
  out.to_string()
}

///|
fn condition_at(
  c : Condition,
  row : Array[String],
  depth : Int32,
) -> Bool raise LoomError {
  if depth > 16 {
    raise LoomError("condition exceeds depth limit")
  }
  match c {
    Equals(a, b) => eval_at(a, row, depth + 1) == eval_at(b, row, depth + 1)
    Empty(e) => eval_at(e, row, depth + 1).is_empty()
    Matches(e, pattern, full) =>
      regex_test(eval_at(e, row, depth + 1), pattern, full)
    Not(c) => !condition_at(c, row, depth + 1)
    All(cs) => {
      for child in cs {
        if !condition_at(child, row, depth + 1) {
          return false
        }
      }
      true
    }
    Any(cs) => {
      for child in cs {
        if condition_at(child, row, depth + 1) {
          return true
        }
      }
      false
    }
  }
}

///|
pub fn test_condition(
  c : Condition,
  row : Array[String],
) -> Bool raise LoomError {
  check_condition(c, 0, { used: 0, })
  condition_at(c, row, 0)
}

///|
pub fn explain_condition(c : Condition) -> String {
  match c {
    Equals(a, b) => "equals(\{explain(a)}, \{explain(b)})"
    Empty(e) => "empty(\{explain(e)})"
    Matches(e, p, full) =>
      "matches(\{explain(e)}, \{Json(p).stringify()}, full=\{full})"
    Not(c) => "not(\{explain_condition(c)})"
    All(cs) => "all(" + cs.map(explain_condition).join(", ") + ")"
    Any(cs) => "any(" + cs.map(explain_condition).join(", ") + ")"
  }
}
