# title: Lists & maps
let squares = []
for n in 1..11 {
  squares.push(n * n)
}
print("squares:", squares)
print("sum:", squares.reduce(0, fn(a, b) { return a + b }))
print("evens:", squares.filter(fn(n) { return n % 2 == 0 }))

let person = {name: "Ada", langs: ["Faxal", "JS"]}
person.age = 36
print(person)
print(person.keys())
