/* Pocket Lisp -- the printer and the output sinks (CPC Lisp's
 * src/print.asm and putc's modes: the screen, memory, a file). */
#include "lisp.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void format_float(double d, char *buf);

static sink screen = { put_to_screen, 0, NULL };
sink *out = &screen;
int out_col;

void put_to_screen(sink *s, int c)
{
    (void)s;
    mach_putc(c);
}

void putch(int c)
{
    out->put(out, c);
    if (c == '\n' || c == '\r')
        out->col = 0;
    else
        out->col++;
}

void putstr(const char *s)
{
    while (*s)
        putch((uint8_t)*s++);
}

void newline(void) { putch('\n'); }

void fresh_line(void)
{
    if (out->col != 0)
        newline();
}

/* ---- string sinks: printing into memory ---- */

typedef struct {
    sink s;
    sink *prev;
    char *buf;
    size_t n, cap;
    obj tag;                    /* the string output stream, if any */
} strsink;

void sink_set_tag(sink *s, obj t) { ((strsink *)s)->tag = t; }
obj sink_tag(sink *s) { return ((strsink *)s)->tag; }

static void put_to_string(sink *s, int c)
{
    strsink *ss = (strsink *)s;
    if (ss->n == ss->cap) {
        ss->cap = ss->cap ? ss->cap * 2 : 64;
        ss->buf = realloc(ss->buf, ss->cap);
    }
    ss->buf[ss->n++] = (char)c;
}

sink *push_string_sink(void)
{
    strsink *ss = calloc(1, sizeof(strsink));
    ss->s.put = put_to_string;
    ss->prev = out;
    out = &ss->s;
    return &ss->s;
}

obj pop_string_sink(sink *s)
{
    strsink *ss = (strsink *)s;
    out = ss->prev;
    obj r = mkstring(ss->buf ? ss->buf : "", ss->n);
    free(ss->buf);
    free(ss);
    return r;
}

/* the sink to go back to when an error leaves a string sink behind */
void reset_sinks(void)
{
    while (out != &screen) {
        strsink *ss = (strsink *)out;
        if (ss->s.put != put_to_string)
            break;
        out = ss->prev;
        free(ss->buf);
        free(ss);
    }
    out = &screen;
}

/* ---- objects ---- */

static const struct { const char *name; int code; } charnames[] = {
    {"Space", 32}, {"Newline", 10}, {"Tab", 9}, {"Return", 13},
    {"Linefeed", 10}, {"Page", 12}, {"Backspace", 8}, {"Escape", 27},
    {"Rubout", 127}, {"Nul", 0}, {NULL, 0}
};

const char *char_name(int c)
{
    for (int i = 0; charnames[i].name; i++)
        if (charnames[i].code == c)
            return charnames[i].name;
    return NULL;
}

int char_by_name(const char *s, size_t n)
{
    for (int i = 0; charnames[i].name; i++)
        if (strlen(charnames[i].name) == n && !strncasecmp(charnames[i].name, s, n))
            return charnames[i].code;
    return -1;
}

static int is_delim(int c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '('
        || c == ')' || c == '\'' || c == '"' || c == ';' || c == '`'
        || c == ',';
}

/* would read give this name back as it is? */
static int sym_odd(const char *s, uint32_t n)
{
    if (n == 0 || (n == 1 && s[0] == '.'))
        return 1;
    uint32_t i = 0;
    if (s[0] == '+' || s[0] == '-') {
        i = 1;
        if (n == 1)
            goto word;
    }
    {
        uint32_t k = i;
        while (k < n && s[k] >= '0' && s[k] <= '9')
            k++;
        if (k == n)
            return 1;               /* digits: a number */
    }
word:
    for (i = 0; i < n; i++) {
        int c = (uint8_t)s[i];
        if ((c >= 'a' && c <= 'z') || c == '|' || c == '\\' || is_delim(c))
            return 1;
    }
    return 0;
}

static void print_chars(const char *s, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++)
        putch((uint8_t)s[i]);
}

