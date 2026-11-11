// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
pub(all) enum Ast {
  Empty
  /// Anything that can be interpreted as range (inclusive) pair list, e.g. `.` (0..=0x10FFFF)
  CharClass(ArrayView[Char], neg~ : Bool)
  Assertion(Predicate)
  Capture(Ast, index~ : Int32)
  ZeroOrMore(Ast, greedy~ : Bool)
  OneOrMore(Ast, greedy~ : Bool)
  ZeroOrOne(Ast, greedy~ : Bool)
  /// Matches a specific number of repetitions.
  Repeat(Ast, greedy~ : Bool, min~ : UInt32, max~ : UInt32?)
  Concat(Array[Ast])
  Alternate(Ast, Ast)
  Backreference(Int32)
  Look(Ast, positive~ : Bool, behind~ : Int32?)
} derive(Debug)

///|
pub extend Ast with Debug::{to_repr}

///|
/// @returns next capture
fn Ast::compile_aux(regex : Ast, instructions : Array[Instruction]) -> Unit {
  match regex {
    Empty => ()
    CharClass(chars, neg~) =>
      if neg {
        // compute the complement of the character class
        let complement = compute_char_class_complement(chars)
        instructions.push(Char(complement))
      } else {
        // simplify and sort the character ranges for binary search
        let simplified = simplify_char_ranges(chars)
        instructions.push(Char(simplified))
      }
    Assertion(pred) => instructions.push(Assertion(pred))
    Capture(inner, index=capture) => {
      instructions.push(Save(capture * 2))
      inner.compile_aux(instructions)
      instructions.push(Save(capture * 2 + 1))
    }
    ZeroOrMore(inner, greedy~) => {
      // Compiles to (a+)?
      // See https://github.com/golang/go/issues/46123
      // [ ..., split, inner, split, ... ]
      //          ^ -- instructions.length() at the beginning
      //                            ^ -- instructions.length() at the end
      let split_pos = instructions.length()
      // placeholder for split
      instructions.push(Split(-1, -1))
      inner.compile_iteration(instructions)
      let next_pos = instructions.length()
      if !greedy {
        instructions.push(Split(next_pos + 1, split_pos + 1))
        instructions[split_pos] = Split(next_pos + 1, split_pos + 1)
      } else {
        instructions.push(Split(split_pos + 1, next_pos + 1))
        instructions[split_pos] = Split(split_pos + 1, next_pos + 1)
      }
    }
    OneOrMore(inner, greedy~) => {
      // [ ..., inner, split, ... ]
      //         ^ -- instructions.length() at the beginning
      let jmp_pos = instructions.length()
      inner.compile_iteration(instructions)
      let next_pos = instructions.length()
      if !greedy {
        instructions.push(Split(next_pos + 1, jmp_pos))
      } else {
        instructions.push(Split(jmp_pos, next_pos + 1))
      }
    }
    ZeroOrOne(inner, greedy~) => {
      // [ ..., split, inner, ... ]
      //          ^ -- instructions.length() at the beginning
      //                        ^ -- instructions.length() at the end
      let split_pos = instructions.length()
      // for taking up position
      instructions.push(Split(-1, -1))
      inner.compile_iteration(instructions)
      if !greedy {
        instructions[split_pos] = Split(instructions.length(), split_pos + 1)
      } else {
        instructions[split_pos] = Split(split_pos + 1, instructions.length())
      }
    }
    Repeat(greedy~, min~, max~, inner) =>
      if max is Some(max) {
        // [ ..., inner * min, [ split, inner ] * (max - min), ... ]
        for _ in 0U..<min {
          inner.compile_iteration(instructions)
        }
        let split_pos = []
        for _ in 0U..<(max - min) {
          // placeholder for split
          split_pos.push(instructions.length())
          instructions.push(Split(-1, -1))
          inner.compile_iteration(instructions) |> ignore
        }
        let jmp_pos = instructions.length()
        if !greedy {
          for pos in split_pos {
            instructions[pos] = Split(jmp_pos, pos + 1)
          }
        } else {
          for pos in split_pos {
            instructions[pos] = Split(pos + 1, jmp_pos)
          }
        }
      } else {
        // [ ..., inner * min, split, inner, jmp, ... ]
        //                      ^ -- instructions.length() at the beginning
        //                                         ^ -- instructions.length() at the end
        for _ in 0U..<min {
          inner.compile_iteration(instructions)
        }
        let split_pos = instructions.length()
        // placeholder for split
        instructions.push(Split(-1, -1))
        inner.compile_iteration(instructions)
        instructions.push(Jump(split_pos))
        if !greedy {
          instructions[split_pos] = Split(instructions.length(), split_pos + 1)
        } else {
          instructions[split_pos] = Split(split_pos + 1, instructions.length())
        }
      }
    Concat(regexs) =>
      for regex in regexs {
        regex.compile_aux(instructions)
      }
    Alternate(left, right) => {
      // [ ..., split, left, jmp, right, ... ]
      //          ^ -- instructions.length() at the beginning
      //                      ^ -- instructions.length() at the middle
      //                                   ^ -- instructions.length() at the end
      let split_pos = instructions.length()
      // for taking up position
      instructions.push(Split(-1, -1))
      left.compile_aux(instructions)
      let jmp_pos = instructions.length()
      // placeholder for jump
      instructions.push(Jump(-1))
      right.compile_aux(instructions)
      instructions[split_pos] = Split(split_pos + 1, jmp_pos + 1)
      instructions[jmp_pos] = Jump(instructions.length())
    }
    Look(inner, positive~, behind~) =>
      instructions.push(Look(inner.compile_anchored(), positive~, behind~))
    Backreference(i) => instructions.push(Backreference(i))
  }
}

