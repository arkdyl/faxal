export interface Lesson { id: string; title: string; text: string[]; code: string; task: string }

/** The guided tour. `text` paragraphs may use <code>. Every `code` runs in the playground's safe mode. */
export const LESSONS: Lesson[] = [
  {
    id: "hello", title: "Hello, world",
    text: [
      "A Faxal program is a list of instructions, one per line. <code>print</code> shows things on the screen. Text goes in quotes.",
      "There are no semicolons and no boilerplate: this is the whole program.",
    ],
    code: `print("Hello, world!")\nprint("Faxal can add:", 2 + 3)`,
    task: "Change the message, then press Run. Print your name.",
  },
  {
    id: "values", title: "Values and variables",
    text: [
      "<code>let</code> gives a value a name. Numbers, text (strings), <code>true</code>/<code>false</code> and <code>nil</code> (nothing) are the basic values.",
      "Put an <code>f</code> before a quote to drop values into text with <code>{ }</code>. <code>+=</code> changes a variable.",
    ],
    code: `let name = "Ada"\nlet age = 36\nprint(f"{name} is {age} years old")\nage += 1\nprint(f"next year: {age}")\nprint("shout".upper(), "shout".len())`,
    task: "Make a variable for your favourite number and print its square (<code>n * n</code>).",
  },
  {
    id: "decisions", title: "Making decisions",
    text: [
      "<code>if</code> runs code only when something is true. Join conditions with <code>and</code>, <code>or</code>, <code>not</code>. Only <code>nil</code> and <code>false</code> count as false.",
    ],
    code: `let score = 72\nif score >= 90 {\n  print("excellent")\n} else if score >= 50 and score < 90 {\n  print("good")\n} else {\n  print("keep going")\n}\nlet nickname = nil\nprint(nickname ?? "no nickname")`,
    task: "Change <code>score</code> to see each message. What does <code>??</code> do?",
  },
  {
    id: "loops", title: "Loops",
    text: [
      "<code>for</code> repeats code for every item of a list, string or range. <code>0..5</code> is the numbers 0 to 4, and <code>by</code> sets the step. <code>while</code> repeats as long as a condition holds.",
    ],
    code: `for i in 0..5 { write(i, " ") }\nprint()\nfor i in 10..0 by -3 { write(i, " ") }\nprint()\nlet n = 1\nwhile n < 100 { n *= 2 }\nprint("first power of two over 100:", n)`,
    task: "Print the 5 times table with a loop.",
  },
  {
    id: "lists", title: "Lists",
    text: [
      "A list holds many values in order. Lists have handy methods: <code>push</code>, <code>map</code>, <code>filter</code>, <code>sum</code>, <code>sorted</code>... Negative indexes count from the end and <code>[a:b]</code> slices.",
    ],
    code: `let nums = [5, 3, 8, 1]\nnums.push(10)\nprint(nums.sorted(), nums.sum(), nums.max())\nprint(nums.map(fn(x) => x * 2))\nprint(nums.filter(fn(x) => x > 4))\nprint(nums[0], nums[-1], nums[1:3])`,
    task: "Keep only the odd numbers (<code>x % 2 == 1</code>), then add them up.",
  },
  {
    id: "maps", title: "Maps",
    text: [
      "A map pairs keys with values, and remembers the order you added them. <code>m.name</code> is the same as <code>m[\"name\"]</code>. A missing key gives <code>nil</code>.",
    ],
    code: `let person = {name: "Ada", langs: ["Faxal"]}\nperson.age = 36\nprint(person.name, person.age, person.missing)\nfor key in person { print(key, "->", person[key]) }\nlet counts = {}\nfor w in "a b a c a b".split(" ") { counts[w] = counts.get(w, 0) + 1 }\nprint(counts)`,
    task: "Count the letters of a word instead of the words of a sentence (<code>\"hello\".chars()</code>).",
  },
  {
    id: "functions", title: "Functions",
    text: [
      "<code>fn</code> names a piece of code you can reuse. Parameters can have defaults. A short function can be written with an arrow: <code>fn(x) => x * 2</code>. Functions are values, and they remember the variables around them (closures). Arguments can be passed by name: <code>greet(\"Cy\", greeting = \"Hi\")</code>.",
    ],
    code: `fn greet(name, greeting = "Hello") {\n  return f"{greeting}, {name}!"\n}\nprint(greet("Ada"), greet("Bo", "Hi"), greet("Cy", greeting = "Hey"))\n\nfn counter() {\n  let n = 0\n  return fn() { n += 1; return n }\n}\nlet next = counter()\nnext(); next()\nprint(next())\n\nprint([1, 2, 3] |> fn(l) => l.map(fn(x) => x * x))`,
    task: "Write <code>fn area(w, h = w)</code> that returns the area of a rectangle (a square if you give one number).",
  },
  {
    id: "classes", title: "Classes",
    text: [
      "A class bundles data and the functions that use it. <code>init</code> sets up a new object, <code>self</code> is the object, <code>extends</code> builds on another class, and <code>to_str</code> says how an object prints.",
    ],
    code: `class Animal {\n  fn init(name) { self.name = name }\n  fn speak() => self.name + " makes a sound"\n  fn to_str() => "<" + self.name + ">"\n}\nclass Dog extends Animal {\n  fn speak() => self.name + " says woof"\n}\nlet pets = [Animal("Cat"), Dog("Rex")]\nfor p in pets { print(p, "-", p.speak()) }\nprint(isinstance(pets[1], Animal))`,
    task: "Add a <code>Bird</code> class that extends <code>Animal</code> and says tweet.",
  },
  {
    id: "errors", title: "When things go wrong",
    text: [
      "Errors stop a program, with a message that points at the line. <code>try</code> and <code>catch</code> let you deal with them, and <code>throw</code> raises your own. Faxal's messages suggest fixes when they can.",
    ],
    code: `fn divide(a, b) {\n  if b == 0 { throw "can't divide by zero" }\n  return a / b\n}\ntry {\n  print(divide(10, 2))\n  print(divide(1, 0))\n} catch e {\n  print("caught:", e)\n}\ntry { prnt("typo") } catch e { print(e) }`,
    task: "Make <code>divide</code> throw a different message, and print it.",
  },
  {
    id: "draw", title: "Drawing",
    text: [
      "Drawing is built in. A turtle holds a pen: <code>forward</code> moves it, <code>turn</code> rotates it, <code>color</code> sets the colour. Shapes: <code>circle</code>, <code>disc</code>, <code>rect</code>, <code>box</code>, <code>text</code>. Loops turn a few lines into art.",
    ],
    code: `background("#000")\nlet i = 0\nwhile i < 72 {\n  color(90 + i * 2, 90 + i, 255 - i * 2)\n  forward(10 + i * 2.5)\n  turn(89)\n  i += 1\n}`,
    task: "Change <code>turn(89)</code> to <code>turn(61)</code> or <code>turn(121)</code>. What changes?",
  },
  {
    id: "types", title: "Optional types",
    text: [
      "Parameters, return values and variables can say what type they expect: <code>num</code> <code>str</code> <code>bool</code> <code>list</code> <code>map</code> <code>fn</code> <code>any</code>, or a class name. <code>num or nil</code> allows more than one. Wrong values stop the program with a clear message. Types are optional: untyped code works as before.",
    ],
    code: `fn area(w: num, h: num = 1) -> num {\n  return w * h\n}\nprint(area(3, 4))\ntry {\n  print(area("3"))\n} catch e {\n  print(e)\n}\nlet name: str = "Ada"\nprint(name)`,
    task: "Add a type to a function of your own, then call it with the wrong kind of value.",
  },
  {
    id: "generators", title: "Coroutines and generators",
    text: [
      "A coroutine is a function that can pause with <code>yield</code> and be continued later with <code>resume</code>, keeping all its variables. A <code>for</code> loop can walk a coroutine, so endless sequences are easy.",
    ],
    code: `fn naturals() {\n  let n = 1\n  while true { yield(n); n += 1 }\n}\nfor n in coroutine(naturals) {\n  if n > 5 { break }\n  write(n, " ")\n}\nprint()\n\nlet chat = coroutine(fn(first) {\n  let reply = yield("got " + first)\n  return "then " + reply\n})\nprint(resume(chat, "hello"))\nprint(resume(chat, "world"))`,
    task: "Write a generator that yields the squares of 1, 2, 3, ... and print the first 6.",
  },
  {
    id: "async", title: "async and await",
    text: [
      "<code>async fn</code> makes a function that can wait without blocking the others. <code>await</code> pauses until something is ready, and meanwhile other tasks run. The scheduler is in <code>std/tasks</code>. Here the playground uses a pretend clock, so even long sleeps finish instantly.",
    ],
    code: `import "std/tasks" as tasks\n\nasync fn fetch(name, seconds) {\n  await tasks.sleep(seconds)\n  print(name, "is ready")\n  return name.upper()\n}\n\nasync fn main() {\n  let results = await tasks.gather([\n    fetch("slow", 3),\n    fetch("fast", 1),\n    fetch("middle", 2),\n  ])\n  print(results)\n}\ntasks.run(main())`,
    task: "Add a fourth task that sleeps for 0.5 seconds. In what order do they finish?",
  },
  {
    id: "web", title: "Web servers",
    text: [
      "<code>std/http</code> is an HTTP client and server written in Faxal. A <code>Router</code> maps paths like <code>/notes/:id</code> to functions that take a request and give back a response: text, HTML, or a map or list (sent as JSON).",
      "This page can't open network connections, so here the router is called directly with made-up requests. On your own computer, <code>http.serve(8080, app)</code> serves the very same router to browsers. The repository's <code>apps/notes</code> is a whole web app built this way.",
    ],
    code: `import "std/http" as http\n\nlet notes = {1: "Buy milk", 2: "Learn Faxal"}\n\nlet app = http.Router()\napp.get("/hello", fn(req) => http.text("Hello, " + (req.query.name ?? "you") + "!"))\napp.get("/notes/:id", fn(req) {\n  let note = notes.get(int(req.params.id))\n  if note == nil { return http.send_json({error: "no such note"}, 404) }\n  return http.send_json({id: req.params.id, text: note})\n})\n\nfn ask(method, target) {\n  let res = app.handle(http.Request(method, target, {}, ""))\n  print(method, target, "->", res.status, res.body)\n}\nask("GET", "/hello?name=Ada")\nask("GET", "/notes/2")\nask("GET", "/notes/9")\nask("DELETE", "/hello")\nask("GET", "/nowhere")`,
    task: "Add a route <code>/add?a=2&b=3</code> that answers with the sum (remember <code>int(...)</code>).",
  },
  {
    id: "library", title: "The standard library",
    text: [
      "Faxal comes with modules you load with <code>import</code>: collections, text, numbers, colours, regular expressions, dates, paths, CSV, random numbers. They are written in Faxal, and you can read them. The reference page lists everything.",
    ],
    code: `import "std/regex" as re\nimport "std/datetime" as dt\nimport "std/text" as tx\n\nprint(re.find("\\\\d+", "room 42, floor 7").text)\nprint(re.replace("(\\\\w+)@(\\\\w+)", "ada@home", "$2:$1"))\nlet d = dt.make(2026, 10, 3)\nprint(d.format("%A, %d %B %Y"), "->", d.add_days(30).format("%d %b"))\nprint(tx.title("the quick brown fox"), tx.commas(1234567))`,
    task: "Use <code>re.find_all</code> to pull every number out of a sentence.",
  },
];
