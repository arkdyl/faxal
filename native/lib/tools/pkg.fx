# faxal add / remove / install / list: a small package manager. Written in Faxal.
#
#   faxal add user/repo           a git repository (GitHub shorthand)
#   faxal add https://host/x.git  any git URL
#   faxal add ../shared/utils     a local folder (or a single .fx file)
#   faxal add <source> <name>     choose the name you import it by
#   faxal install                 install everything listed in faxal.json
#   faxal remove <name>
#   faxal list
#
# Packages live in fx_modules/ and are used with:  import "name"

let command = os.args[0]
let rest = os.args.slice(1)

fn usage() {
  print("usage: faxal add <source> [name] | install | remove <name> | list")
}

fn die(message) {
  print("faxal " + command + ": " + message)
  os.exit(1)
}

# Quote text for the shell.
fn q(s) { return "'" + s.replace("'", "'\\''") + "'" }

fn read_manifest() {
  if not fs.exists("faxal.json") {
    return {name: os.cwd().split("/")[-1], version: "0.1.0", main: "main.fx", dependencies: {}}
  }
  let m = json.decode(fs.read("faxal.json"))
  if m.dependencies == nil { m.dependencies = {} }
  return m
}

fn write_manifest(m) {
  fs.write("faxal.json", json.encode(m, 2) + "\n")
}

fn default_name(source) {
  let parts = source.split("/").filter(fn(p) { return len(p) > 0 })
  let last = parts[-1]
  if last.ends_with(".git") { last = last[:-4] }
  if last.ends_with(".fx") { last = last[:-3] }
  return last
}

fn install(name, source) {
  fs.mkdir("fx_modules")
  let dest = "fx_modules/" + name
  os.run("rm -rf " + q(dest) + " " + q(dest + ".fx"))

  if fs.exists(source) {
    let how = fs.is_dir(source) and "cp -R " + q(source) + " " + q(dest) or "cp " + q(source) + " " + q(dest + ".fx")
    let r = os.run(how)
    if r.code != 0 { die("could not copy " + source + ": " + r.output.trim()) }
  } else {
    let url = source
    if not (source.contains("://") or source.starts_with("git@")) {
      if source.split("/").len() != 2 { die("cannot find " + source) }
      url = "https://github.com/" + source + ".git"
    }
    let r = os.run("git clone --depth 1 " + q(url) + " " + q(dest))
    if r.code != 0 { die("git could not fetch " + url + ":\n" + r.output.trim()) }
    os.run("rm -rf " + q(dest + "/.git"))
  }
  print(f"  installed {name} from {source}")
}

if command == "add" {
  if rest.len() < 1 { usage(); os.exit(64) }
  let source = rest[0]
  let name = rest.len() > 1 and rest[1] or default_name(source)
  install(name, source)
  let m = read_manifest()
  m.dependencies[name] = source
  write_manifest(m)
} else if command == "install" {
  let m = read_manifest()
  let names = m.dependencies.keys()
  if names.len() == 0 { print("Nothing to install: faxal.json has no dependencies.") }
  for name in names { install(name, m.dependencies[name]) }
} else if command == "remove" {
  if rest.len() < 1 { usage(); os.exit(64) }
  let m = read_manifest()
  if not m.dependencies.has(rest[0]) { die(rest[0] + " is not in faxal.json") }
  m.dependencies.remove(rest[0])
  os.run("rm -rf " + q("fx_modules/" + rest[0]) + " " + q("fx_modules/" + rest[0] + ".fx"))
  write_manifest(m)
  print(f"  removed {rest[0]}")
} else if command == "list" {
  let m = read_manifest()
  if m.dependencies.len() == 0 { print("No packages. Add one with: faxal add <source>") }
  for name in m.dependencies.keys() {
    let here = fs.exists("fx_modules/" + name) or fs.exists("fx_modules/" + name + ".fx")
    let status = here and "(installed)" or "(missing: run faxal install)"
    print(f"{name}  {m.dependencies[name]}  {status}")
  }
} else {
  usage()
  os.exit(64)
}
