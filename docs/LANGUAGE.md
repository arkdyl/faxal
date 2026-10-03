## Getting started

Faxal is a small, dynamically typed language. Programs are plain text files ending in `.fx`, run by the native `faxal` interpreter: a compiler to bytecode plus a fast virtual machine with a garbage collector. It needs nothing else installed.

```bash
./install.sh            # Linux, macOS, BSD: builds faxal and installs it (needs only a C compiler)
.\install.ps1           # Windows (PowerShell, with MinGW-w64 gcc or clang)
```

There is nothing else to set up. To build by hand, the whole runtime is one C file, so this is the entire build on any system:

```bash
cc -O2 -o faxal native/dist/faxal.c -lm     # Windows with MinGW: gcc -O2 -o faxal.exe native/dist/faxal.c
./faxal --version
```

(Developers can also run `make -C native`, which builds `bin/faxal` from the separate source files.)

```bash
faxal hello.fx            # run a program
faxal repl                # interactive shell
faxal -e 'print(6 * 7)'   # run a snippet
faxal check hello.fx      # find syntax errors without running
faxal --dump hello.fx     # show the compiled bytecode
faxal --svg out.svg art.fx  # save the turtle drawing as an SVG
```

Exit codes: `0` success, `65` syntax error, `70` uncaught runtime error, `74` file not found.

## The basics

A statement ends at the end of the line. Use `;` to put several on one line. Comments start with `#`.

```fx
let name = "Faxal"       # declare a variable
let count = 3
count += 1               # also -= *= /= %=
print(f"{name} has {count} apples")
```

A line also continues when it ends with an operator, a comma, or an open bracket, or when the next line starts with `.`, `and`, `or` or `else`:

```fx
let total = 1 +
  2
let names = people
  .filter(fn(p) { return p.age > 18 })
  .map(fn(p) { return p.name })
```

### Values

| Type | Examples |
| --- | --- |
| number | `42`, `3.14`, `1_000_000`, `0xff`, `1e-3` (always 64-bit floats) |
| string | `"hi"`, `'hi'` (UTF-8, immutable) |
| bool | `true`, `false` |
| nil | `nil` (no value) |
| list | `[1, "two", [3]]` |
| map | `{name: "Ada", "age": 36}` |
| range | `0..10` (0 up to, not including, 10) |
| function | `fn(x) { return x + 1 }` |

Only `nil` and `false` are false. `0`, `""` and `[]` are true. Use `type(x)` to see what something is.

## Strings

Strings use single or double quotes and can span several lines. Escapes: `\n` `\t` `\r` `\\` `\"` `\'` `\e`.

An **f-string** (put an `f` before the quote) evaluates anything inside `{ }`. Use `\{` for a literal brace. Plain strings never treat `{` specially, so they are safe for JSON and code.

```fx
let n = 3
print(f"{n} squared is {n * n}")        # 3 squared is 9
print(f"shout: {"hi".upper()}!")         # shout: HI!
print("no {interpolation} here")         # no {interpolation} here
```

Adding anything to a string turns it into text, and multiplying repeats it:

```fx
print("n = " + 5)       # n = 5
print("ab" * 3)         # ababab
```

Indexing and slicing work on bytes: `s[0]`, `s[-1]`, `s[2:5]`, `s[:3]`, `s[3:]`. Looping with `for` goes character by character. Methods:

| Method | Result |
| --- | --- |
| `s.len()` | length in bytes |
| `s.upper()` `s.lower()` `s.trim()` | new string |
| `s.contains(t)` `s.starts_with(t)` `s.ends_with(t)` | bool |
| `s.find(t)` `s.find(t, from)` | index, or `-1` |
| `s.count(t)` | how many times `t` appears |
| `s.replace(a, b)` | replace every `a` with `b` |
| `s.split(sep)` | list of pieces (`s.split("")` gives characters) |
| `s.chars()` `s.lines()` | list of characters / lines |
| `s.repeat(n)` `s.reverse()` | new string |
| `s.pad_left(width, fill)` `s.pad_right(width, fill)` `s.center(width, fill)` | pad to a width (`fill` is one character, default a space) |
| `s.lstrip()` `s.rstrip()` `s.capitalize()` | new string |
| `s.is_digit()` `s.is_alpha()` `s.is_empty()` | bool |
| `s.size()` | length in characters (`len` counts bytes) |

