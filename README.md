# Faxal

A small programming language for making things you can see: its own compiler, a fast virtual machine, a standard library written in Faxal, project tools, standalone executables, and a website where you can try it, share programs and browse a gallery.

```
import "std/color" as c

for i in 0..24 {
  color(c.rainbow(i, 24))
  home()
  turn(15 * i)
  penup(); forward(90); pendown()
  circle(34)
}
```

Faxal is a real language, not a web demo. The interpreter is one native C program with no dependencies, and the website runs that same interpreter on the server, in a sandbox. Read [docs/DESIGN.md](docs/DESIGN.md) for what Faxal is for and where its ideas come from.

## Try it

You need a C compiler (clang or gcc) and `make`. The website additionally needs Node 24+.

```bash
cd native
make                              # builds native/bin/faxal
./bin/faxal ../examples/hello.fx
./bin/faxal repl                  # interactive shell
sudo make install                 # optional: puts `faxal` in /usr/local/bin
```

```bash
faxal program.fx [args...]        # run a program
faxal -e 'print(6 * 7)'           # run a snippet
faxal check program.fx            # syntax check only
faxal --dump program.fx           # show the bytecode
faxal --svg out.svg art.fx        # save the turtle drawing as an SVG
faxal --sandbox program.fx        # no files/os/imports, plus time and memory limits
faxal --c-compiler program.fx     # use the compiler written in C instead of the Faxal one
```

## Projects, tools and packages

```bash
faxal init my-app        # new project: faxal.json, main.fx, a test, .gitignore
cd my-app
faxal run                # run the project's main file
faxal test               # run every *_test.fx file
faxal fmt                # format all code (--check to only report)
faxal add user/repo      # add a package: GitHub shorthand, git URL, folder or .fx file
faxal install            # install everything listed in faxal.json
faxal build main.fx -o app   # one standalone executable, nothing else to install
faxal compile main.fx        # compile to a bytecode file (main.fxc); run it with: faxal main.fxc
```

`faxal build` packs your program (compiled to bytecode), the files it imports (packages included) and the interpreter into a single file. The built program runs on its own and gets its command-line arguments in `os.args`. It works for the kind of computer you build on.

The language guide is in [docs/LANGUAGE.md](docs/LANGUAGE.md) and on the website's Docs page. Example programs are in [examples/](examples/). Editor support for VS Code is in [editors/vscode/](editors/vscode/).

## Install

```bash
./install.sh        # Linux, macOS, BSD
.\install.ps1       # Windows (PowerShell)
```

Both build faxal from `native/dist/faxal.c`, the whole runtime as a single C file, so the only thing you need is a C compiler. Or do it by hand: `cc -O2 -o faxal native/dist/faxal.c -lm`. No Make, Python or Node is needed to build or use the language. CI builds and tests it on Linux, macOS and Windows (`.github/workflows/`).

## What the language has

- numbers, strings (UTF-8, `f"..."` interpolation), booleans, `nil`, lists, ordered maps, ranges (`0..10 by 2`)
- functions as values, closures, recursion, default parameters, short arrow functions `fn(x) => x * 2`
- optional types that are checked at run time: `fn area(w: num, h: num) -> num`
- coroutines and generators (`yield`, `resume`, `for x in coroutine(...)`), and `async fn` / `await` with a task scheduler in `std/tasks` (sleep, gather, timeout, channels)
- classes with `init`, `self`, `extends`, `super`, and `to_str` for printing
- `if` / `while` / `for … in`, `break`, `continue`; `try` / `catch` / `throw` with stack traces
- pipes `x |> f(a)`, default values `a ?? b`, safe access `a?.b`
- modules (`import`), packages, a standard library, and compiled bytecode files (`.fxc`)
- a standard library with regular expressions, dates, paths, CSV, random, collections and more
- friendly errors that suggest fixes (`Did you mean 'print'?`)
- built-in drawing: turtle, circles, rectangles, text, SVG export

## Written in Faxal

Faxal builds a lot of itself. These are Faxal programs, built into the `faxal` executable as bytecode:

| Where | What |
| --- | --- |
| `native/lib/std/` | the standard library: `collections` `iter` `text` `numbers` `color` `test`, the tokenizer `lex`, the formatter `fmt`, and **the compiler** (`compiler`, `bytecode`) |
| `native/lib/tools/` | `faxal fmt`, `faxal test`, `faxal init`, the package manager, `faxal run` |
| `native/lib/tools/lsp.fx` | `faxal lsp`, the language server |
| `native/tools/amalgamate.fx` | writes `native/dist/faxal.c`, the whole runtime as one C file |
| `native/tools/embed.fx` | compiles the files above to bytecode and builds them into the executable (`native/src/embedded.c`, `make embed`), so faxal builds its own library |

