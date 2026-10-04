/* stdlib.c: built-in functions, methods, namespaces (math, os, fs, time, json) and turtle graphics */
#include "faxal.h"
#include <math.h>
#include <ctype.h>
#include <time.h>
#include <errno.h>
#include <limits.h>

#define NATIVE(name) static bool name(int argc, Value* args, Value* out)
#define UNUSED (void)argc; (void)args; (void)out

static Value strVal(const char* s, int n) { return OBJ_VAL(newString(s, n)); }

static bool argNum(const char* fn, Value v, double* out) {
  if (!IS_NUM(v)) return throwError("%s() expects a number, got %s", fn, typeName(v));
  *out = AS_NUM(v);
  return true;
}
static bool argInt(const char* fn, Value v, int* out) {
  if (!IS_NUM(v) || AS_NUM(v) != floor(AS_NUM(v)) || fabs(AS_NUM(v)) > 2147483647.0) return throwError("%s() expects a whole number, got %s", fn, typeName(v));
  *out = (int)AS_NUM(v);
  return true;
}
static bool argStr(const char* fn, Value v, ObjString** out) {
  if (!IS_STRING(v)) return throwError("%s() expects a string, got %s", fn, typeName(v));
  *out = AS_STRING(v);
  return true;
}
static bool argFn(const char* fn, Value v) {
  if (!IS_CALLABLE(v)) return throwError("%s() expects a function, got %s", fn, typeName(v));
  return true;
}

#define NUM(fn, i, var) double var; if (!argNum(fn, args[i], &var)) return false
#define INT(fn, i, var) int var; if (!argInt(fn, args[i], &var)) return false
#define STR(fn, i, var) ObjString* var; if (!argStr(fn, args[i], &var)) return false

/* ------------------------------------------------------------ core globals */

NATIVE(n_print) {
  (void)out;
  Buffer b; bufInit(&b);
  for (int i = 0; i < argc; i++) {
    if (i) bufChar(&b, ' ');
    if (!appendValue(&b, args[i], false, 0)) { bufFree(&b); return false; }
  }
  bufChar(&b, '\n');
  bool ok = vmWrite(b.data, b.len);
  bufFree(&b);
  return ok;
}

NATIVE(n_write) {
  (void)out;
  Buffer b; bufInit(&b);
  for (int i = 0; i < argc; i++) {
    if (!appendValue(&b, args[i], false, 0)) { bufFree(&b); return false; }
  }
  bool ok = vmWrite(b.data ? b.data : "", b.len);
  bufFree(&b);
  return ok;
}

NATIVE(n_input) {
  if (argc > 0) {
    Buffer b; bufInit(&b);
    if (!appendValue(&b, args[0], false, 0)) { bufFree(&b); return false; }
    vmWrite(b.data, b.len);
    bufFree(&b);
  }
  fflush(stdout);
  Buffer line; bufInit(&line);
  int c;
  bool any = false;
  while ((c = fgetc(stdin)) != EOF) { any = true; if (c == '\n') break; bufChar(&line, (char)c); }
  if (!any) { *out = NIL_VAL; bufFree(&line); return true; }
  if (line.len && line.data[line.len - 1] == '\r') line.len--;
  *out = strVal(line.data ? line.data : "", line.len);
  bufFree(&line);
  return true;
}

NATIVE(n_len) {
  Value v = args[0];
  if (IS_STRING(v)) *out = NUM_VAL(AS_STRING(v)->length);
  else if (IS_LIST(v)) *out = NUM_VAL(AS_LIST(v)->count);
  else if (IS_MAP(v)) *out = NUM_VAL(AS_MAP(v)->map.live);
  else if (IS_RANGE(v)) *out = NUM_VAL(rangeLength(AS_RANGE(v)));
  else return throwError("len() needs a string, list, map or range, got %s", typeName(v));
  return true;
}

NATIVE(n_str) { (void)argc; ObjString* s = valueToString(args[0]); if (!s) return false; *out = OBJ_VAL(s); return true; }

NATIVE(n_repr) {
  (void)argc;
  Buffer b; bufInit(&b);
  if (!appendValue(&b, args[0], true, 0)) { bufFree(&b); return false; }
  *out = strVal(b.data ? b.data : "", b.len);
  bufFree(&b);
  return true;
}

static bool parseNumber(const char* s, double* d) {
  while (isspace((unsigned char)*s)) s++;
  if (!(isdigit((unsigned char)*s) || *s == '-' || *s == '+' || *s == '.')) return false;
  char* end;
  *d = strtod(s, &end);
  if (end == s) return false;
  while (isspace((unsigned char)*end)) end++;
  return *end == '\0';
}

NATIVE(n_num) {
  (void)argc;
  if (IS_NUM(args[0])) { *out = args[0]; return true; }
  if (IS_BOOL(args[0])) { *out = NUM_VAL(AS_BOOL(args[0]) ? 1 : 0); return true; }
  double d;
  if (IS_STRING(args[0]) && parseNumber(AS_CSTRING(args[0]), &d)) *out = NUM_VAL(d);
  else *out = NIL_VAL;
  return true;
}

NATIVE(n_int) {
  (void)argc;
  double d;
  if (IS_NUM(args[0])) d = AS_NUM(args[0]);
  else if (!(IS_STRING(args[0]) && parseNumber(AS_CSTRING(args[0]), &d))) { *out = NIL_VAL; return true; }
  *out = NUM_VAL(trunc(d));
  return true;
}

NATIVE(n_type) { (void)argc; *out = OBJ_VAL(cstring(typeName(args[0]))); return true; }

NATIVE(n_range) {
  double a, b = 0, s = 1;
  if (argc == 1) { NUM("range", 0, e); a = 0; b = e; }
  else {
    if (!argNum("range", args[0], &a) || !argNum("range", args[1], &b)) return false;
    if (argc == 3 && !argNum("range", args[2], &s)) return false;
  }
  if (s == 0) return throwError("range() step can't be 0");
  *out = OBJ_VAL(newRange(a, b, s));
  return true;
}

NATIVE(n_isinstance) {
  (void)argc;
  if (!IS_CLASS(args[1])) return throwError("isinstance() needs a class as its second argument, got %s", typeName(args[1]));
  *out = BOOL_VAL(false);
  if (!IS_INSTANCE(args[0])) return true;
  for (ObjClass* k = AS_INSTANCE(args[0])->klass; k; k = k->super)
    if (k == AS_CLASS(args[1])) { *out = BOOL_VAL(true); break; }
  return true;
}


/* __check(value, "num|str", "parameter 'x' of f()") backs the optional type annotations (fn f(x: num) -> str).
   The compiler emits calls to it; it returns the value when the type fits and throws a type error when not. */
static bool typeNameMatches(Value v, const char* t, size_t n) {
#define IS_T(s) (n == sizeof(s) - 1 && memcmp(t, s, n) == 0)
  if (IS_T("any")) return true;
  if (IS_T("num") || IS_T("number")) return IS_NUM(v);
  if (IS_T("int")) return IS_NUM(v) && AS_NUM(v) == floor(AS_NUM(v)) && isfinite(AS_NUM(v));
  if (IS_T("str") || IS_T("string")) return IS_STRING(v);
  if (IS_T("bool") || IS_T("boolean")) return IS_BOOL(v);
  if (IS_T("nil")) return IS_NIL(v);
  if (IS_T("list")) return IS_LIST(v);
  if (IS_T("map")) return IS_MAP(v);
  if (IS_T("range")) return IS_RANGE(v);
  if (IS_T("fn") || IS_T("function")) return IS_CALLABLE(v);
  if (IS_T("class")) return IS_CLASS(v);
#undef IS_T
  if (IS_INSTANCE(v)) {   /* anything else names a class */
    for (ObjClass* k = AS_INSTANCE(v)->klass; k; k = k->super)
      if ((size_t)k->name->length == n && memcmp(k->name->chars, t, n) == 0) return true;
  }
  return false;
}

NATIVE(n_check) {
  (void)argc;
  if (!IS_STRING(args[1]) || !IS_STRING(args[2])) return throwError("__check() is called by the compiler");
  const char* spec = AS_CSTRING(args[1]);
  for (const char* p = spec; *p;) {
    const char* e = strchr(p, '|');
    size_t n = e ? (size_t)(e - p) : strlen(p);
    if (typeNameMatches(args[0], p, n)) { *out = args[0]; return true; }
    if (!e) break;
    p = e + 1;
  }
  Buffer want; bufInit(&want);
  for (const char* p = spec; *p; p++) { if (*p == '|') bufStr(&want, " or "); else bufChar(&want, *p); }
  Buffer got; bufInit(&got);
  bufStr(&got, typeName(args[0]));
  if (IS_INSTANCE(args[0])) { bufStr(&got, " ("); bufStr(&got, AS_INSTANCE(args[0])->klass->name->chars); bufChar(&got, ')'); }
  else if (IS_NUM(args[0]) || IS_BOOL(args[0]) || IS_STRING(args[0])) {
    Buffer r; bufInit(&r);
    bool printed = appendValue(&r, args[0], true, 0);   /* numbers, booleans and strings never run user code */
    if (printed && r.len <= 24) { bufStr(&got, " "); bufAppend(&got, r.data, r.len); }
    bufFree(&r);
  }
  bool ok = throwError("Type error: %s must be %s, got %s", AS_CSTRING(args[2]), want.data ? want.data : "?", got.data ? got.data : "?");
  bufFree(&want); bufFree(&got);
  return ok;
}

/* load("path") is `import` as a function: it can take a path computed at run time. */
NATIVE(n_load) {
  (void)argc;
  ObjModule* caller = vm.frameCount > 0 ? vm.frames[vm.frameCount - 1].closure->function->module : vm.mainModule;
  return importModule(args[0], caller, out);
}

NATIVE(n_assert) {
  if (!isFalsey(args[0])) return true;
  (void)out;
  if (argc > 1) {
    ObjString* m = valueToString(args[1]);
    if (!m) return false;
    return throwError("Assertion failed: %s", m->chars);
  }
  return throwError("Assertion failed");
}

NATIVE(n_ord) {
  (void)argc;
  STR("ord", 0, s);
  if (s->length == 0) return throwError("ord() needs a non-empty string");
  unsigned char c = (unsigned char)s->chars[0];
  int cp = c, n = 0;
  if (c >= 0xF0) { cp = c & 7; n = 3; } else if (c >= 0xE0) { cp = c & 15; n = 2; } else if (c >= 0xC0) { cp = c & 31; n = 1; }
  for (int i = 1; i <= n && i < s->length; i++) cp = (cp << 6) | (s->chars[i] & 63);
  *out = NUM_VAL(cp);
  return true;
}

