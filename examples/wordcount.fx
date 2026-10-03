# cli-only
# Count the most common words in a file (this one, unless you pass another path).
let path = os.args.len() > 0 and os.args[0] or os.script
let text = fs.read(path)
let counts = {}
for line in text.lines() {
  for word in line.lower().split(" ") {
    let w = word.trim()
    if w.len() > 3 { counts[w] = counts.get(w, 0) + 1 }
  }
}
let top = counts.items().sort(fn(a, b) { return b[1] - a[1] })
for pair in top.slice(0, 5) {
  print(f"{pair[0]}: {pair[1]}")
}
