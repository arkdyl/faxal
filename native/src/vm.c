/* vm.c: the bytecode virtual machine */
#include "faxal.h"
#include <math.h>
#include <limits.h>

extern const MethodDef stringMethods[], listMethods[], mapMethods[], rangeMethods[];

/* ---- friendly hints: "Did you mean 'print'?" ---- */

static int editDistance(const char* a, const char* b) {
  int la = (int)strlen(a), lb = (int)strlen(b);
  if (la > 40 || lb > 40) return 99;
  int prev[42], cur[42];
  for (int j = 0; j <= lb; j++) prev[j] = j;
  for (int i = 1; i <= la; i++) {
    cur[0] = i;
    for (int j = 1; j <= lb; j++) {
      int cost = a[i - 1] == b[j - 1] ? 0 : 1;
      int best = prev[j - 1] + cost;
      if (prev[j] + 1 < best) best = prev[j] + 1;
      if (cur[j - 1] + 1 < best) best = cur[j - 1] + 1;
      cur[j] = best;
    }
    memcpy(prev, cur, sizeof(int) * (size_t)(lb + 1));
  }
  return prev[lb];
}

typedef struct { const char* name; char best[64]; int dist; } Suggest;

static void consider(Suggest* s, const char* cand) {
  if (strcmp(cand, s->name) == 0) return;
  int len = (int)strlen(s->name);
  int limit = len <= 3 ? 1 : len <= 7 ? 2 : 3;
  int d = editDistance(s->name, cand);
  if (d <= limit && d < s->dist) { s->dist = d; snprintf(s->best, sizeof s->best, "%s", cand); }
}

static void considerMap(Suggest* s, Map* m) {
  for (int i = 0; i < m->count; i++)
    if (m->entries[i].live && IS_STRING(m->entries[i].key)) consider(s, AS_CSTRING(m->entries[i].key));
}

static void considerMethods(Suggest* s, const MethodDef* t) { for (; t && t->name; t++) consider(s, t->name); }

static const MethodDef* methodTable(Value r) {
  if (IS_STRING(r)) return stringMethods;
  if (IS_LIST(r)) return listMethods;
  if (IS_MAP(r)) return mapMethods;
  if (IS_RANGE(r)) return rangeMethods;
  return NULL;
}

/* Returns " Did you mean 'x'?" (or "") for a mistyped name. */
static const char* hint(Suggest* s) {
  static char buf[100];
  if (s->dist > 3 || !s->best[0]) return "";
  snprintf(buf, sizeof buf, ". Did you mean '%s'?", s->best);
  return buf;
}

#define MAX_STRING_BYTES (256 * 1024 * 1024)

/* ------------------------------------------------------------------ helpers */

void push(Value v) { *vm.stackTop++ = v; }
Value pop(void) { return *--vm.stackTop; }
static Value peek(int d) { return vm.stackTop[-1 - d]; }

bool throwError(const char* fmt, ...) {
  char buf[600];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
  vm.thrown = OBJ_VAL(newString(buf, (int)strlen(buf)));
  return false;
}

bool vmWrite(const char* s, int n) {
  if (!vm.jsonMode) { fwrite(s, 1, (size_t)n, stdout); return true; }
  if (vm.maxOutput && (size_t)(vm.out.len + n) > vm.maxOutput) {
    vm.fatal = true;
    return throwError("Too much output");
  }
  bufAppend(&vm.out, s, n);
  return true;
}

char* readFile(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  rewind(f);
  if (size < 0 || size > 512L * 1024 * 1024) { fclose(f); return NULL; }
  char* buf = malloc((size_t)size + 1);
  size_t got = fread(buf, 1, (size_t)size, f);
  buf[got] = '\0';
  fclose(f);
  return buf;
}

void defineNative(Map* m, const char* name, NativeFn fn, int minArgs, int maxArgs) {
  mapSet(m, OBJ_VAL(cstring(name)), OBJ_VAL(newNative(name, fn, minArgs, maxArgs)));
}
void defineValue(Map* m, const char* name, Value v) { mapSet(m, OBJ_VAL(cstring(name)), v); }

const MethodDef* findMethod(Value r, ObjString* name) {
  const MethodDef* t = NULL;
  if (IS_STRING(r)) t = stringMethods;
  else if (IS_LIST(r)) t = listMethods;
  else if (IS_MAP(r)) t = mapMethods;
  else if (IS_RANGE(r)) t = rangeMethods;
  if (!t) return NULL;
  for (; t->name; t++) if (strcmp(t->name, name->chars) == 0) return t;
  return NULL;
}

void vmInit(void) {
  memset(&vm, 0, sizeof vm);
  vm.stack = malloc(sizeof(Value) * (STACK_MAX + STACK_SLACK)); /* slack: room for huge list literals */
  vm.stackTop = vm.stack;
  vm.nextGC = 1024 * 1024;
  vm.thrown = NIL_VAL;
  vm.fxCompile = NIL_VAL;
  bufInit(&vm.out);
  mapInit(&vm.builtins);
  mapInit(&vm.modules);
  vm.turtle.down = true; vm.turtle.width = 2;
  vm.turtle.color = strdup("#ffffff");
}

void vmFree(void) {
  mapFree(&vm.builtins);
  mapFree(&vm.modules);
  vm.mainModule = NULL;
  freeObjects();
  free(vm.stack);
  bufFree(&vm.out);
  free(vm.traceback);
  free(vm.turtle.color); free(vm.turtle.background);
  for (int i = 0; i < vm.turtle.count; i++) free(vm.turtle.segs[i].color);
  free(vm.turtle.segs);
  for (int i = 0; i < vm.turtle.shapeCount; i++) { free(vm.turtle.shapes[i].color); free(vm.turtle.shapes[i].text); }
  free(vm.turtle.shapes);
}

ObjModule* loadMainModule(const char* path) {
  char resolved[PATH_MAX];
  const char* name = path;
  if (path[0] != '<' && fx_realpath(path, resolved)) name = resolved;
  ObjModule* m = newModule(cstring(name));
  vm.mainModule = m;
  return m;
}

/* ---------------------------------------------------------------- upvalues */

