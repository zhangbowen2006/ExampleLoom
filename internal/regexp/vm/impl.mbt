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
pub(all) enum Instruction {
  Matched
  Save(Int32)
  Char(ArrayView[Char])
  Jump(Int32)
  Split(Int32, Int32)
  /// Zero-width assertions
  Assertion(Predicate)
  Backreference(Int32)
  Look(Array[Instruction], positive~ : Bool, behind~ : Int32?)
  Reset(Array[Int32])
}

///|
pub impl ToJson for Instruction with fn to_json(self) {
  match self {
    Matched => "Matched"
    Save(i) => ["Save", i]
    Char(chars) => ["Chars", chars.map(c => repr(c))]
    Jump(i) => ["Jump", i]
    Split(i1, i2) => ["Split", i1, i2]
    Assertion(pred) => ["Assertion", pred]
    Look(code, positive~, behind~) => ["Look", code, positive, behind]
    Backreference(i) => ["Backreference", i]
    Reset(slots) => ["Reset", slots]
  }
}

///|
pub extend Instruction with ToJson::{to_json}

///|
pub(all) enum Predicate {
  BeginText
  EndText
  BeginLine
  EndLine
  WordBoundary
  NoWordBoundary
} derive(Debug, ToJson)

///|
pub extend Predicate with Debug::{to_repr}

///|
pub extend Predicate with ToJson::{to_json}

///|
/// Same text as the former `derive(Show)` output.
pub impl Show for Predicate with fn output(self, logger) {
  logger.write_string(
    match self {
      BeginText => "BeginText"
      EndText => "EndText"
      BeginLine => "BeginLine"
      EndLine => "EndLine"
      WordBoundary => "WordBoundary"
      NoWordBoundary => "NoWordBoundary"
    },
  )
}

///|
pub extend Predicate with Show::{to_string, output}

// Modified by ExampleLoom: shared instruction budget, absolute-position
// matching, fixed-width lookbehind, lookahead and bounded backreferences.

///|
pub suberror MatchLimit {
  MatchLimit
} derive(Debug)

///|
pub extend MatchLimit with Debug::{to_repr}

///|
pub(all) struct Budget {
  mut remaining : Int32
}

///|
fn tick(budget : Budget) -> Unit raise MatchLimit {
  budget.remaining -= 1
  if budget.remaining < 0 {
    raise MatchLimit
  }
}

///|
priv struct Thread {
  pc : Int32
  sp : Int32
  captures : Array[Int32]
}

///|
fn previous(input : StringView, offset : Int32, scalars : Int32) -> Int32? {
  let mut pos = offset
  for _ in 0..<scalars {
    if pos == 0 {
      return None
    }
    pos -= 1
    let u = input.code_unit_at(pos).to_int()
    if u >= 0xdc00 && u <= 0xdfff && pos > 0 {
      let hi = input.code_unit_at(pos - 1).to_int()
      if hi >= 0xd800 && hi <= 0xdbff {
        pos -= 1
      }
    }
  }
  Some(pos)
}

