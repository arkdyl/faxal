# title: Optional types
# Types are optional and checked while the program runs.
fn area(w: num, h: num = 1) -> num {
  return w * h
}
print(area(3, 4))

try {
  area("3")
} catch e {
  print(e)
}

# "or" allows more than one type; nil means "nothing"
fn find(items: list, wanted: any) -> num or nil {
  let i = items.index_of(wanted)
  if i < 0 { return nil }
  return i
}
print(find(["a", "b", "c"], "b"), find(["a", "b", "c"], "z"))

class Point {
  fn init(x: num, y: num) { self.x = x; self.y = y }
}
fn norm(p: Point) -> num => math.hypot(p.x, p.y)
print(norm(Point(3, 4)))
