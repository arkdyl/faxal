/* platform.h: everything that differs between Linux, macOS and Windows lives here.
 *
 * The rest of the runtime calls the fx_* functions below and never touches an operating-system header
 * directly, so a new platform means adding one more branch to this file. This file must be the first
 * thing included (faxal.h does that): the feature-test macros only work before any system header.
 *
 * Windows support targets MinGW-w64 (gcc/clang) and MSVC; paths are converted to forward slashes so the
 * rest of the code can treat every path the same way. */
#ifndef FAXAL_PLATFORM_H
#define FAXAL_PLATFORM_H

#if defined(_WIN32)
  #define FX_WINDOWS 1
  #define FX_OS_NAME "windows"
  #ifndef _CRT_SECURE_NO_WARNINGS
  #define _CRT_SECURE_NO_WARNINGS 1
  #endif
  #ifndef _USE_MATH_DEFINES
  #define _USE_MATH_DEFINES 1
  #endif
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN 1
  #endif
  #ifndef NOMINMAX
  #define NOMINMAX 1
  #endif
#else
  #if !defined(__APPLE__) && !defined(_GNU_SOURCE)
  #define _GNU_SOURCE 1          /* glibc and musl: expose popen, realpath, strdup, nanosleep, DT_* ... */
  #endif
  #ifdef __APPLE__
    #define FX_OS_NAME "macos"
  #elif defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
    #define FX_OS_NAME "bsd"
  #else
    #define FX_OS_NAME "linux"
  #endif
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <time.h>

#ifdef FX_WINDOWS
  #include <windows.h>
  #include <io.h>
  #include <direct.h>
  #include <fcntl.h>
  #include <sys/types.h>
  #include <sys/stat.h>
  #ifndef PATH_MAX
  #define PATH_MAX 4096
  #endif
  #ifndef S_ISDIR
  #define S_ISDIR(m) (((m) & _S_IFMT) == _S_IFDIR)
  #endif
  #ifndef S_ISREG
  #define S_ISREG(m) (((m) & _S_IFMT) == _S_IFREG)
  #endif
  #ifndef strdup
  #define strdup _strdup
  #endif
  /* MinGW and MSVC have no strndup */
  static inline char* fx_strndup(const char* s, size_t n) {
    size_t len = 0;
    while (len < n && s[len]) len++;
    char* r = (char*)malloc(len + 1);
    if (r) { memcpy(r, s, len); r[len] = '\0'; }
    return r;
  }
  #define strndup fx_strndup
#else
  #include <unistd.h>
  #include <dirent.h>
  #include <sys/stat.h>
  #include <sys/time.h>
  #include <sys/wait.h>
  #ifdef __APPLE__
    #include <mach-o/dyld.h>
  #endif
#endif

#define FX_PATH_SEP '/'

/* Rewrites backslashes as forward slashes (Windows only; a no-op elsewhere). */
static inline void fx_slashes(char* p) {
#ifdef FX_WINDOWS
  for (; *p; p++) if (*p == '\\') *p = '/';
#else
  (void)p;
#endif
}

/* Is a terminal attached to this standard stream (0 = stdin, 1 = stdout, 2 = stderr)? */
static inline bool fx_isatty(int fd) {
#ifdef FX_WINDOWS
  return _isatty(fd) != 0;
#else
  return isatty(fd) != 0;
#endif
}

/* Makes standard input/output byte-exact (Windows would otherwise turn \n into \r\n and stop at ^Z). */
static inline void fx_binary_stdio(void) {
#ifdef FX_WINDOWS
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stderr), _O_BINARY);
#endif
}

/* The absolute, symlink-free form of a path (forward slashes). false if the path doesn't exist. */
static inline bool fx_realpath(const char* path, char* out) {
#ifdef FX_WINDOWS
  if (!_fullpath(out, path, PATH_MAX)) return false;
  fx_slashes(out);
  return _access(out, 0) == 0;
#else
  return realpath(path, out) != NULL;
#endif
}

static inline bool fx_exists(const char* path) {
#ifdef FX_WINDOWS
  return _access(path, 0) == 0;
#else
  return access(path, F_OK) == 0;
#endif
}

