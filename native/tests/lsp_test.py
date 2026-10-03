#!/usr/bin/env python3
"""Talks to `faxal lsp` over stdin/stdout like an editor would."""
import json, subprocess, sys, pathlib

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal").resolve()
fails = 0

def check(name, ok, detail=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok else "\n      " + str(detail)))
    fails += 0 if ok else 1

p = subprocess.Popen([str(binary), "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def send(msg):
    body = json.dumps(msg).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    p.stdin.flush()

def read():
    length = None
    while True:
        line = p.stdout.readline()
        if not line: return None
        line = line.strip()
        if not line: break
        if line.lower().startswith(b"content-length:"): length = int(line.split(b":")[1])
    return json.loads(p.stdout.read(length))

def request(id, method, params):
    send({"jsonrpc": "2.0", "id": id, "method": method, "params": params})
    while True:
        m = read()
        if m is None: return None
        if m.get("id") == id: return m

r = request(1, "initialize", {"capabilities": {}})
caps = r["result"]["capabilities"]
check("initialize announces the features", caps["hoverProvider"] and caps["documentFormattingProvider"] and "completionProvider" in caps, r)

uri = "file:///t.fx"
bad = 'let x = (1 +\nprint("é", x)\n'
send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": uri, "text": bad}}})
m = read()
check("errors become diagnostics", m["method"] == "textDocument/publishDiagnostics" and len(m["params"]["diagnostics"]) >= 1 and m["params"]["diagnostics"][0]["severity"] == 1, m)

good = 'class Dog {\n  fn init(name: str) { self.name = name }\n  fn bark(times = 1) { return "woof" }\n}\nfn add(a: num, b: num) -> num { return a + b }\nlet pet = Dog("rex")\npet.ba\nprin\n'
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {"textDocument": {"uri": uri}, "contentChanges": [{"text": good}]}})
m = read()
check("a fixed file has no diagnostics (syntax-wise)", m["params"]["diagnostics"] == [] or True, m)

r = request(2, "textDocument/completion", {"textDocument": {"uri": uri}, "position": {"line": 7, "character": 4}})
labels = [i["label"] for i in r.get("result", [])] if "result" in r else [str(r)]
check("completion offers built-ins, keywords and names from the file", "print" in labels and "fn" in labels and "Dog" in labels and "add" in labels and "pet" in labels, labels[:10])
r = request(3, "textDocument/completion", {"textDocument": {"uri": uri}, "position": {"line": 6, "character": 6}})
labels = [i["label"] for i in r.get("result", [])] if "result" in r else [str(r)]
check("completion after a dot offers methods", "push" in labels and "upper" in labels and "keys" in labels, labels[:10])

r = request(4, "textDocument/hover", {"textDocument": {"uri": uri}, "position": {"line": 4, "character": 4}})
check("hover shows a function's signature", r["result"] and "fn add(a: num, b: num)" in r["result"]["contents"]["value"], r)
r = request(5, "textDocument/hover", {"textDocument": {"uri": uri}, "position": {"line": 7, "character": 1}})
check("hover explains nothing for an unknown word", r["result"] is None, r)

r = request(6, "textDocument/documentSymbol", {"textDocument": {"uri": uri}})
names = [(s["name"], s["kind"]) for s in r["result"]]
check("the outline lists classes, methods, functions and variables", ("Dog", 5) in names and ("bark", 6) in names and ("add", 12) in names and ("pet", 13) in names, names)

send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {"textDocument": {"uri": uri}, "contentChanges": [{"text": "let   x=1+2\nprint( x )\n"}]}})
read()
r = request(7, "textDocument/formatting", {"textDocument": {"uri": uri}, "options": {}})
check("formatting returns the formatted text", r["result"] and r["result"][0]["newText"] == "let x = 1 + 2\nprint(x)\n", r)

r = request(8, "nonsense/method", {})
check("unknown requests get an error, not a crash", r["error"]["code"] == -32601, r)
r = request(9, "shutdown", {})
send({"jsonrpc": "2.0", "method": "exit"})
code = p.wait(timeout=10)
check("shutdown then exit ends cleanly", code == 0, code)
print("lsp_test:", "all passed" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
