/* compiler.c: scanner + single-pass bytecode compiler (Pratt parser) */
#include "faxal.h"
#include <ctype.h>

bool compileQuiet = false;
bool compileCollectImports = false;
char** compiledImports = NULL;
int compiledImportCount = 0;
int compileErrorLine, compileErrorCol;
char compileErrorMsg[512];

/* ------------------------------------------------------------------ scanner */

typedef enum {
  T_LPAREN, T_RPAREN, T_LBRACE, T_RBRACE, T_LBRACKET, T_RBRACKET,
  T_COMMA, T_DOT, T_DOTDOT, T_COLON, T_SEMI,
  T_MINUS, T_PLUS, T_SLASH, T_STAR, T_STARSTAR, T_PERCENT,
  T_PLUS_EQ, T_MINUS_EQ, T_STAR_EQ, T_SLASH_EQ, T_PERCENT_EQ,
  T_NE, T_EQ, T_EQEQ, T_GT, T_GE, T_LT, T_LE,
  T_IDENT, T_STRING, T_FSTRING, T_NUMBER,
  T_AND, T_OR, T_NOT, T_BREAK, T_CONTINUE, T_ELSE, T_FALSE, T_FN, T_FOR, T_IF,
  T_IMPORT, T_IN, T_LET, T_NIL, T_RETURN, T_TRUE, T_WHILE, T_TRY, T_CATCH, T_THROW,
  T_CLASS, T_EXTENDS, T_SELF, T_SUPER, T_BY,
  T_PIPE, T_QQ, T_QDOT, T_ARROW, T_RARROW, T_ASYNC, T_AWAIT,
  T_ERROR, T_EOF
} FxTokenType;

typedef struct { FxTokenType type; const char* start; int length; int line; const char* lineStart; } Token;

typedef struct {
  const char* start; const char* current; int line; const char* lineStart;
  int tokLine; const char* tokLineStart;
  FxTokenType last; char brackets[256]; int depth; bool eofSemi;
} Scanner;

static Scanner scanner;

static void initScanner(const char* source, int line) {
  memset(&scanner, 0, sizeof scanner);
  scanner.start = scanner.current = scanner.lineStart = scanner.tokLineStart = source;
  scanner.line = scanner.tokLine = line;
  scanner.last = T_SEMI;
}

static bool needsSemi(FxTokenType t) {
  switch (t) {
    case T_IDENT: case T_SELF: case T_NUMBER: case T_STRING: case T_FSTRING: case T_RPAREN: case T_RBRACKET: case T_RBRACE:
    case T_TRUE: case T_FALSE: case T_NIL: case T_BREAK: case T_CONTINUE: case T_RETURN: return true;
    default: return false;
  }
}

static bool isAlpha(char c) { return isalpha((unsigned char)c) || c == '_' || (unsigned char)c >= 0x80; }
static bool isDigit(char c) { return c >= '0' && c <= '9'; }

/* After a newline: does the next line continue this statement (else / and / or / .method)? */
static bool continuationAhead(const char* p) {
  for (;;) {
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (*p == '#') { while (*p && *p != '\n') p++; continue; }
    break;
  }
  if (*p == '.' && p[1] != '.') return true;
  if (p[0] == '|' && p[1] == '>') return true;
  if (p[0] == '?' && (p[1] == '?' || p[1] == '.')) return true;
  const char* words[] = {"else", "and", "or"};
  for (int i = 0; i < 3; i++) {
    size_t n = strlen(words[i]);
    if (strncmp(p, words[i], n) == 0 && !isAlpha(p[n]) && !isDigit(p[n])) return true;
  }
  return false;
}

static Token makeToken(FxTokenType type) {
  Token t = { type, scanner.start, (int)(scanner.current - scanner.start), scanner.tokLine, scanner.tokLineStart };
  scanner.last = type;
  if (type == T_LPAREN || type == T_LBRACKET || type == T_LBRACE) {
    if (scanner.depth < 255) scanner.brackets[scanner.depth] = type == T_LPAREN ? '(' : type == T_LBRACKET ? '[' : '{';
    scanner.depth++;
  } else if ((type == T_RPAREN || type == T_RBRACKET || type == T_RBRACE) && scanner.depth > 0) {
    scanner.depth--;
  }
  return t;
}

static Token errorToken(const char* msg) {
  Token t = { T_ERROR, msg, (int)strlen(msg), scanner.tokLine, scanner.tokLineStart };
  return t;
}

static bool newlinesSignificant(void) {
  return scanner.depth == 0 || (scanner.depth <= 256 && scanner.brackets[scanner.depth - 1] == '{');
}

static FxTokenType keywordType(const char* s, int n) {
  static const struct { const char* w; FxTokenType t; } kw[] = {
    {"and", T_AND}, {"async", T_ASYNC}, {"await", T_AWAIT}, {"break", T_BREAK}, {"catch", T_CATCH}, {"by", T_BY}, {"class", T_CLASS}, {"extends", T_EXTENDS}, {"self", T_SELF}, {"super", T_SUPER}, {"continue", T_CONTINUE}, {"else", T_ELSE},
    {"false", T_FALSE}, {"fn", T_FN}, {"for", T_FOR}, {"if", T_IF}, {"import", T_IMPORT}, {"in", T_IN},
    {"let", T_LET}, {"nil", T_NIL}, {"not", T_NOT}, {"or", T_OR}, {"return", T_RETURN}, {"throw", T_THROW},
    {"true", T_TRUE}, {"try", T_TRY}, {"while", T_WHILE},
  };
  for (size_t i = 0; i < sizeof kw / sizeof kw[0]; i++)
    if ((int)strlen(kw[i].w) == n && memcmp(kw[i].w, s, (size_t)n) == 0) return kw[i].t;
  return T_IDENT;
}

static Token scanString(char quote, bool interp) {
  int braceDepth = 0;
  while (*scanner.current) {
    char c = *scanner.current;
    if (c == quote && braceDepth == 0) break;
    if (c == '\\' && scanner.current[1]) {
      if (scanner.current[1] == '\n') { scanner.line++; scanner.lineStart = scanner.current + 2; }   /* an escaped line break is still a line */
      scanner.current += 2;
      continue;
    }
    if (!interp) { /* plain string: braces mean nothing */ }
    else if (c == '{') braceDepth++;
    else if (c == '}' && braceDepth > 0) braceDepth--;
    else if ((c == '"' || c == '\'') && braceDepth > 0) {
      char q = c;
      scanner.current++;
      while (*scanner.current && *scanner.current != q) {
        if (*scanner.current == '\\' && scanner.current[1]) scanner.current++;
        if (*scanner.current == '\n') { scanner.line++; scanner.lineStart = scanner.current + 1; } /* keep line numbers right */
        scanner.current++;
      }
    }
    if (*scanner.current == '\n') { scanner.line++; scanner.lineStart = scanner.current + 1; }
    if (*scanner.current) scanner.current++;
  }
  if (!*scanner.current) return errorToken("Unterminated string.");
  scanner.current++;
  return makeToken(interp ? T_FSTRING : T_STRING);
}

