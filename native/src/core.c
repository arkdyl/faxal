/* core.c: buffers, memory, garbage collector, objects, strings, maps */
#include "faxal.h"
#include <math.h>

VM vm;

/* ----------------------------------------------------------------- buffers */

void bufInit(Buffer* b) { b->data = NULL; b->len = 0; b->cap = 0; }
void bufFree(Buffer* b) { free(b->data); bufInit(b); }

static void bufReserve(Buffer* b, int extra) {
  if (b->len + extra + 1 <= b->cap) return;
  int cap = b->cap ? b->cap : 64;
  while (cap < b->len + extra + 1) cap *= 2;
  b->data = realloc(b->data, (size_t)cap);
  if (!b->data) { fputs("faxal: out of memory\n", stderr); exit(70); }
  b->cap = cap;
}

void bufAppend(Buffer* b, const char* s, int n) {
  bufReserve(b, n);
  if (n > 0) memcpy(b->data + b->len, s, (size_t)n);
  b->len += n;
  b->data[b->len] = '\0';
}
void bufStr(Buffer* b, const char* s) { bufAppend(b, s, (int)strlen(s)); }
void bufChar(Buffer* b, char c) { bufAppend(b, &c, 1); }

void bufPrintf(Buffer* b, const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  char tmp[512];
  int n = vsnprintf(tmp, sizeof tmp, fmt, ap);
  va_end(ap);
  if (n < (int)sizeof tmp) { bufAppend(b, tmp, n); return; }
  char* big = malloc((size_t)n + 1);
  va_start(ap, fmt);
  vsnprintf(big, (size_t)n + 1, fmt, ap);
  va_end(ap);
  bufAppend(b, big, n);
  free(big);
}

/* ------------------------------------------------------------------ memory */

void* reallocate(void* ptr, size_t oldSize, size_t newSize) {
  vm.bytesAllocated += newSize;
  vm.bytesAllocated -= oldSize;
  if (newSize == 0) { free(ptr); return NULL; }
  void* r = realloc(ptr, newSize);
  if (!r) { fputs("faxal: out of memory\n", stderr); exit(70); }
  return r;
}

static Obj* allocateObject(size_t size, ObjType type) {
  Obj* o = (Obj*)reallocate(NULL, 0, size);
  o->type = type;
  o->isMarked = false;
  o->next = vm.objects;
  vm.objects = o;
  return o;
}
#define ALLOC_OBJ(T, t) ((T*)allocateObject(sizeof(T), t))

/* ----------------------------------------------------------------- strings */

#define TOMB ((ObjString*)1)

static uint32_t hashBytes(const char* s, int n) {
  uint32_t h = 2166136261u;
  for (int i = 0; i < n; i++) { h ^= (uint8_t)s[i]; h *= 16777619u; }
  return h;
}

static void internInsert(ObjString* s);

static void internGrow(void) {
  int oldCap = vm.stringCap;
  ObjString** old = vm.strings;
  vm.stringCap = oldCap ? oldCap * 2 : 256;
  vm.strings = calloc((size_t)vm.stringCap, sizeof(ObjString*));
  vm.stringUsed = 0;
  for (int i = 0; i < oldCap; i++)
    if (old[i] && old[i] != TOMB) internInsert(old[i]);
  free(old);
}

static void internInsert(ObjString* s) {
  if ((vm.stringUsed + 1) * 4 > vm.stringCap * 3) internGrow();
  uint32_t mask = (uint32_t)vm.stringCap - 1, i = s->hash & mask;
  while (vm.strings[i] && vm.strings[i] != TOMB) i = (i + 1) & mask;
  if (!vm.strings[i]) vm.stringUsed++;
  vm.strings[i] = s;
}

