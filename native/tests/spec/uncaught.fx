print("before")                   # expect: before
fn boom() { throw "kaboom" }
boom()
print("never")
# error: kaboom
# error: at boom (
