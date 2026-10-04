## Built in everywhere

These need no `import`. They also work in safe mode (except `fs`, `os`, `input` and `exit`, which need a real computer).

### Global functions

| Function | What it does |
| --- | --- |
| `print(...)` `write(...)` | show values separated by spaces, with / without a new line |
| `input(prompt)` | read a line from the keyboard; `nil` at the end of the input |
| `len(x)` | length of a string (bytes), list, map or range |
| `str(x)` `repr(x)` | text; `repr` shows strings with quotes |
| `num(x)` `int(x)` | read a number from text; `int` drops decimals |
| `bool(x)` | `true` unless `x` is `nil` or `false` |
| `type(x)` | `"number"` `"string"` `"list"` `"map"` `"range"` `"function"` `"class"` `"instance"` `"coroutine"` ... |
| `range(n)` `range(a, b, step)` | a range of numbers |
| `isinstance(obj, Class)` | made by this class or a subclass? |
| `assert(cond, message)` | stop with an error if `cond` is false |
| `abs floor ceil round sqrt min max` | the usual maths |
| `sum(list)` `any(list, f)` `all(list, f)` | add up / is `f` true for some / for every item |
| `sorted(list, cmp)` `reversed(list)` | sorted / reversed copies |
| `zip(a, b)` `enumerate(list)` | pairs: `[a0, b0]...` and `[index, item]...` |
| `ord(c)` `chr(n)` | character code and back |
| `exit(code)` | stop the program |
| `load(path)` | `import` as a function, for paths computed at run time |
| `coroutine resume yield resume_error status` | coroutines (see the language docs) |

### math

`math.pi` `math.e` `math.inf` `math.nan`

| Function | |
| --- | --- |
| `sqrt(x)` `pow(x, y)` `exp(x)` `log(x)` `log2(x)` `log10(x)` | powers and logarithms |
| `sin cos tan asin acos atan` `atan2(y, x)` `hypot(x, y)` | trigonometry, in radians |
| `floor ceil round trunc abs sign` | rounding and sign |
| `min(a, b, ...)` `max(...)` `clamp(x, lo, hi)` | extremes (also take one list) |
| `radians(deg)` `degrees(rad)` | angle conversion |
| `random()` `randint(a, b)` `seed(n)` | random numbers; `seed` makes them repeatable |

```fx
print(math.sqrt(16), math.clamp(15, 0, 10), math.floor(2.7), math.hypot(3, 4))   # 4 10 2 5
```

### json

`json.encode(value)` makes text, `json.encode(value, 2)` indents it, `json.decode(text)` reads it back.

```fx
let text = json.encode({name: "Ada", langs: ["Faxal"], age: 36})
print(text)                         # {"name":"Ada","langs":["Faxal"],"age":36}
print(json.decode(text).langs[0])   # Faxal
```

### time

`time.now()` is seconds since 1970, `time.clock()` is CPU seconds (good for timing), `time.sleep(seconds)` waits (not in safe mode).

### fs and os (not in safe mode)

| | |
| --- | --- |
| `fs.read(path)` `fs.write(path, text)` `fs.append(path, text)` | whole files |
| `fs.lines(path)` `fs.list(dir)` | lines of a file / names in a folder |
| `fs.exists(path)` `fs.is_dir(path)` `fs.mkdir(path)` `fs.remove(path)` | checks and changes |
| `os.run(command)` | runs a shell command, gives `{code, output}` |
| `os.args` `os.script` `os.env(name)` `os.cwd()` `os.platform` | the program's surroundings (`"macos"`, `"linux"`, `"windows"`) |
| `os.stdin_read(n)` `os.flush()` | read bytes from standard input / flush output |
| `net.listen(port, host)` `net.port(server)` `net.accept(server, timeout)` | TCP: start listening (port `0` picks a free one) / the port it got / wait for a connection (`nil` after `timeout` seconds) |
| `net.connect(host, port, timeout)` `net.read(conn, max, timeout)` `net.write(conn, text)` `net.close(conn)` | TCP client and data: `read` gives `""` when the other side closed and `nil` on a timeout. `std/http` is built on these |