ObjString* newString(const char* chars, int length) {
  uint32_t hash = hashBytes(chars, length);
  if (vm.stringCap > 0) {
    uint32_t mask = (uint32_t)vm.stringCap - 1, i = hash & mask;
    for (;;) {
      ObjString* s = vm.strings[i];
      if (!s) break;
      if (s != TOMB && s->hash == hash && s->length == length && memcmp(s->chars, chars, (size_t)length) == 0) return s;
      i = (i + 1) & mask;
    }
  }
  ObjString* s = (ObjString*)allocateObject(sizeof(ObjString) + (size_t)length + 1, OBJ_STRING);
  s->length = length;
  s->hash = hash;
  memcpy(s->chars, chars, (size_t)length);
  s->chars[length] = '\0';
  internInsert(s);
  return s;
}

ObjString* cstring(const char* chars) { return newString(chars, (int)strlen(chars)); }

static void removeWhiteStrings(void) {
  for (int i = 0; i < vm.stringCap; i++) {
    ObjString* s = vm.strings[i];
    if (s && s != TOMB && !s->obj.isMarked) vm.strings[i] = TOMB;
  }
}

/* -------------------------------------------------------------------- maps */

static uint32_t hashValue(Value v) {
  switch (v.type) {
    case VAL_NIL: return 7;
    case VAL_BOOL: return AS_BOOL(v) ? 3 : 5;
    case VAL_NUM: {
      double d = AS_NUM(v);
      if (d == 0) d = 0;
      uint64_t bits; memcpy(&bits, &d, sizeof bits);
      bits ^= bits >> 33; bits *= 0xff51afd7ed558ccdULL; bits ^= bits >> 33;
      return (uint32_t)bits;
    }
    case VAL_OBJ:
      if (OBJ_TYPE(v) == OBJ_STRING) return AS_STRING(v)->hash;
      return (uint32_t)(((uintptr_t)AS_OBJ(v)) >> 4) * 2654435761u;
  }
  return 0;
}

static bool keyEq(Value a, Value b) {
  if (a.type != b.type) return false;
  switch (a.type) {
    case VAL_NIL: return true;
    case VAL_BOOL: return AS_BOOL(a) == AS_BOOL(b);
    case VAL_NUM: return AS_NUM(a) == AS_NUM(b);
    case VAL_OBJ: return AS_OBJ(a) == AS_OBJ(b);
  }
  return false;
}

bool validKey(Value key) { return !IS_OBJ(key) || IS_STRING(key); }

void mapInit(Map* m) { memset(m, 0, sizeof *m); }

void mapFree(Map* m) {
  FREE_ARRAY(Entry, m->entries, m->capacity);
  FREE_ARRAY(int32_t, m->index, m->indexCap);
  mapInit(m);
}

/* Returns the entry index (or -1); *slot receives the index-table position. */
static int mapFind(Map* m, Value key, int* slot) {
  if (m->indexCap == 0) return -1;
  uint32_t mask = (uint32_t)m->indexCap - 1, i = hashValue(key) & mask;
  for (;;) {
    int32_t s = m->index[i];
    if (s == 0) return -1;
    if (s > 0 && keyEq(m->entries[s - 1].key, key)) { if (slot) *slot = (int)i; return s - 1; }
    i = (i + 1) & mask;
  }
}

static void mapRebuild(Map* m, int newCap) {
  Entry* old = m->entries;
  int oldCount = m->count, oldCap = m->capacity, oldIdxCap = m->indexCap;
  int32_t* oldIdx = m->index;

  int idxCap = 8;
  while (idxCap < newCap * 2) idxCap *= 2;
  m->entries = ALLOCATE(Entry, newCap);
  m->index = ALLOCATE(int32_t, idxCap);
  memset(m->index, 0, sizeof(int32_t) * (size_t)idxCap);
  m->capacity = newCap;
  m->indexCap = idxCap;
  m->count = 0;
  for (int k = 0; k < oldCount; k++) {
    if (!old[k].live) continue;
    int n = m->count++;
    m->entries[n] = old[k];
    uint32_t mask = (uint32_t)idxCap - 1, i = hashValue(old[k].key) & mask;
    while (m->index[i] != 0) i = (i + 1) & mask;
    m->index[i] = n + 1;
  }
  FREE_ARRAY(Entry, old, oldCap);
  FREE_ARRAY(int32_t, oldIdx, oldIdxCap);
}

