# std/test: a small test framework, written in Faxal.
#
#   import "std/test" as t
#
#   t.test("addition works", fn() {
#     t.eq(1 + 1, 2)
#   })
#
# Put tests in files that end with _test.fx and run them with:  faxal test

let state = {tests: [], file: ""}

# Register a test. It passes if `body` finishes without throwing.
fn test(name, body) {
  state.tests.push({name: name, body: body, file: state.file})
}

fn fail(message = "test failed") {
  throw message
}

fn ok(condition, message = nil) {
  if not condition { throw message ?? "expected a true value" }
}

fn eq(actual, expected, message = nil) {
  if actual != expected {
    let detail = f"expected {repr(expected)} but got {repr(actual)}"
    throw message == nil and detail or f"{message} ({detail})"
  }
}

fn ne(actual, unexpected, message = nil) {
  if actual == unexpected {
    let detail = f"did not expect {repr(actual)}"
    throw message == nil and detail or f"{message} ({detail})"
  }
}

# Numbers that are equal within a small tolerance.
fn close(actual, expected, tolerance = 0.000001) {
  if abs(actual - expected) > tolerance {
    throw f"expected {expected} (within {tolerance}) but got {actual}"
  }
}

# `body` must throw; optionally the error text must contain `expected`.
fn throws(body, expected = nil) {
  let failed = false
  let error = nil
  try {
    body()
  } catch e {
    failed = true
    error = str(e)
  }
  if not failed { throw "expected an error to be thrown" }
  if expected != nil and not error.contains(str(expected)) {
    throw f"expected an error containing {repr(str(expected))} but got {repr(error)}"
  }
}

# Run every registered test (optionally only those whose name contains `filter`).
# Returns {passed, failed}.
fn run(filter = nil) {
  let passed = 0
  let failures = []
  let current = nil
  for t in state.tests {
    if filter != nil and not t.name.contains(filter) { continue }
    if t.file != current {
      current = t.file
      if current != "" { print(current) }
    }
    try {
      t.body()
      passed += 1
      print(f"  ok    {t.name}")
    } catch e {
      failures.push({name: t.name, file: t.file, error: str(e)})
      print(f"  FAIL  {t.name}")
      print(f"        {e}")
    }
  }
  print(f"\n{passed} passed, {failures.len()} failed")
  return {passed: passed, failed: failures.len()}
}
