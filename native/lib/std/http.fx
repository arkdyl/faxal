# std/http: an HTTP/1.1 client and server, written in Faxal on top of the `net` functions.
#
#   import "std/http" as http
#
#   let res = http.get("http://example.com/")        # a Response: status, ok, headers, body, text(), json()
#   print(res.status, res.headers["content-type"])
#   http.post("http://localhost:8080/notes", json.encode({text: "hi"}), {"content-type": "application/json"})
#
#   fn handler(req) {                                 # a tiny server: handler(request) returns a response
#     if req.path == "/hello" { return http.text("Hello, " + (req.query.name ?? "you")) }
#     return http.send_json({path: req.path, method: req.method})
#   }
#   http.serve(8080, handler)
#
# The same as a Router, and as async tasks (many connections at once):
#
#   let app = http.Router()
#   app.get("/notes/:id", fn(req) => http.send_json({id: req.params.id}))
#   app.post("/notes", async fn(req) { return http.send_json(req.json(), 201) })
#   tasks.run(http.serve_async(8080, app))
#
# Plain http:// only (there is no TLS yet). Not available in safe mode (it needs the network).

import "std/tasks" as tasks
import "std/encoding" as enc

let _REASONS = {
  200: "OK", 201: "Created", 202: "Accepted", 204: "No Content", 301: "Moved Permanently", 302: "Found", 303: "See Other",
  304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized",
  403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 408: "Request Timeout", 409: "Conflict", 410: "Gone",
  413: "Payload Too Large", 415: "Unsupported Media Type", 418: "I'm a teapot", 422: "Unprocessable Entity",
  429: "Too Many Requests", 500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway",
  503: "Service Unavailable", 504: "Gateway Timeout",
}
let MAX_HEAD = 65536
let MAX_BODY = 10485760

fn reason(status) { return _REASONS.get(status, "Status " + str(status)) }

# ------------------------------------------------------------------ messages

# A response, from a server or to a client. status, reason, headers (lowercase names), body, ok (2xx).
class Response {
  fn init(status = 200, body = "", headers = nil) {
    self.status = status
    self.reason = reason(status)
    self.body = body
    self.headers = headers ?? {}
    self.ok = status >= 200 and status < 300
  }
  fn text() => self.body
  fn json() => json.decode(self.body)
  fn header(name) => self.headers.get(name.lower())
  fn to_str() => "<Response " + str(self.status) + " " + self.reason + ">"
}

# A request, as a server sees it: method, path (without the query), query (a map), headers (lowercase names),
# body, params (filled in by a Router from patterns like /notes/:id).
class Request {
  fn init(method, target, headers, body) {
    self.method = method
    self.target = target
    let q = target.find("?")
    self.path = q >= 0 and url_decode_path(target[0:q]) or url_decode_path(target)
    self.query = q >= 0 and parse_query(target[q + 1:]) or {}
    self.headers = headers
    self.body = body
    self.params = {}
  }
  fn header(name) => self.headers.get(name.lower())
  fn json() => json.decode(self.body)
  fn form() => parse_query(self.body)
  fn to_str() => "<Request " + self.method + " " + self.target + ">"
}

fn url_decode_path(p) => enc.url_decode(p, false)

# "a=1&b=x%20y" -> {a: "1", b: "x y"}
fn parse_query(text) {
  let out = {}
  if text == "" { return out }
  for pair in text.split("&") {
    if pair == "" { continue }
    let eq = pair.find("=")
    if eq < 0 { out[enc.url_decode(pair)] = "" }
    else { out[enc.url_decode(pair[0:eq])] = enc.url_decode(pair[eq + 1:]) }
  }
  return out
}

fn text(body, status = 200) => Response(status, str(body), {"content-type": "text/plain; charset=utf-8"})
fn html(body, status = 200) => Response(status, str(body), {"content-type": "text/html; charset=utf-8"})
fn send_json(value, status = 200) => Response(status, json.encode(value), {"content-type": "application/json"})
fn redirect(url, status = 302) => Response(status, "", {"location": url})
fn status_only(status) => Response(status, reason(status), {"content-type": "text/plain; charset=utf-8"})