static int encodeUtf8(int cp, char* o) {
  if (cp < 0x80) { o[0] = (char)cp; return 1; }
  if (cp < 0x800) { o[0] = (char)(0xC0 | (cp >> 6)); o[1] = (char)(0x80 | (cp & 63)); return 2; }
  if (cp < 0x10000) { o[0] = (char)(0xE0 | (cp >> 12)); o[1] = (char)(0x80 | ((cp >> 6) & 63)); o[2] = (char)(0x80 | (cp & 63)); return 3; }
  o[0] = (char)(0xF0 | (cp >> 18)); o[1] = (char)(0x80 | ((cp >> 12) & 63)); o[2] = (char)(0x80 | ((cp >> 6) & 63)); o[3] = (char)(0x80 | (cp & 63));
  return 4;
}

NATIVE(n_chr) {
  (void)argc;
  INT("chr", 0, cp);
  if (cp < 0 || cp > 0x10FFFF) return throwError("chr() needs a code point from 0 to 1114111");
  char buf[4];
  *out = strVal(buf, encodeUtf8(cp, buf));
  return true;
}

NATIVE(n_exit) {
  (void)out;
  int code = 0;
  if (argc > 0 && !argInt("exit", args[0], &code)) return false;
  fflush(stdout);
  exit(code);
}

/* --------------------------------------------------------------------- math */

static uint64_t rngState = 0x9E3779B97F4A7C15ULL;
static double rngNext(void) {
  rngState ^= rngState >> 12; rngState ^= rngState << 25; rngState ^= rngState >> 27;
  return (double)((rngState * 0x2545F4914F6CDD1DULL) >> 11) / 9007199254740992.0;
}

#define MATH1(cname, label, expr) NATIVE(cname) { (void)argc; (void)out; NUM(label, 0, x); *out = NUM_VAL(expr); return true; }
MATH1(m_sqrt, "math.sqrt", sqrt(x))
MATH1(m_sin, "math.sin", sin(x))
MATH1(m_cos, "math.cos", cos(x))
MATH1(m_tan, "math.tan", tan(x))
MATH1(m_asin, "math.asin", asin(x))
MATH1(m_acos, "math.acos", acos(x))
MATH1(m_atan, "math.atan", atan(x))
MATH1(m_log, "math.log", log(x))
MATH1(m_log2, "math.log2", log2(x))
MATH1(m_log10, "math.log10", log10(x))
MATH1(m_exp, "math.exp", exp(x))
MATH1(m_floor, "floor", floor(x))
MATH1(m_ceil, "ceil", ceil(x))
MATH1(m_round, "round", round(x))
MATH1(m_trunc, "math.trunc", trunc(x))
MATH1(m_abs, "abs", fabs(x))
MATH1(m_sign, "math.sign", x > 0 ? 1 : x < 0 ? -1 : 0)
MATH1(m_radians, "math.radians", x * M_PI / 180.0)
MATH1(m_degrees, "math.degrees", x * 180.0 / M_PI)

NATIVE(m_pow) { (void)argc; NUM("math.pow", 0, a); NUM("math.pow", 1, b); *out = NUM_VAL(pow(a, b)); return true; }
NATIVE(m_atan2) { (void)argc; NUM("math.atan2", 0, a); NUM("math.atan2", 1, b); *out = NUM_VAL(atan2(a, b)); return true; }
NATIVE(m_hypot) { (void)argc; NUM("math.hypot", 0, a); NUM("math.hypot", 1, b); *out = NUM_VAL(hypot(a, b)); return true; }
NATIVE(m_clamp) { (void)argc; NUM("math.clamp", 0, x); NUM("math.clamp", 1, lo); NUM("math.clamp", 2, hi); *out = NUM_VAL(x < lo ? lo : x > hi ? hi : x); return true; }

static bool extreme(const char* fn, int argc, Value* args, bool wantMax, Value* out) {
  Value* items = args; int n = argc;
  if (argc == 1 && IS_LIST(args[0])) { items = AS_LIST(args[0])->items; n = AS_LIST(args[0])->count; }
  if (n == 0) return throwError("%s() needs at least one value", fn);
  double best = 0;
  for (int i = 0; i < n; i++) {
    double d;
    if (!argNum(fn, items[i], &d)) return false;
    if (i == 0 || (wantMax ? d > best : d < best)) best = d;
  }
  *out = NUM_VAL(best);
  return true;
}
NATIVE(m_min) { return extreme("min", argc, args, false, out); }
NATIVE(m_max) { return extreme("max", argc, args, true, out); }

NATIVE(m_random) { UNUSED; *out = NUM_VAL(rngNext()); return true; }
NATIVE(m_randint) {
  (void)argc;
  INT("math.randint", 0, lo); INT("math.randint", 1, hi);
  if (hi < lo) return throwError("math.randint(a, b) needs a <= b");
  *out = NUM_VAL(lo + floor(rngNext() * ((double)hi - lo + 1)));
  return true;
}
NATIVE(m_seed) { (void)argc; (void)out; NUM("math.seed", 0, s); rngState = (uint64_t)(int64_t)s * 0x9E3779B97F4A7C15ULL + 0x1234567ULL; if (!rngState) rngState = 1; return true; }

/* --------------------------------------------------------------- time/os/fs */

static double nowSeconds(void) { return fx_now(); }
NATIVE(t_now) { UNUSED; *out = NUM_VAL(nowSeconds()); return true; }
NATIVE(t_clock) { UNUSED; *out = NUM_VAL((double)clock() / CLOCKS_PER_SEC); return true; }
NATIVE(t_sleep) {
  (void)argc; (void)out;
  NUM("time.sleep", 0, s);
  fflush(stdout);
  fx_sleep(s);
  return true;
}

NATIVE(os_env) {
  (void)argc;
  STR("os.env", 0, name);
  const char* v = getenv(name->chars);
  *out = v ? strVal(v, (int)strlen(v)) : NIL_VAL;
  return true;
}
/* os.run("command") runs a shell command and returns {code, output}. Not available in sandbox mode. */
NATIVE(os_run) {
  (void)argc;
  STR("os.run", 0, cmd);
  Buffer full; bufInit(&full);
  bufAppend(&full, cmd->chars, cmd->length);
  bufStr(&full, " 2>&1");
  fflush(stdout);
  FILE* p = fx_popen(full.data);
  bufFree(&full);
  if (!p) return throwError("Cannot run '%s': %s", cmd->chars, strerror(errno));
  Buffer o; bufInit(&o);
  char chunk[4096]; size_t n;
  while ((n = fread(chunk, 1, sizeof chunk, p)) > 0) bufAppend(&o, chunk, (int)n);
  int code = fx_pclose(p);
  ObjMap* m = newMap();
  defineValue(&m->map, "code", NUM_VAL(code));
  defineValue(&m->map, "output", strVal(o.data ? o.data : "", o.len));
  bufFree(&o);
  *out = OBJ_VAL(m);
  return true;
}

/* os.stdin_read(n) reads exactly n bytes from standard input (fewer at the end of the input; nil when nothing is left). */
NATIVE(os_stdin_read) {
  (void)argc; INT("os.stdin_read", 0, n);
  if (n < 0 || n > 64 * 1024 * 1024) return throwError("os.stdin_read() needs a size between 0 and 64 MB");
  char* buf = malloc((size_t)n + 1);
  size_t got = fread(buf, 1, (size_t)n, stdin);
  *out = (got == 0 && n > 0) ? NIL_VAL : strVal(buf, (int)got);
  free(buf);
  return true;
}
NATIVE(os_flush) { UNUSED; fflush(stdout); *out = NIL_VAL; return true; }


/* ------------------------------------------------------------------------ net
 * Raw TCP for the standard library's std/http. Handles are small numbers. Not available in safe mode. */
#define MAX_SOCKETS 256
static fx_socket netSocks[MAX_SOCKETS];
static bool netUsed[MAX_SOCKETS];

static int netAdd(fx_socket s) {
  for (int i = 0; i < MAX_SOCKETS; i++) if (!netUsed[i]) { netUsed[i] = true; netSocks[i] = s; return i; }
  fx_net_close(s);
  return -1;
}

static bool netGet(const char* fn, Value v, fx_socket* out) {
  if (!IS_NUM(v) || AS_NUM(v) < 0 || AS_NUM(v) >= MAX_SOCKETS || AS_NUM(v) != floor(AS_NUM(v))) return throwError("%s() expects a connection from net.connect or net.accept, got %s", fn, typeName(v));
  int i = (int)AS_NUM(v);
  if (!netUsed[i]) return throwError("%s(): that connection is closed", fn);
  *out = netSocks[i];
  return true;
}

NATIVE(net_listen) {
  fx_net_init();
  INT("net.listen", 0, port);
  const char* host = "127.0.0.1";
  if (argc > 1) { ObjString* h; if (!argStr("net.listen", args[1], &h)) return false; host = h->chars; }
  char portStr[16]; snprintf(portStr, sizeof portStr, "%d", port);
  struct addrinfo hints, *res = NULL;
  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM; hints.ai_flags = AI_PASSIVE;
  if (getaddrinfo(host, portStr, &hints, &res) != 0 || !res) return throwError("net.listen: can't use the address '%s'", host);
  fx_socket s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  if (s == FX_BAD_SOCKET) { freeaddrinfo(res); return throwError("net.listen: %s", fx_net_error()); }
  int yes = 1;
  setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (const char*)&yes, sizeof yes);
  if (bind(s, res->ai_addr, (int)res->ai_addrlen) != 0 || listen(s, 128) != 0) {
    const char* why = fx_net_error();
    freeaddrinfo(res); fx_net_close(s);
    return throwError("net.listen: can't listen on %s:%d (%s)", host, port, why);
  }
  freeaddrinfo(res);
  int h = netAdd(s);
  if (h < 0) return throwError("net.listen: too many open connections");
  *out = NUM_VAL(h);
  return true;
}

NATIVE(net_port) {
  (void)argc; fx_socket s; if (!netGet("net.port", args[0], &s)) return false;
  struct sockaddr_in a; socklen_t len = sizeof a;
  if (getsockname(s, (struct sockaddr*)&a, &len) != 0) return throwError("net.port: %s", fx_net_error());
  *out = NUM_VAL(ntohs(a.sin_port));
  return true;
}

/* net.accept(listener, timeout): a new connection, or nil if none arrives within `timeout` seconds (0 = just look, omitted = wait) */
NATIVE(net_accept) {
  fx_socket s; if (!netGet("net.accept", args[0], &s)) return false;
  if (argc > 1) {
    NUM("net.accept", 1, t);
    int w = fx_net_wait(s, false, t < 0 ? 0 : t);
    if (w < 0) return throwError("net.accept: %s", fx_net_error());
    if (w == 0) { *out = NIL_VAL; return true; }
  }
  fx_socket c = accept(s, NULL, NULL);
  if (c == FX_BAD_SOCKET) { *out = NIL_VAL; return true; }
  int h = netAdd(c);
  if (h < 0) return throwError("net.accept: too many open connections");
  *out = NUM_VAL(h);
  return true;
}