static ObjUpvalue* captureUpvalue(Value* local) {
  ObjUpvalue *prev = NULL, *u = vm.openUpvalues;
  while (u && u->location > local) { prev = u; u = u->next; }
  if (u && u->location == local) return u;
  ObjUpvalue* created = newUpvalue(local);
  created->next = u;
  if (prev) prev->next = created; else vm.openUpvalues = created;
  return created;
}

static void closeUpvalues(Value* last) {
  while (vm.openUpvalues && vm.openUpvalues->location >= last) {
    ObjUpvalue* u = vm.openUpvalues;
    u->closed = *u->location;
    u->location = &u->closed;
    vm.openUpvalues = u->next;
  }
}

/* --------------------------------------------------------------- tracebacks */

static void captureTraceback(void) {
  Buffer b; bufInit(&b);
  for (int i = vm.frameCount - 1; i >= 0; i--) {
    CallFrame* f = &vm.frames[i];
    ObjFunction* fn = f->closure->function;
    int line = fn->chunk.lines[f->ip - fn->chunk.code - 1 < 0 ? 0 : (int)(f->ip - fn->chunk.code - 1)];
    if (i == vm.frameCount - 1) vm.errorLine = line;
    bufPrintf(&b, "  at %s (%s:%d)\n", fn->name ? fn->name->chars : (fn->isScript ? "<script>" : "<lambda>"),
              fn->module ? fn->module->path->chars : "?", line);
    if (i == vm.frameCount - 1 - 20 && i > 5) { bufStr(&b, "  ...\n"); i = 5; }
  }
  free(vm.traceback);
  vm.traceback = b.data ? b.data : strdup("");
}

/* -------------------------------------------------------------------- calls */

static bool callClosure(ObjClosure* c, int argc) {
  ObjFunction* fn = c->function;
  if (argc < fn->minArity || argc > fn->arity) {
    const char* name = fn->name ? fn->name->chars : "function";
    if (fn->minArity == fn->arity) return throwError("%s() takes %d argument%s but got %d", name, fn->arity, fn->arity == 1 ? "" : "s", argc);
    return throwError("%s() takes %d to %d arguments but got %d", name, fn->minArity, fn->arity, argc);
  }
  if (vm.frameCount == FRAMES_MAX || vm.stackTop + 300 > vm.stack + STACK_MAX) return throwError("Stack overflow (too much recursion)");
  CallFrame* f = &vm.frames[vm.frameCount++];
  f->closure = c;
  f->ip = c->function->chunk.code;
  f->slots = vm.stackTop - argc - 1;
  for (int i = argc; i < fn->arity; i++) push(NIL_VAL); /* missing arguments start as nil; defaults fill them in */
  return true;
}

static bool checkArity(const char* name, int argc, int min, int max) {
  if (argc >= min && (max < 0 || argc <= max)) return true;
  if (min == max) return throwError("%s() takes %d argument%s but got %d", name, min, min == 1 ? "" : "s", argc);
  if (max < 0) return throwError("%s() takes at least %d argument%s but got %d", name, min, min == 1 ? "" : "s", argc);
  return throwError("%s() takes %d to %d arguments but got %d", name, min, max, argc);
}

static bool invokeFromClass(ObjClass* klass, ObjString* name, int argc) {
  Value m;
  if (!mapGet(&klass->methods, OBJ_VAL(name), &m)) {
    Suggest s = { name->chars, "", 99 };
    considerMap(&s, &klass->methods);
    return throwError("%s has no method '%s'%s", klass->name->chars, name->chars, hint(&s));
  }
  return callClosure(AS_CLOSURE(m), argc);
}

static bool callValue(Value callee, int argc) {
  if (IS_OBJ(callee)) {
    if (OBJ_TYPE(callee) == OBJ_BOUND_METHOD) {
      ObjBoundMethod* b = AS_BOUND(callee);
      vm.stackTop[-argc - 1] = b->receiver;
      return callClosure(b->method, argc);
    }
    if (OBJ_TYPE(callee) == OBJ_CLASS) {
      ObjClass* k = AS_CLASS(callee);
      vm.stackTop[-argc - 1] = OBJ_VAL(newInstance(k));
      Value init;
      if (mapGet(&k->methods, OBJ_VAL(cstring("init")), &init)) return callClosure(AS_CLOSURE(init), argc);
      if (argc != 0) return throwError("%s() takes 0 arguments but got %d (the class has no init method)", k->name->chars, argc);
      return true;
    }
    if (OBJ_TYPE(callee) == OBJ_CLOSURE) return callClosure(AS_CLOSURE(callee), argc);
    if (OBJ_TYPE(callee) == OBJ_NATIVE) {
      ObjNative* n = AS_NATIVE(callee);
      if (!checkArity(n->name, argc, n->minArgs, n->maxArgs)) return false;
      Value result = NIL_VAL;
      if (!n->fn(argc, vm.stackTop - argc, &result)) return false;
      vm.stackTop -= argc + 1;
      push(result);
      return true;
    }
  }
  return throwError("Can only call functions, but this is %s", typeName(callee));
}

static bool run(int base);

/* Natives (map, sort, to_str, ...) call back into the VM, which nests another run() on the C stack. */
#define MAX_NATIVE_DEPTH 200

bool vmCall(Value fn, int argc, Value* argv, Value* out) {
  if (vm.nativeDepth >= MAX_NATIVE_DEPTH) return throwError("Stack overflow (too much recursion)");
  push(fn);
  for (int i = 0; i < argc; i++) push(argv[i]);
  int before = vm.frameCount;
  vm.nativeDepth++;
  bool ok = callValue(fn, argc) && (vm.frameCount == before || run(before));
  vm.nativeDepth--;
  if (!ok) return false;
  *out = pop();
  return true;
}

/* ---------------------------------------------------------------- operators */

static bool tooBig(long long bytes) {
  if (bytes > MAX_STRING_BYTES || (vm.maxMemory && (size_t)bytes > vm.maxMemory / 2)) { vm.fatal = vm.maxMemory != 0; return throwError(vm.maxMemory ? "Out of memory" : "String is too long"); }
  return false;
}