## Operators

From tightest to loosest: `**` (right to left), unary `-`, `* / %`, `+ -`, `..` (range), `< <= > >= in`, `== !=`, `not`, `and`, `or`. `%` takes the sign of the right side (`-7 % 3` is `2`). `and`/`or` return one of their operands, so `name or "anonymous"` works. `x in y` checks substrings, list items, map keys and ranges.

### Pipes, defaults and safe access

`x |> f` means `f(x)`, and `x |> f(a)` means `f(x, a)`: the value on the left goes in as the first argument. Pipes read like a recipe and can continue on the next line:

```fx
fn double(x) { return x * 2 }
fn add(x, amount = 1) { return x + amount }

print(5 |> double |> add(10))            # 20
let shout = ["pipe", "lines"]
  |> fn(ws) { return ws.map(fn(w) { return w.upper() }) }
  |> fn(ws) { return ws.join(" ") }
print(shout)                             # PIPE LINES
```

`a ?? b` gives `b` only when `a` is `nil`, so `0 ?? 5` is `0` and `false ?? 5` is `false`. `a?.name` and `a?.method()` give `nil` instead of an error when `a` is `nil`; each `?.` guards one step, so write `a?.b?.c`.

```fx
let settings = {theme: nil, user: {name: "Ada"}}
print(settings.theme ?? "light")                  # light
print(settings?.user?.name, settings.guest?.name) # Ada nil
```

`0..10 by 2` is a range with a step (`0 2 4 6 8`), and `10..0 by -3` counts down.

## Control flow

Conditions don't need parentheses, but braces are always required.

```fx
if score > 90 {
  print("great")
} else if score > 50 {
  print("ok")
} else {
  print("keep going")
}

while n > 0 { n -= 1 }

for i in 0..5 { print(i) }              # 0 1 2 3 4
for item in ["a", "b"] { print(item) }
for ch in "héy" { print(ch) }
for key in {a: 1, b: 2} { print(key) }  # keys, in insertion order
for x in range(10, 0, -3) { print(x) }  # 10 7 4 1
```

`break` leaves a loop and `continue` skips to the next round.

## Functions

```fx
fn add(a, b) { return a + b }
let double = fn(x) { return x * 2 }     # an anonymous function is a value
print(add(2, 3), double(4))
```

Short functions can use an arrow: `fn(x) => expression` is the same as `fn(x) { return expression }`. It works for named functions and methods too.

```fx
let nums = [3, 1, 2]
print(nums.map(fn(x) => x * 10))                  # [30, 10, 20]
print(nums.sorted(fn(a, b) => b - a))             # [3, 2, 1]
fn area(w, h = w) => w * h
print(area(3), area(3, 4))                        # 9 12
```

Functions are values: pass them, return them, store them in lists and maps. They remember the variables around them (closures), and every loop round gets its own copy of the loop variable:

```fx
fn make_counter() {
  let n = 0
  return fn() { n += 1; return n }
}
let next = make_counter()
next(); next()
print(next())           # 3
```

Parameters can have **default values**. They are used when the argument is left out (or is `nil`), may use earlier parameters, and must come last:

```fx
fn pad(text, width, fill = " ") { return text + fill * (width - len(text)) }
print(pad("ab", 5, "."))      # ab...
print("[" + pad("ab", 4) + "]")   # [ab  ]
```

### Types (optional)

Parameters, return values and variables can say what type they expect. Nothing is required: untyped code works as before. When a type is given, it is **checked every time the code runs**, and a wrong value stops the program with a clear message:

```fx
fn area(w: num, h: num = 1) -> num { return w * h }
let name: str = "Ada"
print(area(3, 4))                                  # 12
try { area("3") } catch e { print(e) }             # Type error: parameter 'w' of area() must be num, got string "3"
fn find(xs: list, x: any) -> num or nil {          # "or" allows more than one type
  let i = xs.index_of(x)
  if i < 0 { return nil }
  return i
}
```

