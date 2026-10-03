# title: Pipes & defaults
# |> passes the value on its left to the function on its right
fn double(x) { return x * 2 }
fn add(x, amount = 1) { return x + amount }

print(5 |> double |> add)
print(5 |> double |> add(100))

let words = ["pipe", "lines", "of", "code"]
let shout = words
  |> fn(ws) { return ws.map(fn(w) { return w.upper() }) }
  |> fn(ws) { return ws.join(" ") }
print(shout)

# ?? gives a default for nil, ?. is a safe lookup
let settings = {theme: nil, user: {name: "Ada"}}
print(settings.theme ?? "light")
print(settings?.user?.name, settings.guest?.name ?? "nobody")

# ranges can take a step
for n in 10..0 by -3 { write(n, " ") }
print()