## Strings, lists and maps

Methods are listed in the language docs. A few more details:

- `s.bytes()` gives the bytes of a string as a list of numbers 0 to 255, and `from_bytes(list)` makes a string from them (this is how `std/encoding` works).
- Strings are UTF-8 bytes: `len` counts bytes, `s.size()` counts characters, and `for c in s` goes character by character.
- `list.sort()` sorts in place and `sorted(list)` makes a sorted copy. Mixed numbers and strings need a comparison function: `sort(fn(a, b) => a.age - b.age)`.
- Maps keep the order entries were added. Reading a missing key gives `nil`.

## std/collections

```fx
import "std/collections" as col
let s = col.Stack()
s.push(1).push(2)
print(s.pop(), s.peek(), s.len())       # 2 1 1
let q = col.Queue()
q.push("a").push("b")
print(q.pop(), q.len())                 # a 1
let seen = col.set_of([1, 2, 2, 3])
print(seen.has(2), seen.len())          # true 3
```

| | |
| --- | --- |
| `Stack` | `push pop peek len is_empty to_list` (last in, first out) |
| `Queue` | `push pop peek len is_empty` (first in, first out; `pop` stays fast however long it is) |
| `Set` / `set_of(list)` | `add has remove len is_empty to_list each union intersect minus is_subset` |
| `Heap` | a priority queue: `push(x)`, `pop()` gives the smallest, `peek len is_empty` (pass a comparison function to `Heap(cmp)` to change the order) |
| `counter(list)` | a map from each item to how many times it appears |

## std/iter

`enumerate zip sum product count any all find take skip reverse flatten chunks unique group_by sort_by min_by max_by partition repeat`

```fx
import "std/iter" as it
print(it.chunks([1, 2, 3, 4, 5], 2))                       # [[1, 2], [3, 4], [5]]
print(it.group_by(["ant", "bee", "ape"], fn(w) => w[0]))   # {a: ["ant", "ape"], b: ["bee"]}
print(it.partition([1, 2, 3, 4], fn(n) => n % 2 == 0))     # [[2, 4], [1, 3]]
```

## std/text

`pad_left pad_right center capitalize title reverse is_digit is_alpha words truncate wrap fixed commas starts_with_any` (`wrap(text, width)` gives a list of lines)

```fx
import "std/text" as tx
print(tx.title("the quick fox"), tx.fixed(3.14159, 2), tx.commas(1234567))   # The Quick Fox 3.14 1,234,567
print(tx.wrap("one two three four five", 10))
```

## std/numbers

`gcd lcm factorial is_prime primes_up_to mean median variance stddev remap`

```fx
import "std/numbers" as nm
print(nm.gcd(12, 18), nm.factorial(5), nm.is_prime(97), nm.mean([1, 2, 3, 4]))   # 6 120 true 2.5
print(nm.remap(5, 0, 10, 0, 100))                                                 # 50
```

## std/color

`rgb(r, g, b)` `hsl(h, s, l)` `gray(0..1)` `rainbow(i, n)` make color text for `color()` and `background()`.

```fx
import "std/color" as c
background(c.gray(0.05))
for i in 0..36 { color(c.rainbow(i, 36)); forward(60); turn(170) }
```

## std/regex

Regular expressions: literals, `.` `[abc]` `[^abc]` `[a-z]`, `\d \w \s` (and `\D \W \S`), `\b`, `^ $`, groups `( )`, non-capturing `(?: )`, named groups `(?<name> )`, alternation `|`, `* + ? {n} {n,} {n,m}` (add `?` for lazy), lookahead `(?= )` `(?! )` and backreferences `\1`. Positions count characters. The flag `"i"` ignores case.