Types: `num` `int` `str` `bool` `nil` `list` `map` `range` `fn` `any`, or the name of a class (instances of subclasses also fit). Write `num or nil` for "a number, or nothing". A function with a return type must return a fitting value: forgetting to return anything is an error unless `nil` is allowed. A variable's type is checked when it is declared, not on later assignments.

A function without `return` gives `nil`. Calling with the wrong number of arguments is an error. Recursion depth is limited to about 1,500 calls.

## Lists

```fx
let xs = [10, 20, 30]
xs[0] = 99
xs[-1] += 1              # negative indexes count from the end
print(xs[1:], xs[:2])    # slices make new lists
```

| Method | What it does |
| --- | --- |
| `len()` | number of items |
| `push(x)` `pop()` | add to / remove from the end |
| `insert(i, x)` `remove(i)` | add / remove at an index (`remove` returns the item) |
| `contains(x)` `index_of(x)` | search (`-1` if missing) |
| `join(sep)` | glue the items into a string |
| `sort()` `sort(cmp)` | sort in place; `cmp(a, b)` returns a negative, zero or positive number |
| `reverse()` `clear()` | change in place |
| `slice(a, b)` `copy()` | new lists |
| `map(f)` `filter(f)` | new lists |
| `reduce(start, f)` | fold the list into one value: `f(total, item)` |
| `each(f)` | call `f` on every item |
| `first()` `last()` | the first / last item (`nil` if the list is empty) |
| `sum()` `min()` `max()` | add up / find the smallest / largest |
| `any(f)` `all(f)` | is `f(item)` true for some / every item? (`f` is optional: items are tested themselves) |
| `find(f)` `count(f)` | the first item where `f` is true (or `nil`) / how many; `count(x)` also counts a value |
| `extend(other)` | add all the items of another list to the end |
| `unique()` `flatten()` | new lists: without repeats / with inner lists opened up one level |
| `sorted()` `sorted(cmp)` `reversed()` | new lists (the original is unchanged) |
| `is_empty()` | no items? |

The most useful ones also exist as plain functions, so they read naturally: `sum(xs)`, `sorted(xs)`, `reversed(xs)`, `any(xs, f)`, `all(xs, f)`, `zip(a, b)` (pairs) and `enumerate(xs)` (`[index, item]` pairs), plus `bool(x)`.

`+` joins two lists. `==` compares lists by value.

## Maps

A map holds key/value pairs and remembers the order they were added. Keys can be strings, numbers or booleans. `m.name` is the same as `m["name"]`. A missing key gives `nil`.

```fx
let person = {name: "Ada", langs: ["Faxal"]}
person.age = 36
person["city"] = "London"
print(person.name, person.missing)       # Ada nil
print(person.keys())                     # ["name", "langs", "age", "city"]

let counts = {}
for w in "a b a".split(" ") { counts[w] = counts.get(w, 0) + 1 }
print(counts)                            # {a: 2, b: 1}
```

| Method | What it does |
| --- | --- |
| `len()` `keys()` `values()` | size, lists of keys / values |
| `items()` | list of `[key, value]` pairs |
| `has(k)` `get(k, default)` | look up safely |
| `remove(k)` | delete and return the old value |
| `clear()` `copy()` | empty it / make a copy |
| `merge(other)` | copy all the entries of another map into this one |
| `is_empty()` | no entries? |

A key with the same name as a method hides it: after `m["has"] = 1`, `m.has(x)` is no longer the method. If a map can have arbitrary keys, use `m[key]` to read and write them.

Storing functions in a map gives you objects: `{count: 0, inc: fn() { obj.count += 1 }}`.

## Classes

A class bundles data and the functions that work on it. Call the class like a function to make an **instance**. The special method `init` runs first and sets things up; inside a method, `self` is the instance.

```fx
class Account {
  fn init(owner, balance) {
    self.owner = owner
    self.balance = balance
  }

  fn deposit(amount) {
    if amount <= 0 { throw "deposit must be positive" }
    self.balance += amount
    return self                       # returning self lets calls chain
  }

  fn describe() {
    return f"{self.owner} has {self.balance}"
  }
}

let acc = Account("Ada", 100)
acc.deposit(50).deposit(25)
print(acc.describe())                 # Ada has 175
print(acc.balance)                    # fields are public: 175
```