///|
pub fn Ast::compile(self : Ast) -> Array[Instruction] {
  // for leftmost matching
  let instructions : Array[Instruction] = [
    Split(3, 1),
    Char(['\u{0}', '\u{10FFFF}']),
    Jump(0),
  ]
  // start matching
  instructions.push(Save(0))
  self.compile_aux(instructions)
  instructions.push(Save(1))
  instructions.push(Matched)
  instructions
}

///|
pub impl ToJson for Ast with fn to_json(self) {
  match self {
    Empty => "Empty"
    CharClass(chars, neg~) => ["CharClass neg=\{neg}", chars.map(c => repr(c))]
    Assertion(pred) => "Assertion \{pred}"
    Capture(inner, index~) => ["Capture \{index}", inner]
    ZeroOrMore(inner, greedy~) => ["ZeroOrMore greedy=\{greedy}", inner]
    OneOrMore(inner, greedy~) => ["OneOrMore greedy=\{greedy}", inner]
    ZeroOrOne(inner, greedy~) => ["ZeroOrOne greedy=\{greedy}", inner]
    Repeat(greedy~, min~, max~, inner) =>
      if max is Some(max) {
        ["Repeat {\{min}, \{max}} greedy=\{greedy}", inner]
      } else {
        ["Repeat {\{min},} greedy=\{greedy}", inner]
      }
    Concat(regexs) => [..regexs.map(r => r.to_json())]
    Alternate(left, right) => ["Alternate", left, right]
    Look(inner, positive~, behind~) => ["Look", inner, positive, behind]
    Backreference(i) => ["Backreference", i]
  }
}

///|
pub extend Ast with ToJson::{to_json}

///|
/// Added by ExampleLoom: assertions execute at an absolute input position.
fn Ast::capture_slots(self : Ast, slots : Array[Int32]) -> Unit {
  match self {
    Capture(inner, index~) => {
      slots.push(index * 2)
      slots.push(index * 2 + 1)
      inner.capture_slots(slots)
    }
    ZeroOrMore(inner, ..)
    | OneOrMore(inner, ..)
    | ZeroOrOne(inner, ..)
    | Repeat(inner, ..)
    | Look(inner, ..) => inner.capture_slots(slots)
    Concat(parts) =>
      for part in parts {
        part.capture_slots(slots)
      }
    Alternate(a, b) => {
      a.capture_slots(slots)
      b.capture_slots(slots)
    }
    _ => ()
  }
}

///|
fn Ast::compile_iteration(
  self : Ast,
  instructions : Array[Instruction],
) -> Unit {
  let slots = []
  self.capture_slots(slots)
  if !slots.is_empty() {
    instructions.push(Reset(slots))
  }
  self.compile_aux(instructions)
}

///|
pub fn Ast::compile_anchored(self : Ast) -> Array[Instruction] {
  let instructions : Array[Instruction] = [Save(0)]
  self.compile_aux(instructions)
  instructions.push(Save(1))
  instructions.push(Matched)
  instructions
}

///| A fixed width in Unicode scalars, not UTF-16 units. Variable-width

///|
/// lookbehind is deliberately rejected before execution.
pub fn Ast::fixed_width(self : Ast) -> Int32? {
  match self {
    Empty | Assertion(_) | Look(_, ..) => Some(0)
    CharClass(_, ..) => Some(1)
    Capture(inner, ..) => inner.fixed_width()
    Concat(parts) => {
      let mut total = 0
      for part in parts {
        guard part.fixed_width() is Some(n) else { return None }
        total += n
      }
      Some(total)
    }
    Alternate(a, b) => {
      let x = a.fixed_width()
      if x == b.fixed_width() {
        x
      } else {
        None
      }
    }
    Repeat(inner, min~, max~, ..) => {
      guard max is Some(max) && min == max else { return None }
      inner.fixed_width().map(n => n * min.reinterpret_as_int())
    }
    _ => None
  }
}

///| Backward evaluation would change the selected capture of a repeated

///|
/// group. Reject that form rather than silently return forward captures.
pub fn Ast::lookbehind_captures_safe(self : Ast) -> Bool {
  match self {
    Capture(inner, ..) => inner.lookbehind_captures_safe()
    Repeat(inner, max~, ..) => {
      let slots = []
      inner.capture_slots(slots)
      (max == Some(0U) || max == Some(1U) || slots.is_empty()) &&
      inner.lookbehind_captures_safe()
    }
    ZeroOrMore(inner, ..) | OneOrMore(inner, ..) | ZeroOrOne(inner, ..) => {
      let slots = []
      inner.capture_slots(slots)
      slots.is_empty() && inner.lookbehind_captures_safe()
    }
    Concat(parts) => parts.all(p => p.lookbehind_captures_safe())
    Alternate(a, b) =>
      a.lookbehind_captures_safe() && b.lookbehind_captures_safe()
    _ => true
  }
}