# What a handler may return: a Response, text, a map or list (sent as JSON), true/nil (204).
fn to_response(value) {
  if isinstance(value, Response) { return value }
  if type(value) == "string" { return value.starts_with("<") and html(value) or text(value) }
  if type(value) == "map" or type(value) == "list" { return send_json(value) }
  if value == nil { return Response(204, "") }
  return text(str(value))
}

# ------------------------------------------------------------ parsing (pure)

# Splits "head\r\n\r\nrest": [head, rest], or nil when the head isn't complete yet.
fn split_head(buf) {
  let i = buf.find("\r\n\r\n")
  if i < 0 { return nil }
  return [buf[0:i], buf[i + 4:]]
}

# "Name: value" lines -> map with lowercase names (repeated names are joined with ", ")
fn parse_headers(lines) {
  let headers = {}
  for line in lines {
    let colon = line.find(":")
    if colon <= 0 { continue }
    let name = line[0:colon].trim().lower()
    let value = line[colon + 1:].trim()
    headers[name] = headers.has(name) and headers[name] + ", " + value or value
  }
  return headers
}

# Decodes a chunked body. Returns the text, or nil if it is not complete yet.
fn decode_chunked(raw) {
  let out = []
  let pos = 0
  while true {
    let eol = raw.find("\r\n", pos)
    if eol < 0 { return nil }
    let size_text = raw[pos:eol].split(";")[0].trim()
    let size = 0
    for c in size_text.lower().chars() {
      let d = "0123456789abcdef".find(c)
      if d < 0 { throw "http: bad chunk size " + repr(size_text) }
      size = size * 16 + d
    }
    pos = eol + 2
    if size == 0 { return out.join("") }       # (trailers, if any, are ignored)
    if pos + size + 2 > len(raw) { return nil }
    out.push(raw[pos:pos + size])
    pos += size + 2
  }
}

# The body, once all of it has arrived: text, or nil while more is needed.
# `closed` says the other side has finished sending (then whatever came is the body).
fn complete_body(headers, raw, closed) {
  if headers.get("transfer-encoding", "").lower().contains("chunked") {
    let body = decode_chunked(raw)
    if body == nil and closed { throw "http: the connection closed in the middle of a chunked body" }
    return body
  }
  let length = headers.get("content-length")
  if length != nil {
    let n = int(length)
    if n == nil or n < 0 { throw "http: bad content-length " + repr(length) }
    if n > MAX_BODY { throw "http: the body is too large" }
    if len(raw) >= n { return raw[0:n] }
    if closed { throw "http: the connection closed before the whole body arrived" }
    return nil
  }
  return closed and raw or nil
}

# --------------------------------------------------------------------- client

# {host, port, path, https} from "http://host:port/path?query"
fn parse_url(url) {
  let rest = url
  let scheme = "http"
  let sep = url.find("://")
  if sep >= 0 { scheme = url[0:sep].lower(); rest = url[sep + 3:] }
  if scheme != "http" { throw "http: only http:// URLs work (no TLS yet), got " + scheme + "://" }
  let slash = rest.find("/")
  let hostport = slash >= 0 and rest[0:slash] or rest
  let path = slash >= 0 and rest[slash:] or "/"
  let q = path.find("#")
  if q >= 0 { path = path[0:q] }
  let host = hostport
  let port = 80
  let colon = hostport.find(":")
  if colon >= 0 {
    host = hostport[0:colon]
    port = int(hostport[colon + 1:])
    if port == nil { throw "http: bad port in " + url }
  }
  if host == "" { throw "http: no host in " + url }
  return {host: host, port: port, path: path}
}

fn build_request(method, u, body, headers) {
  let h = {"host": u.port == 80 and u.host or u.host + ":" + str(u.port), "user-agent": "faxal", "connection": "close", "accept": "*/*"}
  for name in (headers ?? {}).keys() { h[name.lower()] = headers[name] }
  if body != nil and body != "" { h["content-length"] = str(len(body)) }
  let lines = [method + " " + u.path + " HTTP/1.1"]
  for name in h.keys() { lines.push(name + ": " + str(h[name])) }
  return lines.join("\r\n") + "\r\n\r\n" + (body ?? "")
}