static bool concat(Value a, Value b, Value* out) {
  ObjString* sa = valueToString(a);
  if (!sa) return false;
  push(OBJ_VAL(sa)); /* keep it alive: converting b may run user code and trigger a collection */
  ObjString* sb = valueToString(b);
  pop();
  if (!sb) return false;
  long long len = (long long)sa->length + sb->length;
  if (tooBig(len)) return false;
  char* buf = malloc((size_t)len + 1);
  memcpy(buf, sa->chars, (size_t)sa->length);
  memcpy(buf + sa->length, sb->chars, (size_t)sb->length);
  *out = OBJ_VAL(newString(buf, (int)len));
  free(buf);
  return true;
}

static bool repeatString(ObjString* s, double times, Value* out) {
  if (times < 0 || times != floor(times)) return throwError("Can only repeat a string a whole, non-negative number of times");
  if (s->length == 0 || times == 0) { *out = OBJ_VAL(newString("", 0)); return true; }
  if (tooBig((long long)fmin(times * s->length, 1e18))) return false;
  int n = (int)times;
  char* buf = malloc((size_t)s->length * (size_t)n + 1);
  for (int i = 0; i < n; i++) memcpy(buf + (size_t)i * (size_t)s->length, s->chars, (size_t)s->length);
  *out = OBJ_VAL(newString(buf, s->length * n));
  free(buf);
  return true;
}

static bool compareValues(Value a, Value b, int* result) {
  if (IS_NUM(a) && IS_NUM(b)) { *result = AS_NUM(a) < AS_NUM(b) ? -1 : AS_NUM(a) > AS_NUM(b) ? 1 : 0; return true; }
  if (IS_STRING(a) && IS_STRING(b)) {
    ObjString *x = AS_STRING(a), *y = AS_STRING(b);
    int n = x->length < y->length ? x->length : y->length;
    int c = memcmp(x->chars, y->chars, (size_t)n);
    *result = c ? (c < 0 ? -1 : 1) : (x->length < y->length ? -1 : x->length > y->length ? 1 : 0);
    return true;
  }
  return throwError("Can't compare %s with %s", typeName(a), typeName(b));
}

static bool checkIndex(Value idx, int count, int* out, const char* what) {
  if (!IS_NUM(idx) || AS_NUM(idx) != floor(AS_NUM(idx))) return throwError("%s index must be a whole number, got %s", what, typeName(idx));
  double d = AS_NUM(idx);
  if (d < 0) d += count;
  if (d < 0 || d >= count) {
    char n[32]; formatNumber(AS_NUM(idx), n);
    return throwError("%s index %s is out of range (length %d)", what, n, count);
  }
  *out = (int)d;
  return true;
}

static bool getIndex(Value obj, Value idx, Value* out) {
  int i;
  if (IS_LIST(obj)) { if (!checkIndex(idx, AS_LIST(obj)->count, &i, "List")) return false; *out = AS_LIST(obj)->items[i]; return true; }
  if (IS_STRING(obj)) { if (!checkIndex(idx, AS_STRING(obj)->length, &i, "String")) return false; *out = OBJ_VAL(newString(AS_CSTRING(obj) + i, 1)); return true; }
  if (IS_RANGE(obj)) { ObjRange* r = AS_RANGE(obj); if (!checkIndex(idx, rangeLength(r), &i, "Range")) return false; *out = NUM_VAL(r->start + i * r->step); return true; }
  if (IS_MAP(obj)) {
    if (!validKey(idx)) return throwError("Map keys must be strings, numbers or booleans, not %s", typeName(idx));
    if (!mapGet(&AS_MAP(obj)->map, idx, out)) *out = NIL_VAL;
    return true;
  }
  return throwError("Can't index into %s", typeName(obj));
}

static bool setIndex(Value obj, Value idx, Value v) {
  int i;
  if (IS_LIST(obj)) { if (!checkIndex(idx, AS_LIST(obj)->count, &i, "List")) return false; AS_LIST(obj)->items[i] = v; return true; }
  if (IS_MAP(obj)) {
    if (!validKey(idx)) return throwError("Map keys must be strings, numbers or booleans, not %s", typeName(idx));
    mapSet(&AS_MAP(obj)->map, idx, v);
    return true;
  }
  if (IS_STRING(obj)) return throwError("Strings can't be changed in place. Build a new string instead");
  return throwError("Can't assign into %s", typeName(obj));
}

static bool sliceBound(Value v, int len, int dflt, int* out) {
  if (IS_NIL(v)) { *out = dflt; return true; }
  if (!IS_NUM(v)) return throwError("Slice bounds must be numbers, got %s", typeName(v));
  double d = floor(AS_NUM(v));
  if (isnan(d)) d = 0;
  if (d < 0) d += len;
  *out = d < 0 ? 0 : d > len ? len : (int)d;
  return true;
}

static bool sliceValue(Value obj, Value s, Value e, Value* out) {
  int len, a, b;
  if (IS_LIST(obj)) len = AS_LIST(obj)->count;
  else if (IS_STRING(obj)) len = AS_STRING(obj)->length;
  else return throwError("Can't slice %s", typeName(obj));
  if (!sliceBound(s, len, 0, &a) || !sliceBound(e, len, len, &b)) return false;
  if (b < a) b = a;
  if (IS_STRING(obj)) { *out = OBJ_VAL(newString(AS_CSTRING(obj) + a, b - a)); return true; }
  ObjList* l = newList();
  *out = OBJ_VAL(l);
  for (int i = a; i < b; i++) listPush(l, AS_LIST(obj)->items[i]);
  return true;
}

static bool containsValue(Value needle, Value hay, bool* result) {
  if (IS_STRING(hay)) {
    if (!IS_STRING(needle)) return throwError("'in' on a string needs a string on the left, got %s", typeName(needle));
    *result = strstr(AS_CSTRING(hay), AS_CSTRING(needle)) != NULL;
    return true;
  }
  if (IS_LIST(hay)) {
    ObjList* l = AS_LIST(hay);
    *result = false;
    for (int i = 0; i < l->count && !*result; i++) *result = valuesEqual(l->items[i], needle);
    return true;
  }
  if (IS_MAP(hay)) { Value dummy; *result = validKey(needle) && mapGet(&AS_MAP(hay)->map, needle, &dummy); return true; }
  if (IS_RANGE(hay)) {
    ObjRange* r = AS_RANGE(hay);
    *result = false;
    if (IS_NUM(needle)) {
      double x = AS_NUM(needle), k = (x - r->start) / r->step;
      *result = k >= 0 && k < rangeLength(r) && k == floor(k);
    }
    return true;
  }
  return throwError("'in' can't search inside %s", typeName(hay));
}