static Token scanToken(void) {
  for (;;) {
    char c = *scanner.current;
    if (c == ' ' || c == '\t' || c == '\r') { scanner.current++; continue; }
    if (c == '#') { while (*scanner.current && *scanner.current != '\n') scanner.current++; continue; }
    if (c == '\n') {
      if (newlinesSignificant() && needsSemi(scanner.last) && !continuationAhead(scanner.current + 1)) {
        scanner.start = scanner.current; scanner.current++;
        scanner.tokLine = scanner.line; scanner.tokLineStart = scanner.lineStart;
        Token t = makeToken(T_SEMI);
        scanner.line++; scanner.lineStart = scanner.current;
        return t;
      }
      scanner.current++; scanner.line++; scanner.lineStart = scanner.current;
      continue;
    }
    break;
  }

  scanner.start = scanner.current;
  scanner.tokLine = scanner.line;
  scanner.tokLineStart = scanner.lineStart;

  if (!*scanner.current) {
    if (!scanner.eofSemi && needsSemi(scanner.last) && newlinesSignificant()) { scanner.eofSemi = true; return makeToken(T_SEMI); }
    return makeToken(T_EOF);
  }

  char c = *scanner.current++;
  if (c == 'f' && (*scanner.current == '"' || *scanner.current == '\'')) return scanString(*scanner.current++, true);
  if (isAlpha(c)) {
    while (isAlpha(*scanner.current) || isDigit(*scanner.current)) scanner.current++;
    return makeToken(keywordType(scanner.start, (int)(scanner.current - scanner.start)));
  }
  if (isDigit(c)) {
    if (c == '0' && (*scanner.current == 'x' || *scanner.current == 'X') && isxdigit((unsigned char)scanner.current[1])) {
      scanner.current++;
      while (isxdigit((unsigned char)*scanner.current) || *scanner.current == '_') scanner.current++;
      return makeToken(T_NUMBER);
    }
    while (isDigit(*scanner.current) || *scanner.current == '_') scanner.current++;
    if (*scanner.current == '.' && isDigit(scanner.current[1])) {
      scanner.current++;
      while (isDigit(*scanner.current) || *scanner.current == '_') scanner.current++;
    }
    if ((*scanner.current == 'e' || *scanner.current == 'E') &&
        (isDigit(scanner.current[1]) || ((scanner.current[1] == '-' || scanner.current[1] == '+') && isDigit(scanner.current[2])))) {
      scanner.current += 2;
      while (isDigit(*scanner.current)) scanner.current++;
    }
    return makeToken(T_NUMBER);
  }

#define TWO(second, yes, no) (*scanner.current == (second) ? (scanner.current++, makeToken(yes)) : makeToken(no))
  switch (c) {
    case '(': return makeToken(T_LPAREN);
    case ')': return makeToken(T_RPAREN);
    case '{': return makeToken(T_LBRACE);
    case '}': return makeToken(T_RBRACE);
    case '[': return makeToken(T_LBRACKET);
    case ']': return makeToken(T_RBRACKET);
    case ',': return makeToken(T_COMMA);
    case ';': return makeToken(T_SEMI);
    case ':': return makeToken(T_COLON);
    case '.': return TWO('.', T_DOTDOT, T_DOT);
    case '-':
      if (*scanner.current == '>') { scanner.current++; return makeToken(T_RARROW); }
      return TWO('=', T_MINUS_EQ, T_MINUS);
    case '+': return TWO('=', T_PLUS_EQ, T_PLUS);
    case '/': return TWO('=', T_SLASH_EQ, T_SLASH);
    case '%': return TWO('=', T_PERCENT_EQ, T_PERCENT);
    case '*':
      if (*scanner.current == '*') { scanner.current++; return makeToken(T_STARSTAR); }
      return TWO('=', T_STAR_EQ, T_STAR);
    case '=':
      if (*scanner.current == '>') { scanner.current++; return makeToken(T_ARROW); }
      return TWO('=', T_EQEQ, T_EQ);
    case '<': return TWO('=', T_LE, T_LT);
    case '>': return TWO('=', T_GE, T_GT);
    case '!':
      if (*scanner.current == '=') { scanner.current++; return makeToken(T_NE); }
      return errorToken("Unexpected '!'. Use 'not' for negation and '!=' for not-equal.");
    case '|':
      if (*scanner.current == '>') { scanner.current++; return makeToken(T_PIPE); }
      return errorToken("Unexpected '|'. Did you mean '|>' (pipe) or 'or'?");
    case '?':
      if (*scanner.current == '?') { scanner.current++; return makeToken(T_QQ); }
      if (*scanner.current == '.') { scanner.current++; return makeToken(T_QDOT); }
      return errorToken("Unexpected '?'. Faxal has the operators ?? (default value) and ?. (safe access).");
    case '"': case '\'': return scanString(c, false);
  }
#undef TWO
  return errorToken("Unexpected character.");
}

/* ------------------------------------------------------------------- parser */

typedef struct { Token current, previous; bool hadError, panicMode, eofError; } Parser;

typedef enum {
  PREC_NONE, PREC_ASSIGNMENT, PREC_PIPE, PREC_COALESCE, PREC_OR, PREC_AND, PREC_EQUALITY, PREC_COMPARISON, PREC_RANGE,
  PREC_TERM, PREC_FACTOR, PREC_UNARY, PREC_POWER, PREC_CALL, PREC_PRIMARY
} Precedence;

typedef void (*ParseFn)(bool canAssign);
typedef struct { ParseFn prefix; ParseFn infix; Precedence precedence; } ParseRule;

typedef struct { Token name; int depth; bool isCaptured; } Local;
typedef struct { uint8_t index; bool isLocal; } UpvalueRef;
typedef enum { TYPE_FUNCTION, TYPE_SCRIPT, TYPE_METHOD, TYPE_INITIALIZER } FunctionType;

typedef struct Loop {
  struct Loop* enclosing;
  int start, localBase, tryDepth;
  int breaks[64]; int breakCount;
} Loop;

typedef struct Compiler {
  struct Compiler* enclosing;
  ObjFunction* function;
  FunctionType type;
  Local locals[256]; int localCount;
  UpvalueRef upvalues[256];
  int scopeDepth, tryDepth;
  Loop* loop;
  char retSpec[96];     /* the declared return type ("" when there is none), e.g. "num" or "str|nil" */
  char label[72];       /* how error messages name this function, e.g. "add()" */
} Compiler;

typedef struct ClassCompiler { struct ClassCompiler* enclosing; bool hasSuperclass; } ClassCompiler;

static Parser parser;
static Compiler* current = NULL;
static ClassCompiler* currentClass = NULL;
static ObjModule* currentModule = NULL;
static bool errorReported;

static Chunk* currentChunk(void) { return &current->function->chunk; }

/* Prints an error with the line of code and a ^^^ underline. Used by both compilers. */
void printCompileError(const char* path, int line, int col, const char* text, int len, int tl, const char* message) {
  if (vm.jsonMode || compileQuiet) return;
  bool color = fx_isatty(2);
  const char *red = color ? "\x1b[1;31m" : "", *bold = color ? "\x1b[1m" : "", *dim = color ? "\x1b[2m" : "", *off = color ? "\x1b[0m" : "";
  fflush(stdout);
  fprintf(stderr, "%serror%s%s: %s%s\n", red, off, bold, message, off);
  fprintf(stderr, "%s  --> %s:%d:%d%s\n", dim, path, line, col, off);
  char num[16];
  snprintf(num, sizeof num, "%d", line);
  int w = (int)strlen(num);
  fprintf(stderr, "%s%*s |%s\n", dim, w, "", off);
  fprintf(stderr, "%s%s |%s %.*s\n", dim, num, off, len, text);
  fprintf(stderr, "%s%*s |%s %*s%s", dim, w, "", off, col - 1, "", red);
  for (int i = 0; i < tl && col - 1 + i < len + 1; i++) fputc('^', stderr);
  fprintf(stderr, "%s\n", off);
}

static void errorAt(Token* t, const char* message) {
  if (parser.panicMode) return;
  parser.panicMode = true;
  parser.hadError = true;
  if (t->type == T_EOF || (t->type == T_SEMI && t->length == 0)) parser.eofError = true;

  int col = (int)(t->start - t->lineStart) + 1;
  if (t->type == T_ERROR) col = (int)(scanner.start - t->lineStart) + 1;
  if (!errorReported) {
    errorReported = true;
    compileErrorLine = t->line; compileErrorCol = col;
    snprintf(compileErrorMsg, sizeof compileErrorMsg, "%s", message);
  }
  if (vm.jsonMode || compileQuiet) return;

  const char* ls = t->lineStart;
  int len = 0;
  while (ls[len] && ls[len] != '\n') len++;
  int tl = t->type == T_EOF || t->length < 1 ? 1 : t->length;
  if (t->type == T_ERROR) tl = 1;
  printCompileError(currentModule ? currentModule->path->chars : "<script>", t->line, col, ls, len, tl, message);
}

