# title: async and await
import "std/tasks" as tasks

async fn fetch(name, seconds) {
  print("start", name)
  await tasks.sleep(seconds)
  print("done ", name)
  return name.upper()
}

async fn main() {
  # three tasks at the same time: they finish in the order of their sleeps
  let results = await tasks.gather([fetch("slow", 3), fetch("fast", 1), fetch("middle", 2)])
  print(results)

  # a channel hands values from one task to another
  let ch = tasks.Channel()
  tasks.spawn(async fn() {
    for i in 1..4 {
      await ch.send(i * i)
      await tasks.sleep(0.5)
    }
    ch.close()
  }())
  while true {
    let v = await ch.recv()
    if v == nil { break }
    print("received", v)
  }

  try {
    await tasks.timeout(fetch("very slow", 60), 2)
  } catch e {
    print("gave up:", e)
  }
}
tasks.run(main())
