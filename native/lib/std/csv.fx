# std/csv: read and write comma-separated values, written in Faxal.
#
#   import "std/csv" as csv
#   let rows = csv.parse("name,age\nada,36\n\"Lee, Bo\",41")   # [["name","age"],["ada","36"],["Lee, Bo","41"]]
#   let people = csv.records(text)                              # [{name: "ada", age: "36"}, ...] using the first row as names
#   print(csv.stringify(rows))                                  # quotes fields only when needed
#
# Fields are always strings. Quoted fields may contain the separator, quotes ("" is one quote) and newlines.

fn parse(text, sep = ",") {
  let rows = []
  let row = []
  let field = ""
  let quoted = false
  let was_quoted = false
  let chars = text.chars()
  let n = len(chars)
  let i = 0
  while i < n {
    let c = chars[i]
    if quoted {
      if c == "\"" {
        if i + 1 < n and chars[i + 1] == "\"" { field += "\""; i += 1 } else { quoted = false }
      } else { field += c }
    } else if c == "\"" and field == "" {
      quoted = true
      was_quoted = true
    } else if c == sep {
      row.push(field)
      field = ""
      was_quoted = false
    } else if c == "\n" or c == "\r" {
      if c == "\r" and i + 1 < n and chars[i + 1] == "\n" { i += 1 }
      row.push(field)
      rows.push(row)
      row = []
      field = ""
      was_quoted = false
    } else {
      field += c
    }
    i += 1
  }
  if quoted { throw "csv: a quoted field is never closed" }
  if field != "" or was_quoted or len(row) > 0 {
    row.push(field)
    rows.push(row)
  }
  return rows
}

# The first row names the columns; every other row becomes a map.
fn records(text, sep = ",") {
  let rows = parse(text, sep)
  if len(rows) == 0 { return [] }
  let names = rows[0]
  let out = []
  for r in rows[1:] {
    let rec = {}
    for i in 0..len(names) { rec[names[i]] = i < len(r) and r[i] or nil }
    out.push(rec)
  }
  return out
}

fn _field(value, sep) {
  let s = value == nil and "" or str(value)
  if s.contains(sep) or s.contains("\"") or s.contains("\n") or s.contains("\r") { return "\"" + s.replace("\"", "\"\"") + "\"" }
  return s
}

fn stringify(rows, sep = ",") {
  let lines = []
  for r in rows { lines.push(r.map(fn(v) => _field(v, sep)).join(sep)) }
  return lines.join("\n") + "\n"
}
