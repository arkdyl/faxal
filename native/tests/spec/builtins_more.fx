print("ab".repeat(3), "héllo".reverse())              # expect: ababab olléh
print("7".pad_left(3, "0"), "x".center(5, "*"), "ab".pad_right(4, ".") + "|")   # expect: 007 **x** ab..|
print("  a ".lstrip() + "|", "|" + " a  ".rstrip(), "hELLO".capitalize())   # expect: a | | a Hello
print("123".is_digit(), "12a".is_digit(), "abc".is_alpha(), "".is_empty(), "é".size(), "é".len())   # expect: true false true true 1 2
let l = [3, 1, 2, 3]
print(l.first(), l.last(), l.sum(), l.min(), l.max(), [].first())   # expect: 3 3 9 1 3 nil
print(l.unique(), sorted(l), reversed(l), l)          # expect: [3, 1, 2] [1, 2, 3, 3] [3, 2, 1, 3] [3, 1, 2, 3]
print(l.any(fn(x) => x > 2), all(l, fn(x) => x > 0), l.find(fn(x) => x < 3), l.count(3), l.count(fn(x) => x > 1))   # expect: true true 1 2 3
print(zip([1, 2], ["a", "b"]), enumerate(["x", "y"]))   # expect: [[1, "a"], [2, "b"]] [[0, "x"], [1, "y"]]
print([[1, 2], [3]].flatten(), sum([1, 2, 3]), any([]), all([]))   # expect: [1, 2, 3] 6 false true
let m = {"a": 1}
m.merge({"b": 2})
print(m, m.is_empty(), {}.is_empty())                  # expect: {a: 1, b: 2} false true
print(bool(0), bool(nil), bool(false), bool([]))      # expect: true false false true
l.extend(l)
print(l.len())                                        # expect: 8
let big = [1, 2]
big.extend(big)
print(big)                                            # expect: [1, 2, 1, 2]