static void error(const char* m) { errorAt(&parser.previous, m); }
static void errorAtCurrent(const char* m) { errorAt(&parser.current, m); }

static void advance(void) {
  parser.previous = parser.current;
  for (;;) {
    parser.current = scanToken();
    if (parser.current.type != T_ERROR) break;
    errorAtCurrent(parser.current.start);
  }
}

static bool check(FxTokenType t) { return parser.current.type == t; }
static bool match(FxTokenType t) { if (!check(t)) return false; advance(); return true; }
static void consume(FxTokenType t, const char* m) {
  if (check(t)) { advance(); return; }
  errorAtCurrent(m);
}
static void skipSemis(void) { while (check(T_SEMI)) advance(); }

static Token peekNext(void) {
  Scanner saved = scanner;
  Token t = scanToken();
  scanner = saved;
  return t;
}

/* ---------------------------------------------------------------- emitting */

static void emitByte(uint8_t b) { chunkWrite(currentChunk(), b, parser.previous.line); }
static void emitBytes(uint8_t a, uint8_t b) { emitByte(a); emitByte(b); }
static void emitShort(int v) { emitByte((uint8_t)((v >> 8) & 0xff)); emitByte((uint8_t)(v & 0xff)); }

static int makeConstant(Value v) {
  int idx = chunkAddConstant(currentChunk(), v);
  if (idx > 0xffff) { error("Too many constants in one function."); return 0; }
  return idx;
}
static void emitConstant(Value v) { emitByte(OP_CONSTANT); emitShort(makeConstant(v)); }

static int identifierConstant(Token* name) {
  ObjString* s = newString(name->start, name->length);
  ValueArray* a = &currentChunk()->constants;
  for (int i = 0; i < a->count; i++) if (IS_STRING(a->values[i]) && AS_STRING(a->values[i]) == s) return i;
  return makeConstant(OBJ_VAL(s));
}

static int emitJump(uint8_t op) { emitByte(op); emitByte(0xff); emitByte(0xff); return currentChunk()->count - 2; }

static void patchJump(int offset) {
  int jump = currentChunk()->count - offset - 2;
  if (jump > 0xffff) error("Too much code to jump over.");
  currentChunk()->code[offset] = (uint8_t)((jump >> 8) & 0xff);
  currentChunk()->code[offset + 1] = (uint8_t)(jump & 0xff);
}

static void emitLoop(int start) {
  emitByte(OP_LOOP);
  int offset = currentChunk()->count - start + 2;
  if (offset > 0xffff) error("Loop body is too large.");
  emitShort(offset);
}

/* Type annotations are checked while the program runs: the value on top of the stack goes through
   __check(value, "num or str", "what it is"), which gives the value back or throws a type error. */
static void emitCheckTop(const char* spec, const char* what) {
  Token name = { T_IDENT, "__check", 7, 0, NULL };
  emitByte(OP_GET_GLOBAL); emitShort(identifierConstant(&name));
  emitByte(OP_SWAP);
  emitConstant(OBJ_VAL(newString(spec, (int)strlen(spec))));
  emitConstant(OBJ_VAL(newString(what, (int)strlen(what))));
  emitBytes(OP_CALL, 3);
}

static bool specAcceptsNil(const char* spec) {
  for (const char* p = spec; *p;) {
    const char* e = strchr(p, '|'); size_t n = e ? (size_t)(e - p) : strlen(p);
    if ((n == 3 && !memcmp(p, "nil", 3)) || (n == 3 && !memcmp(p, "any", 3))) return true;
    if (!e) break;
    p = e + 1;
  }
  return false;
}

static void emitReturn(void) {
  if (current->type == TYPE_INITIALIZER) emitBytes(OP_GET_LOCAL, 0); /* init() gives back the new object */
  else {
    emitByte(OP_NIL);
    if (current->retSpec[0] && !specAcceptsNil(current->retSpec)) {
      char what[128]; snprintf(what, sizeof what, "return value of %s", current->label);
      emitCheckTop(current->retSpec, what);
    }
  }
  emitByte(OP_RETURN);
}

static void initCompiler(Compiler* c, FunctionType type) {
  c->enclosing = current; c->function = NULL; c->type = type;
  c->localCount = 0; c->scopeDepth = 0; c->tryDepth = 0; c->loop = NULL;
  c->retSpec[0] = '\0'; snprintf(c->label, sizeof c->label, "the function");
  c->function = newFunction();
  c->function->module = currentModule;
  c->function->isScript = (type == TYPE_SCRIPT);
  current = c;
  Local* l = &c->locals[c->localCount++];
  l->depth = 0; l->isCaptured = false;
  if (type == TYPE_METHOD || type == TYPE_INITIALIZER) { l->name.start = "self"; l->name.length = 4; }
  else { l->name.start = ""; l->name.length = 0; }
}

static ObjFunction* endCompiler(void) {
  emitReturn();
  ObjFunction* f = current->function;
  if (vm.dumpCode && !parser.hadError) disassembleFunction(f);
  current = current->enclosing;
  return f;
}

static void beginScope(void) { current->scopeDepth++; }

static void endScope(void) {
  current->scopeDepth--;
  while (current->localCount > 0 && current->locals[current->localCount - 1].depth > current->scopeDepth) {
    emitByte(current->locals[current->localCount - 1].isCaptured ? OP_CLOSE_UPVALUE : OP_POP);
    current->localCount--;
  }
}

/* emit pops for locals above `base` without forgetting them (used by break/continue) */
static void emitPopsTo(int base) {
  for (int i = current->localCount - 1; i >= base; i--)
    emitByte(current->locals[i].isCaptured ? OP_CLOSE_UPVALUE : OP_POP);
}

/* ---------------------------------------------------------------- variables */

static bool identsEqual(Token* a, Token* b) { return a->length == b->length && memcmp(a->start, b->start, (size_t)a->length) == 0; }

static int resolveLocal(Compiler* c, Token* name) {
  for (int i = c->localCount - 1; i >= 0; i--) {
    Local* l = &c->locals[i];
    if (identsEqual(name, &l->name)) {
      if (l->depth == -1) error("Can't read a variable in its own initializer.");
      return i;
    }
  }
  return -1;
}

static int addUpvalue(Compiler* c, uint8_t index, bool isLocal) {
  int count = c->function->upvalueCount;
  for (int i = 0; i < count; i++) if (c->upvalues[i].index == index && c->upvalues[i].isLocal == isLocal) return i;
  if (count == 256) { error("Too many captured variables in one function."); return 0; }
  c->upvalues[count].isLocal = isLocal;
  c->upvalues[count].index = index;
  return c->function->upvalueCount++;
}

static int resolveUpvalue(Compiler* c, Token* name) {
  if (!c->enclosing) return -1;
  int local = resolveLocal(c->enclosing, name);
  if (local != -1) { c->enclosing->locals[local].isCaptured = true; return addUpvalue(c, (uint8_t)local, true); }
  int up = resolveUpvalue(c->enclosing, name);
  if (up != -1) return addUpvalue(c, (uint8_t)up, false);
  return -1;
}

static void addLocal(Token name) {
  if (current->localCount == 256) { error("Too many local variables in one function."); return; }
  Local* l = &current->locals[current->localCount++];
  l->name = name; l->depth = -1; l->isCaptured = false;
}

static void markInitialized(void) {
  if (current->scopeDepth == 0) return;
  current->locals[current->localCount - 1].depth = current->scopeDepth;
}

static void declareVariable(void) {
  if (current->scopeDepth == 0) return;
  Token* name = &parser.previous;
  for (int i = current->localCount - 1; i >= 0; i--) {
    Local* l = &current->locals[i];
    if (l->depth != -1 && l->depth < current->scopeDepth) break;
    if (identsEqual(name, &l->name)) error("There is already a variable with this name in this scope.");
  }
  addLocal(*name);
}