NATIVE(net_connect) {
  fx_net_init();
  STR("net.connect", 0, host); INT("net.connect", 1, port);
  double timeout = 10;
  if (argc > 2) { if (!argNum("net.connect", args[2], &timeout)) return false; }
  char portStr[16]; snprintf(portStr, sizeof portStr, "%d", port);
  struct addrinfo hints, *res = NULL;
  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
  if (getaddrinfo(host->chars, portStr, &hints, &res) != 0 || !res) return throwError("net.connect: can't find the host '%s'", host->chars);
  fx_socket s = FX_BAD_SOCKET;
  const char* why = "no address worked";
  for (struct addrinfo* a = res; a; a = a->ai_next) {
    fx_socket t = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
    if (t == FX_BAD_SOCKET) continue;
    fx_net_blocking(t, false);
    int r = connect(t, a->ai_addr, (int)a->ai_addrlen);
    bool ok = r == 0;
    if (!ok && fx_net_would_block()) {
      if (fx_net_wait(t, true, timeout) == 1) {
        int err = 0; socklen_t el = sizeof err;
        getsockopt(t, SOL_SOCKET, SO_ERROR, (char*)&err, &el);
        ok = err == 0;
        if (!ok) why = "the connection was refused";
      } else why = "the connection timed out";
    } else if (!ok) why = fx_net_error();
    if (ok) { fx_net_blocking(t, true); s = t; break; }
    fx_net_close(t);
  }
  freeaddrinfo(res);
  if (s == FX_BAD_SOCKET) return throwError("net.connect: can't connect to %s:%d (%s)", host->chars, port, why);
  int h = netAdd(s);
  if (h < 0) return throwError("net.connect: too many open connections");
  *out = NUM_VAL(h);
  return true;
}

/* net.read(conn, max, timeout): up to `max` bytes as text; "" when the other side has closed; nil if nothing arrived within `timeout` seconds */
NATIVE(net_read) {
  fx_socket s; if (!netGet("net.read", args[0], &s)) return false;
  int max = 65536;
  if (argc > 1 && !argInt("net.read", args[1], &max)) return false;
  if (max < 1 || max > 16 * 1024 * 1024) return throwError("net.read: max must be between 1 and 16777216");
  if (argc > 2 && !IS_NIL(args[2])) {
    NUM("net.read", 2, t);
    if (t >= 0) {
      int w = fx_net_wait(s, false, t);
      if (w < 0) return throwError("net.read: %s", fx_net_error());
      if (w == 0) { *out = NIL_VAL; return true; }
    }
  }
  char* buf = malloc((size_t)max);
  int n = (int)recv(s, buf, (size_t)max, 0);
  if (n < 0) n = 0;        /* a reset connection reads as closed */
  *out = strVal(buf, n);
  free(buf);
  return true;
}

NATIVE(net_write) {
  (void)argc; fx_socket s; if (!netGet("net.write", args[0], &s)) return false;
  ObjString* d = valueToString(args[1]);
  if (!d) return false;
  int sent = 0;
  while (sent < d->length) {
    int n = (int)send(s, d->chars + sent, (size_t)(d->length - sent), 0);
    if (n <= 0) {
      if (n < 0 && fx_net_would_block()) { fx_net_wait(s, true, 1.0); continue; }
      return throwError("net.write: the connection was closed");
    }
    sent += n;
  }
  *out = NUM_VAL(sent);
  return true;
}

NATIVE(net_close) {
  (void)argc; (void)out;
  if (!IS_NUM(args[0]) || AS_NUM(args[0]) < 0 || AS_NUM(args[0]) >= MAX_SOCKETS) return throwError("net.close() expects a connection");
  int i = (int)AS_NUM(args[0]);
  if (netUsed[i]) { fx_net_close(netSocks[i]); netUsed[i] = false; }
  return true;
}

NATIVE(os_cwd) { UNUSED; char buf[PATH_MAX]; if (!fx_getcwd(buf, sizeof buf)) return throwError("os.cwd() failed"); *out = strVal(buf, (int)strlen(buf)); return true; }

NATIVE(fs_read) {
  (void)argc;
  STR("fs.read", 0, p);
  char* s = readFile(p->chars);
  if (!s) return throwError("Cannot read '%s': %s", p->chars, strerror(errno));
  *out = strVal(s, (int)strlen(s));
  free(s);
  return true;
}

static bool writeFile(const char* fn, int argc, Value* args, const char* mode) {
  (void)argc;
  ObjString* p; if (!argStr(fn, args[0], &p)) return false;
  ObjString* d = valueToString(args[1]);
  if (!d) return false;
  FILE* f = fopen(p->chars, mode);
  if (!f) return throwError("Cannot write '%s': %s", p->chars, strerror(errno));
  fwrite(d->chars, 1, (size_t)d->length, f);
  fclose(f);
  return true;
}
NATIVE(fs_write) { (void)out; return writeFile("fs.write", argc, args, "wb"); }
NATIVE(fs_append) { (void)out; return writeFile("fs.append", argc, args, "ab"); }
NATIVE(fs_exists) { (void)argc; STR("fs.exists", 0, p); *out = BOOL_VAL(fx_exists(p->chars)); return true; }
NATIVE(fs_is_dir) { (void)argc; STR("fs.is_dir", 0, p); *out = BOOL_VAL(fx_is_dir(p->chars)); return true; }
NATIVE(fs_remove) { (void)argc; (void)out; STR("fs.remove", 0, p); if (remove(p->chars) != 0) return throwError("Cannot remove '%s': %s", p->chars, strerror(errno)); return true; }
NATIVE(fs_mkdir) { (void)argc; (void)out; STR("fs.mkdir", 0, p); if (!fx_mkdir(p->chars)) return throwError("Cannot create '%s': %s", p->chars, strerror(errno)); return true; }

static int cmpStrPtr(const void* a, const void* b) { return strcmp(*(char* const*)a, *(char* const*)b); }
NATIVE(fs_list) {
  (void)argc;
  STR("fs.list", 0, p);
  int n = 0;
  char** names = fx_list_dir(p->chars, &n);
  if (!names) return throwError("Cannot list '%s': %s", p->chars, strerror(errno));
  qsort(names, (size_t)n, sizeof(char*), cmpStrPtr);
  ObjList* l = newList();
  for (int i = 0; i < n; i++) { listPush(l, strVal(names[i], (int)strlen(names[i]))); free(names[i]); }
  free(names);
  *out = OBJ_VAL(l);
  return true;
}

static Value splitLines(const char* s, int len) {
  ObjList* l = newList();
  int start = 0;
  for (int i = 0; i <= len; i++) {
    if (i == len || s[i] == '\n') {
      if (i == len && start == len) break;
      int end = i;
      if (end > start && s[end - 1] == '\r') end--;
      listPush(l, strVal(s + start, end - start));
      start = i + 1;
    }
  }
  return OBJ_VAL(l);
}

NATIVE(fs_lines) {
  (void)argc;
  STR("fs.lines", 0, p);
  char* s = readFile(p->chars);
  if (!s) return throwError("Cannot read '%s': %s", p->chars, strerror(errno));
  *out = splitLines(s, (int)strlen(s));
  free(s);
  return true;
}

/* --------------------------------------------------------------------- json */

void jsonQuote(Buffer* b, const char* s, int len) {
  bufChar(b, '"');
  for (int i = 0; i < len; i++) {
    unsigned char c = (unsigned char)s[i];
    switch (c) {
      case '"': bufStr(b, "\\\""); break;
      case '\\': bufStr(b, "\\\\"); break;
      case '\n': bufStr(b, "\\n"); break;
      case '\r': bufStr(b, "\\r"); break;
      case '\t': bufStr(b, "\\t"); break;
      default:
        if (c < 0x20) bufPrintf(b, "\\u%04x", c);
        else bufChar(b, (char)c);
    }
  }
  bufChar(b, '"');
}

static void jsonIndent(Buffer* b, int indent, int level) {
  if (!indent) return;
  bufChar(b, '\n');
  for (int i = 0; i < indent * level; i++) bufChar(b, ' ');
}

static bool jsonEncode(Buffer* b, Value v, int indent, int level) {
  if (level > 100) return throwError("json.encode: data is nested too deeply");
  if (b->len > (64 << 20)) return throwError("json.encode: result is too large");
  char num[40];
  switch (v.type) {
    case VAL_NIL: bufStr(b, "null"); return true;
    case VAL_BOOL: bufStr(b, AS_BOOL(v) ? "true" : "false"); return true;
    case VAL_NUM:
      if (isnan(AS_NUM(v)) || isinf(AS_NUM(v))) return throwError("json.encode: can't encode nan or inf");
      if (AS_NUM(v) == floor(AS_NUM(v)) && fabs(AS_NUM(v)) < 1e15) snprintf(num, sizeof num, "%.0f", AS_NUM(v));
      else snprintf(num, sizeof num, "%.17g", AS_NUM(v));
      bufStr(b, num);
      return true;
    case VAL_OBJ: break;
  }
  if (IS_STRING(v)) { jsonQuote(b, AS_CSTRING(v), AS_STRING(v)->length); return true; }
  if (IS_LIST(v)) {
    ObjList* l = AS_LIST(v);
    if (l->count == 0) { bufStr(b, "[]"); return true; }
    bufChar(b, '[');
    for (int i = 0; i < l->count; i++) {
      if (i) bufChar(b, ',');
      jsonIndent(b, indent, level + 1);
      if (!jsonEncode(b, l->items[i], indent, level + 1)) return false;
    }
    jsonIndent(b, indent, level);
    bufChar(b, ']');
    return true;
  }
  if (IS_MAP(v) || IS_INSTANCE(v)) {
    Map* m = IS_MAP(v) ? &AS_MAP(v)->map : &AS_INSTANCE(v)->fields;
    if (m->live == 0) { bufStr(b, "{}"); return true; }
    bufChar(b, '{');
    bool first = true;
    for (int i = 0; i < m->count; i++) {
      if (!m->entries[i].live) continue;
      if (!first) bufChar(b, ',');
      first = false;
      jsonIndent(b, indent, level + 1);
      ObjString* k = valueToString(m->entries[i].key);
      if (!k) return false;
      jsonQuote(b, k->chars, k->length);
      bufStr(b, indent ? ": " : ":");
      if (!jsonEncode(b, m->entries[i].value, indent, level + 1)) return false;
    }
    jsonIndent(b, indent, level);
    bufChar(b, '}');
    return true;
  }
  return throwError("json.encode: can't encode a %s", typeName(v));
}

NATIVE(j_encode) {
  int indent = 0;
  if (argc > 1 && !argInt("json.encode", args[1], &indent)) return false;
  if (indent < 0 || indent > 16) indent = 2;
  Buffer b; bufInit(&b);
  if (!jsonEncode(&b, args[0], indent, 0)) { bufFree(&b); return false; }
  *out = strVal(b.data ? b.data : "", b.len);
  bufFree(&b);
  return true;
}

typedef struct { const char* s; int pos, len; char err[120]; } JsonParser;

static void jsonSkip(JsonParser* p) { while (p->pos < p->len && isspace((unsigned char)p->s[p->pos])) p->pos++; }
static bool jsonFail(JsonParser* p, const char* m) { snprintf(p->err, sizeof p->err, "%s at position %d", m, p->pos); return false; }

