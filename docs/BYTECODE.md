## Bytecode files (.fxc)

A `.fxc` file is a compiled Faxal module: the instructions, line numbers and constants of every function in it. `faxal compile app.fx` writes one, `faxal app.fxc` runs it, and `faxal build` packs them into executables. This page describes the format (version 1).

All numbers are little-endian. A *string* is a `u32` length followed by that many bytes.

## Layout

```text
file      = header function* checksum
header    = magic  version  revision  flags  faxal-version  source-name  function-count
magic     = 7F 46 58 43              (the bytes DEL, "F", "X", "C": DEL can never start valid source code)
version   = u16                      the file format, currently 1
revision  = u16                      the instruction set, see below
flags     = u32                      0 for now
faxal-version = string               the faxal that wrote the file (informational)
source-name   = string               the name of the source file (used in error traces; imports resolve next to the .fxc)
function-count = u32

function  = name arity min-arity upvalue-count is-script
            code-length code
            run-count run*
            constant-count constant*
name      = string, or the single value FFFFFFFF for "no name" (a lambda or the main script)
arity     = u8      parameters
min-arity = u8      parameters without a default value
upvalue-count = u16 outer variables captured
is-script = u8      1 for the main code of the file, else 0
code      = bytes   the instructions
run       = line:u32 length:u32     the next `length` bytes of code come from source line `line`
constant  = 00 f64                 a number (the 8 bytes of the IEEE 754 double)
          | 01 string              a string (any bytes)
          | 02 u32                 a function: its position in this file's function list

checksum  = u32      FNV-1a (32 bit) of every byte before it
```

