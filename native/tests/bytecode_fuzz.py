#!/usr/bin/env python3
"""Fuzzes the bytecode loader, the verifier and the VM with damaged .fxc files.

Valid .fxc files are mutated at random (bytes changed, inserted, removed, truncated, chunks copied). The checksum is
then recomputed, so the damage is not caught by the checksum and has to be caught by the reader and the verifier
(or, if the verifier accepts it, survived by the VM). Nothing may crash, hang, or trigger a sanitizer report.
usage: python3 tests/bytecode_fuzz.py <faxal binary, ideally the ASan build> [iterations] [seed]
"""
import pathlib, random, shutil, subprocess, sys, tempfile

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin/faxal-asan").resolve())
iterations = int(sys.argv[2]) if len(sys.argv) > 2 else 400
seed = int(sys.argv[3]) if len(sys.argv) > 3 else random.randrange(10**6)
rng = random.Random(seed)
here = pathlib.Path(__file__).parent

def checksum(data):
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h

def with_checksum(body):
    return bytes(body) + checksum(body).to_bytes(4, "little")

def code_ranges(data):
    """(start, length) of the instruction bytes of every function in a .fxc file."""
    pos = 4 + 2 + 2 + 4
    def u32():
        nonlocal pos
        v = int.from_bytes(data[pos:pos + 4], "little"); pos += 4; return v
    for _ in range(2):          # faxal version, source name
        pos += u32()
    count = u32()
    ranges = []
    for _ in range(count):
        n = u32()
        if n != 0xFFFFFFFF: pos += n
        pos += 1 + 1 + 2 + 1
        length = u32()
        ranges.append((pos, length)); pos += length
        runs = u32(); pos += runs * 8
        for _ in range(u32()):
            tag = data[pos]; pos += 1
            if tag == 0: pos += 8
            elif tag == 1: pos += 4 + int.from_bytes(data[pos:pos + 4], "little")
            else: pos += 4
    return ranges

def mutate_code(good):
    """Damage only the instruction streams: change an instruction, an operand, or swap instructions around."""
    body = bytearray(good[:-4])
    ranges = [r for r in code_ranges(good) if r[1] > 2]
    for _ in range(rng.randint(1, 3)):
        start, length = rng.choice(ranges)
        i = start + rng.randrange(length)
        kind = rng.randrange(4)
        if kind == 0: body[i] = rng.randrange(0, 57)                      # a different instruction
        elif kind == 1: body[i] = rng.choice([0, 1, 2, 3, 5, 255, body[i] ^ 1, (body[i] + 1) & 255])   # a nearby operand
        elif kind == 2:
            j = start + rng.randrange(length); body[i], body[j] = body[j], body[i]
        else: body[i] = rng.randrange(256)
    return with_checksum(body)

def mutate(good):
    if rng.random() < 0.6:
        try: return mutate_code(good)
        except Exception: pass
    return mutate_bytes(good)

def mutate_bytes(good):
    body = bytearray(good[:-4])
    for _ in range(rng.randint(1, 4)):
        if len(body) < 20: break
        kind = rng.randrange(7)
        i = rng.randrange(14, len(body))        # leave the magic and version alone most of the time
        if kind == 0: body[i] = rng.randrange(256)
        elif kind == 1: body[i] ^= 1 << rng.randrange(8)
        elif kind == 2: body.insert(i, rng.randrange(256))
        elif kind == 3: del body[i]
        elif kind == 4: del body[i:i + rng.randint(1, 20)]
        elif kind == 5:
            j = min(len(body), i + rng.randint(1, 30)); body[i:i] = body[i:j]
        else: body[i] = rng.choice([0, 1, 2, 255, 254, 128, 127])
    return with_checksum(body)

def attempt(path, *args):
    try:
        r = subprocess.run([binary, *args, path], capture_output=True, text=True, timeout=20, stdin=subprocess.DEVNULL, errors="replace")
    except subprocess.TimeoutExpired:
        return "timeout"
    if r.returncode < 0:
        return f"killed by signal {-r.returncode}: {r.stderr[:300]}"
    if "Sanitizer" in r.stderr or "runtime error:" in r.stderr:
        return "sanitizer report: " + r.stderr[:600]
    return None

bad = 0
stats = {"rejected": 0, "verified": 0}
with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    sources = sorted((here / "spec").glob("*.fx")) + sorted((here.parent.parent / "examples").glob("*.fx")) + sorted((here / "std").glob("*.fx"))
    goods = []
    for s in sources:
        shutil.copy(s, tmp / s.name)
        r = subprocess.run([binary, "compile", s.name], cwd=tmp, capture_output=True, text=True, stdin=subprocess.DEVNULL)
        out = tmp / (s.stem + ".fxc")
        if r.returncode == 0 and out.exists():
            goods.append(out.read_bytes())
    for n in range(iterations):
        data = mutate(rng.choice(goods))
        path = tmp / "case.fxc"
        path.write_bytes(data)
        problem = attempt(str(path), "check")
        c = subprocess.run([binary, "check", str(path)], capture_output=True, text=True, errors="replace", stdin=subprocess.DEVNULL)
        stats["verified" if c.returncode == 0 else "rejected"] += 1
        if problem is None and c.returncode == 0:
            problem = attempt(str(path), "--sandbox")      # the verifier accepted it: run it, in safe mode
            if problem == "timeout": problem = None        # a mutated program may loop forever; that is fine
        if problem:
            bad += 1
            keep = pathlib.Path(f"/tmp/fxc-fuzz-{n}.fxc"); keep.write_bytes(data)
            print(f"BAD case {n} (seed {seed}): {problem}\n   saved to {keep}")
print(f"{iterations} damaged bytecode files: {stats['rejected']} rejected, {stats['verified']} accepted by the verifier, {bad} problems (seed {seed})")
sys.exit(1 if bad else 0)
