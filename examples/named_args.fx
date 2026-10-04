# title: Named arguments
# Pass arguments by name, in any order, after the positional ones.
fn box(w, h = 2, label = "box", border = "#") {
  return f"{label}: {w}x{h} {border}"
}
print(box(3))
print(box(3, label = "big"))
print(box(5, border = "*", h = 9))
print(box(h = 1, w = 4))

class Point {
  fn init(x, y = 0) { self.x = x; self.y = y }
  fn moved(dx = 0, dy = 0) => Point(self.x + dx, self.y + dy)
  fn to_str() => f"({self.x}, {self.y})"
}
print(Point(y = 5, x = 1), Point(1).moved(dy = 4))

try {
  box(1, hight = 3)
} catch e {
  print(e)
}
