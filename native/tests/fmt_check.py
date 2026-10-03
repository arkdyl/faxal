#!/usr/bin/env python3
"""Checks the Faxal formatter on every .fx file in the repository.

For each file: formatting must be idempotent, and the formatted code must compile to *exactly* the same
bytecode as the original (only line numbers may differ). So formatting can never change what a program does.
usage: python3 tests/fmt_check.py <faxal binary>
"""
import pathlib, re, subprocess, sys, tempfile

binary = sys.argv[1] if len(sys.argv) > 1 else "bin/faxal"
here = pathlib.Path(__file__).parent
roots = [here / "spec", here / "std", here.parent / "lib", here.parent / "tools", here.parent.parent / "examples"]

def run(*args, input=None):
    return subprocess.run([binary, *args], capture_output=True, text=True, input=input, timeout=60)

def bytecode(path):
    r = run("check", "--dump", str(path))
    if r.returncode != 0:
        return None
    # drop the source-line column, keep everything else
    return [re.sub(r"^(\d{4}) (?:   \| |[ \d]{4} )", r"\1 ", l) for l in r.stdout.splitlines() if l[:4].isdigit()]

files = sorted(p for root in roots if root.exists() for p in root.rglob("*.fx"))
bad = 0
with tempfile.TemporaryDirectory() as tmp:
    for f in files:
        formatted = run("fmt", "--stdout", str(f))
        if formatted.returncode != 0:
            print(f"FAIL {f}: formatter error: {formatted.stdout[-200:]}{formatted.stderr[-200:]}"); bad += 1; continue
        out1 = pathlib.Path(tmp) / "once.fx"
        out1.write_text(formatted.stdout)
        again = run("fmt", "--stdout", str(out1))
        if again.stdout != formatted.stdout:
            print(f"FAIL {f}: formatting is not idempotent"); bad += 1; continue
        before, after = bytecode(f), bytecode(out1)
        if before is None:
            continue  # files that are meant to fail to compile are only checked for idempotency
        if before != after:
            print(f"FAIL {f}: formatting changed the compiled program"); bad += 1
print(f"{len(files)} files checked, {bad} problems")
sys.exit(1 if bad else 0)