| Function | |
| --- | --- |
| `test(pattern, text)` | is there a match anywhere? |
| `find(pattern, text)` | the first match, or `nil`: `{text, start, end, groups, named}` |
| `find_all(pattern, text)` | a list of matches |
| `full_match(pattern, text)` | a match only if the whole text matches |
| `replace(pattern, text, with)` | replace every match; `with` is text (`$1` is group 1, `$0` the match) or a function |
| `replace_first(...)` `split(pattern, text)` | replace one / split at matches |
| `escape(text)` `compile(pattern)` | make text safe inside a pattern / compile once and reuse |

```fx
import "std/regex" as re
let m = re.find("(?<year>\\d{4})-(?<month>\\d\\d)", "due 2026-10-03")
print(m.named.year, m.named.month, m.start)                       # 2026 10 4
print(re.replace("(\\w+)@(\\w+)", "ada@home", "$2:$1"))           # home:ada
print(re.split("[,;] *", "a, b;c"))                               # ["a", "b", "c"]
print(re.find_all("\\d+", "1 22 333").map(fn(m) => m.text))       # ["1", "22", "333"]
```

## std/datetime

Dates and times in UTC. A `DateTime` has `year month day hour minute second ts` (seconds since 1970).

| | |
| --- | --- |
| `make(y, m, d, h, mi, s)` | a date (only the year is required) |
| `now()` `today()` `from_timestamp(ts)` | the current time / midnight today / from seconds |
| `parse("2026-10-03 14:30")` | reads `YYYY-MM-DD`, with optional `HH:MM[:SS]` and `T`/`Z` |
| `d.format("%A, %d %B %Y")` | `%Y %y %m %d %e %H %I %M %S %p %B %b %A %a %j %u %s %%` |
| `d.add_days(n)` `add_months(n)` `add_years(n)` `add_hours(n)` `add_minutes(n)` `add_seconds(n)` | a new date (month ends are handled: Jan 31 + 1 month is Feb 28/29) |
| `d.weekday()` `d.day_of_year()` `d.days_until(other)` `d.is_before(other)` `d.start_of_day()` | |
| `is_leap(year)` `days_in_month(year, month)` | |

```fx
import "std/datetime" as dt
let d = dt.make(2026, 10, 3, 14, 30)
print(d, "|", d.format("%A, %d %B %Y"))                  # 2026-10-03 14:30:00 | Saturday, 03 October 2026
print(d.add_months(4).format("%Y-%m-%d"), d.weekday())   # 2027-02-03 5
print(dt.make(2026, 1, 1).days_until(dt.make(2026, 12, 25)))   # 358
```

## std/path

`join basename dirname ext stem split normalize with_ext is_absolute`

```fx
import "std/path" as path
print(path.join("a", "b", "c.txt"), path.basename("/x/y/z.tar.gz"), path.ext("z.tar.gz"))   # a/b/c.txt z.tar.gz .gz
print(path.normalize("a/./b/../c"), path.stem("z.tar.gz"))                                  # a/c z.tar
```

## std/csv

`parse(text)` gives a list of rows, `records(text)` a list of maps using the first row as names, `stringify(rows)` writes text. Fields containing the separator, quotes or new lines are quoted.

```fx
import "std/csv" as csv
let rows = csv.records("name,age\nada,36\n\"Lee, Bo\",41")
print(rows[1].name, rows[1].age)                         # Lee, Bo 41
print(csv.stringify([["a", "b,c"], [1, 2]]))
```

## std/random

`seed(n)` `int(a, b)` `float(a, b)` `choice(list)` `shuffle(list)` (in place) `sample(list, n)` `chance(p)`

```fx
import "std/random" as random
random.seed(42)
let deck = random.shuffle([1, 2, 3, 4, 5])
print(deck.len(), random.sample(deck, 2).len(), random.int(1, 6) <= 6)    # 5 2 true
```

## std/tasks

`run spawn sleep gather timeout Channel` for `async fn` and `await`. See "Coroutines and async" in the language docs. `tasks.run(main, true)` uses a pretend clock only, so sleeping takes no time and tasks always finish in the same order (handy in tests).

