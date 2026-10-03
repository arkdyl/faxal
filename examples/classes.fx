# title: Classes
class Shape {
  fn init(name) { self.name = name }
  fn area() { return 0 }
  fn to_str() { return f"{self.name} with area {round(self.area())}" }
}

class Circle extends Shape {
  fn init(r) {
    super.init("circle")
    self.r = r
  }
  fn area() { return math.pi * self.r ** 2 }
}

class Rect extends Shape {
  fn init(w, h) {
    super.init("rectangle")
    self.w = w
    self.h = h
  }
  fn area() { return self.w * self.h }
}

let shapes = [Circle(5), Rect(3, 4), Circle(1)]
print(shapes)  # to_str decides how objects print
for s in shapes { print(s) }

let total = shapes.reduce(0, fn(sum, s) { return sum + s.area() })
print(f"total area: {round(total)}")
