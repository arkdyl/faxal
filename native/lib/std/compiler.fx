# std/compiler: the Faxal compiler, written in Faxal.
#
# It turns source code into bytecode (see std/bytecode). It is a port of the compiler in
# native/src/compiler.c and produces exactly the same bytecode, line numbers and error
# messages. The test suite checks that, for every Faxal file in the repository and for
# thousands of damaged programs.
#
#   import "std/compiler" as fxc
#   let result = fxc.compile("print(1 + 2)")
#   print(bytecode.disassemble(result.program))
#
# How it works, in three steps:
#   1. layout()  cuts the source into tokens (with std/lex) and adds the invisible ';' that
#                ends a statement at the end of a line.
#   2. A Pratt parser reads the tokens. There is no syntax tree: as soon as the parser has
#      understood a piece of code it writes the matching bytecode ("single pass").
#   3. end_compiler() collects the finished function.

import "std/lex" as lex
import "std/bytecode" as bc

let OP = bc.OP

# ------------------------------------------------------------------ tokens

# A token is a map: {type, text, line, col}.
#   type  "IDENT" "NUMBER" "STRING" "FSTRING" "SEMI" "EOF" "ERROR", or the token's own text
#         for keywords and punctuation (so the type of the keyword `if` is "if", of "(" is "(").
#   text  the exact source text. A SEMI that ends a line has the text "\n", the SEMI at the
#         very end of the input has "", an explicit ; has ";".

let NEEDS_SEMI = {
  "IDENT": true, "self": true, "NUMBER": true, "STRING": true, "FSTRING": true,
  ")": true, "]": true, "}": true, "true": true, "false": true, "nil": true,
  "break": true, "continue": true, "return": true,
}

let CONTINUES_LINE = {"else": true, "and": true, "or": true, ".": true, "|>": true, "??": true, "?.": true}

fn _line_start(src, pos) {
  let j = pos - 1
  while j >= 0 and src[j] != "\n" { j -= 1 }
  return j + 1
}

fn _error_message(text) {
  if text == "!" { return "Unexpected '!'. Use 'not' for negation and '!=' for not-equal." }
  if text == "|" { return "Unexpected '|'. Did you mean '|>' (pipe) or 'or'?" }
  if text == "?" { return "Unexpected '?'. Faxal has the operators ?? (default value) and ?. (safe access)." }
  return "Unexpected character."
}

# Tokens for `src`, with the ';' that ends a line added where a statement ends. This is the
# rule: a line break ends a statement when the last token could end one (a name, number,
# string, closing bracket, true/false/nil, break, continue, return), when we are not inside
# ( ) or [ ], and when the next line does not continue the statement (it does not start with
# a '.', '|>', '??', '?.', 'else', 'and' or 'or').
fn layout(src, first_line = 1) {
  let raw = lex.tokenize(src)
  let out = []
  let brackets = []
  let last = "SEMI"
  let prev_raw = nil
  let newline_seen = false
  let newline_after = nil
  let shift = first_line - 1

  for t in raw {
    if t.nl > 0 and not newline_seen {
      newline_seen = true
      newline_after = prev_raw
    }
    if t.kind == "comment" {
      prev_raw = t
      continue
    }
    let depth = brackets.len()
    let significant = depth == 0 or (depth <= 255 and brackets[depth - 1] == "{")
    let type = ""
    if t.kind == "eof" { type = "EOF" }
    else if t.kind == "ident" { type = "IDENT" }
    else if t.kind == "number" { type = "NUMBER" }
    else if t.kind == "string" { type = "STRING" }
    else if t.kind == "fstring" { type = "FSTRING" }
    else if t.kind == "keyword" { type = t.text }
    else if t.kind == "error" { type = "ERROR" }
    else if t.text == ";" { type = "SEMI" }
    else { type = t.text }
    if (type == "STRING" or type == "FSTRING") and t.open { type = "ERROR" }

    # a line break that ends the statement
    if newline_seen and NEEDS_SEMI.has(last) and significant and not CONTINUES_LINE.has(type) and newline_after != nil {
      let at = src.find("\n", newline_after.pos + len(newline_after.text))
      let started = _line_start(src, at)
      out.push({type: "SEMI", text: "\n", line: newline_after.line + newline_after.text.count("\n") + shift, col: at - started + 1})
      last = "SEMI"
    } else if type == "EOF" and not newline_seen and NEEDS_SEMI.has(last) and significant {
      out.push({type: "SEMI", text: "", line: t.line + shift, col: t.col})
      last = "SEMI"
    }
    newline_seen = false
    newline_after = nil

    if type == "ERROR" {
      let message = t.open and "Unterminated string." or _error_message(t.text)
      out.push({type: "ERROR", text: t.text, line: t.line + shift, col: t.col, message: message})
    } else {
      out.push({type: type, text: t.text, line: t.line + shift, col: t.col})
      last = type
      if type == "(" or type == "[" or type == "{" {
        brackets.push(type)
      } else if (type == ")" or type == "]" or type == "}") and depth > 0 {
        brackets.pop()
      }
    }
    prev_raw = t
  }
  return out
}

# ------------------------------------------------------------ compiler state

# The parser's state lives in `ps`; the function being compiled is `cur`.
let ps = nil
let cur = nil
let current_class = nil
let functions = []

