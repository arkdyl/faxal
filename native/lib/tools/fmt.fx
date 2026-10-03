# faxal fmt: formats Faxal code. Written in Faxal.
#
#   faxal fmt                 format every .fx file under the current folder
#   faxal fmt app.fx lib/     format these files and folders
#   faxal fmt --check ...     don't change anything; exit with 1 if a file needs formatting
#   faxal fmt --stdout app.fx print the formatted code instead of writing it

import "std/fmt" as fmt

fn usage() {
  print("usage: faxal fmt [--check] [--stdout] [files or folders...]")
}

fn collect(path, out, explicit) {
  if fs.is_dir(path) {
    for name in fs.list(path) {
      if name.starts_with(".") or name == "fx_modules" or name == "node_modules" { continue }
      collect(path + "/" + name, out, false)
    }
  } else if explicit or path.ends_with(".fx") {
    out.push(path)
  }
}

let check = false
let to_stdout = false
let paths = []
for arg in os.args.slice(1) {
  if arg == "--check" { check = true }
  else if arg == "--stdout" { to_stdout = true }
  else if arg == "--help" or arg == "-h" { usage(); os.exit(0) }
  else if arg.starts_with("--") { print(f"faxal fmt: unknown option {arg}"); usage(); os.exit(64) }
  else { paths.push(arg) }
}
if paths.len() == 0 { paths.push(".") }

let files = []
for p in paths {
  if not fs.exists(p) {
    print(f"faxal fmt: cannot find {p}")
    os.exit(74)
  }
  collect(p, files, true)
}

let changed = 0
let failed = 0
for file in files {
  let source = fs.read(file)
  let result = nil
  try {
    result = fmt.format_checked(source)
  } catch e {
    print(f"{file}: {e}")
    failed += 1
    continue
  }
  if to_stdout {
    write(result)
  } else if result != source {
    changed += 1
    if check {
      print(f"would reformat {file}")
    } else {
      fs.write(file, result)
      print(f"formatted {file}")
    }
  }
}

if not to_stdout {
  let verb = check and "would be reformatted" or "reformatted"
  print(f"{changed} {verb}, {files.len() - changed - failed} already formatted")
}
if failed > 0 or (check and changed > 0) { os.exit(1) }
