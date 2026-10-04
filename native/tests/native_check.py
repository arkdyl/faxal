#!/usr/bin/env python3
"""The single-file build and compile-to-C.

  1. dist/faxal.c (the whole runtime as one C file) compiles with a plain `cc` and the result runs the spec suite.
  2. `faxal build --c` writes a program as one C file that any C compiler turns into a native executable.
  3. `faxal build --native` does both steps; the executable needs neither faxal nor its source files.
"""
import os, pathlib, shutil, subprocess, sys, tempfile

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal").resolve()
here = pathlib.Path(__file__).resolve().parent.parent
cc = os.environ.get("CC") or shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")
if not cc:
    print("native_check: no C compiler, skipping"); sys.exit(0)
fails = 0

def check(name, ok, detail=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok else "\n" + detail))
    fails += 0 if ok else 1

tmp = pathlib.Path(tempfile.mkdtemp(prefix="faxal-native-"))
exe_ext = ".exe" if os.name == "nt" else ""
try:
    one = tmp / ("faxal-one" + exe_ext)
    r = subprocess.run([cc, "-O1", "-std=c11", "-o", str(one), str(here / "dist" / "faxal.c"), "-lws2_32" if os.name == "nt" else "-lm"], capture_output=True, text=True)
    check("dist/faxal.c compiles with a plain C compiler", r.returncode == 0, r.stderr[:2000])
    if r.returncode == 0:
        r = subprocess.run([sys.executable, str(here / "tests" / "run.py"), str(one)], capture_output=True, text=True)
        check("the one-file build passes the spec suite", r.returncode == 0, r.stdout[-1500:] + r.stderr[-500:])

    src = tmp / "src"
    src.mkdir()
    (src / "helper.fx").write_text("fn double(x) { return x * 2 }\n")
    (src / "main.fx").write_text('import "std/regex" as re\nimport "helper.fx" as h\nprint("hi", h.double(21), re.find("[0-9]+", "ab 123").text, os.args)\n')

    r = subprocess.run([str(binary), "build", str(src / "main.fx"), "--c", "-o", str(tmp / "prog.c")], capture_output=True, text=True)
    check("faxal build --c writes one C file", r.returncode == 0 and (tmp / "prog.c").exists(), r.stdout + r.stderr)
    prog = tmp / ("prog" + exe_ext)
    r = subprocess.run([cc, "-O1", "-o", str(prog), str(tmp / "prog.c"), "-lws2_32" if os.name == "nt" else "-lm"], capture_output=True, text=True)
    check("that C file compiles to a native program", r.returncode == 0, r.stderr[:2000])
    if r.returncode == 0:
        r = subprocess.run([str(prog), "x", "y"], capture_output=True, text=True)
        check("the native program runs", r.stdout.strip() == 'hi 42 123 ["x", "y"]', r.stdout + r.stderr)

    nat = tmp / ("nat" + exe_ext)
    r = subprocess.run([str(binary), "build", str(src / "main.fx"), "--native", "-o", str(nat)], capture_output=True, text=True)
    check("faxal build --native", r.returncode == 0 and nat.exists(), r.stdout + r.stderr)
    (src / "helper.fx").unlink()
    (src / "main.fx").unlink()
    if nat.exists():
        r = subprocess.run([str(nat)], capture_output=True, text=True)
        check("the native program needs none of its source files", r.stdout.strip() == "hi 42 123 []", r.stdout + r.stderr)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("native_check:", "all passed" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