/* -------------------------------------------------------------------- imports */

const EmbeddedFile* findEmbedded(const char* name) {
  for (int i = 0; i < embeddedCount; i++) if (strcmp(embeddedFiles[i].name, name) == 0) return &embeddedFiles[i];
  return NULL;
}

/* Cleans up an absolute path: resolves "." and ".." and repeated slashes. */
static void normalizePath(const char* in, char* out, size_t cap) {
  char tmp[PATH_MAX * 2];
  snprintf(tmp, sizeof tmp, "%s", in);
  const char* parts[256];
  int n = 0;
  for (char* tok = strtok(tmp, "/"); tok && n < 256; tok = strtok(NULL, "/")) {
    if (!strcmp(tok, ".")) continue;
    if (!strcmp(tok, "..")) { if (n > 0) n--; continue; }
    parts[n++] = tok;
  }
  if (n == 0) { snprintf(out, cap, "/"); return; }
  size_t len = 0;
  out[0] = '\0';
  for (int i = 0; i < n && len < cap; i++) len += (size_t)snprintf(out + len, cap - len, "/%s", parts[i]);
}

typedef bool (*ExistsFn)(const char* path, char* resolved);

static bool fsExists(const char* path, char* resolved) {
  return fx_realpath(path, resolved) && fx_is_file(resolved);
}

static bool bundleExists(const char* path, char* resolved) {
  char norm[PATH_MAX * 2], full[PATH_MAX * 2];
  normalizePath(path, norm, sizeof norm);
  for (int i = 0; i < vm.bundleCount; i++) {
    snprintf(full, sizeof full, "/bundle/%s", vm.bundle[i].path);
    if (strcmp(norm, full) == 0) { snprintf(resolved, PATH_MAX, "%s", full); return true; }
  }
  return false;
}

/* Finds the file for `import "rel"`: next to the importing file first, then in fx_modules/ folders
   of this and every parent folder (that is where `faxal add` puts packages). */
static bool resolveModule(const char* rel, ObjModule* importer, ExistsFn exists, char* resolved) {
  static const char* exts[] = { "", ".fx", ".fxc" };
  char dir[PATH_MAX], cand[PATH_MAX * 2];
  snprintf(dir, sizeof dir, "%s", importer->path->chars);
  if (dir[0] == '/') { char* slash = strrchr(dir, '/'); *slash = '\0'; if (!dir[0]) strcpy(dir, "/"); }
  else strcpy(dir, ".");

  if (rel[0] == '/') {
    for (int i = 0; i < 3; i++) { snprintf(cand, sizeof cand, "%s%s", rel, exts[i]); if (exists(cand, resolved)) return true; }
    return false;
  }
  for (int i = 0; i < 3; i++) {
    snprintf(cand, sizeof cand, "%s/%s%s", dir, rel, exts[i]);
    if (exists(cand, resolved)) return true;
  }
  size_t relLen = strlen(rel);
  if (relLen > 3 && strcmp(rel + relLen - 3, ".fx") == 0) {   /* import "lib.fx" can also be satisfied by a compiled lib.fxc */
    snprintf(cand, sizeof cand, "%s/%sc", dir, rel);
    if (exists(cand, resolved)) return true;
  }
  if (strncmp(rel, "./", 2) == 0 || strncmp(rel, "../", 3) == 0) return false;

  char d[PATH_MAX];
  snprintf(d, sizeof d, "%s", dir);
  for (int depth = 0; depth < 32; depth++) {
    static const char* forms[] = { "%s/fx_modules/%s.fx", "%s/fx_modules/%s/main.fx", "%s/fx_modules/%s", "%s/fx_modules/%s.fxc", "%s/fx_modules/%s/main.fxc" };
    for (int f = 0; f < 5; f++) {
      snprintf(cand, sizeof cand, forms[f], d, rel);
      if (exists(cand, resolved)) return true;
    }
    if (d[0] == '/') {
      if (strcmp(d, "/") == 0) break;
      char* slash = strrchr(d, '/');
      if (slash == d) strcpy(d, "/"); else *slash = '\0';
    } else {
      size_t n = strlen(d);
      if (n + 4 >= sizeof d) break;
      strcat(d, "/..");
    }
  }
  return false;
}

bool resolveImport(const char* rel, ObjModule* importer, char* resolved) { return resolveModule(rel, importer, fsExists, resolved); }

/* Compiles and runs `source` as a module, caching its exports (a map of its public names). */
static bool runModule(ObjString* key, const char* source, size_t length, const char* shown, Value* out) {
  ObjModule* m = newModule(key);
  m->loading = true;
  mapSet(&vm.modules, OBJ_VAL(key), OBJ_VAL(m));
  ObjFunction* f;
  if (bytecodeLooksLike((const unsigned char*)source, length)) {
    /* a compiled module (.fxc): checked by the verifier before it is allowed to run */
    char err[400];
    f = bytecodeRead((const unsigned char*)source, length, m, NULL, 0, err, sizeof err);
    if (!f) {
      mapDelete(&vm.modules, OBJ_VAL(key));
      return throwError("Cannot load the compiled module '%s': %s", shown, err);
    }
  } else {
    f = compile(source, m, NULL);
    if (!f) {
      mapDelete(&vm.modules, OBJ_VAL(key));
      return throwError("Cannot compile module '%s' (line %d: %s)", shown, compileErrorLine, compileErrorMsg);
    }
  }
  ObjClosure* c = newClosure(f);
  Value ignored;
  if (!vmCall(OBJ_VAL(c), 0, NULL, &ignored)) { mapDelete(&vm.modules, OBJ_VAL(key)); return false; }

  ObjMap* exports = newMap();
  for (int i = 0; i < m->globals.count; i++) {
    Entry* e = &m->globals.entries[i];
    if (!e->live || !IS_STRING(e->key) || AS_CSTRING(e->key)[0] == '_') continue;
    mapSet(&exports->map, e->key, e->value);
  }
  m->exports = exports;
  m->loading = false;
  *out = OBJ_VAL(exports);
  return true;
}