Fields can be added any time (`acc.nickname = "A"`), and a field holding a function shadows a method of the same name. A method taken without calling it remembers its instance: `let d = acc.deposit` then `d(10)` still deposits into `acc`. Methods can create closures that capture `self`.

### Inheritance

`extends` makes a class that starts with everything its parent has. A child can override methods, and `super` reaches the parent's version.

```fx
class Animal {
  fn init(name) { self.name = name }
  fn speak() { return "..." }
  fn intro() { return f"{self.name} says {self.speak()}" }
}

class Dog extends Animal {
  fn init(name) {
    super.init(name)                  # run the parent's init
    self.tricks = []
  }
  fn speak() { return "woof" }
}

class Puppy extends Dog {
  fn speak() { return super.speak() + " (squeaky)" }
}

print(Dog("Rex").intro())             # Rex says woof
print(Puppy("Bit").intro())           # Bit says woof (squeaky)
print(isinstance(Puppy("x"), Animal)) # true
```

`isinstance(value, Class)` is true for instances of that class or any class that extends it. `type(x)` gives `"instance"` for instances and `"class"` for classes. `json.encode(instance)` encodes its fields. Instances are compared by identity (`==` is only true for the same object). Since anything can be thrown, instances make good custom errors: `throw MyError("bad")`.

### Controlling how an object prints

By default an instance prints as `<Dog instance>`. Give the class a `to_str` method that returns a string and Faxal uses it everywhere text is needed: `print`, `str()`, `repr()`, f-strings, `+` with a string, `join`, and when the object sits inside a list or map. Uncaught errors use it too, so a custom error class gives a readable crash message.

```fx
class Point {
  fn init(x, y) { self.x = x; self.y = y }
  fn to_str() { return f"({self.x}, {self.y})" }
}

let p = Point(1, 2)
print(p)                          # (1, 2)
print("at " + p)                  # at (1, 2)
print([p, Point(3, 4)])           # [(1, 2), (3, 4)]
```

`to_str` is inherited, and a child can override it (or call `super.to_str()`). It must return a string, otherwise printing is an error. If `to_str` throws, the error propagates to whatever was printing.

A few rules: `self` and `super` only exist inside classes, `super` needs `extends`, a class can't extend itself, and `init` can't `return` a value (it always gives back the new instance). A parent's methods are copied into the child when the class is created.

## Errors

Anything can be thrown. Runtime problems (dividing by zero, a bad index, a missing variable) throw a text message you can catch.

```fx
fn divide(a, b) {
  if b == 0 { throw "can't divide by zero" }
  return a / b
}

try {
  print(divide(1, 0))
} catch err {
  print("oops:", err)
}
```

An uncaught error prints a message and a stack trace to stderr, and the program exits with code `70`:

```text
error: can't divide by zero
  at divide (/home/you/demo.fx:2)
  at <script> (/home/you/demo.fx:7)
```

Many errors suggest a fix when you mistype a name:

```text
error: Undefined variable 'prnt'. Did you mean 'print'?
error: string has no method 'uper'. Did you mean 'upper'?
```

`return`, `break` and `continue` all work inside `try`.

## Coroutines and async

A **coroutine** is a function that can pause in the middle and be continued later, keeping all its variables. `yield(x)` pauses it and hands `x` to whoever started it; `resume(co)` continues it.

```fx
let countdown = coroutine(fn() {
  for i in 3..0 by -1 { yield(i) }
  return "liftoff"
})
print(resume(countdown), resume(countdown), resume(countdown))   # 3 2 1
print(resume(countdown), countdown.status())                      # liftoff done
```

`resume(co, value)` sends a value back in: it becomes the result of the `yield` the coroutine was paused at (the first `resume` passes it to the function as its argument). A `for` loop can walk a coroutine, which makes generators easy, even endless ones:

```fx
fn naturals() {
  let n = 1
  while true { yield(n); n += 1 }
}
for n in coroutine(naturals) {
  if n > 5 { break }
  write(n, " ")                                  # 1 2 3 4 5
}
print()
print(coroutine(fn() { yield("a"); yield("b") }).to_list())    # ["a", "b"]
```