## std/http

An HTTP/1.1 client and server written in Faxal on top of `net` (plain `http://` only: there is no TLS). Not available in safe mode.

```fx
import "std/http" as http
import "std/tasks" as tasks

let app = http.Router()
app.get("/hello", fn(req) => http.text("Hello, " + (req.query.name ?? "you") + "!"))
app.get("/notes/:id", fn(req) => http.send_json({id: req.params.id}))
app.post("/echo", async fn(req) => http.send_json(req.json(), 201))

async fn main() {
  let port = nil
  let server = tasks.spawn(http.serve_async(0, app, limit = 2, on_start = fn(p) { port = p }))
  await nil
  let base = "http://127.0.0.1:" + str(port)
  print((await http.get_async(base + "/hello?name=Ada")).text())     # Hello, Ada!
  print((await http.get_async(base + "/notes/42")).json().id)        # 42
  await server
}
tasks.run(main())
```

| Client | |
| --- | --- |
| `get(url)` `head` `delete` | a `Response`: `status`, `reason`, `ok`, `headers` (lowercase names), `body`, `text()`, `json()`, `header(name)` |
| `post(url, body, headers)` `put` `post_json(url, value)` | send a body |
| `request(method, url, body, headers, timeout, redirects)` | the general form (follows up to 5 redirects; handles chunked bodies) |
| `get_async(url)` `post_async` `request_async(...)` | the same for `await`: other tasks run while waiting |

| Server | |
| --- | --- |
| `serve(port, handler, host, limit, on_start)` | one connection at a time. `handler` is a function `fn(req)` or a `Router`. Use port `0` to get a free port, `limit` stops after that many requests |
| `serve_async(...)` | every connection is its own task, and handlers may be `async fn`s; start it with `tasks.run` |
| `Router()` | `get post put delete add(method, pattern, handler)`: patterns like `/notes/:id` (`req.params.id`) and `/files/*` (`req.params.rest`); gives 404 and 405 for you |
| `req` | `method path query headers body params`, plus `req.json()`, `req.form()`, `req.header(name)` |
| handler results | a `Response`, text (HTML if it starts with `<`), a map or list (sent as JSON), or `nil` (204). An error in a handler becomes a 500 response |
| `text(body, status)` `html` `send_json(value, status)` `redirect(url)` `status_only(404)` | build responses |

## std/encoding

`base64_encode` `base64_decode` `hex_encode` `hex_decode` `url_encode` `url_decode(text, plus)` `html_escape`. Text is handled as bytes (UTF-8), so any text round-trips.

```fx
import "std/encoding" as enc
print(enc.base64_encode("héllo"), enc.url_encode("a b&c"), enc.hex_encode("hi"))   # aMOpbGxv a%20b%26c 6869
print(enc.html_escape("<b>"), enc.url_decode("a%20b+c"))                          # &lt;b&gt; a b c
```

## std/test

The test framework behind `faxal test`: `test(name, fn)`, `eq(actual, expected)`, `ne`, `ok(condition)`, `close(a, b)`, `throws(fn, text)`, `fail(message)` and `run()`.

```fx
import "std/test" as t
t.test("adds", fn() { t.eq(1 + 1, 2) })
t.test("fails loudly", fn() { t.throws(fn() { throw "boom" }, "boom") })
t.run()
```

## std/lex, std/fmt, std/compiler, std/bytecode, std/analyze

The tokenizer, formatter, compiler and bytecode tools that Faxal is built from. `std/analyze` finds the names in code and what they refer to (used by the language server for go to definition, references and rename): `analyze(source)` gives `decls` and `refs`, `resolve(a, token)` gives every use of a name. `lex.tokenize(source)` gives tokens, `fmt.format(source)` gives formatted code, `compiler.compile(source)` gives `{ok, program}` or `{ok: false, errors}` (each error has `message line col text length`). They are written in Faxal: read them in `native/lib/std/`.
