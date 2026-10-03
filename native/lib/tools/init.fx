# faxal init: starts a new project. Written in Faxal.
#
#   faxal init            set up a project in the current folder
#   faxal init my-app     create a folder my-app and set up a project in it

let name = os.args.len() > 1 and os.args[1] or nil
let dir = name ?? "."
if name != nil and not fs.exists(dir) { fs.mkdir(dir) }
let project = name ?? os.cwd().split("/")[-1]

let manifest = dir + "/faxal.json"
if fs.exists(manifest) {
  print("This folder already has a faxal.json.")
  os.exit(1)
}

fn make(path, text) {
  fs.write(dir + "/" + path, text)
  print("  created " + (name != nil and name + "/" or "") + path)
}

print(f"Creating a Faxal project called {project}")
make("faxal.json", json.encode({name: project, version: "0.1.0", main: "main.fx", dependencies: {}}, 2) + "\n")
make("main.fx", "import \"greeting\"\n\nprint(greeting.greet(\"world\"))\n")
make("greeting.fx", "fn greet(name) {\n  return f\"Hello, {name}!\"\n}\n")
fs.mkdir(dir + "/tests")
make("tests/greeting_test.fx", "import \"std/test\" as t\nimport \"../greeting\" as greeting\n\nt.test(\"greets by name\", fn() {\n  t.eq(greeting.greet(\"Faxal\"), \"Hello, Faxal!\")\n})\n")
make(".gitignore", "fx_modules/\n")

print("")
print("Next steps:")
if name != nil { print(f"  cd {name}") }
print("  faxal run          run the program")
print("  faxal test         run the tests")
print("  faxal fmt          tidy up the code")
print("  faxal add <pkg>    add a package")