static bool jsonValue(JsonParser* p, Value* out, int depth);

static bool jsonString(JsonParser* p, Buffer* b) {
  p->pos++;
  while (p->pos < p->len && p->s[p->pos] != '"') {
    char c = p->s[p->pos++];
    if (c != '\\') { bufChar(b, c); continue; }
    if (p->pos >= p->len) return jsonFail(p, "Unterminated string");
    char e = p->s[p->pos++];
    switch (e) {
      case 'n': bufChar(b, '\n'); break;
      case 't': bufChar(b, '\t'); break;
      case 'r': bufChar(b, '\r'); break;
      case 'b': bufChar(b, '\b'); break;
      case 'f': bufChar(b, '\f'); break;
      case '/': case '\\': case '"': bufChar(b, e); break;
      case 'u': {
        if (p->pos + 4 > p->len) return jsonFail(p, "Bad \\u escape");
        char hex[5] = {0}; memcpy(hex, p->s + p->pos, 4);
        int cp = (int)strtol(hex, NULL, 16);
        p->pos += 4;
        if (cp >= 0xD800 && cp < 0xDC00 && p->pos + 6 <= p->len && p->s[p->pos] == '\\' && p->s[p->pos + 1] == 'u') {
          char h2[5] = {0}; memcpy(h2, p->s + p->pos + 2, 4);
          int lo = (int)strtol(h2, NULL, 16);
          if (lo >= 0xDC00 && lo < 0xE000) { cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00); p->pos += 6; }
        }
        char tmp[4]; bufAppend(b, tmp, encodeUtf8(cp, tmp));
        break;
      }
      default: return jsonFail(p, "Bad escape");
    }
  }
  if (p->pos >= p->len) return jsonFail(p, "Unterminated string");
  p->pos++;
  return true;
}

static bool jsonValue(JsonParser* p, Value* out, int depth) {
  if (depth > 200) return jsonFail(p, "Nested too deeply");
  jsonSkip(p);
  if (p->pos >= p->len) return jsonFail(p, "Unexpected end");
  char c = p->s[p->pos];
  if (c == '"') {
    Buffer b; bufInit(&b);
    bool ok = jsonString(p, &b);
    if (ok) *out = strVal(b.data ? b.data : "", b.len);
    bufFree(&b);
    return ok;
  }
  if (c == '[') {
    p->pos++;
    ObjList* l = newList();
    *out = OBJ_VAL(l);
    jsonSkip(p);
    if (p->pos < p->len && p->s[p->pos] == ']') { p->pos++; return true; }
    for (;;) {
      Value item;
      if (!jsonValue(p, &item, depth + 1)) return false;
      listPush(l, item);
      jsonSkip(p);
      if (p->pos < p->len && p->s[p->pos] == ',') { p->pos++; continue; }
      if (p->pos < p->len && p->s[p->pos] == ']') { p->pos++; return true; }
      return jsonFail(p, "Expected ',' or ']'");
    }
  }
  if (c == '{') {
    p->pos++;
    ObjMap* m = newMap();
    *out = OBJ_VAL(m);
    jsonSkip(p);
    if (p->pos < p->len && p->s[p->pos] == '}') { p->pos++; return true; }
    for (;;) {
      jsonSkip(p);
      if (p->pos >= p->len || p->s[p->pos] != '"') return jsonFail(p, "Expected a string key");
      Buffer kb; bufInit(&kb);
      bool ok = jsonString(p, &kb);
      Value key = ok ? strVal(kb.data ? kb.data : "", kb.len) : NIL_VAL;
      bufFree(&kb);
      if (!ok) return false;
      jsonSkip(p);
      if (p->pos >= p->len || p->s[p->pos] != ':') return jsonFail(p, "Expected ':'");
      p->pos++;
      Value v;
      if (!jsonValue(p, &v, depth + 1)) return false;
      mapSet(&m->map, key, v);
      jsonSkip(p);
      if (p->pos < p->len && p->s[p->pos] == ',') { p->pos++; continue; }
      if (p->pos < p->len && p->s[p->pos] == '}') { p->pos++; return true; }
      return jsonFail(p, "Expected ',' or '}'");
    }
  }
  if (!strncmp(p->s + p->pos, "true", 4)) { p->pos += 4; *out = BOOL_VAL(true); return true; }
  if (!strncmp(p->s + p->pos, "false", 5)) { p->pos += 5; *out = BOOL_VAL(false); return true; }
  if (!strncmp(p->s + p->pos, "null", 4)) { p->pos += 4; *out = NIL_VAL; return true; }
  if (c == '-' || isdigit((unsigned char)c)) {
    char* end;
    double d = strtod(p->s + p->pos, &end);
    if (end == p->s + p->pos) return jsonFail(p, "Bad number");
    p->pos = (int)(end - p->s);
    *out = NUM_VAL(d);
    return true;
  }
  return jsonFail(p, "Unexpected character");
}

NATIVE(j_decode) {
  (void)argc;
  STR("json.decode", 0, s);
  JsonParser p = { s->chars, 0, s->length, "" };
  if (!jsonValue(&p, out, 0)) return throwError("Invalid JSON: %s", p.err);
  jsonSkip(&p);
  if (p.pos != p.len) { p.err[0] = 0; jsonFail(&p, "Extra data"); return throwError("Invalid JSON: %s", p.err); }
  return true;
}

/* ------------------------------------------------------------------- turtle */

static void turtleMove(double dist) {
  Turtle* t = &vm.turtle;
  double rad = t->angle * M_PI / 180.0;
  double nx = t->x + sin(rad) * dist, ny = t->y + cos(rad) * dist;
  if (t->down) {
    if (t->count >= 100000) { vm.fatal = true; throwError("Too many lines drawn"); return; }
    if (t->count == t->cap) { t->cap = t->cap ? t->cap * 2 : 256; t->segs = realloc(t->segs, sizeof(Segment) * (size_t)t->cap); }
    Segment* s = &t->segs[t->count++];
    s->x1 = t->x; s->y1 = t->y; s->x2 = nx; s->y2 = ny; s->color = strdup(t->color); s->width = t->width;
  }
  t->x = nx; t->y = ny;
}

static void addShape(int kind, double a, double b, const char* text) {
  Turtle* t = &vm.turtle;
  if (t->shapeCount >= 20000) { vm.fatal = true; throwError("Too many shapes drawn"); return; }
  if (t->shapeCount == t->shapeCap) { t->shapeCap = t->shapeCap ? t->shapeCap * 2 : 64; t->shapes = realloc(t->shapes, sizeof(Shape) * (size_t)t->shapeCap); }
  Shape* sh = &t->shapes[t->shapeCount++];
  sh->kind = kind; sh->x = t->x; sh->y = t->y; sh->a = a; sh->b = b;
  sh->color = strdup(t->color); sh->width = t->width; sh->text = text ? strdup(text) : NULL;
}

NATIVE(g_circle) { (void)argc; (void)out; NUM("circle", 0, r); addShape(SHAPE_CIRCLE, fabs(r), 0, NULL); return !vm.fatal; }
NATIVE(g_disc) { (void)argc; (void)out; NUM("disc", 0, r); addShape(SHAPE_DISC, fabs(r), 0, NULL); return !vm.fatal; }
NATIVE(g_rect) { (void)argc; (void)out; NUM("rect", 0, w); NUM("rect", 1, h); addShape(SHAPE_RECT, fabs(w), fabs(h), NULL); return !vm.fatal; }
NATIVE(g_box) { (void)argc; (void)out; NUM("box", 0, w); NUM("box", 1, h); addShape(SHAPE_BOX, fabs(w), fabs(h), NULL); return !vm.fatal; }
NATIVE(g_text) {
  (void)out;
  ObjString* s = valueToString(args[0]);
  if (!s) return false;
  double size = 16;
  if (argc > 1 && !argNum("text", args[1], &size)) return false;
  if (s->length > 200) return throwError("text() is limited to 200 characters");
  addShape(SHAPE_TEXT, size, 0, s->chars);
  return !vm.fatal;
}

NATIVE(g_forward) { (void)argc; (void)out; NUM("forward", 0, d); turtleMove(d); return !vm.fatal; }
NATIVE(g_back) { (void)argc; (void)out; NUM("back", 0, d); turtleMove(-d); return !vm.fatal; }
NATIVE(g_turn) { (void)argc; (void)out; NUM("turn", 0, d); vm.turtle.angle += d; return true; }
NATIVE(g_penup) { UNUSED; vm.turtle.down = false; return true; }
NATIVE(g_pendown) { UNUSED; vm.turtle.down = true; return true; }
NATIVE(g_goto) { (void)argc; (void)out; NUM("goto", 0, x); NUM("goto", 1, y); vm.turtle.x = x; vm.turtle.y = y; return true; }
NATIVE(g_home) { UNUSED; vm.turtle.x = 0; vm.turtle.y = 0; vm.turtle.angle = 0; return true; }
NATIVE(g_width) { (void)argc; (void)out; NUM("width", 0, w); vm.turtle.width = w; return true; }
NATIVE(g_color) {
  (void)out;
  char buf[64];
  if (argc == 3) {
    NUM("color", 0, r); NUM("color", 1, g); NUM("color", 2, b);
    snprintf(buf, sizeof buf, "rgb(%d, %d, %d)", (int)fmax(0, fmin(255, r)), (int)fmax(0, fmin(255, g)), (int)fmax(0, fmin(255, b)));
  } else if (argc == 1 && IS_STRING(args[0]) && AS_STRING(args[0])->length < 40) {
    snprintf(buf, sizeof buf, "%s", AS_CSTRING(args[0]));
    for (char* c = buf; *c; c++) if (!(isalnum((unsigned char)*c) || *c == '#' || *c == '(' || *c == ')' || *c == ',' || *c == ' ' || *c == '.' || *c == '%')) return throwError("color(): invalid color name");
  } else return throwError("color() needs a color name like \"white\" or three numbers (r, g, b)");
  free(vm.turtle.color);
  vm.turtle.color = strdup(buf);
  return true;
}
NATIVE(g_background) {
  (void)argc; (void)out;
  STR("background", 0, s);
  for (int i = 0; i < s->length; i++) { char c = s->chars[i]; if (!(isalnum((unsigned char)c) || c == '#' || c == '(' || c == ')' || c == ',' || c == ' ' || c == '.')) return throwError("background(): invalid color name"); }
  free(vm.turtle.background);
  vm.turtle.background = strdup(s->chars);
  return true;
}

