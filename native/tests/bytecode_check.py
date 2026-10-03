#!/usr/bin/env python3
"""Tests for the bytecode file format (.fxc).

For every program in tests/spec, examples/, the standard library (lib/), the tools and the Faxal tests:
  - `faxal --c-compiler compile` (the C compiler) makes a .fxc, and `faxal compile` (the default, the Faxal compiler) makes the *same bytes*;
  - running the .fxc gives exactly the same output, error text and exit code as running the source;
  - `faxal dump` of the .fxc prints exactly what the compiler's `--dump` printed;
  - `faxal check` accepts it (the verifier approves);
  - modules can be imported from .fxc files alone, after the source files are deleted.
usage: python3 tests/bytecode_check.py <faxal binary>
"""
import pathlib, shutil, subprocess, sys, tempfile

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal").resolve())
here = pathlib.Path(__file__).parent
bad = 0

def run(*args, cwd):
    return subprocess.run([binary, *args], cwd=cwd, capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL)

def fail(msg):
    global bad
    bad += 1
    print("FAIL", msg)

# the opcode list in std/bytecode.fx must match the OpCode enum in faxal.h, in order
import re
header = (here.parent / "src" / "faxal.h").read_text()
enum = re.search(r"typedef enum \{\s*(OP_CONSTANT.*?)\} OpCode;", header, re.S).group(1)
names = [n[3:] for n in re.findall(r"\bOP_[A-Z0-9_]+", enum) if n != "OP_COUNT"]
shown = run("-e", 'import "std/bytecode" as b\nprint(b.OPS.join(","))', cwd=here).stdout.strip().split(",")
if names != shown:
    fail("the opcode list in lib/std/bytecode.fx does not match the OpCode enum in src/faxal.h")

with tempfile.TemporaryDirectory() as tmp:
    work = pathlib.Path(tmp).resolve()
    shutil.copytree(here / "spec", work / "spec")
    shutil.copytree(here.parent.parent / "examples", work / "examples")
    shutil.copytree(here.parent / "lib", work / "lib")      # the standard library and the tools, compiler included
    shutil.copytree(here / "std", work / "stdtests")
    shutil.copytree(here.parent / "tools", work / "tools")
    sources = sorted(p for p in work.rglob("*.fx"))
    compiled = []

    for src in sources:
        rel = src.relative_to(work)
        out, out2 = src.with_suffix(".fxc"), src.with_suffix(".self.fxc")
        c = run("--c-compiler", "compile", src.name, cwd=src.parent)
        f = run("compile", "-o", out2.name, src.name, cwd=src.parent)
        if c.returncode != f.returncode:
            fail(f"{rel}: the two compilers disagree about whether it compiles ({c.returncode} / {f.returncode})")
            continue
        if c.returncode != 0:
            continue   # programs that are meant not to compile
        compiled.append(src)
        if out.read_bytes() != out2.read_bytes():
            fail(f"{rel}: the C compiler and the Faxal compiler produce different .fxc files")

        d = run("dump", out.name, cwd=src.parent)
        e = run("--c-compiler", "check", "--dump", src.name, cwd=src.parent)
        if d.stdout != e.stdout.rsplit(f"{src.name}: ok", 1)[0]:
            fail(f"{rel}: `faxal dump` of the .fxc differs from the compiler's --dump")
        if run("check", out.name, cwd=src.parent).returncode != 0:
            fail(f"{rel}: the verifier rejected a file the compiler wrote")

        if rel.parts[0] in ("lib", "tools"):
            continue   # the library and the tools are only compared as bytes: running them has side effects
        a = run(src.name, cwd=src.parent)
        b = run(out.name, cwd=src.parent)
        if (a.stdout, a.returncode) != (b.stdout, b.returncode):
            fail(f"{rel}: running the .fxc gives different output ({a.returncode} / {b.returncode})\n  {a.stdout[:150]!r}\n  {b.stdout[:150]!r}")
        elif a.stderr != b.stderr:
            fail(f"{rel}: running the .fxc gives different error text\n  {a.stderr[:300]!r}\n  {b.stderr[:300]!r}")

    # modules from bytecode only
    spec = work / "spec"
    for f in (spec / "modules").glob("*.fx"):
        f.unlink()
    r = run("modules.fxc", cwd=spec)
    expected = run("modules.fxc", cwd=spec)
    if r.returncode != 0 or "mathlib" not in r.stdout or "42" not in r.stdout:
        fail(f"importing from .fxc files alone failed:\n{r.stdout}{r.stderr}")

    # files that once made the VM misbehave (found by bytecode_fuzz.py): they must now fail cleanly, never crash
    for f in sorted((here / "fxc").glob("*.fxc")):
        shutil.copy(f, spec / f.name)
        for args in (["check", f.name], ["--sandbox", f.name]):
            r = run(*args, cwd=spec)
            if r.returncode < 0 or r.returncode not in (0, 65, 70) or "Sanitizer" in r.stderr or "runtime error:" in r.stderr:
                fail(f"{f.name} ({' '.join(args)}): exit {r.returncode}\n{r.stderr[:400]}")

    # a damaged file is rejected, not run
    victim = spec / "basics.fxc"
    data = bytearray(victim.read_bytes())
    data[len(data) // 2] ^= 0x55
    victim.write_bytes(bytes(data))
    r = run("basics.fxc", cwd=spec)
    if r.returncode == 0 or "damaged" not in r.stderr:
        fail(f"a damaged .fxc was not rejected: {r.stderr[:200]}")
    victim.write_bytes(b"not bytecode at all")
    if run("check", "basics.fxc", cwd=spec).returncode == 0:
        fail("a text file was accepted as bytecode")

print(f"bytecode: {len(compiled)} programs round-tripped, {bad} problems")
sys.exit(1 if bad else 0)
