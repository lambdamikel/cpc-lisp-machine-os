/* Pocket Lisp -- start-up, the library's Lisp text, the REPL, and the
 * machine layer on Linux (a terminal; the tests' transcripts). */
#include "lisp.h"
#include "read.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

obj S_T, S_QUOTE, S_FUNCTION, S_LAMBDA, S_QUASIQUOTE, S_UNQUOTE,
    S_UNQUOTE_SPLICING, S_AMP_OPTIONAL, S_AMP_REST, S_AMP_BODY, S_AMP_KEY,
    S_AMP_AUX, S_OTHERWISE, S_STDOUT, S_SETF, S_PROGN, S_BLOCK, S_DECLARE,
    S_STAR, S_STAR2, S_STAR3, S_KW_INITIAL_ELEMENT, S_KW_TEST, S_KW_TEST_NOT,
    S_KW_KEY, S_KW_START, S_KW_END, S_KW_FROM_END, S_KW_COUNT, S_SETF_PROP,
    S_STRUCTURE, S_ELSE, S_EXPANDED;

int loading_library;
static int batch;               /* input not a terminal: echo typed lines */

int toplevel_run(void (*fn)(void *), void *arg);
void reset_sinks(void);
void abandon_files(void);
void init_core_subrs(void);
void init_num(void);
void init_lib(void);
struct sfdef { const char *name; fsubr_fn fn; };
extern const struct sfdef special_forms[];

/* ---- the machine: Linux ---- */

void mach_putc(int c)
{
    putchar(c);
}

/* the tests' input: every line read first, so that a line of key actions
 * after one ("!esc N": ESC while it runs) is known when it starts */
static char **lines;
static int nlines, next_line;
extern int break_armed;
extern long break_countdown;

static void read_all_lines(void)
{
    char buf[4096];
    int cap = 0;
    while (fgets(buf, sizeof buf, stdin)) {
        size_t n = strlen(buf);
        while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
            buf[--n] = 0;
        if (nlines == cap) {
            cap = cap ? cap * 2 : 256;
            lines = realloc(lines, cap * sizeof(char *));
        }
        lines[nlines++] = strdup(buf);
    }
}

int mach_getline(char *buf, int max)
{
    fflush(stdout);
    if (lines) {
        while (next_line < nlines && lines[next_line][0] == '!')
            next_line++;
        if (next_line >= nlines)
            return -1;
        snprintf(buf, max, "%s", lines[next_line++]);
        break_armed = 0;
        int k = next_line;
        while (k < nlines && lines[k][0] == '!') {
            int frames;
            if (sscanf(lines[k], "!esc %d", &frames) == 1) {
                break_armed = 1;
                break_countdown = (long)frames * 2000;
            }
            int skip;
            if (sscanf(lines[k], "!type %d %n", &frames, &skip) == 1 && skip > 0) {
                extern void push_keys(const char *s);
                push_keys(lines[k] + skip);
            }
            k++;
        }
        return (int)strlen(buf);
    }
    if (!fgets(buf, max, stdin))
        return -1;
    size_t n = strlen(buf);
    while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
        buf[--n] = 0;
    return (int)n;
}

uint32_t mach_ticks(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 300 + ts.tv_nsec / 3333333);
}

/* ---- builtin symbols ---- */

static obj constant(const char *name, obj value)
{
    obj s = intern_cstr(name);
    SYM(s)->value = value == UNBOUND ? s : value;
    SYM(s)->flags |= SF_CONST;
    return s;
}

static obj special(const char *name, obj value)
{
    obj s = intern_cstr(name);
    SYM(s)->value = value;
    SYM(s)->flags |= SF_SPECIAL;
    return s;
}

void init_builtins(void)
{
    syms[0].name = mkstr("NIL");
    S_T = constant("T", UNBOUND);
    S_AMP_OPTIONAL = constant("&OPTIONAL", NIL);
    S_AMP_REST = constant("&REST", NIL);
    S_AMP_BODY = constant("&BODY", NIL);
    S_AMP_KEY = constant("&KEY", NIL);
    S_AMP_AUX = constant("&AUX", NIL);
    S_OTHERWISE = intern_cstr("OTHERWISE");
    S_UNQUOTE = intern_cstr("UNQUOTE");
    S_UNQUOTE_SPLICING = intern_cstr("UNQUOTE-SPLICING");
    for (int i = 0; special_forms[i].name; i++)
        defspecial(special_forms[i].name, special_forms[i].fn);
    S_QUOTE = intern_cstr("QUOTE");
    S_FUNCTION = intern_cstr("FUNCTION");
    S_LAMBDA = intern_cstr("LAMBDA");
    S_QUASIQUOTE = intern_cstr("QUASIQUOTE");
    S_SETF = intern_cstr("SETF");
    S_SETF_PROP = S_SETF;
    S_PROGN = intern_cstr("PROGN");
    S_BLOCK = intern_cstr("BLOCK");
    S_DECLARE = intern_cstr("DECLARE");
    S_EXPANDED = intern_cstr("%EXPANDED");
    S_ELSE = intern_cstr("ELSE");
    S_STRUCTURE = intern_cstr("STRUCTURE");
    init_core_subrs();
    init_num();
    S_STAR = special("*", NIL);
    S_STAR2 = special("**", NIL);
    S_STAR3 = special("***", NIL);
    S_STDOUT = special("*STANDARD-OUTPUT*", NIL);
    S_KW_INITIAL_ELEMENT = intern_cstr(":INITIAL-ELEMENT");
    S_KW_TEST = intern_cstr(":TEST");
    S_KW_TEST_NOT = intern_cstr(":TEST-NOT");
    S_KW_KEY = intern_cstr(":KEY");
    S_KW_START = intern_cstr(":START");
    S_KW_END = intern_cstr(":END");
    S_KW_FROM_END = intern_cstr(":FROM-END");
    S_KW_COUNT = intern_cstr(":COUNT");
    init_lib();
}