static void print_symbol(obj o, int escape)
{
    obj name = SYM(o)->name;
    uint32_t n = str_len(name);
    /* (the name stays put: printing allocates nothing) */
    const char *s = str_chars(name);
    if (escape && sym_odd(s, n)) {
        putch('|');
        print_chars(s, n);
        putch('|');
    } else
        print_chars(s, n);
}

static void print_string(obj o, int escape)
{
    uint32_t n = str_len(o);
    const char *s = str_chars(o);
    if (!escape) {
        print_chars(s, n);
        return;
    }
    putch('"');
    for (uint32_t i = 0; i < n; i++) {
        if (s[i] == '"' || s[i] == '\\')
            putch('\\');
        putch((uint8_t)s[i]);
    }
    putch('"');
}

static void print_char(obj o, int escape)
{
    int c = (int)charval(o);
    if (!escape) {
        putch(c);
        return;
    }
    putstr("#\\");
    if (c <= ' ' || c == 127) {
        const char *nm = char_name(c);
        if (nm) {
            putstr(nm);
            return;
        }
    }
    putch(c);
}

static void print_list(obj o, int escape)
{
    obj a = car(o);
    /* a macro call with its expansion kept: shown as written */
    extern obj S_EXPANDED;
    if (a == S_EXPANDED && iscons(cdr(o)) && iscons(cdr(cdr(o)))) {
        print_list(cdr(cdr(o)), escape);
        return;
    }
    if (issym(a) && iscons(cdr(o)) && cdr(cdr(o)) == NIL) {
        const char *pre = NULL;
        if (a == S_QUOTE) pre = "'";
        else if (a == S_FUNCTION) pre = "#'";
        else if (a == S_QUASIQUOTE) pre = "`";
        else if (a == S_UNQUOTE) pre = ",";
        else if (a == S_UNQUOTE_SPLICING) pre = ",@";
        if (pre) {
            putstr(pre);
            print_obj(car(cdr(o)), escape);
            return;
        }
    }
    putch('(');
    for (;;) {
        print_obj(car(o), escape);
        o = cdr(o);
        if (!iscons(o))
            break;
        putch(' ');
    }
    if (o != NIL) {
        putstr(" . ");
        print_obj(o, escape);
    }
    putch(')');
}

void print_obj(obj o, int escape)
{
    if (isfix(o)) {
        char buf[16];
        snprintf(buf, sizeof buf, "%d", fixval(o));
        putstr(buf);
        return;
    }
    if (issym(o)) {
        print_symbol(o, escape);
        return;
    }
    if (iscons(o)) {
        print_list(o, escape);
        return;
    }
    if (ischar(o)) {
        print_char(o, escape);
        return;
    }
    if (ismarker(o)) {
        putstr(o == UNBOUND ? "#<UNBOUND>" : "#<MARKER>");
        return;
    }
    switch (HDR(o)) {
    case T_STRING:
        print_string(o, escape);
        return;
    case T_FLOAT: {
        char buf[48];
        format_float(floatval(o), buf);
        putstr(buf);
        return;
    }
    case T_VECTOR:
    case T_STRUCT: {
        uint32_t n = vec_len(o);
        putstr(HDR(o) == T_VECTOR ? "#(" : "#S(");
        for (uint32_t i = 0; i < n; i++) {
            if (i)
                putch(' ');
            print_obj(vec_elts(o)[i], escape);
        }
        putch(')');
        return;
    }
    case T_CLOSURE:
    case T_CODE:
        putstr("#<FUNCTION>");
        return;
    case T_MACRO:
        putstr("#<MACRO>");
        return;
    case T_SUBR: {
        const builtin *b = &builtins[DATA(o)];
        putstr(b->special ? "#<SPECIAL " : "#<SUBR ");
        putstr(b->name);
        putch('>');
        return;
    }
    }
    putstr("#<?>");
}

void prin1(obj o) { print_obj(o, 1); }
void princ(obj o) { print_obj(o, 0); }