static int parseVariable(const char* msg) {
  consume(T_IDENT, msg);
  declareVariable();
  if (current->scopeDepth > 0) return 0;
  return identifierConstant(&parser.previous);
}

static void defineVariable(int global) {
  if (current->scopeDepth > 0) { markInitialized(); return; }
  emitByte(OP_DEFINE_GLOBAL);
  emitShort(global);
}

/* ------------------------------------------------------------- expressions */

static void expression(void);
static void statement(void);
static void declaration(void);
static void block(void);
static ParseRule* getRule(FxTokenType t);
static void parsePrecedence(Precedence p);

static int nesting = 0;

static void parsePrecedence(Precedence precedence) {
  if (++nesting > 200) { error("This is nested too deeply."); nesting--; return; }
  advance();
  ParseFn prefix = getRule(parser.previous.type)->prefix;
  if (!prefix) { error("Expected an expression."); nesting--; return; }
  bool canAssign = precedence <= PREC_ASSIGNMENT;
  prefix(canAssign);
  while (precedence <= getRule(parser.current.type)->precedence) {
    advance();
    getRule(parser.previous.type)->infix(canAssign);
  }
  if (canAssign && (check(T_EQ) || check(T_PLUS_EQ) || check(T_MINUS_EQ) || check(T_STAR_EQ) || check(T_SLASH_EQ) || check(T_PERCENT_EQ))) {
    advance();
    error("Invalid assignment target.");
  }
  nesting--;
}

static void expression(void) { parsePrecedence(PREC_ASSIGNMENT); }

static bool matchCompound(OpCode* op) {
  if (match(T_PLUS_EQ)) { *op = OP_ADD; return true; }
  if (match(T_MINUS_EQ)) { *op = OP_SUB; return true; }
  if (match(T_STAR_EQ)) { *op = OP_MUL; return true; }
  if (match(T_SLASH_EQ)) { *op = OP_DIV; return true; }
  if (match(T_PERCENT_EQ)) { *op = OP_MOD; return true; }
  return false;
}

static void namedVariable(Token name, bool canAssign) {
  uint8_t getOp, setOp;
  int arg = resolveLocal(current, &name);
  bool isGlobal = false;
  if (arg != -1) { getOp = OP_GET_LOCAL; setOp = OP_SET_LOCAL; }
  else if ((arg = resolveUpvalue(current, &name)) != -1) { getOp = OP_GET_UPVALUE; setOp = OP_SET_UPVALUE; }
  else { arg = identifierConstant(&name); getOp = OP_GET_GLOBAL; setOp = OP_SET_GLOBAL; isGlobal = true; }

#define EMIT_ARG(op) do { emitByte(op); if (isGlobal) emitShort(arg); else emitByte((uint8_t)arg); } while (0)
  OpCode compound;
  if (canAssign && match(T_EQ)) { expression(); EMIT_ARG(setOp); }
  else if (canAssign && matchCompound(&compound)) { EMIT_ARG(getOp); expression(); emitByte(compound); EMIT_ARG(setOp); }
  else EMIT_ARG(getOp);
#undef EMIT_ARG
}

static void variable(bool canAssign) { namedVariable(parser.previous, canAssign); }

static void number(bool canAssign) {
  (void)canAssign;
  char buf[64];
  int n = 0;
  for (int i = 0; i < parser.previous.length && n < 62; i++)
    if (parser.previous.start[i] != '_') buf[n++] = parser.previous.start[i];
  buf[n] = '\0';
  double v = (buf[0] == '0' && (buf[1] == 'x' || buf[1] == 'X')) ? (double)strtoull(buf, NULL, 16) : strtod(buf, NULL);
  emitConstant(NUM_VAL(v));
}

static void literal(bool canAssign) {
  (void)canAssign;
  switch (parser.previous.type) {
    case T_FALSE: emitByte(OP_FALSE); break;
    case T_NIL: emitByte(OP_NIL); break;
    case T_TRUE: emitByte(OP_TRUE); break;
    default: return;
  }
}

/* Strings: handles escapes and {interpolation}. */
static void flushLiteral(Buffer* lit, bool* first) {
  if (lit->len > 0 || *first) {
    emitConstant(OBJ_VAL(newString(lit->data ? lit->data : "", lit->len)));
    if (!*first) emitByte(OP_ADD);
    *first = false;
    lit->len = 0;
    if (lit->data) lit->data[0] = '\0';
  }
}

static void compileInterpolation(const char* text, int len, int line) {
  Scanner savedScanner = scanner;
  Parser savedParser = parser;
  char* copy = malloc((size_t)len + 1);
  memcpy(copy, text, (size_t)len);
  copy[len] = '\0';

  initScanner(copy, line);
  parser.panicMode = false;
  advance();
  if (check(T_EOF) || check(T_SEMI)) errorAtCurrent("Empty {} in f-string. Use \\{ for a literal brace.");
  else {
    expression();
    skipSemis();
    if (!check(T_EOF)) errorAtCurrent("Unexpected token in string interpolation.");
  }
  bool failed = parser.hadError;
  bool eof = parser.eofError;
  free(copy);
  scanner = savedScanner;
  parser = savedParser;
  (void)eof;
  if (failed) parser.hadError = true;
}

static void string(bool canAssign) {
  (void)canAssign;
  bool interp = parser.previous.type == T_FSTRING;
  const char* raw = parser.previous.start + (interp ? 2 : 1);
  int n = parser.previous.length - (interp ? 3 : 2);
  int line = parser.previous.line;
  Buffer lit; bufInit(&lit);
  bool first = true;

  for (int i = 0; i < n; i++) {
    char c = raw[i];
    if (c == '\\' && i + 1 < n) {
      char e = raw[++i];
      switch (e) {
        case 'n': bufChar(&lit, '\n'); break;
        case 't': bufChar(&lit, '\t'); break;
        case 'r': bufChar(&lit, '\r'); break;
        case '0': bufChar(&lit, '\0'); break;
        case 'e': bufChar(&lit, 27); break;
        case '\\': case '"': case '\'': case '{': case '}': bufChar(&lit, e); break;
        default: bufChar(&lit, '\\'); bufChar(&lit, e);
      }
    } else if (c == '{' && interp) {
      int depth = 1, j = i + 1;
      while (j < n && depth > 0) {
        if (raw[j] == '\\') { j += 2; continue; }
        if (raw[j] == '"' || raw[j] == '\'') {
          char q = raw[j++];
          while (j < n && raw[j] != q) { if (raw[j] == '\\') j++; j++; }
        } else if (raw[j] == '{') depth++;
        else if (raw[j] == '}') depth--;
        j++;
      }
      if (depth != 0) { error("Unclosed { in f-string. Use \\{ for a literal brace."); break; }
      flushLiteral(&lit, &first);
      compileInterpolation(raw + i + 1, j - i - 2, line);
      emitByte(OP_ADD);
      i = j - 1;
    } else {
      bufChar(&lit, c);
    }
  }
  flushLiteral(&lit, &first);
  bufFree(&lit);
}

static void grouping(bool canAssign) {
  (void)canAssign;
  expression();
  consume(T_RPAREN, "Expected ')' after expression.");
}

static void unary(bool canAssign) {
  (void)canAssign;
  FxTokenType op = parser.previous.type;
  if (op == T_NOT) { parsePrecedence(PREC_EQUALITY); emitByte(OP_NOT); }
  else { parsePrecedence(PREC_UNARY); emitByte(OP_NEG); }
}

