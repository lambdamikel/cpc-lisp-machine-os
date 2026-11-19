/* Pocket Lisp -- CPC Lisp's design in C, on 32-bit words.
 *
 * A Lisp value is a 32-bit word; its low bits say what it is (as CPC
 * Lisp's 16-bit ones, docs/design.md):
 *
 *   ...1        a fixnum: the value times 2 plus 1 (31 bits)
 *   0           NIL
 *   ...000      a cons: 8 x its cell's index
 *   ...010      a typed cell: 8 x its index + 2 -- [header][data]
 *   ...100      a symbol: 16 x its slot + 4 (NIL is slot 0)
 *   ...0110     a character: code x 16 + 6
 *   ...1110     a marker (UNBOUND, EOF...): never a value
 *
 * Every object is an offset into the heap, never a C pointer, so the heap
 * is the same on a 64-bit host and the 32-bit RP2350, and a saved image
 * needs no relocation. The GC scans the C stack conservatively, as CPC
 * Lisp scans the Z80's: a native may keep Lisp values in its locals. It
 * must not keep a C pointer into block space across an allocation:
 * blocks move. */
#ifndef LISP_H
#define LISP_H
#include <stdint.h>
#include <stddef.h>
#include <setjmp.h>

typedef uint32_t obj;

#define NIL         ((obj)0)
#define isfix(o)    ((o) & 1)
#define mkfix(n)    ((obj)(((uint32_t)(int32_t)(n) << 1) | 1))
#define fixval(o)   ((int32_t)(o) >> 1)
#define FIX_MAX     0x3FFFFFFF
#define FIX_MIN     (-0x40000000)
#define iscons(o)   (((o) & 7) == 0 && (o) != 0)
#define istyped(o)  (((o) & 7) == 2)
#define issym(o)    (((o) & 7) == 4 || (o) == NIL)
#define ischar(o)   (((o) & 15) == 6)
#define ismarker(o) (((o) & 15) == 14)
#define mkchar(c)   ((obj)(((uint32_t)(c) << 4) | 6))
#define charval(o)  ((o) >> 4)
#define listp(o)    ((o) == NIL || iscons(o))

#define UNBOUND     ((obj)((1 << 4) | 14))
#define EOFMARK     ((obj)((2 << 4) | 14))
#define FREEMARK    ((obj)((3 << 4) | 14))
#define TAILCALL    ((obj)((4 << 4) | 14))   /* a special form's: go on with
                                                tail_form in tail_env */
#define NOVALUE     ((obj)((5 << 4) | 14))   /* an optional argument left out */

/* the heap: cells (8 bytes: car, cdr or header, data), symbols, blocks */
extern uint32_t *cells;
extern uint32_t ncells;
#define CELL(o)     (cells + ((o) >> 3) * 2)
#define car(o)      (CELL(o)[0])
#define cdr(o)      (CELL(o)[1])
#define HDR(o)      (CELL(o)[0])
#define DATA(o)     (CELL(o)[1])

/* typed cells' headers: the type, and whether the data word is a Lisp
 * value the GC follows (HF_OBJ), the index of a block (HF_BLOCK) or raw */
#define HF_OBJ      0x100
#define HF_BLOCK    0x200
enum {
    T_CLOSURE = 1 | HF_OBJ,     /* data: ((lambda-list . body) . env) */
    T_MACRO   = 2 | HF_OBJ,     /* data: a closure */
    T_SUBR    = 3,              /* data: a builtin's index */
    T_STRING  = 4 | HF_BLOCK,   /* data: a block of characters */
    T_FLOAT   = 5 | HF_BLOCK,   /* data: a block of 8 bytes, a double */
    T_VECTOR  = 6 | HF_BLOCK,   /* data: a block of words, Lisp values */
    T_STRUCT  = 7 | HF_BLOCK,   /*   the same; element 0 its type */
    T_CODE    = 8 | HF_OBJ,     /* a compiled function (later) */
};

/* a symbol's slot */
typedef struct {
    obj name;                   /* a string */
    obj value;                  /* UNBOUND if none */
    obj fn;                     /* UNBOUND if none */
    obj plist;
    uint32_t flags;
} symbol;
#define SF_SPECIAL  1
#define SF_CONST    2
#define SF_LIBDEF   4           /* defined by library text (save leaves it out) */
#define SF_USERDEF  8           /* defined by the user (defun, setf of the function) */
extern symbol *syms;
extern uint32_t nsyms;
#define SYM(o)      (&syms[(o) >> 4])
#define mksym(i)    ((obj)(((uint32_t)(i) << 4) | 4))

/* builtins */
typedef obj (*subr_fn)(int argc, obj *argv);
typedef obj (*fsubr_fn)(obj args, obj env);
typedef struct {
    const char *name;
    void *fn;
    int8_t min, max;            /* max -1: any number */
    uint8_t special;            /* a special form (FSUBR) */
} builtin;
extern builtin *builtins;
extern int nbuiltins;
#define ANY (-1)
obj defsubr(const char *name, subr_fn fn, int min, int max);
obj defspecial(const char *name, fsubr_fn fn);

