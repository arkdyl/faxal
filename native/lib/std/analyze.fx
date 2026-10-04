# std/analyze: finds the names in Faxal code and what they refer to, written in Faxal.
# The language server (faxal lsp) uses it for go to definition, find references and rename.
#
#   import "std/analyze" as an
#   let a = an.analyze(source)
#   a.decls   every declaration: {id, name, kind, line, col, tok, detail, params, member, path}
#   a.refs    every use of a name: {name, line, col, tok, decl, member, after}
#   a.toks    the tokens (comments left out); line and col start at 1
#
# kind is "variable", "function", "class", "param", "loop", "catch", "module" or "method".
# A use inside a scope refers to the nearest declaration of the same name that is visible there (decl is its id,
# or nil for built-ins and globals that are not declared in this file). "member" uses come after a dot
# (obj.name): they are matched by name only, so `after` holds the name before the dot (a module alias, say).
# Columns count bytes, not characters.

import "std/lex" as lex

let _OPENERS = {"(": ")", "[": "]", "{": "}"}

# For every opening bracket, where its closing bracket is.
fn _match_brackets(toks) {
  let close_of = {}
  let stack = []
  for i in 0..len(toks) {
    let t = toks[i]
    if t.kind == "punct" and _OPENERS.has(t.text) { stack.push(i) }
    else if t.kind == "punct" and (t.text == ")" or t.text == "]" or t.text == "}") {
      if len(stack) > 0 { close_of[stack.pop()] = i }
    }
  }
  for i in stack { close_of[i] = len(toks) - 1 }
  return close_of
}

fn _is_punct(t, text) => t.kind == "punct" and t.text == text
fn _is_op(t, text) => t.kind == "op" and t.text == text

# Where the body of an arrow function ends: before the first token on a new line or a closing bracket at the same depth.
fn _arrow_end(toks, start, close_of) {
  let i = start
  while i < len(toks) {
    let t = toks[i]
    if t.kind == "eof" { return i - 1 }
    if i > start and t.nl > 0 { return i - 1 }
    if t.kind == "punct" and (t.text == ")" or t.text == "]" or t.text == "}" or t.text == ",") { return i - 1 }
    if t.kind == "punct" and _OPENERS.has(t.text) { i = close_of.get(i, i) }
    i += 1
  }
  return len(toks) - 1
}

# The signature text and parameter names of a function whose "(" is at toks[open]: ["(a, b = 2)", ["a", "b"], close_index]
fn _read_params(toks, open, close_of) {
  let close = close_of.get(open, open)
  let names = []
  let text = "("
  let expect_name = true
  let depth = 0
  for i in open + 1..close {
    let t = toks[i]
    if t.kind == "punct" and _OPENERS.has(t.text) { depth += 1 }
    else if t.kind == "punct" and (t.text == ")" or t.text == "]" or t.text == "}") { depth -= 1 }
    if depth == 0 and expect_name and t.kind == "ident" {
      names.push(t.text)
      expect_name = false
    } else if depth == 0 and _is_punct(t, ",") {
      expect_name = true
    }
    if _is_punct(t, ",") { text += ", " }
    else if _is_punct(t, ":") { text += ": " }
    else if t.kind == "op" and (t.text == "=" or t.text == "->") { text += " " + t.text + " " }
    else if t.kind == "keyword" and t.text == "or" { text += " or " }
    else { text += t.text }
  }
  return [text + ")", names, close]
}