# Turns a finished head + body into a Response (or nil if the head can't be read).
fn make_response(head, body) {
  let lines = head.split("\r\n")
  let parts = lines[0].split(" ")
  if len(parts) < 2 or not parts[0].starts_with("HTTP/") { throw "http: the server sent something that is not HTTP: " + repr(lines[0][0:40]) }
  let status = int(parts[1])
  if status == nil { throw "http: bad status line " + repr(lines[0]) }
  let res = Response(status, body, parse_headers(lines[1:]))
  if len(parts) > 2 { res.reason = parts[2:].join(" ") }
  return res
}

fn _is_redirect(res) => [301, 302, 303, 307, 308].contains(res.status) and res.headers.has("location")

fn _redirect_target(u, location) {
  if location.starts_with("http://") { return location }
  if location.starts_with("/") { return "http://" + u.host + ":" + str(u.port) + location }
  return "http://" + u.host + ":" + str(u.port) + u.path[0:u.path.find("?") >= 0 and u.path.find("?") or len(u.path)] + "/../" + location
}

# One request. headers is a map; timeout is in seconds; up to `redirects` redirects are followed.
fn request(method, url, body = nil, headers = nil, timeout = 30, redirects = 5) {
  let u = parse_url(url)
  let conn = net.connect(u.host, u.port, timeout)
  let res = nil
  try {
    net.write(conn, build_request(method.upper(), u, body, headers))
    let buf = ""
    let head = nil
    let rest = ""
    let closed = false
    let result = nil
    while result == nil {
      let data = net.read(conn, 65536, timeout)
      if data == nil { throw "http: timed out waiting for " + u.host }
      if data == "" { closed = true }
      buf += data
      if head == nil {
        let parts = split_head(buf)
        if parts != nil { head = parts[0]; rest = parts[1] }
        else if len(buf) > MAX_HEAD { throw "http: the response head is too large" }
        else if closed { throw "http: the connection closed before a response arrived" }
      } else {
        rest = rest + data
      }
      if head != nil {
        let status_headers = parse_headers(head.split("\r\n")[1:])
        let body_text = complete_body(status_headers, rest, closed)
        if body_text != nil { result = make_response(head, body_text) }
        else if closed { result = make_response(head, rest) }
      }
    }
    res = result
  } catch e {
    net.close(conn)
    throw e
  }
  net.close(conn)
  if redirects > 0 and _is_redirect(res) and (method.upper() == "GET" or method.upper() == "HEAD" or res.status == 303) {
    return request(res.status == 303 and "GET" or method, _redirect_target(u, res.headers["location"]), nil, headers, timeout, redirects - 1)
  }
  return res
}

fn get(url, headers = nil, timeout = 30) => request("GET", url, nil, headers, timeout)
fn head(url, headers = nil, timeout = 30) => request("HEAD", url, nil, headers, timeout)
fn post(url, body = "", headers = nil, timeout = 30) => request("POST", url, body, headers, timeout)
fn put(url, body = "", headers = nil, timeout = 30) => request("PUT", url, body, headers, timeout)
fn delete(url, headers = nil, timeout = 30) => request("DELETE", url, nil, headers, timeout)
# POST a value as JSON and get the Response
fn post_json(url, value, headers = nil, timeout = 30) {
  let h = {"content-type": "application/json"}
  for name in (headers ?? {}).keys() { h[name.lower()] = headers[name] }
  return request("POST", url, json.encode(value), h, timeout)
}

# ------------------------------------------------------------ async versions
# Awaitables for tasks: they poll the connection without blocking, so other tasks run meanwhile.

let Pollable = tasks.Pollable

class _ReadWait extends Pollable {
  fn init(conn) { self.conn = conn }
  fn external() => true
  fn poll() {
    let data = net.read(self.conn, 65536, 0)
    if data == nil { return nil }
    return [data]
  }
}

class _AcceptWait extends Pollable {
  fn init(listener) { self.listener = listener }
  fn external() => true
  fn poll() {
    let conn = net.accept(self.listener, 0)
    if conn == nil { return nil }
    return [conn]
  }
}

