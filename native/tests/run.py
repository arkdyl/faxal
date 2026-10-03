#!/usr/bin/env python3
"""Spec test runner.

Each tests/spec/**/*.fx file declares its expectations in comments:
  # expect: <line>          one line of expected stdout (in order)
  # error: <text>           the program must fail at runtime (exit 70), stderr containing <text>
  # compile-error: <text>   the program must fail to compile (exit 65), stderr containing <text>
Files in a directory called "modules" are helpers, not tests.
"""
import re, subprocess, sys, pathlib

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal").resolve()
root = pathlib.Path(__file__).parent / "spec"
only = sys.argv[2] if len(sys.argv) > 2 else None

passed = failed = 0
for f in sorted(root.rglob("*.fx")):
    if "modules" in f.parts or (only and only not in str(f)):
        continue
    src = f.read_text()
    expect = re.findall(r"#\s*expect: ?(.*)$", src, re.M)
    err = re.findall(r"#\s*error: ?(.*)$", src, re.M)
    cerr = re.findall(r"#\s*compile-error: ?(.*)$", src, re.M)
    try:
        r = subprocess.run([str(binary), f.name], cwd=f.parent, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        print(f"FAIL {f.relative_to(root)}: timed out"); failed += 1; continue
    problems = []
    want_code = 70 if err else 65 if cerr else 0
    if r.returncode != want_code:
        problems.append(f"exit code {r.returncode}, wanted {want_code}")
    if err and not any(e in r.stderr for e in err): problems.append(f"stderr missing {err!r}:\n{r.stderr}")
    if cerr and not any(e in r.stderr for e in cerr): problems.append(f"stderr missing {cerr!r}:\n{r.stderr}")
    if expect or not (err or cerr):
        got = [l.rstrip() for l in r.stdout.split("\n")]
        if got and got[-1] == "": got.pop()
        want = [e.rstrip() for e in expect]
        if got != want:
            for i in range(max(len(got), len(want))):
                g = got[i] if i < len(got) else "<missing>"; w = want[i] if i < len(want) else "<missing>"
                if g != w:
                    problems.append(f"line {i+1}: got {g!r}, wanted {w!r}"); break
            if not problems or "line" not in problems[-1]: problems.append("output differs")
        if r.returncode == 0 and r.stderr.strip(): problems.append("unexpected stderr: " + r.stderr.strip()[:200])
    if problems:
        failed += 1; print(f"FAIL {f.relative_to(root)}"); [print("   ", p) for p in problems]
    else:
        passed += 1
# the example programs must all run cleanly (interactive ones are skipped)
for f in sorted((pathlib.Path(__file__).parent.parent.parent / "examples").glob("*.fx")):
    if "guess" in f.name or (only and only not in str(f)):
        continue
    r = subprocess.run([str(binary), str(f)], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        failed += 1; print(f"FAIL examples/{f.name}: exit {r.returncode}\n    {r.stderr.strip()[:300]}")
    else:
        passed += 1
print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