let PREC_NONE = 0
let PREC_ASSIGNMENT = 1
let PREC_PIPE = 2
let PREC_COALESCE = 3
let PREC_OR = 4
let PREC_AND = 5
let PREC_EQUALITY = 6
let PREC_COMPARISON = 7
let PREC_RANGE = 8
let PREC_TERM = 9
let PREC_FACTOR = 10
let PREC_UNARY = 11
let PREC_POWER = 12
let PREC_CALL = 13
let PREC_PRIMARY = 14

# Everything the compiler needs to know about the function it is compiling.
class FnState {
  fn init(type, name, enclosing) {
    self.type = type                # "function", "script", "method" or "initializer"
    self.name = name
    self.enclosing = enclosing
    self.code = []
    self.lines = []
    self.constants = []
    self.arity = 0
    self.min_arity = 0
    self.locals = [{name: (type == "method" or type == "initializer") and "self" or "", depth: 0, captured: false}]
    self.upvalues = []
    self.scope_depth = 0
    self.try_depth = 0
    self.loop = nil
    self.ret_spec = ""              # the declared return type, such as "num" or "str|nil" ("" when there is none)
    self.label = name == nil and "the function" or name[0:60] + "()"   # how error messages name this function
  }
}

# ------------------------------------------------------------------- errors

fn error_at(tok, message) {
  if ps.panic { return }
  ps.panic = true
  ps.had_error = true
  if tok.type == "EOF" or (tok.type == "SEMI" and tok.text == "") { ps.eof_error = true }
  let index = tok.line - ps.first_line
  let text = (index >= 0 and index < ps.src_lines.len()) and ps.src_lines[index] or ""
  let length = (tok.type == "EOF" or len(tok.text) < 1 or tok.type == "ERROR") and 1 or len(tok.text)
  ps.errors.push({message: message, line: tok.line, col: tok.col, text: text, length: length})
}

fn error(message) { error_at(ps.previous, message) }
fn error_at_current(message) { error_at(ps.current, message) }

fn advance() {
  ps.previous = ps.current
  while true {
    ps.current = ps.toks[ps.pos]
    if ps.pos < ps.toks.len() - 1 { ps.pos += 1 }
    if ps.current.type != "ERROR" { break }
    error_at_current(ps.current.message)
  }
}

fn check(type) { return ps.current.type == type }

fn match(type) {
  if not check(type) { return false }
  advance()
  return true
}

fn consume(type, message) {
  if check(type) {
    advance()
    return
  }
  error_at_current(message)
}

fn skip_semis() {
  while check("SEMI") { advance() }
}

# The token after the current one, without consuming anything.
fn peek_next() {
  return ps.toks[ps.pos]
}

# ----------------------------------------------------------------- emitting

fn emit_byte(b) {
  cur.code.push(b)
  cur.lines.push(ps.previous.line)
}

fn emit_bytes(a, b) {
  emit_byte(a)
  emit_byte(b)
}

fn emit_short(v) {
  emit_byte(floor(v / 256) % 256)
  emit_byte(v % 256)
}

fn make_constant(value) {
  cur.constants.push(value)
  let index = cur.constants.len() - 1
  if index > 65535 {
    error("Too many constants in one function.")
    return 0
  }
  return index
}

fn emit_constant(value) {
  emit_byte(OP.CONSTANT)
  emit_short(make_constant(value))
}

# The constant slot holding the name `name`; reuses an equal string that is already there.
fn identifier_constant(name) {
  let constants = cur.constants
  for i in 0..constants.len() {
    if type(constants[i]) == "string" and constants[i] == name { return i }
  }
  return make_constant(name)
}

fn emit_jump(op) {
  emit_byte(op)
  emit_byte(255)
  emit_byte(255)
  return cur.code.len() - 2
}

fn patch_jump(offset) {
  let jump = cur.code.len() - offset - 2
  if jump > 65535 { error("Too much code to jump over.") }
  cur.code[offset] = floor(jump / 256) % 256
  cur.code[offset + 1] = jump % 256
}

fn emit_loop(start) {
  emit_byte(OP.LOOP)
  let offset = cur.code.len() - start + 2
  if offset > 65535 { error("Loop body is too large.") }
  emit_short(offset)
}

# Type annotations are checked while the program runs: the value on top of the stack goes through
# __check(value, "num or str", "what it is"), which gives the value back or throws a type error.
fn emit_check_top(spec, what) {
  emit_byte(OP.GET_GLOBAL)
  emit_short(identifier_constant("__check"))
  emit_byte(OP.SWAP)
  emit_constant(spec)
  emit_constant(what)
  emit_bytes(OP.CALL, 3)
}

fn spec_accepts_nil(spec) {
  for word in spec.split("|") {
    if word == "nil" or word == "any" { return true }
  }
  return false
}

fn emit_return() {
  if cur.type == "initializer" {
    emit_bytes(OP.GET_LOCAL, 0)
  } else {
    emit_byte(OP.NIL)
    if cur.ret_spec != "" and not spec_accepts_nil(cur.ret_spec) {
      emit_check_top(cur.ret_spec, "return value of " + cur.label)
    }
  }
  emit_byte(OP.RETURN)
}

fn begin_function(type, name) {
  cur = FnState(type, name, cur)
}

# Finishes the current function and returns it.
fn end_compiler() {
  emit_return()
  let f = {
    name: cur.name,
    arity: cur.arity,
    min_arity: cur.min_arity,
    upvalue_count: cur.upvalues.len(),
    is_script: cur.type == "script",
    code: cur.code,
    lines: cur.lines,
    constants: cur.constants,
    upvalues: cur.upvalues,
    index: functions.len(),
  }
  functions.push(f)
  cur = cur.enclosing
  return f
}

