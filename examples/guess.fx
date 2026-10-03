# cli-only
# interactive: a number guessing game
let secret = math.randint(1, 100)
let tries = 0
print("I'm thinking of a number from 1 to 100.")
while true {
  let line = input("Your guess: ")
  if line == nil { break }
  let guess = num(line)
  if guess == nil { print("Please type a number."); continue }
  tries += 1
  if guess < secret { print("Higher!") }
  else if guess > secret { print("Lower!") }
  else {
    print(f"You got it in {tries} tries!")
    break
  }
}
