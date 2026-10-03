print(math.sqrt(2) * math.sqrt(2) > 1.9999, math.pi > 3.14, math.e > 2.71)    # expect: true true true
print(math.floor(-1.5), math.ceil(-1.5), math.round(-1.5), math.trunc(-1.5))  # expect: -2 -1 -2 -1
print(math.pow(2, 8), math.abs(-4), math.sign(-9), math.sign(0), math.hypot(3, 4))   # expect: 256 4 -1 0 5
print(math.max(1, 5, 3), math.min([4, 2, 8]), math.clamp(15, 0, 10), math.clamp(-5, 0, 10))  # expect: 5 2 10 0
print(math.log10(1000), math.log2(8), math.exp(0), math.sin(0), math.cos(0))   # expect: 3 3 1 0 1
print(math.degrees(math.pi), math.radians(180) == math.pi)   # expect: 180 true
math.seed(42)
let a = math.random()
math.seed(42)
print(a == math.random(), a >= 0 and a < 1)                 # expect: true true
let ok = true
for i in 0..200 { let r = math.randint(3, 6); if r < 3 or r > 6 or r != floor(r) { ok = false } }
print(ok)                                                   # expect: true
print(math.inf > 1e308, math.nan == math.nan, 1e300 * 1e300)   # expect: true false inf