# Like request(), for use with await: other tasks run while this one waits for the server.
async fn request_async(method, url, body = nil, headers = nil, timeout = 30, redirects = 5) {
  let u = parse_url(url)
  let conn = net.connect(u.host, u.port, timeout)
  let res = nil
  try {
    net.write(conn, build_request(method.upper(), u, body, headers))
    let buf = ""
    let head = nil
    let rest = ""
    let closed = false
    let result = nil
    while result == nil {
      let data = await _ReadWait(conn)
      if data == "" { closed = true }
      buf += data
      if head == nil {
        let parts = split_head(buf)
        if parts != nil { head = parts[0]; rest = parts[1] }
        else if len(buf) > MAX_HEAD { throw "http: the response head is too large" }
        else if closed { throw "http: the connection closed before a response arrived" }
      } else {
        rest = rest + data
      }
      if head != nil {
        let body_text = complete_body(parse_headers(head.split("\r\n")[1:]), rest, closed)
        if body_text != nil { result = make_response(head, body_text) }
        else if closed { result = make_response(head, rest) }
      }
    }
    res = result
  } catch e {
    net.close(conn)
    throw e
  }
  net.close(conn)
  if redirects > 0 and _is_redirect(res) and (method.upper() == "GET" or method.upper() == "HEAD" or res.status == 303) {
    return await request_async(res.status == 303 and "GET" or method, _redirect_target(u, res.headers["location"]), nil, headers, timeout, redirects - 1)
  }
  return res
}

async fn get_async(url, headers = nil, timeout = 30) => await request_async("GET", url, nil, headers, timeout)
async fn post_async(url, body = "", headers = nil, timeout = 30) => await request_async("POST", url, body, headers, timeout)

# --------------------------------------------------------------------- server

# A router: patterns like /notes/:id, matched in the order they were added.
#   app.get("/notes/:id", handler)    handler(req) with req.params.id
class Router {
  fn init() { self.routes = [] }
  fn add(method, pattern, handler) {
    self.routes.push({method: method.upper(), parts: pattern.split("/").filter(fn(s) => s != ""), handler: handler})
    return self
  }
  fn get(pattern, handler) => self.add("GET", pattern, handler)
  fn post(pattern, handler) => self.add("POST", pattern, handler)
  fn put(pattern, handler) => self.add("PUT", pattern, handler)
  fn delete(pattern, handler) => self.add("DELETE", pattern, handler)
  # Finds the handler for a request (filling in req.params); a 404 or 405 response if there is none.
  fn handle(req) {
    let segments = req.path.split("/").filter(fn(s) => s != "")
    let path_matched = false
    for route in self.routes {
      let params = _match_route(route.parts, segments)
      if params == nil { continue }
      path_matched = true
      if route.method != req.method and not (route.method == "GET" and req.method == "HEAD") { continue }
      req.params = params
      return route.handler(req)
    }
    return path_matched and status_only(405) or status_only(404)
  }
}

fn _match_route(parts, segments) {
  let tail = len(parts) > 0 and parts[-1] == "*"
  if tail { if len(segments) < len(parts) - 1 { return nil } }
  else if len(parts) != len(segments) { return nil }
  let params = {}
  for i in 0..len(parts) {
    let p = parts[i]
    if p == "*" and i == len(parts) - 1 { params["rest"] = segments[i:].join("/"); break }
    if p.starts_with(":") { params[p[1:]] = enc.url_decode(segments[i], false) }
    else if p != segments[i] { return nil }
  }
  return params
}

fn _call_handler(handler, req) {
  if isinstance(handler, Router) { return handler.handle(req) }
  return handler(req)
}

fn _serialize(res, method) {
  let body = res.body
  let h = {}
  for name in res.headers.keys() { h[name.lower()] = res.headers[name] }
  h["content-length"] = str(len(body))
  h["connection"] = "close"
  if not h.has("content-type") and body != "" { h["content-type"] = "text/plain; charset=utf-8" }
  let lines = ["HTTP/1.1 " + str(res.status) + " " + res.reason]
  for name in h.keys() { lines.push(name + ": " + str(h[name])) }
  return lines.join("\r\n") + "\r\n\r\n" + (method == "HEAD" and "" or body)
}