static void binary(bool canAssign) {
  (void)canAssign;
  FxTokenType op = parser.previous.type;
  ParseRule* rule = getRule(op);
  parsePrecedence(op == T_STARSTAR ? PREC_POWER : (Precedence)(rule->precedence + 1));
  switch (op) {
    case T_PLUS: emitByte(OP_ADD); break;
    case T_MINUS: emitByte(OP_SUB); break;
    case T_STAR: emitByte(OP_MUL); break;
    case T_SLASH: emitByte(OP_DIV); break;
    case T_PERCENT: emitByte(OP_MOD); break;
    case T_STARSTAR: emitByte(OP_POW); break;
    case T_EQEQ: emitByte(OP_EQUAL); break;
    case T_NE: emitBytes(OP_EQUAL, OP_NOT); break;
    case T_GT: emitByte(OP_GREATER); break;
    case T_GE: emitBytes(OP_LESS, OP_NOT); break;
    case T_LT: emitByte(OP_LESS); break;
    case T_LE: emitBytes(OP_GREATER, OP_NOT); break;
    case T_IN: emitByte(OP_IN); break;
    case T_DOTDOT: emitByte(OP_RANGE); break;
    case T_BY: emitByte(OP_BY); break;
    default: return;
  }
}

static void and_(bool canAssign) {
  (void)canAssign;
  int end = emitJump(OP_JUMP_IF_FALSE);
  emitByte(OP_POP);
  parsePrecedence(PREC_AND + 1);
  patchJump(end);
}

static void or_(bool canAssign) {
  (void)canAssign;
  int elseJump = emitJump(OP_JUMP_IF_FALSE);
  int endJump = emitJump(OP_JUMP);
  patchJump(elseJump);
  emitByte(OP_POP);
  parsePrecedence(PREC_OR + 1);
  patchJump(endJump);
}

static uint8_t argumentList(void) {
  int argc = 0;
  if (!check(T_RPAREN)) {
    do {
      if (check(T_RPAREN)) break;
      expression();
      if (argc == 255) error("Can't have more than 255 arguments.");
      argc++;
    } while (match(T_COMMA));
  }
  consume(T_RPAREN, "Expected ')' after arguments.");
  return (uint8_t)argc;
}

/* Named arguments: f(1, width = 3). Before the arguments are compiled, a look ahead (on a copy of the scanner)
   finds out whether there are any and what they are called, because the code that calls f has to be set up
   differently:   f(a, w = 3)   becomes   __call_named(f, "w", a, 3)   and the VM matches the names to parameters. */
typedef struct { int count; char names[512]; } NamedArgs;

static void scanNamedArgs(NamedArgs* na) {
  na->count = 0; na->names[0] = '\0';
  Scanner saved = scanner;
  Token t = parser.current, nextTok;
  int depth = 0;
  bool argStart = true;
  size_t used = 0;
  for (int guard = 0; guard < 100000; guard++) {
    if (t.type == T_EOF || t.type == T_ERROR) break;
    if (t.type == T_LPAREN || t.type == T_LBRACKET || t.type == T_LBRACE) depth++;
    else if (t.type == T_RPAREN || t.type == T_RBRACKET || t.type == T_RBRACE) { if (depth == 0) break; depth--; }
    if (depth == 0 && argStart && t.type == T_IDENT) {
      nextTok = scanToken();
      if (nextTok.type == T_EQ) {
        if (used + (size_t)t.length + 2 < sizeof na->names) {
          if (na->count) na->names[used++] = ',';
          memcpy(na->names + used, t.start, (size_t)t.length); used += (size_t)t.length; na->names[used] = '\0';
        }
        na->count++;
      }
      argStart = false;
      t = nextTok;
      continue;
    }
    if (depth == 0) argStart = t.type == T_COMMA;
    t = scanToken();
  }
  scanner = saved;
}

/* The callee is on the stack and '(' has been read. */
static void namedCall(NamedArgs* na) {
  Token g = { T_IDENT, "__call_named", 12, 0, NULL };
  emitByte(OP_GET_GLOBAL); emitShort(identifierConstant(&g));
  emitByte(OP_SWAP);
  emitConstant(OBJ_VAL(newString(na->names, (int)strlen(na->names))));
  int argc = 0;
  bool named = false;
  if (!check(T_RPAREN)) {
    do {
      if (check(T_RPAREN)) break;
      if (check(T_IDENT) && peekNext().type == T_EQ) {
        advance(); advance();
        named = true;
        expression();
      } else {
        if (named) error("A positional argument can't come after a named argument.");
        expression();
      }
      if (argc >= 253) error("Can't have more than 253 arguments in a call with named arguments.");
      argc++;
    } while (match(T_COMMA));
  }
  consume(T_RPAREN, "Expected ')' after arguments.");
  emitBytes(OP_CALL, (uint8_t)(2 + argc));
}

static void call(bool canAssign) {
  (void)canAssign;
  NamedArgs na; scanNamedArgs(&na);
  if (na.count > 0) { namedCall(&na); return; }
  uint8_t argc = argumentList();
  emitBytes(OP_CALL, argc);
}

static void dot(bool canAssign) {
  consume(T_IDENT, "Expected a property name after '.'.");
  int name = identifierConstant(&parser.previous);
  OpCode compound;
  if (canAssign && match(T_EQ)) {
    expression();
    emitByte(OP_SET_PROPERTY); emitShort(name);
  } else if (canAssign && matchCompound(&compound)) {
    emitByte(OP_DUP);
    emitByte(OP_GET_PROPERTY); emitShort(name);
    expression();
    emitByte(compound);
    emitByte(OP_SET_PROPERTY); emitShort(name);
  } else if (match(T_LPAREN)) {
    NamedArgs na; scanNamedArgs(&na);
    if (na.count > 0) { emitByte(OP_GET_PROPERTY); emitShort(name); namedCall(&na); return; }
    uint8_t argc = argumentList();
    emitByte(OP_INVOKE); emitShort(name); emitByte(argc);
  } else {
    emitByte(OP_GET_PROPERTY); emitShort(name);
  }
}

static void subscript(bool canAssign) {
  OpCode compound;
  bool sliced = false;
  if (check(T_COLON)) emitByte(OP_NIL); else expression();
  if (match(T_COLON)) {
    sliced = true;
    if (check(T_RBRACKET)) emitByte(OP_NIL); else expression();
  }
  consume(T_RBRACKET, "Expected ']' after index.");
  if (sliced) { emitByte(OP_SLICE); return; }
  if (canAssign && match(T_EQ)) { expression(); emitByte(OP_SET_INDEX); }
  else if (canAssign && matchCompound(&compound)) {
    emitByte(OP_DUP2); emitByte(OP_GET_INDEX); expression(); emitByte(compound); emitByte(OP_SET_INDEX);
  } else emitByte(OP_GET_INDEX);
}

static void list(bool canAssign) {
  (void)canAssign;
  int count = 0;
  if (!check(T_RBRACKET)) {
    do {
      if (check(T_RBRACKET)) break;
      expression();
      if (count == 0xffff) error("Too many items in a list literal.");
      count++;
    } while (match(T_COMMA));
  }
  consume(T_RBRACKET, "Expected ']' after list items.");
  emitByte(OP_BUILD_LIST); emitShort(count);
}

static void mapLiteral(bool canAssign) {
  (void)canAssign;
  int count = 0;
  skipSemis();
  while (!check(T_RBRACE) && !check(T_EOF)) {
    if (check(T_IDENT) && peekNext().type == T_COLON) {
      advance();
      emitConstant(OBJ_VAL(newString(parser.previous.start, parser.previous.length)));
    } else if (check(T_STRING) || check(T_NUMBER) || check(T_TRUE) || check(T_FALSE)) {
      advance();
      getRule(parser.previous.type)->prefix(false);
    } else {
      errorAtCurrent("Expected a key (a name, string or number) in map.");
      return;
    }
    consume(T_COLON, "Expected ':' after map key.");
    skipSemis();
    expression();
    count++;
    skipSemis();
    if (!match(T_COMMA)) break;
    skipSemis();
  }
  skipSemis();
  consume(T_RBRACE, "Expected '}' after map entries.");
  emitByte(OP_BUILD_MAP); emitShort(count);
}

