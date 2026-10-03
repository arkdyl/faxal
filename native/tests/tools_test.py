#!/usr/bin/env python3
"""End-to-end test of the project tools: init, run, test, fmt, add/remove, build, sandbox rules.
usage: python3 tests/tools_test.py <faxal binary>
"""
import os, pathlib, subprocess, sys, tempfile

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal").resolve())
failures = []

def faxal(*args, cwd, input=None, ok=True):
    r = subprocess.run([binary, *args], cwd=cwd, capture_output=True, text=True, input=input, timeout=60)
    return r

def check(name, cond, detail=""):
    if not cond:
        failures.append(name)
        print(f"FAIL {name} {detail}")

with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp).resolve()

    # --- init
    r = faxal("init", "app", cwd=tmp)
    check("init exits 0", r.returncode == 0, r.stderr)
    app = tmp / "app"
    for f in ["faxal.json", "main.fx", "greeting.fx", "tests/greeting_test.fx", ".gitignore"]:
        check(f"init creates {f}", (app / f).exists())
    check("init refuses to overwrite", faxal("init", cwd=app).returncode == 1)

    # --- run (no file: uses faxal.json) and test
    r = faxal("run", cwd=app)
    check("run uses faxal.json", r.returncode == 0 and r.stdout.strip() == "Hello, world!", r.stdout + r.stderr)
    r = faxal("test", cwd=app)
    check("test passes", r.returncode == 0 and "1 passed, 0 failed" in r.stdout, r.stdout + r.stderr)

    # a failing test makes `faxal test` exit 1
    (app / "tests" / "bad_test.fx").write_text('import "std/test" as t\nt.test("nope", fn() { t.eq(1, 2) })\nt.test("fine", fn() { t.ok(true) })\n')
    r = faxal("test", cwd=app)
    check("failing test exits 1", r.returncode == 1 and "FAIL  nope" in r.stdout and "ok    fine" in r.stdout, r.stdout)
    r = faxal("test", "--filter=fine", cwd=app)
    check("test --filter", r.returncode == 0 and "FAIL" not in r.stdout, r.stdout)
    (app / "tests" / "bad_test.fx").unlink()

    # --- fmt
    (app / "messy.fx").write_text("let   x=1+2\nfn f(a,b){return a+b}\n")
    r = faxal("fmt", "--check", cwd=app)
    check("fmt --check finds messy file", r.returncode == 1 and "messy.fx" in r.stdout, r.stdout)
    r = faxal("fmt", cwd=app)
    check("fmt rewrites", r.returncode == 0 and (app / "messy.fx").read_text() == "let x = 1 + 2\nfn f(a, b) { return a + b }\n", (app / "messy.fx").read_text())
    check("fmt --check passes afterwards", faxal("fmt", "--check", cwd=app).returncode == 0)
    (app / "messy.fx").unlink()

    # --- packages
    pkg = tmp / "shared"
    pkg.mkdir()
    (pkg / "main.fx").write_text('fn shout(s) { return s.upper() + "!" }\nlet VERSION = 3\n')
    r = faxal("add", str(pkg), "utils", cwd=app)
    check("add installs a folder", r.returncode == 0 and (app / "fx_modules/utils/main.fx").exists(), r.stdout + r.stderr)
    check("add records the dependency", '"utils"' in (app / "faxal.json").read_text())
    (app / "main.fx").write_text('import "greeting"\nimport "utils"\nprint(greeting.greet("x"), utils.shout("hey"), utils.VERSION)\nprint(os.args)\n')
    r = faxal("run", cwd=app)
    check("packages can be imported", r.stdout.splitlines()[0] == "Hello, x! HEY! 3", r.stdout + r.stderr)

    single = tmp / "single.fx"
    single.write_text("let ONE = 1\n")
    r = faxal("add", str(single), cwd=app)
    check("add installs a single file", r.returncode == 0 and (app / "fx_modules/single.fx").exists(), r.stdout + r.stderr)

    # reinstall everything from faxal.json
    subprocess.run(["rm", "-rf", str(app / "fx_modules")])
    r = faxal("install", cwd=app)
    check("install restores packages", r.returncode == 0 and (app / "fx_modules/utils/main.fx").exists(), r.stdout + r.stderr)
    r = faxal("list", cwd=app)
    check("list shows packages", "utils" in r.stdout and "(installed)" in r.stdout, r.stdout)
    r = faxal("remove", "single", cwd=app)
    check("remove works", r.returncode == 0 and not (app / "fx_modules/single.fx").exists() and '"single"' not in (app / "faxal.json").read_text(), r.stdout + r.stderr)
    check("add of a missing source fails", faxal("add", "/nonexistent/place", cwd=app).returncode == 1)

    # --- build: a standalone executable
    r = faxal("build", "main.fx", "-o", "myapp", cwd=app)
    check("build succeeds", r.returncode == 0 and "3 files packed as bytecode" in r.stdout, r.stdout + r.stderr)
    r2 = faxal("build", "--source", "main.fx", "-o", "myapp-src", cwd=app)
    check("build --source packs source text", r2.returncode == 0 and "as source" in r2.stdout, r2.stdout + r2.stderr)
    subprocess.run(["cp", str(app / "myapp-src"), str(tmp / "myapp-src")])
    elsewhere = tmp / "elsewhere"
    elsewhere.mkdir()
    subprocess.run(["cp", str(app / "myapp"), str(elsewhere / "myapp")])
    subprocess.run(["rm", "-rf", str(app)])   # the sources are gone: the app must carry everything it needs
    r = subprocess.run([str(elsewhere / "myapp"), "one", "--two"], cwd=elsewhere, capture_output=True, text=True, timeout=30)
    check("built app runs on its own", r.returncode == 0 and r.stdout.splitlines()[0] == "Hello, x! HEY! 3", r.stdout + r.stderr)
    check("built app gets its arguments", r.stdout.splitlines()[1] == '["one", "--two"]', r.stdout)
    r = subprocess.run([str(tmp / "myapp-src"), "x"], cwd=elsewhere, capture_output=True, text=True, timeout=30)
    check("a source-packed app works too", r.returncode == 0 and r.stdout.splitlines()[0] == "Hello, x! HEY! 3", r.stdout + r.stderr)
    # an app that fails keeps the exit code
    bad = tmp / "boom.fx"
    bad.write_text('print("before")\nthrow "kaboom"\n')
    faxal("build", "boom.fx", "-o", "boom", cwd=tmp)
    r = subprocess.run([str(tmp / "boom")], cwd=tmp, capture_output=True, text=True, timeout=30)
    check("built app reports errors with exit 70", r.returncode == 70 and "kaboom" in r.stderr and r.stdout == "before\n", r.stdout + r.stderr)
    check("build rejects a missing file", faxal("build", "nope.fx", cwd=tmp).returncode == 74)
    (tmp / "needs.fx").write_text('import "ghost"\n')
    check("build rejects a missing import", faxal("build", "needs.fx", cwd=tmp).returncode == 65)

    # --- bytecode files: compile, run, dump, check, and -o in either position
    prog = tmp / "prog.fx"
    prog.write_text('print("from bytecode", os.args)\n')
    r = faxal("compile", "prog.fx", cwd=tmp)
    check("compile writes prog.fxc", r.returncode == 0 and (tmp / "prog.fxc").exists() and "prog.fxc" in r.stdout, r.stdout + r.stderr)
    r = faxal("compile", "-o", "first.fxc", "prog.fx", cwd=tmp)
    check("compile -o before the file", r.returncode == 0 and (tmp / "first.fxc").exists(), r.stdout + r.stderr)
    r = faxal("compile", "prog.fx", "-o", "second.fxc", cwd=tmp)
    check("compile -o after the file", r.returncode == 0 and (tmp / "second.fxc").read_bytes() == (tmp / "first.fxc").read_bytes(), r.stdout + r.stderr)
    r = faxal("prog.fxc", "a", "b", cwd=tmp)
    check("a .fxc runs, with arguments", r.returncode == 0 and r.stdout.strip() == 'from bytecode ["a", "b"]', r.stdout + r.stderr)
    r = faxal("dump", "prog.fxc", cwd=tmp)
    check("dump shows the instructions", "== <script> ==" in r.stdout and "GET_GLOBAL" in r.stdout, r.stdout)
    r = faxal("check", "prog.fxc", cwd=tmp)
    check("check verifies a .fxc", r.returncode == 0 and "verified" in r.stdout, r.stdout + r.stderr)
    r = faxal("compile", "prog.fxc", cwd=tmp)
    check("compile refuses an already compiled file", r.returncode == 64, r.stdout + r.stderr)
    (tmp / "broken.fx").write_text("let x = (1 +\n")
    r = faxal("compile", "broken.fx", cwd=tmp)
    check("compile reports syntax errors and writes nothing", r.returncode == 65 and not (tmp / "broken.fxc").exists(), r.stderr)
    (tmp / "pure.fx").write_text('print("pure", 6 * 7)\n')
    faxal("compile", "pure.fx", cwd=tmp)
    r = faxal("--sandbox", "pure.fxc", cwd=tmp)
    check("a verified .fxc can run in safe mode", r.returncode == 0 and r.stdout.strip() == "pure 42", r.stdout + r.stderr)

    # --- sandbox rules for imports
    r = faxal("--sandbox", "-", cwd=tmp, input='import "std/text" as t\nprint(t.pad_left("1", 3, "0"))\n')
    check("sandbox can import std modules", r.returncode == 0 and r.stdout.strip() == "001", r.stdout + r.stderr)
    r = faxal("--sandbox", "-", cwd=tmp, input='import "boom" as b\n')
    check("sandbox cannot import files", r.returncode == 70 and "disabled in sandbox" in r.stderr, r.stderr)
    r = faxal("--sandbox", "-", cwd=tmp, input='print(os.run("echo hi"))\n')
    check("sandbox has no os.run", r.returncode == 70, r.stderr)
    r = faxal("-e", 'print(os.run("echo hi"))', cwd=tmp)
    check("os.run works normally", r.returncode == 0 and "hi" in r.stdout, r.stdout + r.stderr)

print("tools: all checks passed" if not failures else f"tools: {len(failures)} checks failed")
sys.exit(1 if failures else 0)
