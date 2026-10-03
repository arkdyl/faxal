# std/lex: a tokenizer for Faxal source code, written in Faxal.
#
# tokenize(source) returns a list of tokens. Every token is a map:
#   kind  "ident" "keyword" "number" "string" "fstring" "op" "punct" "comment" "error" or "eof"
#   text  exactly the characters of the token
#   line  the line it starts on (the first line is 1)
#   nl    how many line breaks come right before it (0 means "same line as the token before")
#   sp    true if spaces or tabs came right before it on the same line
#   col   the column it starts at (the first column is 1)
#   pos   the byte offset where it starts
#   open  (strings only) true if the string was never closed

let KEYWORDS = [
  "let", "fn", "if", "else", "while", "for", "in", "break", "continue", "return",
  "true", "false", "nil", "and", "or", "not", "try", "catch", "throw", "import",
  "class", "extends", "self", "super", "by", "async", "await",
]
let TWO_CHAR_OPS = ["**", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "..", "|>", "??", "?.", "=>", "->"]
let ONE_CHAR_OPS = "+-*/%<>="
let PUNCTUATION = "(){}[],:;."

fn _is_digit(c) { return c >= "0" and c <= "9" }
fn _is_hex(c) { return _is_digit(c) or (c >= "a" and c <= "f") or (c >= "A" and c <= "F") }
# letters, underscore and any non-ASCII byte
fn _is_alpha(c) { return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c > "~" }

fn _scan_number(src, i, n) {
  if src[i] == "0" and i + 2 < n and (src[i + 1] == "x" or src[i + 1] == "X") and _is_hex(src[i + 2]) {
    i += 2
    while i < n and (_is_hex(src[i]) or src[i] == "_") { i += 1 }
    return i
  }
  while i < n and (_is_digit(src[i]) or src[i] == "_") { i += 1 }
  if i + 1 < n and src[i] == "." and _is_digit(src[i + 1]) {
    i += 1
    while i < n and (_is_digit(src[i]) or src[i] == "_") { i += 1 }
  }
  if i < n and (src[i] == "e" or src[i] == "E") {
    let j = i + 1
    if j < n and (src[j] == "-" or src[j] == "+") { j += 1 }
    if j < n and _is_digit(src[j]) {
      i = j
      while i < n and _is_digit(src[i]) { i += 1 }
    }
  }
  return i
}

# Set by _scan_string: true when the last string it scanned had no closing quote.
let _scan = {unterminated: false}

# `i` is the position of the opening quote; returns the position after the closing one.
fn _scan_string(src, i, n, interpolated) {
  let quote = src[i]
  i += 1
  let depth = 0
  _scan.unterminated = false
  while i < n {
    let c = src[i]
    if c == quote and depth == 0 { return i + 1 }
    if c == "\\" and i + 1 < n {
      i += 2
      continue
    }
    if interpolated {
      if c == "{" { depth += 1 }
      else if c == "}" and depth > 0 { depth -= 1 }
      else if (c == "\"" or c == "'") and depth > 0 {
        let inner = c
        i += 1
        while i < n and src[i] != inner {
          if src[i] == "\\" and i + 1 < n { i += 1 }
          i += 1
        }
      }
    }
    i += 1
  }
  _scan.unterminated = true
  return n
}

fn tokenize(src) {
  let tokens = []
  let n = len(src)
  let i = 0
  let line = 1
  let line_start = 0
  let nl = 0
  let sp = false
  while i < n {
    let c = src[i]
    if c == "\n" {
      nl += 1
      line += 1
      line_start = i + 1
      sp = false
      i += 1
      continue
    }
    if c == " " or c == "\t" or c == "\r" {
      sp = true
      i += 1
      continue
    }

    let start = i
    let open = false
    let kind = "op"
    if c == "#" {
      kind = "comment"
      while i < n and src[i] != "\n" { i += 1 }
    } else if _is_digit(c) {
      kind = "number"
      i = _scan_number(src, i, n)
    } else if _is_alpha(c) {
      i += 1
      while i < n and (_is_alpha(src[i]) or _is_digit(src[i])) { i += 1 }
      let word = src[start:i]
      if word == "f" and i < n and (src[i] == "\"" or src[i] == "'") {
        kind = "fstring"
        i = _scan_string(src, i, n, true)
        open = _scan.unterminated
      } else if KEYWORDS.contains(word) {
        kind = "keyword"
      } else {
        kind = "ident"
      }
    } else if c == "\"" or c == "'" {
      kind = "string"
      i = _scan_string(src, i, n, false)
      open = _scan.unterminated
    } else {
      if TWO_CHAR_OPS.contains(src[i:i + 2]) { i += 2 } else { i += 1 }
      let text = src[start:i]
      if len(text) == 1 and PUNCTUATION.contains(text) { kind = "punct" }
      else if len(text) == 2 or ONE_CHAR_OPS.contains(text) { kind = "op" }
      else { kind = "error" }
    }

    let text = src[start:i]
    tokens.push({kind: kind, text: text, line: line, nl: nl, sp: sp, col: start - line_start + 1, pos: start, open: open})
    let breaks = text.count("\n")
    if breaks > 0 {
      line += breaks
      line_start = start + text.find("\n") + 1
      let last_break = text.find("\n")
      while last_break >= 0 {
        line_start = start + last_break + 1
        last_break = text.find("\n", last_break + 1)
      }
    }
    nl = 0
    sp = false
  }
  tokens.push({kind: "eof", text: "", line: line, nl: nl, sp: false, col: n - line_start + 1, pos: n, open: false})
  return tokens
}
