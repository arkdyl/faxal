CC      ?= cc
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -Wno-unused-parameter
SRC      = $(wildcard src/*.c)
HDR      = $(wildcard src/*.h)
PREFIX  ?= /usr/local

all: bin/faxal

bin/faxal: $(SRC) $(HDR)
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $(SRC) -lm

# Debug build: AddressSanitizer + UBSan, and a GC that collects at every safe point.
bin/faxal-debug: $(SRC) $(HDR)
	@mkdir -p bin
	$(CC) -std=c11 -g -O1 -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -fno-omit-frame-pointer -DFAXAL_GC_STRESS -o $@ $(SRC) -lm

# Sanitizers only (no GC stress): used for fuzzing.
bin/faxal-asan: $(SRC) $(HDR)
	@mkdir -p bin
	$(CC) -std=c11 -g -O1 -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -fno-omit-frame-pointer -o $@ $(SRC) -lm

fuzz: bin/faxal-asan
	python3 tests/fuzz.py bin/faxal-asan 600
	FUZZ_FMT=1 python3 tests/fuzz.py bin/faxal-asan 300
	python3 tests/selfhost_fuzz.py bin/faxal-asan 600
	python3 tests/bytecode_fuzz.py bin/faxal-asan 1500

# Regenerate src/embedded.c from lib/ (the generator is a Faxal program), then rebuild.
embed: bin/faxal
	bin/faxal tools/embed.fx src/embedded.c
	$(MAKE) bin/faxal

# The whole runtime as one C file, dist/faxal.c: `cc -O2 -o faxal dist/faxal.c -lm` builds faxal with nothing else.
amalgam: bin/faxal
	bin/faxal tools/amalgamate.fx dist/faxal.c

check-amalgam: bin/faxal
	@bin/faxal tools/amalgamate.fx $${TMPDIR:-/tmp}/faxal-one.c >/dev/null && diff -q $${TMPDIR:-/tmp}/faxal-one.c dist/faxal.c >/dev/null || (echo 'dist/faxal.c is out of date: run make amalgam'; exit 1)

check-embed: bin/faxal
	@bin/faxal tools/embed.fx $${TMPDIR:-/tmp}/faxal-embedded.c >/dev/null && diff -q $${TMPDIR:-/tmp}/faxal-embedded.c src/embedded.c >/dev/null || (echo 'src/embedded.c is out of date: run make embed'; exit 1)

test: bin/faxal check-embed check-amalgam
	python3 tests/run.py bin/faxal
	bin/faxal test tests/std
	python3 tests/fmt_check.py bin/faxal
	python3 tests/tools_test.py bin/faxal
	# the compiler written in Faxal is the default; the C compiler is the reference it is compared against
	python3 tests/selfhost_check.py bin/faxal
	python3 tests/selfhost_fuzz.py bin/faxal 300 1
	FAXAL_C_COMPILER=1 python3 tests/run.py bin/faxal
	FAXAL_C_COMPILER=1 bin/faxal test tests/std
	# the bytecode file format
	python3 tests/bytecode_check.py bin/faxal
	# the single-file build and compile-to-C
	python3 tests/native_check.py bin/faxal
	# the language server
	python3 tests/lsp_test.py bin/faxal
	# async in safe mode
	python3 tests/async_check.py bin/faxal

selfhost-fuzz: bin/faxal
	python3 tests/selfhost_fuzz.py bin/faxal 5000

test-debug: bin/faxal-debug bin/faxal-asan
	python3 tests/run.py bin/faxal-debug
	bin/faxal-debug test tests/std
	python3 tests/tools_test.py bin/faxal-debug
	FAXAL_C_COMPILER=1 python3 tests/run.py bin/faxal-debug
	FAXAL_C_COMPILER=1 bin/faxal-debug test tests/std
	python3 tests/bytecode_check.py bin/faxal-asan

install: bin/faxal dist/faxal.c
	install -d $(PREFIX)/bin $(PREFIX)/share/faxal
	install -m 755 bin/faxal $(PREFIX)/bin/faxal
	install -m 644 dist/faxal.c $(PREFIX)/share/faxal/faxal.c

clean:
	rm -rf bin

.PHONY: all test test-debug fuzz selfhost-fuzz embed check-embed amalgam check-amalgam install clean
