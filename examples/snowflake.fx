# title: Snowflake
# The Koch snowflake, a classic fractal
fn koch(len, depth) {
  if depth == 0 {
    forward(len)
    return
  }
  koch(len / 3, depth - 1)
  turn(-60)
  koch(len / 3, depth - 1)
  turn(120)
  koch(len / 3, depth - 1)
  turn(-60)
  koch(len / 3, depth - 1)
}

width(1)
color("white")
for side in 0..3 {
  koch(300, 4)
  turn(120)
}