static bool cachedModule(ObjString* key, const char* shown, Value* out, bool* hit) {
  Value existing;
  *hit = false;
  if (!mapGet(&vm.modules, OBJ_VAL(key), &existing)) return true;
  ObjModule* m = AS_MODULE(existing);
  if (m->loading) return throwError("Circular import of '%s'", shown);
  *out = OBJ_VAL(m->exports);
  *hit = true;
  return true;
}

bool importModule(Value pathv, ObjModule* importer, Value* out) {
  if (!IS_STRING(pathv)) return throwError("import needs a string path");
  const char* rel = AS_CSTRING(pathv);
  bool hit;

  /* 1. modules written in Faxal and built into the faxal program itself */
  if (strncmp(rel, "std/", 4) == 0) {
    char name[128];
    snprintf(name, sizeof name, "%s", rel);
    size_t n = strlen(name);
    if (n > 3 && strcmp(name + n - 3, ".fx") == 0) name[n - 3] = '\0';
    const EmbeddedFile* e = findEmbedded(name);
    if (!e) return throwError("Cannot find the standard module '%s'", rel);
    ObjString* key = cstring(name);
    if (!cachedModule(key, rel, out, &hit)) return false;
    if (hit) return true;
    return runModule(key, (const char*)e->data, e->length, rel, out);
  }

  if (vm.sandbox) return throwError("import is disabled in sandbox mode (only std/ modules can be imported)");

  char resolved[PATH_MAX];
  if (vm.bundleCount > 0) {
    /* a program made by `faxal build`: its files live inside the executable */
    if (!resolveModule(rel, importer, bundleExists, resolved)) return throwError("Cannot find module '%s'", rel);
    ObjString* key = cstring(resolved);
    if (!cachedModule(key, rel, out, &hit)) return false;
    if (hit) return true;
    for (int i = 0; i < vm.bundleCount; i++) {
      char full[PATH_MAX * 2];
      snprintf(full, sizeof full, "/bundle/%s", vm.bundle[i].path);
      if (strcmp(full, resolved) == 0) return runModule(key, vm.bundle[i].source, vm.bundle[i].length, rel, out);
    }
    return throwError("Cannot find module '%s'", rel);
  }

  if (!resolveModule(rel, importer, fsExists, resolved)) return throwError("Cannot find module '%s'", rel);
  ObjString* key = cstring(resolved);
  if (!cachedModule(key, rel, out, &hit)) return false;
  if (hit) return true;
  size_t length;
  unsigned char* source = readFileBytes(resolved, &length);
  if (!source) return throwError("Cannot read module '%s'", rel);
  bool ok = runModule(key, (const char*)source, length, rel, out);
  free(source);
  return ok;
}

/* ----------------------------------------------------------------- the loop */

static bool safePoint(void) {
  maybeGC();
  if (vm.maxMemory && vm.bytesAllocated > vm.maxMemory) {
    collectGarbage();
    if (vm.bytesAllocated > vm.maxMemory) { vm.fatal = true; return throwError("Out of memory"); }
  }
  return true;
}


