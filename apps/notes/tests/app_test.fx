import "std/test" as t
import "std/http" as http
import "std/tasks" as tasks
import "../store.fx" as store
import "../app.fx" as app

t.test("the whole app over real HTTP", fn() {
  let notes = store.Store()
  async fn main() {
    let port = nil
    let server = tasks.spawn(http.serve_async(0, app.make(notes), "127.0.0.1", 11, fn(p) { port = p }))
    await nil
    let base = "http://127.0.0.1:" + str(port)
    let post = fn(path, value) => http.request_async("POST", base + path, json.encode(value), {"content-type": "application/json"})

    let r = await http.get_async(base + "/")
    t.eq([r.status, r.headers["content-type"]], [200, "text/html; charset=utf-8"])
    t.ok(r.text().contains("entirely in <a href"))

    r = await post("/api/notes", {text: "Buy milk", tags: ["home"]})
    t.eq([r.status, r.json().id, r.json().tags], [201, 1, ["home"]])
    r = await post("/api/notes", {text: "Call Ada"})
    t.eq(r.json().id, 2)
    r = await post("/api/notes", {text: "  "})
    t.eq([r.status, r.json().error], [400, "a note needs some text"])
    r = await http.request_async("POST", base + "/api/notes", "not json")
    t.eq([r.status, r.json().error], [400, "the body must be JSON"])

    r = await http.get_async(base + "/api/notes?q=MILK")
    t.eq(r.json().map(fn(n) => n.text), ["Buy milk"])
    r = await http.get_async(base + "/api/notes/2")
    t.eq(r.json().text, "Call Ada")
    r = await http.request_async("PUT", base + "/api/notes/2", json.encode({text: "Call Ada back", tags: ["people"]}), {"content-type": "application/json"})
    t.eq([r.status, r.json().text, r.json().tags], [200, "Call Ada back", ["people"]])
    r = await http.get_async(base + "/api/tags")
    t.eq(r.json(), {home: 1, people: 1})
    r = await http.request_async("DELETE", base + "/api/notes/1")
    t.eq(r.status, 204)
    r = await http.get_async(base + "/api/notes/1")
    t.eq(r.status, 404)
    await server
  }
  tasks.run(main())
})

t.run()