bool mapGet(Map* m, Value key, Value* out) {
  int e = mapFind(m, key, NULL);
  if (e < 0) return false;
  *out = m->entries[e].value;
  return true;
}

bool mapSet(Map* m, Value key, Value value) {
  int e = mapFind(m, key, NULL);
  if (e >= 0) { m->entries[e].value = value; return false; }
  if (m->count == m->capacity) mapRebuild(m, m->live * 2 < m->capacity && m->capacity > 0 ? m->capacity : GROW_CAPACITY(m->capacity));
  int n = m->count++;
  m->entries[n].key = key; m->entries[n].value = value; m->entries[n].live = true;
  m->live++;
  uint32_t mask = (uint32_t)m->indexCap - 1, i = hashValue(key) & mask;
  while (m->index[i] > 0) i = (i + 1) & mask;
  m->index[i] = n + 1;
  return true;
}

bool mapDelete(Map* m, Value key) {
  int slot = 0;
  int e = mapFind(m, key, &slot);
  if (e < 0) return false;
  m->index[slot] = -1;
  m->entries[e].live = false;
  m->entries[e].key = NIL_VAL;
  m->entries[e].value = NIL_VAL;
  m->live--;
  return true;
}

/* ----------------------------------------------------------------- objects */

ObjFunction* newFunction(void) {
  ObjFunction* f = ALLOC_OBJ(ObjFunction, OBJ_FUNCTION);
  f->arity = 0; f->minArity = 0; f->upvalueCount = 0; f->name = NULL; f->module = NULL; f->isScript = false;
  chunkInit(&f->chunk);
  return f;
}

ObjClosure* newClosure(ObjFunction* function) {
  ObjUpvalue** ups = function->upvalueCount ? ALLOCATE(ObjUpvalue*, function->upvalueCount) : NULL;
  for (int i = 0; i < function->upvalueCount; i++) ups[i] = NULL;
  ObjClosure* c = ALLOC_OBJ(ObjClosure, OBJ_CLOSURE);
  c->function = function; c->upvalues = ups; c->upvalueCount = function->upvalueCount;
  return c;
}

ObjUpvalue* newUpvalue(Value* slot) {
  ObjUpvalue* u = ALLOC_OBJ(ObjUpvalue, OBJ_UPVALUE);
  u->location = slot; u->closed = NIL_VAL; u->next = NULL;
  return u;
}

ObjNative* newNative(const char* name, NativeFn fn, int minArgs, int maxArgs) {
  ObjNative* n = ALLOC_OBJ(ObjNative, OBJ_NATIVE);
  n->fn = fn; n->name = name; n->minArgs = minArgs; n->maxArgs = maxArgs;
  return n;
}

ObjList* newList(void) {
  ObjList* l = ALLOC_OBJ(ObjList, OBJ_LIST);
  l->items = NULL; l->count = 0; l->capacity = 0;
  return l;
}

void listPush(ObjList* l, Value v) {
  if (l->count == l->capacity) {
    int old = l->capacity;
    l->capacity = GROW_CAPACITY(old);
    l->items = GROW_ARRAY(Value, l->items, old, l->capacity);
  }
  l->items[l->count++] = v;
}

ObjMap* newMap(void) {
  ObjMap* m = ALLOC_OBJ(ObjMap, OBJ_MAP);
  mapInit(&m->map);
  return m;
}

ObjRange* newRange(double start, double end, double step) {
  ObjRange* r = ALLOC_OBJ(ObjRange, OBJ_RANGE);
  r->start = start; r->end = end; r->step = step;
  return r;
}

ObjModule* newModule(ObjString* path) {
  ObjModule* m = ALLOC_OBJ(ObjModule, OBJ_MODULE);
  m->path = path; m->exports = NULL; m->loading = false;
  mapInit(&m->globals);
  return m;
}

