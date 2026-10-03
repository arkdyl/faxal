/* main.c: the `faxal` command line: run, repl, check, -e */
#include "faxal.h"
#include <limits.h>

#define EX_USAGE 64
#define EX_DATAERR 65
#define EX_SOFTWARE 70
#define EX_IOERR 74

static void usage(FILE* to) {
  fputs(
    "Faxal " FAXAL_VERSION " - a small, friendly programming language\n"
    "\n"
    "Usage:\n"
    "  faxal <file.fx> [args...]     run a program\n"
    "  faxal repl                    start the interactive shell\n"
    "  faxal -e '<code>'             run code given on the command line\n"
    "  faxal check <file.fx>         check for syntax errors without running\n"
    "  faxal compile <file.fx> [-o out.fxc]   compile to a bytecode file; run it with: faxal out.fxc\n"
    "  faxal dump <file.fxc>         show the bytecode inside a bytecode file\n"
    "  faxal -                       read the program from standard input\n"
    "\n"
    "Project tools:\n"
    "  faxal init [name]             start a new project (faxal.json, main.fx, tests)\n"
    "  faxal run                     run the project's main file\n"
    "  faxal test [folder]           run *_test.fx files\n"
    "  faxal fmt [--check] [paths]   format code\n"
    "  faxal lsp                     language server (editors talk to it over stdin/stdout)\n"
    "  faxal add <source> [name]     add a package (git repo or folder); also: install, remove, list\n"
    "  faxal build <main.fx> [-o x]  make a standalone executable (--source packs source text instead of bytecode)\n"
    "\n"
    "Options:\n"
    "  --dump          print the compiled bytecode before running\n"
    "  --svg <file>    save the turtle drawing as an SVG when the program ends\n"
    "  --sandbox       no files, os, input or imports, plus time and memory limits\n"
    "  --c-compiler    compile with the compiler written in C instead of the one written in Faxal\n"
    "  --json          print the result as JSON (used by the website)\n"
    "  --version, --help\n", to);
}

static char* readStdin(void) {
  Buffer b; bufInit(&b);
  char chunk[4096];
  size_t n;
  while ((n = fread(chunk, 1, sizeof chunk, stdin)) > 0) bufAppend(&b, chunk, (int)n);
  if (!b.data) bufAppend(&b, "", 0);
  return b.data;
}

/* The text of the uncaught error. An instance's own to_str is used when it works. */
static ObjString* errorText(void) {
  Value original = vm.thrown;
  if (IS_STRING(original)) return AS_STRING(original);
  if (IS_INSTANCE(original) && !vm.fatal) {
    vm.stackTop = vm.stack; vm.frameCount = 0; vm.handlerCount = 0;
    vm.noToStr = false;
    ObjString* s = valueToString(original);
    vm.thrown = original;
    vm.noToStr = true;
    if (s) return s;
  }
  vm.noToStr = true;
  return valueToString(original);
}

static void reportRuntimeError(void) {
  vm.noToStr = true;
  bool color = fx_isatty(2);
  ObjString* msg = errorText();
  fflush(stdout);
  fprintf(stderr, "%serror%s: %s\n", color ? "\x1b[1;31m" : "", color ? "\x1b[0m" : "", msg->chars);
  if (vm.traceback) fputs(vm.traceback, stderr);
}

static void printJson(int status, const char* errKind) {
  vm.noToStr = true;
  Buffer b; bufInit(&b);
  bufStr(&b, "{\"output\":");
  jsonQuote(&b, vm.out.data ? vm.out.data : "", vm.out.len);
  bufStr(&b, ",\"error\":");
  if (status == 0) bufStr(&b, "null");
  else if (status == 65) {
    bufStr(&b, "{\"kind\":\"syntax\",\"message\":");
    jsonQuote(&b, compileErrorMsg, (int)strlen(compileErrorMsg));
    bufPrintf(&b, ",\"line\":%d,\"col\":%d}", compileErrorLine, compileErrorCol);
  } else {
    ObjString* msg = errorText();
    bufStr(&b, "{\"kind\":\"");
    bufStr(&b, errKind);
    bufStr(&b, "\",\"message\":");
    jsonQuote(&b, msg->chars, msg->length);
    bufPrintf(&b, ",\"line\":%d,\"trace\":", vm.errorLine);
    jsonQuote(&b, vm.traceback ? vm.traceback : "", vm.traceback ? (int)strlen(vm.traceback) : 0);
    bufChar(&b, '}');
  }
  bufStr(&b, ",\"turtle\":");
  turtleToJson(&b);
  bufStr(&b, "}\n");
  fwrite(b.data, 1, (size_t)b.len, stdout);
  bufFree(&b);
}

