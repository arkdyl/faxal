let s = "Hello, World"
print(s.len(), s.upper(), s.lower())      # expect: 12 HELLO, WORLD hello, world
print("  pad  ".trim() + "|")             # expect: pad|
print(s.contains("World"), s.contains("x"), s.starts_with("Hell"), s.ends_with("d"))   # expect: true false true true
print(s.find("o"), s.find("o", 5), s.find("zzz"))   # expect: 4 8 -1
print(s.replace("l", "L"), "aaa".replace("a", "bb"))   # expect: HeLLo, WorLd bbbbbb
print("a,b,,c".split(","), "abc".split(""), "one".split(","))   # expect: ["a", "b", "", "c"] ["a", "b", "c"] ["one"]
print("héllo".chars(), "x".chars())     # expect: ["h", "é", "l", "l", "o"] ["x"]
print("a\nb\r\nc".lines())               # expect: ["a", "b", "c"]
print("banana".count("an"))              # expect: 2
print(s[0], s[-1], s[7:], s[:5], s[2:4])   # expect: H d World Hello ll
print("tab\there", 'single "quoted"', "say \"hi\"")   # expect: tab	here single "quoted" say "hi"
print("braces { } stay {plain}")         # expect: braces { } stay {plain}
let name = "Ada"
let n = 3
print(f"Hi {name}! {n} + {n} = {n + n}")    # expect: Hi Ada! 3 + 3 = 6
print(f"{name.upper()}{"!" * n}")           # expect: ADA!!!
print(f"list {[1, 2]} map {{x: 1}}")        # expect: list [1, 2] map {x: 1}
print(f"escaped \{ brace")                  # expect: escaped { brace
print(f"{1}{2}{3}", f"", f"{"nested {x}"}")  # expect: 123  nested {x}
print("é" + "ü", "日本語".len(), "日本語".chars().len())   # expect: éü 9 3
print("abc" < "abd", "Z" < "a", "" < "a")   # expect: true true true
print("x" in "xyz", "q" in "xyz")           # expect: true false
let multi = "line1
line2"
print(multi)                                # expect: line1
                                            # expect: line2
print(str(nil) + str(true) + str(1.5))      # expect: niltrue1.5
