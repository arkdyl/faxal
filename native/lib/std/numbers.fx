# std/numbers: number helpers, written in Faxal.

fn gcd(a, b) {
  a = abs(a)
  b = abs(b)
  while b != 0 {
    let t = b
    b = a % b
    a = t
  }
  return a
}

fn lcm(a, b) {
  if a == 0 or b == 0 { return 0 }
  return abs(a * b) / gcd(a, b)
}

fn factorial(n) {
  if n < 0 or n != floor(n) { throw "factorial() needs a whole number that is not negative" }
  let result = 1
  for i in 2..n + 1 { result *= i }
  return result
}

fn is_prime(n) {
  if n < 2 or n != floor(n) { return false }
  if n < 4 { return true }
  if n % 2 == 0 { return false }
  let i = 3
  while i * i <= n {
    if n % i == 0 { return false }
    i += 2
  }
  return true
}

# All the primes up to and including n.
fn primes_up_to(n) {
  let found = []
  for i in 2..n + 1 { if is_prime(i) { found.push(i) } }
  return found
}

fn mean(xs) {
  if len(xs) == 0 { throw "mean() needs at least one number" }
  let total = 0
  for x in xs { total += x }
  return total / len(xs)
}

fn median(xs) {
  if len(xs) == 0 { throw "median() needs at least one number" }
  let sorted = xs.copy().sort()
  let mid = floor(len(sorted) / 2)
  if len(sorted) % 2 == 1 { return sorted[mid] }
  return (sorted[mid - 1] + sorted[mid]) / 2
}

fn variance(xs) {
  let m = mean(xs)
  let total = 0
  for x in xs { total += (x - m) ** 2 }
  return total / len(xs)
}

fn stddev(xs) { return math.sqrt(variance(xs)) }

# Moves a value from one range to another: remap(5, 0, 10, 0, 100) is 50
fn remap(x, from_lo, from_hi, to_lo, to_hi) {
  return to_lo + (x - from_lo) * (to_hi - to_lo) / (from_hi - from_lo)
}