fn begin_scope() { cur.scope_depth += 1 }

fn end_scope() {
  cur.scope_depth -= 1
  while cur.locals.len() > 0 and cur.locals[-1].depth > cur.scope_depth {
    emit_byte(cur.locals[-1].captured and OP.CLOSE_UPVALUE or OP.POP)
    cur.locals.pop()
  }
}

# Pops the locals above `base` without forgetting them (used by break and continue).
fn emit_pops_to(base) {
  let i = cur.locals.len() - 1
  while i >= base {
    emit_byte(cur.locals[i].captured and OP.CLOSE_UPVALUE or OP.POP)
    i -= 1
  }
}

# ---------------------------------------------------------------- variables

fn resolve_local(state, name) {
  let i = state.locals.len() - 1
  while i >= 0 {
    let l = state.locals[i]
    if l.name == name {
      if l.depth == -1 { error("Can't read a variable in its own initializer.") }
      return i
    }
    i -= 1
  }
  return -1
}

fn add_upvalue(state, index, is_local) {
  let count = state.upvalues.len()
  for i in 0..count {
    if state.upvalues[i].index == index and state.upvalues[i].is_local == is_local { return i }
  }
  if count == 256 {
    error("Too many captured variables in one function.")
    return 0
  }
  state.upvalues.push({index: index, is_local: is_local})
  return count
}

fn resolve_upvalue(state, name) {
  if state.enclosing == nil { return -1 }
  let local = resolve_local(state.enclosing, name)
  if local != -1 {
    state.enclosing.locals[local].captured = true
    return add_upvalue(state, local, true)
  }
  let up = resolve_upvalue(state.enclosing, name)
  if up != -1 { return add_upvalue(state, up, false) }
  return -1
}

fn add_local(name) {
  if cur.locals.len() == 256 {
    error("Too many local variables in one function.")
    return
  }
  cur.locals.push({name: name, depth: -1, captured: false})
}

fn mark_initialized() {
  if cur.scope_depth == 0 { return }
  cur.locals[-1].depth = cur.scope_depth
}

fn declare_variable() {
  if cur.scope_depth == 0 { return }
  let name = ps.previous.text
  let i = cur.locals.len() - 1
  while i >= 0 {
    let l = cur.locals[i]
    if l.depth != -1 and l.depth < cur.scope_depth { break }
    if l.name == name { error("There is already a variable with this name in this scope.") }
    i -= 1
  }
  add_local(name)
}

fn parse_variable(message) {
  consume("IDENT", message)
  declare_variable()
  if cur.scope_depth > 0 { return 0 }
  return identifier_constant(ps.previous.text)
}

fn define_variable(global) {
  if cur.scope_depth > 0 {
    mark_initialized()
    return
  }
  emit_byte(OP.DEFINE_GLOBAL)
  emit_short(global)
}

# -------------------------------------------------------------- expressions

fn parse_precedence(precedence) {
  ps.nesting += 1
  if ps.nesting > 200 {
    error("This is nested too deeply.")
    ps.nesting -= 1
    return
  }
  advance()
  let prefix = get_rule(ps.previous.type)[0]
  if prefix == nil {
    error("Expected an expression.")
    ps.nesting -= 1
    return
  }
  let can_assign = precedence <= PREC_ASSIGNMENT
  prefix(can_assign)
  while precedence <= get_rule(ps.current.type)[2] {
    advance()
    get_rule(ps.previous.type)[1](can_assign)
  }
  if can_assign and (check("=") or check("+=") or check("-=") or check("*=") or check("/=") or check("%=")) {
    advance()
    error("Invalid assignment target.")
  }
  ps.nesting -= 1
}

fn expression() { parse_precedence(PREC_ASSIGNMENT) }

# If the next token is += -= *= /= or %=, consume it and return the matching instruction.
fn match_compound() {
  if match("+=") { return OP.ADD }
  if match("-=") { return OP.SUB }
  if match("*=") { return OP.MUL }
  if match("/=") { return OP.DIV }
  if match("%=") { return OP.MOD }
  return nil
}

fn named_variable(name, can_assign) {
  let get_op = nil
  let set_op = nil
  let is_global = false
  let arg = resolve_local(cur, name)
  if arg != -1 {
    get_op = OP.GET_LOCAL
    set_op = OP.SET_LOCAL
  } else {
    arg = resolve_upvalue(cur, name)
    if arg != -1 {
      get_op = OP.GET_UPVALUE
      set_op = OP.SET_UPVALUE
    } else {
      arg = identifier_constant(name)
      get_op = OP.GET_GLOBAL
      set_op = OP.SET_GLOBAL
      is_global = true
    }
  }
  let emit_arg = fn(op) {
    emit_byte(op)
    if is_global { emit_short(arg) } else { emit_byte(arg % 256) }
  }
  if can_assign and match("=") {
    expression()
    emit_arg(set_op)
    return
  }
  let compound = can_assign and match_compound() or nil
  if compound != nil {
    emit_arg(get_op)
    expression()
    emit_byte(compound)
    emit_arg(set_op)
  } else {
    emit_arg(get_op)
  }
}

fn variable(can_assign) { named_variable(ps.previous.text, can_assign) }

