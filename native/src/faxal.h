#ifndef FAXAL_H
#define FAXAL_H

#include "platform.h"
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#define FAXAL_VERSION "1.0.0"
#define FRAMES_MAX 1500
#define STACK_MAX (FRAMES_MAX * 256)
#define HANDLERS_MAX 256
#define STACK_SLACK 140000

/* ------------------------------------------------------------------ values */

typedef struct Obj Obj;
typedef struct ObjString ObjString;
typedef struct ObjFunction ObjFunction;
typedef struct ObjClosure ObjClosure;
typedef struct ObjUpvalue ObjUpvalue;
typedef struct ObjNative ObjNative;
typedef struct ObjList ObjList;
typedef struct ObjMap ObjMap;
typedef struct ObjRange ObjRange;
typedef struct ObjModule ObjModule;
typedef struct ObjClass ObjClass;
typedef struct ObjInstance ObjInstance;
typedef struct ObjBoundMethod ObjBoundMethod;
typedef struct ObjCoroutine ObjCoroutine;

typedef enum { VAL_NIL, VAL_BOOL, VAL_NUM, VAL_OBJ } ValueType;

typedef struct {
  ValueType type;
  union { bool boolean; double number; Obj* obj; } as;
} Value;

#define NIL_VAL        ((Value){VAL_NIL, {.number = 0}})
#define BOOL_VAL(v)    ((Value){VAL_BOOL, {.boolean = (v)}})
#define NUM_VAL(v)     ((Value){VAL_NUM, {.number = (v)}})
#define OBJ_VAL(o)     ((Value){VAL_OBJ, {.obj = (Obj*)(o)}})

#define IS_NIL(v)      ((v).type == VAL_NIL)
#define IS_BOOL(v)     ((v).type == VAL_BOOL)
#define IS_NUM(v)      ((v).type == VAL_NUM)
#define IS_OBJ(v)      ((v).type == VAL_OBJ)
#define AS_BOOL(v)     ((v).as.boolean)
#define AS_NUM(v)      ((v).as.number)
#define AS_OBJ(v)      ((v).as.obj)

typedef enum {
  OBJ_STRING, OBJ_FUNCTION, OBJ_CLOSURE, OBJ_UPVALUE, OBJ_NATIVE,
  OBJ_LIST, OBJ_MAP, OBJ_RANGE, OBJ_MODULE, OBJ_CLASS, OBJ_INSTANCE, OBJ_BOUND_METHOD,
  OBJ_COROUTINE
} ObjType;

struct Obj { ObjType type; bool isMarked; struct Obj* next; };

#define OBJ_TYPE(v)     (AS_OBJ(v)->type)
#define IS_OBJ_TYPE(v, t) (IS_OBJ(v) && OBJ_TYPE(v) == (t))
#define IS_STRING(v)    IS_OBJ_TYPE(v, OBJ_STRING)
#define IS_FUNCTION(v)  IS_OBJ_TYPE(v, OBJ_FUNCTION)
#define IS_CLOSURE(v)   IS_OBJ_TYPE(v, OBJ_CLOSURE)
#define IS_NATIVE(v)    IS_OBJ_TYPE(v, OBJ_NATIVE)
#define IS_LIST(v)      IS_OBJ_TYPE(v, OBJ_LIST)
#define IS_MAP(v)       IS_OBJ_TYPE(v, OBJ_MAP)
#define IS_RANGE(v)     IS_OBJ_TYPE(v, OBJ_RANGE)
#define IS_MODULE(v)    IS_OBJ_TYPE(v, OBJ_MODULE)
#define IS_CLASS(v)     IS_OBJ_TYPE(v, OBJ_CLASS)
#define IS_INSTANCE(v)  IS_OBJ_TYPE(v, OBJ_INSTANCE)
#define IS_BOUND(v)     IS_OBJ_TYPE(v, OBJ_BOUND_METHOD)
#define IS_COROUTINE(v) IS_OBJ_TYPE(v, OBJ_COROUTINE)
#define AS_COROUTINE(v) ((ObjCoroutine*)AS_OBJ(v))
#define IS_CALLABLE(v)  (IS_CLOSURE(v) || IS_NATIVE(v) || IS_CLASS(v) || IS_BOUND(v))