| | |
| --- | --- |
| `coroutine(f)` | a new coroutine that will run `f` (nothing happens until the first `resume`) |
| `resume(co)` `resume(co, x)` | run until the next `yield` (gives its value) or until `f` returns (gives the result) |
| `yield(x)` `yield()` | pause the running coroutine |
| `resume_error(co, e)` | throw `e` inside a paused coroutine, at its `yield` |
| `co.status()` | `"new"` `"suspended"` `"running"` `"done"` or `"failed"` |
| `co.is_done()` `co.to_list()` | finished? / run to the end and collect every yielded value |

An error inside a coroutine comes out of the `resume` that was running it. You can only `yield` from the coroutine's own code, not from inside a callback that a built-in calls (`map`, `sort`, `to_str`). A coroutine has a stack of its own that holds about 250 nested calls.

### async and await

`async fn` makes a function that returns a coroutine instead of running. `await` pauses the current async function until something is ready, and meanwhile other tasks run. The scheduler lives in `std/tasks`:

```fx
import "std/tasks" as tasks

async fn fetch(name, seconds) {
  await tasks.sleep(seconds)            # other tasks run while this one waits
  return name + " is ready"
}

async fn main() {
  let a = tasks.spawn(fetch("a", 0.2))  # start two tasks right now ...
  let b = tasks.spawn(fetch("b", 0.1))
  print(await a, "|", await b)          # ... and wait for each result
  print(await tasks.gather([fetch("c", 0.1), fetch("d", 0.1)]))
  print(await fetch("e", 0.05))         # awaiting a call runs it and gives its result
}
tasks.run(main())                       # starts the scheduler and runs main to the end
```

Tasks never run at the same moment: they take turns, and switch only at an `await`, so there are no data races. What you can wait for:

| `await ...` | gives |
| --- | --- |
| `fetch(...)` (a call of an `async fn`) | its result; an error inside is thrown here |
| `tasks.spawn(call)` (a task) | the task's result |
| `tasks.sleep(seconds)` | `nil`, after the time has passed |
| `tasks.gather([a, b, c])` | the list of results, in order (the first error is thrown) |
| `tasks.timeout(x, seconds)` | the result of `x`, or throws `"timed out after ..."` |
| `channel.recv()` `channel.send(x)` | a value from / into a `tasks.Channel(capacity)` (`nil` from `recv` once it is closed and empty) |
| `nil` | nothing: just lets the other tasks take a turn |

`async fn` also works for methods (`async fn get() { ... }` inside a class) and as an expression (`async fn(x) => await other(x)`). `await` only works inside an async function (or a coroutine). `tasks.run` stops with an error if every task is waiting for something that can never happen ("deadlock"), and reports an error from a task that nobody awaited. In safe mode there is no real clock to wait on, so `sleep` moves a pretend clock forward: programs finish immediately and in the same order. `async` and `await` are reserved words, so they can't be names of variables or modules.

## Modules

`import` runs another file once and gives you its public names as a map. Paths are relative to the importing file, and `.fx` can be left off. Names that start with `_` stay private.

```fx
# shapes.fx
let PI = 3.14159
fn _square(x) { return x * x }          # private
fn area(r) { return PI * _square(r) }
```

```fx
import "shapes.fx" as shapes
import "shapes"                         # same file; the name defaults to "shapes"
print(shapes.area(2))
```

`load("path")` is `import` as a function, for paths that are worked out while the program runs.

### Standard modules

Names that start with `std/` are modules that are built into Faxal itself, so they work anywhere (even in safe mode):

```fx
import "std/collections" as col
let q = col.Queue()
q.push("a").push("b")
print(q.pop(), q)                       # a Queue["b"]
```

They are written in Faxal. The sources are in `native/lib/std/` and are good examples to learn from. See the table in the next section.

### Packages

A project can use code from other places. `faxal add <source>` copies a package into the project's `fx_modules/` folder and records it in `faxal.json`; then `import "name"` finds it, from any file in the project. See "Project tools" below.

## Standard library

Built into every program:

