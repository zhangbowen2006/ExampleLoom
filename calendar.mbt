///|
/// Accepted date formats have an explicit day/month order and four-digit years.
pub fn date_formats() -> Array[String] {
  ["YYYY-MM-DD", "YYYY/MM/DD", "YYYYMMDD", "DD/MM/YYYY", "MM/DD/YYYY"]
}

///|
fn decimal_at(
  chars : Array[Char],
  a : Int32,
  b : Int32,
) -> Int32 raise LoomError {
  let mut n = 0
  for i in a..<b {
    if !chars[i].is_ascii_digit() {
      raise LoomError("date contains non-digit")
    }
    n = n * 10 + chars[i].to_int() - 48
  }
  n
}

///|
/// Calendar validation is Gregorian and rejects impossible or ambiguous formats.
pub fn convert_date(
  text : String,
  source : String,
  target : String,
) -> String raise LoomError {
  let c = text.to_array()
  let (year, month, day) = match source {
    "YYYYMMDD" => {
      if c.length() != 8 {
        raise LoomError("date length does not match YYYYMMDD")
      }
      (decimal_at(c, 0, 4), decimal_at(c, 4, 6), decimal_at(c, 6, 8))
    }
    "YYYY-MM-DD" | "YYYY/MM/DD" => {
      let separator = if source == "YYYY-MM-DD" { '-' } else { '/' }
      if c.length() != 10 || c[4] != separator || c[7] != separator {
        raise LoomError("date does not match declared format")
      }
      (decimal_at(c, 0, 4), decimal_at(c, 5, 7), decimal_at(c, 8, 10))
    }
    "DD/MM/YYYY" | "MM/DD/YYYY" => {
      if c.length() != 10 || c[2] != '/' || c[5] != '/' {
        raise LoomError("date does not match declared format")
      }
      let a = decimal_at(c, 0, 2)
      let b = decimal_at(c, 3, 5)
      (
        decimal_at(c, 6, 10),
        if source == "DD/MM/YYYY" {
          b
        } else {
          a
        },
        if source == "DD/MM/YYYY" {
          a
        } else {
          b
        },
      )
    }
    _ => raise LoomError("unsupported source date format")
  }
  if year < 1 || month < 1 || month > 12 {
    raise LoomError("invalid calendar date")
  }
  let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
  let days = [
    31,
    if leap {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  if day < 1 || day > days[month - 1] {
    raise LoomError("invalid calendar date")
  }
  let y = year.to_string().pad_start(4, '0')
  let m = month.to_string().pad_start(2, '0')
  let d = day.to_string().pad_start(2, '0')
  match target {
    "YYYY-MM-DD" => "\{y}-\{m}-\{d}"
    "YYYY/MM/DD" => "\{y}/\{m}/\{d}"
    "YYYYMMDD" => "\{y}\{m}\{d}"
    "DD/MM/YYYY" => "\{d}/\{m}/\{y}"
    "MM/DD/YYYY" => "\{m}/\{d}/\{y}"
    _ => raise LoomError("unsupported target date format")
  }
}
