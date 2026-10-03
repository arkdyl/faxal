/* selfhost.c: running programs compiled by the compiler that is written in Faxal (lib/std/compiler.fx).
 *
 * With --self-hosted, compile() hands the source text to the Faxal compiler (a Faxal function running on this
 * very VM). It answers with plain data (see std/bytecode.fx: to_wire): either a list of functions with their
 * bytecode and constants, or a list of errors. This file turns that data into the VM's own function objects.
 *
 * The loader checks the shape of the data, but it does not verify the bytecode itself: it is meant for the
 * output of the Faxal compiler, not for programs from untrusted sources.
 */
#include "faxal.h"

static bool field(Map* m, const char* name, Value* out) { return mapGet(m, OBJ_VAL(cstring(name)), out); }

static bool whole(Value v, long min, long max, long* out) {
  if (!IS_NUM(v) || AS_NUM(v) != (double)(long)AS_NUM(v) || AS_NUM(v) < (double)min || AS_NUM(v) > (double)max) return false;
  *out = (long)AS_NUM(v);
  return true;
}

typedef struct { int function; int slot; int target; } Link;

/* Builds the functions of a program. Returns the main script function, or NULL if the data is malformed. */
static ObjFunction* loadProgram(Value tree, ObjModule* module) {
  Value v;
  if (!IS_MAP(tree) || !field(&AS_MAP(tree)->map, "functions", &v) || !IS_LIST(v) || AS_LIST(v)->count == 0) return NULL;
  ObjList* list = AS_LIST(v);
  int count = list->count;
  ObjFunction** fns = calloc((size_t)count, sizeof(ObjFunction*));
  Link* links = NULL;
  int linkCount = 0, linkCap = 0;
  ObjFunction* main = NULL;

  for (int i = 0; i < count; i++) {
    Value fv = list->items[i];
    if (!IS_MAP(fv)) goto bad;
    Map* fm = &AS_MAP(fv)->map;
    ObjFunction* f = newFunction();
    fns[i] = f;
    f->module = module;

    long n;
    Value x;
    if (!field(fm, "name", &x)) goto bad;
    if (IS_STRING(x)) f->name = AS_STRING(x); else if (!IS_NIL(x)) goto bad;
    if (!field(fm, "arity", &x) || !whole(x, 0, 255, &n)) goto bad;
    f->arity = (int)n;
    if (!field(fm, "min_arity", &x) || !whole(x, 0, 255, &n)) goto bad;
    f->minArity = (int)n;
    if (!field(fm, "upvalues", &x) || !whole(x, 0, 256, &n)) goto bad;
    f->upvalueCount = (int)n;
    if (!field(fm, "script", &x) || !IS_BOOL(x)) goto bad;
    f->isScript = AS_BOOL(x);

    Value code, lines, consts;
    if (!field(fm, "code", &code) || !IS_LIST(code) || !field(fm, "lines", &lines) || !IS_LIST(lines) ||
        AS_LIST(code)->count != AS_LIST(lines)->count || !field(fm, "constants", &consts) || !IS_LIST(consts)) goto bad;
    for (int k = 0; k < AS_LIST(code)->count; k++) {
      long byte, line;
      if (!whole(AS_LIST(code)->items[k], 0, 255, &byte) || !whole(AS_LIST(lines)->items[k], 0, 2147483647, &line)) goto bad;
      chunkWrite(&f->chunk, (uint8_t)byte, (int)line);
    }
    for (int k = 0; k < AS_LIST(consts)->count; k++) {
      Value c = AS_LIST(consts)->items[k];
      if (IS_NUM(c) || IS_STRING(c)) chunkAddConstant(&f->chunk, c);
      else if (IS_MAP(c)) {
        Value t;
        if (field(&AS_MAP(c)->map, "fn", &t) && whole(t, 0, count - 1, &n)) {
          if (linkCount == linkCap) { linkCap = linkCap ? linkCap * 2 : 16; links = realloc(links, sizeof(Link) * (size_t)linkCap); }
          links[linkCount++] = (Link){ i, chunkAddConstant(&f->chunk, NIL_VAL), (int)n };
        } else if (field(&AS_MAP(c)->map, "num", &t) && IS_STRING(t)) {
          const char* s = AS_CSTRING(t);
          chunkAddConstant(&f->chunk, NUM_VAL(!strcmp(s, "nan") ? (0.0 / 0.0) : !strcmp(s, "-inf") ? -(1.0 / 0.0) : (1.0 / 0.0)));
        } else goto bad;
      } else goto bad;
    }
  }
  for (int k = 0; k < linkCount; k++) {
    if (!fns[links[k].target]) goto bad;
    fns[links[k].function]->chunk.constants.values[links[k].slot] = OBJ_VAL(fns[links[k].target]);
  }
  main = fns[count - 1];
  if (!main->isScript) main = NULL;
  if (main) {
    char err[400];
    if (!verifyProgram(fns, count, err, sizeof err)) { fprintf(stderr, "faxal: %s\n", err); main = NULL; }
  }
  if (main && vm.dumpCode) for (int i = 0; i < count; i++) disassembleFunction(fns[i]);
bad:
  free(links);
  free(fns);
  return main;
}

