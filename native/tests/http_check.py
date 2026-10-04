#!/usr/bin/env python3
"""std/http against other people's HTTP: Python's urllib talks to a Faxal server, and a Faxal client talks to Python's server."""
import http.server, json, os, pathlib, subprocess, sys, tempfile, threading, time, urllib.request, urllib.error

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal").resolve()
fails = 0

def check(name, ok, detail=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok else "\n      " + str(detail)))
    fails += 0 if ok else 1

tmp = pathlib.Path(tempfile.mkdtemp(prefix="faxal-http-"))

# --- a Faxal server (blocking), used from Python
server_src = '''
import "std/http" as http
let app = http.Router()
app.get("/hello", fn(req) => http.text("Hello, " + (req.query.name ?? "you")))
app.get("/big", fn(req) => http.text("x".repeat(300000)))
app.post("/echo", fn(req) => http.send_json({body: req.body, type: req.header("content-type"), len: len(req.body)}, 201))
app.get("/boom", fn(req) { throw "kaput" })
http.serve(0, app, "127.0.0.1", 7, fn(port) { print(port); os.flush() })
'''
(tmp / "server.fx").write_text(server_src)
p = subprocess.Popen([str(binary), str(tmp / "server.fx")], stdout=subprocess.PIPE, text=True)
port = int(p.stdout.readline())
base = f"http://127.0.0.1:{port}"
try:
    r = urllib.request.urlopen(base + "/hello?name=Python%20User")
    check("a Faxal server answers urllib", r.status == 200 and r.read() == b"Hello, Python User" and r.headers["Content-Type"].startswith("text/plain"), r)
    r = urllib.request.urlopen(base + "/big")
    check("a large body arrives whole", len(r.read()) == 300000)
    body = ("héllo " * 20000).encode()   # a body bigger than one read
    req = urllib.request.Request(base + "/echo", data=body, headers={"Content-Type": "text/x-test"}, method="POST")
    r = urllib.request.urlopen(req)
    got = json.loads(r.read())
    check("a large POST body is read completely", r.status == 201 and got["len"] == len(body) and got["type"] == "text/x-test", got["len"])
    try:
        urllib.request.urlopen(base + "/nope"); check("404 for an unknown path", False)
    except urllib.error.HTTPError as e:
        check("404 for an unknown path", e.code == 404)
    try:
        urllib.request.urlopen(base + "/boom"); check("500 when a handler throws", False)
    except urllib.error.HTTPError as e:
        check("500 when a handler throws", e.code == 500 and b"kaput" in e.read())
    try:
        urllib.request.urlopen(urllib.request.Request(base + "/hello", method="DELETE")); check("405 for the wrong method", False)
    except urllib.error.HTTPError as e:
        check("405 for the wrong method", e.code == 405)
    r = urllib.request.urlopen(urllib.request.Request(base + "/hello", method="HEAD"))
    check("HEAD has no body", r.status == 200 and r.read() == b"")
finally:
    p.terminate(); p.wait(timeout=10)

# --- a Python server, used from a Faxal client
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/chunked":
            self.send_response(200); self.send_header("Transfer-Encoding", "chunked"); self.send_header("Content-Type", "text/plain"); self.end_headers()
            for part in [b"hello ", b"chunked ", b"world"]:
                self.wfile.write(b"%x\r\n%s\r\n" % (len(part), part))
            self.wfile.write(b"0\r\n\r\n")
        elif self.path == "/redirect":
            self.send_response(302); self.send_header("Location", "/final"); self.send_header("Content-Length", "0"); self.end_headers()
        elif self.path == "/final":
            body = b"final!"; self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
        elif self.path == "/noclen":
            self.send_response(200); self.send_header("Connection", "close"); self.end_headers(); self.wfile.write(b"until the end")
            self.close_connection = True
        else:
            body = json.dumps({"path": self.path, "ua": self.headers.get("User-Agent")}).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); data = self.rfile.read(n)
        body = json.dumps({"len": n, "echo": data.decode()}).encode()
        self.send_response(201); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
pyport = srv.server_address[1]
client_src = f'''
import "std/http" as http
let base = "http://127.0.0.1:{pyport}"
let r = http.get(base + "/x?y=1")
print(r.status, r.json().path, r.json().ua, r.headers["content-type"])
print(http.get(base + "/chunked").text())
print(http.get(base + "/redirect").text())
print(http.get(base + "/noclen").text())
r = http.post_json(base + "/post", {{msg: "héllo", n: [1, 2]}})
print(r.status, r.json().len, json.decode(r.json().echo).msg)
print(http.post(base + "/post", "x".repeat(200000)).json().len)
'''
(tmp / "client.fx").write_text(client_src)
res = subprocess.run([str(binary), str(tmp / "client.fx")], capture_output=True, text=True, timeout=60)
lines = res.stdout.strip().split("\n")
check("a Faxal client reads normal, chunked, redirected and unlengthed responses",
      res.returncode == 0 and lines == ['200 /x?y=1 faxal application/json', 'hello chunked world', 'final!', 'until the end', '201 26 héllo', '200000'] ,
      res.stdout + res.stderr)
srv.shutdown()
print("http_check:", "all passed" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
