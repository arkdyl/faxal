#!/usr/bin/env python3
"""Mutation fuzzer: corrupts real programs and checks that faxal never crashes or hangs.

usage: python3 tests/fuzz.py <binary> [iterations] [seed]
A run is "bad" if the process dies from a signal, hangs, or prints a sanitizer report.
"""
import pathlib, random, subprocess, sys

binary = sys.argv[1] if len(sys.argv) > 1 else "bin/faxal"
iterations = int(sys.argv[2]) if len(sys.argv) > 2 else 500
seed = int(sys.argv[3]) if len(sys.argv) > 3 else random.randrange(10**6)
rng = random.Random(seed)

here = pathlib.Path(__file__).parent
corpus = [p.read_text() for p in sorted((here / "spec").glob("*.fx"))]
corpus += [p.read_text() for p in sorted((here.parent.parent / "examples").glob("*.fx")) if "guess" not in p.name]

TOKENS = ["(", ")", "{", "}", "[", "]", ",", ".", "..", ":", ";", "+", "-", "*", "/", "%", "**", "=", "==", "<", ">",
          "let", "fn", "if", "else", "while", "for", "in", "break", "continue", "return", "try", "catch", "throw",
          "nil", "true", "and", "or", "not", "import", '"', "'", "f\"", "{", "\n", "#", "0", "1e999", "-1", "x", "[0]", ".len()"]

def mutate(src: str) -> str:
    s = src
    for _ in range(rng.randint(1, 4)):
        if not s: break
        i = rng.randrange(len(s))
        kind = rng.randrange(6)
        if kind == 0: s = s[:i] + s[i + 1:]
        elif kind == 1: s = s[:i] + rng.choice(TOKENS) + s[i:]
        elif kind == 2:
            j = min(len(s), i + rng.randint(1, 60)); s = s[:j] + s[i:j] + s[j:]       # duplicate a chunk
        elif kind == 3:
            j = min(len(s), i + rng.randint(1, 40)); s = s[:i] + s[j:]                # delete a chunk
        elif kind == 4: s = s[:i] + rng.choice(TOKENS) + s[i + 1:]
        else:
            lines = s.split("\n"); k = rng.randrange(len(lines)); lines.insert(rng.randrange(len(lines)), lines[k]); s = "\n".join(lines)
    return s

nasty = [
    "(" * 5000 + "1" + ")" * 5000,
    "[" * 3000 + "]" * 3000,
    "{" * 400 + "}" * 400,
    "let a = [1]\nfor i in 0..100 { a.push(a) }\nprint(a)\nprint(a == a.copy())\nprint(json.encode(a))",
    "let a = []\nlet b = []\na.push(a); a.push(a); b.push(b); b.push(b)\nprint(a == b)",
    "print(\"x\" * 1e9)", "print(\"\" * math.inf)", "print(range(math.nan).len())", "print([1,2][math.nan])",
    "print(\"abc\"[math.nan:])", "print((0..math.inf).len())", "for i in 0..math.inf { break }",
    "let s = \"x\"\nwhile true { s = s + s }", "let l = [1]\nwhile true { l = l + l }",
    "fn f() { return [1].map(fn(x) { return f() }) }\ntry { f() } catch e { print(e) }",
    "fn f(n) { try { return f(n + 1) } catch e { throw e } }\nf(0)",
    "let x = 1\n" + "if true {\n" * 300 + "}\n" * 300,
    "print(f\"{" * 100 + "1" + "}\"" * 100 + ")",
    "let big = [" + ",".join(["1"] * 60000) + "]\nprint(len(big))",
    "let m = {" + ",".join(f"k{i}: {i}" for i in range(30000)) + "}\nprint(len(m))",
    "print(json.decode(\"[\" * 500 + \"]\" * 500))", "print(chr(0).len())", "print(\"a\\0b\".split(\"b\"))",
    "let a = []\nfor i in 0..200000 { a.push(i) }\nprint(a.sort(fn(x, y) { return y - x })[0])",
    "[3,1,2].sort(fn(a, b) { return \"x\" })", "print(math.randint(1, 0))", "print(int(1e300), int(math.nan))",
    "let t = {}\nt[math.nan] = 1\nt[math.nan] = 2\nprint(len(t))",
    "print(1 / 0)", "print(10 % 0)", "print(-(-(-1)))", "print(not not not nil)",
]

bad = 0
import os
FMT = os.environ.get("FUZZ_FMT")   # fuzz the formatter instead of the interpreter
inputs = ([] if (os.environ.get("NO_NASTY") or FMT) else nasty) + [mutate(rng.choice(corpus)) for _ in range(iterations)]
for n, src in enumerate(inputs):
    try:
        if FMT:
            p = pathlib.Path("/tmp/fuzz-fmt-input.fx"); p.write_text(src)
            r = subprocess.run([binary, "fmt", "--stdout", str(p)], capture_output=True, text=True, timeout=60)
        else:
            r = subprocess.run([binary, "--sandbox", "--json", "-"], input=src, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        bad += 1; print(f"HANG (input {n}, seed {seed})"); pathlib.Path(f"/tmp/fuzz-hang-{n}.fx").write_text(src); continue
    problem = None
    if r.returncode < 0: problem = f"killed by signal {-r.returncode}"
    elif "Sanitizer" in r.stderr or "runtime error" in r.stderr: problem = "sanitizer report: " + r.stderr[:400]
    elif FMT and ("would have changed" in r.stdout or "would have changed" in r.stderr): problem = "formatter changed the program"
    elif FMT and r.returncode not in (0, 1): problem = f"unexpected exit {r.returncode}: {r.stderr[:200]}"
    elif not FMT and r.returncode != 0: problem = f"unexpected exit {r.returncode}"
    if problem:
        bad += 1; print(f"BAD (input {n}, seed {seed}): {problem}")
        pathlib.Path(f"/tmp/fuzz-bad-{n}.fx").write_text(src)
print(f"{len(inputs)} programs, {bad} problems (seed {seed})")
sys.exit(1 if bad else 0)
