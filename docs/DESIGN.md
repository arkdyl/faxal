## What Faxal is for

Faxal is a small programming language for **making things you can see**. You can draw with it from the very first line, and the language stays small enough to hold in your head: the whole reference fits on one page. It is a real language with a compiler, a virtual machine, a standard library, tools and tests, so what you learn on small programs carries over to big ones.

## Principles

- **Code you can see.** Drawing is built in: a turtle, circles, rectangles and text, with SVG export. Programs show their results.
- **Small.** One way to do most things. A language you can finish learning.
- **Friendly.** Error messages point at the line and suggest fixes ("Did you mean 'print'?"). Mistakes should teach.
- **Batteries included, written in Faxal.** Collections, text and number helpers, colors, a test framework, a formatter and a package manager come with it, and most of them are Faxal programs you can read.
- **Real, not a toy.** A fast native virtual machine, a garbage collector, closures, classes, modules, standalone executables, and a test suite that is fuzzed and run under memory sanitizers.

## Where the ideas come from

No language is built from nothing. Faxal is a particular selection of ideas that already work well:

| Idea | From |
| --- | --- |
| The way the compiler and virtual machine are built | *Crafting Interpreters* (the clox design) |
| `{ }` blocks, `let`, `fn` | Rust, JavaScript |
| Lines end statements, no semicolons | Go |
| f-strings, `for x in`, ranges | Python, Rust |
| Pipes `\|>` | Elixir, F# |
| `??` and `?.` | JavaScript, Swift, C# |
| Maps as objects and a small fast VM | Lua |
| Turtle graphics | Logo |
| `class`, `init`, `extends`, `super` | Lox, Swift, Python |
| Only `nil` and `false` are false | Ruby, Lua |
| Default parameters | Python, JavaScript |
| Single-file standalone programs | Go, Deno |

What is Faxal's own is the combination and the details: drawing as part of the core language, `to_str` for printing, insertion-ordered maps everywhere, opt-in `f"..."` strings so that plain strings never surprise you, and the tools being written in the language itself.

## Faxal builds itself

Most of Faxal is written in Faxal:

- the standard library (`native/lib/std/`): collections, iteration, text, numbers, colors, the test framework
- the tools: `faxal fmt`, `faxal test`, `faxal init`, the package manager, `faxal run`
- the tokenizer (`std/lex`) and the formatter (`std/fmt`)
- the program that packs those files into the faxal executable (`native/tools/embed.fx`), so that `faxal` builds its own library
- **the compiler** (`std/compiler`, with `std/bytecode`): a complete compiler from Faxal source to bytecode, written in Faxal

The compiler written in Faxal is a port of the C one, and it is **the default compiler**: everything you run, including the standard library, the tools and the website's safe mode, is compiled by it. It produces exactly the same bytecode (instructions, line numbers and constants) and the same error messages, line numbers and columns as the C compiler.

How it is built into faxal: `make embed` compiles every file in `native/lib/` (the compiler, the standard library, the tools) to bytecode and builds the bytes into the executable. Starting faxal loads the compiler from there, so nothing has to be compiled to get going (a start takes under 10 ms). The program that does this is itself written in Faxal.

How we know it is right:

- for every Faxal file in the repository, the two compilers produce identical bytecode. This includes the compiler's own source: the Faxal compiler, compiled by the C compiler, compiles itself to exactly the same bytecode the C compiler gives it
- for tens of thousands of randomly damaged programs, both compilers agree on whether the program compiles, and if not, on the first error's message, line and column. This found a real bug in the C scanner (wrong line numbers after a newline inside a string inside an f-string), which is fixed
- the full test suite, also under AddressSanitizer and a garbage collector that runs at every opportunity, passes with either compiler

Why the C compiler is still there:

- It bootstraps faxal: it compiles the Faxal compiler into the bytecode that is built in (`make embed`). Without a compiler that exists before the Faxal one, there would be no way to build either.
- It is the reference the Faxal compiler is tested against, and it is the fallback if the built-in compiler can't be loaded.
- It is faster, though only by a small amount: a 1,300 line file takes 5 ms in C and 20 ms in Faxal.
- `faxal --c-compiler` (or `FAXAL_C_COMPILER=1`) uses it.

Programs can be compiled ahead of time to **bytecode files** (`.fxc`, see `docs/BYTECODE.md`): `faxal compile app.fx`, then `faxal app.fxc`. The format has a checksum, a version, and a verifier that proves a file safe for the virtual machine before it runs. Both compilers write byte-for-byte identical files. The verifier is also why untrusted code can safely go through the Faxal compiler: whatever it produces is checked before it runs.

What is still C: the virtual machine, the garbage collector and the built-in functions (`native/src/`). A Faxal program can't run without something that runs it, so that part stays native.

## Nothing to depend on

The whole runtime (virtual machine, garbage collector, built-in functions and the embedded bytecode of the compiler, library and tools) can be written out as **one C file**, `native/dist/faxal.c`, by a Faxal program (`native/tools/amalgamate.fx`). `cc -O2 -o faxal faxal.c -lm` is the entire build: no Make, no package manager, nothing to download. All the system-specific code (Linux, macOS, Windows) lives in one header, `platform.h`. A Faxal program can also be turned into one C file with `faxal build --c`, which any C compiler turns into a native executable on a machine that never had Faxal installed.

## Concurrency without threads

Faxal has coroutines: a function with a stack of its own that can pause with `yield` and continue later. `async fn` and `await` are built on them: an `async` function returns a coroutine, `await` hands what it waits for to the scheduler in `std/tasks`, and the scheduler runs other tasks in the meantime. Everything runs on one thread and tasks switch only at `await`, so programs have no data races and the virtual machine stays simple. The scheduler itself is a Faxal program.

## How it is tested

- **Specs:** every language feature has small programs with their expected output (`native/tests/spec/`).
- **Faxal tests:** the standard library is tested with `faxal test`, using Faxal's own test framework.
- **Toolchain tests:** `init`, `run`, `test`, `fmt`, `add`, `build` and the safe mode are exercised end to end.
- **Two compilers:** the C compiler and the Faxal compiler (the default) are compared on every Faxal file in the repository and on tens of thousands of damaged programs, and the whole test suite runs with both.
- **Bytecode files:** every program is compiled to a `.fxc`, run from it, and compared with running the source; thousands of corrupted `.fxc` files are loaded and run under AddressSanitizer.
- **Formatter proof:** for every Faxal file in the repository, formatting must be idempotent and must produce *byte-for-byte the same bytecode*.
- **Memory safety:** the whole suite also runs under AddressSanitizer and UBSan, with a garbage collector that collects at every opportunity.
- **Fuzzing:** thousands of corrupted programs are fed to the interpreter and to the formatter; neither may crash or hang.

## What Faxal does not try to be

- A language with a strict static type system, parallel threads, or a huge ecosystem. Types are optional and checked while the program runs, and `async` tasks take turns on one thread.
- Compatible with any other language. Faxal programs should be easy to read and write, not easy to port.
- A research language. Its ideas are known ideas, chosen carefully.
