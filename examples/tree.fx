# title: Fractal tree
# Functions can call themselves, so drawing a tree is easy
fn tree(size) {
  if size < 6 { return }
  width(size / 10 + 1)
  forward(size)
  turn(-25)
  tree(size * 0.72)
  turn(50)
  tree(size * 0.72)
  turn(-25)
  back(size)
}

color("#dcdce0")
tree(90)
