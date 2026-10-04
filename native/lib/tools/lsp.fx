# faxal lsp: a language server for Faxal, written in Faxal.
#
#   faxal lsp        talks the Language Server Protocol over stdin and stdout
#
# Point an editor at it (VS Code, Neovim, Helix, Zed, ...) and .fx files get:
#   - errors and warnings as you type (the real compiler checks every edit)
#   - completion for keywords, built-in functions, methods and the names in your file
#   - hover help for built-ins and for your own functions and classes
#   - format document (the same formatter as `faxal fmt`)
#   - an outline of the functions, classes and variables in the file

import "std/compiler" as compiler
import "std/fmt" as fmt
import "std/lex" as lex
import "std/analyze" as an
import "std/path" as path
import "std/encoding" as enc

let docs = {}          # uri -> the current text
let shutting_down = false

# ------------------------------------------------------------------ protocol

fn read_message() {
  let length = nil
  while true {
    let line = input()
    if line == nil { return nil }
    line = line.trim()
    if line == "" { break }
    if line.lower().starts_with("content-length:") { length = int(line[15:].trim()) }
  }
  if length == nil { return nil }
  let body = os.stdin_read(length)
  if body == nil { return nil }
  return json.decode(body)
}

fn send(message) {
  let body = json.encode(message)
  write("Content-Length: " + str(len(body)) + "\r\n\r\n" + body)
  os.flush()
}

fn reply(id, result) { send({jsonrpc: "2.0", id: id, result: result}) }
fn reply_error(id, code, message) { send({jsonrpc: "2.0", id: id, error: {code: code, message: message}}) }
fn notify(method, params) { send({jsonrpc: "2.0", method: method, params: params}) }

# ----------------------------------------------------------------- knowledge

let KEYWORDS = lex.KEYWORDS

let BUILTINS = {
  print: "print(values...)  Show values separated by spaces, then a new line.",
  write: "write(values...)  Show values without a new line.",
  len: "len(x)  The length of a string (bytes), list, map or range.",
  str: "str(x)  Turn any value into text (uses a class's to_str method).",
  repr: "repr(x)  Text that looks like code: strings get quotes.",
  num: "num(x)  Read a number from text.",
  int: "int(x)  Read a whole number from text or cut a number's decimals.",
  bool: "bool(x)  true unless x is nil or false.",
  type: "type(x)  The type name: \"number\", \"string\", \"list\", ...",
  range: "range(n) or range(a, b, step)  A range of numbers.",
  assert: "assert(condition, message)  Stop with an error when the condition is false.",
  input: "input(prompt)  Read a line of text from the keyboard (nil at the end of the input).",
  exit: "exit(code)  Stop the program.",
  load: "load(path)  Import a module from a path computed at run time.",
  isinstance: "isinstance(object, Class)  Is the object made by this class or a subclass?",
  ord: "ord(char)  The code number of a character.",
  chr: "chr(code)  The character with this code number.",
  abs: "abs(x)  Absolute value.", floor: "floor(x)  Round down.", ceil: "ceil(x)  Round up.", round: "round(x)  Round to the nearest whole number.",
  sqrt: "sqrt(x)  Square root.", min: "min(a, b, ...) or min(list)  The smallest value.", max: "max(a, b, ...) or max(list)  The largest value.",
  sum: "sum(list)  Add up a list of numbers.",
  any: "any(list, test)  Is the test true for at least one item?",
  all: "all(list, test)  Is the test true for every item?",
  sorted: "sorted(list, compare)  A sorted copy of the list.",
  reversed: "reversed(list)  A reversed copy of the list.",
  zip: "zip(a, b)  Pair up two lists: [[a0, b0], [a1, b1], ...].",
  enumerate: "enumerate(list)  Pairs of [index, item].",
  coroutine: "coroutine(fn)  A function that can pause itself with yield(). Nothing runs until resume().",
  resume: "resume(co, value)  Run the coroutine until it yields or finishes; value becomes the result of its yield().",
  yield: "yield(value)  Pause the running coroutine and give value to whoever resumed it.",
  resume_error: "resume_error(co, error)  Throw an error inside a paused coroutine, at its yield().",
  status: "status(co)  \"new\", \"suspended\", \"running\", \"done\" or \"failed\".",
}