void turtleToSvg(Buffer* b) {
  Turtle* t = &vm.turtle;
  double minX = 0, minY = 0, maxX = 1, maxY = 1;
  for (int i = 0; i < t->count; i++) {
    Segment* s = &t->segs[i];
    if (i == 0) { minX = fmin(s->x1, s->x2); maxX = fmax(s->x1, s->x2); minY = fmin(-s->y1, -s->y2); maxY = fmax(-s->y1, -s->y2); }
    minX = fmin(minX, fmin(s->x1, s->x2)); maxX = fmax(maxX, fmax(s->x1, s->x2));
    minY = fmin(minY, fmin(-s->y1, -s->y2)); maxY = fmax(maxY, fmax(-s->y1, -s->y2));
  }
  for (int i = 0; i < t->shapeCount; i++) {
    Shape* sh = &t->shapes[i];
    double hw = sh->kind == SHAPE_CIRCLE || sh->kind == SHAPE_DISC ? sh->a : sh->kind == SHAPE_TEXT ? sh->a * (double)strlen(sh->text) * 0.3 : sh->a / 2;
    double hh = sh->kind == SHAPE_CIRCLE || sh->kind == SHAPE_DISC ? sh->a : sh->kind == SHAPE_TEXT ? sh->a / 2 : sh->b / 2;
    if (i == 0 && t->count == 0) { minX = sh->x - hw; maxX = sh->x + hw; minY = -sh->y - hh; maxY = -sh->y + hh; }
    minX = fmin(minX, sh->x - hw); maxX = fmax(maxX, sh->x + hw);
    minY = fmin(minY, -sh->y - hh); maxY = fmax(maxY, -sh->y + hh);
  }
  double pad = 20;
  bufPrintf(b, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"%.2f %.2f %.2f %.2f\">\n", minX - pad, minY - pad, maxX - minX + 2 * pad, maxY - minY + 2 * pad);
  bufPrintf(b, "<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" fill=\"%s\"/>\n", minX - pad, minY - pad, maxX - minX + 2 * pad, maxY - minY + 2 * pad, t->background ? t->background : "#000");
  bufStr(b, "<g stroke-linecap=\"round\" fill=\"none\">\n");
  for (int i = 0; i < t->count; i++) {
    Segment* s = &t->segs[i];
    bufPrintf(b, "<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" stroke=\"%s\" stroke-width=\"%g\"/>\n", s->x1, -s->y1, s->x2, -s->y2, s->color, s->width);
  }
  for (int i = 0; i < t->shapeCount; i++) {
    Shape* sh = &t->shapes[i];
    switch (sh->kind) {
      case SHAPE_CIRCLE: case SHAPE_DISC:
        bufPrintf(b, "<circle cx=\"%.2f\" cy=\"%.2f\" r=\"%.2f\" %s=\"%s\" stroke-width=\"%g\"%s/>\n", sh->x, -sh->y, sh->a,
                  sh->kind == SHAPE_DISC ? "fill" : "stroke", sh->color, sh->width, sh->kind == SHAPE_DISC ? "" : " fill=\"none\"");
        break;
      case SHAPE_RECT: case SHAPE_BOX:
        bufPrintf(b, "<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" %s=\"%s\" stroke-width=\"%g\"%s/>\n", sh->x - sh->a / 2, -sh->y - sh->b / 2, sh->a, sh->b,
                  sh->kind == SHAPE_BOX ? "fill" : "stroke", sh->color, sh->width, sh->kind == SHAPE_BOX ? "" : " fill=\"none\"");
        break;
      case SHAPE_TEXT: {
        Buffer esc; bufInit(&esc);
        for (const char* p = sh->text; *p; p++) {
          if (*p == '<') bufStr(&esc, "&lt;"); else if (*p == '>') bufStr(&esc, "&gt;"); else if (*p == '&') bufStr(&esc, "&amp;"); else bufChar(&esc, *p);
        }
        bufPrintf(b, "<text x=\"%.2f\" y=\"%.2f\" font-size=\"%.1f\" fill=\"%s\" text-anchor=\"middle\" dominant-baseline=\"central\" font-family=\"sans-serif\">%s</text>\n", sh->x, -sh->y, sh->a, sh->color, esc.data ? esc.data : "");
        bufFree(&esc);
        break;
      }
    }
  }
  bufStr(b, "</g>\n</svg>\n");
}

void turtleToJson(Buffer* b) {
  Turtle* t = &vm.turtle;
  bufStr(b, "{\"background\":");
  if (t->background) jsonQuote(b, t->background, (int)strlen(t->background)); else bufStr(b, "null");
  bufStr(b, ",\"segments\":[");
  for (int i = 0; i < t->count; i++) {
    Segment* s = &t->segs[i];
    if (i) bufChar(b, ',');
    bufPrintf(b, "[%.2f,%.2f,%.2f,%.2f,", s->x1, s->y1, s->x2, s->y2);
    jsonQuote(b, s->color, (int)strlen(s->color));
    bufPrintf(b, ",%g]", s->width);
  }
  bufStr(b, "],\"shapes\":[");
  static const char* kinds[] = {"circle", "disc", "rect", "box", "text"};
  for (int i = 0; i < t->shapeCount; i++) {
    Shape* sh = &t->shapes[i];
    if (i) bufChar(b, ',');
    bufPrintf(b, "[\"%s\",%.2f,%.2f,%.2f,%.2f,", kinds[sh->kind], sh->x, sh->y, sh->a, sh->b);
    jsonQuote(b, sh->color, (int)strlen(sh->color));
    bufPrintf(b, ",%g,", sh->width);
    if (sh->text) jsonQuote(b, sh->text, (int)strlen(sh->text)); else bufStr(b, "null");
    bufChar(b, ']');
  }
  bufStr(b, "]}");
}

NATIVE(g_save_svg) {
  (void)argc; (void)out;
  STR("save_svg", 0, p);
  Buffer b; bufInit(&b);
  turtleToSvg(&b);
  FILE* f = fopen(p->chars, "wb");
  if (!f) { bufFree(&b); return throwError("Cannot write '%s': %s", p->chars, strerror(errno)); }
  fwrite(b.data, 1, (size_t)b.len, f);
  fclose(f);
  bufFree(&b);
  return true;
}

/* ------------------------------------------------------------ string methods */


NATIVE(s_len) { (void)argc; *out = NUM_VAL(AS_STRING(args[0])->length); return true; }
NATIVE(s_upper) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  char* b = malloc((size_t)s->length + 1);
  for (int i = 0; i < s->length; i++) b[i] = (char)toupper((unsigned char)s->chars[i]);
  *out = strVal(b, s->length); free(b); return true;
}
NATIVE(s_lower) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  char* b = malloc((size_t)s->length + 1);
  for (int i = 0; i < s->length; i++) b[i] = (char)tolower((unsigned char)s->chars[i]);
  *out = strVal(b, s->length); free(b); return true;
}
NATIVE(s_trim) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  int a = 0, e = s->length;
  while (a < e && isspace((unsigned char)s->chars[a])) a++;
  while (e > a && isspace((unsigned char)s->chars[e - 1])) e--;
  *out = strVal(s->chars + a, e - a); return true;
}
NATIVE(s_contains) { (void)argc; STR("contains", 1, n); *out = BOOL_VAL(strstr(AS_CSTRING(args[0]), n->chars) != NULL); return true; }
NATIVE(s_starts_with) {
  (void)argc; STR("starts_with", 1, n); ObjString* s = AS_STRING(args[0]);
  *out = BOOL_VAL(n->length <= s->length && memcmp(s->chars, n->chars, (size_t)n->length) == 0); return true;
}
NATIVE(s_ends_with) {
  (void)argc; STR("ends_with", 1, n); ObjString* s = AS_STRING(args[0]);
  *out = BOOL_VAL(n->length <= s->length && memcmp(s->chars + s->length - n->length, n->chars, (size_t)n->length) == 0); return true;
}
NATIVE(s_find) {
  STR("find", 1, n);
  int from = 0;
  if (argc > 2 && !argInt("find", args[2], &from)) return false;
  ObjString* s = AS_STRING(args[0]);
  if (from < 0) from = 0;
  if (from > s->length) { *out = NUM_VAL(-1); return true; }
  const char* f = strstr(s->chars + from, n->chars);
  *out = NUM_VAL(f ? (double)(f - s->chars) : -1);
  return true;
}
NATIVE(s_count) {
  (void)argc; STR("count", 1, n); ObjString* s = AS_STRING(args[0]);
  if (n->length == 0) return throwError("count() needs a non-empty string");
  int c = 0;
  for (const char* p = s->chars; (p = strstr(p, n->chars)); p += n->length) c++;
  *out = NUM_VAL(c); return true;
}
NATIVE(s_replace) {
  (void)argc; STR("replace", 1, from); STR("replace", 2, to);
  ObjString* s = AS_STRING(args[0]);
  if (from->length == 0) return throwError("replace() can't search for an empty string");
  Buffer b; bufInit(&b);
  const char* p = s->chars;
  for (;;) {
    const char* f = strstr(p, from->chars);
    if (!f) { bufStr(&b, p); break; }
    bufAppend(&b, p, (int)(f - p));
    bufAppend(&b, to->chars, to->length);
    p = f + from->length;
  }
  *out = strVal(b.data ? b.data : "", b.len);
  bufFree(&b);
  return true;
}
NATIVE(s_split) {
  ObjString* s = AS_STRING(args[0]);
  ObjList* l = newList();
  *out = OBJ_VAL(l);
  if (argc < 2 || (IS_STRING(args[1]) && AS_STRING(args[1])->length == 0)) {
    for (int i = 0; i < s->length;) { int n = utf8Len((unsigned char)s->chars[i]); if (i + n > s->length) n = s->length - i; listPush(l, strVal(s->chars + i, n)); i += n; }
    return true;
  }
  STR("split", 1, sep);
  const char* p = s->chars;
  for (;;) {
    const char* f = strstr(p, sep->chars);
    if (!f) { listPush(l, strVal(p, (int)strlen(p))); break; }
    listPush(l, strVal(p, (int)(f - p)));
    p = f + sep->length;
  }
  return true;
}
NATIVE(s_chars) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  ObjList* l = newList();
  for (int i = 0; i < s->length;) { int n = utf8Len((unsigned char)s->chars[i]); if (i + n > s->length) n = s->length - i; listPush(l, strVal(s->chars + i, n)); i += n; }
  *out = OBJ_VAL(l); return true;
}
NATIVE(s_lines) { (void)argc; ObjString* s = AS_STRING(args[0]); *out = splitLines(s->chars, s->length); return true; }


static int cpCount(const char* s, int n) { int c = 0; for (int i = 0; i < n; i++) if (((unsigned char)s[i] & 0xC0) != 0x80) c++; return c; }