ObjClass* newClass(ObjString* name) {
  ObjClass* k = ALLOC_OBJ(ObjClass, OBJ_CLASS);
  k->name = name; k->super = NULL;
  mapInit(&k->methods);
  return k;
}

ObjInstance* newInstance(ObjClass* klass) {
  ObjInstance* i = ALLOC_OBJ(ObjInstance, OBJ_INSTANCE);
  i->klass = klass;
  mapInit(&i->fields);
  return i;
}

ObjBoundMethod* newBoundMethod(Value receiver, ObjClosure* method) {
  ObjBoundMethod* b = ALLOC_OBJ(ObjBoundMethod, OBJ_BOUND_METHOD);
  b->receiver = receiver; b->method = method;
  return b;
}

ObjCoroutine* newCoroutine(Value fn) {
  ObjCoroutine* c = ALLOC_OBJ(ObjCoroutine, OBJ_COROUTINE);
  memset(&c->ctx, 0, sizeof c->ctx);
  memset(&c->host, 0, sizeof c->host);
  c->fn = fn; c->state = CO_NEW; c->resumer = NULL; c->depth = 0; c->yieldArgc = 0;
  return c;
}

void chunkInit(Chunk* c) {
  c->code = NULL; c->lines = NULL; c->count = 0; c->capacity = 0;
  c->constants.values = NULL; c->constants.count = 0; c->constants.capacity = 0;
}

void chunkFree(Chunk* c) {
  FREE_ARRAY(uint8_t, c->code, c->capacity);
  FREE_ARRAY(int, c->lines, c->capacity);
  FREE_ARRAY(Value, c->constants.values, c->constants.capacity);
  chunkInit(c);
}

void chunkWrite(Chunk* c, uint8_t byte, int line) {
  if (c->capacity < c->count + 1) {
    int old = c->capacity;
    c->capacity = GROW_CAPACITY(old);
    c->code = GROW_ARRAY(uint8_t, c->code, old, c->capacity);
    c->lines = GROW_ARRAY(int, c->lines, old, c->capacity);
  }
  c->code[c->count] = byte;
  c->lines[c->count] = line;
  c->count++;
}

int chunkAddConstant(Chunk* c, Value v) {
  ValueArray* a = &c->constants;
  if (a->capacity < a->count + 1) {
    int old = a->capacity;
    a->capacity = GROW_CAPACITY(old);
    a->values = GROW_ARRAY(Value, a->values, old, a->capacity);
  }
  a->values[a->count] = v;
  return a->count++;
}

/* ------------------------------------------------------------------ values */

bool isFalsey(Value v) { return IS_NIL(v) || (IS_BOOL(v) && !AS_BOOL(v)); }

static int eqBudget;
static bool equalDepth(Value a, Value b, int depth) {
  if (a.type != b.type) return false;
  if (--eqBudget < 0) return false; /* cyclic / enormous structures: give up */
  switch (a.type) {
    case VAL_NIL: return true;
    case VAL_BOOL: return AS_BOOL(a) == AS_BOOL(b);
    case VAL_NUM: return AS_NUM(a) == AS_NUM(b);
    case VAL_OBJ:
      if (AS_OBJ(a) == AS_OBJ(b)) return true;
      if (OBJ_TYPE(a) != OBJ_TYPE(b) || depth > 50) return false;
      if (OBJ_TYPE(a) == OBJ_LIST) {
        ObjList *x = AS_LIST(a), *y = AS_LIST(b);
        if (x->count != y->count) return false;
        for (int i = 0; i < x->count; i++) if (!equalDepth(x->items[i], y->items[i], depth + 1)) return false;
        return true;
      }
      if (OBJ_TYPE(a) == OBJ_MAP) {
        Map *x = &AS_MAP(a)->map, *y = &AS_MAP(b)->map;
        if (x->live != y->live) return false;
        for (int i = 0; i < x->count; i++) {
          if (!x->entries[i].live) continue;
          Value other;
          if (!mapGet(y, x->entries[i].key, &other) || !equalDepth(x->entries[i].value, other, depth + 1)) return false;
        }
        return true;
      }
      if (OBJ_TYPE(a) == OBJ_RANGE) {
        ObjRange *x = AS_RANGE(a), *y = AS_RANGE(b);
        return x->start == y->start && x->end == y->end && x->step == y->step;
      }
      return false;
  }
  return false;
}
bool valuesEqual(Value a, Value b) { eqBudget = 200000; return equalDepth(a, b, 0); }