fn number(can_assign) {
  let text = ps.previous.text.replace("_", "")
  emit_constant(num(text[:62]))
}

fn literal(can_assign) {
  let t = ps.previous.type
  if t == "false" { emit_byte(OP.FALSE) }
  else if t == "nil" { emit_byte(OP.NIL) }
  else if t == "true" { emit_byte(OP.TRUE) }
}

# Writes the literal text collected so far. Pieces of an f-string are added together.
fn flush_literal(lit, first) {
  if lit.len() > 0 or first {
    emit_constant(lit.join(""))
    if not first { emit_byte(OP.ADD) }
    lit.clear()
    return false
  }
  return first
}

# The code inside { } of an f-string is compiled by running the parser on that little text.
fn compile_interpolation(text, line) {
  let saved = {
    toks: ps.toks, pos: ps.pos, previous: ps.previous, current: ps.current, panic: ps.panic,
    src_lines: ps.src_lines, first_line: ps.first_line, eof_error: ps.eof_error,
  }
  ps.toks = layout(text, line)
  ps.pos = 0
  ps.src_lines = text.split("\n")
  ps.first_line = line
  ps.panic = false
  advance()
  if check("EOF") or check("SEMI") {
    error_at_current("Empty {} in f-string. Use \\{ for a literal brace.")
  } else {
    expression()
    skip_semis()
    if not check("EOF") { error_at_current("Unexpected token in string interpolation.") }
  }
  ps.toks = saved.toks
  ps.pos = saved.pos
  ps.previous = saved.previous
  ps.current = saved.current
  ps.panic = saved.panic
  ps.src_lines = saved.src_lines
  ps.first_line = saved.first_line
  ps.eof_error = saved.eof_error
}

# Strings: escapes like \n, and for f"..." the {expressions} inside.
fn string(can_assign) {
  let interp = ps.previous.type == "FSTRING"
  let text = ps.previous.text
  let raw = text[interp and 2 or 1:len(text) - 1]
  let line = ps.previous.line
  let n = len(raw)
  let lit = []
  let first = true
  let i = 0
  while i < n {
    let c = raw[i]
    if c == "\\" and i + 1 < n {
      i += 1
      let e = raw[i]
      if e == "n" { lit.push("\n") }
      else if e == "t" { lit.push("\t") }
      else if e == "r" { lit.push("\r") }
      else if e == "0" { lit.push("\0") }
      else if e == "e" { lit.push("\e") }
      else if e == "\\" or e == "\"" or e == "'" or e == "{" or e == "}" { lit.push(e) }
      else {
        lit.push("\\")
        lit.push(e)
      }
    } else if c == "{" and interp {
      let depth = 1
      let j = i + 1
      while j < n and depth > 0 {
        if raw[j] == "\\" {
          j += 2
          continue
        }
        if raw[j] == "\"" or raw[j] == "'" {
          let quote = raw[j]
          j += 1
          while j < n and raw[j] != quote {
            if raw[j] == "\\" { j += 1 }
            j += 1
          }
        } else if raw[j] == "{" { depth += 1 }
        else if raw[j] == "}" { depth -= 1 }
        j += 1
      }
      if depth != 0 {
        error("Unclosed { in f-string. Use \\{ for a literal brace.")
        break
      }
      first = flush_literal(lit, first)
      compile_interpolation(raw[i + 1:j - 1], line)
      emit_byte(OP.ADD)
      i = j - 1
    } else {
      lit.push(c)
    }
    i += 1
  }
  flush_literal(lit, first)
}

fn grouping(can_assign) {
  expression()
  consume(")", "Expected ')' after expression.")
}

fn unary(can_assign) {
  if ps.previous.type == "not" {
    parse_precedence(PREC_EQUALITY)
    emit_byte(OP.NOT)
  } else {
    parse_precedence(PREC_UNARY)
    emit_byte(OP.NEG)
  }
}

let BINARY_OPS = {
  "+": [OP.ADD], "-": [OP.SUB], "*": [OP.MUL], "/": [OP.DIV], "%": [OP.MOD], "**": [OP.POW],
  "==": [OP.EQUAL], "!=": [OP.EQUAL, OP.NOT], ">": [OP.GREATER], ">=": [OP.LESS, OP.NOT],
  "<": [OP.LESS], "<=": [OP.GREATER, OP.NOT], "in": [OP.IN], "..": [OP.RANGE], "by": [OP.BY],
}

fn binary(can_assign) {
  let op = ps.previous.type
  let rule = get_rule(op)
  parse_precedence(op == "**" and PREC_POWER or rule[2] + 1)
  for code in BINARY_OPS[op] { emit_byte(code) }
}

fn and_(can_assign) {
  let end = emit_jump(OP.JUMP_IF_FALSE)
  emit_byte(OP.POP)
  parse_precedence(PREC_AND + 1)
  patch_jump(end)
}

fn or_(can_assign) {
  let else_jump = emit_jump(OP.JUMP_IF_FALSE)
  let end_jump = emit_jump(OP.JUMP)
  patch_jump(else_jump)
  emit_byte(OP.POP)
  parse_precedence(PREC_OR + 1)
  patch_jump(end_jump)
}

fn argument_list() {
  let argc = 0
  if not check(")") {
    let more = true
    while more {
      if check(")") { break }
      expression()
      if argc == 255 { error("Can't have more than 255 arguments.") }
      argc += 1
      more = match(",")
    }
  }
  consume(")", "Expected ')' after arguments.")
  return argc % 256
}

