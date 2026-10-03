async fn double(x) { return x * 2 }
let c = double(21)
print(c.status(), resume(c), c.status())              # expect: new 42 done
class Svc {
  fn init(n) { self.n = n }
  async fn get(k) { yield("working"); return self.n + k }
}
let s = Svc(10).get(5)
print(s.to_list(), s.status())                        # expect: ["working"] done
let anon = async fn(a, b = 2) => a * b
print(resume(anon(4)))                                # expect: 8
async fn typed(x: num) -> num { return x }
print(resume(typed(3)))                               # expect: 3
try { typed("no") } catch e { print(e) }              # expect: Type error: parameter 'x' of typed() must be num, got string "no"
async fn wrong() -> num { return "text" }
try { resume(wrong()) } catch e { print(e) }          # expect: Type error: return value of wrong() must be num, got string "text"
async fn adder(a, b) { await 0; return a + b }
fn run(co) {
  let v = resume(co)
  while not co.is_done() { v = resume(co, nil) }
  return v
}
print(run(adder(2, 3)))                               # expect: 5
