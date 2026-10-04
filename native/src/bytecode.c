/* bytecode.c: the .fxc bytecode file format: writing, reading and verifying.
 *
 * A .fxc file holds one compiled module: every function in it with its instructions, line numbers and
 * constants. The exact layout is described in docs/BYTECODE.md.
 *
 * Reading never trusts the file. The checksum catches damage, every length is checked against the bytes that
 * are left, and then the verifier (below) proves, before anything runs, that the code can't misuse the stack.
 */
#include "faxal.h"
#include <math.h>

#define FXC_MAGIC "\x7f" "FXC"   /* starts with DEL, which can never begin valid Faxal source */
#define FORMAT_VERSION 2   /* 2 added the parameter names after each function header; version 1 files still load */
#define MAX_FUNCTIONS 100000
#define MAX_STACK_DEPTH 139000   /* below the slack the VM keeps after STACK_MAX, see faxal.h */

bool bytecodeLooksLike(const unsigned char* data, size_t len) { return len >= 4 && memcmp(data, FXC_MAGIC, 4) == 0; }

static uint32_t checksum(const unsigned char* d, size_t n) {
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < n; i++) { h ^= d[i]; h *= 16777619u; }
  return h;
}

/* ------------------------------------------------------------------ writing */

static void put8(Buffer* b, unsigned v) { char c = (char)v; bufAppend(b, &c, 1); }
static void put16(Buffer* b, unsigned v) { put8(b, v & 0xff); put8(b, (v >> 8) & 0xff); }
static void put32(Buffer* b, uint32_t v) { put16(b, v & 0xffff); put16(b, v >> 16); }
static void putDouble(Buffer* b, double d) {
  uint64_t bits;
  memcpy(&bits, &d, sizeof bits);
  put32(b, (uint32_t)(bits & 0xffffffffu));
  put32(b, (uint32_t)(bits >> 32));
}
static void putBytes(Buffer* b, const char* s, size_t n) { put32(b, (uint32_t)n); bufAppend(b, s, (int)n); }

typedef struct { ObjFunction** list; int count; int cap; } FnList;

static int indexOf(FnList* l, ObjFunction* f) {
  for (int i = 0; i < l->count; i++) if (l->list[i] == f) return i;
  return -1;
}

/* Post-order walk: a function is listed after every function it contains, and the main script is last. */
static void collectFunctions(FnList* l, ObjFunction* f) {
  if (indexOf(l, f) >= 0) return;
  for (int i = 0; i < f->chunk.constants.count; i++) {
    Value c = f->chunk.constants.values[i];
    if (IS_FUNCTION(c)) collectFunctions(l, AS_FUNCTION(c));
  }
  if (l->count == l->cap) { l->cap = l->cap ? l->cap * 2 : 16; l->list = realloc(l->list, sizeof(ObjFunction*) * (size_t)l->cap); }
  l->list[l->count++] = f;
}

bool bytecodeWrite(ObjFunction* main, const char* sourceName, Buffer* out) {
  FnList l = { NULL, 0, 0 };
  collectFunctions(&l, main);

  bufAppend(out, FXC_MAGIC, 4);
  put16(out, FORMAT_VERSION);
  put16(out, FAXAL_BYTECODE_REVISION);
  put32(out, 0);                                  /* flags: none yet */
  putBytes(out, FAXAL_VERSION, strlen(FAXAL_VERSION));
  putBytes(out, sourceName, strlen(sourceName));
  put32(out, (uint32_t)l.count);

  for (int i = 0; i < l.count; i++) {
    ObjFunction* f = l.list[i];
    if (f->name) putBytes(out, f->name->chars, (size_t)f->name->length); else put32(out, 0xffffffffu);
    put8(out, (unsigned)f->arity);
    put8(out, (unsigned)f->minArity);
    put16(out, (unsigned)f->upvalueCount);
    put8(out, f->isScript ? 1 : 0);
    put8(out, f->paramNames ? 1 : 0);                    /* parameter names follow (so named arguments work) */
    if (f->paramNames) for (int k = 0; k < f->arity; k++) putBytes(out, f->paramNames[k]->chars, (size_t)f->paramNames[k]->length);

    Chunk* c = &f->chunk;
    put32(out, (uint32_t)c->count);
    bufAppend(out, (const char*)c->code, c->count);

    /* line numbers as runs: (line, how many bytes of code are on that line) */
    int runs = 0;
    for (int k = 0; k < c->count; k++) if (k == 0 || c->lines[k] != c->lines[k - 1]) runs++;
    put32(out, (uint32_t)runs);
    for (int k = 0; k < c->count;) {
      int j = k;
      while (j < c->count && c->lines[j] == c->lines[k]) j++;
      put32(out, (uint32_t)c->lines[k]);
      put32(out, (uint32_t)(j - k));
      k = j;
    }

    put32(out, (uint32_t)c->constants.count);
    for (int k = 0; k < c->constants.count; k++) {
      Value v = c->constants.values[k];
      if (IS_NUM(v)) { put8(out, 0); putDouble(out, AS_NUM(v)); }
      else if (IS_STRING(v)) { put8(out, 1); putBytes(out, AS_CSTRING(v), (size_t)AS_STRING(v)->length); }
      else if (IS_FUNCTION(v)) { put8(out, 2); put32(out, (uint32_t)indexOf(&l, AS_FUNCTION(v))); }
      else { free(l.list); return false; }
    }
  }
  put32(out, checksum((const unsigned char*)out->data, (size_t)out->len));
  free(l.list);
  return true;
}