/* type := name ('or' name)*   written into out as "name|name". */
static bool typeSpec(char* out, size_t cap) {
  size_t n = 0;
  out[0] = '\0';
  for (;;) {
    if (!(check(T_IDENT) || check(T_NIL) || check(T_FN))) { errorAtCurrent("Expected a type name (num, str, bool, list, map, fn, nil, any, or a class name)."); return false; }
    advance();
    size_t len = (size_t)parser.previous.length;
    if (n + len + 2 >= cap) { error("This type is too long."); return false; }
    if (n) out[n++] = '|';
    memcpy(out + n, parser.previous.start, len); n += len; out[n] = '\0';
    if (!match(T_OR)) break;
  }
  return true;
}

static void function(FunctionType type, Token* name, bool isAsync) {
  Compiler c;
  initCompiler(&c, type);
  if (name) {
    c.function->name = newString(name->start, name->length);
    snprintf(c.label, sizeof c.label, "%.*s()", name->length > 60 ? 60 : name->length, name->start);
  }
  beginScope();
  consume(T_LPAREN, "Expected '(' before parameters.");
  bool sawDefault = false;
  ObjString* paramNames[256];
  if (!check(T_RPAREN)) {
    do {
      if (check(T_RPAREN)) break;
      current->function->arity++;
      if (current->function->arity > 255) errorAtCurrent("Can't have more than 255 parameters.");
      int p = parseVariable("Expected a parameter name.");
      defineVariable(p);
      Token paramName = parser.previous;
      if (current->function->arity <= 255) paramNames[current->function->arity - 1] = newString(paramName.start, paramName.length);
      char paramSpec[96]; paramSpec[0] = '\0';
      if (match(T_COLON)) typeSpec(paramSpec, sizeof paramSpec);
      if (match(T_EQ)) {
        /* default value: at function entry, if the argument is nil, compute the default */
        sawDefault = true;
        int slot = current->localCount - 1;
        emitBytes(OP_GET_LOCAL, (uint8_t)slot);
        int skip = emitJump(OP_JUMP_IF_NOT_NIL);
        emitByte(OP_POP);
        expression();
        emitBytes(OP_SET_LOCAL, (uint8_t)slot);
        patchJump(skip);
        emitByte(OP_POP);
      } else {
        if (sawDefault) error("A parameter without a default value can't come after one that has a default.");
        current->function->minArity++;
      }
      if (paramSpec[0]) {
        char what[160]; snprintf(what, sizeof what, "parameter '%.*s' of %s", paramName.length > 40 ? 40 : paramName.length, paramName.start, current->label);
        Token g = { T_IDENT, "__check", 7, 0, NULL };
        emitByte(OP_GET_GLOBAL); emitShort(identifierConstant(&g));
        emitBytes(OP_GET_LOCAL, (uint8_t)(current->localCount - 1));
        emitConstant(OBJ_VAL(newString(paramSpec, (int)strlen(paramSpec))));
        emitConstant(OBJ_VAL(newString(what, (int)strlen(what))));
        emitBytes(OP_CALL, 3);
        emitByte(OP_POP);
      }
    } while (match(T_COMMA));
  }
  consume(T_RPAREN, "Expected ')' after parameters.");
  if (current->function->arity > 0 && current->function->arity <= 255) {   /* kept so that named arguments can find them */
    int n = current->function->arity;
    current->function->paramNames = ALLOCATE(ObjString*, n);
    for (int i = 0; i < n; i++) current->function->paramNames[i] = paramNames[i];
  }
  if (match(T_RARROW)) typeSpec(current->retSpec, sizeof current->retSpec);
  /* async fn f(x) { body }  is   fn f(x) { return __coroutine(fn() { body }) }: calling it gives a coroutine
     that has not started yet (the body can use the parameters because it is a closure) */
  Compiler inner;
  if (isAsync) {
    if (type == TYPE_INITIALIZER) error("An init() method can't be async.");
    Token g = { T_IDENT, "__coroutine", 11, 0, NULL };
    emitByte(OP_GET_GLOBAL); emitShort(identifierConstant(&g));
    initCompiler(&inner, TYPE_FUNCTION);
    memcpy(inner.label, c.label, sizeof inner.label);
    memcpy(inner.retSpec, c.retSpec, sizeof inner.retSpec);
    c.retSpec[0] = '\0';
    if (name) inner.function->name = newString(name->start, name->length);
    beginScope();
  }
  if (match(T_ARROW)) {
    /* fn(x) => expression   is short for   fn(x) { return expression } */
    if (type == TYPE_INITIALIZER) error("Can't return a value from init().");
    expression();
    if (current->retSpec[0]) { char what[128]; snprintf(what, sizeof what, "return value of %s", current->label); emitCheckTop(current->retSpec, what); }
    emitByte(OP_RETURN);
  } else {
    skipSemis();
    consume(T_LBRACE, "Expected '{' before function body.");
    block();
  }
  if (isAsync) {
    ObjFunction* body = endCompiler();
    emitByte(OP_CLOSURE);
    emitShort(makeConstant(OBJ_VAL(body)));
    for (int i = 0; i < body->upvalueCount; i++) { emitByte(inner.upvalues[i].isLocal ? 1 : 0); emitByte(inner.upvalues[i].index); }
    emitBytes(OP_CALL, 1);
    emitByte(OP_RETURN);
  }
  ObjFunction* f = endCompiler();
  emitByte(OP_CLOSURE);
  emitShort(makeConstant(OBJ_VAL(f)));
  for (int i = 0; i < f->upvalueCount; i++) { emitByte(c.upvalues[i].isLocal ? 1 : 0); emitByte(c.upvalues[i].index); }
}

static void lambda(bool canAssign) { (void)canAssign; function(TYPE_FUNCTION, NULL, false); }

/* async fn(x) { ... } as an expression */
static void asyncLambda(bool canAssign) {
  (void)canAssign;
  consume(T_FN, "Expected 'fn' after 'async'.");
  function(TYPE_FUNCTION, NULL, true);
}

/* await x  becomes  __await(x): inside an async function the coroutine suspends until x is ready */
static void awaitExpr(bool canAssign) {
  (void)canAssign;
  parsePrecedence(PREC_UNARY);
  Token g = { T_IDENT, "__await", 7, 0, NULL };
  emitByte(OP_GET_GLOBAL); emitShort(identifierConstant(&g));
  emitByte(OP_SWAP);
  emitBytes(OP_CALL, 1);
}

/* x |> f        becomes  f(x)
   x |> f(a, b)  becomes  f(x, a, b)      (x is passed first) */
static void pipeOp(bool canAssign) {
  (void)canAssign;
  parsePrecedence(PREC_PRIMARY);                 /* the function: a name, lambda, or ( expression ) */
  while (match(T_DOT)) {                         /* ... or a dotted name like math.sqrt */
    consume(T_IDENT, "Expected a name after '.'.");
    emitByte(OP_GET_PROPERTY);
    emitShort(identifierConstant(&parser.previous));
  }
  emitByte(OP_SWAP);                             /* stack: value, function  ->  function, value */
  int argc = 1;
  if (match(T_LPAREN)) {
    NamedArgs na; scanNamedArgs(&na);
    if (na.count > 0) error("Named arguments aren't supported after '|>': call the function with ( ) instead.");
    int extra = argumentList();
    if (extra + 1 > 255) error("Too many arguments.");
    argc += extra;
  }
  emitBytes(OP_CALL, (uint8_t)argc);
}

/* a ?? b : a, unless a is nil */
static void coalesce(bool canAssign) {
  (void)canAssign;
  int end = emitJump(OP_JUMP_IF_NOT_NIL);
  emitByte(OP_POP);
  parsePrecedence(PREC_COALESCE + 1);
  patchJump(end);
}

/* a?.b and a?.m(x) : nil when a is nil, instead of an error */
static void optionalDot(bool canAssign) {
  (void)canAssign;
  int skip = emitJump(OP_JUMP_IF_NIL);
  consume(T_IDENT, "Expected a property name after '?.'.");
  int name = identifierConstant(&parser.previous);
  if (match(T_LPAREN)) {
    NamedArgs na; scanNamedArgs(&na);
    if (na.count > 0) { emitByte(OP_GET_PROPERTY); emitShort(name); namedCall(&na); }
    else {
      uint8_t argc = argumentList();
      emitByte(OP_INVOKE); emitShort(name); emitByte(argc);
    }
  } else {
    emitByte(OP_GET_PROPERTY); emitShort(name);
  }
  patchJump(skip);
}