fn call(can_assign) {
  let argc = argument_list()
  emit_bytes(OP.CALL, argc)
}

fn dot(can_assign) {
  consume("IDENT", "Expected a property name after '.'.")
  let name = identifier_constant(ps.previous.text)
  if can_assign and match("=") {
    expression()
    emit_byte(OP.SET_PROPERTY)
    emit_short(name)
    return
  }
  let compound = can_assign and match_compound() or nil
  if compound != nil {
    emit_byte(OP.DUP)
    emit_byte(OP.GET_PROPERTY)
    emit_short(name)
    expression()
    emit_byte(compound)
    emit_byte(OP.SET_PROPERTY)
    emit_short(name)
  } else if match("(") {
    let argc = argument_list()
    emit_byte(OP.INVOKE)
    emit_short(name)
    emit_byte(argc)
  } else {
    emit_byte(OP.GET_PROPERTY)
    emit_short(name)
  }
}

fn subscript(can_assign) {
  let sliced = false
  if check(":") { emit_byte(OP.NIL) } else { expression() }
  if match(":") {
    sliced = true
    if check("]") { emit_byte(OP.NIL) } else { expression() }
  }
  consume("]", "Expected ']' after index.")
  if sliced {
    emit_byte(OP.SLICE)
    return
  }
  if can_assign and match("=") {
    expression()
    emit_byte(OP.SET_INDEX)
    return
  }
  let compound = can_assign and match_compound() or nil
  if compound != nil {
    emit_byte(OP.DUP2)
    emit_byte(OP.GET_INDEX)
    expression()
    emit_byte(compound)
    emit_byte(OP.SET_INDEX)
  } else {
    emit_byte(OP.GET_INDEX)
  }
}

fn list_literal(can_assign) {
  let count = 0
  if not check("]") {
    let more = true
    while more {
      if check("]") { break }
      expression()
      if count == 65535 { error("Too many items in a list literal.") }
      count += 1
      more = match(",")
    }
  }
  consume("]", "Expected ']' after list items.")
  emit_byte(OP.BUILD_LIST)
  emit_short(count)
}

fn map_literal(can_assign) {
  let count = 0
  skip_semis()
  while not check("}") and not check("EOF") {
    if check("IDENT") and peek_next().type == ":" {
      advance()
      emit_constant(ps.previous.text)
    } else if check("STRING") or check("NUMBER") or check("true") or check("false") {
      advance()
      get_rule(ps.previous.type)[0](false)
    } else {
      error_at_current("Expected a key (a name, string or number) in map.")
      return
    }
    consume(":", "Expected ':' after map key.")
    skip_semis()
    expression()
    count += 1
    skip_semis()
    if not match(",") { break }
    skip_semis()
  }
  skip_semis()
  consume("}", "Expected '}' after map entries.")
  emit_byte(OP.BUILD_MAP)
  emit_short(count)
}

# type := name ("or" name)*   as the text "name|name"
fn type_spec() {
  let out = ""
  while true {
    if not (check("IDENT") or check("nil") or check("fn")) {
      error_at_current("Expected a type name (num, str, bool, list, map, fn, nil, any, or a class name).")
      return out
    }
    advance()
    let word = ps.previous.text
    if len(out) + len(word) + 2 >= 96 {
      error("This type is too long.")
      return out
    }
    if out != "" { out += "|" }
    out += word
    if not match("or") { break }
  }
  return out
}

# A function or method: parameters (with optional types and defaults) and a body.
fn function(type, name) {
  begin_function(type, name)
  begin_scope()
  consume("(", "Expected '(' before parameters.")
  let saw_default = false
  if not check(")") {
    let more = true
    while more {
      if check(")") { break }
      cur.arity += 1
      if cur.arity > 255 { error_at_current("Can't have more than 255 parameters.") }
      let p = parse_variable("Expected a parameter name.")
      define_variable(p)
      let param_name = ps.previous.text
      let param_spec = ""
      if match(":") { param_spec = type_spec() }
      if match("=") {
        # a default value: at function entry, if the argument is nil, compute the default
        saw_default = true
        let slot = cur.locals.len() - 1
        emit_bytes(OP.GET_LOCAL, slot % 256)
        let skip = emit_jump(OP.JUMP_IF_NOT_NIL)
        emit_byte(OP.POP)
        expression()
        emit_bytes(OP.SET_LOCAL, slot % 256)
        patch_jump(skip)
        emit_byte(OP.POP)
      } else {
        if saw_default { error("A parameter without a default value can't come after one that has a default.") }
        cur.min_arity += 1
      }
      if param_spec != "" {
        let what = "parameter '" + param_name[0:40] + "' of " + cur.label
        emit_byte(OP.GET_GLOBAL)
        emit_short(identifier_constant("__check"))
        emit_bytes(OP.GET_LOCAL, (cur.locals.len() - 1) % 256)
        emit_constant(param_spec)
        emit_constant(what)
        emit_bytes(OP.CALL, 3)
        emit_byte(OP.POP)
      }
      more = match(",")
    }
  }
  consume(")", "Expected ')' after parameters.")
  if match("->") { cur.ret_spec = type_spec() }
  if match("=>") {
    if cur.type == "initializer" { error("Can't return a value from init().") }
    expression()
    if cur.ret_spec != "" { emit_check_top(cur.ret_spec, "return value of " + cur.label) }
    emit_byte(OP.RETURN)
  } else {
    skip_semis()
    consume("{", "Expected '{' before function body.")
    block()
  }
  let f = end_compiler()
  emit_byte(OP.CLOSURE)
  emit_short(make_constant(f))
  for up in f.upvalues {
    emit_byte(up.is_local and 1 or 0)
    emit_byte(up.index)
  }
}