/* memory: mem.c */
void mem_init(size_t cell_bytes, size_t block_bytes, uint32_t max_syms);
obj cons(obj a, obj d);
obj mktyped(uint32_t hdr, obj data);
obj mkstring(const char *s, size_t n);
obj mkstr(const char *s);
obj make_blob(uint32_t hdr, size_t nbytes);
uint32_t blk_len(obj o);        /* a block object's length in bytes */
uint8_t *blk_bytes(obj o);      /* its bytes (valid until the next allocation) */
obj *vec_elts(obj o);           /* a vector's or structure's elements */
uint32_t vec_len(obj o);
obj mkfloat(double d);
double floatval(obj o);
obj intern(const char *name, size_t n);
obj intern_cstr(const char *name);
obj make_symbol(obj name);      /* uninterned */
obj find_symbol(const char *name, size_t n);
void gc(void);
extern uint32_t gc_count, cells_free_after_gc;
uint32_t cells_free(void);
uint32_t blocks_free(void);
void gc_root(obj *p);
extern uintptr_t stack_base;
#define istype(o, t) (istyped(o) && HDR(o) == (uint32_t)(t))
#define isstring(o)  istype(o, T_STRING)
#define isfloat(o)   istype(o, T_FLOAT)
#define isvector(o)  istype(o, T_VECTOR)
#define isstruct(o)  istype(o, T_STRUCT)
#define isnumber(o)  (isfix(o) || isfloat(o))
#define str_len(o)   blk_len(o)
#define str_chars(o) ((char *)blk_bytes(o))

/* errors and frames: eval.c */
void lisp_error(const char *msg, obj o) __attribute__((noreturn));
void lisp_error0(const char *msg) __attribute__((noreturn));
void lisp_signal(obj condition) __attribute__((noreturn));
#define NOOBJ UNBOUND

/* evaluation */
obj eval(obj form, obj env);
obj apply(obj fn, int argc, obj *argv);
obj apply_list(obj fn, obj args);
obj funcall1(obj fn, obj a);
obj funcall2(obj fn, obj a, obj b);
obj coerce_fn(obj f);           /* a function designator -> a function */
obj progn(obj body, obj env);
obj macroexpand_1(obj form, obj env, int *expanded);
void set_value(obj sym, obj v);
obj sym_value(obj sym);
extern obj mv_vals[];           /* multiple values beyond the first */
extern int mv_count;            /* 0: one value; else how many */
extern obj tail_form, tail_env;

/* reading and printing: read.c, print.c */
typedef struct instream instream;
obj lisp_read(instream *in, int eof_error, obj eof_value);
obj read_from_cstr(const char *s, size_t n, size_t *used);
void prin1(obj o);
void princ(obj o);
void print_obj(obj o, int escape);
void putch(int c);
void putstr(const char *s);
void fresh_line(void);
void newline(void);
extern int out_col;

/* output redirection: a stack of sinks (the screen, a string, a file) */
typedef struct sink sink;
struct sink {
    void (*put)(sink *s, int c);
    int col;
    void *data;
};
extern sink *out;
sink *push_string_sink(void);
obj pop_string_sink(sink *s);   /* -> what was printed, as a string */
void put_to_screen(sink *s, int c);

/* predicates and helpers: subrs.c */
int eql(obj a, obj b);
int equal(obj a, obj b);
obj list2(obj a, obj b);
obj list3(obj a, obj b, obj c);
obj nreverse(obj l);
int32_t lisp_length(obj l);
obj check_list(obj o);
obj check_sym(obj o);
obj check_string(obj o);
int32_t check_int(obj o);
obj bool_obj(int b);
obj string_designator(obj o);   /* a string, symbol or character -> a string */

/* numbers: num.c */
obj num_add(obj a, obj b);
obj num_sub(obj a, obj b);
obj num_mul(obj a, obj b);
obj num_div(obj a, obj b);
int num_cmp(obj a, obj b);
obj check_number(obj o);
double num_double(obj o);
obj mkint(int64_t n);           /* a fixnum, or a float past 31 bits */

/* the builtin symbols the C code names */
extern obj S_T, S_QUOTE, S_FUNCTION, S_LAMBDA, S_QUASIQUOTE, S_UNQUOTE,
    S_UNQUOTE_SPLICING, S_AMP_OPTIONAL, S_AMP_REST, S_AMP_BODY, S_AMP_KEY,
    S_AMP_AUX, S_OTHERWISE, S_STDOUT, S_SETF, S_PROGN, S_BLOCK, S_DECLARE,
    S_STAR, S_STAR2, S_STAR3, S_KW_INITIAL_ELEMENT, S_KW_TEST, S_KW_TEST_NOT,
    S_KW_KEY, S_KW_START, S_KW_END, S_KW_FROM_END, S_KW_COUNT, S_SETF_PROP,
    S_STRUCTURE, S_ELSE;

void init_builtins(void);
void lib_init(void);
void load_library(const char *dir);
void repl(void);

/* the machine: mach_host.c */
int mach_getline(char *buf, int max);   /* a typed line, without its end; -1 at the end */
void mach_putc(int c);
uint32_t mach_ticks(void);              /* 1/300 s, as the CPC's TIME */

#endif
