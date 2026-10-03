# std/regex: regular expressions, written in Faxal.
#
#   import "std/regex" as re
#   re.test("[0-9]+", "room 42")                  # true
#   re.find("([a-z]+)@([a-z]+)", "hi bob@home")   # {text: "bob@home", start: 3, end: 11, groups: ["bob", "home"], named: {}}
#   re.find_all("[0-9]+", "1 22 333")             # [{...}, {...}, {...}]
#   re.replace("[aeiou]", "banana", "_")          # "b_n_n_"
#   re.split("[,;]", "a,b;c")                     # ["a", "b", "c"]
#
# Supported: literals, . [abc] [^abc] [a-z], \d \w \s \D \W \S \b \B, ^ $, ( ), (?: ), (?<name> ),
# alternation |, * + ? {n} {n,} {n,m} (add ? after any of them for the lazy form),
# lookahead (?= ) (?! ), and backreferences \1..\9. A flag string of "i" ignores case.
# Every function takes the pattern as a string or as the result of compile().
# Positions count characters, not bytes. A match is a map with text, start, end, groups and named.

let _DIGIT = [["0", "9"]]
let _WORD = [["a", "z"], ["A", "Z"], ["0", "9"], ["_", "_"]]
let _SPACE = [[" ", " "], ["\t", "\t"], ["\n", "\n"], ["\r", "\r"]]
let _INF = 1000000000

fn _fail(pattern, message) { throw "regex error: " + message + " in /" + pattern + "/" }

# ------------------------------------------------------------------ parser