/* ------------------------------------------------------------------ reading */

typedef struct { const unsigned char* p; size_t left; const char* why; } Cursor;

static bool need(Cursor* c, size_t n) {
  if (c->why) return false;
  if (c->left < n) { c->why = "the file ends too early"; return false; }
  return true;
}
static uint32_t get8(Cursor* c) { if (!need(c, 1)) return 0; uint32_t v = c->p[0]; c->p++; c->left--; return v; }
static uint32_t get16(Cursor* c) { uint32_t a = get8(c); uint32_t b = get8(c); return a | b << 8; }
static uint32_t get32(Cursor* c) { uint32_t a = get16(c); uint32_t b = get16(c); return a | b << 16; }
static double getDouble(Cursor* c) {
  uint64_t lo = get32(c), hi = get32(c);
  uint64_t bits = lo | hi << 32;
  double d;
  memcpy(&d, &bits, sizeof d);
  return d;
}
/* A length-prefixed byte string; the length is checked against what is left in the file. */
static const unsigned char* getBytes(Cursor* c, uint32_t* n) {
  *n = get32(c);
  if (!need(c, *n)) { *n = 0; return NULL; }
  const unsigned char* start = c->p;
  c->p += *n;
  c->left -= *n;
  return start;
}

ObjFunction* bytecodeRead(const unsigned char* data, size_t len, ObjModule* module, char* sourceName, size_t sourceCap, char* err, size_t errCap) {
  ObjFunction** fns = NULL;
  ObjFunction* result = NULL;
  int count = 0;
#define FAIL(...) do { snprintf(err, errCap, __VA_ARGS__); goto done; } while (0)

  if (sourceName && sourceCap) sourceName[0] = '\0';
  if (!bytecodeLooksLike(data, len)) FAIL("this is not a Faxal bytecode file");
  if (len < 4 + 2 + 2 + 4 + 4 + 4 + 4 + 4) FAIL("the file is too short to be a bytecode file");
  uint32_t stored = (uint32_t)data[len - 4] | (uint32_t)data[len - 3] << 8 | (uint32_t)data[len - 2] << 16 | (uint32_t)data[len - 1] << 24;
  if (stored != checksum(data, len - 4)) FAIL("the file is damaged (its checksum does not match)");

  Cursor cur = { data + 4, len - 4 - 4, NULL };
  Cursor* c = &cur;
  uint32_t version = get16(c), revision = get16(c);
  if (version != FORMAT_VERSION && version != 1) FAIL("this bytecode file uses format version %u, but this faxal understands version %d", version, FORMAT_VERSION);
  if (revision != FAXAL_BYTECODE_REVISION) FAIL("this bytecode file was made by an incompatible faxal (instruction set %u, this faxal uses %d): compile it again", revision, FAXAL_BYTECODE_REVISION);
  get32(c); /* flags */
  uint32_t n;
  getBytes(c, &n); /* the faxal version that wrote the file (informational) */
  const unsigned char* src = getBytes(c, &n);
  if (sourceName && sourceCap && src) {
    size_t k = n < sourceCap - 1 ? n : sourceCap - 1;
    memcpy(sourceName, src, k);
    sourceName[k] = '\0';
  }
  uint32_t fcount = get32(c);
  if (c->why) FAIL("%s", c->why);
  if (fcount == 0 || fcount > MAX_FUNCTIONS || fcount > c->left / 20) FAIL("the file claims %u functions, which does not fit its size", fcount);

  fns = calloc(fcount, sizeof(ObjFunction*));
  for (uint32_t i = 0; i < fcount; i++) {
    ObjFunction* f = newFunction();
    fns[count++] = f;
    f->module = module;

    uint32_t nameLen = get32(c);
    if (nameLen != 0xffffffffu) {
      if (!need(c, nameLen)) FAIL("%s", c->why);
      f->name = newString((const char*)c->p, (int)nameLen);
      c->p += nameLen; c->left -= nameLen;
    }
    f->arity = (int)get8(c);
    f->minArity = (int)get8(c);
    f->upvalueCount = (int)get16(c);
    f->isScript = get8(c) == 1;
    if (version >= 2 && get8(c) == 1) {
      if (f->arity > 0) { f->paramNames = ALLOCATE(ObjString*, f->arity); for (int k = 0; k < f->arity; k++) f->paramNames[k] = NULL; }
      for (int k = 0; k < f->arity; k++) {
        uint32_t pl;
        const unsigned char* ps = getBytes(c, &pl);
        if (c->why) FAIL("%s", c->why);
        f->paramNames[k] = newString((const char*)ps, (int)pl);
      }
    }

    uint32_t codeLen = get32(c);
    if (c->why) FAIL("%s", c->why);
    if (codeLen == 0 || codeLen > c->left || codeLen > 100 * 1024 * 1024) FAIL("function %u has a code size that does not fit the file", i);
    const unsigned char* code = c->p;
    c->p += codeLen; c->left -= codeLen;

    uint32_t runs = get32(c);
    if (c->why) FAIL("%s", c->why);
    if (runs == 0 || runs > codeLen || runs > c->left / 8) FAIL("function %u has a bad line table", i);
    int* lines = malloc(sizeof(int) * codeLen);
    uint32_t at = 0;
    for (uint32_t r = 0; r < runs; r++) {
      uint32_t line = get32(c), run = get32(c);
      if (c->why || run == 0 || run > codeLen - at || line > 2147483647u) { free(lines); FAIL("function %u has a bad line table", i); }
      for (uint32_t k = 0; k < run; k++) lines[at + k] = (int)line;
      at += run;
    }
    if (at != codeLen) { free(lines); FAIL("function %u: the line table does not cover its code", i); }
    for (uint32_t k = 0; k < codeLen; k++) chunkWrite(&f->chunk, code[k], lines[k]);
    free(lines);

    uint32_t constCount = get32(c);
    if (c->why) FAIL("%s", c->why);
    if (constCount > 0xffff + 1 || constCount > c->left / 5) FAIL("function %u has too many constants", i);
    for (uint32_t k = 0; k < constCount; k++) {
      uint32_t tag = get8(c);
      if (tag == 0) chunkAddConstant(&f->chunk, NUM_VAL(getDouble(c)));
      else if (tag == 1) {
        uint32_t sl;
        const unsigned char* s = getBytes(c, &sl);
        if (c->why) FAIL("%s", c->why);
        chunkAddConstant(&f->chunk, OBJ_VAL(newString((const char*)s, (int)sl)));
      } else if (tag == 2) {
        uint32_t target = get32(c);
        if (c->why) FAIL("%s", c->why);
        if (target >= i) FAIL("function %u refers to a function that is not defined before it", i);
        chunkAddConstant(&f->chunk, OBJ_VAL(fns[target]));
      } else FAIL("function %u has a constant of an unknown kind (%u)", i, tag);
      if (c->why) FAIL("%s", c->why);
    }
    if (c->why) FAIL("%s", c->why);
  }
  if (c->left != 0) FAIL("there are %zu unexpected bytes after the last function", c->left);

  if (!fns[count - 1]->isScript) FAIL("the last function is not the main script");
  if (!verifyProgram(fns, count, err, errCap)) goto done;
  result = fns[count - 1];
done:
  free(fns);
  return result;
#undef FAIL
}