static inline bool fx_is_dir(const char* path) {
  struct stat st;
  return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static inline bool fx_is_file(const char* path) {
  struct stat st;
  return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* Creates a directory; true also when it already exists. errno is set on failure. */
static inline bool fx_mkdir(const char* path) {
#ifdef FX_WINDOWS
  int r = _mkdir(path);
#else
  int r = mkdir(path, 0777);
#endif
  return r == 0 || errno == EEXIST;
}

static inline bool fx_getcwd(char* buf, size_t cap) {
#ifdef FX_WINDOWS
  if (!_getcwd(buf, (int)cap)) return false;
  fx_slashes(buf);
  return true;
#else
  return getcwd(buf, cap) != NULL;
#endif
}

/* Marks a file as runnable (no-op on Windows, where .exe is what makes a program runnable). */
static inline void fx_make_executable(const char* path) {
#ifdef FX_WINDOWS
  (void)path;
#else
  chmod(path, 0755);
#endif
}

/* Seconds since 1970-01-01 UTC, with microsecond resolution. */
static inline double fx_now(void) {
#ifdef FX_WINDOWS
  FILETIME ft; GetSystemTimeAsFileTime(&ft);
  uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;   /* 100 ns units since 1601 */
  return (double)(t - 116444736000000000ULL) / 1e7;
#else
  struct timeval tv; gettimeofday(&tv, NULL);
  return (double)tv.tv_sec + tv.tv_usec / 1e6;
#endif
}

static inline void fx_sleep(double seconds) {
  if (seconds <= 0) return;
#ifdef FX_WINDOWS
  Sleep((DWORD)(seconds * 1000.0));
#else
  struct timespec ts = { (time_t)seconds, (long)((seconds - (double)(time_t)seconds) * 1e9) };
  nanosleep(&ts, NULL);
#endif
}

/* Runs a shell command and returns its output stream; fx_pclose gives the exit code (or -1). */
static inline FILE* fx_popen(const char* command) {
#ifdef FX_WINDOWS
  return _popen(command, "rb");
#else
  return popen(command, "r");
#endif
}

static inline int fx_pclose(FILE* p) {
#ifdef FX_WINDOWS
  return _pclose(p);
#else
  int status = pclose(p);
  return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
#endif
}

/* The path of the running executable (forward slashes). */
static inline bool fx_self_path(char* out, size_t cap) {
#if defined(FX_WINDOWS)
  DWORD n = GetModuleFileNameA(NULL, out, (DWORD)cap);
  if (n == 0 || n >= cap) return false;
  fx_slashes(out);
  return true;
#elif defined(__APPLE__)
  char tmp[PATH_MAX]; uint32_t size = sizeof tmp;
  if (_NSGetExecutablePath(tmp, &size) != 0) return false;
  return realpath(tmp, out) != NULL;
#else
  ssize_t n = readlink("/proc/self/exe", out, cap - 1);
  if (n < 0) return false;
  out[n] = '\0';
  return true;
#endif
}

/* Lists the names inside a directory (without . and ..). Returns a malloc'd array of malloc'd names,
   or NULL with errno set when the directory can't be opened. *count is set on success. */
static inline char** fx_list_dir(const char* path, int* count) {
  char** names = NULL; int n = 0, cap = 0;
#ifdef FX_WINDOWS
  char pattern[PATH_MAX + 4];
  snprintf(pattern, sizeof pattern, "%s\\*", path);
  WIN32_FIND_DATAA data;
  HANDLE h = FindFirstFileA(pattern, &data);
  if (h == INVALID_HANDLE_VALUE) { errno = ENOENT; return NULL; }
  do {
    if (!strcmp(data.cFileName, ".") || !strcmp(data.cFileName, "..")) continue;
    if (n == cap) { cap = cap ? cap * 2 : 16; names = (char**)realloc(names, sizeof(char*) * (size_t)cap); }
    names[n++] = strdup(data.cFileName);
  } while (FindNextFileA(h, &data));
  FindClose(h);
#else
  DIR* d = opendir(path);
  if (!d) return NULL;
  struct dirent* e;
  while ((e = readdir(d))) {
    if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
    if (n == cap) { cap = cap ? cap * 2 : 16; names = (char**)realloc(names, sizeof(char*) * (size_t)cap); }
    names[n++] = strdup(e->d_name);
  }
  closedir(d);
#endif
  if (!names) names = (char**)malloc(sizeof(char*));   /* never return NULL for an empty directory */
  *count = n;
  return names;
}

#endif