#define AS_STRING(v)    ((ObjString*)AS_OBJ(v))
#define AS_CSTRING(v)   (AS_STRING(v)->chars)
#define AS_FUNCTION(v)  ((ObjFunction*)AS_OBJ(v))
#define AS_CLOSURE(v)   ((ObjClosure*)AS_OBJ(v))
#define AS_NATIVE(v)    ((ObjNative*)AS_OBJ(v))
#define AS_LIST(v)      ((ObjList*)AS_OBJ(v))
#define AS_MAP(v)       ((ObjMap*)AS_OBJ(v))
#define AS_RANGE(v)     ((ObjRange*)AS_OBJ(v))
#define AS_MODULE(v)    ((ObjModule*)AS_OBJ(v))
#define AS_CLASS(v)     ((ObjClass*)AS_OBJ(v))
#define AS_INSTANCE(v)  ((ObjInstance*)AS_OBJ(v))
#define AS_BOUND(v)     ((ObjBoundMethod*)AS_OBJ(v))

typedef struct { Value* values; int count; int capacity; } ValueArray;

/* An insertion-ordered hash map. `entries` keeps order; `index` is the hash table. */
typedef struct { Value key; Value value; bool live; } Entry;
typedef struct {
  Entry* entries; int count; int capacity; int live;
  int32_t* index; int indexCap;
} Map;

typedef struct { uint8_t* code; int* lines; int count; int capacity; ValueArray constants; } Chunk;

struct ObjString { Obj obj; int length; uint32_t hash; char chars[]; };
struct ObjFunction { Obj obj; int arity; int minArity; int upvalueCount; Chunk chunk; ObjString* name; ObjModule* module; bool isScript; };
struct ObjUpvalue { Obj obj; Value* location; Value closed; struct ObjUpvalue* next; };
struct ObjClosure { Obj obj; ObjFunction* function; ObjUpvalue** upvalues; int upvalueCount; };
typedef bool (*NativeFn)(int argc, Value* args, Value* out);
struct ObjNative { Obj obj; NativeFn fn; const char* name; int minArgs; int maxArgs; };
struct ObjList { Obj obj; Value* items; int count; int capacity; };
struct ObjMap { Obj obj; Map map; };
struct ObjRange { Obj obj; double start; double end; double step; };
struct ObjModule { Obj obj; ObjString* path; Map globals; ObjMap* exports; bool loading; };

struct ObjClass { Obj obj; ObjString* name; ObjClass* super; Map methods; };
struct ObjInstance { Obj obj; ObjClass* klass; Map fields; };
struct ObjBoundMethod { Obj obj; Value receiver; ObjClosure* method; };

typedef struct { const char* name; NativeFn fn; int minArgs; int maxArgs; } MethodDef;

/* One execution context: a value stack, call frames, try handlers and the open upvalues that point into the
   stack. The main program has one; every coroutine has its own, and the VM swaps them in and out. */
typedef struct CallFrame CallFrame;
typedef struct Handler Handler;
typedef struct {
  Value* stack; Value* stackTop; Value* stackEnd;
  CallFrame* frames; int frameCount, frameMax;
  Handler* handlers; int handlerCount, handlerMax;
  ObjUpvalue* openUpvalues;
} Context;

typedef enum { CO_NEW, CO_SUSPENDED, CO_RUNNING, CO_DONE, CO_FAILED } CoState;
struct ObjCoroutine {
  Obj obj;
  Value fn;                 /* what runs inside the coroutine */
  CoState state;
  Context ctx;              /* its own stack and frames while it is not running */
  Context host;             /* the stack of whoever resumed it, while it is running */
  ObjCoroutine* resumer;    /* ... and that resumer, if it is a coroutine too */
  int depth;                /* vm.nativeDepth while it runs: yield must happen at exactly this depth */
  int yieldArgc;            /* how many arguments the pending yield() call has on the stack */
};

/* ---------------------------------------------------------------- bytecode */

typedef enum {
  OP_CONSTANT, OP_NIL, OP_TRUE, OP_FALSE, OP_POP, OP_DUP, OP_DUP2,
  OP_GET_LOCAL, OP_SET_LOCAL, OP_GET_GLOBAL, OP_DEFINE_GLOBAL, OP_SET_GLOBAL,
  OP_GET_UPVALUE, OP_SET_UPVALUE, OP_GET_PROPERTY, OP_SET_PROPERTY,
  OP_GET_INDEX, OP_SET_INDEX, OP_SLICE,
  OP_EQUAL, OP_GREATER, OP_LESS, OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_POW,
  OP_NEG, OP_NOT, OP_IN, OP_RANGE,
  OP_JUMP, OP_JUMP_IF_FALSE, OP_LOOP,
  OP_CALL, OP_INVOKE, OP_CLOSURE, OP_CLOSE_UPVALUE, OP_RETURN,
  OP_BUILD_LIST, OP_BUILD_MAP, OP_FOR_NEXT,
  OP_TRY, OP_END_TRY, OP_THROW, OP_IMPORT, OP_REPL_PRINT,
  OP_CLASS, OP_INHERIT, OP_METHOD, OP_GET_SUPER, OP_SUPER_INVOKE,
  OP_SWAP, OP_BY, OP_JUMP_IF_NIL, OP_JUMP_IF_NOT_NIL,
  OP_COUNT /* not an instruction: the number of instructions */
} OpCode;