NATIVE(s_repeat) {
  (void)argc; INT("repeat", 1, n);
  ObjString* s = AS_STRING(args[0]);
  if (n < 0) return throwError("repeat() needs a count of 0 or more");
  if ((double)n * s->length > 16777216.0) return throwError("repeat() result would be too large");
  Buffer b; bufInit(&b);
  for (int i = 0; i < n; i++) bufAppend(&b, s->chars, s->length);
  *out = strVal(b.data ? b.data : "", b.len); bufFree(&b); return true;
}
NATIVE(s_reverse) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  char* r = malloc((size_t)s->length + 1);
  int w = s->length;
  for (int i = 0; i < s->length;) {
    int n = utf8Len((unsigned char)s->chars[i]); if (i + n > s->length) n = s->length - i;
    memcpy(r + w - n, s->chars + i, (size_t)n); w -= n; i += n;
  }
  *out = strVal(r, s->length); free(r); return true;
}
static bool padString(const char* fn, int argc, Value* args, Value* out, int where) {
  int width; if (!argInt(fn, args[1], &width)) return false;
  ObjString* s = AS_STRING(args[0]);
  const char* fill = " "; int fillLen = 1;
  if (argc > 2) {
    ObjString* f; if (!argStr(fn, args[2], &f)) return false;
    if (cpCount(f->chars, f->length) != 1) return throwError("%s() fill must be a single character", fn);
    fill = f->chars; fillLen = f->length;
  }
  int have = cpCount(s->chars, s->length), pad = width - have;
  if (pad <= 0) { *out = args[0]; return true; }
  if (pad > 1000000) return throwError("%s() width is too large", fn);
  int left = where == 0 ? pad : where == 1 ? 0 : pad / 2, right = pad - left;
  Buffer b; bufInit(&b);
  for (int i = 0; i < left; i++) bufAppend(&b, fill, fillLen);
  bufAppend(&b, s->chars, s->length);
  for (int i = 0; i < right; i++) bufAppend(&b, fill, fillLen);
  *out = strVal(b.data, b.len); bufFree(&b); return true;
}
NATIVE(s_pad_left) { return padString("pad_left", argc, args, out, 0); }
NATIVE(s_pad_right) { return padString("pad_right", argc, args, out, 1); }
NATIVE(s_center) { return padString("center", argc, args, out, 2); }
NATIVE(s_lstrip) {
  (void)argc; ObjString* s = AS_STRING(args[0]); int a = 0;
  while (a < s->length && isspace((unsigned char)s->chars[a])) a++;
  *out = strVal(s->chars + a, s->length - a); return true;
}
NATIVE(s_rstrip) {
  (void)argc; ObjString* s = AS_STRING(args[0]); int e = s->length;
  while (e > 0 && isspace((unsigned char)s->chars[e - 1])) e--;
  *out = strVal(s->chars, e); return true;
}
NATIVE(s_capitalize) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  char* r = malloc((size_t)s->length + 1); memcpy(r, s->chars, (size_t)s->length);
  for (int i = 0; i < s->length; i++) r[i] = i == 0 ? (char)toupper((unsigned char)r[i]) : (char)tolower((unsigned char)r[i]);
  *out = strVal(r, s->length); free(r); return true;
}
NATIVE(s_is_digit) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  bool ok = s->length > 0; for (int i = 0; i < s->length; i++) if (!isdigit((unsigned char)s->chars[i])) ok = false;
  *out = BOOL_VAL(ok); return true;
}
NATIVE(s_is_alpha) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  bool ok = s->length > 0; for (int i = 0; i < s->length; i++) if (!isalpha((unsigned char)s->chars[i])) ok = false;
  *out = BOOL_VAL(ok); return true;
}
/* s.bytes(): the bytes of the text as a list of numbers 0..255; from_bytes(list) is the opposite */
NATIVE(s_bytes) {
  (void)argc; ObjString* s = AS_STRING(args[0]);
  ObjList* l = newList();
  push(OBJ_VAL(l));
  for (int i = 0; i < s->length; i++) listPush(l, NUM_VAL((unsigned char)s->chars[i]));
  pop();
  *out = OBJ_VAL(l); return true;
}
NATIVE(g_from_bytes) {
  (void)argc;
  if (!IS_LIST(args[0])) return throwError("from_bytes() expects a list of numbers, got %s", typeName(args[0]));
  ObjList* l = AS_LIST(args[0]);
  char* b = malloc((size_t)l->count + 1);
  for (int i = 0; i < l->count; i++) {
    Value v = l->items[i];
    if (!IS_NUM(v) || AS_NUM(v) < 0 || AS_NUM(v) > 255 || AS_NUM(v) != floor(AS_NUM(v))) { free(b); return throwError("from_bytes() needs whole numbers from 0 to 255"); }
    b[i] = (char)(int)AS_NUM(v);
  }
  *out = strVal(b, l->count); free(b); return true;
}
NATIVE(s_is_empty) { (void)argc; *out = BOOL_VAL(AS_STRING(args[0])->length == 0); return true; }
NATIVE(s_size) { (void)argc; ObjString* s = AS_STRING(args[0]); *out = NUM_VAL(cpCount(s->chars, s->length)); return true; }

const MethodDef stringMethods[] = {
  {"len", s_len, 0, 0}, {"upper", s_upper, 0, 0}, {"lower", s_lower, 0, 0}, {"trim", s_trim, 0, 0},
  {"contains", s_contains, 1, 1}, {"starts_with", s_starts_with, 1, 1}, {"ends_with", s_ends_with, 1, 1},
  {"find", s_find, 1, 2}, {"count", s_count, 1, 1}, {"replace", s_replace, 2, 2},
  {"split", s_split, 0, 1}, {"chars", s_chars, 0, 0}, {"lines", s_lines, 0, 0},
  {"repeat", s_repeat, 1, 1}, {"reverse", s_reverse, 0, 0}, {"pad_left", s_pad_left, 1, 2}, {"pad_right", s_pad_right, 1, 2},
  {"center", s_center, 1, 2}, {"lstrip", s_lstrip, 0, 0}, {"rstrip", s_rstrip, 0, 0}, {"capitalize", s_capitalize, 0, 0},
  {"is_digit", s_is_digit, 0, 0}, {"is_alpha", s_is_alpha, 0, 0}, {"is_empty", s_is_empty, 0, 0}, {"size", s_size, 0, 0}, {"bytes", s_bytes, 0, 0}, {NULL, NULL, 0, 0}
};

/* -------------------------------------------------------------- list methods */

static bool listIndex(const char* fn, ObjList* l, Value idx, int allowEnd, int* out) {
  int i;
  if (!argInt(fn, idx, &i)) return false;
  if (i < 0) i += l->count;
  if (i < 0 || i > l->count - (allowEnd ? 0 : 1)) return throwError("%s(): index %d is out of range (length %d)", fn, (int)AS_NUM(idx), l->count);
  *out = i;
  return true;
}

NATIVE(l_len) { (void)argc; *out = NUM_VAL(AS_LIST(args[0])->count); return true; }
NATIVE(l_push) { (void)argc; listPush(AS_LIST(args[0]), args[1]); *out = args[0]; return true; }
NATIVE(l_pop) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  if (l->count == 0) return throwError("pop() from an empty list");
  *out = l->items[--l->count]; return true;
}
NATIVE(l_insert) {
  (void)argc; ObjList* l = AS_LIST(args[0]); int i;
  if (!listIndex("insert", l, args[1], 1, &i)) return false;
  listPush(l, NIL_VAL);
  memmove(l->items + i + 1, l->items + i, sizeof(Value) * (size_t)(l->count - 1 - i));
  l->items[i] = args[2];
  *out = args[0]; return true;
}
NATIVE(l_remove) {
  (void)argc; ObjList* l = AS_LIST(args[0]); int i;
  if (!listIndex("remove", l, args[1], 0, &i)) return false;
  *out = l->items[i];
  memmove(l->items + i, l->items + i + 1, sizeof(Value) * (size_t)(l->count - 1 - i));
  l->count--; return true;
}
NATIVE(l_clear) { (void)argc; AS_LIST(args[0])->count = 0; *out = args[0]; return true; }
NATIVE(l_contains) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  *out = BOOL_VAL(false);
  for (int i = 0; i < l->count; i++) if (valuesEqual(l->items[i], args[1])) { *out = BOOL_VAL(true); break; }
  return true;
}
NATIVE(l_index_of) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  *out = NUM_VAL(-1);
  for (int i = 0; i < l->count; i++) if (valuesEqual(l->items[i], args[1])) { *out = NUM_VAL(i); break; }
  return true;
}
NATIVE(l_join) {
  ObjList* l = AS_LIST(args[0]);
  ObjString* sep = NULL;
  if (argc > 1 && !argStr("join", args[1], &sep)) return false;
  Buffer b; bufInit(&b);
  for (int i = 0; i < l->count; i++) {
    if (i && sep) bufAppend(&b, sep->chars, sep->length);
    if (!appendValue(&b, l->items[i], false, 0)) { bufFree(&b); return false; }
  }
  *out = strVal(b.data ? b.data : "", b.len);
  bufFree(&b);
  return true;
}
NATIVE(l_reverse) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  for (int i = 0, j = l->count - 1; i < j; i++, j--) { Value t = l->items[i]; l->items[i] = l->items[j]; l->items[j] = t; }
  *out = args[0]; return true;
}
NATIVE(l_slice) {
  ObjList* l = AS_LIST(args[0]);
  int a = 0, b = l->count;
  if (argc > 1 && !argInt("slice", args[1], &a)) return false;
  if (argc > 2 && !argInt("slice", args[2], &b)) return false;
  if (a < 0) a += l->count;
  if (b < 0) b += l->count;
  if (a < 0) a = 0;
  if (b > l->count) b = l->count;
  ObjList* r = newList();
  for (int i = a; i < b; i++) listPush(r, l->items[i]);
  *out = OBJ_VAL(r); return true;
}
NATIVE(l_copy) {
  (void)argc; ObjList* l = AS_LIST(args[0]); ObjList* r = newList();
  for (int i = 0; i < l->count; i++) listPush(r, l->items[i]);
  *out = OBJ_VAL(r); return true;
}

static bool sortCompare(Value cmp, Value a, Value b, int* r) {
  if (IS_NIL(cmp)) {
    if (IS_NUM(a) && IS_NUM(b)) { *r = AS_NUM(a) < AS_NUM(b) ? -1 : AS_NUM(a) > AS_NUM(b) ? 1 : 0; return true; }
    if (IS_STRING(a) && IS_STRING(b)) { int c = strcmp(AS_CSTRING(a), AS_CSTRING(b)); *r = c < 0 ? -1 : c > 0 ? 1 : 0; return true; }
    return throwError("sort() can't compare %s with %s (pass a comparison function)", typeName(a), typeName(b));
  }
  Value av[2] = {a, b}, res;
  if (!vmCall(cmp, 2, av, &res)) return false;
  if (!IS_NUM(res)) return throwError("sort() comparison function must return a number");
  *r = AS_NUM(res) < 0 ? -1 : AS_NUM(res) > 0 ? 1 : 0;
  return true;
}

static bool mergeSort(Value* a, Value* tmp, int n, Value cmp) {
  if (n < 2) return true;
  int mid = n / 2;
  if (!mergeSort(a, tmp, mid, cmp) || !mergeSort(a + mid, tmp, n - mid, cmp)) return false;
  int i = 0, j = mid, k = 0;
  while (i < mid && j < n) {
    int r;
    if (!sortCompare(cmp, a[j], a[i], &r)) return false;
    tmp[k++] = r < 0 ? a[j++] : a[i++];
  }
  while (i < mid) tmp[k++] = a[i++];
  while (j < n) tmp[k++] = a[j++];
  memcpy(a, tmp, sizeof(Value) * (size_t)n);
  return true;
}