fn analyze(source) {
  let all = lex.tokenize(source)
  let toks = all.filter(fn(t) => t.kind != "comment")
  let close_of = _match_brackets(toks)
  let decls = []
  let refs = []
  let scopes = [{end: len(toks), names: {}, class_body: false}]
  let class_bodies = {}          # token index of a class body's "{"
  let skip = {}                  # token indexes that are declarations or keys, not uses
  let n = len(toks)

  fn declare(name_tok_index, kind, detail, params, member) {
    let t = toks[name_tok_index]
    let id = len(decls)
    decls.push({id: id, name: t.text, kind: kind, line: t.line, col: t.col, tok: name_tok_index, detail: detail, params: params, member: member, path: nil})
    skip[name_tok_index] = true
    if not member { scopes[-1].names[t.text] = id }
    return id
  }

  fn lookup(name) {
    let i = len(scopes) - 1
    while i >= 0 {
      let found = scopes[i].names.get(name)
      if found != nil { return found }
      i -= 1
    }
    return nil
  }

  let i = 0
  while i < n {
    while len(scopes) > 1 and i > scopes[-1].end { scopes.pop() }
    let t = toks[i]
    if t.kind == "eof" { break }

    if t.kind == "punct" and t.text == "{" {
      scopes.push({end: close_of.get(i, n), names: {}, class_body: class_bodies.has(i)})
    } else if t.kind == "keyword" and t.text == "let" and i + 1 < n and toks[i + 1].kind == "ident" {
      declare(i + 1, "variable", "variable", nil, false)
      i += 2
      continue
    } else if t.kind == "keyword" and t.text == "class" and i + 1 < n and toks[i + 1].kind == "ident" {
      declare(i + 1, "class", "class " + toks[i + 1].text, nil, false)
      let j = i + 2
      while j < n and not _is_punct(toks[j], "{") and toks[j].kind != "eof" { j += 1 }
      if j < n { class_bodies[j] = true }
      i += 2
      continue
    } else if t.kind == "keyword" and t.text == "fn" {
      let named = i + 1 < n and toks[i + 1].kind == "ident"
      let open = named and i + 2 or i + 1
      let method = named and scopes[-1].class_body
      let name_index = i + 1
      if open < n and _is_punct(toks[open], "(") {
        let read = _read_params(toks, open, close_of)
        let after = read[2] + 1
        let end = after
        if after < n and _is_op(toks[after], "->") {
          # skip the return type: names and "or"
          end = after + 1
          while end < n and (toks[end].kind == "ident" or (toks[end].kind == "keyword" and (toks[end].text == "or" or toks[end].text == "nil" or toks[end].text == "fn"))) { end += 1 }
          after = end
        }
        let body_end = after
        if after < n and _is_op(toks[after], "=>") { body_end = _arrow_end(toks, after + 1, close_of) }
        else if after < n and _is_punct(toks[after], "{") { body_end = close_of.get(after, n) }
        if named {
          declare(name_index, method and "method" or "function", "fn " + toks[name_index].text + read[0], read[1], method)
        }
        scopes.push({end: body_end, names: {}, class_body: false})
        # parameters
        let depth = 0
        let expect = true
        for k in open + 1..read[2] {
          let p = toks[k]
          if p.kind == "punct" and _OPENERS.has(p.text) { depth += 1 }
          else if p.kind == "punct" and (p.text == ")" or p.text == "]" or p.text == "}") { depth -= 1 }
          if depth == 0 and expect and p.kind == "ident" {
            declare(k, "param", "parameter of " + (named and toks[name_index].text or "a function"), nil, false)
            expect = false
          } else if depth == 0 and _is_punct(p, ",") { expect = true }
        }
        i = open + 1
        # the parameter list itself is scanned for uses (defaults), but not the declared names
        continue
      }
    } else if t.kind == "keyword" and t.text == "for" and i + 1 < n and toks[i + 1].kind == "ident" {
      let j = i + 2
      let body_end = n
      let depth = 0
      while j < n {
        if toks[j].kind == "punct" and (toks[j].text == "(" or toks[j].text == "[") { depth += 1 }
        else if toks[j].kind == "punct" and (toks[j].text == ")" or toks[j].text == "]") { depth -= 1 }
        else if depth == 0 and _is_punct(toks[j], "{") { body_end = close_of.get(j, n); break }
        j += 1
      }
      scopes.push({end: body_end, names: {}, class_body: false})
      declare(i + 1, "loop", "loop variable", nil, false)
      i += 2
      continue
    } else if t.kind == "keyword" and t.text == "catch" and i + 1 < n and toks[i + 1].kind == "ident" {
      let j = i + 2
      let body_end = j < n and _is_punct(toks[j], "{") and close_of.get(j, n) or n
      scopes.push({end: body_end, names: {}, class_body: false})
      declare(i + 1, "catch", "caught error", nil, false)
      i += 2
      continue
    } else if t.kind == "keyword" and t.text == "import" and i + 1 < n and toks[i + 1].kind == "string" {
      let path_text = toks[i + 1].text[1:len(toks[i + 1].text) - 1]
      let alias = nil
      if i + 3 < n and toks[i + 2].kind == "ident" and toks[i + 2].text == "as" and toks[i + 3].kind == "ident" {
        alias = i + 3
      }
      if alias != nil {
        let id = declare(alias, "module", "module " + path_text, nil, false)
        decls[id].path = path_text
        i = alias + 1
        continue
      }
      i += 2
      continue
    } else if t.kind == "ident" and not skip.has(i) {
      let prev = i > 0 and toks[i - 1] or nil
      let member = prev != nil and ((prev.kind == "punct" and prev.text == ".") or (prev.kind == "op" and prev.text == "?."))
      let nxt = i + 1 < n and toks[i + 1] or nil
      let is_key = nxt != nil and _is_punct(nxt, ":") and prev != nil and (_is_punct(prev, "{") or _is_punct(prev, ","))
      let is_named_arg = nxt != nil and _is_op(nxt, "=") and prev != nil and (_is_punct(prev, "(") or _is_punct(prev, ","))
      if not is_key and not is_named_arg {
        let before = nil
        if member and i >= 2 and toks[i - 2].kind == "ident" { before = toks[i - 2].text }
        let target = nil
        if not member { target = lookup(t.text) }
        refs.push({name: t.text, line: t.line, col: t.col, tok: i, decl: target, member: member, after: before})
      }
    }
    i += 1
  }
  return {toks: toks, decls: decls, refs: refs}
}

# The token that covers a position (1-based line and column), or nil. A name the cursor touches wins.
fn token_at(a, line, col) {
  for i in 0..len(a.toks) {
    let t = a.toks[i]
    if t.kind == "ident" and t.line == line and col >= t.col and col <= t.col + len(t.text) { return i }
  }
  for i in 0..len(a.toks) {
    let t = a.toks[i]
    if t.kind != "eof" and t.line == line and col >= t.col and col < t.col + len(t.text) { return i }
  }
  return nil
}

# What the identifier token `index` stands for: {decl: the declaration (or nil), uses: every token index with the same meaning}.
fn resolve(a, index) {
  let target = nil
  for d in a.decls { if d.tok == index { target = d } }
  let member = false
  if target == nil {
    for r in a.refs {
      if r.tok == index {
        if r.member { member = true }
        else if r.decl != nil { target = a.decls[r.decl] }
      }
    }
  }
  let name = a.toks[index].text
  let uses = []
  if target != nil and target.member {
    member = true
    target = nil
  }
  if target != nil {
    uses.push(target.tok)
    for r in a.refs { if r.decl == target.id { uses.push(r.tok) } }
  } else if member {
    # a member (obj.name): every member use and every method/function with that name
    for r in a.refs { if r.member and r.name == name { uses.push(r.tok) } }
    for d in a.decls { if d.member and d.name == name { uses.push(d.tok) } }
  } else {
    for r in a.refs { if not r.member and r.decl == nil and r.name == name { uses.push(r.tok) } }
  }
  uses.sort()
  return {decl: target, member: member, uses: uses, name: name}
}
