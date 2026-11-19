/* Pocket Lisp -- memory: cells, typed cells, block space, symbols, and the
 * garbage collector (mark and sweep, the C stack scanned conservatively,
 * block space compacted), as CPC Lisp's src/mem.asm. */
#include "lisp.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

uint32_t *cells;
uint32_t ncells;
static uint32_t free_list;          /* a cell index, 0: none */
static uint8_t *marks;
symbol *syms;
uint32_t nsyms;
static uint32_t max_syms;
static uint32_t *symhash;           /* symbol indices, 0 empty */
static uint32_t symhash_size;
static uint32_t *blocks;            /* block space, in words */
static uint32_t blk_top, blk_size;
uint32_t gc_count, cells_free_after_gc;
uintptr_t stack_base;
static obj *roots[64];
static int nroots;

void mem_init(size_t cell_bytes, size_t block_bytes, uint32_t maxs)
{
    ncells = cell_bytes / 8;
    cells = calloc(ncells, 8);
    marks = calloc(ncells, 1);
    blk_size = block_bytes / 4;
    blocks = calloc(blk_size, 4);
    blk_top = 1;                    /* (index 0: no block) */
    max_syms = maxs;
    syms = calloc(max_syms, sizeof(symbol));
    symhash_size = 1;
    while (symhash_size < max_syms * 2)
        symhash_size <<= 1;
    symhash = calloc(symhash_size, 4);
    if (!cells || !marks || !blocks || !syms || !symhash) {
        fprintf(stderr, "pocket: no memory for the heap\n");
        exit(1);
    }
    free_list = 0;                  /* cell 0 is NIL's: never used */
    for (uint32_t i = ncells - 1; i >= 1; i--) {
        cells[2 * i] = FREEMARK;
        cells[2 * i + 1] = free_list;
        free_list = i;
    }
    nsyms = 1;                      /* slot 0: NIL, named by init_builtins */
    syms[0].value = NIL;
    syms[0].fn = UNBOUND;
    syms[0].flags = SF_CONST;
}

void gc_root(obj *p)
{
    roots[nroots++] = p;
}

static uint32_t take_cell(void)
{
    if (!free_list) {
        gc();
        if (!free_list)
            lisp_error0("out of memory");
    }
    uint32_t i = free_list;
    free_list = cells[2 * i + 1];
    return i;
}

obj cons(obj a, obj d)
{
    uint32_t i = take_cell();
    cells[2 * i] = a;
    cells[2 * i + 1] = d;
    return (obj)(i * 8);
}

obj mktyped(uint32_t hdr, obj data)
{
    uint32_t i = take_cell();
    cells[2 * i] = hdr;
    cells[2 * i + 1] = data;
    return (obj)(i * 8 + 2);
}

/* make_blob: a typed cell with a block of nbytes (zeroed) */
obj make_blob(uint32_t hdr, size_t nbytes)
{
    uint32_t words = 2 + (uint32_t)((nbytes + 3) / 4);
    obj o = mktyped(hdr, 0);        /* reachable from here on (the stack) */
    if (blk_top + words > blk_size) {
        gc();
        if (blk_top + words > blk_size)
            lisp_error0("out of string space");
    }
    uint32_t b = blk_top;
    blk_top += words;
    blocks[b] = o >> 3;             /* the owner: the cell */
    blocks[b + 1] = (uint32_t)nbytes;
    memset(&blocks[b + 2], 0, (words - 2) * 4);
    DATA(o) = b;
    return o;
}

uint32_t blk_len(obj o) { return blocks[DATA(o) + 1]; }
uint8_t *blk_bytes(obj o) { return (uint8_t *)&blocks[DATA(o) + 2]; }
obj *vec_elts(obj o) { return (obj *)&blocks[DATA(o) + 2]; }
uint32_t vec_len(obj o) { return blocks[DATA(o) + 1] / 4; }

obj mkstring(const char *s, size_t n)
{
    obj o = make_blob(T_STRING, n);
    if (n)
        memcpy(blk_bytes(o), s, n);
    return o;
}

obj mkstr(const char *s) { return mkstring(s, strlen(s)); }

obj mkfloat(double d)
{
    obj o = make_blob(T_FLOAT, 8);
    memcpy(blk_bytes(o), &d, 8);
    return o;
}

double floatval(obj o)
{
    double d;
    memcpy(&d, blk_bytes(o), 8);
    return d;
}

/* ---- symbols ---- */

static uint32_t hash_name(const char *s, size_t n)
{
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++)
        h = (h ^ (uint8_t)s[i]) * 16777619u;
    return h;
}

static obj new_symbol(obj name)
{
    if (nsyms >= max_syms)
        lisp_error0("out of symbols");
    uint32_t i = nsyms++;
    syms[i].name = name;
    syms[i].value = UNBOUND;
    syms[i].fn = UNBOUND;
    syms[i].plist = NIL;
    syms[i].flags = 0;
    return mksym(i);
}

obj find_symbol(const char *name, size_t n)
{
    uint32_t h = hash_name(name, n) & (symhash_size - 1);
    while (symhash[h]) {
        symbol *s = &syms[symhash[h]];
        if (str_len(s->name) == n && !memcmp(str_chars(s->name), name, n))
            return mksym(symhash[h]);
        h = (h + 1) & (symhash_size - 1);
    }
    if (n == 3 && !memcmp(name, "NIL", 3))
        return NIL;
    return UNBOUND;
}