fn lambda(can_assign) { function("function", nil) }

# x |> f becomes f(x), and x |> f(a, b) becomes f(x, a, b)
fn pipe_op(can_assign) {
  parse_precedence(PREC_PRIMARY)
  while match(".") {
    consume("IDENT", "Expected a name after '.'.")
    emit_byte(OP.GET_PROPERTY)
    emit_short(identifier_constant(ps.previous.text))
  }
  emit_byte(OP.SWAP)
  let argc = 1
  if match("(") {
    let extra = argument_list()
    if extra + 1 > 255 { error("Too many arguments.") }
    argc += extra
  }
  emit_bytes(OP.CALL, argc % 256)
}

# a ?? b is a, unless a is nil
fn coalesce(can_assign) {
  let end = emit_jump(OP.JUMP_IF_NOT_NIL)
  emit_byte(OP.POP)
  parse_precedence(PREC_COALESCE + 1)
  patch_jump(end)
}

# a?.b and a?.m(x) are nil when a is nil, instead of an error
fn optional_dot(can_assign) {
  let skip = emit_jump(OP.JUMP_IF_NIL)
  consume("IDENT", "Expected a property name after '?.'.")
  let name = identifier_constant(ps.previous.text)
  if match("(") {
    let argc = argument_list()
    emit_byte(OP.INVOKE)
    emit_short(name)
    emit_byte(argc)
  } else {
    emit_byte(OP.GET_PROPERTY)
    emit_short(name)
  }
  patch_jump(skip)
}

fn self_(can_assign) {
  if current_class == nil {
    error("'self' can only be used inside a class.")
    return
  }
  variable(false)
}

fn super_(can_assign) {
  if current_class == nil { error("'super' can only be used inside a class.") }
  else if not current_class.has_superclass { error("'super' can only be used in a class that extends another class.") }
  consume(".", "Expected '.' after 'super'.")
  consume("IDENT", "Expected a method name after 'super.'.")
  let name = identifier_constant(ps.previous.text)
  named_variable("self", false)
  if match("(") {
    let argc = argument_list()
    named_variable("super", false)
    emit_byte(OP.SUPER_INVOKE)
    emit_short(name)
    emit_byte(argc)
  } else {
    named_variable("super", false)
    emit_byte(OP.GET_SUPER)
    emit_short(name)
  }
}

# --------------------------------------------------------------- statements

fn end_statement() {
  if match("SEMI") { return }
  if check("}") or check("EOF") { return }
  error_at_current("Expected a new line or ';' after this statement.")
}

fn block() {
  skip_semis()
  while not check("}") and not check("EOF") {
    declaration()
    skip_semis()
  }
  consume("}", "Expected '}' to close the block.")
}

fn scoped_block() {
  consume("{", "Expected '{'.")
  begin_scope()
  block()
  end_scope()
}

fn let_declaration() {
  let global = parse_variable("Expected a variable name after 'let'.")
  let var_name = ps.previous.text
  let spec = ""
  if match(":") { spec = type_spec() }
  if match("=") {
    if check("fn") { mark_initialized() }   # lets a local function call itself
    expression()
    if spec != "" { emit_check_top(spec, "variable '" + var_name[0:60] + "'") }
  } else {
    emit_byte(OP.NIL)
  }
  end_statement()
  define_variable(global)
}

fn fun_declaration() {
  let global = parse_variable("Expected a function name.")
  let name = ps.previous.text
  mark_initialized()
  function("function", name)
  define_variable(global)
}

fn method() {
  skip_semis()
  consume("fn", "Expected 'fn' to start a method.")
  consume("IDENT", "Expected a method name.")
  let name = ps.previous.text
  let constant = identifier_constant(name)
  function(name == "init" and "initializer" or "method", name)
  emit_byte(OP.METHOD)
  emit_short(constant)
}

fn class_declaration() {
  consume("IDENT", "Expected a class name.")
  let class_name = ps.previous.text
  let name_constant = identifier_constant(class_name)
  declare_variable()
  emit_byte(OP.CLASS)
  emit_short(name_constant)
  define_variable(name_constant)

  let cc = {has_superclass: false, enclosing: current_class}
  current_class = cc

  if match("extends") {
    consume("IDENT", "Expected a superclass name after 'extends'.")
    variable(false)
    if class_name == ps.previous.text { error("A class can't extend itself.") }
    begin_scope()
    add_local("super")
    define_variable(0)
    named_variable(class_name, false)
    emit_byte(OP.INHERIT)
    cc.has_superclass = true
  }

  named_variable(class_name, false)
  skip_semis()
  consume("{", "Expected '{' before the class body.")
  skip_semis()
  while not check("}") and not check("EOF") {
    method()
    skip_semis()
  }
  consume("}", "Expected '}' after the class body.")
  emit_byte(OP.POP)
  if cc.has_superclass { end_scope() }
  current_class = cc.enclosing
}

fn _is_alpha(c) { return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c > "~" }
fn _is_digit(c) { return c >= "0" and c <= "9" }

