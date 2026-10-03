# title: Mandala
# Circles, colors from std/color, and a loop: that's all a mandala needs
import "std/color" as c

background("#0b0b10")
width(1.5)
let petals = 24
for i in 0..petals {
  color(c.rainbow(i, petals))
  penup()
  home()
  turn(360 * i / petals)
  forward(90)
  circle(34)
}
color("white")
home()
disc(6)