let METHODS = {
  string: ["len", "size", "upper", "lower", "trim", "lstrip", "rstrip", "contains", "starts_with", "ends_with", "find", "count", "replace", "split", "chars", "lines", "repeat", "reverse", "pad_left", "pad_right", "center", "capitalize", "is_digit", "is_alpha", "is_empty"],
  list: ["len", "push", "pop", "insert", "remove", "clear", "contains", "index_of", "join", "reverse", "sort", "slice", "copy", "map", "filter", "each", "reduce", "first", "last", "is_empty", "sum", "min", "max", "any", "all", "find", "count", "extend", "unique", "flatten", "sorted", "reversed"],
  coroutine: ["resume", "status", "is_done", "to_list"],
  map: ["len", "keys", "values", "items", "has", "get", "remove", "clear", "copy", "is_empty", "merge"],
}

let MODULES = ["math", "json", "time", "os", "fs"]
let STD_MODULES = ["std/tasks", "std/test", "std/collections", "std/iter", "std/text", "std/numbers", "std/color", "std/regex", "std/datetime", "std/path", "std/csv", "std/random", "std/lex", "std/fmt", "std/bytecode", "std/compiler"]

# ---------------------------------------------------------------- the source

fn position_to_offset(text, line, character) {
  let lines = text.split("\n")
  let offset = 0
  for i in 0..line {
    if i >= len(lines) { return len(text) }
    offset += len(lines[i]) + 1
  }
  return min(offset + character, len(text))
}

# The word under or just before the cursor, and the character before it.
fn word_at(text, offset) {
  let a = offset
  let b = offset
  while a > 0 and _is_word_char(text[a - 1]) { a -= 1 }
  while b < len(text) and _is_word_char(text[b]) { b += 1 }
  return {word: text[a:b], start: a, end: b, before: a > 0 and text[a - 1] or ""}
}