/* Bump this whenever an opcode is added, removed, reordered or changes meaning: it is stored in .fxc files. */
#define FAXAL_BYTECODE_REVISION 1

/* ---------------------------------------------------------------------- VM */

typedef struct { char* data; int len; int cap; } Buffer;

struct CallFrame { ObjClosure* closure; uint8_t* ip; Value* slots; };
struct Handler { int frame; Value* sp; uint8_t* catchIp; };

typedef struct { double x1, y1, x2, y2; char* color; double width; } Segment;
typedef struct { int kind; double x, y, a, b; char* color; double width; char* text; } Shape;
enum { SHAPE_CIRCLE, SHAPE_DISC, SHAPE_RECT, SHAPE_BOX, SHAPE_TEXT };
typedef struct {
  double x, y, angle; bool down; char* color; double width; char* background;
  Segment* segs; int count; int cap;
  Shape* shapes; int shapeCount; int shapeCap;
} Turtle;

typedef struct { char* path; char* source; size_t length; bool isBytecode; } BundleFile;   /* a file packed inside an executable made by `faxal build` (source text or a .fxc) */
typedef struct { const char* name; const unsigned char* data; size_t length; } EmbeddedFile;   /* a compiled Faxal module (.fxc bytes) built into the faxal binary itself */

typedef struct {
  /* the running execution context (see Context): the main program's, or the current coroutine's */
  Value* stack; Value* stackTop; Value* stackEnd;
  CallFrame* frames; int frameCount, frameMax;
  Handler* handlers; int handlerCount, handlerMax;
  ObjUpvalue* openUpvalues;
  ObjCoroutine* currentCo; bool yielded; Value yieldValue;
  Map builtins; Map modules; ObjModule* mainModule;
  ObjString** strings; int stringCap; int stringUsed;
  Obj* objects; size_t bytesAllocated; size_t nextGC;
  Obj** grayStack; int grayCount; int grayCap;
  Value thrown; char* traceback; int errorLine; bool fatal;
  bool sandbox, jsonMode, dumpCode, replMode;
  int gcPause;
  int nativeDepth; /* how many natives are currently running VM code (bounds C stack use) */
  bool noToStr; /* skip to_str hooks (used while reporting errors) */
  uint64_t steps, maxSteps; size_t maxMemory; size_t maxOutput;
  Buffer out; bool outTruncated;
  Turtle turtle;
  int scriptArgc; char** scriptArgv;
  BundleFile* bundle; int bundleCount;
  Value fxCompile; /* the compile function of the compiler written in Faxal, when --self-hosted is on (else nil) */
} VM;

extern VM vm;

/* the length in bytes of the UTF-8 character that starts with byte c */
static inline int utf8Len(unsigned char c) { return c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 1; }

/* ---------------------------------------------------------------- services */

/* buffers (plain malloc, not GC managed) */
void bufInit(Buffer* b);
void bufFree(Buffer* b);
void bufAppend(Buffer* b, const char* s, int n);
void bufStr(Buffer* b, const char* s);
void bufChar(Buffer* b, char c);
void bufPrintf(Buffer* b, const char* fmt, ...);

/* memory + GC */
void* reallocate(void* ptr, size_t oldSize, size_t newSize);
#define ALLOCATE(type, count) ((type*)reallocate(NULL, 0, sizeof(type) * (size_t)(count)))
#define FREE(type, p) reallocate((p), sizeof(type), 0)
#define GROW_CAPACITY(c) ((c) < 8 ? 8 : (c) * 2)
#define GROW_ARRAY(type, p, o, n) ((type*)reallocate((p), sizeof(type) * (size_t)(o), sizeof(type) * (size_t)(n)))
#define FREE_ARRAY(type, p, o) reallocate((p), sizeof(type) * (size_t)(o), 0)
void collectGarbage(void);
void freeObjects(void);
void maybeGC(void);