fn import_statement() {
  consume("STRING", "Expected a file path string after 'import'.")
  let path = ps.previous.text
  if ps.collect_imports { ps.imports.push(path[1:len(path) - 1]) }
  string(false)
  emit_byte(OP.IMPORT)

  let name = nil
  if check("IDENT") and ps.current.text == "as" {
    advance()
    consume("IDENT", "Expected a name after 'as'.")
    name = ps.previous.text
  } else {
    # the name comes from the file name: "lib/util.fx" becomes util
    let s = path[1:len(path) - 1]
    let n = len(s)
    let begin = 0
    let end = n
    for i in 0..n { if s[i] == "/" { begin = i + 1 } }
    let i = n - 1
    while i >= begin {
      if s[i] == "." {
        end = i
        break
      }
      i -= 1
    }
    name = s[begin:end]
    let ok = len(name) > 0 and _is_alpha(name[0])
    for c in name { if ok and not _is_alpha(c) and not _is_digit(c) { ok = false } }
    if not ok {
      error("Can't make a name from this path. Write: import \"file.fx\" as name")
      return
    }
  }
  end_statement()
  if cur.scope_depth == 0 {
    emit_byte(OP.DEFINE_GLOBAL)
    emit_short(identifier_constant(name))
  } else {
    add_local(name)
    mark_initialized()
  }
}

fn expression_statement() {
  expression()
  if ps.repl and cur.type == "script" and cur.scope_depth == 0 { emit_byte(OP.REPL_PRINT) } else { emit_byte(OP.POP) }
  end_statement()
}

fn if_statement() {
  expression()
  let then_jump = emit_jump(OP.JUMP_IF_FALSE)
  emit_byte(OP.POP)
  scoped_block()
  let else_jump = emit_jump(OP.JUMP)
  patch_jump(then_jump)
  emit_byte(OP.POP)
  if match("else") {
    if match("if") { if_statement() } else { scoped_block() }
  }
  patch_jump(else_jump)
}

fn push_loop(start, local_base) {
  cur.loop = {enclosing: cur.loop, start: start, local_base: local_base, try_depth: cur.try_depth, breaks: []}
}

fn pop_loop() {
  let l = cur.loop
  for b in l.breaks { patch_jump(b) }
  cur.loop = l.enclosing
}

fn while_statement() {
  let start = cur.code.len()
  push_loop(start, cur.locals.len())
  expression()
  let exit_jump = emit_jump(OP.JUMP_IF_FALSE)
  emit_byte(OP.POP)
  scoped_block()
  emit_loop(start)
  patch_jump(exit_jump)
  emit_byte(OP.POP)
  pop_loop()
}

fn for_statement() {
  begin_scope()
  consume("IDENT", "Expected a loop variable name after 'for'.")
  let var_name = ps.previous.text
  consume("in", "Expected 'in' after the loop variable.")
  expression()
  add_local("(iter)")
  mark_initialized()
  emit_constant(0)
  add_local("(idx)")
  mark_initialized()

  let iter_slot = cur.locals.len() - 2
  let start = cur.code.len()
  push_loop(start, cur.locals.len())

  emit_byte(OP.FOR_NEXT)
  emit_byte(iter_slot % 256)
  emit_byte(255)
  emit_byte(255)
  let exit_jump = cur.code.len() - 2     # taken when the iterable is used up

  begin_scope()
  add_local(var_name)
  mark_initialized()
  scoped_block()
  end_scope()
  emit_loop(start)
  patch_jump(exit_jump)
  pop_loop()
  end_scope()
}

fn return_statement() {
  if cur.type == "script" { error("Can't return from top-level code.") }
  if check("SEMI") or check("}") or check("EOF") {
    emit_return()
  } else {
    if cur.type == "initializer" { error("Can't return a value from init().") }
    expression()
    if cur.ret_spec != "" { emit_check_top(cur.ret_spec, "return value of " + cur.label) }
    emit_byte(OP.RETURN)
  }
  end_statement()
}

fn break_continue(is_break) {
  let l = cur.loop
  if l == nil {
    error(is_break and "'break' can only be used inside a loop." or "'continue' can only be used inside a loop.")
    end_statement()
    return
  }
  let i = cur.try_depth
  while i > l.try_depth {
    emit_byte(OP.END_TRY)
    i -= 1
  }
  emit_pops_to(l.local_base)
  if is_break {
    if l.breaks.len() == 64 { error("Too many 'break' statements in one loop.") }
    else { l.breaks.push(emit_jump(OP.JUMP)) }
  } else {
    emit_loop(l.start)
  }
  end_statement()
}

fn try_statement() {
  let try_jump = emit_jump(OP.TRY)
  cur.try_depth += 1
  scoped_block()
  cur.try_depth -= 1
  emit_byte(OP.END_TRY)
  let end_jump = emit_jump(OP.JUMP)
  patch_jump(try_jump)
  consume("catch", "Expected 'catch' after the try block.")
  begin_scope()
  consume("IDENT", "Expected a name for the error after 'catch'.")
  add_local(ps.previous.text)
  mark_initialized()
  scoped_block()
  end_scope()
  patch_jump(end_jump)
}

let SYNC_POINTS = {
  "let": true, "class": true, "fn": true, "for": true, "if": true, "while": true,
  "return": true, "try": true, "throw": true, "import": true,
}