fn _is_word_char(c) { return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" }

# Functions, classes and top-level variables found by reading the tokens.
fn symbols(text) {
  let found = []
  let toks = lex.tokenize(text)
  let depth = 0
  let class_depth = nil
  for i in 0..len(toks) - 1 {
    let t = toks[i]
    if t.kind == "punct" and t.text == "{" { depth += 1 }
    if t.kind == "punct" and t.text == "}" {
      depth -= 1
      if class_depth != nil and depth <= class_depth { class_depth = nil }
    }
    if t.kind != "keyword" { continue }
    let next = toks[i + 1]
    if next.kind != "ident" { continue }
    if t.text == "class" {
      found.push({name: next.text, kind: 5, line: next.line - 1, col: next.col - 1, detail: "class"})
      class_depth = depth
    } else if t.text == "fn" {
      let method = class_depth != nil and depth == class_depth + 1
      found.push({name: next.text, kind: method and 6 or 12, line: next.line - 1, col: next.col - 1, detail: _signature(toks, i + 2), method: method})
    } else if t.text == "let" and depth == 0 {
      found.push({name: next.text, kind: 13, line: next.line - 1, col: next.col - 1, detail: "variable"})
    }
  }
  return found
}

fn _signature(toks, i) {
  if i >= len(toks) or toks[i].text != "(" { return "" }
  let text = "("
  let depth = 0
  while i < len(toks) {
    let t = toks[i]
    if t.text == "(" { depth += 1 }
    if t.text == ")" { depth -= 1 }
    if t.kind == "eof" { break }
    if t.text == "," { text += ", " }
    else if t.text == "(" and len(text) == 1 { }
    else if t.text == ":" { text += ": " }
    else if t.text == "=" or t.text == "->" or t.text == "or" { text += " " + t.text + " " }
    else if t.text != "(" and t.text != ")" { text += t.text }
    if depth == 0 { break }
    i += 1
  }
  return text + ")"
}

# -------------------------------------------------------------- diagnostics

fn publish_diagnostics(uri) {
  let text = docs[uri]
  let list = []
  if text != nil {
    let result = nil
    try { result = compiler.compile(text) } catch e { result = nil }
    if result != nil and not result.ok {
      for err in result.errors {
        list.push({
          range: {start: {line: err.line - 1, character: err.col - 1}, end: {line: err.line - 1, character: err.col - 1 + max(err.length, 1)}},
          severity: 1,
          source: "faxal",
          message: err.message,
        })
      }
    }
  }
  notify("textDocument/publishDiagnostics", {uri: uri, diagnostics: list})
}

# -------------------------------------------------------------- completion

fn completion(uri, position) {
  let text = docs[uri] ?? ""
  let offset = position_to_offset(text, position.line, position.character)
  let w = word_at(text, offset)
  let items = []
  let seen = {}

  fn add(label, kind, detail = nil) {
    if seen[label] == true { return }   # (not seen.has(): a key named "has" would hide the method)
    seen[label] = true
    items.push({label: label, kind: kind, detail: detail})
  }

  if w.before == "." {
    # after a dot: methods (we don't know the type, so offer the ones of every type)
    for group in ["string", "list", "map", "coroutine"] {
      for m in METHODS[group] { add(m, 2, group + " method") }
    }
    return items
  }
  let inside_import = text[0:w.start].rstrip().ends_with("import") or w.before == "\""
  if inside_import {
    for m in STD_MODULES { add(m, 9, "standard library") }
    return items
  }
  for k in KEYWORDS { add(k, 14) }
  for name in BUILTINS.keys() { add(name, 3, BUILTINS[name].split("  ")[0]) }
  for m in MODULES { add(m, 9, "module") }
  for s in symbols(text) { if not s.method { add(s.name, s.kind == 5 and 7 or s.kind == 12 and 3 or 6, s.detail) } }
  return items
}

fn hover(uri, position) {
  let text = docs[uri] ?? ""
  let offset = position_to_offset(text, position.line, position.character)
  let w = word_at(text, offset)
  if w.word == "" { return nil }
  let md = nil
  for s in symbols(text) {
    if s.name == w.word and md == nil {
      md = s.kind == 5 and "```faxal\nclass " + s.name + "\n```" or "```faxal\nfn " + s.name + s.detail + "\n```"
      if s.kind == 13 { md = "```faxal\nlet " + s.name + "\n```" }
    }
  }
  if md == nil and BUILTINS.has(w.word) { md = "```faxal\n" + BUILTINS[w.word].split("  ")[0] + "\n```\n" + (BUILTINS[w.word].split("  ")[1] ?? "") }
  if md == nil and KEYWORDS.contains(w.word) { md = "`" + w.word + "` is a keyword." }
  if md == nil { return nil }
  return {contents: {kind: "markdown", value: md}}
}

fn document_symbols(uri) {
  let out = []
  for s in symbols(docs[uri] ?? "") {
    let range = {start: {line: s.line, character: s.col}, end: {line: s.line, character: s.col + len(s.name)}}
    out.push({name: s.name, kind: s.kind, range: range, selectionRange: range, detail: s.detail})
  }
  return out
}

fn formatting(uri) {
  let text = docs[uri] ?? ""
  let formatted = nil
  try { formatted = fmt.format(text) } catch e { return [] }
  if formatted == nil or formatted == text { return [] }
  let lines = text.split("\n")
  return [{
    range: {start: {line: 0, character: 0}, end: {line: len(lines), character: 0}},
    newText: formatted,
  }]
}

# ------------------------------------------------- names: definition, references, rename

let cache = {}         # uri -> {text, analysis}

fn analysis(uri) {
  let text = docs[uri] ?? ""
  let hit = cache.get(uri)
  if hit != nil and hit.text == text { return hit.analysis }
  let a = an.analyze(text)
  cache[uri] = {text: text, analysis: a}
  return a
}

fn tok_range(t) {
  return {start: {line: t.line - 1, character: t.col - 1}, end: {line: t.line - 1, character: t.col - 1 + len(t.text)}}
}

fn uri_to_path(uri) {
  let p = uri.starts_with("file://") and uri[7:] or uri
  return enc.url_decode(p, false)
}

fn path_to_uri(p) => "file://" + enc.url_encode(p).replace("%2F", "/").replace("%3A", ":")

# The file an `import "x"` points at (nil for the built-in std/ modules and for files that don't exist).
fn import_file(uri, rel) {
  if rel.starts_with("std/") { return nil }
  let dir = path.dirname(uri_to_path(uri))
  for ext in ["", ".fx", ".fxc"] {
    let candidate = rel.starts_with("/") and rel + ext or path.join(dir, rel + ext)
    if fs.exists(candidate) and not fs.is_dir(candidate) { return candidate }
  }
  return nil
}

# Reads a file on disk (or the open document) and analyses it.
fn analysis_of_file(file) {
  let uri = path_to_uri(file)
  if docs.has(uri) { return {uri: uri, analysis: analysis(uri)} }
  if not file.ends_with(".fx") { return nil }
  let text = fs.read(file)
  return {uri: uri, analysis: an.analyze(text)}
}

fn definition(uri, pos) {
  let a = analysis(uri)
  let idx = an.token_at(a, pos.line + 1, pos.character + 1)
  if idx == nil { return nil }
  let tok = a.toks[idx]
  if tok.kind == "string" and idx > 0 and a.toks[idx - 1].kind == "keyword" and a.toks[idx - 1].text == "import" {
    let file = import_file(uri, tok.text[1:len(tok.text) - 1])
    if file == nil { return nil }
    return {uri: path_to_uri(file), range: {start: {line: 0, character: 0}, end: {line: 0, character: 0}}}
  }
  if tok.kind != "ident" { return nil }
  let r = an.resolve(a, idx)
  if r.decl != nil { return {uri: uri, range: tok_range(a.toks[r.decl.tok])} }
  if not r.member { return nil }
  let found = []
  # obj.name where obj is an imported module: the declaration in that file
  let ref = nil
  for x in a.refs { if x.tok == idx { ref = x } }
  if ref != nil and ref.after != nil {
    for d in a.decls {
      if d.kind == "module" and d.name == ref.after and d.path != nil {
        let file = import_file(uri, d.path)
        let other = file != nil and analysis_of_file(file) or nil
        if other != nil {
          for od in other.analysis.decls {
            if od.name == r.name and not od.member and (od.kind == "function" or od.kind == "class" or od.kind == "variable") {
              found.push({uri: other.uri, range: tok_range(other.analysis.toks[od.tok])})
            }
          }
        }
      }
    }
  }
  if len(found) == 0 {
    for d in a.decls { if d.member and d.name == r.name { found.push({uri: uri, range: tok_range(a.toks[d.tok])}) } }
  }
  if len(found) == 0 { return nil }
  return len(found) == 1 and found[0] or found
}

fn references(uri, pos, include_declaration = true) {
  let a = analysis(uri)
  let idx = an.token_at(a, pos.line + 1, pos.character + 1)
  if idx == nil or a.toks[idx].kind != "ident" { return [] }
  let r = an.resolve(a, idx)
  let out = []
  for u in r.uses {
    let is_decl = false
    for d in a.decls { if d.tok == u { is_decl = true } }
    if is_decl and not include_declaration { continue }
    out.push({uri: uri, range: tok_range(a.toks[u])})
  }
  return out
}

fn highlights(uri, pos) {
  let a = analysis(uri)
  let idx = an.token_at(a, pos.line + 1, pos.character + 1)
  if idx == nil or a.toks[idx].kind != "ident" { return [] }
  return an.resolve(a, idx).uses.map(fn(u) => {range: tok_range(a.toks[u]), kind: 1})
}

fn is_valid_name(name) {
  if name == "" or KEYWORDS.contains(name) { return false }
  let first = name[0]
  if not ((first >= "a" and first <= "z") or (first >= "A" and first <= "Z") or first == "_") { return false }
  for c in name.chars() { if not _is_word_char(c) { return false } }
  return true
}

# The range that would be renamed, or nil
fn prepare_rename(uri, pos) {
  let a = analysis(uri)
  let idx = an.token_at(a, pos.line + 1, pos.character + 1)
  if idx == nil or a.toks[idx].kind != "ident" { return nil }
  let r = an.resolve(a, idx)
  if r.decl == nil and not r.member { return nil }       # a built-in or a global from somewhere else
  return {range: tok_range(a.toks[idx]), placeholder: a.toks[idx].text}
}

fn rename(uri, pos, new_name) {
  if not is_valid_name(new_name) { throw "'" + new_name + "' is not a valid name" }
  let a = analysis(uri)
  let idx = an.token_at(a, pos.line + 1, pos.character + 1)
  if idx == nil or a.toks[idx].kind != "ident" { throw "put the cursor on a name to rename it" }
  let r = an.resolve(a, idx)
  if r.decl == nil and not r.member { throw "'" + r.name + "' is built in or declared in another file, so it can't be renamed here" }
  let edits = r.uses.map(fn(u) => {range: tok_range(a.toks[u]), newText: new_name})
  let changes = {}
  changes[uri] = edits
  return {changes: changes}
}

# The function being called around the cursor: signature, its parameters, and which one is being typed
fn signature_help(uri, pos) {
  let a = analysis(uri)
  let at = an.token_at(a, pos.line + 1, pos.character + 1)
  let i = at
  if i == nil {
    # between tokens (for example right after "(" or ","): the last token before the cursor
    i = -1
    for k in 0..len(a.toks) {
      let t = a.toks[k]
      if t.kind != "eof" and (t.line < pos.line + 1 or (t.line == pos.line + 1 and t.col + len(t.text) <= pos.character + 1)) { i = k }
    }
  }
  if i < 0 { return nil }
  let depth = 0
  let commas = 0
  let open = nil
  let k = i
  # when the cursor is on "(" itself it is not inside the call yet
  while k >= 0 {
    let t = a.toks[k]
    if t.kind == "punct" and (t.text == ")" or t.text == "]" or t.text == "}") { depth += 1 }
    else if t.kind == "punct" and (t.text == "(" or t.text == "[" or t.text == "{") {
      if depth == 0 { if t.text == "(" and not (k == i and at != nil) { open = k }; if open != nil or t.text != "(" { break } }
      else { depth -= 1 }
    } else if depth == 0 and t.kind == "punct" and t.text == "," { commas += 1 }
    k -= 1
  }
  if open == nil or open == 0 { return nil }
  let callee = a.toks[open - 1]
  if callee.kind != "ident" { return nil }
  let target = nil
  for x in a.refs { if x.tok == open - 1 and x.decl != nil { target = a.decls[x.decl] } }
  if target == nil {
    for d in a.decls { if d.name == callee.text and (d.kind == "function" or d.kind == "method" or d.kind == "class") { target = d } }
  }
  if target == nil { return nil }
  let params = target.params
  let label = target.detail
  if target.kind == "class" {
    for d in a.decls { if d.kind == "method" and d.name == "init" and d.line > target.line { params = d.params; label = "class " + target.name + d.detail[len("fn init"):]; break } }
  }
  if params == nil { return nil }
  # a named argument being typed selects its parameter
  let active = commas
  let first = open + 1
  let j = open + 1
  let seen = 0
  while j <= i and seen < commas { if a.toks[j].kind == "punct" and a.toks[j].text == "," and true { seen += 1; first = j + 1 }; j += 1 }
  if first + 1 <= i and a.toks[first].kind == "ident" and a.toks[first + 1].kind == "op" and a.toks[first + 1].text == "=" {
    for p in 0..len(params) { if params[p] == a.toks[first].text { active = p } }
  }
  return {signatures: [{label: label, parameters: params.map(fn(p) => {label: p})}], activeSignature: 0, activeParameter: active}
}

fn workspace_symbols(query) {
  let out = []
  let q = query.lower()
  for uri in docs.keys() {
    for d in analysis(uri).decls {
      if d.kind == "param" or d.kind == "loop" or d.kind == "catch" { continue }
      if q == "" or d.name.lower().contains(q) {
        let a = analysis(uri)
        let kinds = {"function": 12, "method": 6, "class": 5, "variable": 13, "module": 2}
        out.push({name: d.name, kind: kinds.get(d.kind, 13), location: {uri: uri, range: tok_range(a.toks[d.tok])}})
      }
    }
  }
  return out
}

# -------------------------------------------------------------------- loop

fn handle(msg) {
  let method = msg.method
  let params = msg.params ?? {}
  let id = msg.id
  if method == "initialize" {
    reply(id, {
      capabilities: {
        textDocumentSync: 1,
        completionProvider: {triggerCharacters: [".", "\""]},
        hoverProvider: true,
        documentFormattingProvider: true,
        documentSymbolProvider: true,
        definitionProvider: true,
        referencesProvider: true,
        documentHighlightProvider: true,
        renameProvider: {prepareProvider: true},
        signatureHelpProvider: {triggerCharacters: ["(", ","]},
        workspaceSymbolProvider: true,
      },
      serverInfo: {name: "faxal", version: "1.1.0"},
    })
  } else if method == "shutdown" {
    shutting_down = true
    reply(id, nil)
  } else if method == "exit" {
    os.exit(shutting_down and 0 or 1)
  } else if method == "textDocument/didOpen" {
    docs[params.textDocument.uri] = params.textDocument.text
    publish_diagnostics(params.textDocument.uri)
  } else if method == "textDocument/didChange" {
    let changes = params.contentChanges
    if len(changes) > 0 { docs[params.textDocument.uri] = changes[-1].text }
    publish_diagnostics(params.textDocument.uri)
  } else if method == "textDocument/didClose" {
    docs.remove(params.textDocument.uri)
    cache.remove(params.textDocument.uri)
    notify("textDocument/publishDiagnostics", {uri: params.textDocument.uri, diagnostics: []})
  } else if method == "textDocument/completion" {
    reply(id, completion(params.textDocument.uri, params.position))
  } else if method == "textDocument/hover" {
    reply(id, hover(params.textDocument.uri, params.position))
  } else if method == "textDocument/documentSymbol" {
    reply(id, document_symbols(params.textDocument.uri))
  } else if method == "textDocument/definition" {
    reply(id, definition(params.textDocument.uri, params.position))
  } else if method == "textDocument/references" {
    reply(id, references(params.textDocument.uri, params.position, (params.context ?? {}).includeDeclaration ?? true))
  } else if method == "textDocument/documentHighlight" {
    reply(id, highlights(params.textDocument.uri, params.position))
  } else if method == "textDocument/prepareRename" {
    let r = prepare_rename(params.textDocument.uri, params.position)
    if r == nil { reply_error(id, -32602, "there is nothing here that can be renamed") } else { reply(id, r) }
  } else if method == "textDocument/rename" {
    let edit = nil
    try { edit = rename(params.textDocument.uri, params.position, params.newName) } catch e { reply_error(id, -32602, str(e)); return }
    reply(id, edit)
  } else if method == "textDocument/signatureHelp" {
    reply(id, signature_help(params.textDocument.uri, params.position))
  } else if method == "workspace/symbol" {
    reply(id, workspace_symbols(params.query ?? ""))
  } else if method == "textDocument/formatting" {
    reply(id, formatting(params.textDocument.uri))
  } else if id != nil {
    reply_error(id, -32601, "method not supported: " + str(method))
  }
}

while true {
  let msg = read_message()
  if msg == nil { break }
  try {
    handle(msg)
  } catch e {
    if msg.id != nil { reply_error(msg.id, -32603, "internal error: " + str(e)) }
  }
}