/* objects */
ObjString* newString(const char* chars, int length);
ObjString* cstring(const char* chars);
ObjFunction* newFunction(void);
ObjClosure* newClosure(ObjFunction* function);
ObjUpvalue* newUpvalue(Value* slot);
ObjNative* newNative(const char* name, NativeFn fn, int minArgs, int maxArgs);
ObjList* newList(void);
void listPush(ObjList* l, Value v);
ObjMap* newMap(void);
ObjRange* newRange(double start, double end, double step);
ObjModule* newModule(ObjString* path);
ObjClass* newClass(ObjString* name);
ObjInstance* newInstance(ObjClass* klass);
ObjBoundMethod* newBoundMethod(Value receiver, ObjClosure* method);
ObjCoroutine* newCoroutine(Value fn);
bool coroutineResume(ObjCoroutine* co, Value sent, bool inject, Value* out);
const char* coroutineStatus(ObjCoroutine* co);
extern const MethodDef coroutineMethods[];

/* values */
bool valuesEqual(Value a, Value b);
bool isFalsey(Value v);
const char* typeName(Value v);
void formatNumber(double d, char* buf);
/* Both may run user code (a class's to_str method), so they can fail: false / NULL with vm.thrown set. */
bool appendValue(Buffer* b, Value v, bool repr, int depth);
ObjString* valueToString(Value v);
int rangeLength(ObjRange* r);

/* maps */
void mapInit(Map* m);
void mapFree(Map* m);
bool mapGet(Map* m, Value key, Value* out);
bool mapSet(Map* m, Value key, Value value);   /* true if key was new */
bool mapDelete(Map* m, Value key);
bool validKey(Value key);

/* chunks */
void chunkInit(Chunk* c);
void chunkFree(Chunk* c);
void chunkWrite(Chunk* c, uint8_t byte, int line);
int chunkAddConstant(Chunk* c, Value v);

/* compiler */
ObjFunction* compile(const char* source, ObjModule* module, bool* needMoreInput);
extern bool compileQuiet;
extern int compileErrorLine, compileErrorCol;
extern char compileErrorMsg[512];

/* vm */
char* readFile(const char* path);
void vmInit(void);
void vmFree(void);
void push(Value v);
Value pop(void);
bool throwError(const char* fmt, ...);
bool vmCall(Value fn, int argc, Value* argv, Value* out);
bool vmWrite(const char* s, int n);
int runFunction(ObjFunction* f);
int runSource(const char* source, ObjModule* module); /* compile + run, printing nothing */
int interpret(const char* source, ObjModule* module, bool* needMoreInput);   /* 0 ok, 65 compile, 70 runtime */
ObjModule* loadMainModule(const char* path);
void defineNative(Map* m, const char* name, NativeFn fn, int minArgs, int maxArgs);
void defineValue(Map* m, const char* name, Value v);
const MethodDef* findMethod(Value receiver, ObjString* name);
void registerCoroutineBuiltins(Map* g);

/* embedded Faxal sources (generated into embedded.c by tools/embed.fx) */
extern const EmbeddedFile embeddedFiles[];
extern const int embeddedCount;
const EmbeddedFile* findEmbedded(const char* name);
bool importModule(Value pathv, ObjModule* importer, Value* out);
bool resolveImport(const char* rel, ObjModule* importer, char* resolved); /* file system lookup, used by `faxal build` */

/* standalone executables */
bool loadBundleFromSelf(void);
int cmdBuild(int argc, char** argv, int first);

/* the compiler written in Faxal (see selfhost.c) */
ObjFunction* compileWithFaxal(const char* source, ObjModule* module, bool* needMoreInput);
bool enableSelfHostedCompiler(void);
void printCompileError(const char* path, int line, int col, const char* text, int textLen, int underline, const char* message);

/* bytecode files (.fxc), see bytecode.c and docs/BYTECODE.md */
bool bytecodeWrite(ObjFunction* main, const char* sourceName, Buffer* out);
ObjFunction* bytecodeRead(const unsigned char* data, size_t len, ObjModule* module, char* sourceName, size_t sourceCap, char* err, size_t errCap);
bool bytecodeLooksLike(const unsigned char* data, size_t len);
bool bytecodeSourceName(const unsigned char* data, size_t len, char* out, size_t cap);
void bytecodeDump(ObjFunction* main);
bool verifyProgram(ObjFunction** fns, int count, char* err, size_t errCap);
unsigned char* readFileBytes(const char* path, size_t* len);

/* compile-time hook used by `faxal build` to find imports */
extern bool compileCollectImports;
extern char** compiledImports;
extern int compiledImportCount;

/* stdlib */
void registerBuiltins(void);
void turtleToSvg(Buffer* b);
void turtleToJson(Buffer* b);
void jsonQuote(Buffer* b, const char* s, int len);

/* debug */
void disassembleFunction(ObjFunction* f);

#endif
