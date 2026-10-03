# std/collections: Stack, Queue, Set and Heap, written in Faxal.

class Stack {
  fn init() { self.items = [] }
  fn push(x) { self.items.push(x); return self }
  fn pop() {
    if self.items.len() == 0 { throw "pop from an empty Stack" }
    return self.items.pop()
  }
  fn peek() {
    if self.items.len() == 0 { throw "peek at an empty Stack" }
    return self.items[-1]
  }
  fn len() { return self.items.len() }
  fn is_empty() { return self.items.len() == 0 }
  fn to_list() { return self.items.copy() }
  fn to_str() { return "Stack" + str(self.items) }
}

# First in, first out. pop() is fast no matter how long the queue gets.
class Queue {
  fn init() {
    self.items = []
    self.head = 0
  }
  fn push(x) { self.items.push(x); return self }
  fn pop() {
    if self.head >= self.items.len() { throw "pop from an empty Queue" }
    let value = self.items[self.head]
    self.items[self.head] = nil
    self.head += 1
    if self.head > 32 and self.head * 2 > self.items.len() {
      self.items = self.items.slice(self.head)
      self.head = 0
    }
    return value
  }
  fn peek() {
    if self.head >= self.items.len() { throw "peek at an empty Queue" }
    return self.items[self.head]
  }
  fn len() { return self.items.len() - self.head }
  fn is_empty() { return self.head >= self.items.len() }
  fn to_list() { return self.items.slice(self.head) }
  fn to_str() { return "Queue" + str(self.to_list()) }
}

# A collection of unique values. Values must be strings, numbers or booleans.
class Set {
  fn init() { self.data = {} }
  fn add(x) { self.data[x] = true; return self }
  fn has(x) { return self.data.has(x) }
  fn remove(x) { self.data.remove(x); return self }
  fn len() { return self.data.len() }
  fn is_empty() { return self.data.len() == 0 }
  fn to_list() { return self.data.keys() }
  fn each(f) { self.data.keys().each(f) }
  fn union(other) {
    let result = set_of(self.to_list())
    for x in other.to_list() { result.add(x) }
    return result
  }
  fn intersect(other) {
    let result = Set()
    for x in self.to_list() { if other.has(x) { result.add(x) } }
    return result
  }
  fn minus(other) {
    let result = Set()
    for x in self.to_list() { if not other.has(x) { result.add(x) } }
    return result
  }
  fn is_subset(other) {
    for x in self.to_list() { if not other.has(x) { return false } }
    return true
  }
  fn to_str() { return "Set" + str(self.to_list()) }
}

fn set_of(items) {
  let s = Set()
  for x in items { s.add(x) }
  return s
}

# How many times each value appears: counter(["a", "b", "a"]) is {a: 2, b: 1}
fn counter(items) {
  let counts = {}
  for x in items { counts[x] = counts.get(x, 0) + 1 }
  return counts
}

fn _default_compare(a, b) {
  if a < b { return -1 }
  if a > b { return 1 }
  return 0
}

# A priority queue: pop() always returns the smallest item.
# Pass your own compare(a, b) (negative, zero or positive) to change the order.
class Heap {
  fn init(compare = nil) {
    self.items = []
    self.compare = compare ?? _default_compare
  }
  fn len() { return self.items.len() }
  fn is_empty() { return self.items.len() == 0 }
  fn peek() {
    if self.items.len() == 0 { throw "peek at an empty Heap" }
    return self.items[0]
  }
  fn push(x) {
    self.items.push(x)
    let i = self.items.len() - 1
    while i > 0 {
      let parent = floor((i - 1) / 2)
      if self.compare(self.items[i], self.items[parent]) >= 0 { break }
      let tmp = self.items[i]
      self.items[i] = self.items[parent]
      self.items[parent] = tmp
      i = parent
    }
    return self
  }
  fn pop() {
    let n = self.items.len()
    if n == 0 { throw "pop from an empty Heap" }
    let top = self.items[0]
    let last = self.items.pop()
    n -= 1
    if n > 0 {
      self.items[0] = last
      let i = 0
      while true {
        let left = i * 2 + 1
        let right = left + 1
        let smallest = i
        if left < n and self.compare(self.items[left], self.items[smallest]) < 0 { smallest = left }
        if right < n and self.compare(self.items[right], self.items[smallest]) < 0 { smallest = right }
        if smallest == i { break }
        let tmp = self.items[i]
        self.items[i] = self.items[smallest]
        self.items[smallest] = tmp
        i = smallest
      }
    }
    return top
  }
  fn to_str() { return "Heap(" + str(self.items.len()) + " items)" }
}