///|
fn add_thread(
  content : StringView,
  instructions : Array[Instruction],
  inst_gen : Array[Int32],
  thread : Thread,
  clist : Array[Thread],
  budget : Budget,
  depth : Int32,
) -> Unit raise MatchLimit {
  tick(budget)
  if inst_gen[thread.pc] == thread.sp {
    return
  }
  inst_gen[thread.pc] = thread.sp
  let next = fn(captures) raise MatchLimit {
    add_thread(
      content,
      instructions,
      inst_gen,
      { ..thread, pc: thread.pc + 1, captures, },
      clist,
      budget,
      depth,
    )
  }
  match instructions[thread.pc] {
    Reset(slots) => {
      for slot in slots {
        thread.captures[slot] = -1
      }
      next(thread.captures)
    }
    Save(i) => {
      thread.captures[i] = thread.sp
      next(thread.captures)
    }
    Jump(i) =>
      add_thread(
        content,
        instructions,
        inst_gen,
        { ..thread, pc: i, },
        clist,
        budget,
        depth,
      )
    Split(a, b) => {
      budget.remaining -= thread.captures.length()
      tick(budget)
      add_thread(
        content,
        instructions,
        inst_gen,
        { ..thread, pc: a, captures: thread.captures.copy(), },
        clist,
        budget,
        depth,
      )
      add_thread(
        content,
        instructions,
        inst_gen,
        { ..thread, pc: b, },
        clist,
        budget,
        depth,
      )
    }
    Assertion(pred) => {
      let sp = thread.sp
      let ok = match pred {
        BeginText => sp == 0
        EndText => sp == content.length()
        BeginLine => sp == 0 || content.code_unit_at(sp - 1) == (10 : UInt16)
        EndLine =>
          sp == content.length() || content.code_unit_at(sp) == (10 : UInt16)
        WordBoundary =>
          is_word_char_at(content, sp - 1) != is_word_char_at(content, sp)
        NoWordBoundary =>
          is_word_char_at(content, sp - 1) == is_word_char_at(content, sp)
      }
      if ok {
        next(thread.captures)
      }
    }
    Look(code, positive~, behind~) => {
      if depth >= 8 {
        raise MatchLimit
      }
      let start = match behind {
        None => Some(thread.sp)
        Some(n) => previous(content, thread.sp, n)
      }
      let found = match start {
        None => []
        Some(start) =>
          run(
            code,
            content,
            start,
            thread.captures.copy(),
            true,
            if behind is Some(_) {
              Some(thread.sp)
            } else {
              None
            },
            budget,
            depth + 1,
          )
      }
      if positive && !found.is_empty() {
        found[0] = thread.captures[0]
        found[1] = thread.captures[1]
        next(found)
      } else if !positive && found.is_empty() {
        next(thread.captures)
      }
    }
    Backreference(i) if thread.captures[i * 2] < 0 ||
      thread.captures[i * 2] == thread.captures[i * 2 + 1] =>
      next(thread.captures)
    _ => {
      if clist.length() >= 4096 {
        raise MatchLimit
      }
      clist.push(thread)
    }
  }
}

///|
fn run(
  instructions : Array[Instruction],
  input : StringView,
  start : Int32,
  initial : Array[Int32],
  backreferences : Bool,
  required_end : Int32?,
  budget : Budget,
  depth : Int32,
) -> Array[Int32] raise MatchLimit {
  let inst_gen = Array::make(instructions.length(), -1)
  let mut clist : Array[Thread] = []
  let mut nlist : Array[Thread] = []
  let mut matched : Array[Int32] = []
  add_thread(
    input,
    instructions,
    inst_gen,
    { sp: start, pc: 0, captures: initial, },
    clist,
    budget,
    depth,
  )
  for sp = start; sp <= input.length(); {
    tick(budget)
    if clist.is_empty() {
      break
    }
    let ch = input.get_char(sp)
    let next_sp = sp +
      (if ch is Some(c) && c.to_int() > 0xffff { 2 } else { 1 })
    for thread in clist {
      tick(budget)
      let { pc, captures, sp: thread_sp, } = thread
      if thread_sp > sp {
        nlist.push(thread)
        continue
      }
      if instructions[pc] is Matched {
        if required_end is None || required_end == Some(sp) {
          matched = captures
          break
        }
        continue
      }
      let generation = if backreferences {
        budget.remaining -= instructions.length()
        tick(budget)
        Array::make(instructions.length(), -1)
      } else {
        inst_gen
      }
      match instructions[pc] {
        Char(chars) =>
          if ch is Some(c) && char_in_ranges(c, chars) {
            add_thread(
              input,
              instructions,
              generation,
              { pc: pc + 1, captures, sp: next_sp, },
              nlist,
              budget,
              depth,
            )
          }
        Backreference(i) => {
          let a = captures[i * 2]
          let b = captures[i * 2 + 1]
          let end = sp + b - a
          if end <= input.length() && input[a:b] == input[sp:end] {
            add_thread(
              input,
              instructions,
              generation,
              { pc: pc + 1, captures, sp: end, },
              nlist,
              budget,
              depth,
            )
          }
        }
        _ => ()
      }
    }
    let tmp = clist
    clist = nlist
    nlist = tmp
    nlist.clear()
    continue next_sp
  }
  matched
}

///| Search without slicing the input: anchors, boundaries and lookbehind

///|
/// keep their original context during global iteration.
pub fn search(
  instructions : Array[Instruction],
  input : StringView,
  captures : Int32,
  from : Int32,
  backreferences : Bool,
  full : Bool,
  budget : Budget,
) -> Array[Int32] raise MatchLimit {
  run(
    instructions,
    input,
    from,
    Array::make(captures * 2, -1),
    backreferences,
    if full {
      Some(input.length())
    } else {
      None
    },
    budget,
    0,
  )
}