NATIVE(l_sort) {
  ObjList* l = AS_LIST(args[0]);
  Value cmp = NIL_VAL;
  if (argc > 1) { if (!argFn("sort", args[1])) return false; cmp = args[1]; }
  Value* tmp = malloc(sizeof(Value) * (size_t)(l->count + 1));
  vm.gcPause++;
  bool ok = mergeSort(l->items, tmp, l->count, cmp);
  vm.gcPause--;
  free(tmp);
  if (!ok) return false;
  *out = args[0]; return true;
}

NATIVE(l_map) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  if (!argFn("map", args[1])) return false;
  ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = 0; i < l->count; i++) {
    Value item = l->items[i], res;
    if (!vmCall(args[1], 1, &item, &res)) return false;
    listPush(r, res);
  }
  pop();
  *out = OBJ_VAL(r); return true;
}
NATIVE(l_filter) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  if (!argFn("filter", args[1])) return false;
  ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = 0; i < l->count; i++) {
    Value item = l->items[i], res;
    if (!vmCall(args[1], 1, &item, &res)) return false;
    if (!isFalsey(res)) listPush(r, item);
  }
  pop();
  *out = OBJ_VAL(r); return true;
}
NATIVE(l_each) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  if (!argFn("each", args[1])) return false;
  for (int i = 0; i < l->count; i++) { Value item = l->items[i], res; if (!vmCall(args[1], 1, &item, &res)) return false; }
  *out = NIL_VAL; return true;
}
NATIVE(l_reduce) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  if (!argFn("reduce", args[2])) return false;
  Value acc = args[1];
  push(acc);
  for (int i = 0; i < l->count; i++) {
    Value av[2] = { acc, l->items[i] }, res;
    if (!vmCall(args[2], 2, av, &res)) return false;
    acc = res;
    vm.stackTop[-1] = acc;
  }
  pop();
  *out = acc; return true;
}


static bool listArg(const char* fn, Value v) {
  if (!IS_LIST(v)) return throwError("%s() expects a list, got %s", fn, typeName(v));
  return true;
}
NATIVE(l_first) { (void)argc; ObjList* l = AS_LIST(args[0]); *out = l->count ? l->items[0] : NIL_VAL; return true; }
NATIVE(l_last) { (void)argc; ObjList* l = AS_LIST(args[0]); *out = l->count ? l->items[l->count - 1] : NIL_VAL; return true; }
NATIVE(l_is_empty) { (void)argc; *out = BOOL_VAL(AS_LIST(args[0])->count == 0); return true; }
NATIVE(l_sum) {
  (void)argc; if (!listArg("sum", args[0])) return false;
  ObjList* l = AS_LIST(args[0]); double t = 0;
  for (int i = 0; i < l->count; i++) {
    if (!IS_NUM(l->items[i])) return throwError("sum() needs a list of numbers, found %s", typeName(l->items[i]));
    t += AS_NUM(l->items[i]);
  }
  *out = NUM_VAL(t); return true;
}
NATIVE(l_min) { (void)argc; return extreme("min", 1, args, false, out); }
NATIVE(l_max) { (void)argc; return extreme("max", 1, args, true, out); }
NATIVE(l_any) {
  if (!listArg("any", args[0])) return false;
  ObjList* l = AS_LIST(args[0]);
  if (argc > 1 && !argFn("any", args[1])) return false;
  for (int i = 0; i < l->count; i++) {
    Value v = l->items[i];
    if (argc > 1) { Value item = v; if (!vmCall(args[1], 1, &item, &v)) return false; }
    if (!isFalsey(v)) { *out = BOOL_VAL(true); return true; }
  }
  *out = BOOL_VAL(false); return true;
}
NATIVE(l_all) {
  if (!listArg("all", args[0])) return false;
  ObjList* l = AS_LIST(args[0]);
  if (argc > 1 && !argFn("all", args[1])) return false;
  for (int i = 0; i < l->count; i++) {
    Value v = l->items[i];
    if (argc > 1) { Value item = v; if (!vmCall(args[1], 1, &item, &v)) return false; }
    if (isFalsey(v)) { *out = BOOL_VAL(false); return true; }
  }
  *out = BOOL_VAL(true); return true;
}
NATIVE(l_find) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  if (!argFn("find", args[1])) return false;
  for (int i = 0; i < l->count; i++) {
    Value item = l->items[i], res;
    if (!vmCall(args[1], 1, &item, &res)) return false;
    if (!isFalsey(res)) { *out = item; return true; }
  }
  *out = NIL_VAL; return true;
}
NATIVE(l_count) {
  (void)argc; ObjList* l = AS_LIST(args[0]); int c = 0;
  if (IS_CALLABLE(args[1])) {
    for (int i = 0; i < l->count; i++) {
      Value item = l->items[i], res;
      if (!vmCall(args[1], 1, &item, &res)) return false;
      if (!isFalsey(res)) c++;
    }
  } else for (int i = 0; i < l->count; i++) if (valuesEqual(l->items[i], args[1])) c++;
  *out = NUM_VAL(c); return true;
}
NATIVE(l_extend) {
  (void)argc; ObjList* l = AS_LIST(args[0]);
  if (!listArg("extend", args[1])) return false;
  ObjList* o = AS_LIST(args[1]);
  int n = o->count;   /* l.extend(l) must not loop forever */
  for (int i = 0; i < n; i++) listPush(l, o->items[i]);
  *out = args[0]; return true;
}
NATIVE(l_unique) {
  (void)argc; if (!listArg("unique", args[0])) return false;
  ObjList* l = AS_LIST(args[0]); ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = 0; i < l->count; i++) {
    bool seen = false;
    for (int j = 0; j < r->count && !seen; j++) seen = valuesEqual(r->items[j], l->items[i]);
    if (!seen) listPush(r, l->items[i]);
  }
  pop();
  *out = OBJ_VAL(r); return true;
}
NATIVE(l_flatten) {
  (void)argc; if (!listArg("flatten", args[0])) return false;
  ObjList* l = AS_LIST(args[0]); ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = 0; i < l->count; i++) {
    if (IS_LIST(l->items[i])) { ObjList* in = AS_LIST(l->items[i]); for (int j = 0; j < in->count; j++) listPush(r, in->items[j]); }
    else listPush(r, l->items[i]);
  }
  pop();
  *out = OBJ_VAL(r); return true;
}
NATIVE(l_sorted) {
  if (!listArg("sorted", args[0])) return false;
  ObjList* l = AS_LIST(args[0]); ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = 0; i < l->count; i++) listPush(r, l->items[i]);
  Value sargs[2] = { OBJ_VAL(r), argc > 1 ? args[1] : NIL_VAL };
  bool ok = l_sort(argc > 1 ? 2 : 1, sargs, out);
  pop();
  if (ok) *out = OBJ_VAL(r);
  return ok;
}
NATIVE(l_reversed) {
  (void)argc; if (!listArg("reversed", args[0])) return false;
  ObjList* l = AS_LIST(args[0]); ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = l->count - 1; i >= 0; i--) listPush(r, l->items[i]);
  pop();
  *out = OBJ_VAL(r); return true;
}
NATIVE(g_zip) {
  (void)argc; if (!listArg("zip", args[0]) || !listArg("zip", args[1])) return false;
  ObjList* a = AS_LIST(args[0]); ObjList* b = AS_LIST(args[1]); ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = 0; i < a->count && i < b->count; i++) {
    ObjList* p = newList(); push(OBJ_VAL(p));
    listPush(p, a->items[i]); listPush(p, b->items[i]);
    pop(); listPush(r, OBJ_VAL(p));
  }
  pop();
  *out = OBJ_VAL(r); return true;
}
NATIVE(g_enumerate) {
  (void)argc; if (!listArg("enumerate", args[0])) return false;
  ObjList* a = AS_LIST(args[0]); ObjList* r = newList();
  push(OBJ_VAL(r));
  for (int i = 0; i < a->count; i++) {
    ObjList* p = newList(); push(OBJ_VAL(p));
    listPush(p, NUM_VAL(i)); listPush(p, a->items[i]);
    pop(); listPush(r, OBJ_VAL(p));
  }
  pop();
  *out = OBJ_VAL(r); return true;
}
NATIVE(g_bool) { (void)argc; *out = BOOL_VAL(!isFalsey(args[0])); return true; }

const MethodDef listMethods[] = {
  {"len", l_len, 0, 0}, {"push", l_push, 1, 1}, {"pop", l_pop, 0, 0}, {"insert", l_insert, 2, 2},
  {"remove", l_remove, 1, 1}, {"clear", l_clear, 0, 0}, {"contains", l_contains, 1, 1}, {"index_of", l_index_of, 1, 1},
  {"join", l_join, 0, 1}, {"reverse", l_reverse, 0, 0}, {"sort", l_sort, 0, 1}, {"slice", l_slice, 0, 2},
  {"copy", l_copy, 0, 0}, {"map", l_map, 1, 1}, {"filter", l_filter, 1, 1}, {"each", l_each, 1, 1},
  {"reduce", l_reduce, 2, 2},
  {"first", l_first, 0, 0}, {"last", l_last, 0, 0}, {"is_empty", l_is_empty, 0, 0}, {"sum", l_sum, 0, 0},
  {"min", l_min, 0, 0}, {"max", l_max, 0, 0}, {"any", l_any, 0, 1}, {"all", l_all, 0, 1}, {"find", l_find, 1, 1},
  {"count", l_count, 1, 1}, {"extend", l_extend, 1, 1}, {"unique", l_unique, 0, 0}, {"flatten", l_flatten, 0, 0},
  {"sorted", l_sorted, 0, 1}, {"reversed", l_reversed, 0, 0}, {NULL, NULL, 0, 0}
};

/* --------------------------------------------------------------- map methods */

NATIVE(mp_len) { (void)argc; *out = NUM_VAL(AS_MAP(args[0])->map.live); return true; }
NATIVE(mp_keys) {
  (void)argc; Map* m = &AS_MAP(args[0])->map; ObjList* l = newList();
  for (int i = 0; i < m->count; i++) if (m->entries[i].live) listPush(l, m->entries[i].key);
  *out = OBJ_VAL(l); return true;
}
NATIVE(mp_values) {
  (void)argc; Map* m = &AS_MAP(args[0])->map; ObjList* l = newList();
  for (int i = 0; i < m->count; i++) if (m->entries[i].live) listPush(l, m->entries[i].value);
  *out = OBJ_VAL(l); return true;
}
NATIVE(mp_items) {
  (void)argc; Map* m = &AS_MAP(args[0])->map; ObjList* l = newList();
  push(OBJ_VAL(l));
  for (int i = 0; i < m->count; i++) {
    if (!m->entries[i].live) continue;
    ObjList* pair = newList();
    listPush(pair, m->entries[i].key); listPush(pair, m->entries[i].value);
    listPush(l, OBJ_VAL(pair));
  }
  pop();
  *out = OBJ_VAL(l); return true;
}
NATIVE(mp_has) {
  (void)argc; Value d;
  *out = BOOL_VAL(validKey(args[1]) && mapGet(&AS_MAP(args[0])->map, args[1], &d)); return true;
}
NATIVE(mp_get) {
  Value v;
  if (validKey(args[1]) && mapGet(&AS_MAP(args[0])->map, args[1], &v)) *out = v;
  else *out = argc > 2 ? args[2] : NIL_VAL;
  return true;
}
NATIVE(mp_remove) {
  (void)argc; Value v;
  if (validKey(args[1]) && mapGet(&AS_MAP(args[0])->map, args[1], &v)) { mapDelete(&AS_MAP(args[0])->map, args[1]); *out = v; }
  else *out = NIL_VAL;
  return true;
}
NATIVE(mp_clear) {
  (void)argc; Map* m = &AS_MAP(args[0])->map;
  mapFree(m);
  *out = args[0]; return true;
}
NATIVE(mp_copy) {
  (void)argc; Map* m = &AS_MAP(args[0])->map; ObjMap* r = newMap();
  for (int i = 0; i < m->count; i++) if (m->entries[i].live) mapSet(&r->map, m->entries[i].key, m->entries[i].value);
  *out = OBJ_VAL(r); return true;
}