**The compiler is written in Faxal too, and it is the default.** `std/compiler` is a complete port of the C compiler that produces exactly the same bytecode and error messages. It is built into the `faxal` executable as precompiled bytecode (`make embed`), so faxal starts in under 10 ms and compiles everything you run with it, the standard library and tools included. The C compiler is still there: it bootstraps the build, it is the reference the Faxal one is tested against, and `--c-compiler` uses it. The virtual machine, garbage collector and built-in functions are C. See [docs/DESIGN.md](docs/DESIGN.md).

## The website

Pages: a home page with live demos, **Learn** (a 14-lesson guided tour with code you can run), the **Playground** (sharing and a gallery), the **Language guide** and the **Reference** (every command and standard-library function; code blocks have Run, Open and Copy buttons), **Install**, **Roadmap** (limits and changelog) and **About**. The guides are rendered from `docs/*.md`, and a test runs every code example in them.

A Node + SQLite server hosts the site (TypeScript, no framework). Runs go to `POST /api/run`, which starts `native/bin/faxal --sandbox --json` for each request (5 second timeout, limited output); `std/` modules work there too. Shared programs are stored in SQLite, with a small drawing preview for the gallery.

```bash
npm install
npm run dev:all        # builds the interpreter, then site on :5173 and API on :3001
```

Production: `npm run build && npm start` serves the built site and API on `:3001`.
Environment: `PORT`, `DB_PATH` (default `data/faxal.db`), `FAXAL_BIN` (default `native/bin/faxal`).

## How it works

| File | Role |
| --- | --- |
| `native/src/compiler.c` | scanner (automatic line endings) and a single-pass Pratt compiler that emits bytecode |
| `native/src/vm.c` | stack-based bytecode VM: calls, closures, classes, exceptions, imports, friendly error hints |
| `native/src/core.c` | strings (interned), insertion-ordered hash maps, objects, mark-and-sweep GC |
| `native/src/stdlib.c` | built-in functions, methods, `math`/`json`/`fs`/`os`/`time`, drawing |
| `native/src/bytecode.c` | the `.fxc` bytecode file format: writer, reader and the verifier that proves a file safe ([docs/BYTECODE.md](docs/BYTECODE.md)) |
| `native/src/selfhost.c` | the hook and loader that make the compiler written in Faxal the VM's compiler |
| `native/src/bundle.c` | `faxal build`, and running a program packed inside an executable |
| `native/src/platform.h` | the only place that differs between Linux, macOS and Windows |
| `native/src/main.c` | the `faxal` command: files, REPL, `-e`, `check`, tools, `--json` |
| `native/src/debug.c` | bytecode disassembler (`--dump`) |
| `server/` | HTTP API, SQLite, and the sandboxed process runner |
| `src/` | the website: home, playground, docs, about, gallery |

The GC runs only at safe points (calls and loop back-edges), so natives never see a collection halfway through a job. Native code that calls back into the VM (`map`, `sort`, `to_str`) is depth-limited so runaway recursion is a catchable error. Resource limits in sandbox mode (instruction count, memory, output) cannot be caught by `try`.

## Testing

```bash
npm test                    # website/server tests, then the whole language suite
make -C native test         # specs + Faxal's own tests + formatter proof + toolchain test
make -C native test-debug   # the same under AddressSanitizer, UBSan and a GC that collects at every safe point
make -C native fuzz         # mutation fuzzing of the interpreter, the formatter and the two compilers
make -C native embed        # recompile lib/ into src/embedded.c after editing it (make test checks it is up to date)
```

- `native/tests/spec/`: small programs that declare their expected output in comments (`# expect: …`, `# error: …`, `# compile-error: …`)
- `native/tests/std/`: the standard library, tested with `faxal test` and Faxal's own test framework
- `native/tests/fmt_check.py`: for every Faxal file in the repo, formatting must be idempotent and must produce identical bytecode
- `native/tests/bytecode_check.py` and `bytecode_fuzz.py`: every program is compiled to a `.fxc`, run from it and compared with the source; thousands of corrupted `.fxc` files are loaded and run under AddressSanitizer
- `native/tests/selfhost_check.py` and `selfhost_fuzz.py`: the Faxal compiler (the default) against the C compiler, on every file in the repo and on damaged programs: identical bytecode, or the same first error
- `native/tests/tools_test.py`: `init`, `run`, `test`, `fmt`, `add`/`remove`/`install`, `build` and the safe mode, end to end

## Project history

`legacy/ts-interpreter/` holds the first version of Faxal, an interpreter written in TypeScript that ran only in the browser. It is kept for reference and is not used.

## Ideas for next

- caching: compile imported modules to `.fxc` once and reuse them
- compressing or stripping bytecode (line tables, names) for smaller executables
- making the Faxal compiler fast enough to be the default (a cheaper token representation would help)
- go to definition and rename in the language server
- an HTTP client and server in the standard library
- machine-code generation (the bytecode VM is still what runs a "native" program)
- named arguments (`f(x, width = 3)`)
- running the VM in the browser via WebAssembly, so the site works without a server
- cross-compiling `faxal build` for other operating systems (today it builds for the computer it runs on)
- accounts, likes and comments in the gallery
