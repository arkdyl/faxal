/* bundle.c: `faxal build` makes a standalone executable; a built program finds its code inside itself.
 *
 * An executable made by `faxal build` is a copy of the faxal program with the Faxal source files of the
 * app appended to it, followed by a 16-byte trailer ("FAXALPK1" + the size of the appended data). When
 * faxal starts it looks at its own last 16 bytes: if they match, it runs the packed app instead of
 * behaving like the command-line tool.
 *
 * (On macOS the packed file keeps the original ad-hoc signature, which covers the original program bytes;
 * the appended data is never mapped into memory, so the system is happy to run it.)
 */
#include "faxal.h"

#define PACK_MAGIC "FAXALPK2"
#define MAX_BUNDLE (512u * 1024 * 1024)

static bool selfPath(char* out, size_t cap) { return fx_self_path(out, cap); }

static uint32_t rd32(const unsigned char* p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void wr32(Buffer* b, uint32_t v) { char c[4] = { (char)v, (char)(v >> 8), (char)(v >> 16), (char)(v >> 24) }; bufAppend(b, c, 4); }

/* Reads a packed program (see cmdBuild for the layout) into vm.bundle. */
static bool parsePayload(const unsigned char* data, size_t len) {
  size_t pos = 4;
  if (len < 4) return false;
  uint32_t count = rd32(data);
  if (count == 0 || count > 100000) return false;
  BundleFile* files = calloc(count, sizeof(BundleFile));
  for (uint32_t i = 0; i < count; i++) {
    if (pos + 4 > len) goto bad;
    uint32_t plen = rd32(data + pos); pos += 4;
    if (pos + plen + 5 > len) goto bad;
    files[i].path = strndup((const char*)data + pos, plen); pos += plen;
    if (pos + 5 > len) goto bad;
    files[i].isBytecode = data[pos] == 1; pos += 1;
    uint32_t slen = rd32(data + pos); pos += 4;
    if (pos + slen > len) goto bad;
    files[i].source = malloc((size_t)slen + 1);
    memcpy(files[i].source, data + pos, slen);
    files[i].source[slen] = '\0';
    files[i].length = slen;
    pos += slen;
  }
  vm.bundle = files;
  vm.bundleCount = (int)count;
  return true;
bad:
  for (uint32_t i = 0; i < count; i++) { free(files[i].path); free(files[i].source); }
  free(files);
  return false;
}

bool loadBundleFromSelf(void) {
#ifdef FAXAL_EMBEDDED_PROGRAM
  /* this is a program made by `faxal build --c`: its code is an array inside the C file itself */
  return parsePayload(faxalProgramData, (size_t)faxalProgramLength);
#else
  char path[PATH_MAX];
  if (!selfPath(path, sizeof path)) return false;
  FILE* f = fopen(path, "rb");
  if (!f) return false;
  unsigned char trailer[16];
  if (fseek(f, -16, SEEK_END) != 0 || fread(trailer, 1, 16, f) != 16 || memcmp(trailer, PACK_MAGIC, 8) != 0) { fclose(f); return false; }
  uint64_t len = 0;
  for (int i = 7; i >= 0; i--) len = (len << 8) | trailer[8 + i];
  if (len < 4 || len > MAX_BUNDLE || fseek(f, -(long)(16 + len), SEEK_END) != 0) { fclose(f); return false; }
  unsigned char* data = malloc((size_t)len);
  if (fread(data, 1, (size_t)len, f) != len) { free(data); fclose(f); return false; }
  fclose(f);
  bool ok = parsePayload(data, (size_t)len);
  free(data);
  return ok;
#endif
}

/* ---------------------------------------------------------------- faxal build */

typedef struct { char* abs; char* rel; char* source; char* data; size_t dataLength; bool isBytecode; } Collected;
static bool buildBytecode = true;
static Collected* files = NULL;
static int fileCount = 0;
static char rootDir[PATH_MAX];

static bool endsWith(const char* s, const char* suffix) {
  size_t a = strlen(s), b = strlen(suffix);
  return a >= b && strcmp(s + a - b, suffix) == 0;
}

static void dirOf(const char* path, char* out) {
  snprintf(out, PATH_MAX, "%s", path);
  char* slash = strrchr(out, '/');
  if (slash == out) out[1] = '\0';
  else if (slash) *slash = '\0';
}

static void findRoot(const char* mainAbs) {
  char dir[PATH_MAX], probe[PATH_MAX * 2];
  dirOf(mainAbs, dir);
  char start[PATH_MAX];
  snprintf(start, sizeof start, "%s", dir);
  for (int i = 0; i < 32; i++) {
    snprintf(probe, sizeof probe, "%s/faxal.json", dir);
    if (fx_exists(probe)) { snprintf(rootDir, sizeof rootDir, "%s", dir); return; }
    if (strcmp(dir, "/") == 0) break;
    char parent[PATH_MAX];
    dirOf(dir, parent);
    snprintf(dir, sizeof dir, "%s", parent);
  }
  snprintf(rootDir, sizeof rootDir, "%s", start);
}

/* Reads one file, finds the files it imports (recursively) and records them all. */
static bool collectModule(const char* abs) {
  for (int i = 0; i < fileCount; i++) if (strcmp(files[i].abs, abs) == 0) return true;

  size_t rootLen = strlen(rootDir);
  bool inside = strncmp(abs, rootDir, rootLen) == 0 && (abs[rootLen] == '/' || rootLen == 1);
  if (!inside) {
    fprintf(stderr, "faxal build: %s is outside the project folder (%s), so it can't be packed.\n", abs, rootDir);
    return false;
  }
  char* source = readFile(abs);
  if (!source) { fprintf(stderr, "faxal build: cannot read %s\n", abs); return false; }

  files = realloc(files, sizeof(Collected) * (size_t)(fileCount + 1));
  Collected* me = &files[fileCount++];
  me->abs = strdup(abs);
  me->rel = strdup(abs + rootLen + (rootLen == 1 ? 0 : 1));
  me->source = source;
  me->data = NULL;
  me->dataLength = 0;
  me->isBytecode = false;

  ObjModule* mod = newModule(cstring(abs));
  push(OBJ_VAL(mod));   /* the compiler runs on the VM and may trigger a garbage collection: keep `mod` alive */
  compileCollectImports = true;
  compiledImportCount = 0;
  ObjFunction* fn = compile(source, mod, NULL);
  compileCollectImports = false;
  if (!fn) { pop(); return false; }
  if (buildBytecode) {
    Buffer b;
    bufInit(&b);
    if (!bytecodeWrite(fn, me->rel, &b)) { bufFree(&b); fprintf(stderr, "faxal build: cannot turn %s into bytecode\n", abs); pop(); return false; }
    me->data = b.data;
    me->dataLength = (size_t)b.len;
    me->isBytecode = true;
  }

  int n = compiledImportCount;
  char** imports = compiledImports;
  compiledImports = NULL;
  compiledImportCount = 0;
  bool ok = true;
  for (int i = 0; i < n && ok; i++) {
    if (strncmp(imports[i], "std/", 4) != 0) {
      char resolved[PATH_MAX];
      if (!resolveImport(imports[i], mod, resolved)) {
        fprintf(stderr, "faxal build: cannot find module '%s' (imported by %s)\n", imports[i], abs);
        ok = false;
      } else ok = collectModule(resolved);
    }
    free(imports[i]);
  }
  free(imports);
  pop();
  return ok;
}

/* ------------------------------------------------- faxal build --c / --native
 * Writes the program as ONE C file: the program's bytecode as an array, followed by the whole runtime
 * (dist/faxal.c). Any C compiler turns that file into a native executable, and the machine that compiles
 * it needs no faxal at all. --native also runs the C compiler. */

static char* findRuntimeSource(size_t* len) {
  char self[PATH_MAX], candidate[PATH_MAX * 2];
  const char* env = getenv("FAXAL_RUNTIME");
  if (env) { char* t = (char*)readFileBytes(env, len); if (t) return t; }
  if (selfPath(self, sizeof self)) {
    char dir[PATH_MAX];
    dirOf(self, dir);
    static const char* where[] = { "%s/../share/faxal/faxal.c", "%s/../dist/faxal.c", "%s/faxal.c" };
    for (int i = 0; i < 3; i++) {
      snprintf(candidate, sizeof candidate, where[i], dir);
      char* t = (char*)readFileBytes(candidate, len);
      if (t) return t;
    }
  }
  return NULL;
}

static int buildC(Buffer* payload, const char* outPath, bool compile) {
  size_t runtimeLen = 0;
  char* runtime = findRuntimeSource(&runtimeLen);
  if (!runtime) {
    fputs("faxal build: the single-file runtime (faxal.c) was not found.\n"
          "  Run `make amalgam` in the faxal source tree, or set FAXAL_RUNTIME=/path/to/faxal.c\n", stderr);
    return 70;
  }
  char cPath[PATH_MAX], exePath[PATH_MAX];
  if (!outPath) outPath = compile ? "a.out" : "program.c";
  if (compile) {
    snprintf(exePath, sizeof exePath, "%s", outPath);
    snprintf(cPath, sizeof cPath, "%s.c", outPath);
  } else {
    snprintf(cPath, sizeof cPath, "%s", outPath);
  }
  FILE* out = fopen(cPath, "wb");
  if (!out) { fprintf(stderr, "faxal build: cannot write '%s'\n", cPath); free(runtime); return 74; }
  fputs("/* A Faxal program as one C file, made by `faxal build --c`.\n"
        " * Build it with any C compiler:   cc -O2 -o program program.c -lm\n"
        " * The array below is the program's bytecode; everything after it is the Faxal runtime. */\n"
        "#define FAXAL_EMBEDDED_PROGRAM 1\n"
        "static const unsigned char faxalProgramData[] = {", out);
  for (int i = 0; i < payload->len; i++) fprintf(out, "%s%u,", i % 24 == 0 ? "\n" : "", (unsigned)(unsigned char)payload->data[i]);
  fprintf(out, "\n};\nstatic const unsigned long long faxalProgramLength = %dULL;\n\n", payload->len);
  fwrite(runtime, 1, runtimeLen, out);
  fclose(out);
  free(runtime);
  if (!compile) {
    printf("wrote %s: the program and the runtime in one C file (build it with: cc -O2 -o program %s -lm)\n", cPath, cPath);
    return 0;
  }
  const char* cc = getenv("CC");
  static const char* tries[] = { "cc", "gcc", "clang" };
  char command[PATH_MAX * 4];
  for (int i = cc ? -1 : 0; i < 3; i++) {
    const char* compiler = i < 0 ? cc : tries[i];
    #ifdef FX_WINDOWS
    snprintf(command, sizeof command, "%s -O2 -o \"%s\" \"%s\" -lws2_32", compiler, exePath, cPath);
#else
    snprintf(command, sizeof command, "%s -O2 -o \"%s\" \"%s\" -lm", compiler, exePath, cPath);
#endif
    FILE* p = fx_popen(command);
    if (!p) continue;
    char line[512]; Buffer msgs; bufInit(&msgs);
    while (fgets(line, sizeof line, p)) bufStr(&msgs, line);
    int code = fx_pclose(p);
    if (code == 0) {
      remove(cPath);
      printf("built %s with %s: a native executable (no faxal needed to run it)\n", exePath, compiler);
      bufFree(&msgs);
      return 0;
    }
    if (i == 2 || (cc && i < 0 && code != 127)) { fputs(msgs.data ? msgs.data : "", stderr); bufFree(&msgs); break; }
    bufFree(&msgs);
  }
  fprintf(stderr, "faxal build: no working C compiler found (tried CC, cc, gcc, clang). The C file is %s\n", cPath);
  return 70;
}

int cmdBuild(int argc, char** argv, int first) {
  const char* mainPath = NULL;
  const char* outPath = NULL;
  bool emitC = false, nativeBuild = false;
  for (int i = first; i < argc; i++) {
    if (!strcmp(argv[i], "-o") && i + 1 < argc) outPath = argv[++i];
    else if (!strcmp(argv[i], "--source")) buildBytecode = false;
    else if (!strcmp(argv[i], "--c")) emitC = true;
    else if (!strcmp(argv[i], "--native")) nativeBuild = true;
    else if (!mainPath) mainPath = argv[i];
    else { fprintf(stderr, "faxal build: unexpected argument '%s'\n", argv[i]); return 64; }
  }
  if (!mainPath) { fputs("usage: faxal build <main.fx> [-o output] [--c | --native]\n", stderr); return 64; }

  char mainAbs[PATH_MAX];
  if (!fx_realpath(mainPath, mainAbs)) { fprintf(stderr, "faxal build: cannot open '%s'\n", mainPath); return 74; }
  findRoot(mainAbs);
  if (!collectModule(mainAbs)) return 65;

  char defaultOut[PATH_MAX];
  if (!outPath) {
    const char* base = strrchr(mainPath, '/');
    base = base ? base + 1 : mainPath;
    snprintf(defaultOut, sizeof defaultOut, "%s", base);
    if (endsWith(defaultOut, ".fx")) defaultOut[strlen(defaultOut) - 3] = '\0';
    if (strcmp(defaultOut, base) == 0) strcat(defaultOut, "-app");
    outPath = defaultOut;
  }

  Buffer payload;
  bufInit(&payload);
  wr32(&payload, (uint32_t)fileCount);
  for (int i = 0; i < fileCount; i++) {
    wr32(&payload, (uint32_t)strlen(files[i].rel)); bufStr(&payload, files[i].rel);
    bufChar(&payload, files[i].isBytecode ? 1 : 0);
    if (files[i].isBytecode) { wr32(&payload, (uint32_t)files[i].dataLength); bufAppend(&payload, files[i].data, (int)files[i].dataLength); }
    else { wr32(&payload, (uint32_t)strlen(files[i].source)); bufStr(&payload, files[i].source); }
  }

  if (emitC || nativeBuild) { int r = buildC(&payload, outPath, nativeBuild); bufFree(&payload); return r; }

  char self[PATH_MAX];
  if (!selfPath(self, sizeof self)) { fputs("faxal build: cannot find the faxal program itself\n", stderr); return 70; }
  char* exe = NULL;
  FILE* in = fopen(self, "rb");
  if (!in) { fputs("faxal build: cannot read the faxal program\n", stderr); return 70; }
  fseek(in, 0, SEEK_END);
  long exeSize = ftell(in);
  rewind(in);
  exe = malloc((size_t)exeSize);
  if (fread(exe, 1, (size_t)exeSize, in) != (size_t)exeSize) { fclose(in); free(exe); return 70; }
  fclose(in);

  FILE* out = fopen(outPath, "wb");
  if (!out) { fprintf(stderr, "faxal build: cannot write '%s'\n", outPath); free(exe); return 74; }
  fwrite(exe, 1, (size_t)exeSize, out);
  fwrite(payload.data, 1, (size_t)payload.len, out);
  fwrite(PACK_MAGIC, 1, 8, out);
  uint64_t len = (uint64_t)payload.len;
  unsigned char lenBytes[8];
  for (int i = 0; i < 8; i++) lenBytes[i] = (unsigned char)(len >> (8 * i));
  fwrite(lenBytes, 1, 8, out);
  fclose(out);
  free(exe);
  fx_make_executable(outPath);

  printf("built %s: %d file%s packed as %s, %.1f MB\n", outPath, fileCount, fileCount == 1 ? "" : "s", buildBytecode ? "bytecode" : "source", (double)(exeSize + payload.len + 16) / 1048576.0);
  bufFree(&payload);
  return 0;
}