fn _parse(pattern) {
  let src = pattern.chars()
  let n = len(src)
  let state = {pos: 0, groups: 0, names: {}}

  fn peek() { return state.pos < n and src[state.pos] or nil }
  fn eat(c) {
    if state.pos < n and src[state.pos] == c { state.pos += 1; return true }
    return false
  }

  fn class_escape(c) {
    if c == "d" { return {t: "set", neg: false, items: _DIGIT} }
    if c == "D" { return {t: "set", neg: true, items: _DIGIT} }
    if c == "w" { return {t: "set", neg: false, items: _WORD} }
    if c == "W" { return {t: "set", neg: true, items: _WORD} }
    if c == "s" { return {t: "set", neg: false, items: _SPACE} }
    if c == "S" { return {t: "set", neg: true, items: _SPACE} }
    return nil
  }

  fn literal_escape(c) {
    if c == "n" { return "\n" }
    if c == "t" { return "\t" }
    if c == "r" { return "\r" }
    return c
  }

  fn parse_set() {
    let neg = eat("^")
    let items = []
    let first = true
    while true {
      let c = peek()
      if c == nil { _fail(pattern, "unterminated [") }
      if c == "]" and not first { state.pos += 1; break }
      first = false
      state.pos += 1
      if c == "\\" {
        let e = peek()
        if e == nil { _fail(pattern, "trailing backslash") }
        state.pos += 1
        let cls = class_escape(e)
        if cls != nil {
          if cls.neg { _fail(pattern, "\\" + e + " can't be used inside [ ]") }
          for it in cls.items { items.push(it) }
          continue
        }
        c = literal_escape(e)
      }
      if peek() == "-" and state.pos + 1 < n and src[state.pos + 1] != "]" {
        state.pos += 1
        let hi = src[state.pos]
        state.pos += 1
        if hi == "\\" and state.pos < n { hi = literal_escape(src[state.pos]); state.pos += 1 }
        if hi < c { _fail(pattern, "bad range " + c + "-" + hi) }
        items.push([c, hi])
      } else {
        items.push([c, c])
      }
    }
    return {t: "set", neg: neg, items: items}
  }

  let parse_alt = nil

  fn parse_atom() {
    let c = src[state.pos]
    state.pos += 1
    if c == "." { return {t: "any"} }
    if c == "^" { return {t: "bol"} }
    if c == "$" { return {t: "eol"} }
    if c == "[" { return parse_set() }
    if c == "(" {
      let idx = nil
      let look = nil
      let name = nil
      let capture = true
      if eat("?") {
        if eat(":") {
          capture = false
        } else if eat("=") {
          look = "ahead"
        } else if eat("!") {
          look = "not"
        } else if eat("<") {
          name = ""
          while peek() != nil and peek() != ">" { name += src[state.pos]; state.pos += 1 }
          if not eat(">") or name == "" { _fail(pattern, "bad group name") }
        } else {
          _fail(pattern, "unknown group type (?" + (peek() ?? "") + ")")
        }
      }
      if look == nil and capture {
        state.groups += 1
        idx = state.groups
        if name != nil { state.names[name] = idx }
      }
      let inner = parse_alt()
      if not eat(")") { _fail(pattern, "missing )") }
      if look != nil { return {t: "look", node: inner, negate: look == "not"} }
      return {t: "group", node: inner, idx: idx}
    }
    if c == "\\" {
      let e = peek()
      if e == nil { _fail(pattern, "trailing backslash") }
      state.pos += 1
      let cls = class_escape(e)
      if cls != nil { return cls }
      if e == "b" { return {t: "wordb", negate: false} }
      if e == "B" { return {t: "wordb", negate: true} }
      if e >= "1" and e <= "9" { return {t: "ref", n: int(e)} }
      return {t: "char", c: literal_escape(e)}
    }
    if c == "*" or c == "+" or c == "?" { _fail(pattern, "nothing to repeat before " + c) }
    if c == ")" { _fail(pattern, "unmatched )") }
    return {t: "char", c: c}
  }

  fn parse_number() {
    let digits = ""
    while peek() != nil and peek() >= "0" and peek() <= "9" { digits += src[state.pos]; state.pos += 1 }
    if digits == "" { return nil }
    return int(digits)
  }

  fn parse_quantified() {
    let atom = parse_atom()
    while true {
      let c = peek()
      let lo = nil
      let hi = nil
      if c == "*" { lo = 0; hi = _INF; state.pos += 1 }
      else if c == "+" { lo = 1; hi = _INF; state.pos += 1 }
      else if c == "?" { lo = 0; hi = 1; state.pos += 1 }
      else if c == "{" {
        let save = state.pos
        state.pos += 1
        let a = parse_number()
        if a != nil {
          lo = a
          hi = a
          if eat(",") {
            let b = parse_number()
            hi = b ?? _INF
          }
        }
        if a == nil or not eat("}") {
          state.pos = save
          lo = nil
        }
        if lo != nil and hi < lo { _fail(pattern, "bad repeat count") }
        if lo == nil { break }
      } else { break }
      let lazy = eat("?")
      atom = {t: "rep", node: atom, min: lo, max: hi, lazy: lazy}
    }
    return atom
  }

  fn parse_seq() {
    let items = []
    while state.pos < n and peek() != "|" and peek() != ")" { items.push(parse_quantified()) }
    return {t: "seq", items: items}
  }

  parse_alt = fn() {
    let alts = [parse_seq()]
    while eat("|") { alts.push(parse_seq()) }
    return alts.len() == 1 and alts[0] or {t: "alt", alts: alts}
  }

  let tree = parse_alt()
  if state.pos < n { _fail(pattern, "unmatched )") }
  return {tree: tree, groups: state.groups, names: state.names}
}

# ----------------------------------------------------------------- matcher

fn _in_set(items, c) {
  for it in items {
    if c >= it[0] and c <= it[1] { return true }
  }
  return false
}

fn _is_word(c) { return _in_set(_WORD, c) }

