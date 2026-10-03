# title: Spiral
# Draw with a turtle: forward(), turn(), color()
let i = 0
while i < 90 {
  color(90 + i, 90 + i, 90 + i)
  forward(i * 2.5)
  turn(89)
  i += 1
}
