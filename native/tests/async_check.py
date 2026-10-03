#!/usr/bin/env python3
"""async in safe mode: sleeping uses a pretend clock, so long sleeps finish at once and in order;
coroutines respect the memory limit."""
import json, pathlib, subprocess, sys, time

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal").resolve()
fails = 0

def run(src, *flags):
    t = time.time()
    r = subprocess.run([str(binary), "--sandbox", "--json", *flags, "-"], input=src, capture_output=True, text=True, timeout=60)
    return json.loads(r.stdout), time.time() - t

def check(name, ok, detail=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok else "\n      " + str(detail)))
    fails += 0 if ok else 1

res, took = run('''
import "std/tasks" as tasks
async fn nap(name, s) { await tasks.sleep(s); print(name); return s }
async fn main() { print(await tasks.gather([nap("slow", 3600), nap("fast", 1800), nap("mid", 2400)])) }
tasks.run(main())
''')
check("long sleeps finish at once and in order", res["error"] is None and res["output"] == "fast\nmid\nslow\n[3600, 1800, 2400]\n" and took < 5, res)

res, _ = run('let cos = []\nwhile true { let c = coroutine(fn() { yield(1) }); resume(c); cos.push(c) }')
check("endless coroutines hit the memory limit instead of crashing", res["error"] is not None and "memory" in res["error"]["message"].lower(), res)

res, _ = run('fn loop() { while true { yield(1) } }\nlet c = coroutine(loop)\nwhile true { resume(c) }')
check("an endless coroutine hits the step limit", res["error"] is not None and res["error"]["kind"] == "limit", res)

print("async_check:", "all passed" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