const char* typeName(Value v) {
  switch (v.type) {
    case VAL_NIL: return "nil";
    case VAL_BOOL: return "bool";
    case VAL_NUM: return "number";
    case VAL_OBJ:
      switch (OBJ_TYPE(v)) {
        case OBJ_STRING: return "string";
        case OBJ_LIST: return "list";
        case OBJ_MAP: return "map";
        case OBJ_RANGE: return "range";
        case OBJ_MODULE: return "module";
        case OBJ_FUNCTION: case OBJ_CLOSURE: case OBJ_NATIVE: case OBJ_BOUND_METHOD: return "function";
        case OBJ_CLASS: return "class";
        case OBJ_INSTANCE: return "instance";
        case OBJ_COROUTINE: return "coroutine";
        default: return "object";
      }
  }
  return "?";
}

int rangeLength(ObjRange* r) {
  if (isnan(r->start) || isnan(r->end) || isnan(r->step)) return 0;
  if (r->step > 0 ? r->start >= r->end : r->start <= r->end) return 0;
  double n = ceil((r->end - r->start) / r->step);
  if (isnan(n) || n <= 0) return 0;
  return n > 2147483647.0 ? 2147483647 : (int)n;
}

void formatNumber(double d, char* buf) {
  if (isnan(d)) strcpy(buf, "nan");
  else if (isinf(d)) strcpy(buf, d < 0 ? "-inf" : "inf");
  else if (d == floor(d) && fabs(d) < 1e15) snprintf(buf, 32, "%.0f", d == 0 ? 0.0 : d);
  else snprintf(buf, 32, "%.14g", d);
}

