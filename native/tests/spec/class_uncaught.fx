class Stack {
  fn init() { self.items = [] }
  fn pop() { if self.items.len() == 0 { throw "stack is empty" } return self.items.pop() }
}
Stack().pop()
# error: stack is empty
# error: at pop (