static bool run(int base) {
  CallFrame* frame = &vm.frames[vm.frameCount - 1];

#define READ_BYTE() (*frame->ip++)
#define READ_SHORT() (frame->ip += 2, (uint16_t)((frame->ip[-2] << 8) | frame->ip[-1]))
#define READ_CONSTANT() (frame->closure->function->chunk.constants.values[READ_SHORT()])
#define READ_STRING() AS_STRING(READ_CONSTANT())
#define THROW(...) do { throwError(__VA_ARGS__); goto handle_throw; } while (0)
#define FAIL_IF(expr) do { if (!(expr)) goto handle_throw; } while (0)
#define NUM_OPERANDS() do { if (!IS_NUM(peek(0)) || !IS_NUM(peek(1))) THROW("Operands must be numbers, got %s and %s", typeName(peek(1)), typeName(peek(0))); } while (0)

  for (;;) {
    if (vm.maxSteps && ++vm.steps > vm.maxSteps) { vm.fatal = true; throwError("Execution limit exceeded (infinite loop?)"); goto handle_throw; }
    uint8_t op = READ_BYTE();
    switch (op) {
      case OP_CONSTANT: push(READ_CONSTANT()); break;
      case OP_NIL: push(NIL_VAL); break;
      case OP_TRUE: push(BOOL_VAL(true)); break;
      case OP_FALSE: push(BOOL_VAL(false)); break;
      case OP_POP: pop(); break;
      case OP_DUP: push(peek(0)); break;
      case OP_DUP2: { Value a = peek(1), b = peek(0); push(a); push(b); break; }

      case OP_GET_LOCAL: push(frame->slots[READ_BYTE()]); break;
      case OP_SET_LOCAL: frame->slots[READ_BYTE()] = peek(0); break;
      case OP_GET_GLOBAL: {
        ObjString* name = READ_STRING();
        Value v;
        if (mapGet(&frame->closure->function->module->globals, OBJ_VAL(name), &v) || mapGet(&vm.builtins, OBJ_VAL(name), &v)) push(v);
        else {
          Suggest s = { name->chars, "", 99 };
          considerMap(&s, &frame->closure->function->module->globals);
          considerMap(&s, &vm.builtins);
          THROW("Undefined variable '%s'%s", name->chars, hint(&s));
        }
        break;
      }
      case OP_DEFINE_GLOBAL: {
        ObjString* name = READ_STRING();
        mapSet(&frame->closure->function->module->globals, OBJ_VAL(name), peek(0));
        pop();
        break;
      }
      case OP_SET_GLOBAL: {
        ObjString* name = READ_STRING();
        Value dummy;
        Map* g = &frame->closure->function->module->globals;
        if (!mapGet(g, OBJ_VAL(name), &dummy)) {
          Suggest s = { name->chars, "", 99 };
          considerMap(&s, g);
          const char* h = hint(&s);
          THROW("Undefined variable '%s'%s", name->chars, *h ? h : ". Declare it with 'let' first");
        }
        mapSet(g, OBJ_VAL(name), peek(0));
        break;
      }
      case OP_GET_UPVALUE: push(*frame->closure->upvalues[READ_BYTE()]->location); break;
      case OP_SET_UPVALUE: *frame->closure->upvalues[READ_BYTE()]->location = peek(0); break;

      case OP_GET_PROPERTY: {
        ObjString* name = READ_STRING();
        Value obj = peek(0);
        if (IS_INSTANCE(obj)) {
          ObjInstance* inst = AS_INSTANCE(obj);
          Value fv;
          if (mapGet(&inst->fields, OBJ_VAL(name), &fv)) { pop(); push(fv); break; }
          if (mapGet(&inst->klass->methods, OBJ_VAL(name), &fv)) {
            ObjBoundMethod* bm = newBoundMethod(obj, AS_CLOSURE(fv));
            pop(); push(OBJ_VAL(bm));
            break;
          }
          Suggest s = { name->chars, "", 99 };
          considerMap(&s, &inst->fields);
          considerMap(&s, &inst->klass->methods);
          THROW("%s has no field or method '%s'%s", inst->klass->name->chars, name->chars, hint(&s));
        }
        if (!IS_MAP(obj)) THROW("Only maps have properties, but this is %s. (Did you forget the parentheses of a method call?)", typeName(obj));
        Value v;
        if (!mapGet(&AS_MAP(obj)->map, OBJ_VAL(name), &v)) v = NIL_VAL;
        pop(); push(v);
        break;
      }
      case OP_SET_PROPERTY: {
        ObjString* name = READ_STRING();
        Value obj = peek(1);
        if (IS_INSTANCE(obj)) {
          mapSet(&AS_INSTANCE(obj)->fields, OBJ_VAL(name), peek(0));
          Value val = pop(); pop(); push(val);
          break;
        }
        if (!IS_MAP(obj)) THROW("Can only set properties on maps, but this is %s", typeName(obj));
        mapSet(&AS_MAP(obj)->map, OBJ_VAL(name), peek(0));
        Value v = pop(); pop(); push(v);
        break;
      }
      case OP_GET_INDEX: {
        Value out;
        FAIL_IF(getIndex(peek(1), peek(0), &out));
        pop(); pop(); push(out);
        break;
      }
      case OP_SET_INDEX: {
        FAIL_IF(setIndex(peek(2), peek(1), peek(0)));
        Value v = pop(); pop(); pop(); push(v);
        break;
      }
      case OP_SLICE: {
        Value out;
        FAIL_IF(sliceValue(peek(2), peek(1), peek(0), &out));
        pop(); pop(); pop(); push(out);
        break;
      }

      case OP_EQUAL: { Value b = pop(), a = pop(); push(BOOL_VAL(valuesEqual(a, b))); break; }
      case OP_GREATER: { int c; FAIL_IF(compareValues(peek(1), peek(0), &c)); pop(); pop(); push(BOOL_VAL(c > 0)); break; }
      case OP_LESS: { int c; FAIL_IF(compareValues(peek(1), peek(0), &c)); pop(); pop(); push(BOOL_VAL(c < 0)); break; }
      case OP_ADD: {
        Value b = peek(0), a = peek(1), out;
        if (IS_NUM(a) && IS_NUM(b)) { pop(); pop(); push(NUM_VAL(AS_NUM(a) + AS_NUM(b))); break; }
        if (IS_STRING(a) || IS_STRING(b)) { FAIL_IF(concat(a, b, &out)); }
        else if (IS_LIST(a) && IS_LIST(b)) {
          ObjList* l = newList();
          out = OBJ_VAL(l);
          for (int i = 0; i < AS_LIST(a)->count; i++) listPush(l, AS_LIST(a)->items[i]);
          for (int i = 0; i < AS_LIST(b)->count; i++) listPush(l, AS_LIST(b)->items[i]);
        } else THROW("Can't add %s and %s", typeName(a), typeName(b));
        pop(); pop(); push(out);
        break;
      }
      case OP_SUB: NUM_OPERANDS(); { double b = AS_NUM(pop()), a = AS_NUM(pop()); push(NUM_VAL(a - b)); } break;
      case OP_MUL: {
        Value b = peek(0), a = peek(1);
        if (IS_NUM(a) && IS_NUM(b)) { pop(); pop(); push(NUM_VAL(AS_NUM(a) * AS_NUM(b))); break; }
        Value out;
        if (IS_STRING(a) && IS_NUM(b)) { FAIL_IF(repeatString(AS_STRING(a), AS_NUM(b), &out)); }
        else if (IS_NUM(a) && IS_STRING(b)) { FAIL_IF(repeatString(AS_STRING(b), AS_NUM(a), &out)); }
        else THROW("Can't multiply %s and %s", typeName(a), typeName(b));
        pop(); pop(); push(out);
        break;
      }
      case OP_DIV: {
        NUM_OPERANDS();
        double b = AS_NUM(pop()), a = AS_NUM(pop());
        if (b == 0) THROW("Division by zero");
        push(NUM_VAL(a / b));
        break;
      }
      case OP_MOD: {
        NUM_OPERANDS();
        double b = AS_NUM(pop()), a = AS_NUM(pop());
        if (b == 0) THROW("Modulo by zero");
        double r = fmod(a, b);
        if (r != 0 && (r < 0) != (b < 0)) r += b; /* result takes the sign of the divisor */
        push(NUM_VAL(r));
        break;
      }
      case OP_POW: { NUM_OPERANDS(); double b = AS_NUM(pop()), a = AS_NUM(pop()); push(NUM_VAL(pow(a, b))); break; }
      case OP_NEG: {
        if (!IS_NUM(peek(0))) THROW("Can only negate numbers, not %s", typeName(peek(0)));
        push(NUM_VAL(-AS_NUM(pop())));
        break;
      }
      case OP_NOT: push(BOOL_VAL(isFalsey(pop()))); break;
      case OP_IN: {
        bool r;
        FAIL_IF(containsValue(peek(1), peek(0), &r));
        pop(); pop(); push(BOOL_VAL(r));
        break;
      }
      case OP_RANGE: {
        NUM_OPERANDS();
        double b = AS_NUM(peek(0)), a = AS_NUM(peek(1));
        Value r = OBJ_VAL(newRange(a, b, 1));
        pop(); pop(); push(r);
        break;
      }

      case OP_JUMP: { uint16_t off = READ_SHORT(); frame->ip += off; break; }
      case OP_JUMP_IF_FALSE: { uint16_t off = READ_SHORT(); if (isFalsey(peek(0))) frame->ip += off; break; }
      case OP_LOOP: { uint16_t off = READ_SHORT(); frame->ip -= off; FAIL_IF(safePoint()); break; }

      case OP_CALL: {
        int argc = READ_BYTE();
        FAIL_IF(safePoint());
        FAIL_IF(callValue(peek(argc), argc));
        frame = &vm.frames[vm.frameCount - 1];
        break;
      }
      case OP_INVOKE: {
        ObjString* name = READ_STRING();
        int argc = READ_BYTE();
        FAIL_IF(safePoint());
        Value recv = peek(argc);
        if (IS_INSTANCE(recv)) {
          ObjInstance* inst = AS_INSTANCE(recv);
          Value fv;
          if (mapGet(&inst->fields, OBJ_VAL(name), &fv)) {
            vm.stackTop[-argc - 1] = fv;
            FAIL_IF(callValue(fv, argc));
          } else {
            FAIL_IF(invokeFromClass(inst->klass, name, argc));
          }
          frame = &vm.frames[vm.frameCount - 1];
          break;
        }
        if (IS_MAP(recv)) {
          Value fn;
          if (mapGet(&AS_MAP(recv)->map, OBJ_VAL(name), &fn)) {
            vm.stackTop[-argc - 1] = fn;
            FAIL_IF(callValue(fn, argc));
            frame = &vm.frames[vm.frameCount - 1];
            break;
          }
        }
        const MethodDef* m = findMethod(recv, name);
        if (!m) {
          Suggest s = { name->chars, "", 99 };
          considerMethods(&s, methodTable(recv));
          if (IS_MAP(recv)) {
            considerMap(&s, &AS_MAP(recv)->map);
            THROW("Map has no key or method '%s'%s", name->chars, hint(&s));
          }
          THROW("%s has no method '%s'%s", typeName(recv), name->chars, hint(&s));
        }
        FAIL_IF(checkArity(m->name, argc, m->minArgs, m->maxArgs));
        Value result = NIL_VAL;
        FAIL_IF(m->fn(argc + 1, vm.stackTop - argc - 1, &result));
        vm.stackTop -= argc + 1;
        push(result);
        break;
      }
      case OP_CLOSURE: {
        ObjFunction* fn = AS_FUNCTION(READ_CONSTANT());
        ObjClosure* c = newClosure(fn);
        push(OBJ_VAL(c));
        for (int i = 0; i < c->upvalueCount; i++) {
          uint8_t isLocal = READ_BYTE(), index = READ_BYTE();
          c->upvalues[i] = isLocal ? captureUpvalue(frame->slots + index) : frame->closure->upvalues[index];
        }
        break;
      }
      case OP_CLOSE_UPVALUE: closeUpvalues(vm.stackTop - 1); pop(); break;
      case OP_RETURN: {
        Value result = pop();
        while (vm.handlerCount > 0 && vm.handlers[vm.handlerCount - 1].frame >= vm.frameCount) vm.handlerCount--;
        closeUpvalues(frame->slots);
        vm.frameCount--;
        vm.stackTop = frame->slots;
        push(result);
        if (vm.frameCount == base) return true;
        frame = &vm.frames[vm.frameCount - 1];
        break;
      }

      case OP_BUILD_LIST: {
        int n = READ_SHORT();
        ObjList* l = newList();
        l->items = n ? GROW_ARRAY(Value, NULL, 0, n) : NULL;
        l->capacity = n;
        for (int i = 0; i < n; i++) l->items[i] = vm.stackTop[-n + i];
        l->count = n;
        vm.stackTop -= n;
        push(OBJ_VAL(l));
        break;
      }
      case OP_BUILD_MAP: {
        int n = READ_SHORT();
        ObjMap* m = newMap();
        for (int i = 0; i < n; i++) {
          Value k = vm.stackTop[-2 * n + 2 * i], v = vm.stackTop[-2 * n + 2 * i + 1];
          if (!validKey(k)) THROW("Map keys must be strings, numbers or booleans, not %s", typeName(k));
          mapSet(&m->map, k, v);
        }
        vm.stackTop -= 2 * n;
        push(OBJ_VAL(m));
        break;
      }
      case OP_FOR_NEXT: {
        uint8_t slot = READ_BYTE();
        uint16_t off = READ_SHORT();
        Value iter = frame->slots[slot];
        if (!IS_NUM(frame->slots[slot + 1])) THROW("Invalid bytecode: a loop counter is not a number");
        double idx = AS_NUM(frame->slots[slot + 1]);
        if (!(idx >= 0 && idx < 2147483647.0)) THROW("Invalid bytecode: a loop counter is out of range");
        Value item = NIL_VAL;
        bool has = false;
        int i = (int)idx;
        if (IS_LIST(iter)) {
          ObjList* l = AS_LIST(iter);
          if (i < l->count) { item = l->items[i]; frame->slots[slot + 1] = NUM_VAL(i + 1); has = true; }
        } else if (IS_STRING(iter)) {
          ObjString* s = AS_STRING(iter);
          if (i < s->length) {
            int n = utf8Len((unsigned char)s->chars[i]);
            if (i + n > s->length) n = s->length - i;
            item = OBJ_VAL(newString(s->chars + i, n));
            frame->slots[slot + 1] = NUM_VAL(i + n);
            has = true;
          }
        } else if (IS_MAP(iter)) {
          Map* m = &AS_MAP(iter)->map;
          while (i < m->count && !m->entries[i].live) i++;
          if (i < m->count) { item = m->entries[i].key; frame->slots[slot + 1] = NUM_VAL(i + 1); has = true; }
        } else if (IS_RANGE(iter)) {
          ObjRange* r = AS_RANGE(iter);
          if (i < rangeLength(r)) { item = NUM_VAL(r->start + i * r->step); frame->slots[slot + 1] = NUM_VAL(i + 1); has = true; }
        } else THROW("Can't loop over %s (use a list, string, map or range)", typeName(iter));
        if (has) push(item); else frame->ip += off;
        break;
      }

      case OP_TRY: {
        uint16_t off = READ_SHORT();
        if (vm.handlerCount == HANDLERS_MAX) THROW("Too many nested try blocks");
        Handler* h = &vm.handlers[vm.handlerCount++];
        h->frame = vm.frameCount; h->sp = vm.stackTop; h->catchIp = frame->ip + off;
        break;
      }
      case OP_END_TRY:
        if (vm.handlerCount == 0 || vm.handlers[vm.handlerCount - 1].frame != vm.frameCount) THROW("Invalid bytecode: a try block ended that was never started");
        vm.handlerCount--;
        break;
      case OP_THROW: vm.thrown = pop(); goto handle_throw;
      case OP_IMPORT: {
        Value out;
        FAIL_IF(importModule(peek(0), frame->closure->function->module, &out));
        pop(); push(out);
        break;
      }
      case OP_REPL_PRINT: {
        Value v = pop();
        if (!IS_NIL(v)) {
          Buffer b; bufInit(&b);
          bool ok = appendValue(&b, v, true, 0);
          bufChar(&b, '\n');
          if (ok) ok = vmWrite(b.data, b.len);
          bufFree(&b);
          if (!ok) goto handle_throw;
        }
        break;
      }
      case OP_SWAP: { Value a = peek(0); vm.stackTop[-1] = peek(1); vm.stackTop[-2] = a; break; }
      case OP_BY: {
        Value step = peek(0), r = peek(1);
        if (!IS_RANGE(r) || !IS_NUM(step)) THROW("'by' needs a range on the left and a number on the right, like 0..10 by 2");
        if (AS_NUM(step) == 0) THROW("The step after 'by' can't be 0");
        Value nr = OBJ_VAL(newRange(AS_RANGE(r)->start, AS_RANGE(r)->end, AS_NUM(step)));
        pop(); pop(); push(nr);
        break;
      }
      case OP_JUMP_IF_NIL: { uint16_t off = READ_SHORT(); if (IS_NIL(peek(0))) frame->ip += off; break; }
      case OP_JUMP_IF_NOT_NIL: { uint16_t off = READ_SHORT(); if (!IS_NIL(peek(0))) frame->ip += off; break; }
      case OP_CLASS: push(OBJ_VAL(newClass(READ_STRING()))); break;
      case OP_INHERIT: {
        Value sup = peek(1);
        if (!IS_CLASS(sup)) THROW("A class can only extend another class, not %s", typeName(sup));
        if (!IS_CLASS(peek(0))) THROW("Invalid bytecode: expected a class");
        ObjClass* sub = AS_CLASS(peek(0));
        Map* from = &AS_CLASS(sup)->methods;
        for (int i = 0; i < from->count; i++) if (from->entries[i].live) mapSet(&sub->methods, from->entries[i].key, from->entries[i].value);
        sub->super = AS_CLASS(sup);
        pop();
        break;
      }
      case OP_METHOD: {
        ObjString* name = READ_STRING();
        if (!IS_CLASS(peek(1)) || !IS_CLOSURE(peek(0))) THROW("Invalid bytecode: a method must be a function in a class");
        mapSet(&AS_CLASS(peek(1))->methods, OBJ_VAL(name), peek(0));
        pop();
        break;
      }
      case OP_GET_SUPER: {
        ObjString* name = READ_STRING();
        if (!IS_CLASS(peek(0))) THROW("Invalid bytecode: expected a class");
        ObjClass* sup = AS_CLASS(pop());
        Value m;
        if (!mapGet(&sup->methods, OBJ_VAL(name), &m)) THROW("The superclass %s has no method '%s'", sup->name->chars, name->chars);
        ObjBoundMethod* bm = newBoundMethod(peek(0), AS_CLOSURE(m));
        pop(); push(OBJ_VAL(bm));
        break;
      }
      case OP_SUPER_INVOKE: {
        ObjString* name = READ_STRING();
        int argc = READ_BYTE();
        if (!IS_CLASS(peek(0))) THROW("Invalid bytecode: expected a class");
        ObjClass* sup = AS_CLASS(pop());
        FAIL_IF(invokeFromClass(sup, name, argc));
        frame = &vm.frames[vm.frameCount - 1];
        break;
      }
      default: THROW("Internal error: bad opcode %d", op);
    }
    continue;

  handle_throw:
    if ((vm.handlerCount == 0 || vm.fatal) && !vm.traceback) captureTraceback();
    if (!vm.fatal && vm.handlerCount > 0 && vm.handlers[vm.handlerCount - 1].frame > base) {
      Handler h = vm.handlers[--vm.handlerCount];
      closeUpvalues(h.sp);
      vm.frameCount = h.frame;
      vm.stackTop = h.sp;
      push(vm.thrown);
      frame = &vm.frames[vm.frameCount - 1];
      frame->ip = h.catchIp;
      continue;
    }
    vm.frameCount = base;
    return false;
  }
#undef READ_BYTE
#undef READ_SHORT
#undef READ_CONSTANT
#undef READ_STRING
#undef THROW
#undef FAIL_IF
#undef NUM_OPERANDS
}