# After an error: skip ahead to the start of the next statement.
fn synchronize() {
  ps.panic = false
  while ps.current.type != "EOF" {
    if ps.previous.type == "SEMI" { return }
    if SYNC_POINTS.has(ps.current.type) { return }
    advance()
  }
}

fn declaration() {
  ps.nesting += 1
  if ps.nesting > 200 {
    error("Blocks are nested too deeply.")
    ps.nesting -= 1
    if not check("EOF") { advance() }
    synchronize()
    return
  }
  if match("let") { let_declaration() }
  else if match("class") { class_declaration() }
  else if check("fn") and peek_next().type == "IDENT" {
    advance()
    fun_declaration()
  }
  else if match("import") { import_statement() }
  else { statement() }
  ps.nesting -= 1
  if ps.panic { synchronize() }
}

fn statement() {
  if match("if") { if_statement() }
  else if match("while") { while_statement() }
  else if match("for") { for_statement() }
  else if match("return") { return_statement() }
  else if match("break") { break_continue(true) }
  else if match("continue") { break_continue(false) }
  else if match("try") { try_statement() }
  else if match("throw") {
    expression()
    emit_byte(OP.THROW)
    end_statement()
  }
  else if check("{") {
    advance()
    begin_scope()
    block()
    end_scope()
  }
  else { expression_statement() }
}

# ------------------------------------------------------------- the rule table

# For each token type: [what it does at the start of an expression, what it does after an
# expression (an operator), how tightly that operator binds]. This is the heart of a Pratt parser.
let NO_RULE = [nil, nil, PREC_NONE]
let RULES = {
  "(": [grouping, call, PREC_CALL],
  "[": [list_literal, subscript, PREC_CALL],
  "{": [map_literal, nil, PREC_NONE],
  ".": [nil, dot, PREC_CALL],
  "-": [unary, binary, PREC_TERM],
  "+": [nil, binary, PREC_TERM],
  "/": [nil, binary, PREC_FACTOR],
  "*": [nil, binary, PREC_FACTOR],
  "%": [nil, binary, PREC_FACTOR],
  "**": [nil, binary, PREC_POWER],
  "..": [nil, binary, PREC_RANGE],
  "!=": [nil, binary, PREC_EQUALITY],
  "==": [nil, binary, PREC_EQUALITY],
  ">": [nil, binary, PREC_COMPARISON],
  ">=": [nil, binary, PREC_COMPARISON],
  "<": [nil, binary, PREC_COMPARISON],
  "<=": [nil, binary, PREC_COMPARISON],
  "in": [nil, binary, PREC_COMPARISON],
  "IDENT": [variable, nil, PREC_NONE],
  "STRING": [string, nil, PREC_NONE],
  "FSTRING": [string, nil, PREC_NONE],
  "NUMBER": [number, nil, PREC_NONE],
  "and": [nil, and_, PREC_AND],
  "or": [nil, or_, PREC_OR],
  "not": [unary, nil, PREC_NONE],
  "false": [literal, nil, PREC_NONE],
  "true": [literal, nil, PREC_NONE],
  "nil": [literal, nil, PREC_NONE],
  "fn": [lambda, nil, PREC_NONE],
  "self": [self_, nil, PREC_NONE],
  "super": [super_, nil, PREC_NONE],
  "|>": [nil, pipe_op, PREC_PIPE],
  "??": [nil, coalesce, PREC_COALESCE],
  "?.": [nil, optional_dot, PREC_CALL],
  "by": [nil, binary, PREC_RANGE],
}

fn get_rule(type) { return RULES.get(type, NO_RULE) }

# -------------------------------------------------------------- the entry point

# Compiles `source`. Options (a map, all optional):
#   repl: true     a bare expression at the top level prints its value
#   imports: true  also collect the paths of all `import "..."` statements
# Returns {ok: true, program, imports} or {ok: false, errors, eof}:
#   program  {functions: [...]}, see std/bytecode
#   errors   a list of {message, line, col, text, length}; text is the source line
#   eof      true when the code ended too early (more input could make it valid)
fn compile(source, options = nil) {
  let opts = options ?? {}
  ps = {
    toks: layout(source, 1), pos: 0, previous: nil, current: {type: "SEMI", text: "", line: 0, col: 0},
    had_error: false, panic: false, eof_error: false, nesting: 0, errors: [],
    src_lines: source.split("\n"), first_line: 1,
    repl: opts.repl ?? false, collect_imports: opts.imports ?? false, imports: [],
  }
  functions = []
  current_class = nil
  cur = nil
  begin_function("script", nil)

  advance()
  skip_semis()
  while not check("EOF") {
    declaration()
    skip_semis()
  }
  end_compiler()

  let result = nil
  if ps.had_error {
    result = {ok: false, errors: ps.errors, eof: ps.eof_error}
  } else {
    result = {ok: true, program: {functions: functions}, imports: ps.imports}
  }
  ps = nil
  cur = nil
  return result
}

# What the faxal program calls for --self-hosted: like compile(), but the program comes back
# as plain data that the virtual machine can load (see std/bytecode.to_wire).
fn compile_for_vm(source, repl, collect_imports) {
  let result = nil
  try {
    result = compile(source, {repl: repl, imports: collect_imports})
  } catch e {
    ps = nil
    cur = nil
    return {ok: false, eof: false, errors: [{message: "internal compiler error: " + str(e), line: 1, col: 1, text: "", length: 1}]}
  }
  if result.ok { return {ok: true, program: bc.to_wire(result.program), imports: result.imports} }
  return result
}
