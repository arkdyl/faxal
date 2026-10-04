fn box(w, h = 2, label = "box", border = "#") {
  return f"{label}: {w}x{h} {border}"
}
print(box(3))                                         # expect: box: 3x2 #
print(box(3, label = "big"))                          # expect: big: 3x2 #
print(box(5, border = "*", h = 9))                    # expect: box: 5x9 *
print(box(w = 1, h = 1))                              # expect: box: 1x1 #
class Pt {
  fn init(x, y = 0) { self.x = x; self.y = y }
  fn move(dx = 0, dy = 0) { return Pt(self.x + dx, self.y + dy) }
  fn to_str() => f"({self.x}, {self.y})"
}
class Pt3 extends Pt {
  fn init(x, y = 0, z = 0) { super.init(x, y = y); self.z = z }
  fn move(dx = 0, dy = 0, dz = 0) {
    let p = super.move(dx = dx, dy = dy)
    return Pt3(p.x, p.y, self.z + dz)
  }
}
print(Pt(y = 5, x = 1), Pt(1).move(dy = 4))           # expect: (1, 5) (1, 4)
print(Pt3(1, z = 9).move(dz = 1).z)                   # expect: 10
try { box() } catch e { print(e) }                    # expect: box() takes 1 to 4 arguments but got 0
try { box(h = 3) } catch e { print(e) }               # expect: box() is missing the argument 'w'
try { box(1, hight = 3) } catch e { print(e) }        # expect: box() has no parameter 'hight' (its parameters: w, h, label, border)
try { box(1, w = 3) } catch e { print(e) }            # expect: box() got more than one value for 'w'
try { box(1, h = 1, h = 2) } catch e { print(e) }     # expect: box() got more than one value for 'h'
try { print(sqrt(x = 4)) } catch e { print(e) }       # expect: sqrt() is a built-in function: it doesn't take named arguments
let f = fn(a, b = 10) => a - b
print(f(b = 1, a = 5), f(5, b = 3))                   # expect: 4 2
let t = nil
print(t?.foo(x = 1))                                  # expect: nil
async fn job(n, scale = 2) { return n * scale }
print(resume(job(4, scale = 5)))                      # expect: 20
fn pick(a, b = "B", c = "C") => a + b + c
print(pick("a", c = "!"), pick(c = "3", a = "1"))     # expect: aB! 1B3
print(pick("x", b = pick("y", c = "z")))              # expect: xyBzC
let args = {n: 1}
fn show(n, extra = nil) => str(n) + str(extra)
print(show(args.n, extra = [1, 2]))                   # expect: 1[1, 2]
print(show(n = 3 == 3, extra = (1 < 2)))              # expect: truetrue