static bool useCCompiler = false;   /* --c-compiler: compile with the compiler written in C instead of the one written in Faxal */

/* Switches every later compile to the compiler written in Faxal (the default). */
static bool startSelfHosted(void) {
  if (useCCompiler) return true;
  if (enableSelfHostedCompiler()) return true;
  reportRuntimeError();
  return false;
}

static const struct { const char* command; const char* tool; } TOOLS[] = {
  {"fmt", "tools/fmt"}, {"test", "tools/test"}, {"init", "tools/init"}, {"fxc", "tools/fxc"}, {"lsp", "tools/lsp"},
  {"add", "tools/pkg"}, {"remove", "tools/pkg"}, {"install", "tools/pkg"}, {"list", "tools/pkg"},
};

static const char* toolFor(const char* command) {
  for (size_t i = 0; i < sizeof TOOLS / sizeof TOOLS[0]; i++) if (!strcmp(TOOLS[i].command, command)) return TOOLS[i].tool;
  return NULL;
}

/* A program made by `faxal build`: everything on the command line belongs to the program. */
static int runBundled(int argc, char** argv) {
  vm.scriptArgc = argc - 1;
  vm.scriptArgv = argv + 1;
  registerBuiltins();
  char path[PATH_MAX];
  snprintf(path, sizeof path, "/bundle/%s", vm.bundle[0].path);
  ObjModule* mod = loadMainModule(path);
  Value osv;
  if (mapGet(&vm.builtins, OBJ_VAL(cstring("os")), &osv) && IS_MAP(osv))
    defineValue(&AS_MAP(osv)->map, "script", OBJ_VAL(mod->path));
  int status;
  if (vm.bundle[0].isBytecode) {
    char err[400];
    ObjFunction* f = bytecodeRead((const unsigned char*)vm.bundle[0].source, vm.bundle[0].length, mod, NULL, 0, err, sizeof err);
    if (!f) { fprintf(stderr, "faxal: this program's bytecode is invalid: %s\n", err); return EX_DATAERR; }
    status = runFunction(f);
  } else {
    status = interpret(vm.bundle[0].source, mod, NULL);
  }
  if (status == EX_SOFTWARE) reportRuntimeError();
  fflush(stdout);
  return status;
}

static int repl(void) {
  printf("Faxal %s  (type exit() or press Ctrl-D to quit)\n", FAXAL_VERSION);
  ObjModule* mod = loadMainModule("<repl>");
  if (!startSelfHosted()) return EX_SOFTWARE;
  vm.replMode = true;
  Buffer input; bufInit(&input);
  char line[4096];
  bool more = false;
  for (;;) {
    fputs(more ? "... " : ">>> ", stdout);
    fflush(stdout);
    if (!fgets(line, sizeof line, stdin)) { fputc('\n', stdout); break; }
    bufStr(&input, line);

    bool needMore = false;
    compileQuiet = true;
    ObjFunction* f = compile(input.data, mod, &needMore);
    compileQuiet = false;
    if (!f) {
      if (needMore) { more = true; continue; }
      compile(input.data, mod, NULL); /* again, this time printing the error */
    } else if (runFunction(f) != 0) {
      reportRuntimeError();
    }
    fflush(stdout);
    input.len = 0; if (input.data) input.data[0] = '\0';
    more = false;
  }
  bufFree(&input);
  return 0;
}