static bool isIdentifier(const char* s, int n) {
  if (n == 0 || !((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z') || s[0] == '_')) return false;
  for (int i = 1; i < n; i++) {
    char c = s[i];
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) return false;
  }
  return true;
}

static void appendQuoted(Buffer* b, const char* s, int n) {
  bufChar(b, '"');
  for (int i = 0; i < n; i++) {
    switch (s[i]) {
      case '"': bufStr(b, "\\\""); break;
      case '\\': bufStr(b, "\\\\"); break;
      case '\n': bufStr(b, "\\n"); break;
      case '\t': bufStr(b, "\\t"); break;
      case '\r': bufStr(b, "\\r"); break;
      default: bufChar(b, s[i]);
    }
  }
  bufChar(b, '"');
}

bool appendValue(Buffer* b, Value v, bool repr, int depth) {
  char num[32];
  switch (v.type) {
    case VAL_NIL: bufStr(b, "nil"); return true;
    case VAL_BOOL: bufStr(b, AS_BOOL(v) ? "true" : "false"); return true;
    case VAL_NUM: formatNumber(AS_NUM(v), num); bufStr(b, num); return true;
    case VAL_OBJ: break;
  }
  switch (OBJ_TYPE(v)) {
    case OBJ_STRING:
      if (repr) appendQuoted(b, AS_CSTRING(v), AS_STRING(v)->length);
      else bufAppend(b, AS_CSTRING(v), AS_STRING(v)->length);
      return true;
    case OBJ_LIST: {
      ObjList* l = AS_LIST(v);
      if (depth > 6) { bufStr(b, "[...]"); return true; }
      bufChar(b, '[');
      for (int i = 0; i < l->count; i++) {
        if (b->len > (4 << 20)) { bufStr(b, "..."); break; }
        if (i) bufStr(b, ", ");
        if (!appendValue(b, l->items[i], true, depth + 1)) return false;
      }
      bufChar(b, ']');
      return true;
    }
    case OBJ_MAP: {
      Map* m = &AS_MAP(v)->map;
      if (depth > 6) { bufStr(b, "{...}"); return true; }
      bufChar(b, '{');
      bool first = true;
      for (int i = 0; i < m->count; i++) {
        if (!m->entries[i].live) continue;
        if (b->len > (4 << 20)) { bufStr(b, "..."); break; }
        if (!first) bufStr(b, ", ");
        first = false;
        Value k = m->entries[i].key;
        if (IS_STRING(k) && isIdentifier(AS_CSTRING(k), AS_STRING(k)->length)) bufAppend(b, AS_CSTRING(k), AS_STRING(k)->length);
        else if (!appendValue(b, k, true, depth + 1)) return false;
        bufStr(b, ": ");
        if (!appendValue(b, m->entries[i].value, true, depth + 1)) return false;
      }
      bufChar(b, '}');
      return true;
    }
    case OBJ_RANGE: {
      ObjRange* r = AS_RANGE(v);
      char a[32], z[32];
      formatNumber(r->start, a); formatNumber(r->end, z);
      if (r->step == 1) bufPrintf(b, "%s..%s", a, z);
      else { char s[32]; formatNumber(r->step, s); bufPrintf(b, "range(%s, %s, %s)", a, z, s); }
      return true;
    }
    case OBJ_FUNCTION: bufPrintf(b, "<fn %s>", AS_FUNCTION(v)->name ? AS_FUNCTION(v)->name->chars : "anonymous"); return true;
    case OBJ_CLOSURE: {
      ObjFunction* f = AS_CLOSURE(v)->function;
      bufPrintf(b, "<fn %s>", f->name ? f->name->chars : "anonymous");
      return true;
    }
    case OBJ_NATIVE: bufPrintf(b, "<native %s>", AS_NATIVE(v)->name); return true;
    case OBJ_MODULE: bufPrintf(b, "<module %s>", AS_MODULE(v)->path->chars); return true;
    case OBJ_CLASS: bufPrintf(b, "<class %s>", AS_CLASS(v)->name->chars); return true;
    case OBJ_INSTANCE: {
      ObjInstance* inst = AS_INSTANCE(v);
      Value hook;
      if (!vm.noToStr && depth <= 6 && mapGet(&inst->klass->methods, OBJ_VAL(cstring("to_str")), &hook)) {
        Value res;
        if (!vmCall(OBJ_VAL(newBoundMethod(v, AS_CLOSURE(hook))), 0, NULL, &res)) return false;
        if (!IS_STRING(res)) return throwError("to_str() must return a string, but %s.to_str() returned %s", inst->klass->name->chars, typeName(res));
        bufAppend(b, AS_CSTRING(res), AS_STRING(res)->length);
        return true;
      }
      bufPrintf(b, "<%s instance>", inst->klass->name->chars);
      return true;
    }
    case OBJ_BOUND_METHOD: {
      ObjFunction* f = AS_BOUND(v)->method->function;
      bufPrintf(b, "<method %s>", f->name ? f->name->chars : "?");
      return true;
    }
    case OBJ_UPVALUE: bufStr(b, "<upvalue>"); return true;
    case OBJ_COROUTINE: bufPrintf(b, "<coroutine %s>", coroutineStatus(AS_COROUTINE(v))); return true;
  }
  return true;
}

ObjString* valueToString(Value v) {
  if (IS_STRING(v)) return AS_STRING(v);
  Buffer b; bufInit(&b);
  if (!appendValue(&b, v, false, 0)) { bufFree(&b); return NULL; }
  ObjString* s = newString(b.data ? b.data : "", b.len);
  bufFree(&b);
  return s;
}

/* ---------------------------------------------------------------------- GC */

static void markObject(Obj* o) {
  if (!o || o->isMarked) return;
  o->isMarked = true;
  if (vm.grayCap < vm.grayCount + 1) {
    vm.grayCap = vm.grayCap < 8 ? 8 : vm.grayCap * 2;
    vm.grayStack = realloc(vm.grayStack, sizeof(Obj*) * (size_t)vm.grayCap);
    if (!vm.grayStack) exit(70);
  }
  vm.grayStack[vm.grayCount++] = o;
}
static void markValue(Value v) { if (IS_OBJ(v)) markObject(AS_OBJ(v)); }
static void markMap(Map* m) {
  for (int i = 0; i < m->count; i++) if (m->entries[i].live) { markValue(m->entries[i].key); markValue(m->entries[i].value); }
}

/* everything a context keeps alive: its stack values, the functions running in it, its open upvalues */
static void markContext(Context* c) {
  if (!c->stack) return;
  for (Value* s = c->stack; s < c->stackTop; s++) markValue(*s);
  for (int i = 0; i < c->frameCount; i++) markObject((Obj*)c->frames[i].closure);
  for (ObjUpvalue* u = c->openUpvalues; u; u = u->next) markObject((Obj*)u);
}

static void blacken(Obj* o) {
  switch (o->type) {
    case OBJ_FUNCTION: {
      ObjFunction* f = (ObjFunction*)o;
      markObject((Obj*)f->name); markObject((Obj*)f->module);
      for (int i = 0; i < f->chunk.constants.count; i++) markValue(f->chunk.constants.values[i]);
      break;
    }
    case OBJ_CLOSURE: {
      ObjClosure* c = (ObjClosure*)o;
      markObject((Obj*)c->function);
      for (int i = 0; i < c->upvalueCount; i++) markObject((Obj*)c->upvalues[i]);
      break;
    }
    case OBJ_UPVALUE: markValue(*((ObjUpvalue*)o)->location); break;   /* an open upvalue may outlive the coroutine stack it points into */
    case OBJ_LIST: {
      ObjList* l = (ObjList*)o;
      for (int i = 0; i < l->count; i++) markValue(l->items[i]);
      break;
    }
    case OBJ_MAP: markMap(&((ObjMap*)o)->map); break;
    case OBJ_MODULE: {
      ObjModule* m = (ObjModule*)o;
      markObject((Obj*)m->path); markObject((Obj*)m->exports); markMap(&m->globals);
      break;
    }
    case OBJ_CLASS: {
      ObjClass* k = (ObjClass*)o;
      markObject((Obj*)k->name); markObject((Obj*)k->super); markMap(&k->methods);
      break;
    }
    case OBJ_INSTANCE: {
      ObjInstance* i = (ObjInstance*)o;
      markObject((Obj*)i->klass); markMap(&i->fields);
      break;
    }
    case OBJ_BOUND_METHOD: {
      ObjBoundMethod* b = (ObjBoundMethod*)o;
      markValue(b->receiver); markObject((Obj*)b->method);
      break;
    }
    case OBJ_COROUTINE: {
      ObjCoroutine* c = (ObjCoroutine*)o;
      markValue(c->fn);
      if (c->state == CO_SUSPENDED) markContext(&c->ctx);
      break;
    }
    case OBJ_STRING: case OBJ_NATIVE: case OBJ_RANGE: break;
  }
}

/* A coroutine's stack is freed with it. Closures that captured its variables must keep them, so the upvalues
   are closed first, while every object is still allocated (the sweep may free them in any order). */
static void detachCoroutineUpvalues(ObjCoroutine* c) {
  for (ObjUpvalue* u = c->ctx.openUpvalues; u; u = u->next) { u->closed = *u->location; u->location = &u->closed; }
  c->ctx.openUpvalues = NULL;
}

static void releaseCoroutine(ObjCoroutine* c) {
  reallocate(c->ctx.stack, sizeof(Value) * (size_t)(c->ctx.stackEnd - c->ctx.stack), 0);
  reallocate(c->ctx.frames, sizeof(CallFrame) * (size_t)c->ctx.frameMax, 0);
  reallocate(c->ctx.handlers, sizeof(Handler) * (size_t)c->ctx.handlerMax, 0);
  memset(&c->ctx, 0, sizeof c->ctx);
}

static void freeObject(Obj* o) {
  switch (o->type) {
    case OBJ_STRING: reallocate(o, sizeof(ObjString) + (size_t)((ObjString*)o)->length + 1, 0); break;
    case OBJ_FUNCTION: chunkFree(&((ObjFunction*)o)->chunk); FREE(ObjFunction, o); break;
    case OBJ_CLOSURE: {
      ObjClosure* c = (ObjClosure*)o;
      FREE_ARRAY(ObjUpvalue*, c->upvalues, c->upvalueCount);
      FREE(ObjClosure, o);
      break;
    }
    case OBJ_UPVALUE: FREE(ObjUpvalue, o); break;
    case OBJ_NATIVE: FREE(ObjNative, o); break;
    case OBJ_LIST: FREE_ARRAY(Value, ((ObjList*)o)->items, ((ObjList*)o)->capacity); FREE(ObjList, o); break;
    case OBJ_MAP: mapFree(&((ObjMap*)o)->map); FREE(ObjMap, o); break;
    case OBJ_RANGE: FREE(ObjRange, o); break;
    case OBJ_MODULE: mapFree(&((ObjModule*)o)->globals); FREE(ObjModule, o); break;
    case OBJ_CLASS: mapFree(&((ObjClass*)o)->methods); FREE(ObjClass, o); break;
    case OBJ_INSTANCE: mapFree(&((ObjInstance*)o)->fields); FREE(ObjInstance, o); break;
    case OBJ_BOUND_METHOD: FREE(ObjBoundMethod, o); break;
    case OBJ_COROUTINE: releaseCoroutine((ObjCoroutine*)o); FREE(ObjCoroutine, o); break;
  }
}

void collectGarbage(void) {
  for (Value* s = vm.stack; s < vm.stackTop; s++) markValue(*s);
  for (int i = 0; i < vm.frameCount; i++) markObject((Obj*)vm.frames[i].closure);
  for (ObjUpvalue* u = vm.openUpvalues; u; u = u->next) markObject((Obj*)u);
  /* coroutines that are running right now: the one on top, and the stacks of everyone who resumed it */
  for (ObjCoroutine* c = vm.currentCo; c; c = c->resumer) { markObject((Obj*)c); markContext(&c->host); }
  markValue(vm.yieldValue);
  markMap(&vm.builtins);
  markMap(&vm.modules);
  markObject((Obj*)vm.mainModule);
  markValue(vm.thrown);
  markValue(vm.fxCompile);

  while (vm.grayCount > 0) blacken(vm.grayStack[--vm.grayCount]);
  removeWhiteStrings();

  for (Obj* o = vm.objects; o; o = o->next)
    if (o->type == OBJ_COROUTINE && !o->isMarked) detachCoroutineUpvalues((ObjCoroutine*)o);

  Obj** link = &vm.objects;
  while (*link) {
    Obj* o = *link;
    if (o->isMarked) { o->isMarked = false; link = &o->next; }
    else { *link = o->next; freeObject(o); }
  }
  vm.nextGC = vm.bytesAllocated * 2;
  if (vm.nextGC < 1024 * 1024) vm.nextGC = 1024 * 1024;
}

void maybeGC(void) {
  if (vm.gcPause) return;
#ifdef FAXAL_GC_STRESS
  collectGarbage();
#else
  if (vm.bytesAllocated > vm.nextGC) collectGarbage();
#endif
}

void freeObjects(void) {
  for (Obj* d = vm.objects; d; d = d->next) if (d->type == OBJ_COROUTINE) detachCoroutineUpvalues((ObjCoroutine*)d);
  Obj* o = vm.objects;
  while (o) { Obj* next = o->next; freeObject(o); o = next; }
  vm.objects = NULL;
  free(vm.grayStack); vm.grayStack = NULL;
  free(vm.strings); vm.strings = NULL; vm.stringCap = 0; vm.stringUsed = 0;
}
