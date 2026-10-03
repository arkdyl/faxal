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
#include <unistd.h>
#include <limits.h>
#include <sys/stat.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

#define MAGIC "FAXALPK2"
#define MAX_BUNDLE (512u * 1024 * 1024)

static bool selfPath(char* out, size_t cap) {
#ifdef __APPLE__
  char tmp[PATH_MAX];
  uint32_t size = sizeof tmp;
  if (_NSGetExecutablePath(tmp, &size) != 0) return false;
  return realpath(tmp, out) != NULL;
#else
  ssize_t n = readlink("/proc/self/exe", out, cap - 1);
  if (n < 0) return false;
  out[n] = '\0';
  return true;
#endif
}

static uint32_t rd32(const unsigned char* p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void wr32(Buffer* b, uint32_t v) { char c[4] = { (char)v, (char)(v >> 8), (char)(v >> 16), (char)(v >> 24) }; bufAppend(b, c, 4); }

bool loadBundleFromSelf(void) {
  char path[PATH_MAX];
  if (!selfPath(path, sizeof path)) return false;
  FILE* f = fopen(path, "rb");
  if (!f) return false;
  unsigned char trailer[16];
  if (fseek(f, -16, SEEK_END) != 0 || fread(trailer, 1, 16, f) != 16 || memcmp(trailer, MAGIC, 8) != 0) { fclose(f); return false; }
  uint64_t len = 0;
  for (int i = 7; i >= 0; i--) len = (len << 8) | trailer[8 + i];
  if (len < 4 || len > MAX_BUNDLE || fseek(f, -(long)(16 + len), SEEK_END) != 0) { fclose(f); return false; }
  unsigned char* data = malloc((size_t)len);
  if (fread(data, 1, (size_t)len, f) != len) { free(data); fclose(f); return false; }
  fclose(f);

  size_t pos = 0;
  uint32_t count = rd32(data);
  pos = 4;
  if (count == 0 || count > 100000) { free(data); return false; }
  BundleFile* files = calloc(count, sizeof(BundleFile));
  for (uint32_t i = 0; i < count; i++) {
    if (pos + 4 > len) goto bad;
    uint32_t plen = rd32(data + pos); pos += 4;
    if (pos + plen + 5 > len) goto bad;
    files[i].path = strndup((char*)data + pos, plen); pos += plen;
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
  free(data);
  vm.bundle = files;
  vm.bundleCount = (int)count;
  return true;
bad:
  free(data);
  return false;
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
    if (access(probe, F_OK) == 0) { snprintf(rootDir, sizeof rootDir, "%s", dir); return; }
    if (strcmp(dir, "/") == 0) break;
    char parent[PATH_MAX];
    dirOf(dir, parent);
    snprintf(dir, sizeof dir, "%s", parent);
  }
  snprintf(rootDir, sizeof rootDir, "%s", start);
}

/* Reads one file, finds the files it imports (recursively) and records them all. */
static bool collect(const char* abs) {
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
      } else ok = collect(resolved);
    }
    free(imports[i]);
  }
  free(imports);
  pop();
  return ok;
}

int cmdBuild(int argc, char** argv, int first) {
  const char* mainPath = NULL;
  const char* outPath = NULL;
  for (int i = first; i < argc; i++) {
    if (!strcmp(argv[i], "-o") && i + 1 < argc) outPath = argv[++i];
    else if (!strcmp(argv[i], "--source")) buildBytecode = false;
    else if (!mainPath) mainPath = argv[i];
    else { fprintf(stderr, "faxal build: unexpected argument '%s'\n", argv[i]); return 64; }
  }
  if (!mainPath) { fputs("usage: faxal build <main.fx> [-o output]\n", stderr); return 64; }

  char mainAbs[PATH_MAX];
  if (!realpath(mainPath, mainAbs)) { fprintf(stderr, "faxal build: cannot open '%s'\n", mainPath); return 74; }
  findRoot(mainAbs);
  if (!collect(mainAbs)) return 65;

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
  fwrite(MAGIC, 1, 8, out);
  uint64_t len = (uint64_t)payload.len;
  unsigned char lenBytes[8];
  for (int i = 0; i < 8; i++) lenBytes[i] = (unsigned char)(len >> (8 * i));
  fwrite(lenBytes, 1, 8, out);
  fclose(out);
  free(exe);
  chmod(outPath, 0755);

  printf("built %s: %d file%s packed as %s, %.1f MB\n", outPath, fileCount, fileCount == 1 ? "" : "s", buildBytecode ? "bytecode" : "source", (double)(exeSize + payload.len + 16) / 1048576.0);
  bufFree(&payload);
  return 0;
}
