# std/tasks: concurrent tasks for `async fn` and `await`, written in Faxal.
#
#   import "std/tasks" as tasks
#
#   async fn fetch(name, seconds) {
#     await tasks.sleep(seconds)             # other tasks run while this one waits
#     return name + " is ready"
#   }
#
#   async fn main() {
#     let a = tasks.spawn(fetch("a", 0.2))   # start two tasks right now ...
#     let b = tasks.spawn(fetch("b", 0.1))
#     print(await a, "|", await b)           # ... then wait for each result
#     print(await tasks.gather([fetch("c", 0.1), fetch("d", 0.1)]))
#   }
#   tasks.run(main())
#
# Calling an `async fn` doesn't run it: it returns a coroutine. `await` hands that coroutine (or a task,
# a sleep, a gather, a channel operation) to the scheduler, which runs other tasks until it is ready.
# tasks.run(x) starts the scheduler and returns the result of x. Nothing runs in parallel: tasks take
# turns, and switch only at `await`. In safe mode (no real clock to wait on) sleeping advances a
# pretend clock, so programs finish instantly and in the same order.

class Task {
  fn init(co) {
    self.co = co
    self.done = false
    self.failed = false
    self.result = nil
    self.error = nil
    self.waiters = []
    self.observed = false
  }
  fn is_done() => self.done
  # The value the task returned. Throws the task's error if it failed, and complains if it isn't finished.
  fn value() {
    if not self.done { throw "the task is not finished yet" }
    self.observed = true
    if self.failed { throw self.error }
    return self.result
  }
  fn to_str() => "<task " + (self.done and (self.failed and "failed" or "done") or "running") + ">"
}

class Timer { fn init(until) { self.until = until } }
class Gather { fn init(items) { self.items = items } }
class Timeout { fn init(what, seconds) { self.what = what; self.seconds = seconds } }
# Things a task can wait for by polling: poll() gives nil while not ready, or [value] when ready.
# external() says the thing depends on the outside world (a network connection): the scheduler then keeps
# polling instead of reporting a deadlock.
class Pollable {
  fn external() => false
}

class Recv extends Pollable {
  fn init(channel) { self.channel = channel }
  fn poll() {
    let ch = self.channel
    if len(ch.items) > 0 { return [ch.items.remove(0)] }
    if ch.closed { return [nil] }
    return nil
  }
}

class Send extends Pollable {
  fn init(channel, value) { self.channel = channel; self.value = value }
  fn poll() {
    let ch = self.channel
    if ch.closed { throw "can't send on a closed channel" }
    if ch.capacity == 0 or len(ch.items) < ch.capacity {
      ch.items.push(self.value)
      return [nil]
    }
    return nil
  }
}

# A queue that tasks use to hand values to each other. capacity 0 means unlimited.
#   await ch.send(x)       waits while the channel is full
#   let x = await ch.recv()   waits for a value; nil once the channel is closed and empty
class Channel {
  fn init(capacity = 0) {
    self.capacity = capacity
    self.items = []
    self.closed = false
  }
  fn send(value) => Send(self, value)
  fn recv() => Recv(self)
  fn close() { self.closed = true }
  fn len() => len(self.items)
}

let _loop = nil

class Loop {
  fn init(virtual = false) {
    self.ready = []        # [task, value, is_error]
    self.timers = []       # {at, fire}
    self.pollers = []      # {task, wait}
    self.tasks = []
    self.skew = 0          # the pretend clock (safe mode, or run(main, true))
    self.virtual = virtual # true: time exists only on the pretend clock, so runs are exactly repeatable
  }
  fn now() => self.virtual and self.skew or time.now() + self.skew
}

fn _schedule(task, value, is_error = false) { _loop.ready.push([task, value, is_error]) }

fn _finish(task, result) {
  task.done = true
  task.result = result
  let waiters = task.waiters
  task.waiters = []
  for w in waiters { w(task) }
}

fn _fail(task, error) {
  task.done = true
  task.failed = true
  task.error = error
  let waiters = task.waiters
  task.waiters = []
  for w in waiters { w(task) }
}

# Calls `then(task)` when t is finished (right away if it already is).
fn _when_done(t, then) {
  t.observed = true
  if t.done { then(t) } else { t.waiters.push(then) }
}

fn spawn(x) {
  if _loop == nil { throw "tasks.spawn needs a running scheduler: call it inside tasks.run(...)" }
  if isinstance(x, Task) { return x }
  if type(x) == "function" { x = coroutine(x) }
  if type(x) != "coroutine" { throw "tasks.spawn expects a coroutine (the result of calling an async fn), got " + type(x) }
  let task = Task(x)
  _loop.tasks.push(task)
  _schedule(task, nil)
  return task
}

fn sleep(seconds) { return Timer((_loop != nil and _loop.now() or time.now()) + seconds) }
fn gather(items) { return Gather(items) }
fn timeout(what, seconds) { return Timeout(what, seconds) }

fn _as_task(x) {
  if isinstance(x, Task) { return x }
  if type(x) == "coroutine" { return spawn(x) }
  return nil
}

