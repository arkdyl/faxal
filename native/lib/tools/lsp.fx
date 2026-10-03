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
      },
      serverInfo: {name: "faxal", version: "1.0.0"},
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
    notify("textDocument/publishDiagnostics", {uri: params.textDocument.uri, diagnostics: []})
  } else if method == "textDocument/completion" {
    reply(id, completion(params.textDocument.uri, params.position))
  } else if method == "textDocument/hover" {
    reply(id, hover(params.textDocument.uri, params.position))
  } else if method == "textDocument/documentSymbol" {
    reply(id, document_symbols(params.textDocument.uri))
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
