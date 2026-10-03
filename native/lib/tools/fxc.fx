# faxal fxc: compile a file with the compiler written in Faxal (std/compiler).
#
#   faxal fxc file.fx            print the bytecode, in the same format as `faxal --dump`
#   faxal fxc --wire file.fx     print the program as JSON (what the virtual machine loads)
#   faxal fxc --check file.fx    only report whether it compiles
#   faxal fxc --errors file.fx   print the errors as "line:col: message" lines

import "std/compiler" as fxc
import "std/bytecode" as bc

let mode = "dump"
let path = nil
for arg in os.args.slice(1) {
  if arg == "--wire" { mode = "wire" }
  else if arg == "--check" { mode = "check" }
  else if arg == "--errors" { mode = "errors" }
  else if arg == "--help" or arg == "-h" {
    print("usage: faxal fxc [--wire | --check | --errors] file.fx")
    os.exit(0)
  }
  else { path = arg }
}
if path == nil {
  print("usage: faxal fxc [--wire | --check | --errors] file.fx")
  os.exit(64)
}
if not fs.exists(path) {
  print(f"faxal fxc: cannot open {path}")
  os.exit(74)
}

let result = fxc.compile(fs.read(path))
if not result.ok {
  for e in result.errors { print(f"{e.line}:{e.col}: {e.message}") }
  os.exit(65)
}
if mode == "dump" { write(bc.disassemble(result.program)) }
else if mode == "wire" { print(json.encode(bc.to_wire(result.program))) }
else if mode == "check" { print(f"{path}: ok") }