/* ---- loading Lisp text ---- */

static char *read_file(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(len + 1);
    *n = fread(buf, 1, len, f);
    buf[*n] = 0;
    fclose(f);
    return buf;
}

typedef struct { instream *in; int done; } evalarg;

static void eval_next(void *p)
{
    evalarg *a = p;
    obj x = lisp_read(a->in, 0, EOFMARK);
    if (x == EOFMARK) {
        a->done = 1;
        return;
    }
    eval(x, NIL);
}

void load_text(const char *text, size_t n, int library)
{
    instream in;
    in_init(&in, text, n);
    evalarg a = { &in, 0 };
    int was = loading_library;
    loading_library = library;
    while (!a.done) {
        if (toplevel_run(eval_next, &a)) {
            reset_sinks();
            if (in.pos >= in.len)
                break;
        }
    }
    loading_library = was;
    in_free(&in);
}

static void load_lib_file(const char *dir, const char *name)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    size_t n;
    char *text = read_file(path, &n);
    if (!text) {
        fprintf(stderr, "pocket: no %s\n", path);
        return;
    }
    load_text(text, n, 1);
    free(text);
}

void load_library(const char *dir)
{
    static const char *files[] = {
        "lisp.lsp", "lazy.lsp", "loop.lsp", "lisp2.lsp", "farray.lsp",
        "demo.lsp", NULL
    };
    for (int i = 0; files[i]; i++)
        load_lib_file(dir, files[i]);
    static const char features[] = "(defvar *features* '(:pocket :cpc-lisp))";
    load_text(features, sizeof features - 1, 1);
}

/* ---- the REPL ---- */

/* a line more for the reader, or for read-line (plain_refill set). In
 * batch mode, as the CPC's test harness and line editor do: each line
 * typed with a blank before it; the reader's lines echoed two in */
int plain_refill;

static int refill_line(instream *in)
{
    char line[4096];
    int n = mach_getline(line, sizeof line);
    if (n < 0)
        return 0;
    if (batch) {
        if (!plain_refill)
            putstr("  ");
        putstr(line);
        newline();
        in_append(in, " ", 1);
    }
    in_append(in, line, (size_t)n);
    in_append(in, "\n", 1);
    return 1;
}

typedef struct { instream *in; } replarg;

static void repl_form(void *p)
{
    replarg *a = p;
    extern obj lisp_read_top(instream *in);
    obj x = lisp_read_top(a->in);
    if (x == EOFMARK)
        return;
    mv_count = 0;
    obj v = eval(x, NIL);
    SYM(S_STAR3)->value = SYM(S_STAR2)->value;
    SYM(S_STAR2)->value = SYM(S_STAR)->value;
    SYM(S_STAR)->value = v;
    if (mv_count && mv_vals[0] == v) {
        for (int i = 0; i < mv_count - 1; i++) {
            fresh_line();
            prin1(mv_vals[i]);
            newline();
        }
        mv_count = 0;
        return;
    }
    fresh_line();
    prin1(v);
    newline();
}

void repl(void)
{
    char line[4096];
    for (;;) {
        fresh_line();
        putstr("LISP> ");
        int n = mach_getline(line, sizeof line);
        if (n < 0)
            break;
        if (batch) {
            putstr(line);
            /* the line editor beeps at a ) with no ( to match */
            int depth = 0, instr = 0;
            for (int k = 0; k < n; k++) {
                char ch = line[k];
                if (instr) { if (ch == '\\') k++; else if (ch == '"') instr = 0; continue; }
                if (ch == '"') instr = 1;
                else if (ch == ';') break;
                else if (ch == '(') depth++;
                else if (ch == ')') { if (depth) depth--; else putch(7); }
            }
            newline();
        } else
            out->col = 0;
        instream in;
        in_init(&in, line, (size_t)n);
        in_append(&in, "\n", 1);
        in.refill = refill_line;
        replarg a = { &in };
        extern instream *kbd_in;
        kbd_in = &in;
        while (!in_at_end(&in)) {
            if (toplevel_run(repl_form, &a)) {
                reset_sinks();
                abandon_files();
                break;
            }
        }
        kbd_in = NULL;
        in_free(&in);
    }
}

static int dummy_for_stack;

int main(int argc, char **argv)
{
    int local;
    stack_base = (uintptr_t)&local;
    (void)dummy_for_stack;
    const char *libdir = "lib";
    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "-l") && i + 1 < argc)
            libdir = argv[++i];
    extern int screen_cols;
    if (getenv("POCKET_COLS"))
        screen_cols = atoi(getenv("POCKET_COLS"));
    batch = !isatty(0);
    if (batch)
        read_all_lines();
    mem_init(8u << 20, 4u << 20, 32768);
    init_builtins();
    load_library(libdir);
    gc();
    printf("Pocket Lisp 0.1\n");
    printf("CPC Lisp's dialect, on a 32-bit core\n");
    printf("%u cells free\n\n", cells_free_after_gc);
    repl();
    return 0;
}
