///| The explicit prefix preserves existing MoonBit core/lexmatch recipes.

///|
/// Only (?rx) opts into the extended, bounded native MoonBit dialect.
priv struct ExtendedRegex {
  code : Array[@rxvm.Instruction]
  groups : Int32
  names : Map[String, Int32]
  backreferences : Bool
}

///|
priv enum CompiledPattern {
  Classic(@string.Regex)
  Extended(ExtendedRegex)
}

///|
priv struct RegexMatch {
  text : String
  start : Int32
  end : Int32
  groups : Array[String?]
  names : Map[String, Int32]
  classic : @string.MatchResult?
}

///|
fn RegexMatch::group(self : RegexMatch, index : Int32) -> StringView? {
  if self.classic is Some(m) {
    return m.group(index)
  }
  if index < 0 || index >= self.groups.length() {
    return None
  }
  self.groups[index].map(s => s[:])
}

///|
fn RegexMatch::before(self : RegexMatch) -> StringView {
  self.text[:self.start]
}

///|
fn RegexMatch::content(self : RegexMatch) -> StringView {
  self.text[self.start:self.end]
}

///|
fn classic_match(text : String, m : @string.MatchResult) -> RegexMatch {
  {
    text,
    start: m.before().length(),
    end: m.before().length() + m.content().length(),
    groups: [],
    names: Map([]),
    classic: Some(m),
  }
}

///|
fn extended_match(
  text : String,
  offsets : Array[Int32],
  names : Map[String, Int32],
) -> RegexMatch {
  {
    text,
    start: offsets[0],
    end: offsets[1],
    names,
    classic: None,
    groups: Array::makei(offsets.length() / 2, i => {
      let a = offsets[i * 2]
      let b = offsets[i * 2 + 1]
      if a < 0 || b < a {
        None
      } else {
        Some(text[a:b].to_owned())
      }
    }),
  }
}

///|
fn extended_pattern(pattern : String) -> CompiledPattern raise LoomError {
  let body = pattern[5:]
  // Bound parser recursion, capture allocation and expanded VM instructions.
  let mut depth = 0
  let mut escaped = false
  let mut in_class = false
  for c in body {
    if escaped {
      escaped = false
      continue
    }
    if c == '\\' {
      escaped = true
      continue
    }
    if c == '[' {
      in_class = true
    }
    if c == ']' {
      in_class = false
    }
    if !in_class && c == '(' {
      depth += 1
    }
    if !in_class && c == ')' {
      depth -= 1
    }
    if depth > 24 {
      raise LoomError("regex nesting exceeds 24")
    }
  }
  let parsed = @rxparse.parse(body) catch {
    _ =>
      raise LoomError(
        "invalid extended regex (variable-width lookbehind is unsupported)",
      )
  }
  if parsed.captures > 33 {
    raise LoomError("regex exceeds 32 capture groups")
  }
  // Upstream byte-comparison backreferences do not implement case folding.
  if parsed.has_backreference && body.contains("(?i") {
    raise LoomError("case-insensitive backreferences are unsupported")
  }
  let code = parsed.ast.compile()
  if code.length() > 16384 {
    raise LoomError("regex instruction expansion exceeds 16384")
  }
  Extended({
    code,
    groups: parsed.captures,
    names: parsed.capture_map,
    backreferences: parsed.has_backreference,
  })
}

///|
fn anchored_pattern(pattern : String) -> String {
  if pattern.has_prefix("(?rx)") {
    "(?rx)^(?:" + pattern[5:].to_owned() + ")$"
  } else {
    "^(?:" + pattern + ")$"
  }
}

///|
fn CompiledPattern::execute(
  self : CompiledPattern,
  input : StringView,
) -> RegexMatch? raise LoomError {
  if input.length() > 65536 {
    raise LoomError("regex input exceeds cell limit")
  }
  let text = input.to_owned()
  match self {
    Classic(regex) => regex.execute(input).map(m => classic_match(text, m))
    Extended(regex) => {
      let offsets = @rxvm.search(
        regex.code,
        input,
        regex.groups,
        0,
        regex.backreferences,
        false,
        { remaining: 300000, },
      ) catch {
        _ =>
          raise LoomError("regex execution exceeded 300000 instruction steps")
      }
      if offsets.is_empty() {
        None
      } else {
        Some(extended_match(text, offsets, regex.names))
      }
    }
  }
}

///|
fn CompiledPattern::find(
  self : CompiledPattern,
  input : StringView,
) -> Array[RegexMatch] raise LoomError {
  if input.length() > 65536 {
    raise LoomError("regex input exceeds cell limit")
  }
  let text = input.to_owned()
  let matches : Array[RegexMatch] = []
  match self {
    Classic(regex) =>
      for m in regex.find(input) {
        if matches.length() == 4096 {
          raise LoomError("regex exceeds 4096 matches")
        }
        matches.push(classic_match(text, m))
      }
    Extended(regex) => {
      let budget : @rxvm.Budget = { remaining: 300000, }
      let mut from = 0
      while from <= input.length() {
        let offsets = @rxvm.search(
          regex.code,
          input,
          regex.groups,
          from,
          regex.backreferences,
          false,
          budget,
        ) catch {
          _ =>
            raise LoomError("regex execution exceeded 300000 instruction steps")
        }
        if offsets.is_empty() {
          break
        }
        if matches.length() == 4096 {
          raise LoomError("regex exceeds 4096 matches")
        }
        matches.push(extended_match(text, offsets, regex.names))
        from = offsets[1]
        if offsets[0] == offsets[1] {
          from += if input.get_char(from) is Some(c) && c.to_int() > 0xffff {
            2
          } else {
            1
          }
        }
      }
    }
  }
  matches
}