fn _wait_poll(task, aw) {
  let r = aw.poll()
  if r != nil { _schedule(task, r[0]) } else { _loop.pollers.push({task: task, wait: aw}) }
}

# What a task asked for when it suspended (it awaited `req`).
fn _dispatch(task, req) {
  if req == nil {
    _schedule(task, nil)
  } else if isinstance(req, Task) or type(req) == "coroutine" {
    let t = _as_task(req)
    _when_done(t, fn(done) {
      if done.failed { _schedule(task, done.error, true) } else { _schedule(task, done.result) }
    })
  } else if isinstance(req, Timer) {
    _loop.timers.push({at: req.until, fire: fn() { _schedule(task, nil) }})
  } else if isinstance(req, Gather) {
    let n = len(req.items)
    let results = []
    let state = {left: n, failed: false}
    if n == 0 { _schedule(task, results) }
    for i in 0..n {
      results.push(nil)
      let t = _as_task(req.items[i])
      if t == nil {
        _schedule(task, "can't gather " + type(req.items[i]) + " (use async fn calls or tasks)", true)
        state.failed = true
        break
      }
      _when_done(t, fn(done) {
        if state.failed { return }
        if done.failed {
          state.failed = true
          _schedule(task, done.error, true)
          return
        }
        results[i] = done.result
        state.left -= 1
        if state.left == 0 { _schedule(task, results) }
      })
    }
  } else if isinstance(req, Timeout) {
    let finished = {over: false}
    let t = _as_task(req.what)
    if t == nil { _schedule(task, "can't await " + type(req.what) + " with a timeout", true) }
    else {
      _loop.timers.push({at: _loop.now() + req.seconds, fire: fn() {
        if finished.over { return }
        finished.over = true
        _schedule(task, "timed out after " + str(req.seconds) + " seconds", true)
      }})
      _when_done(t, fn(done) {
        if finished.over { return }
        finished.over = true
        if done.failed { _schedule(task, done.error, true) } else { _schedule(task, done.result) }
      })
    }
  } else if isinstance(req, Pollable) {
    _wait_poll(task, req)
  } else {
    _schedule(task, "can't await " + type(req) + ": await an async fn call, a task, tasks.sleep(...), tasks.gather(...) or a channel operation", true)
  }
}

fn _step(task, value, is_error) {
  let req = nil
  try {
    if is_error { req = resume_error(task.co, value) } else { req = resume(task.co, value) }
  } catch e {
    _fail(task, e)
    return
  }
  if status(task.co) == "done" { _finish(task, req) } else { _dispatch(task, req) }
}

fn _has_external() {
  for p in _loop.pollers {
    if p.wait.external() { return true }
  }
  return false
}

fn _wake_timers() {
  let lp = _loop
  let external = _has_external()
  if len(lp.timers) == 0 {
    if external { if time.sleep != nil { time.sleep(0.002) }; return true }
    return false
  }
  let first = 0
  for i in 1..len(lp.timers) {
    if lp.timers[i].at < lp.timers[first].at { first = i }
  }
  let wait = lp.timers[first].at - lp.now()
  if external and wait > 0.002 {
    if time.sleep != nil { time.sleep(0.002) }
    return true
  }
  if wait > 0 {
    if time.sleep != nil and not lp.virtual { time.sleep(wait) } else { lp.skew += wait }
  }
  let now = lp.now()
  let due = []
  let rest = []
  for t in lp.timers { if t.at <= now { due.push(t) } else { rest.push(t) } }
  due.sort(fn(a, b) => a.at - b.at)
  lp.timers = rest
  for t in due { t.fire() }
  return true
}

fn _poll_all() {
  let lp = _loop
  let waiting = lp.pollers
  lp.pollers = []
  let progressed = false
  for p in waiting {
    let r = p.wait.poll()
    if r != nil { _schedule(p.task, r[0]); progressed = true } else { lp.pollers.push(p) }
  }
  return progressed
}

# Starts the scheduler, runs `main` (a coroutine from an async fn call, or a function) to the end and returns its result.
# Throws the error if it failed, or if a task that nobody awaited failed.
# run(main, true) uses a pretend clock only: sleeping takes no time and tasks always finish in the same order.
fn run(main, virtual = false) {
  let previous = _loop
  let lp = Loop(virtual)
  _loop = lp
  let main_task = nil
  let problem = nil
  try {
    main_task = spawn(main)
    while not main_task.done {
      if len(lp.ready) > 0 {
        let batch = lp.ready
        lp.ready = []
        for item in batch { _step(item[0], item[1], item[2]) }
      } else if _poll_all() {
        # something became ready
      } else if _wake_timers() {
        # a timer fired
      } else {
        throw "deadlock: every task is waiting for something that can never happen"
      }
    }
  } catch e {
    problem = {error: e}
  }
  _loop = previous
  if problem != nil { throw problem.error }
  if main_task.failed { throw main_task.error }
  for t in lp.tasks {
    if t.failed and not t.observed { throw t.error }
  }
  return main_task.result
}
