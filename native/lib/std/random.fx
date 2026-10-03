# std/random: random numbers and choices, written in Faxal on top of math.random().
#
#   import "std/random" as random
#   random.seed(42)              # same seed, same sequence
#   random.int(1, 6)             # a die roll, 1 to 6
#   random.float(0, 10)          # 0 <= x < 10
#   random.choice(["a", "b"])
#   random.shuffle(list)         # shuffles in place and returns the list
#   random.sample(list, 3)       # 3 different items

fn seed(n) { math.seed(n) }
fn int(lo, hi) { return math.randint(lo, hi) }
fn float(lo = 0, hi = 1) { return lo + math.random() * (hi - lo) }
fn chance(p = 0.5) { return math.random() < p }

fn choice(xs) {
  if len(xs) == 0 { throw "random.choice() needs a non-empty list" }
  return xs[math.randint(0, len(xs) - 1)]
}

fn shuffle(xs) {
  let i = len(xs) - 1
  while i > 0 {
    let j = math.randint(0, i)
    let t = xs[i]
    xs[i] = xs[j]
    xs[j] = t
    i -= 1
  }
  return xs
}

fn sample(xs, n) {
  if n > len(xs) { throw "random.sample() can't pick " + str(n) + " items from " + str(len(xs)) }
  return shuffle(xs.copy())[0:n]
}
