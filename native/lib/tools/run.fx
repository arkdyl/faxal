# faxal run (with no file): runs the "main" file named in faxal.json. Written in Faxal.

if not fs.exists("faxal.json") {
  print("faxal run: no file was given and there is no faxal.json here.")
  print("Start a project with:  faxal init")
  os.exit(64)
}
let manifest = json.decode(fs.read("faxal.json"))
load("./" + (manifest?.main ?? "main.fx"))
