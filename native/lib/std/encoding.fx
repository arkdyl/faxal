# std/encoding: base64, hex, URL and HTML encoding, written in Faxal.
#
#   import "std/encoding" as enc
#   enc.base64_encode("hello")          # "aGVsbG8="
#   enc.base64_decode("aGVsbG8=")       # "hello"
#   enc.hex_encode("hi")                # "6869"
#   enc.url_encode("a b&c=é")           # "a%20b%26c%3D%C3%A9"
#   enc.url_decode("a%20b+c")           # "a b c"
#   enc.html_escape("<b>&</b>")         # "&lt;b&gt;&amp;&lt;/b&gt;"
#
# Text is handled as bytes (UTF-8), so any text round-trips.

let _B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
let _HEX = "0123456789abcdef"

fn base64_encode(text) {
  let bytes = text.bytes()
  let out = []
  let i = 0
  while i < len(bytes) {
    let a = bytes[i]
    let b = i + 1 < len(bytes) and bytes[i + 1] or 0
    let c = i + 2 < len(bytes) and bytes[i + 2] or 0
    let n = a * 65536 + b * 256 + c
    out.push(_B64[math.floor(n / 262144) % 64])
    out.push(_B64[math.floor(n / 4096) % 64])
    out.push(i + 1 < len(bytes) and _B64[math.floor(n / 64) % 64] or "=")
    out.push(i + 2 < len(bytes) and _B64[n % 64] or "=")
    i += 3
  }
  return out.join("")
}

fn base64_decode(text) {
  let bytes = []
  let acc = 0
  let bits = 0
  for c in text.chars() {
    if c == "=" or c == "\n" or c == "\r" or c == " " { continue }
    let v = _B64.find(c)
    if v < 0 {
      if c == "-" { v = 62 } else if c == "_" { v = 63 } else { throw "base64_decode: bad character " + repr(c) }
    }
    acc = acc * 64 + v
    bits += 6
    if bits >= 8 {
      bits -= 8
      let div = math.pow(2, bits)
      bytes.push(math.floor(acc / div) % 256)
      acc = acc % div
    }
  }
  return from_bytes(bytes)
}

fn hex_encode(text) {
  let out = []
  for b in text.bytes() { out.push(_HEX[math.floor(b / 16)] + _HEX[b % 16]) }
  return out.join("")
}

fn hex_decode(text) {
  if len(text) % 2 != 0 { throw "hex_decode: odd number of digits" }
  let bytes = []
  let i = 0
  while i < len(text) {
    let hi = _HEX.find(text[i].lower())
    let lo = _HEX.find(text[i + 1].lower())
    if hi < 0 or lo < 0 { throw "hex_decode: bad digit near " + repr(text[i:i + 2]) }
    bytes.push(hi * 16 + lo)
    i += 2
  }
  return from_bytes(bytes)
}

let _SAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"

fn url_encode(text) {
  let out = []
  for b in text.bytes() {
    let c = chr(b)
    if b < 128 and _SAFE.contains(c) { out.push(c) }
    else { out.push("%" + _HEX[math.floor(b / 16)].upper() + _HEX[b % 16].upper()) }
  }
  return out.join("")
}

# "+" means a space (as in HTML forms) unless plus = false
fn url_decode(text, plus = true) {
  let bytes = []
  let raw = text.bytes()
  let i = 0
  while i < len(raw) {
    let b = raw[i]
    if b == 37 and i + 2 < len(raw) {
      let hi = _HEX.find(chr(raw[i + 1]).lower())
      let lo = _HEX.find(chr(raw[i + 2]).lower())
      if hi >= 0 and lo >= 0 { bytes.push(hi * 16 + lo); i += 3; continue }
    }
    bytes.push(plus and b == 43 and 32 or b)
    i += 1
  }
  return from_bytes(bytes)
}

fn html_escape(text) {
  return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")
}