# Tries to match at exactly position `start`. Returns the captures list [s0, e0, s1, e1, ...] or nil.
fn _match_at(re, cs, start, icase) {
  let n = len(cs)
  let caps = []
  for i in 0..(re.groups + 1) * 2 { caps.push(nil) }

  fn same(a, b) {
    if a == b { return true }
    return icase and a.lower() == b.lower()
  }

  fn in_set(node, c) {
    let hit = _in_set(node.items, c)
    if not hit and icase { hit = _in_set(node.items, c.lower()) or _in_set(node.items, c.upper()) }
    return hit != node.neg
  }

  let seq = nil
  let rep = nil

  fn m(node, i, k) {
    let t = node.t
    if t == "char" { return i < n and same(cs[i], node.c) and k(i + 1) }
    if t == "any" { return i < n and cs[i] != "\n" and k(i + 1) }
    if t == "set" { return i < n and in_set(node, cs[i]) and k(i + 1) }
    if t == "seq" { return seq(node.items, 0, i, k) }
    if t == "alt" {
      for a in node.alts {
        if m(a, i, k) { return true }
      }
      return false
    }
    if t == "rep" { return rep(node, 0, i, k) }
    if t == "group" {
      if node.idx == nil { return m(node.node, i, k) }
      let g = node.idx * 2
      return m(node.node, i, fn(j) {
        let old_start = caps[g]
        let old_end = caps[g + 1]
        caps[g] = i
        caps[g + 1] = j
        if k(j) { return true }
        caps[g] = old_start
        caps[g + 1] = old_end
        return false
      })
    }
    if t == "bol" { return i == 0 and k(i) }
    if t == "eol" { return i == n and k(i) }
    if t == "wordb" {
      let before = i > 0 and _is_word(cs[i - 1])
      let after = i < n and _is_word(cs[i])
      return ((before != after) != node.negate) and k(i)
    }
    if t == "look" {
      let saved = caps.copy()
      let found = m(node.node, i, fn(j) => true)
      if node.negate {
        for x in 0..len(caps) { caps[x] = saved[x] }
        return not found and k(i)
      }
      return found and k(i)
    }
    if t == "ref" {
      let g = node.n * 2
      if g + 1 >= len(caps) or caps[g] == nil { return false }
      let size = caps[g + 1] - caps[g]
      if i + size > n { return false }
      for x in 0..size {
        if not same(cs[i + x], cs[caps[g] + x]) { return false }
      }
      return k(i + size)
    }
    throw "regex: unknown node " + str(t)
  }

  seq = fn(items, idx, i, k) {
    if idx == len(items) { return k(i) }
    return m(items[idx], i, fn(j) => seq(items, idx + 1, j, k))
  }

  rep = fn(node, count, i, k) {
    let more = fn() {
      if count >= node.max { return false }
      return m(node.node, i, fn(j) {
        if j == i and count >= node.min { return false }
        return rep(node, count + 1, j, k)
      })
    }
    if count < node.min { return more() }
    if node.lazy { return k(i) or more() }
    return more() or k(i)
  }

  let end = nil
  if m(re.tree, start, fn(j) { end = j; return true }) {
    caps[0] = start
    caps[1] = end
    return caps
  }
  return nil
}

# --------------------------------------------------------------------- API

# Compiles a pattern once, to use it many times.
fn compile(pattern, flags = "") {
  if type(pattern) == "map" { return pattern }
  let parsed = _parse(pattern)
  return {pattern: pattern, tree: parsed.tree, groups: parsed.groups, names: parsed.names, icase: flags.contains("i")}
}

fn _slice(cs, a, b) {
  let out = ""
  for i in a..b { out += cs[i] }
  return out
}

fn _build(re, cs, caps) {
  let groups = []
  for g in 1..re.groups + 1 {
    if caps[g * 2] == nil { groups.push(nil) } else { groups.push(_slice(cs, caps[g * 2], caps[g * 2 + 1])) }
  }
  let named = {}
  for name in re.names.keys() { named[name] = groups[re.names[name] - 1] }
  return {text: _slice(cs, caps[0], caps[1]), start: caps[0], end: caps[1], groups: groups, named: named}
}

fn _search(re, cs, from) {
  for i in from..len(cs) + 1 {
    let caps = _match_at(re, cs, i, re.icase)
    if caps != nil { return caps }
  }
  return nil
}

