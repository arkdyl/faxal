#!/usr/bin/env python3
"""Differential test: the compiler written in Faxal (std/compiler) against the compiler written in C.

For every Faxal file in the repository, all three of these must agree: the C compiler, the Faxal compiler's own
disassembler, and the Faxal compiler's bytecode loaded into the VM (faxal's default). Each must produce the same bytecode (compared as the text of
`faxal --dump`: instructions, line numbers, constants), or, for files that do not compile, the same
first error (message, line and column).
usage: python3 tests/selfhost_check.py <faxal binary> [files...]
"""
import pathlib, re, subprocess, sys

binary = sys.argv[1] if len(sys.argv) > 1 else "bin/faxal"
here = pathlib.Path(__file__).parent
roots = [here / "spec", here / "std", here.parent / "lib", here.parent / "tools", here.parent.parent / "examples"]
files = [pathlib.Path(a) for a in sys.argv[2:]] or sorted(p for r in roots if r.exists() for p in r.rglob("*.fx"))

def c_compile(path):
    r = subprocess.run([binary, "--c-compiler", "check", "--dump", str(path)], capture_output=True, text=True, timeout=60)
    if r.returncode == 0:
        return ("ok", r.stdout.rsplit(f"{path}: ok", 1)[0])
    m = re.search(r"^error: (.*)\n\s+--> .*:(\d+):(\d+)", r.stderr, re.M)
    return ("error", (int(m.group(2)), int(m.group(3)), m.group(1)) if m else r.stderr)

def loaded_compile(path):
    """The Faxal compiler's bytecode, loaded into the VM and printed by the C disassembler."""
    r = subprocess.run([binary, "check", "--dump", str(path)], capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        return ("ok", r.stdout.rsplit(f"{path}: ok", 1)[0])
    m = re.search(r"^error: (.*)\n\s+--> .*:(\d+):(\d+)", r.stderr, re.M)
    return ("error", (int(m.group(2)), int(m.group(3)), m.group(1)) if m else r.stderr)

def fx_compile(path):
    r = subprocess.run([binary, "fxc", "--errors", str(path)], capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        d = subprocess.run([binary, "fxc", str(path)], capture_output=True, text=True, timeout=120)
        return ("ok", d.stdout)
    first = r.stdout.splitlines()[0] if r.stdout.strip() else ""
    m = re.match(r"(\d+):(\d+): (.*)", first)
    return ("error", (int(m.group(1)), int(m.group(2)), m.group(3)) if m else r.stdout + r.stderr)

bad = 0
for f in files:
    a, b, c = c_compile(f), fx_compile(f), loaded_compile(f)
    if a != c:
        bad += 1
        print(f"DIFFERENT (loaded into the VM) {f}")
        print(f"   C: {a if a[0] == 'error' else 'compiles'}\n   self-hosted run: {c if c[0] == 'error' else 'compiles'}")
        continue
    if a != b:
        bad += 1
        print(f"DIFFERENT {f}")
        if a[0] == "ok" and b[0] == "ok":
            la, lb = a[1].splitlines(), b[1].splitlines()
            for i, (x, y) in enumerate(zip(la, lb)):
                if x != y:
                    print(f"   line {i + 1}:\n     C:     {x}\n     Faxal: {y}"); break
            else:
                print(f"   lengths differ: {len(la)} vs {len(lb)}")
        else:
            print(f"   C: {a}\n   Faxal: {b}")
print(f"{len(files)} files compared, {bad} different")
sys.exit(1 if bad else 0)
