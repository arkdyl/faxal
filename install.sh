#!/bin/sh
# Installs faxal on Linux, macOS and BSD.
#
#   From a checkout of this repository (builds from the single C file, needs only a C compiler):
#       ./install.sh
#   From the web (downloads the latest release; builds from faxal.c if there is no binary for your system):
#       curl -fsSL https://raw.githubusercontent.com/arkdyl/faxal/main/install.sh | sh
#
# Options (environment variables):
#   PREFIX=/usr/local      where to install (bin/faxal and share/faxal/faxal.c); default ~/.faxal if /usr/local isn't writable
#   FAXAL_BASE_URL=...     where faxal.c and the prebuilt faxal-<os>-<arch> files live (default: the latest GitHub release)
#   CC=cc                  the C compiler to use

set -eu

say() { printf 'faxal: %s\n' "$*"; }
die() { printf 'faxal: %s\n' "$*" >&2; exit 1; }

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$os" in
  linux|darwin|freebsd|openbsd|netbsd) ;;
  *) die "unsupported system '$os' (on Windows, use install.ps1)" ;;
esac

if [ -z "${PREFIX:-}" ]; then
  if [ -w /usr/local/bin ] 2>/dev/null; then PREFIX=/usr/local; else PREFIX="$HOME/.faxal"; fi
fi
mkdir -p "$PREFIX/bin" "$PREFIX/share/faxal"

work=$(mktemp -d 2>/dev/null || mktemp -d -t faxal)
trap 'rm -rf "$work"' EXIT INT TERM

fetch() { # fetch URL DEST
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
  else die "need curl or wget to download files"; fi
}

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")
source_c=""
if [ -n "$here" ] && [ -f "$here/native/dist/faxal.c" ]; then
  source_c="$here/native/dist/faxal.c"
  say "building from $source_c"
else
  FAXAL_BASE_URL=${FAXAL_BASE_URL:-https://github.com/arkdyl/faxal/releases/latest/download}
  say "downloading from $FAXAL_BASE_URL"
  if fetch "$FAXAL_BASE_URL/faxal-$os-$arch" "$work/faxal" 2>/dev/null; then
    chmod +x "$work/faxal"
    fetch "$FAXAL_BASE_URL/faxal.c" "$PREFIX/share/faxal/faxal.c" 2>/dev/null || true
    cp "$work/faxal" "$PREFIX/bin/faxal"
    say "installed a prebuilt faxal to $PREFIX/bin/faxal"
    source_c=""
    prebuilt=1
  else
    fetch "$FAXAL_BASE_URL/faxal.c" "$work/faxal.c" || die "could not download faxal.c from $FAXAL_BASE_URL"
    source_c="$work/faxal.c"
  fi
fi

if [ -n "$source_c" ]; then
  cc=${CC:-}
  if [ -z "$cc" ]; then
    for c in cc gcc clang; do command -v "$c" >/dev/null 2>&1 && { cc=$c; break; }; done
  fi
  [ -n "$cc" ] || die "no C compiler found. Install one (Xcode command line tools on macOS: xcode-select --install; build-essential on Debian/Ubuntu)"
  say "compiling with $cc (this takes a few seconds)"
  "$cc" -O2 -std=c11 -o "$work/faxal" "$source_c" -lm || die "the build failed"
  cp "$work/faxal" "$PREFIX/bin/faxal"
  cp "$source_c" "$PREFIX/share/faxal/faxal.c"
fi

chmod +x "$PREFIX/bin/faxal"
"$PREFIX/bin/faxal" -e 'print("faxal " + "works: " + str(1 + 2 == 3))' >/dev/null || die "the installed faxal does not run"
say "installed: $PREFIX/bin/faxal"
case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) say "add it to your PATH:  export PATH=\"$PREFIX/bin:\$PATH\"" ;;
esac
say "try:  faxal -e 'print(\"hello\")'"
