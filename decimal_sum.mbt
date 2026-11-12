///|
priv struct ExactDecimal {
  negative : Bool
  digits : Array[Int32] // little endian coefficient, no floating point
  scale : Int32
}

///|
fn exact_decimal(order : DecimalOrder) -> ExactDecimal {
  {
    negative: order.negative,
    digits: (order.whole + order.fraction).map(c => c.to_int() - 48).rev(),
    scale: order.fraction.length(),
  }
}

///|
fn add_decimal(
  a : ExactDecimal,
  b : ExactDecimal,
) -> ExactDecimal raise LoomError {
  let scale = Int32::max(a.scale, b.scale)
  let x = Array::make(scale - a.scale, 0) + a.digits
  let y = Array::make(scale - b.scale, 0) + b.digits
  let width = Int32::max(x.length(), y.length())
  while x.length() < width {
    x.push(0)
  }
  while y.length() < width {
    y.push(0)
  }
  let digits : Array[Int32] = []
  let mut negative = a.negative
  if a.negative == b.negative {
    let mut carry = 0
    for i in 0..<width {
      let n = x[i] + y[i] + carry
      digits.push(n % 10)
      carry = n / 10
    }
    if carry > 0 {
      digits.push(carry)
    }
  } else {
    let mut order = 0
    for i = width - 1; i >= 0; i = i - 1 {
      if x[i] != y[i] {
        order = x[i] - y[i]
        break
      }
    }
    let (large, small) = if order < 0 { (y, x) } else { (x, y) }
    negative = if order < 0 { b.negative } else { a.negative }
    let mut borrow = 0
    for i in 0..<width {
      let n = large[i] - small[i] - borrow
      digits.push(if n < 0 { n + 10 } else { n })
      borrow = if n < 0 { 1 } else { 0 }
    }
  }
  while digits.length() > 1 && digits[digits.length() - 1] == 0 {
    ignore(digits.pop())
  }
  if digits.length() > 1024 {
    raise LoomError("decimal sum exceeds 1024 coefficient digits")
  }
  if digits.all(d => d == 0) {
    negative = false
  }
  { negative, digits, scale, }
}

///|
fn decimal_text(value : ExactDecimal) -> String {
  if value.digits.all(d => d == 0) {
    return "0"
  }
  let digits = value.digits.copy()
  while digits.length() <= value.scale {
    digits.push(0)
  }
  let text = digits.rev().map(d => d.to_string()).join("")
  let point = text.length() - value.scale
  let mut end = text.length()
  while end > point && text[end - 1:end] == "0" {
    end -= 1
  }
  (if value.negative { "-" } else { "" }) +
  text[:point].to_owned() +
  (if end > point { "." + text[point:end].to_owned() } else { "" })
}

///|
fn decimal_group_values(
  table : Table,
  groups : Groups,
  column : String,
  kind : String,
) -> Array[String] raise LoomError {
  let index = column_index(table, column)
  let sums = Array::makei(groups.keys.length(), _ => ExactDecimal::{
    negative: false,
    digits: [0],
    scale: 0,
  })
  let extremes : Array[DecimalOrder?] = Array::make(groups.keys.length(), None)
  let present = Array::make(groups.keys.length(), false)
  for i, row in table.rows {
    let value = decimal_order(row[index]) catch {
      LoomError(s) => raise LoomError("row \{i+1}, column \{column}: \{s}")
    }
    let group = groups.membership[i]
    if kind == "sum" {
      sums[group] = add_decimal(sums[group], exact_decimal(value))
    } else {
      match extremes[group] {
        None => extremes[group] = Some(value)
        Some(previous) => {
          let order = compare_decimal(value, previous)
          if (kind == "min" && order < 0) || (kind == "max" && order > 0) {
            extremes[group] = Some(value)
          }
        }
      }
    }
    present[group] = true
  }
  Array::makei(groups.keys.length(), i => {
    if !present[i] {
      ""
    } else if kind == "sum" {
      decimal_text(sums[i])
    } else {
      match extremes[i] {
        None => ""
        Some(v) => decimal_text(exact_decimal(v))
      }
    }
  })
}
