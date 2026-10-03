# title: Rosette
width(1.5)
for i in 0..36 {
  color(70 + i * 4, 70 + i * 4, 70 + i * 4)
  for side in 0..4 {
    forward(90)
    turn(90)
  }
  turn(10)
}