static Token syntheticToken(const char* text) {
  Token t = { T_IDENT, text, (int)strlen(text), parser.previous.line, parser.previous.lineStart };
  return t;
}

static void self_(bool canAssign) {
  (void)canAssign;
  if (!currentClass) { error("'self' can only be used inside a class."); return; }
  variable(false);
}

static void super_(bool canAssign) {
  (void)canAssign;
  if (!currentClass) error("'super' can only be used inside a class.");
  else if (!currentClass->hasSuperclass) error("'super' can only be used in a class that extends another class.");
  consume(T_DOT, "Expected '.' after 'super'.");
  consume(T_IDENT, "Expected a method name after 'super.'.");
  int name = identifierConstant(&parser.previous);
  namedVariable(syntheticToken("self"), false);
  if (match(T_LPAREN)) {
    NamedArgs na; scanNamedArgs(&na);
    if (na.count > 0) {
      namedVariable(syntheticToken("super"), false);
      emitByte(OP_GET_SUPER); emitShort(name);
      namedCall(&na);
      return;
    }
    uint8_t argc = argumentList();
    namedVariable(syntheticToken("super"), false);
    emitByte(OP_SUPER_INVOKE); emitShort(name); emitByte(argc);
  } else {
    namedVariable(syntheticToken("super"), false);
    emitByte(OP_GET_SUPER); emitShort(name);
  }
}

static ParseRule rules[T_EOF + 1] = {
  [T_LPAREN] = {grouping, call, PREC_CALL}, [T_LBRACKET] = {list, subscript, PREC_CALL},
  [T_LBRACE] = {mapLiteral, NULL, PREC_NONE}, [T_DOT] = {NULL, dot, PREC_CALL},
  [T_MINUS] = {unary, binary, PREC_TERM}, [T_PLUS] = {NULL, binary, PREC_TERM},
  [T_SLASH] = {NULL, binary, PREC_FACTOR}, [T_STAR] = {NULL, binary, PREC_FACTOR},
  [T_PERCENT] = {NULL, binary, PREC_FACTOR}, [T_STARSTAR] = {NULL, binary, PREC_POWER},
  [T_DOTDOT] = {NULL, binary, PREC_RANGE},
  [T_NE] = {NULL, binary, PREC_EQUALITY}, [T_EQEQ] = {NULL, binary, PREC_EQUALITY},
  [T_GT] = {NULL, binary, PREC_COMPARISON}, [T_GE] = {NULL, binary, PREC_COMPARISON},
  [T_LT] = {NULL, binary, PREC_COMPARISON}, [T_LE] = {NULL, binary, PREC_COMPARISON},
  [T_IN] = {NULL, binary, PREC_COMPARISON},
  [T_IDENT] = {variable, NULL, PREC_NONE}, [T_STRING] = {string, NULL, PREC_NONE}, [T_FSTRING] = {string, NULL, PREC_NONE},
  [T_NUMBER] = {number, NULL, PREC_NONE},
  [T_AND] = {NULL, and_, PREC_AND}, [T_OR] = {NULL, or_, PREC_OR}, [T_NOT] = {unary, NULL, PREC_NONE},
  [T_FALSE] = {literal, NULL, PREC_NONE}, [T_TRUE] = {literal, NULL, PREC_NONE}, [T_NIL] = {literal, NULL, PREC_NONE},
  [T_FN] = {lambda, NULL, PREC_NONE}, [T_ASYNC] = {asyncLambda, NULL, PREC_NONE}, [T_AWAIT] = {awaitExpr, NULL, PREC_NONE}, [T_SELF] = {self_, NULL, PREC_NONE},
  [T_PIPE] = {NULL, pipeOp, PREC_PIPE}, [T_QQ] = {NULL, coalesce, PREC_COALESCE}, [T_QDOT] = {NULL, optionalDot, PREC_CALL}, [T_BY] = {NULL, binary, PREC_RANGE}, [T_SUPER] = {super_, NULL, PREC_NONE},
};

static ParseRule* getRule(FxTokenType t) { return &rules[t]; }

/* -------------------------------------------------------------- statements */

static void endStatement(void) {
  if (match(T_SEMI)) return;
  if (check(T_RBRACE) || check(T_EOF)) return;
  errorAtCurrent("Expected a new line or ';' after this statement.");
}

static void block(void) {
  skipSemis();
  while (!check(T_RBRACE) && !check(T_EOF)) { declaration(); skipSemis(); }
  consume(T_RBRACE, "Expected '}' to close the block.");
}

static void scopedBlock(void) {
  consume(T_LBRACE, "Expected '{'.");
  beginScope();
  block();
  endScope();
}

static void letDeclaration(void) {
  int global = parseVariable("Expected a variable name after 'let'.");
  Token varName = parser.previous;
  char spec[96]; spec[0] = '\0';
  if (match(T_COLON)) typeSpec(spec, sizeof spec);
  if (match(T_EQ)) {
    if (check(T_FN)) markInitialized(); /* lets local functions call themselves */
    expression();
    if (spec[0]) { char what[96]; snprintf(what, sizeof what, "variable '%.*s'", varName.length > 60 ? 60 : varName.length, varName.start); emitCheckTop(spec, what); }
  } else emitByte(OP_NIL);
  endStatement();
  defineVariable(global);
}

static void funDeclaration(bool isAsync) {
  int global = parseVariable("Expected a function name.");
  Token name = parser.previous;
  markInitialized();
  function(TYPE_FUNCTION, &name, isAsync);
  defineVariable(global);
}

static void method(void) {
  skipSemis();
  bool isAsync = match(T_ASYNC);
  consume(T_FN, "Expected 'fn' to start a method.");
  consume(T_IDENT, "Expected a method name.");
  Token name = parser.previous;
  int constant = identifierConstant(&name);
  FunctionType type = (name.length == 4 && memcmp(name.start, "init", 4) == 0) ? TYPE_INITIALIZER : TYPE_METHOD;
  function(type, &name, isAsync);
  emitByte(OP_METHOD);
  emitShort(constant);
}

static void classDeclaration(void) {
  consume(T_IDENT, "Expected a class name.");
  Token className = parser.previous;
  int nameConstant = identifierConstant(&parser.previous);
  declareVariable();
  emitByte(OP_CLASS);
  emitShort(nameConstant);
  defineVariable(nameConstant);

  ClassCompiler cc;
  cc.hasSuperclass = false;
  cc.enclosing = currentClass;
  currentClass = &cc;

  if (match(T_EXTENDS)) {
    consume(T_IDENT, "Expected a superclass name after 'extends'.");
    variable(false);
    if (identsEqual(&className, &parser.previous)) error("A class can't extend itself.");
    beginScope();
    addLocal(syntheticToken("super"));
    defineVariable(0);
    namedVariable(className, false);
    emitByte(OP_INHERIT);
    cc.hasSuperclass = true;
  }

  namedVariable(className, false);
  skipSemis();
  consume(T_LBRACE, "Expected '{' before the class body.");
  skipSemis();
  while (!check(T_RBRACE) && !check(T_EOF)) { method(); skipSemis(); }
  consume(T_RBRACE, "Expected '}' after the class body.");
  emitByte(OP_POP);
  if (cc.hasSuperclass) endScope();
  currentClass = cc.enclosing;
}