int runFunction(ObjFunction* f) {
  vm.steps = 0;   /* the time spent compiling is not charged to the program */
  closeUpvalues(vm.stack);
  vm.stackTop = vm.stack; vm.frameCount = 0; vm.handlerCount = 0;
  free(vm.traceback); vm.traceback = NULL;
  vm.fatal = false; vm.thrown = NIL_VAL; vm.nativeDepth = 0;

  ObjClosure* c = newClosure(f);
  push(OBJ_VAL(c));
  if (!callClosure(c, 0)) return 70;
  if (!run(0)) return 70;
  pop();
  return 0;
}

int runSource(const char* source, ObjModule* module) { return interpret(source, module, NULL); }

int interpret(const char* source, ObjModule* module, bool* needMoreInput) {
  ObjFunction* f = compile(source, module, needMoreInput);
  if (!f) return 65;
  return runFunction(f);
}

/* Reads a whole file as bytes. The buffer is NUL terminated too, so it also works as text. */
unsigned char* readFileBytes(const char* path, size_t* len) {
  FILE* f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  rewind(f);
  if (size < 0 || size > 512L * 1024 * 1024) { fclose(f); return NULL; }
  unsigned char* buf = malloc((size_t)size + 1);
  size_t got = fread(buf, 1, (size_t)size, f);
  buf[got] = '\0';
  fclose(f);
  *len = got;
  return buf;
}
