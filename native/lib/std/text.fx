# std/text: text helpers, written in Faxal.

fn pad_left(s, width, fill = " ") {
  s = str(s)
  if len(s) >= width { return s }
  return fill * (width - len(s)) + s
}

fn pad_right(s, width, fill = " ") {
  s = str(s)
  if len(s) >= width { return s }
  return s + fill * (width - len(s))
}

fn center(s, width, fill = " ") {
  s = str(s)
  if len(s) >= width { return s }
  let total = width - len(s)
  let left = floor(total / 2)
  return fill * left + s + fill * (total - left)
}

fn capitalize(s) {
  if len(s) == 0 { return s }
  return s[0].upper() + s[1:].lower()
}

# "hello big world" becomes "Hello Big World"
fn title(s) {
  return s.split(" ").map(fn(w) { return capitalize(w) }).join(" ")
}

fn reverse(s) {
  return s.chars().reverse().join("")
}

fn is_digit(s) {
  if len(s) == 0 { return false }
  for c in s { if c < "0" or c > "9" { return false } }
  return true
}

fn is_alpha(s) {
  if len(s) == 0 { return false }
  for c in s {
    if not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z")) { return false }
  }
  return true
}

# The words in a text, ignoring any amount of spaces, tabs and new lines.
fn words(s) {
  let cleaned = s.replace("\n", " ").replace("\t", " ").replace("\r", " ")
  return cleaned.split(" ").filter(fn(w) { return len(w) > 0 })
}

# Cuts a text down to at most n characters, ending with "..." when it was shortened.
fn truncate(s, n, ending = "...") {
  if len(s) <= n { return s }
  return s[:max(0, n - len(ending))] + ending
}

fn starts_with_any(s, prefixes) {
  for p in prefixes { if s.starts_with(p) { return true } }
  return false
}

# Breaks a text into lines of at most `width` characters, at word boundaries.
fn wrap(s, width) {
  let lines = []
  let line = ""
  for w in words(s) {
    if line == "" { line = w }
    else if len(line) + 1 + len(w) <= width { line = line + " " + w }
    else {
      lines.push(line)
      line = w
    }
  }
  if line != "" { lines.push(line) }
  return lines
}

# A number with a fixed number of decimals: fixed(3.14159, 2) is "3.14"
fn fixed(n, decimals = 2) {
  let scale = 10 ** decimals
  let r = round(abs(n) * scale)
  let whole = floor(r / scale)
  let text = str(whole)
  if decimals > 0 {
    text = text + "." + pad_left(str(r - whole * scale), decimals, "0")
  }
  if n < 0 and r != 0 { return "-" + text }
  return text
}

# Thousands separators: commas(1234567) is "1,234,567"
fn commas(n) {
  let sign = n < 0 and "-" or ""
  let digits = str(floor(abs(n)))
  let out = ""
  let count = 0
  for i in 0..len(digits) {
    let c = digits[len(digits) - 1 - i]
    if count > 0 and count % 3 == 0 { out = "," + out }
    out = c + out
    count += 1
  }
  return sign + out
}
