# mdsite: turns a folder of Markdown files into a static website. A real program written in Faxal.
#
#   faxal apps/mdsite/main.fx docs public
#   faxal apps/mdsite/main.fx docs public --title "Faxal docs"
#   faxal apps/mdsite/main.fx docs public --serve 8000      # then open http://localhost:8000

import "site.fx" as site
import "std/http" as http
import "std/path" as path

fn usage() {
  print("usage: faxal main.fx <markdown-folder> <output-folder> [--title \"Site title\"] [--serve PORT]")
}

let args = os.args
let positional = []
let title = nil
let port = nil
let i = 0
while i < len(args) {
  let a = args[i]
  if a == "--title" and i + 1 < len(args) { title = args[i + 1]; i += 1 }
  else if a == "--serve" and i + 1 < len(args) { port = int(args[i + 1]); i += 1 }
  else if a == "--help" or a == "-h" { usage(); os.exit(0) }
  else if a.starts_with("--") { print("mdsite: unknown option " + a); usage(); os.exit(64) }
  else { positional.push(a) }
  i += 1
}
if len(positional) != 2 { usage(); os.exit(64) }

let source = positional[0]
let out = positional[1]
let result = nil
try {
  result = site.build(source, out, title = title)
} catch e {
  print(e)
  os.exit(1)
}
print("built " + str(result.pages) + " page" + (result.pages == 1 and "" or "s") + " into " + out + (result.copied > 0 and " (" + str(result.copied) + " other files copied)" or ""))

if port != nil {
  # a tiny file server for previewing the result
  let types = {".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".json": "application/json"}
  http.serve(port, fn(req) {
    let rel = req.path == "/" and "/index.html" or req.path
    if rel.contains("..") { return http.status_only(403) }
    let file = path.join(out, rel[1:])
    if fs.is_dir(file) { file = path.join(file, "index.html") }
    if not fs.exists(file) { return http.status_only(404) }
    return http.Response(200, fs.read(file), {"content-type": types.get(path.ext(file).lower(), "application/octet-stream")})
  }, on_start = fn(p) { print("serving on http://127.0.0.1:" + str(p) + "  (Ctrl+C to stop)") })
}