/* ----------------------------------------------------------------- verifier */

/* The verifier proves, without running anything, that the code of every function is safe for the VM:
 *   - every instruction is a real instruction and lies completely inside the code;
 *   - every jump lands exactly on the start of an instruction, and code never runs off its end;
 *   - the stack never underflows, never grows past a fixed limit, and has the same height every time
 *     the same instruction is reached by different routes;
 *   - local slots, upvalue numbers and constant numbers exist, and names are strings.
 * What the VM can only know while running (is this value a list? is it a number?) it checks itself. */

typedef struct { const char* why; int offset; } Fault;

static int opLength(uint8_t op) {
  switch (op) {
    case OP_CONSTANT: case OP_GET_GLOBAL: case OP_DEFINE_GLOBAL: case OP_SET_GLOBAL: case OP_GET_PROPERTY: case OP_SET_PROPERTY:
    case OP_CLASS: case OP_METHOD: case OP_GET_SUPER: case OP_JUMP: case OP_JUMP_IF_FALSE: case OP_LOOP: case OP_BUILD_LIST:
    case OP_BUILD_MAP: case OP_TRY: case OP_JUMP_IF_NIL: case OP_JUMP_IF_NOT_NIL: case OP_CLOSURE: return 3;
    case OP_GET_LOCAL: case OP_SET_LOCAL: case OP_GET_UPVALUE: case OP_SET_UPVALUE: case OP_CALL: return 2;
    case OP_INVOKE: case OP_SUPER_INVOKE: case OP_FOR_NEXT: return 4;
    default: return 1;
  }
}

