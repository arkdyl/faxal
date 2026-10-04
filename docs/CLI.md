## The faxal command

One program does everything: it runs code, checks it, compiles it, formats it, tests it and packs it.

| Command | What it does |
| --- | --- |
| `faxal file.fx [args...]` | run a program; the arguments land in `os.args` |
| `faxal repl` | an interactive shell (also what plain `faxal` does in a terminal) |
| `faxal -e 'code'` | run a snippet |
| `faxal -` | read the program from standard input |
| `faxal check file.fx` | find syntax errors without running anything |
| `faxal compile file.fx` | write `file.fxc`, a bytecode file that runs without the source |
| `faxal file.fxc` | run a bytecode file |
| `faxal dump file.fxc` | show the instructions inside a bytecode file |
| `faxal --dump file.fx` | show the bytecode of a program, then run it |
| `faxal --svg out.svg file.fx` | save the turtle drawing as an SVG when the program ends |
| `faxal --version` `faxal --help` | version and usage |

Exit codes: `0` success, `65` syntax error, `70` uncaught runtime error, `74` file not found, `64` wrong usage.

## Project tools

```bash
faxal init my-app         # new project: faxal.json, main.fx, a test, .gitignore
cd my-app
faxal run                 # runs the "main" file from faxal.json
faxal test                # runs every *_test.fx file (faxal test tests/ for one folder)
faxal fmt                 # formats all code; --check only reports, --stdout prints
faxal add user/repo       # add a package: GitHub shorthand, a git URL, or a folder/file
faxal add ../shared utils # ...and choose the name you import it by
faxal install             # install everything listed in faxal.json
faxal remove utils        # take a package out
faxal list                # show the project's packages
faxal lsp                 # language server for your editor
```

A project is a folder with a `faxal.json`:

```
{
  "name": "my-app",
  "main": "main.fx",
  "dependencies": { "utils": "../shared" }
}
```

Packages are copied into `fx_modules/`, and `import "utils"` finds them from any file in the project.

## Building programs

| Command | Result |
| --- | --- |
| `faxal build main.fx -o app` | one executable: your program (as bytecode), every file it imports, and the faxal runtime |
| `faxal build main.fx --source -o app` | the same, but carrying source text instead of bytecode |
| `faxal build main.fx --c -o app.c` | one C file with your program and the whole runtime inside |
| `faxal build main.fx --native -o app` | the C file, compiled by your C compiler into a native executable |

The built program takes its own command-line arguments in `os.args` and needs nothing installed. `--c` and `--native` need the runtime source `faxal.c`; the installers put it next to `faxal`, or set `FAXAL_RUNTIME=/path/to/faxal.c`. Only imports written as `import "file"` are packed, not paths worked out at run time with `load()`.

## Safe mode

`faxal --sandbox` is for running code you don't trust (the website uses it). It removes `fs`, `os`, `input`, file `import`s (the `std/` modules still work), `exit` and `save_svg`, and stops programs that run for too long, use too much memory or print too much. `--json` prints the result (output, error, drawing) as JSON.

## Options and variables

| | |
| --- | --- |
| `--c-compiler` or `FAXAL_C_COMPILER=1` | compile with the compiler written in C instead of the one written in Faxal |
| `--sandbox` | safe mode (see above) |
| `--json` | machine-readable result |
| `FAXAL_RUNTIME=path` | where `faxal build --c` finds `faxal.c` |
| `CC=compiler` | the C compiler used by `faxal build --native` and by the installers |

## Editors

`faxal lsp` is a language server (the Language Server Protocol over standard input and output). It gives any editor that supports the protocol:

- errors as you type, checked by the real compiler
- completion, hover help, and signature help while you type arguments (it follows named arguments)
- **go to definition** (also into other files: `import "x"` and `module.name`), **find references**, **highlight uses**, and **rename** (scope-aware: a local `total` and a global `total` are different names)
- format document, an outline of functions and classes, and symbol search

Tell the editor to run `faxal lsp` for `.fx` files. Columns count bytes, so on lines with non-ASCII text positions may be off.

```lua
-- Neovim
vim.lsp.start({ name = "faxal", cmd = { "faxal", "lsp" }, root_dir = vim.fn.getcwd() })
```

For VS Code there is an extension in `editors/vscode/` (syntax colors plus the language server): see its README to install it.

## Installing

```bash
curl -fsSL https://raw.githubusercontent.com/arkdyl/faxal/main/install.sh | sh   # Linux, macOS: downloads the latest release
irm https://raw.githubusercontent.com/arkdyl/faxal/main/install.ps1 | iex        # Windows (PowerShell)
./install.sh                                                                     # from a checkout: builds from one C file (needs a C compiler)
```

By hand, with nothing but a C compiler: `cc -O2 -o faxal native/dist/faxal.c -lm`. Make, Python and Node are not needed to build or use the language (Node only runs this website). The installers put `faxal` in `/usr/local/bin` (or `~/.faxal/bin`, or `%LOCALAPPDATA%\faxal\bin` on Windows) and print how to add it to your PATH. Faxal is developed on macOS. Linux and Windows are built and tested by continuous integration on every change, but have had less everyday use.
