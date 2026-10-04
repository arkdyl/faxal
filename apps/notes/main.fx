# Notes: a small web app written in Faxal.
#
#   faxal apps/notes/main.fx                       # http://127.0.0.1:8080, notes saved in notes.json
#   faxal apps/notes/main.fx --port 3000 --data my-notes.json
#
# Uses std/http (an async server: every connection is a task), std/tasks, std/datetime, json and fs.

import "std/http" as http
import "std/tasks" as tasks
import "store.fx" as store
import "app.fx" as app

let port = 8080
let data_file = "notes.json"
let host = "127.0.0.1"
let limit = nil
let args = os.args
let i = 0
while i < len(args) {
  let a = args[i]
  if a == "--port" and i + 1 < len(args) { port = int(args[i + 1]); i += 1 }
  else if a == "--data" and i + 1 < len(args) { data_file = args[i + 1]; i += 1 }
  else if a == "--host" and i + 1 < len(args) { host = args[i + 1]; i += 1 }
  else if a == "--limit" and i + 1 < len(args) { limit = int(args[i + 1]); i += 1 }   # stop after this many requests (for tests)
  else {
    print("usage: faxal main.fx [--port 8080] [--data notes.json] [--host 127.0.0.1]")
    os.exit(a == "--help" and 0 or 64)
  }
  i += 1
}

let notes = store.Store(data_file)
print("notes: " + str(len(notes.notes)) + " saved in " + data_file)
tasks.run(http.serve_async(port, app.make(notes), host = host, limit = limit, on_start = fn(p) {
  print("listening on http://" + host + ":" + str(p) + "   (Ctrl+C to stop)")
  os.flush()
}))