static bool verifyFunction(ObjFunction* f, int index, char* err, size_t errCap) {
  Chunk* ch = &f->chunk;
  int n = ch->count;
  uint8_t* code = ch->code;
  int* depth = malloc(sizeof(int) * (size_t)n);
  unsigned char* inside = calloc((size_t)n, 1);
  int* work = malloc(sizeof(int) * ((size_t)n + 16));
  int workCount = 0;
  bool ok = false;
  Fault fault = { NULL, 0 };
  for (int i = 0; i < n; i++) depth[i] = -1;

#define FAULT(msg) do { fault.why = (msg); fault.offset = pc; goto finish; } while (0)
#define NEED(k) do { if (d < (k)) FAULT("the stack would underflow"); } while (0)
#define STRING_CONST(i) do { if ((i) >= ch->constants.count || !IS_STRING(ch->constants.values[(i)])) FAULT("a name constant is missing or not a string"); } while (0)

  if (f->arity < f->minArity) { fault.why = "it requires more arguments than it has parameters"; goto finish; }
  if (f->isScript && f->arity != 0) { fault.why = "the main script takes parameters"; goto finish; }
  if (f->isScript && f->upvalueCount != 0) { fault.why = "the main script captures variables"; goto finish; }
  if (f->upvalueCount > 256) { fault.why = "it captures too many variables"; goto finish; }
  if (n == 0) { fault.why = "it has no code"; goto finish; }
  depth[0] = 1 + f->arity;
  work[workCount++] = 0;
  int pc = 0;

  while (workCount > 0) {
    pc = work[--workCount];
    int d = depth[pc];
    if (inside[pc]) FAULT("a jump lands in the middle of an instruction");
    uint8_t op = code[pc];
    if (op >= OP_COUNT) FAULT("unknown instruction");
    int len = opLength(op);
    if (pc + len > n) FAULT("an instruction is cut off by the end of the code");

    int u16 = len >= 3 ? (code[pc + 1] << 8 | code[pc + 2]) : 0;
    if (op == OP_CLOSURE) {
      if (u16 >= ch->constants.count || !IS_FUNCTION(ch->constants.values[u16])) FAULT("a closure refers to something that is not a function");
      len = 3 + 2 * AS_FUNCTION(ch->constants.values[u16])->upvalueCount;
      if (pc + len > n) FAULT("an instruction is cut off by the end of the code");
    }
    for (int k = 1; k < len; k++) {
      if (depth[pc + k] != -1) FAULT("a jump lands in the middle of an instruction");
      inside[pc + k] = 1;
    }

    int next = d;          /* stack height after the instruction (for the instruction that follows it) */
    bool falls = true;     /* does execution continue with the next instruction? */
    switch (op) {
      case OP_CONSTANT: if (u16 >= ch->constants.count) FAULT("a constant number is out of range"); next = d + 1; break;
      case OP_NIL: case OP_TRUE: case OP_FALSE: next = d + 1; break;
      case OP_POP: NEED(1); next = d - 1; break;
      case OP_DUP: NEED(1); next = d + 1; break;
      case OP_DUP2: NEED(2); next = d + 2; break;
      case OP_GET_LOCAL: if (code[pc + 1] >= d) FAULT("a local variable slot is above the stack"); next = d + 1; break;
      case OP_SET_LOCAL: NEED(1); if (code[pc + 1] >= d) FAULT("a local variable slot is above the stack"); break;
      case OP_GET_GLOBAL: STRING_CONST(u16); next = d + 1; break;
      case OP_DEFINE_GLOBAL: STRING_CONST(u16); NEED(1); next = d - 1; break;
      case OP_SET_GLOBAL: STRING_CONST(u16); NEED(1); break;
      case OP_GET_UPVALUE: if (code[pc + 1] >= f->upvalueCount) FAULT("an upvalue number is out of range"); next = d + 1; break;
      case OP_SET_UPVALUE: NEED(1); if (code[pc + 1] >= f->upvalueCount) FAULT("an upvalue number is out of range"); break;
      case OP_GET_PROPERTY: STRING_CONST(u16); NEED(1); break;
      case OP_SET_PROPERTY: STRING_CONST(u16); NEED(2); next = d - 1; break;
      case OP_GET_INDEX: NEED(2); next = d - 1; break;
      case OP_SET_INDEX: case OP_SLICE: NEED(3); next = d - 2; break;
      case OP_EQUAL: case OP_GREATER: case OP_LESS: case OP_ADD: case OP_SUB: case OP_MUL: case OP_DIV: case OP_MOD: case OP_POW:
      case OP_IN: case OP_RANGE: case OP_BY: NEED(2); next = d - 1; break;
      case OP_NEG: case OP_NOT: NEED(1); break;
      case OP_SWAP: NEED(2); break;
      case OP_CALL: NEED(code[pc + 1] + 1); next = d - code[pc + 1]; break;
      case OP_INVOKE: STRING_CONST(u16); NEED(code[pc + 3] + 1); next = d - code[pc + 3]; break;
      case OP_SUPER_INVOKE: STRING_CONST(u16); NEED(code[pc + 3] + 2); next = d - code[pc + 3] - 1; break;
      case OP_CLOSURE: {
        ObjFunction* inner = AS_FUNCTION(ch->constants.values[u16]);
        for (int k = 0; k < inner->upvalueCount; k++) {
          int isLocal = code[pc + 3 + 2 * k], slot = code[pc + 4 + 2 * k];
          if (isLocal > 1) FAULT("a closure capture has a bad kind");
          /* a closure may capture its own variable (let f = fn() { ... f() ... }): that slot is the one it is about to fill, d */
          if (isLocal ? slot > d : slot >= f->upvalueCount) FAULT("a closure captures a variable that does not exist");
        }
        next = d + 1;
        break;
      }
      case OP_CLOSE_UPVALUE: NEED(1); next = d - 1; break;
      case OP_RETURN: NEED(1); falls = false; break;
      case OP_BUILD_LIST: NEED(u16); next = d - u16 + 1; break;
      case OP_BUILD_MAP: NEED(2 * u16); next = d - 2 * u16 + 1; break;
      case OP_END_TRY: break;
      case OP_THROW: NEED(1); falls = false; break;
      case OP_IMPORT: NEED(1); break;
      case OP_REPL_PRINT: NEED(1); next = d - 1; break;
      case OP_CLASS: STRING_CONST(u16); next = d + 1; break;
      case OP_INHERIT: NEED(2); next = d - 1; break;
      case OP_METHOD: STRING_CONST(u16); NEED(2); next = d - 1; break;
      case OP_GET_SUPER: STRING_CONST(u16); NEED(2); next = d - 1; break;
      case OP_JUMP: case OP_JUMP_IF_FALSE: case OP_JUMP_IF_NIL: case OP_JUMP_IF_NOT_NIL: case OP_LOOP: case OP_TRY: case OP_FOR_NEXT: break;
      default: break;
    }
    if (next > MAX_STACK_DEPTH) FAULT("the stack would grow too large");

    /* where execution can go next, with the stack height it arrives with */
    int targets[2], heights[2], tcount = 0;
    int after = pc + len;
    switch (op) {
      case OP_JUMP: targets[0] = after + u16; heights[0] = d; tcount = 1; falls = false; break;
      case OP_LOOP: targets[0] = after - u16; heights[0] = d; tcount = 1; falls = false; break;
      case OP_JUMP_IF_FALSE: case OP_JUMP_IF_NIL: case OP_JUMP_IF_NOT_NIL: targets[0] = after + u16; heights[0] = d; tcount = 1; break;
      case OP_TRY: targets[0] = after + u16; heights[0] = d + 1; tcount = 1; break;
      case OP_FOR_NEXT: {
        if ((int)code[pc + 1] + 1 >= d) FAULT("a loop uses stack slots that do not exist");
        targets[0] = after + (code[pc + 2] << 8 | code[pc + 3]); heights[0] = d; tcount = 1;
        next = d + 1;
        break;
      }
      default: break;
    }
    if (falls) { targets[tcount] = after; heights[tcount] = next; tcount++; }
    for (int k = 0; k < tcount; k++) {
      int t = targets[k], h = heights[k];
      if (t < 0 || t > n) FAULT("a jump goes outside the code");
      if (t == n) FAULT("the code can run past its end");
      if (h > MAX_STACK_DEPTH) FAULT("the stack would grow too large");
      if (depth[t] == -1) {
        if (inside[t]) FAULT("a jump lands in the middle of an instruction");
        depth[t] = h;
        work[workCount++] = t;
      } else if (depth[t] != h) FAULT("the stack has a different height depending on how this instruction is reached");
    }
  }
  ok = true;

finish:
  if (!ok) snprintf(err, errCap, "invalid bytecode in function %d (%s) at offset %d: %s", index, f->name ? f->name->chars : f->isScript ? "main script" : "anonymous", fault.offset, fault.why);
  free(depth);
  free(inside);
  free(work);
  return ok;
#undef FAULT
#undef NEED
#undef STRING_CONST
}

