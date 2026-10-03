# cli-only
# Sieve of Eratosthenes
fn primes_up_to(n) {
  let is_prime = []
  for i in 0..n + 1 { is_prime.push(true) }
  let found = []
  for i in 2..n + 1 {
    if is_prime[i] {
      found.push(i)
      let j = i * i
      while j <= n {
        is_prime[j] = false
        j += i
      }
    }
  }
  return found
}

let ps = primes_up_to(100)
print(f"{ps.len()} primes below 100:")
print(ps.join(" "))
