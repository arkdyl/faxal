print(1 + 2 * 3)                  # expect: 7
print((1 + 2) * 3)                # expect: 9
print(7 / 2, 7 % 3, -7 % 3)       # expect: 3.5 1 2
print(2 ** 10, 2 ** 3 ** 2)       # expect: 1024 512
print(-2 ** 2)                    # expect: -4
print(0.1 + 0.2)                  # expect: 0.3
print(1_000 + 0xff)               # expect: 1255
print(10 - 2 - 3)                 # expect: 5
print("a" + "b", "n=" + 5)        # expect: ab n=5
print("ab" * 3, 2 * "x")          # expect: ababab xx
print(1 < 2, 2 <= 2, 3 > 4, 3 >= 4)   # expect: true true false false
print(1 == 1, 1 != 1, "a" == "a", nil == nil)  # expect: true false true true
print("apple" < "banana", "b" < "a")   # expect: true false
print(true and false, true or false, not true)  # expect: false true false
print(nil or "default", false or nil)  # expect: default nil
print(1 and 2, nil and 2)         # expect: 2 nil
print(not nil, not 0, not "")     # expect: true false false
print(1e3, 2.5e-1)                # expect: 1000 0.25
print(type(1), type("s"), type(nil), type(true), type([]), type({}), type(print), type(1..2))  # expect: number string nil bool list map function range
print(str(12), str(1.5), str([1, "a"]))  # expect: 12 1.5 [1, "a"]
print(num("42") + 1, num("x"), int(3.9), int(-3.9), int("7"))  # expect: 43 nil 3 -3 7
print(len("héllo"), len([1, 2]), len({a: 1}), len(1..5))  # expect: 6 2 1 4
print(abs(-3), floor(2.7), ceil(2.1), round(2.5), sqrt(81), min(3, 1, 2), max([4, 9, 2]))  # expect: 3 2 3 3 9 1 9
print(repr("hi"), repr(nil), repr([1, "a"]))  # expect: "hi" nil [1, "a"]
print(ord("A"), chr(97), chr(8364), ord("€"))  # expect: 65 a € 8364