obj intern(const char *name, size_t n)
{
    obj s = find_symbol(name, n);
    if (s != UNBOUND)
        return s;
    obj str = mkstring(name, n);    /* (the name may be in block space) */
    s = new_symbol(str);
    const char *nm = str_chars(str);
    uint32_t h = hash_name(nm, n) & (symhash_size - 1);
    while (symhash[h])
        h = (h + 1) & (symhash_size - 1);
    symhash[h] = s >> 4;
    if (n && nm[0] == ':') {        /* a keyword: itself, a constant */
        SYM(s)->value = s;
        SYM(s)->flags |= SF_CONST;
    }
    return s;
}

obj intern_cstr(const char *name) { return intern(name, strlen(name)); }

obj make_symbol(obj name) { return new_symbol(name); }

/* ---- the garbage collector ---- */

static obj *mstack;
static uint32_t msp, msize;

static void mpush(obj o)
{
    if (msp == msize) {
        msize = msize ? msize * 2 : 4096;
        mstack = realloc(mstack, msize * sizeof(obj));
    }
    mstack[msp++] = o;
}

static void mark_from(obj o)
{
    mpush(o);
    while (msp) {
        o = mstack[--msp];
    again:
        if (isfix(o) || o == NIL || (o & 7) == 4 || (o & 7) == 6)
            continue;
        uint32_t i = o >> 3;
        if (i == 0 || i >= ncells || marks[i])
            continue;
        marks[i] = 1;
        if ((o & 7) == 0) {
            mpush(cells[2 * i]);
            o = cells[2 * i + 1];
            goto again;
        }
        uint32_t h = cells[2 * i];
        if (h & HF_OBJ) {
            o = cells[2 * i + 1];
            goto again;
        }
        if (h == T_VECTOR || h == T_STRUCT) {
            uint32_t b = cells[2 * i + 1];
            if (b) {
                uint32_t n = blocks[b + 1] / 4;
                for (uint32_t k = 0; k < n; k++)
                    mpush(blocks[b + 2 + k]);
            }
        }
    }
}

/* is w, a word found on the C stack, a live cell's object? */
static int plausible(uint32_t w)
{
    if (isfix(w) || w == 0)
        return 0;
    uint32_t t = w & 7;
    if (t != 0 && t != 2)
        return 0;
    uint32_t i = w >> 3;
    if (i == 0 || i >= ncells)
        return 0;
    uint32_t a = cells[2 * i];
    if (a == FREEMARK)
        return 0;
    if (t == 2)
        return a == T_CLOSURE || a == T_MACRO || a == T_SUBR || a == T_STRING
            || a == T_FLOAT || a == T_VECTOR || a == T_STRUCT || a == T_CODE;
    return 1;
}

static void __attribute__((noinline)) scan_stack(void)
{
    jmp_buf regs;                   /* the registers, onto the stack */
    setjmp(regs);
    volatile uintptr_t here = (uintptr_t)&regs;
    uintptr_t lo = here < stack_base ? here : stack_base;
    uintptr_t hi = here < stack_base ? stack_base : here;
    lo &= ~(uintptr_t)3;
    for (uintptr_t p = lo; p < hi; p += 4) {
        uint32_t w = *(uint32_t *)p;
        if (plausible(w))
            mark_from(w);
    }
}

extern void mark_extra_roots(void (*mark)(obj));

void gc(void)
{
    memset(marks, 0, ncells);
    for (uint32_t i = 0; i < nsyms; i++) {
        mark_from(syms[i].name);
        mark_from(syms[i].value);
        mark_from(syms[i].fn);
        mark_from(syms[i].plist);
    }
    for (int i = 0; i < nroots; i++)
        mark_from(*roots[i]);
    mark_extra_roots(mark_from);
    scan_stack();
    /* blocks: compacted, each moved down to the next free place */
    uint32_t to = 1;
    for (uint32_t b = 1; b < blk_top;) {
        uint32_t owner = blocks[b];
        uint32_t words = 2 + (blocks[b + 1] + 3) / 4;
        if (owner < ncells && marks[owner] && (cells[2 * owner] & HF_BLOCK)
            && cells[2 * owner + 1] == b) {
            if (to != b)
                memmove(&blocks[to], &blocks[b], words * 4);
            cells[2 * owner + 1] = to;
            to += words;
        }
        b += words;
    }
    blk_top = to;
    /* cells: the unmarked ones free */
    free_list = 0;
    uint32_t n = 0;
    for (uint32_t i = ncells - 1; i >= 1; i--) {
        if (!marks[i]) {
            cells[2 * i] = FREEMARK;
            cells[2 * i + 1] = free_list;
            free_list = i;
            n++;
        }
    }
    gc_count++;
    cells_free_after_gc = n;
}

uint32_t cells_free(void)
{
    uint32_t n = 0;
    for (uint32_t i = free_list; i; i = cells[2 * i + 1])
        n++;
    return n;
}

uint32_t blocks_free(void) { return (blk_size - blk_top) * 4; }