| Namespace | Contents |
| --- | --- |
| `math` | `pi e inf nan` · `sqrt pow exp log log2 log10` · `sin cos tan asin acos atan atan2` (radians) · `floor ceil round trunc abs sign min max clamp hypot` · `radians degrees` · `random() randint(a, b) seed(n)` |
| `json` | `json.encode(value)`, `json.encode(value, indent)`, `json.decode(text)` |
| `time` | `now()` (seconds since 1970), `clock()` (CPU seconds), `sleep(seconds)` |
| `fs` | `read(path)` `write(path, text)` `append(path, text)` `lines(path)` `exists(path)` `is_dir(path)` `list(dir)` `remove(path)` `mkdir(path)` |
| `os` | `os.run(command)` (runs a shell command, gives `{code, output}`), `os.args` (list of command-line arguments), `os.script` (path of the running file), `env(name)`, `cwd()`, `exit(code)`, `platform` |

Written in Faxal itself and built into the program (`import "std/..."`):

| Module | Contents |
| --- | --- |
| `std/collections` | `Stack` `Queue` `Set` (`set_of(list)`) `Heap` (priority queue) · `counter(list)` |
| `std/iter` | `enumerate zip sum product count any all find take skip reverse flatten chunks unique group_by sort_by min_by max_by partition repeat` |
| `std/text` | `pad_left pad_right center capitalize title reverse is_digit is_alpha words truncate wrap fixed commas` |
| `std/numbers` | `gcd lcm factorial is_prime primes_up_to mean median variance stddev remap` |
| `std/tasks` | `run spawn sleep gather timeout Channel` for `async fn` and `await` (see Coroutines and async) |
| `std/regex` | regular expressions: `test find find_all full_match replace replace_first split escape compile` (groups, named groups, lazy quantifiers, lookahead, backreferences, `"i"` flag) |
| `std/datetime` | dates and times (UTC): `make(y, m, d, ...)` `now()` `today()` `parse("2026-10-03 14:30")` `from_timestamp(ts)`; a DateTime has `year month day hour minute second ts`, `format("%Y-%m-%d %H:%M")`, `add_days add_months add_years add_hours ...`, `weekday()`, `days_until(other)` |
| `std/path` | `join basename dirname ext stem split normalize with_ext is_absolute` |
| `std/csv` | `parse(text)` (list of rows) `records(text)` (list of maps) `stringify(rows)` |
| `std/random` | `seed int(a, b) float(a, b) choice shuffle sample chance` |
| `std/color` | `rgb(r, g, b)` `hsl(h, s, l)` `gray(0..1)` `rainbow(i, n)`: colors for `color()` and `background()` |
| `std/test` | `test eq ne ok close throws fail run`: the test framework behind `faxal test` |
| `std/lex` `std/fmt` | the tokenizer and the formatter behind `faxal fmt` |

Global functions: `bool`, `sum`, `any`, `all`, `sorted`, `reversed`, `zip`, `enumerate` (see Lists), `print(...)`, `write(...)` (no newline), `input(prompt)` (returns `nil` at end of input), `len`, `str`, `repr`, `num` (text to number, or `nil`), `int`, `type`, `range`, `assert(cond, message)`, `ord`, `chr`, `abs`, `floor`, `ceil`, `round`, `sqrt`, `min`, `max`, `exit`.

## Drawing

Faxal has a built-in turtle: a pen that starts in the middle, pointing up. Move it and it draws.

```fx
color("white")
width(2)
for i in 0..4 {
  forward(100)
  turn(90)               # degrees, clockwise
}
save_svg("square.svg")   # or run with: faxal --svg square.svg program.fx
```

| Function | What it does |
| --- | --- |
| `forward(n)` `back(n)` `turn(degrees)` | move or rotate |
| `penup()` `pendown()` | stop / start drawing |
| `goto(x, y)` `home()` | jump (without drawing) |
| `color(name)` `color(r, g, b)` `width(n)` `background(name)` | style |
| `circle(r)` `disc(r)` | a circle outline / a filled circle, centered on the pen |
| `rect(w, h)` `box(w, h)` | a rectangle outline / a filled rectangle, centered on the pen |
| `text(words, size)` | write words at the pen (size is optional, default 16) |
| `save_svg(path)` | write the picture to a file |

## Project tools

Faxal comes with the tools for a whole project. Most of them are written in Faxal.