int main(int argc, char** argv) {
  fx_binary_stdio();
  vmInit();
  if (loadBundleFromSelf()) return runBundled(argc, argv);
  bool check = false, doRepl = false, compileMode = false, dumpMode = false, buildMode = false;
  int buildFirst = 0;
  const char* emitC = NULL;
  const char* outPath = NULL;
  useCCompiler = getenv("FAXAL_C_COMPILER") != NULL;
  const char* svgPath = NULL;
  const char* evalCode = NULL;
  const char* script = NULL;
  const char* tool = NULL;
  int runWord = 0;
  int scriptArgStart = argc;

  for (int i = 1; i < argc; i++) {
    const char* a = argv[i];
    if (!strcmp(a, "--help") || !strcmp(a, "-h")) { usage(stdout); return 0; }
    else if (!strcmp(a, "--version") || !strcmp(a, "-v")) { printf("faxal %s\n", FAXAL_VERSION); return 0; }
    else if (!strcmp(a, "--dump")) vm.dumpCode = true;
    else if (!strcmp(a, "--sandbox")) vm.sandbox = true;
    else if (!strcmp(a, "--json")) vm.jsonMode = true;
    else if (!strcmp(a, "--c-compiler")) useCCompiler = true;
    else if (!strcmp(a, "--self-hosted")) useCCompiler = false;   /* the default now; kept so old command lines still work */
    else if (!strcmp(a, "--svg") && i + 1 < argc) svgPath = argv[++i];
    else if (!strcmp(a, "-e") && i + 1 < argc) { evalCode = argv[++i]; scriptArgStart = i + 1; break; }
    else if (!strcmp(a, "repl") && !script) doRepl = true;
    else if (!strcmp(a, "check") && !script) check = true;
    else if (!strcmp(a, "compile") && !script) compileMode = true;
    else if (!strcmp(a, "dump") && !script) dumpMode = true;
    else if (!strcmp(a, "-o") && i + 1 < argc) outPath = argv[++i];
    else if (!strcmp(a, "--emit-c") && i + 1 < argc) emitC = argv[++i];
    else if (!strcmp(a, "build") && !script) { buildMode = true; buildFirst = i + 1; break; }
    else if (!strcmp(a, "run") && !script) { runWord = i; continue; }
    else if (!script && !tool && toolFor(a) && !strchr(a, '.')) { tool = toolFor(a); scriptArgStart = i; break; }
    else if (a[0] == '-' && a[1] && strcmp(a, "-") != 0) { fprintf(stderr, "faxal: unknown option '%s'\n\n", a); usage(stderr); return EX_USAGE; }
    else { script = a; scriptArgStart = i + 1; break; }
  }

  if (vm.sandbox) { vm.maxSteps = 30000000; vm.maxMemory = 96u * 1024 * 1024; vm.maxOutput = 256 * 1024; }
  if (vm.jsonMode) vm.sandbox = vm.sandbox; /* json output does not imply sandboxing; the website passes both */

  if (compileMode && script) {   /* faxal compile file.fx -o out.fxc */
    for (int i = scriptArgStart; i + 1 < argc; i++) {
      if (!strcmp(argv[i], "-o")) outPath = argv[i + 1];
      else if (!strcmp(argv[i], "--emit-c")) emitC = argv[i + 1];
    }
  }
  vm.scriptArgc = argc - scriptArgStart;
  vm.scriptArgv = argv + scriptArgStart;
  registerBuiltins();

  if (buildMode) {
    loadMainModule("<build>");
    if (!startSelfHosted()) return EX_SOFTWARE;
    return cmdBuild(argc, argv, buildFirst);
  }
  if (runWord && !script && !evalCode && !tool) { tool = "tools/run"; scriptArgStart = runWord; vm.scriptArgc = argc - scriptArgStart; vm.scriptArgv = argv + scriptArgStart; }
  if (doRepl) return repl();
  if (!script && !evalCode && !tool) {
    if (fx_isatty(0)) return repl();
    script = "-";
  }

  char* source;
  size_t sourceLen = 0;
  bool isBytecode = false;
  const char* name;
  char nameBuf[PATH_MAX * 2];
  if (tool) {
    const EmbeddedFile* e = findEmbedded(tool);
    if (!e) { fprintf(stderr, "faxal: the tool '%s' is missing\n", tool); return EX_SOFTWARE; }
    source = malloc(e->length + 1);   /* the tool is compiled bytecode inside faxal itself */
    memcpy(source, e->data, e->length);
    source[e->length] = '\0';
    sourceLen = e->length;
    isBytecode = true;
    name = "<tool>";
  }
  else if (evalCode) { source = strdup(evalCode); name = "<eval>"; }
  else if (!strcmp(script, "-")) { source = readStdin(); name = "<stdin>"; }
  else {
    unsigned char* bytes = readFileBytes(script, &sourceLen);
    if (!bytes) { fprintf(stderr, "faxal: cannot open '%s' (it is not a file, and not a faxal command)\n", script); return EX_IOERR; }
    source = (char*)bytes;
    name = script;
    if (bytecodeLooksLike(bytes, sourceLen)) {
      /* a compiled program: it keeps the name of its source file, placed next to the .fxc so that imports resolve */
      isBytecode = true;
      char recorded[PATH_MAX], absolute[PATH_MAX];
      if (bytecodeSourceName(bytes, sourceLen, recorded, sizeof recorded) && recorded[0] && fx_realpath(script, absolute)) {
        char* slash = strrchr(absolute, '/');
        if (slash) *slash = '\0';
        const char* base = strrchr(recorded, '/');
        snprintf(nameBuf, sizeof nameBuf, "%s/%s", absolute, base ? base + 1 : recorded);
        name = nameBuf;
      }
    }
  }

  /* leave early without leaking the program text */
#define BAIL(code) do { free(source); vmFree(); return (code); } while (0)
  ObjModule* mod = loadMainModule(name);
  if (!startSelfHosted()) BAIL(EX_SOFTWARE);
  Value osv;
  if (mapGet(&vm.builtins, OBJ_VAL(cstring("os")), &osv) && IS_MAP(osv))
    defineValue(&AS_MAP(osv)->map, "script", OBJ_VAL(mod->path));
  int status;
  if (isBytecode) {
    char err[400];
    ObjFunction* f = bytecodeRead((const unsigned char*)source, sourceLen, mod, NULL, 0, err, sizeof err);
    if (!f) { fprintf(stderr, "faxal: cannot use '%s': %s\n", script ? script : tool, err); BAIL(EX_DATAERR); }
    if (compileMode) { fprintf(stderr, "faxal: '%s' is already compiled\n", script); BAIL(EX_USAGE); }
    if (dumpMode) { bytecodeDump(f); status = 0; }
    else if (check) { printf("%s: ok (verified)\n", script); status = 0; }
    else status = runFunction(f);
  } else if (compileMode) {
    ObjFunction* f = compile(source, mod, NULL);
    if (!f) BAIL(EX_DATAERR);
    char defaultOut[PATH_MAX];
    if (!outPath) {
      snprintf(defaultOut, sizeof defaultOut, "%s", script ? script : "out");
      size_t n = strlen(defaultOut);
      if (n > 3 && !strcmp(defaultOut + n - 3, ".fx")) defaultOut[n - 3] = '\0';
      strncat(defaultOut, ".fxc", sizeof defaultOut - strlen(defaultOut) - 1);
      outPath = defaultOut;
    }
    Buffer b; bufInit(&b);
    const char* base = script && strrchr(script, '/') ? strrchr(script, '/') + 1 : (script ? script : "out.fx");
    if (!bytecodeWrite(f, base, &b)) { fputs("faxal: cannot write this program as bytecode\n", stderr); bufFree(&b); BAIL(EX_SOFTWARE); }
    if (emitC) {
      /* print a C array instead of writing a file: this is how the standard library is built into faxal (make embed) */
      printf("static const unsigned char %s[] = {", emitC);
      for (int k = 0; k < b.len; k++) printf("%s0x%02x,", k % 16 == 0 ? "\n  " : " ", (unsigned char)b.data[k]);
      printf("\n};\n");
      bufFree(&b);
      status = 0;
      goto finished;
    }
    FILE* out = fopen(outPath, "wb");
    if (!out) { fprintf(stderr, "faxal: cannot write '%s'\n", outPath); bufFree(&b); BAIL(EX_IOERR); }
    fwrite(b.data, 1, (size_t)b.len, out);
    fclose(out);
    printf("compiled %s -> %s (%d bytes)\n", script ? script : "<stdin>", outPath, b.len);
    bufFree(&b);
    status = 0;
  } else if (dumpMode) {
    vm.dumpCode = true;
    status = compile(source, mod, NULL) ? 0 : EX_DATAERR;
  } else if (check) {
    status = compile(source, mod, NULL) ? 0 : EX_DATAERR;
    if (status == 0) printf("%s: ok\n", name);
  } else {
    status = interpret(source, mod, NULL);
  }

finished:;
  const char* kind = vm.fatal ? "limit" : "runtime";
  if (vm.jsonMode) printJson(status, kind);
  else if (status == EX_SOFTWARE) reportRuntimeError();
  if (svgPath && !vm.sandbox && status == 0) {
    Buffer b; bufInit(&b);
    turtleToSvg(&b);
    FILE* f = fopen(svgPath, "wb");
    if (f) { fwrite(b.data, 1, (size_t)b.len, f); fclose(f); } else fprintf(stderr, "faxal: cannot write '%s'\n", svgPath);
    bufFree(&b);
  }
  fflush(stdout);
  free(source);
  vmFree();
  return vm.jsonMode ? 0 : status;
#undef BAIL
}
