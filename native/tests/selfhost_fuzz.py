#!/usr/bin/env python3
"""Differential fuzzing of the two compilers on damaged programs.

Real programs are corrupted in random ways. For each result the C compiler and the compiler written in
Faxal must agree: both compile it to identical bytecode, or both reject it with the same first error
(message, line, column).
usage: python3 tests/selfhost_fuzz.py <faxal binary> [iterations] [seed]
"""
import pathlib, random, re, subprocess, sys, tempfile

binary = sys.argv[1] if len(sys.argv) > 1 else "bin/faxal"
iterations = int(sys.argv[2]) if len(sys.argv) > 2 else 300
seed = int(sys.argv[3]) if len(sys.argv) > 3 else random.randrange(10**6)
rng = random.Random(seed)

here = pathlib.Path(__file__).parent
corpus = [p.read_text() for p in sorted((here / "spec").glob("*.fx"))]
corpus += [p.read_text() for p in sorted((here / "std").glob("*.fx"))]
corpus += [p.read_text() for p in sorted((here.parent.parent / "examples").glob("*.fx"))]
corpus += [p.read_text() for p in sorted((here.parent / "lib" / "std").glob("*.fx")) if p.name not in ("compiler.fx",)]

TOKENS = ["(", ")", "{", "}", "[", "]", ",", ".", "..", ":", ";", "+", "-", "*", "/", "%", "**", "=", "==", "!=", "<", ">", "<=",
          "let", "fn", "if", "else", "while", "for", "in", "break", "continue", "return", "try", "catch", "throw", "import",
          "class", "extends", "self", "super", "by", "nil", "true", "and", "or", "not", "|>", "??", "?.", "!", "|", "?", "$", "@",
          '"', "'", 'f"', "f'", '"{', "{x}", "\\", "\n", "\n\n", "#", "0", "0x", "0xg", "1e", "1e5", "1_0", "x", "[0]", ".len()", "=>"]

def mutate(src):
    s = src
    for _ in range(rng.randint(1, 3)):
        if not s: break
        i = rng.randrange(len(s))
        k = rng.randrange(6)
        if k == 0: s = s[:i] + s[i + 1:]
        elif k == 1: s = s[:i] + rng.choice(TOKENS) + s[i:]
        elif k == 2:
            j = min(len(s), i + rng.randint(1, 50)); s = s[:j] + s[i:j] + s[j:]
        elif k == 3:
            j = min(len(s), i + rng.randint(1, 30)); s = s[:i] + s[j:]
        elif k == 4: s = s[:i] + rng.choice(TOKENS) + s[i + 1:]
        else:
            lines = s.split("\n"); a = rng.randrange(len(lines)); lines.insert(rng.randrange(len(lines)), lines[a]); s = "\n".join(lines)
    return s

def c_compile(path):
    r = subprocess.run([binary, "--c-compiler", "check", "--dump", path], capture_output=True, text=True, timeout=60)
    if r.returncode == 0:
        return ("ok", r.stdout.rsplit(f"{path}: ok", 1)[0])
    m = re.search(r"^error: (.*)\n\s+--> .*:(\d+):(\d+)", r.stderr, re.M)
    return ("error", (int(m.group(2)), int(m.group(3)), m.group(1)) if m else r.stderr)

def fx_compile(path):
    r = subprocess.run([binary, "fxc", "--errors", path], capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        return ("ok", subprocess.run([binary, "fxc", path], capture_output=True, text=True, timeout=120).stdout)
    first = r.stdout.splitlines()[0] if r.stdout.strip() else ""
    m = re.match(r"(\d+):(\d+): (.*)", first)
    return ("error", (int(m.group(1)), int(m.group(2)), m.group(3)) if m else r.stdout + r.stderr)

bad = 0
stats = {'compile': 0, 'error': 0}
with tempfile.TemporaryDirectory() as tmp:
    path = str(pathlib.Path(tmp) / "case.fx")
    for n in range(iterations):
        src = mutate(rng.choice(corpus))
        pathlib.Path(path).write_text(src)
        try:
            a, b = c_compile(path), fx_compile(path)
        except subprocess.TimeoutExpired:
            bad += 1; print(f"TIMEOUT case {n} (seed {seed})"); pathlib.Path(f"/tmp/selfhost-fuzz-{n}.fx").write_text(src); continue
        stats[a[0] == 'ok' and 'compile' or 'error'] += 1
        if a != b:
            bad += 1
            pathlib.Path(f"/tmp/selfhost-fuzz-{n}.fx").write_text(src)
            print(f"DIFFERENT case {n} (seed {seed}), saved to /tmp/selfhost-fuzz-{n}.fx")
            if a[0] == "error" or b[0] == "error": print(f"   C: {a if a[0]=='error' else 'compiles'}\n   Faxal: {b if b[0]=='error' else 'compiles'}")
            else:
                for i, (x, y) in enumerate(zip(a[1].splitlines(), b[1].splitlines())):
                    if x != y: print(f"   line {i+1}: C {x!r} / Faxal {y!r}"); break
print(f"{iterations} damaged programs compared ({stats['compile']} compile, {stats['error']} are rejected), {bad} different (seed {seed})")
sys.exit(1 if bad else 0)