```bash
faxal init my-app         # new project: faxal.json, main.fx, a test, .gitignore
cd my-app
faxal run                 # runs the "main" file from faxal.json
faxal test                # runs every *_test.fx file
faxal fmt                 # formats all code (faxal fmt --check only reports)
faxal add user/repo       # add a package: GitHub shorthand, a git URL, or a folder/file
faxal add ../shared utils # ...and choose the name you import it by
faxal install             # install everything listed in faxal.json
faxal build main.fx -o app    # make one standalone executable
faxal build main.fx --native -o app   # ...as real native code, through a C compiler
faxal lsp                 # language server for your editor (see below)
```

A test file is plain Faxal:

```fx
import "std/test" as t

t.test("adds", fn() {
  t.eq(1 + 1, 2)
})
t.test("fails on purpose", fn() {
  t.throws(fn() { throw "boom" }, "boom")
})
```

### Compiled programs

`faxal compile` turns a program into a **bytecode file** that runs without the source and starts without compiling:

```bash
faxal compile app.fx          # writes app.fxc
faxal app.fxc                 # runs it (arguments after the file go to the program, as usual)
faxal check app.fxc           # verify it without running
faxal dump app.fxc            # show the instructions inside
```

Compiled files are checked by a verifier before they run, so a damaged or tampered file is rejected instead of misbehaving. `import "lib"` can load a compiled `lib.fxc`. The file format is described in `docs/BYTECODE.md` in the repository. An executable made with `faxal build` carries bytecode, not source (use `faxal build --source` to carry source text).

### Native programs (compile to C)

`faxal build` has two more modes that go through C:

```bash
faxal build main.fx --c -o program.c     # one C file: your program plus the whole runtime
cc -O2 -o program program.c -lm          # any C compiler turns it into a native executable
faxal build main.fx --native -o program  # both steps at once
```

The C file contains no reference to faxal: it can be compiled on a computer that has never had faxal installed, for any system that has a C compiler (Linux, macOS, Windows with MinGW). The result is a self-contained native executable. It needs the runtime source (`faxal.c`), which `make install` and the installers put next to the `faxal` program; set `FAXAL_RUNTIME=/path/to/faxal.c` to point somewhere else. The program still runs on Faxal's virtual machine: it is a native executable, not machine code made from your functions.

### The language server

`faxal lsp` speaks the Language Server Protocol, so any editor that supports it gets Faxal help without a plugin written for that editor: errors as you type (checked by the real compiler), completion, hover help, format document (the same formatter as `faxal fmt`) and an outline of functions and classes. Configure your editor to run the command `faxal lsp` for `.fx` files. For example, in Neovim:

```lua
vim.lsp.start({ name = "faxal", cmd = { "faxal", "lsp" }, root_dir = vim.fn.getcwd() })
```

### The compiler

Faxal's compiler is written in Faxal itself (`std/compiler`) and is built into the `faxal` program as precompiled bytecode, so it starts instantly. Everything you run or compile goes through it, including the standard library, the tools, and programs in safe mode.

A second compiler, written in C, produces exactly the same bytecode. It is what builds the Faxal one in the first place, and you can ask for it:

```bash
faxal --c-compiler program.fx    # compile with the compiler written in C (or set FAXAL_C_COMPILER=1)
faxal fxc program.fx             # run the Faxal compiler as a tool and print the bytecode it produces
faxal fxc --errors broken.fx     # print its errors as line:column: message
```

You can also use the compiler from your own programs: `import "std/compiler" as fxc` and call `fxc.compile(source)`; see the comments at the top of `native/lib/std/compiler.fx`.

**`faxal build`** packs your program (compiled to bytecode), every file it imports (including packages) and the faxal program itself into one file. Give that file to anyone with the same kind of computer: nothing else needs to be installed. The built program receives its own command-line arguments in `os.args`. It only packs imports written as `import "file"`; paths worked out at run time with `load()` are not included.

## Safe mode

`faxal --sandbox` is for running code you don't trust (the website uses it). It removes `fs`, `os`, `input`, file `import`s (the `std/` modules still work), `exit` and `save_svg`, and stops programs that run for too long, use too much memory or print too much.
