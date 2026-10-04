## Where Faxal is today

Faxal is a complete, working language with its own compiler, virtual machine and tools. It is young: it has been used by a handful of people, so it is a good language to learn with and to build small and medium programs in, and not (yet) a language to bet a company on.

| Area | State |
| --- | --- |
| Language | numbers, strings, lists, maps, ranges, functions, closures, classes, `try`/`catch`, modules, pipes, `??`, `?.`, arrow functions, optional types, coroutines, `async`/`await` |
| Runtime | stack-based bytecode virtual machine in C with a garbage collector; starts in under 10 ms |
| Compiler | written in Faxal, built into the program; a second one written in C produces identical bytecode |
| Programs | run from source, from `.fxc` bytecode files, as standalone executables, or as native executables through C |
| Tools | `fmt`, `test`, `init`, package manager, language server, REPL |
| Library | collections, iteration, text, numbers, colors, regex, dates, paths, CSV, random, tasks, HTTP, encodings, test framework |
| Platforms | developed on macOS; Linux and Windows are built and tested by CI on every change |
| Testing | specs, library tests, formatter proof, two-compiler comparison, bytecode fuzzing, sanitizers and a GC stress build |

## Honest limits

- **Speed.** Faxal is an interpreter. It is fast for an interpreter, in the range of Python and Lua, and far behind compiled languages. Programs "built natively" still run on the virtual machine: the build gives you a self-contained executable, not machine code made from your functions.
- **Types.** Types are optional and checked while the program runs, not before. There are no generics and no type inference.
- **Concurrency.** `async` tasks and coroutines take turns on one thread. There are no threads and no parallelism. A coroutine has a stack of its own that holds about 250 nested calls.
- **Library.** There is no TLS (so no `https://`), no date-time zones (UTC only), and no Unicode case or normalisation functions. The HTTP server handles one request per connection and has no HTTP/2 or WebSockets.
- **Ecosystem.** There is no package registry; packages come from git repositories or folders.
- **Platforms.** Linux and Windows have had much less real use than macOS.

## Next

- HTTPS (TLS) for `std/http`
- a package registry
- real machine-code generation, so the "native" programs are faster, not just self-contained
- a faster virtual machine: cheaper dispatch, caching compiled imports
- cancelling tasks, and a way to wait for the first of several
- running the virtual machine in the browser (WebAssembly), so the site works without a server
- cross-compiling `faxal build` for other operating systems
- accounts, likes and comments in the gallery

## Changelog

### Version 1.1

- **Named arguments.** `box(3, label = "big")`, for functions, methods, classes and `super.init(x, y = y)`. Bytecode files (format version 2) carry parameter names; version 1 files still load.
- **Networking.** The `net` functions (TCP) and `std/http`: an HTTP/1.1 client and server, with a router, JSON helpers, redirects, chunked bodies and an async server where every connection is a task. Also `std/encoding` (base64, hex, URL, HTML) and `s.bytes()` / `from_bytes()`.
- **Language server.** Go to definition (across files), find references, rename, document highlights, signature help and workspace symbols, built on the new `std/analyze`. A real VS Code extension that starts `faxal lsp`.
- **Real programs.** `apps/mdsite` (a Markdown static-site generator: it builds this project's docs) and `apps/notes` (a web app with a REST API and a page, served by Faxal), both with tests.
- **Regular expressions** no longer run out of stack on long texts.

### Version 1.0

- **Coroutines and async.** `coroutine`, `resume`, `yield`, generators with `for`, `async fn`, `await` and the `std/tasks` scheduler with `sleep`, `gather`, `timeout` and channels.
- **Optional types.** `fn area(w: num, h: num) -> num`, `let n: int = 5`, `num or nil`, checked at run time with clear messages.
- **Arrow functions.** `fn(x) => x * 2`.
- **Bigger standard library.** `std/regex`, `std/datetime`, `std/path`, `std/csv`, `std/random`, and many new string, list and map methods plus `sum`, `sorted`, `zip`, `enumerate` and `bool`.
- **Language server.** `faxal lsp`: live errors, completion, hover, formatting and an outline.
- **Independent of anything but a C compiler.** The whole runtime is one C file (`native/dist/faxal.c`); installers for Linux, macOS and Windows; `faxal build --c` and `--native` compile programs to C.
- **Self-hosted compiler.** The default compiler is written in Faxal and compared against the C one on every file and on tens of thousands of damaged programs.
- **Bytecode files.** `.fxc` files with a checksum and a verifier, so compiled code can be loaded safely.
- **Standalone executables.** `faxal build` packs a program and its imports into one file.
- **Classes**, `to_str`, pipes, default parameters, modules and packages, the formatter, the test framework and the REPL.
- **The website.** Playground with sharing and a gallery, running real Faxal in a sandbox.
