# Pocket Lisp on Linux: make; ./pocket (from the repository's root, or -l DIR
# for the library's Lisp text); tools/test.sh runs the regression tests.
CC ?= cc
CFLAGS ?= -O2 -g -Wall -Wextra -Wno-unused-parameter -std=gnu11
SRC := $(wildcard src/*.c)
OBJ := $(SRC:src/%.c=build/%.o)

pocket: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $(OBJ) -lm

build/%.o: src/%.c src/lisp.h src/read.h | build
	$(CC) $(CFLAGS) -c -o $@ $<

build:
	mkdir -p build

clean:
	rm -rf build pocket

.PHONY: clean
