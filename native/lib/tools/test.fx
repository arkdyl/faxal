# faxal test: finds and runs tests. Written in Faxal.
#
#   faxal test                       run every *_test.fx file under the current folder
#   faxal test tests/                ... or under this folder (or just this file)
#   faxal test --filter=login        only tests whose name contains "login"
#
# A test file looks like:
#   import "std/test" as t
#   t.test("adds", fn() { t.eq(1 + 1, 2) })

import "std/test" as t

let root = "."
let filter = nil
for arg in os.args.slice(1) {
  if arg.starts_with("--filter=") { filter = arg[9:] }
  else if arg == "--help" or arg == "-h" {
    print("usage: faxal test [folder or file] [--filter=text]")
    os.exit(0)
  }
  else { root = arg }
}

fn find_tests(path, out) {
  if fs.is_dir(path) {
    for name in fs.list(path) {
      if name.starts_with(".") or name == "fx_modules" or name == "node_modules" { continue }
      find_tests(path + "/" + name, out)
    }
  } else if path.ends_with("_test.fx") {
    out.push(path)
  }
}

if not fs.exists(root) {
  print(f"faxal test: cannot find {root}")
  os.exit(74)
}
let files = []
find_tests(root, files)
if files.len() == 0 {
  print("No test files found. Test files are named like name_test.fx")
  os.exit(0)
}

let load_failures = 0
for file in files {
  t.state.file = file
  try {
    load(file)
  } catch e {
    load_failures += 1
    print(file)
    print(f"  FAIL  could not load this file: {e}")
  }
}

let result = t.run(filter)
if result.failed > 0 or load_failures > 0 { os.exit(1) }