static void importStatement(void) {
  consume(T_STRING, "Expected a file path string after 'import'.");
  Token path = parser.previous;
  if (compileCollectImports) {
    compiledImports = realloc(compiledImports, sizeof(char*) * (size_t)(compiledImportCount + 1));
    compiledImports[compiledImportCount++] = strndup(path.start + 1, (size_t)path.length - 2);
  }
  string(false);
  emitByte(OP_IMPORT);

  Token name;
  if (check(T_IDENT) && parser.current.length == 2 && memcmp(parser.current.start, "as", 2) == 0) {
    advance();
    consume(T_IDENT, "Expected a name after 'as'.");
    name = parser.previous;
  } else {
    /* derive the name from the file name: "lib/util.fx" -> util */
    const char* s = path.start + 1;
    int n = path.length - 2, begin = 0, end = n;
    for (int i = 0; i < n; i++) if (s[i] == '/') begin = i + 1;
    for (int i = n - 1; i >= begin; i--) if (s[i] == '.') { end = i; break; }
    name = path;
    name.start = s + begin; name.length = end - begin;
    bool ok = name.length > 0 && isAlpha(name.start[0]);
    for (int i = 0; ok && i < name.length; i++) if (!isAlpha(name.start[i]) && !isDigit(name.start[i])) ok = false;
    if (!ok) { error("Can't make a name from this path. Write: import \"file.fx\" as name"); return; }
  }
  endStatement();
  if (current->scopeDepth == 0) {
    emitByte(OP_DEFINE_GLOBAL);
    emitShort(identifierConstant(&name));
  } else {
    addLocal(name);
    markInitialized();
  }
}

static void expressionStatement(void) {
  expression();
  if (vm.replMode && current->type == TYPE_SCRIPT && current->scopeDepth == 0) emitByte(OP_REPL_PRINT);
  else emitByte(OP_POP);
  endStatement();
}

static void ifStatement(void) {
  expression();
  int thenJump = emitJump(OP_JUMP_IF_FALSE);
  emitByte(OP_POP);
  scopedBlock();
  int elseJump = emitJump(OP_JUMP);
  patchJump(thenJump);
  emitByte(OP_POP);
  if (match(T_ELSE)) {
    if (match(T_IF)) ifStatement();
    else scopedBlock();
  }
  patchJump(elseJump);
}

static void pushLoop(Loop* l, int start, int localBase) {
  l->enclosing = current->loop; l->start = start; l->localBase = localBase;
  l->tryDepth = current->tryDepth; l->breakCount = 0;
  current->loop = l;
}

static void popLoop(void) {
  Loop* l = current->loop;
  for (int i = 0; i < l->breakCount; i++) patchJump(l->breaks[i]);
  current->loop = l->enclosing;
}

static void whileStatement(void) {
  int start = currentChunk()->count;
  Loop loop;
  pushLoop(&loop, start, current->localCount);
  expression();
  int exitJump = emitJump(OP_JUMP_IF_FALSE);
  emitByte(OP_POP);
  scopedBlock();
  emitLoop(start);
  patchJump(exitJump);
  emitByte(OP_POP);
  popLoop();
}

static void forStatement(void) {
  beginScope();
  consume(T_IDENT, "Expected a loop variable name after 'for'.");
  Token var = parser.previous;
  consume(T_IN, "Expected 'in' after the loop variable.");
  expression();
  Token iterName = { T_IDENT, "(iter)", 6, parser.previous.line, "" };
  Token idxName = { T_IDENT, "(idx)", 5, parser.previous.line, "" };
  addLocal(iterName); markInitialized();
  emitConstant(NUM_VAL(0));
  addLocal(idxName); markInitialized();

  int iterSlot = current->localCount - 2;
  int start = currentChunk()->count;
  Loop loop;
  pushLoop(&loop, start, current->localCount);

  emitByte(OP_FOR_NEXT);
  emitByte((uint8_t)iterSlot);
  emitByte(0xff); emitByte(0xff);
  int exitJump = currentChunk()->count - 2; /* taken when the iterable is exhausted */

  beginScope();
  addLocal(var); markInitialized();
  scopedBlock();
  endScope();
  emitLoop(start);
  patchJump(exitJump);
  popLoop();
  endScope();
}

static void returnStatement(void) {
  if (current->type == TYPE_SCRIPT) error("Can't return from top-level code.");
  if (check(T_SEMI) || check(T_RBRACE) || check(T_EOF)) emitReturn();
  else {
    if (current->type == TYPE_INITIALIZER) error("Can't return a value from init().");
    expression();
    if (current->retSpec[0]) { char what[128]; snprintf(what, sizeof what, "return value of %s", current->label); emitCheckTop(current->retSpec, what); }
    emitByte(OP_RETURN);
  }
  endStatement();
}

static void breakContinue(bool isBreak) {
  Loop* l = current->loop;
  if (!l) { error(isBreak ? "'break' can only be used inside a loop." : "'continue' can only be used inside a loop."); endStatement(); return; }
  for (int i = current->tryDepth; i > l->tryDepth; i--) emitByte(OP_END_TRY);
  emitPopsTo(l->localBase);
  if (isBreak) {
    if (l->breakCount == 64) error("Too many 'break' statements in one loop.");
    else l->breaks[l->breakCount++] = emitJump(OP_JUMP);
  } else {
    emitLoop(l->start);
  }
  endStatement();
}

static void tryStatement(void) {
  int tryJump = emitJump(OP_TRY);
  current->tryDepth++;
  scopedBlock();
  current->tryDepth--;
  emitByte(OP_END_TRY);
  int endJump = emitJump(OP_JUMP);
  patchJump(tryJump);
  consume(T_CATCH, "Expected 'catch' after the try block.");
  beginScope();
  consume(T_IDENT, "Expected a name for the error after 'catch'.");
  addLocal(parser.previous); markInitialized();
  scopedBlock();
  endScope();
  patchJump(endJump);
}

static void synchronize(void) {
  parser.panicMode = false;
  while (parser.current.type != T_EOF) {
    if (parser.previous.type == T_SEMI) return;
    switch (parser.current.type) {
      case T_LET: case T_CLASS: case T_FN: case T_FOR: case T_IF: case T_WHILE: case T_RETURN: case T_TRY: case T_THROW: case T_IMPORT: return;
      default: break;
    }
    advance();
  }
}

static void declaration(void) {
  if (++nesting > 200) { error("Blocks are nested too deeply."); nesting--; if (!check(T_EOF)) advance(); synchronize(); return; }
  if (match(T_LET)) letDeclaration();
  else if (match(T_CLASS)) classDeclaration();
  else if (check(T_FN) && peekNext().type == T_IDENT) { advance(); funDeclaration(false); }
  else if (match(T_ASYNC)) {
    if (!match(T_FN)) errorAtCurrent("Expected 'fn' after 'async'.");
    else funDeclaration(true);
  }
  else if (match(T_IMPORT)) importStatement();
  else statement();
  nesting--;
  if (parser.panicMode) synchronize();
}

static void statement(void) {
  if (match(T_IF)) ifStatement();
  else if (match(T_WHILE)) whileStatement();
  else if (match(T_FOR)) forStatement();
  else if (match(T_RETURN)) returnStatement();
  else if (match(T_BREAK)) breakContinue(true);
  else if (match(T_CONTINUE)) breakContinue(false);
  else if (match(T_TRY)) tryStatement();
  else if (match(T_THROW)) { expression(); emitByte(OP_THROW); endStatement(); }
  else if (check(T_LBRACE)) { advance(); beginScope(); block(); endScope(); }
  else expressionStatement();
}

ObjFunction* compile(const char* source, ObjModule* module, bool* needMoreInput) {
  if (!IS_NIL(vm.fxCompile)) return compileWithFaxal(source, module, needMoreInput);
  initScanner(source, 1);
  Compiler compiler;
  currentModule = module;
  current = NULL;
  currentClass = NULL;
  initCompiler(&compiler, TYPE_SCRIPT);
  parser.hadError = false; parser.panicMode = false; parser.eofError = false; nesting = 0;
  errorReported = false; compileErrorLine = 0; compileErrorCol = 0; compileErrorMsg[0] = '\0';

  advance();
  skipSemis();
  while (!check(T_EOF)) { declaration(); skipSemis(); }
  ObjFunction* f = endCompiler();
  if (needMoreInput) *needMoreInput = parser.hadError && parser.eofError;
  return parser.hadError ? NULL : f;
}
