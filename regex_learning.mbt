///|
/// Infer a small regular capture grammar from shared literal context. This is
/// deliberately not arbitrary regex synthesis: output characters must all
/// belong to a supported ASCII class and at least one context must be shared.
fn inferred_capture_patterns(
  examples : Array[Example],
  column : Int32,
) -> Array[String] {
  if examples.any(e => e.output.is_empty()) {
    return []
  }
  let mut digits = true
  let mut letters = true
  let mut alnum = true
  let lefts : Array[Array[Char]] = []
  let rights : Array[Array[Char]] = []
  for e in examples {
    digits = digits && e.output.all(c => c.is_ascii_digit())
    letters = letters && e.output.all(c => c.is_ascii_alphabetic())
    alnum = alnum &&
      e.output.all(c => c.is_ascii_alphabetic() || c.is_ascii_digit())
    let input = e.input[column].to_array()
    let output = e.output.to_array()
    let mut position = -1
    for i = 0; i + output.length() <= input.length(); i = i + 1 {
      if char_slice(input, i, i + output.length()) == e.output {
        position = i
        break
      }
    }
    if position < 0 {
      return []
    }
    lefts.push(input[:position].to_owned())
    rights.push(input[position + output.length():].to_owned())
  }
  let kind = if digits {
    "[[:digit:]]+"
  } else if letters {
    "[[:alpha:]]+"
  } else if alnum {
    "[[:alnum:]]+"
  } else {
    return []
  }
  let mut before = 0
  let mut after = 0
  for n in 1..<17 {
    if lefts.all(s => {
        s.length() >= n && s[s.length() - n] == lefts[0][lefts[0].length() - n]
      }) {
      before = n
    } else {
      break
    }
  }
  for n in 1..<17 {
    if rights.all(s => s.length() >= n && s[n - 1] == rights[0][n - 1]) {
      after = n
    } else {
      break
    }
  }
  if before == 0 && after == 0 {
    return []
  }
  let left = regex_literal(
    char_slice(lefts[0], lefts[0].length() - before, lefts[0].length()),
  )
  let right = regex_literal(char_slice(rights[0], 0, after))
  let patterns = [left + "(" + kind + ")" + right]
  if before > 0 {
    patterns.push(left + "(" + kind + ")")
  }
  if after > 0 {
    patterns.push("(" + kind + ")" + right)
  }
  patterns
}
