import "std/test" as t
import "std/http" as http
import "std/tasks" as tasks

t.test("urls", fn() {
  let u = http.parse_url("http://example.com:8080/a/b?x=1#frag")
  t.eq([u.host, u.port, u.path], ["example.com", 8080, "/a/b?x=1"])
  u = http.parse_url("example.com")
  t.eq([u.host, u.port, u.path], ["example.com", 80, "/"])
  t.throws(fn() { http.parse_url("https://x.com/") }, "only http://")
  t.throws(fn() { http.parse_url("http:///x") }, "no host")
})

t.test("query strings", fn() {
  t.eq(http.parse_query("a=1&b=x%20y&c&d=a+b"), {a: "1", b: "x y", c: "", d: "a b"})
  t.eq(http.parse_query(""), {})
})

t.test("headers and bodies", fn() {
  t.eq(http.parse_headers(["Content-Type: text/html", "X-A:  1 ", "x-a: 2"]), {"content-type": "text/html", "x-a": "1, 2"})
  t.eq(http.decode_chunked("5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"), "hello world")
  t.eq(http.decode_chunked("5\r\nhel"), nil)
  t.eq(http.complete_body({"content-length": "5"}, "hello world", false), "hello")
  t.eq(http.complete_body({"content-length": "5"}, "hel", false), nil)
  t.throws(fn() { http.complete_body({"content-length": "5"}, "hel", true) }, "closed before")
  t.eq(http.complete_body({}, "all of it", true), "all of it")
  t.eq(http.complete_body({}, "so far", false), nil)
  let parts = http.split_head("GET / HTTP/1.1\r\nHost: x\r\n\r\nbody")
  t.eq(parts, ["GET / HTTP/1.1\r\nHost: x", "body"])
  t.eq(http.split_head("GET / HT"), nil)
})

t.test("responses", fn() {
  let r = http.send_json({a: 1}, 201)
  t.eq([r.status, r.reason, r.ok, r.body], [201, "Created", true, "{\"a\":1}"])
  t.eq(r.json(), {a: 1})
  t.eq(http.status_only(404).ok, false)
  t.eq(http.redirect("/x").headers["location"], "/x")
  t.eq(http.to_response("<p>x</p>").headers["content-type"], "text/html; charset=utf-8")
  t.eq(http.to_response("x").headers["content-type"], "text/plain; charset=utf-8")
  t.eq(http.to_response([1, 2]).body, "[1,2]")
  t.eq(http.to_response(nil).status, 204)
})

t.test("router", fn() {
  let app = http.Router()
  app.get("/notes/:id", fn(req) => http.text("note " + req.params.id))
  app.get("/files/*", fn(req) => http.text("file " + req.params.rest))
  app.post("/notes", fn(req) => http.text("created"))
  let ask = fn(method, target) => app.handle(http.Request(method, target, {}, ""))
  t.eq(ask("GET", "/notes/42").body, "note 42")
  t.eq(ask("GET", "/notes/a%20b?x=1").body, "note a b")
  t.eq(ask("GET", "/files/a/b/c.txt").body, "file a/b/c.txt")
  t.eq(ask("POST", "/notes").body, "created")
  t.eq(ask("GET", "/nope").status, 404)
  t.eq(ask("DELETE", "/notes/1").status, 405)
  t.eq(ask("GET", "/notes").status, 405)
  let req = http.Request("GET", "/search?q=a%26b&n=2", {"host": "x"}, "")
  t.eq([req.path, req.query, req.header("Host")], ["/search", {q: "a&b", n: "2"}, "x"])
})

t.test("a client and a server in one program", fn() {
  let app = http.Router()
  app.get("/hello", fn(req) => http.text("Hello, " + (req.query.name ?? "you")))
  app.post("/echo", async fn(req) {
    await tasks.sleep(0.01)
    return http.send_json({got: req.json()}, 201)
  })
  app.get("/boom", fn(req) { throw "kaput" })
  app.get("/redir", fn(req) => http.redirect("/hello?name=there"))
  async fn main() {
    let port = nil
    let server = tasks.spawn(http.serve_async(0, app, "127.0.0.1", 6, fn(p) { port = p }))
    await nil
    let base = "http://127.0.0.1:" + str(port)
    let r = await http.get_async(base + "/hello?name=Ada")
    t.eq([r.status, r.text()], [200, "Hello, Ada"])
    r = await http.request_async("POST", base + "/echo", json.encode([1, 2]), {"content-type": "application/json"})
    t.eq([r.status, r.json()], [201, {got: [1, 2]}])
    r = await http.get_async(base + "/boom")
    t.eq(r.status, 500)
    r = await http.get_async(base + "/redir")
    t.eq(r.text(), "Hello, there")
    r = await http.get_async(base + "/missing")
    t.eq([r.status, r.ok], [404, false])
    await server
  }
  tasks.run(main())
})

t.test("errors", fn() {
  t.throws(fn() { http.get("http://127.0.0.1:1/") }, "can't connect")
  t.throws(fn() { net.read(200) }, "closed")
})

t.run()
