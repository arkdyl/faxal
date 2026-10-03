# std/iter: helpers for working with lists, written in Faxal.
# (map, filter, reduce, each, sort, join... are already methods on lists.)

fn enumerate(xs) {
  let out = []
  let i = 0
  for x in xs {
    out.push([i, x])
    i += 1
  }
  return out
}

fn zip(a, b) {
  let out = []
  let n = min(len(a), len(b))
  for i in 0..n { out.push([a[i], b[i]]) }
  return out
}

fn sum(xs) {
  let total = 0
  for x in xs { total += x }
  return total
}

fn product(xs) {
  let total = 1
  for x in xs { total *= x }
  return total
}

fn count(xs, test) {
  let n = 0
  for x in xs { if test(x) { n += 1 } }
  return n
}

fn any(xs, test = nil) {
  for x in xs {
    if (test == nil and x) or (test != nil and test(x)) { return true }
  }
  return false
}

fn all(xs, test = nil) {
  for x in xs {
    if not ((test == nil and x) or (test != nil and test(x))) { return false }
  }
  return true
}

# The first item for which test(item) is true, or nil.
fn find(xs, test) {
  for x in xs { if test(x) { return x } }
  return nil
}

fn take(xs, n) { return xs.slice(0, n) }
fn skip(xs, n) { return xs.slice(n) }

fn reverse(xs) { return xs.copy().reverse() }

# One level of nesting removed: flatten([[1, 2], [3]]) is [1, 2, 3]
fn flatten(xs) {
  let out = []
  for x in xs {
    if type(x) == "list" { for y in x { out.push(y) } } else { out.push(x) }
  }
  return out
}

# Pieces of at most n items: chunks([1, 2, 3, 4, 5], 2) is [[1, 2], [3, 4], [5]]
fn chunks(xs, n) {
  if n < 1 { throw "chunks() needs a size of at least 1" }
  let out = []
  let i = 0
  while i < len(xs) {
    out.push(xs.slice(i, i + n))
    i += n
  }
  return out
}

# Removes repeated items, keeping the first of each. Works for any kind of value.
fn unique(xs) {
  let out = []
  let seen = {}
  for x in xs {
    let t = type(x)
    if t == "string" or t == "number" or t == "bool" {
      if not seen.has(x) {
        seen[x] = true
        out.push(x)
      }
    } else if not out.contains(x) {
      out.push(x)
    }
  }
  return out
}

# Groups items by a key: group_by(["a", "bb", "c"], len) is {1: ["a", "c"], 2: ["bb"]}
fn group_by(xs, key) {
  let groups = {}
  for x in xs {
    let k = key(x)
    if not groups.has(k) { groups[k] = [] }
    groups[k].push(x)
  }
  return groups
}

# A new list sorted by key(item). Items with equal keys keep their order.
fn sort_by(xs, key) {
  return xs.copy().sort(fn(a, b) {
    let ka = key(a)
    let kb = key(b)
    if ka < kb { return -1 }
    if ka > kb { return 1 }
    return 0
  })
}

fn min_by(xs, key) {
  if len(xs) == 0 { return nil }
  let best = xs[0]
  for x in xs { if key(x) < key(best) { best = x } }
  return best
}

fn max_by(xs, key) {
  if len(xs) == 0 { return nil }
  let best = xs[0]
  for x in xs { if key(x) > key(best) { best = x } }
  return best
}

# Splits into [matching, others].
fn partition(xs, test) {
  let yes = []
  let no = []
  for x in xs { if test(x) { yes.push(x) } else { no.push(x) } }
  return [yes, no]
}

fn repeat(x, n) {
  let out = []
  for i in 0..n { out.push(x) }
  return out
}
