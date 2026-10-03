# std/bytecode: Faxal's bytecode, described in Faxal.
#
# A compiled program is a list of functions. Every function is a map:
#   name          the function's name, or nil for a lambda or the main script
#   arity         how many parameters it has, min_arity how many are required
#   upvalue_count how many outer variables it captures
#   is_script     true for the main code of a file
#   code          a list of bytes (numbers from 0 to 255): the instructions
#   lines         the source line of every byte of code
#   constants     numbers, strings, and other functions (as the function map itself)
# The functions are listed in the order the compiler finished them: inner functions come
# before the function that contains them, and the main script is last.

import "std/text" as tx

# The opcode numbers. This list must match the OpCode enum in native/src/faxal.h, in order.
let OPS = [
  "CONSTANT", "NIL", "TRUE", "FALSE", "POP", "DUP", "DUP2",
  "GET_LOCAL", "SET_LOCAL", "GET_GLOBAL", "DEFINE_GLOBAL", "SET_GLOBAL",
  "GET_UPVALUE", "SET_UPVALUE", "GET_PROPERTY", "SET_PROPERTY",
  "GET_INDEX", "SET_INDEX", "SLICE",
  "EQUAL", "GREATER", "LESS", "ADD", "SUB", "MUL", "DIV", "MOD", "POW",
  "NEG", "NOT", "IN", "RANGE",
  "JUMP", "JUMP_IF_FALSE", "LOOP",
  "CALL", "INVOKE", "CLOSURE", "CLOSE_UPVALUE", "RETURN",
  "BUILD_LIST", "BUILD_MAP", "FOR_NEXT",
  "TRY", "END_TRY", "THROW", "IMPORT", "REPL_PRINT",
  "CLASS", "INHERIT", "METHOD", "GET_SUPER", "SUPER_INVOKE",
  "SWAP", "BY", "JUMP_IF_NIL", "JUMP_IF_NOT_NIL",
]

# OP.ADD is the number of the ADD instruction, and so on.
let OP = {}
for i in 0..OPS.len() { OP[OPS[i]] = i }

fn _constant_text(c) {
  let t = type(c)
  if t == "map" { return "<fn " + (c.name ?? "anonymous") + ">" }
  return repr(c)
}

fn _u16(code, i) { return code[i] * 256 + code[i + 1] }

# One function as text, in exactly the format of `faxal --dump`.
fn disassemble_function(f) {
  let out = []
  let code = f.code
  let title = f.name ?? (f.is_script and "<script>" or "<lambda>")
  out.push("== " + title + " ==")
  let off = 0
  while off < code.len() {
    let name = OPS[code[off]]
    let line = tx.pad_left(str(off), 4, "0") + " "
    if off > 0 and f.lines[off] == f.lines[off - 1] { line += "   | " } else { line += tx.pad_left(str(f.lines[off]), 4) + " " }
    line += tx.pad_right(name, 16)
    let next = off + 1
    if ["CONSTANT", "GET_GLOBAL", "DEFINE_GLOBAL", "SET_GLOBAL", "GET_PROPERTY", "SET_PROPERTY", "CLASS", "METHOD", "GET_SUPER"].contains(name) {
      let idx = _u16(code, off + 1)
      line += " " + tx.pad_left(str(idx), 4) + " '" + _constant_text(f.constants[idx]) + "'"
      next = off + 3
    } else if ["GET_LOCAL", "SET_LOCAL", "GET_UPVALUE", "SET_UPVALUE", "CALL"].contains(name) {
      line += " " + tx.pad_left(str(code[off + 1]), 4)
      next = off + 2
    } else if ["JUMP", "JUMP_IF_FALSE", "TRY", "JUMP_IF_NIL", "JUMP_IF_NOT_NIL"].contains(name) {
      line += " " + tx.pad_left(str(off), 4) + " -> " + str(off + 3 + _u16(code, off + 1))
      next = off + 3
    } else if name == "LOOP" {
      line += " " + tx.pad_left(str(off), 4) + " -> " + str(off + 3 - _u16(code, off + 1))
      next = off + 3
    } else if name == "INVOKE" or name == "SUPER_INVOKE" {
      let idx = _u16(code, off + 1)
      line += " (" + str(code[off + 3]) + " args) '" + _constant_text(f.constants[idx]) + "'"
      next = off + 4
    } else if name == "BUILD_LIST" or name == "BUILD_MAP" {
      line += " " + tx.pad_left(str(_u16(code, off + 1)), 4)
      next = off + 3
    } else if name == "FOR_NEXT" {
      line += " slot " + str(code[off + 1]) + ", exit -> " + str(off + 4 + _u16(code, off + 2))
      next = off + 4
    } else if name == "CLOSURE" {
      let idx = _u16(code, off + 1)
      let inner = f.constants[idx]
      line += " " + tx.pad_left(str(idx), 4) + " '" + _constant_text(inner) + "'"
      out.push(line)
      line = nil
      next = off + 3
      for k in 0..inner.upvalue_count {
        out.push(tx.pad_left(str(next), 4, "0") + "    |                   " + (code[next] == 1 and "local" or "upvalue") + " " + str(code[next + 1]))
        next += 2
      }
    }
    if line != nil { out.push(line) }
    off = next
  }
  out.push("")
  return out.join("\n") + "\n"
}

# The whole program as text: the same text `faxal --dump` prints.
fn disassemble(program) {
  return program.functions.map(disassemble_function).join("")
}

# The program as plain data (numbers, strings, lists, maps) that json.encode can write and
# the faxal virtual machine can load.
fn to_wire(program) {
  let functions = []
  for f in program.functions {
    let constants = f.constants.map(fn(c) {
      let t = type(c)
      if t == "map" { return {"fn": c.index} }
      if t == "number" and (c != c or c == math.inf or c == -math.inf) {
        return {num: c != c and "nan" or (c > 0 and "inf" or "-inf")}
      }
      return c
    })
    functions.push({
      name: f.name,
      arity: f.arity,
      min_arity: f.min_arity,
      upvalues: f.upvalue_count,
      script: f.is_script,
      code: f.code,
      lines: f.lines,
      constants: constants,
    })
  }
  return {functions: functions}
}
