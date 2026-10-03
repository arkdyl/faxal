color("red"); width(3)
forward(10); turn(90); forward(10)
penup(); forward(5); pendown()
background("black")
home(); goto(1, 2)
print("drawn")                                            # expect: drawn
circle(10); disc(5); rect(20, 10); box(4, 4); text("hi", 12); text(42)
print("shapes ok")                                  # expect: shapes ok