/* The compile() used when --self-hosted is on. */
ObjFunction* compileWithFaxal(const char* source, ObjModule* module, bool* needMoreInput) {
  if (needMoreInput) *needMoreInput = false;
  compileErrorLine = 0; compileErrorCol = 0; compileErrorMsg[0] = '\0';

  Value args[3] = { OBJ_VAL(newString(source, (int)strlen(source))), BOOL_VAL(vm.replMode), BOOL_VAL(compileCollectImports) };
  Value result;
  if (!vmCall(vm.fxCompile, 3, args, &result) || !IS_MAP(result)) {
    printCompileError(module ? module->path->chars : "<script>", 1, 1, "", 0, 1, "The compiler written in Faxal failed (this is a bug in std/compiler)");
    return NULL;
  }
  Map* r = &AS_MAP(result)->map;
  Value ok;
  field(r, "ok", &ok);
  if (!IS_BOOL(ok) || !AS_BOOL(ok)) {
    Value errors, eof;
    if (needMoreInput && field(r, "eof", &eof) && IS_BOOL(eof)) *needMoreInput = AS_BOOL(eof);
    bool first = true;
    if (field(r, "errors", &errors) && IS_LIST(errors)) {
      for (int i = 0; i < AS_LIST(errors)->count; i++) {
        Value ev = AS_LIST(errors)->items[i];
        Value msg, line, col, text, length;
        if (!IS_MAP(ev)) continue;
        Map* e = &AS_MAP(ev)->map;
        if (!field(e, "message", &msg) || !IS_STRING(msg) || !field(e, "line", &line) || !IS_NUM(line) || !field(e, "col", &col) ||
            !IS_NUM(col) || !field(e, "text", &text) || !IS_STRING(text) || !field(e, "length", &length) || !IS_NUM(length)) continue;
        if (first) {
          first = false;
          compileErrorLine = (int)AS_NUM(line);
          compileErrorCol = (int)AS_NUM(col);
          snprintf(compileErrorMsg, sizeof compileErrorMsg, "%s", AS_CSTRING(msg));
        }
        printCompileError(module ? module->path->chars : "<script>", (int)AS_NUM(line), (int)AS_NUM(col), AS_CSTRING(text),
                          AS_STRING(text)->length, (int)AS_NUM(length), AS_CSTRING(msg));
      }
    }
    return NULL;
  }

  Value program, imports;
  if (!field(r, "program", &program)) return NULL;
  if (compileCollectImports && field(r, "imports", &imports) && IS_LIST(imports)) {
    for (int i = 0; i < AS_LIST(imports)->count; i++) {
      if (!IS_STRING(AS_LIST(imports)->items[i])) continue;
      compiledImports = realloc(compiledImports, sizeof(char*) * (size_t)(compiledImportCount + 1));
      compiledImports[compiledImportCount++] = strdup(AS_CSTRING(AS_LIST(imports)->items[i]));
    }
  }
  ObjFunction* f = loadProgram(program, module);
  if (!f) printCompileError(module ? module->path->chars : "<script>", 1, 1, "", 0, 1, "The compiler written in Faxal produced a malformed program (this is a bug in std/compiler)");
  return f;
}

/* Switches every later compile to the compiler written in Faxal. It comes from the faxal program itself, as
 * precompiled bytecode (std/compiler, see tools/embed.fx), so nothing has to be compiled to get started. If it
 * isn't there or can't be loaded, faxal keeps using the compiler written in C and says so. */
bool enableSelfHostedCompiler(void) {
  if (!findEmbedded("std/compiler")) return true;   /* an early build without the embedded library */
  Value exports;
  bool dumping = vm.dumpCode;
  vm.dumpCode = false;
  bool imported = importModule(OBJ_VAL(cstring("std/compiler")), vm.mainModule, &exports);
  vm.dumpCode = dumping;
  Value fn;
  if (imported && IS_MAP(exports) && mapGet(&AS_MAP(exports)->map, OBJ_VAL(cstring("compile_for_vm")), &fn) && IS_CALLABLE(fn)) {
    vm.fxCompile = fn;
    return true;
  }
  if (!imported) {
    ObjString* why = IS_STRING(vm.thrown) ? AS_STRING(vm.thrown) : cstring("unknown error");
    fprintf(stderr, "faxal: warning: the built-in Faxal compiler could not be loaded (%s); using the C compiler. Run: make -C native embed\n", why->chars);
  }
  vm.thrown = NIL_VAL;
  vm.stackTop = vm.stack; vm.frameCount = 0; vm.handlerCount = 0;
  return true;
}
