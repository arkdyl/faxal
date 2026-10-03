import "std/test" as t
import "std/tasks" as tasks

async fn work(log, name, seconds, result = nil) {
  log.push("start " + name)
  await tasks.sleep(seconds)
  log.push("end " + name)
  return result ?? name
}

t.test("run returns the result of the main task", fn() {
  async fn main() { return 42 }
  t.eq(tasks.run(main()), 42)
  t.eq(tasks.run(fn() => 7), 7)
})

t.test("await runs another async function to its result", fn() {
  async fn add(a, b) { await tasks.sleep(0.001); return a + b }
  async fn main() { return (await add(1, 2)) + (await add(10, 20)) }
  t.eq(tasks.run(main()), 33)
})

t.test("spawned tasks run at the same time", fn() {
  let log = []
  async fn main() {
    let slow = tasks.spawn(work(log, "slow", 0.04))
    let fast = tasks.spawn(work(log, "fast", 0.01))
    let a = await slow
    let b = await fast
    return [a, b]
  }
  t.eq(tasks.run(main(), true), ["slow", "fast"])
  t.eq(log, ["start slow", "start fast", "end fast", "end slow"])
})

t.test("gather collects results in order", fn() {
  let log = []
  async fn main() { return await tasks.gather([work(log, "a", 0.03), work(log, "b", 0.01), work(log, "c", 0.02)]) }
  t.eq(tasks.run(main(), true), ["a", "b", "c"])
  t.eq(log.slice(3), ["end b", "end c", "end a"])
  async fn empty() { return await tasks.gather([]) }
  t.eq(tasks.run(empty()), [])
})

t.test("errors travel to whoever awaits", fn() {
  async fn boom() { await tasks.sleep(0.001); throw "kaput" }
  async fn main() {
    try { await boom() } catch e { return "caught " + e }
  }
  t.eq(tasks.run(main()), "caught kaput")
  t.throws(fn() { tasks.run(boom()) }, "kaput")
  async fn g() { return await tasks.gather([work([], "x", 0.001), boom()]) }
  t.throws(fn() { tasks.run(g()) }, "kaput")
})

t.test("an error nobody awaited is reported", fn() {
  async fn boom() { throw "lost" }
  async fn main() { tasks.spawn(boom()); await tasks.sleep(0.001); return 1 }
  t.throws(fn() { tasks.run(main()) }, "lost")
})

t.test("timeout", fn() {
  let log = []
  async fn main() {
    try { await tasks.timeout(work(log, "slow", 10), 0.01) } catch e { return e }
  }
  t.eq(tasks.run(main()), "timed out after 0.01 seconds")
  async fn quick() { return await tasks.timeout(work([], "q", 0.001), 5) }
  t.eq(tasks.run(quick()), "q")
})

t.test("channels hand values between tasks", fn() {
  async fn main() {
    let ch = tasks.Channel()
    async fn producer() {
      for i in 0..4 { await ch.send(i); await tasks.sleep(0.001) }
      ch.close()
    }
    tasks.spawn(producer())
    let got = []
    while true {
      let v = await ch.recv()
      if v == nil { break }
      got.push(v)
    }
    return got
  }
  t.eq(tasks.run(main()), [0, 1, 2, 3])
})

t.test("a bounded channel makes the sender wait", fn() {
  async fn main() {
    let ch = tasks.Channel(1)
    let order = []
    async fn sender() { for i in 0..3 { await ch.send(i); order.push("sent " + str(i)) } ch.close() }
    tasks.spawn(sender())
    while true {
      let v = await ch.recv()
      if v == nil { break }
      order.push("got " + str(v))
    }
    return order
  }
  let order = tasks.run(main())
  t.eq(order.len(), 6)
  t.eq(order.filter(fn(s) => s.starts_with("got")), ["got 0", "got 1", "got 2"])
})

t.test("deadlocks and bad awaits are reported", fn() {
  async fn stuck() { await tasks.Channel().recv() }
  t.throws(fn() { tasks.run(stuck()) }, "deadlock")
  async fn bad() { await 5 }
  t.throws(fn() { tasks.run(bad()) }, "can't await number")
  t.throws(fn() { tasks.spawn(bad()) }, "scheduler")
})

t.test("tasks yielding nil take turns", fn() {
  let order = []
  async fn worker(name) { for i in 0..2 { order.push(name + str(i)); await nil } }
  async fn main() { await tasks.gather([worker("a"), worker("b")]) }
  tasks.run(main())
  t.eq(order, ["a0", "b0", "a1", "b1"])
})

t.run()