Functions are stored so that a function comes after every function it contains, and the main script (the file's own code) is last. A function constant may only refer to a function that comes earlier in the list, so functions can't contain themselves.

The **revision** identifies the instruction set. It changes whenever an instruction is added, removed, reordered or changes meaning (`FAXAL_BYTECODE_REVISION` in `native/src/faxal.h`). A faxal refuses files with a different revision and asks you to compile again.

## Instructions

An instruction is one byte (its number) followed by its operands. `u16` operands are big-endian (high byte first). "Stack" is the change in the number of values on the operand stack.

| # | Name | Operands | Stack | What it does |
| --- | --- | --- | --- | --- |
| 0 | `CONSTANT` | u16 constant | +1 | push a constant |
| 1 | `NIL` | - | +1 | push nil |
| 2 | `TRUE` | - | +1 | push true |
| 3 | `FALSE` | - | +1 | push false |
| 4 | `POP` | - | -1 | discard the top value |
| 5 | `DUP` | - | +1 | copy the top value |
| 6 | `DUP2` | - | +2 | copy the top two values |
| 7 | `GET_LOCAL` | u8 slot | +1 | push a local variable (a slot of the current stack frame) |
| 8 | `SET_LOCAL` | u8 slot | 0 | store the top value in a local (keeps it) |
| 9 | `GET_GLOBAL` | u16 name | +1 | push a global (the name is a string constant) |
| 10 | `DEFINE_GLOBAL` | u16 name | -1 | create a global from the top value |
| 11 | `SET_GLOBAL` | u16 name | 0 | assign an existing global |
| 12 | `GET_UPVALUE` | u8 number | +1 | push a captured variable |
| 13 | `SET_UPVALUE` | u8 number | 0 | store into a captured variable |
| 14 | `GET_PROPERTY` | u16 name | 0 | replace an object by one of its properties |
| 15 | `SET_PROPERTY` | u16 name | -1 | set a property (leaves the value) |
| 16 | `GET_INDEX` | - | -1 | obj[index] |
| 17 | `SET_INDEX` | - | -2 | obj[index] = value (leaves the value) |
| 18 | `SLICE` | - | -2 | obj[start:end] |
| 19 | `EQUAL` | - | -1 | == |
| 20 | `GREATER` | - | -1 | > |
| 21 | `LESS` | - | -1 | < |
| 22 | `ADD` | - | -1 | + |
| 23 | `SUB` | - | -1 | - |
| 24 | `MUL` | - | -1 | * |
| 25 | `DIV` | - | -1 | / |
| 26 | `MOD` | - | -1 | % |
| 27 | `POW` | - | -1 | ** |
| 28 | `NEG` | - | 0 | negate |
| 29 | `NOT` | - | 0 | logical not |
| 30 | `IN` | - | -1 | `in` |
| 31 | `RANGE` | - | -1 | `a..b` |
| 32 | `JUMP` | u16 forward | 0 | jump forward |
| 33 | `JUMP_IF_FALSE` | u16 forward | 0 | jump forward if the top value is falsy (does not pop) |
| 34 | `LOOP` | u16 backward | 0 | jump backward |
| 35 | `CALL` | u8 argc | -argc | call the function below the arguments |
| 36 | `INVOKE` | u16 name, u8 argc | -argc | call a method |
| 37 | `CLOSURE` | u16 function, then 2 bytes per upvalue | +1 | make a closure; each upvalue is (1 = local slot / 0 = enclosing upvalue, index) |
| 38 | `CLOSE_UPVALUE` | - | -1 | move a captured local off the stack, then pop it |
| 39 | `RETURN` | - | end | return the top value |
| 40 | `BUILD_LIST` | u16 n | 1-n | make a list from the top n values |
| 41 | `BUILD_MAP` | u16 n | 1-2n | make a map from the top n key/value pairs |
| 42 | `FOR_NEXT` | u8 slot, u16 forward | +1, or 0 when jumping | next item of the loop at `slot`; jumps forward when there are no more |
| 43 | `TRY` | u16 forward | 0 | start a try block; the catch code is `forward` bytes on (it arrives with the error pushed: +1) |
| 44 | `END_TRY` | - | 0 | leave a try block |
| 45 | `THROW` | - | end | throw the top value |
| 46 | `IMPORT` | - | 0 | replace a module path by the module |
| 47 | `REPL_PRINT` | - | -1 | print the top value (the REPL) |
| 48 | `CLASS` | u16 name | +1 | make a class |
| 49 | `INHERIT` | - | -1 | copy a superclass's methods into the class |
| 50 | `METHOD` | u16 name | -1 | add a method to the class |
| 51 | `GET_SUPER` | u16 name | -1 | bind a superclass method |
| 52 | `SUPER_INVOKE` | u16 name, u8 argc | -argc-1 | call a superclass method |
| 53 | `SWAP` | - | 0 | swap the top two values |
| 54 | `BY` | - | -1 | `range by step` |
| 55 | `JUMP_IF_NIL` | u16 forward | 0 | jump forward if the top value is nil (does not pop) |
| 56 | `JUMP_IF_NOT_NIL` | u16 forward | 0 | jump forward if the top value is not nil (does not pop) |

## Verification

Reading a `.fxc` never trusts it. In this order:

- the magic, versions and **checksum** must match (a damaged file is reported as damaged);
- every length in the file is checked against the bytes that are left, before anything is allocated;
- the **verifier** analyzes every function before anything runs. It proves that every instruction is a real one and lies completely inside the code; that every jump (and every catch target) lands exactly on the start of an instruction and that code never runs off its end; that the stack never underflows, never grows past a fixed limit and has the **same height** whenever an instruction is reached by different routes; that local slots, upvalue numbers and constant numbers exist; that names are strings and closures capture variables that exist.

What can only be known while running (is this value a list? a number?) is checked by the virtual machine itself and raises an ordinary error.

The result: a damaged or hostile `.fxc` is rejected with a message, or runs without being able to corrupt memory. This is tested by corrupting thousands of files (with a recomputed checksum, so that the damage reaches the verifier) and running them under AddressSanitizer. Running untrusted code is still running code: use `faxal --sandbox` to keep it away from your files, and its time and memory limits.

## Tools

```bash
faxal compile app.fx [-o app.fxc]   # write a bytecode file (default: app.fxc next to app.fx)
faxal app.fxc [args...]             # run it; the .fx file is not needed
faxal check app.fxc                 # verify a file without running it
faxal dump app.fxc                  # print the instructions, same format as `faxal --dump`
faxal --c-compiler compile app.fx   # the same file, written by the compiler written in C
```

The two compilers (Faxal, the default, and C) write byte-for-byte the same file for the same source. The standard library built into faxal is stored in this format. `import "lib"` also finds a compiled `lib.fxc` (a `.fx` source next to it wins, if both exist).