# The first match anywhere in the text, or nil.
fn find(pattern, text, flags = "") {
  let re = compile(pattern, flags)
  let cs = text.chars()
  let caps = _search(re, cs, 0)
  if caps == nil { return nil }
  return _build(re, cs, caps)
}

# A match only if the pattern matches the whole text.
fn full_match(pattern, text, flags = "") {
  let re = compile(pattern, flags)
  let cs = text.chars()
  let caps = _match_at({tree: {t: "seq", items: [re.tree, {t: "eol"}]}, groups: re.groups, names: re.names, icase: re.icase}, cs, 0, re.icase)
  if caps == nil { return nil }
  return _build(re, cs, caps)
}

fn test(pattern, text, flags = "") { return find(pattern, text, flags) != nil }

fn find_all(pattern, text, flags = "") {
  let re = compile(pattern, flags)
  let cs = text.chars()
  let found = []
  let pos = 0
  while pos <= len(cs) {
    let caps = _search(re, cs, pos)
    if caps == nil { break }
    found.push(_build(re, cs, caps))
    pos = caps[1] > caps[0] and caps[1] or caps[1] + 1
  }
  return found
}

fn _expand(repl, m) {
  if type(repl) == "function" { return str(repl(m)) }
  let out = ""
  let chars = repl.chars()
  let i = 0
  while i < len(chars) {
    let c = chars[i]
    if c == "$" and i + 1 < len(chars) and chars[i + 1] >= "0" and chars[i + 1] <= "9" {
      let g = int(chars[i + 1])
      let value = g == 0 and m.text or m.groups[g - 1]
      out += value ?? ""
      i += 2
    } else if c == "$" and i + 1 < len(chars) and chars[i + 1] == "$" {
      out += "$"
      i += 2
    } else {
      out += c
      i += 1
    }
  }
  return out
}

# Replaces every match. `repl` is a string ($1 is group 1, $0 the whole match, $$ a dollar sign) or a function(match).
fn replace(pattern, text, repl, flags = "") {
  let re = compile(pattern, flags)
  let cs = text.chars()
  let out = ""
  let pos = 0
  let copied = 0
  while pos <= len(cs) {
    let caps = _search(re, cs, pos)
    if caps == nil { break }
    out += _slice(cs, copied, caps[0]) + _expand(repl, _build(re, cs, caps))
    copied = caps[1]
    pos = caps[1] > caps[0] and caps[1] or caps[1] + 1
    if caps[1] == caps[0] and caps[0] < len(cs) {
      out += cs[caps[0]]
      copied = caps[0] + 1
    }
  }
  return out + _slice(cs, copied, len(cs))
}

fn replace_first(pattern, text, repl, flags = "") {
  let re = compile(pattern, flags)
  let cs = text.chars()
  let caps = _search(re, cs, 0)
  if caps == nil { return text }
  return _slice(cs, 0, caps[0]) + _expand(repl, _build(re, cs, caps)) + _slice(cs, caps[1], len(cs))
}

fn split(pattern, text, flags = "") {
  let re = compile(pattern, flags)
  let cs = text.chars()
  let parts = []
  let last = 0
  let pos = 0
  while pos <= len(cs) {
    let caps = _search(re, cs, pos)
    if caps == nil { break }
    if caps[1] == caps[0] {
      pos = caps[1] + 1
      if caps[0] == 0 or caps[0] >= len(cs) { continue }
    } else {
      pos = caps[1]
    }
    parts.push(_slice(cs, last, caps[0]))
    last = caps[1]
  }
  parts.push(_slice(cs, last, len(cs)))
  return parts
}

# Escapes every special character, so the text can be used as a literal inside a pattern.
fn escape(text) {
  let out = ""
  for c in text.chars() {
    if "\\.^$|?*+()[]{}".contains(c) { out += "\\" }
    out += c
  }
  return out
}