# Reads the pieces of a request from `chunks` as they arrive; returns a Request, or a Response if it was bad.
class _RequestReader {
  fn init() {
    self.buf = ""
    self.head = nil
    self.rest = ""
    self.request = nil
  }
  # Feeds in data ("" = the client closed). Returns nil while more is needed, else a Request or an error Response.
  fn feed(data) {
    let closed = data == ""
    self.buf += data
    if self.head == nil {
      let parts = split_head(self.buf)
      if parts == nil {
        if len(self.buf) > MAX_HEAD { return status_only(413) }
        return closed and status_only(400) or nil
      }
      self.head = parts[0]
      self.rest = parts[1]
    } else {
      self.rest += data
    }
    let lines = self.head.split("\r\n")
    let first = lines[0].split(" ")
    if len(first) != 3 or not first[2].starts_with("HTTP/") { return status_only(400) }
    let headers = parse_headers(lines[1:])
    let body = nil
    if not headers.has("content-length") and not headers.get("transfer-encoding", "").lower().contains("chunked") {
      body = ""                                  # a request without a length has no body
    } else {
      try { body = complete_body(headers, self.rest, closed) } catch e { return status_only(400) }
    }
    if body == nil { return closed and status_only(400) or nil }
    return Request(first[0].upper(), first[1], headers, body)
  }
}

fn _error_response(e) => Response(500, "Internal Server Error\n\n" + str(e) + "\n", {"content-type": "text/plain; charset=utf-8"})

# Reads one request from a connection, calls the handler, writes the response. (Blocking.)
fn _serve_connection(conn, handler) {
  try {
    let reader = _RequestReader()
    let req = nil
    while req == nil {
      let data = net.read(conn, 65536, 10)
      if data == nil { net.write(conn, _serialize(status_only(408), "GET")); net.close(conn); return }
      req = reader.feed(data)
      if req == nil and data == "" { break }
    }
    if req == nil { net.close(conn); return }
    let res = nil
    if isinstance(req, Response) { res = req }
    else {
      try { res = to_response(_call_handler(handler, req)) } catch e { res = _error_response(e) }
    }
    net.write(conn, _serialize(res, isinstance(req, Request) and req.method or "GET"))
  } catch e {
    # the client went away: nothing to do
  }
  net.close(conn)
}

# Starts a server and handles one connection at a time, forever (or until `limit` requests were served).
# handler is a function(request) or a Router. on_start(port) is called when it is listening
# (use port 0 to let the system choose a free port).
fn serve(port, handler, host = "127.0.0.1", limit = nil, on_start = nil) {
  let listener = net.listen(port, host)
  if on_start != nil { on_start(net.port(listener)) }
  let served = 0
  while limit == nil or served < limit {
    let conn = net.accept(listener)
    if conn == nil { continue }
    _serve_connection(conn, handler)
    served += 1
  }
  net.close(listener)
}

async fn _serve_connection_async(conn, handler) {
  try {
    let reader = _RequestReader()
    let req = nil
    while req == nil {
      let data = await _ReadWait(conn)
      req = reader.feed(data)
      if req == nil and data == "" { break }
    }
    if req != nil {
      let res = nil
      if isinstance(req, Response) { res = req }
      else {
        try {
          let r = _call_handler(handler, req)
          if type(r) == "coroutine" { r = await r }
          res = to_response(r)
        } catch e { res = _error_response(e) }
      }
      net.write(conn, _serialize(res, isinstance(req, Request) and req.method or "GET"))
    }
  } catch e {
    # the client went away
  }
  net.close(conn)
}

# Like serve(), for use with tasks.run: every connection is its own task, and handlers may be async fns
# (so one slow request doesn't hold up the others).
async fn serve_async(port, handler, host = "127.0.0.1", limit = nil, on_start = nil) {
  let listener = net.listen(port, host)
  if on_start != nil { on_start(net.port(listener)) }
  let served = 0
  let pending = []
  while limit == nil or served < limit {
    let conn = await _AcceptWait(listener)
    served += 1
    pending.push(tasks.spawn(_serve_connection_async(conn, handler)))
  }
  await tasks.gather(pending)
  net.close(listener)
}