NATIVE(mp_is_empty) { (void)argc; *out = BOOL_VAL(AS_MAP(args[0])->map.live == 0); return true; }
NATIVE(mp_merge) {
  (void)argc; ObjMap* m = AS_MAP(args[0]);
  if (!IS_MAP(args[1])) return throwError("merge() expects a map, got %s", typeName(args[1]));
  ObjMap* o = AS_MAP(args[1]);
  if (o == m) { *out = args[0]; return true; }
  int n = o->map.count;
  for (int i = 0; i < n && i < o->map.count; i++) {
    Entry* e = &o->map.entries[i];
    if (e->live) mapSet(&m->map, e->key, e->value);
  }
  *out = args[0]; return true;
}

const MethodDef mapMethods[] = {
  {"len", mp_len, 0, 0}, {"keys", mp_keys, 0, 0}, {"values", mp_values, 0, 0}, {"items", mp_items, 0, 0},
  {"has", mp_has, 1, 1}, {"get", mp_get, 1, 2}, {"remove", mp_remove, 1, 1}, {"clear", mp_clear, 0, 0},
  {"copy", mp_copy, 0, 0}, {"is_empty", mp_is_empty, 0, 0}, {"merge", mp_merge, 1, 1}, {NULL, NULL, 0, 0}
};

NATIVE(r_len) { (void)argc; *out = NUM_VAL(rangeLength(AS_RANGE(args[0]))); return true; }
NATIVE(r_to_list) {
  (void)argc; ObjRange* r = AS_RANGE(args[0]);
  int n = rangeLength(r);
  if (n > 10000000 || (vm.maxMemory && (size_t)n * sizeof(Value) > vm.maxMemory / 4)) return throwError("Range is too large to turn into a list");
  ObjList* l = newList();
  for (int i = 0; i < n; i++) listPush(l, NUM_VAL(r->start + i * r->step));
  *out = OBJ_VAL(l); return true;
}
const MethodDef rangeMethods[] = { {"len", r_len, 0, 0}, {"to_list", r_to_list, 0, 0}, {NULL, NULL, 0, 0} };

/* ------------------------------------------------------------- registration */

static ObjMap* namespaceMap(const char* name) {
  ObjMap* m = newMap();
  defineValue(&vm.builtins, name, OBJ_VAL(m));
  return m;
}

void registerBuiltins(void) {
  Map* g = &vm.builtins;
  rngState ^= (uint64_t)(nowSeconds() * 1e6) * 0x9E3779B97F4A7C15ULL;
  if (!rngState) rngState = 1;

  defineNative(g, "print", n_print, 0, -1);
  defineNative(g, "write", n_write, 0, -1);
  defineNative(g, "len", n_len, 1, 1);
  defineNative(g, "str", n_str, 1, 1);
  defineNative(g, "repr", n_repr, 1, 1);
  defineNative(g, "num", n_num, 1, 1);
  defineNative(g, "int", n_int, 1, 1);
  defineNative(g, "type", n_type, 1, 1);
  defineNative(g, "range", n_range, 1, 3);
  defineNative(g, "assert", n_assert, 1, 2);
  defineNative(g, "load", n_load, 1, 1);
  defineNative(g, "isinstance", n_isinstance, 2, 2);
  defineNative(g, "__check", n_check, 3, 3);
  defineNative(g, "ord", n_ord, 1, 1);
  defineNative(g, "chr", n_chr, 1, 1);
  defineNative(g, "bool", g_bool, 1, 1);
  defineNative(g, "from_bytes", g_from_bytes, 1, 1);
  defineNative(g, "sum", l_sum, 1, 1);
  defineNative(g, "any", l_any, 1, 2);
  defineNative(g, "all", l_all, 1, 2);
  defineNative(g, "sorted", l_sorted, 1, 2);
  defineNative(g, "reversed", l_reversed, 1, 1);
  defineNative(g, "zip", g_zip, 2, 2);
  defineNative(g, "enumerate", g_enumerate, 1, 1);
  registerCoroutineBuiltins(g);
  defineNative(g, "abs", m_abs, 1, 1);
  defineNative(g, "floor", m_floor, 1, 1);
  defineNative(g, "ceil", m_ceil, 1, 1);
  defineNative(g, "round", m_round, 1, 1);
  defineNative(g, "sqrt", m_sqrt, 1, 1);
  defineNative(g, "min", m_min, 1, -1);
  defineNative(g, "max", m_max, 1, -1);

  defineNative(g, "forward", g_forward, 1, 1);
  defineNative(g, "back", g_back, 1, 1);
  defineNative(g, "turn", g_turn, 1, 1);
  defineNative(g, "penup", g_penup, 0, 0);
  defineNative(g, "pendown", g_pendown, 0, 0);
  defineNative(g, "goto", g_goto, 2, 2);
  defineNative(g, "home", g_home, 0, 0);
  defineNative(g, "width", g_width, 1, 1);
  defineNative(g, "color", g_color, 1, 3);
  defineNative(g, "background", g_background, 1, 1);
  defineNative(g, "circle", g_circle, 1, 1);
  defineNative(g, "disc", g_disc, 1, 1);
  defineNative(g, "rect", g_rect, 2, 2);
  defineNative(g, "box", g_box, 2, 2);
  defineNative(g, "text", g_text, 1, 2);

  ObjMap* math = namespaceMap("math");
  Map* m = &math->map;
  defineValue(m, "pi", NUM_VAL(M_PI)); defineValue(m, "e", NUM_VAL(M_E));
  defineValue(m, "inf", NUM_VAL(INFINITY)); defineValue(m, "nan", NUM_VAL(NAN));
  defineNative(m, "sqrt", m_sqrt, 1, 1); defineNative(m, "pow", m_pow, 2, 2);
  defineNative(m, "sin", m_sin, 1, 1); defineNative(m, "cos", m_cos, 1, 1); defineNative(m, "tan", m_tan, 1, 1);
  defineNative(m, "asin", m_asin, 1, 1); defineNative(m, "acos", m_acos, 1, 1); defineNative(m, "atan", m_atan, 1, 1);
  defineNative(m, "atan2", m_atan2, 2, 2); defineNative(m, "hypot", m_hypot, 2, 2);
  defineNative(m, "log", m_log, 1, 1); defineNative(m, "log2", m_log2, 1, 1); defineNative(m, "log10", m_log10, 1, 1);
  defineNative(m, "exp", m_exp, 1, 1);
  defineNative(m, "floor", m_floor, 1, 1); defineNative(m, "ceil", m_ceil, 1, 1); defineNative(m, "round", m_round, 1, 1);
  defineNative(m, "trunc", m_trunc, 1, 1); defineNative(m, "abs", m_abs, 1, 1); defineNative(m, "sign", m_sign, 1, 1);
  defineNative(m, "min", m_min, 1, -1); defineNative(m, "max", m_max, 1, -1); defineNative(m, "clamp", m_clamp, 3, 3);
  defineNative(m, "radians", m_radians, 1, 1); defineNative(m, "degrees", m_degrees, 1, 1);
  defineNative(m, "random", m_random, 0, 0); defineNative(m, "randint", m_randint, 2, 2); defineNative(m, "seed", m_seed, 1, 1);

  ObjMap* json = namespaceMap("json");
  defineNative(&json->map, "encode", j_encode, 1, 2);
  defineNative(&json->map, "decode", j_decode, 1, 1);

  ObjMap* time = namespaceMap("time");
  defineNative(&time->map, "now", t_now, 0, 0);
  defineNative(&time->map, "clock", t_clock, 0, 0);

  if (vm.sandbox) return;

  defineNative(g, "input", n_input, 0, 1);
  defineNative(g, "exit", n_exit, 0, 1);
  defineNative(g, "save_svg", g_save_svg, 1, 1);
  defineNative(&time->map, "sleep", t_sleep, 1, 1);

  ObjMap* os = namespaceMap("os");
  ObjList* argv = newList();
  for (int i = 0; i < vm.scriptArgc; i++) listPush(argv, strVal(vm.scriptArgv[i], (int)strlen(vm.scriptArgv[i])));
  defineValue(&os->map, "args", OBJ_VAL(argv));
  defineValue(&os->map, "platform", OBJ_VAL(cstring(FX_OS_NAME)));
  defineNative(&os->map, "env", os_env, 1, 1);
  defineNative(&os->map, "cwd", os_cwd, 0, 0);
  defineNative(&os->map, "stdin_read", os_stdin_read, 1, 1);
  defineNative(&os->map, "flush", os_flush, 0, 0);
  defineNative(&os->map, "run", os_run, 1, 1);
  defineNative(&os->map, "exit", n_exit, 0, 1);

  ObjMap* netns = namespaceMap("net");
  defineNative(&netns->map, "listen", net_listen, 1, 2);
  defineNative(&netns->map, "port", net_port, 1, 1);
  defineNative(&netns->map, "accept", net_accept, 1, 2);
  defineNative(&netns->map, "connect", net_connect, 2, 3);
  defineNative(&netns->map, "read", net_read, 1, 3);
  defineNative(&netns->map, "write", net_write, 2, 2);
  defineNative(&netns->map, "close", net_close, 1, 1);

  ObjMap* fs = namespaceMap("fs");
  defineNative(&fs->map, "read", fs_read, 1, 1);
  defineNative(&fs->map, "write", fs_write, 2, 2);
  defineNative(&fs->map, "append", fs_append, 2, 2);
  defineNative(&fs->map, "exists", fs_exists, 1, 1);
  defineNative(&fs->map, "is_dir", fs_is_dir, 1, 1);
  defineNative(&fs->map, "lines", fs_lines, 1, 1);
  defineNative(&fs->map, "list", fs_list, 1, 1);
  defineNative(&fs->map, "remove", fs_remove, 1, 1);
  defineNative(&fs->map, "mkdir", fs_mkdir, 1, 1);
}
