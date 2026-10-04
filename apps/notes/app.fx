# app.fx: the routes of the notes app.
#
#   GET    /                 the web page
#   GET    /api/notes        list (newest first); ?q=text and ?tag=name filter
#   POST   /api/notes        {text, tags?} -> the new note (201)
#   GET    /api/notes/:id    one note
#   PUT    /api/notes/:id    {text?, tags?} -> the changed note
#   DELETE /api/notes/:id    204
#   GET    /api/tags         {tag: count, ...}

import "std/http" as http
import "page.fx" as page

fn _note_id(req) {
  let id = int(req.params.id)
  return id
}

fn _body(req) {
  let data = nil
  try { data = req.json() } catch e { throw "the body must be JSON" }
  if type(data) != "map" { throw "the body must be a JSON object" }
  return data
}

# Builds the router for a Store.
fn make(store) {
  let app = http.Router()

  app.get("/", fn(req) => http.html(page.HTML))

  app.get("/api/notes", fn(req) => http.send_json(store.search(query = req.query.get("q"), tag = req.query.get("tag"))))

  app.post("/api/notes", fn(req) {
    try {
      let data = _body(req)
      return http.send_json(store.add(data.text ?? "", tags = data.tags ?? []), 201)
    } catch e {
      return http.send_json({error: str(e)}, 400)
    }
  })

  app.get("/api/notes/:id", fn(req) {
    let note = store.get(_note_id(req))
    if note == nil { return http.send_json({error: "no such note"}, 404) }
    return http.send_json(note)
  })

  app.put("/api/notes/:id", fn(req) {
    try {
      let data = _body(req)
      let note = store.update(_note_id(req), text = data.text, tags = data.tags)
      if note == nil { return http.send_json({error: "no such note"}, 404) }
      return http.send_json(note)
    } catch e {
      return http.send_json({error: str(e)}, 400)
    }
  })

  app.delete("/api/notes/:id", fn(req) {
    if not store.remove(_note_id(req)) { return http.send_json({error: "no such note"}, 404) }
    return http.Response(204)
  })

  app.get("/api/tags", fn(req) => http.send_json(store.tag_counts()))
  return app
}