/* `fns` lists the functions of one module in definition order (inner functions first, the main script last). */
bool verifyProgram(ObjFunction** fns, int count, char* err, size_t errCap) {
  if (count <= 0) { snprintf(err, errCap, "invalid bytecode: no functions"); return false; }
  for (int i = 0; i < count; i++) {
    for (int k = 0; k < fns[i]->chunk.constants.count; k++) {
      Value c = fns[i]->chunk.constants.values[k];
      if (IS_FUNCTION(c)) {
        int found = -1;
        for (int j = 0; j < i; j++) if (fns[j] == AS_FUNCTION(c)) found = j;
        if (found < 0) { snprintf(err, errCap, "invalid bytecode in function %d: it refers to a function that is not defined before it", i); return false; }
      }
    }
    if (!verifyFunction(fns[i], i, err, errCap)) return false;
  }
  return true;
}

/* The name of the source file recorded in a .fxc file (without checking anything else). */
bool bytecodeSourceName(const unsigned char* data, size_t len, char* out, size_t cap) {
  if (!bytecodeLooksLike(data, len) || len < 4 + 2 + 2 + 4 + 4) return false;
  Cursor cur = { data + 4, len - 4, NULL };
  Cursor* c = &cur;
  get16(c); get16(c); get32(c);
  uint32_t n;
  getBytes(c, &n);
  const unsigned char* src = getBytes(c, &n);
  if (c->why || !src) return false;
  size_t k = n < cap - 1 ? n : cap - 1;
  memcpy(out, src, k);
  out[k] = '\0';
  return true;
}

/* Prints every function of a program, in definition order (the same text `faxal --dump` prints while compiling). */
void bytecodeDump(ObjFunction* main) {
  FnList l = { NULL, 0, 0 };
  collectFunctions(&l, main);
  for (int i = 0; i < l.count; i++) disassembleFunction(l.list[i]);
  free(l.list);
}
