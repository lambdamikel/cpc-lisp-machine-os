/* Pocket Lisp -- the reader (CPC Lisp's src/read.asm): from text in
 * memory, with a refill for more (the keyboard's next line). */
#include "lisp.h"
#include "read.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int char_by_name(const char *s, size_t n);
extern obj S_EXPANDED;

#define CLOSEMARK ((obj)((10 << 4) | 14))
#define DOTMARK   ((obj)((11 << 4) | 14))

void in_init(instream *in, const char *text, size_t n)
{
    memset(in, 0, sizeof *in);
    in->cap = n + 1;
    in->buf = malloc(in->cap);
    memcpy(in->buf, text, n);
    in->len = n;
}

void in_append(instream *in, const char *text, size_t n)
{
    if (in->len + n + 1 > in->cap) {
        in->cap = (in->len + n + 1) * 2;
        in->buf = realloc(in->buf, in->cap);
    }
    memcpy(in->buf + in->len, text, n);
    in->len += n;
}

void in_free(instream *in)
{
    free(in->buf);
    in->buf = NULL;
}

int in_getc(instream *in)
{
    while (in->pos >= in->len) {
        if (!in->refill || !in->refill(in))
            return -1;
    }
    int c = (uint8_t)in->buf[in->pos++];
    in->consumed++;
    return c;
}

int in_peek(instream *in)
{
    while (in->pos >= in->len) {
        if (!in->refill || !in->refill(in))
            return -1;
    }
    return (uint8_t)in->buf[in->pos];
}

void in_unget(instream *in)
{
    if (in->pos > 0) {
        in->pos--;
        in->consumed--;
    }
}

static int is_ws(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'; }

static int is_term(int c)
{
    return c < 0 || is_ws(c) || c == '(' || c == ')' || c == '\'' || c == '"'
        || c == ';' || c == '`' || c == ',';
}

/* skip white space and comments -> the next character, not taken */
static int skip_ws(instream *in)
{
    for (;;) {
        int c = in_peek(in);
        if (c < 0)
            return c;
        if (is_ws(c)) {
            in_getc(in);
            continue;
        }
        if (c == ';') {
            while ((c = in_getc(in)) >= 0 && c != '\n' && c != '\r')
                ;
            continue;
        }
        if (c == '#' && in->pos + 1 < in->len && in->buf[in->pos + 1] == '|') {
            in_getc(in);
            in_getc(in);
            int depth = 1, prev = 0;
            while (depth > 0 && (c = in_getc(in)) >= 0) {
                if (prev == '|' && c == '#') { depth--; c = 0; }
                else if (prev == '#' && c == '|') { depth++; c = 0; }
                prev = c;
            }
            if (c < 0)
                lisp_error0("unexpected end of text");
            continue;
        }
        return c;
    }
}

static obj read_obj(instream *in);

/* a number from a token, or UNBOUND */
static obj parse_number(const char *s, size_t n)
{
    size_t i = 0;
    int neg = 0;
    if (i < n && (s[i] == '+' || s[i] == '-')) {
        neg = s[i] == '-';
        i++;
    }
    size_t d0 = i;
    while (i < n && s[i] >= '0' && s[i] <= '9')
        i++;
    size_t ndig = i - d0;
    if (i == n && ndig > 0) {               /* an integer */
        int64_t v = 0;
        int big = 0;
        for (size_t k = d0; k < n; k++) {
            v = v * 10 + (s[k] - '0');
            if (v > (int64_t)FIX_MAX + 1) { big = 1; break; }
        }
        if (!big) {
            if (neg) v = -v;
            if (v >= FIX_MIN && v <= FIX_MAX)
                return mkfix((int32_t)v);
        }
        char tmp[64];
        if (n >= sizeof tmp) return UNBOUND;
        memcpy(tmp, s, n);
        tmp[n] = 0;
        return mkfloat(strtod(tmp, NULL));
    }
    /* a float: digits [. digits] [e [sign] digits], at least one digit */
    size_t frac = 0;
    if (i < n && s[i] == '.') {
        i++;
        size_t f0 = i;
        while (i < n && s[i] >= '0' && s[i] <= '9')
            i++;
        frac = i - f0;
    } else if (i == n || (s[i] != 'e' && s[i] != 'E'))
        return UNBOUND;
    if (ndig + frac == 0)
        return UNBOUND;
    if (i < n && (s[i] == 'e' || s[i] == 'E')) {
        i++;
        if (i < n && (s[i] == '+' || s[i] == '-'))
            i++;
        size_t e0 = i;
        while (i < n && s[i] >= '0' && s[i] <= '9')
            i++;
        if (i == e0)
            return UNBOUND;
    }
    if (i != n)
        return UNBOUND;
    char tmp[128];
    if (n >= sizeof tmp)
        return UNBOUND;
    memcpy(tmp, s, n);
    tmp[n] = 0;
    return mkfloat(strtod(tmp, NULL));
}

static obj read_token(instream *in, int first)
{
    char tok[4096];
    size_t n = 0;
    int escaped = 0;
    int c = first;
    for (;;) {
        if (c == '|') {
            escaped = 1;
            while ((c = in_getc(in)) >= 0 && c != '|') {
                if (c == '\\')
                    c = in_getc(in);
                if (n < sizeof tok) tok[n++] = (char)c;
            }
            if (c < 0)
                lisp_error0("unexpected end of text");
        } else if (c == '\\') {
            escaped = 1;
            c = in_getc(in);
            if (c < 0)
                lisp_error0("unexpected end of text");
            if (n < sizeof tok) tok[n++] = (char)c;
        } else {
            if (c >= 'a' && c <= 'z')
                c -= 32;
            if (n < sizeof tok) tok[n++] = (char)c;
        }
        c = in_peek(in);
        if (is_term(c))
            break;
        in_getc(in);
    }
    if (n >= sizeof tok)
        lisp_error0("token too long");
    if (!escaped) {
        obj num = parse_number(tok, n);
        if (num != UNBOUND)
            return num;
        if (n == 1 && tok[0] == '.')
            return DOTMARK;
    }
    return intern(tok, n);
}

static obj read_string(instream *in)
{
    char *buf = NULL;
    size_t n = 0, cap = 0;
    int c;
    while ((c = in_getc(in)) >= 0 && c != '"') {
        if (c == '\\') {
            c = in_getc(in);
            if (c < 0)
                break;
        }
        if (n == cap) {
            cap = cap ? cap * 2 : 64;
            buf = realloc(buf, cap);
        }
        buf[n++] = (char)c;
    }
    if (c < 0) {
        free(buf);
        lisp_error0("unexpected end of text");
    }
    obj s = mkstring(buf ? buf : "", n);
    free(buf);
    return s;
}

static obj read_char_lit(instream *in)
{
    char tok[64];
    size_t n = 0;
    int c = in_getc(in);
    if (c < 0)
        lisp_error0("unexpected end of text");
    tok[n++] = (char)c;
    while (!is_term(in_peek(in)) && n < sizeof tok - 1)
        tok[n++] = (char)in_getc(in);
    if (n == 1)
        return mkchar((uint8_t)tok[0]);
    int code = char_by_name(tok, n);
    if (code < 0)
        lisp_error0("unknown character name");
    return mkchar(code);
}

static obj read_list(instream *in, int close)
{
    obj head = NIL, tail = NIL;
    for (;;) {
        int c = skip_ws(in);
        if (c < 0)
            lisp_error0("unexpected end of text");
        if (c == close) {
            in_getc(in);
            return head;
        }
        obj x = read_obj(in);
        if (x == CLOSEMARK)
            return head;
        if (x == DOTMARK) {
            if (tail == NIL)
                lisp_error0("syntax error");
            obj d = read_obj(in);
            if (d == CLOSEMARK || d == DOTMARK || d == EOFMARK)
                lisp_error0("syntax error");
            cdr(tail) = d;
            c = skip_ws(in);
            if (c != close)
                lisp_error0("syntax error");
            in_getc(in);
            return head;
        }
        obj cell = cons(x, NIL);
        if (tail == NIL) head = cell; else cdr(tail) = cell;
        tail = cell;
    }
}

static obj read_obj(instream *in)
{
    int c = skip_ws(in);
    if (c < 0)
        return EOFMARK;
    in_getc(in);
    switch (c) {
    case '(':
        return read_list(in, ')');
    case ')':
        return CLOSEMARK;
    case '\'':
        return list2(S_QUOTE, read_obj(in));
    case '`':
        return list2(S_QUASIQUOTE, read_obj(in));
    case ',':
        if (in_peek(in) == '@') {
            in_getc(in);
            return list2(S_UNQUOTE_SPLICING, read_obj(in));
        }
        return list2(S_UNQUOTE, read_obj(in));
    case '"':
        return read_string(in);
    case '#': {
        int d = in_getc(in);
        if (d == '\'')
            return list2(S_FUNCTION, read_obj(in));
        if (d == '\\')
            return read_char_lit(in);
        if (d == '(') {
            obj l = read_list(in, ')');
            int n = lisp_length(l);
            obj v = make_blob(T_VECTOR, (size_t)n * 4);
            for (int i = 0; i < n; i++, l = cdr(l))
                vec_elts(v)[i] = car(l);
            return v;
        }
        if (d == 'x' || d == 'X' || d == 'b' || d == 'B' || d == 'o' || d == 'O') {
            int base = (d == 'x' || d == 'X') ? 16 : (d == 'b' || d == 'B') ? 2 : 8;
            char tok[64];
            size_t n = 0;
            while (!is_term(in_peek(in)) && n < sizeof tok - 1)
                tok[n++] = (char)in_getc(in);
            tok[n] = 0;
            char *end;
            long v = strtol(tok, &end, base);
            if (*end || n == 0)
                lisp_error0("syntax error");
            return mkint(v);
        }
        lisp_error0("syntax error");
    }
    default:
        return read_token(in, c);
    }
}

/* lisp_read: the next object; at the end EOFMARK (eof_error 0: eof_value) */
obj lisp_read(instream *in, int eof_error, obj eof_value)
{
    obj x;
    do
        x = read_obj(in);
    while (x == CLOSEMARK);
    if (x == DOTMARK)
        lisp_error0("syntax error");
    if (x == EOFMARK) {
        if (eof_error)
            lisp_error0("unexpected end of text");
        return eof_value;
    }
    return x;
}

/* lisp_read_top: the REPL's: a stray ")" is passed over, the line not
 * left for more */
obj lisp_read_top(instream *in)
{
    obj x = read_obj(in);
    if (x == CLOSEMARK)
        return EOFMARK;
    if (x == DOTMARK)
        lisp_error0("syntax error");
    return x;
}

/* the next object from s, or EOFMARK; *used the characters it took */
obj read_from_cstr(const char *s, size_t n, size_t *used)
{
    instream in;
    in_init(&in, s, n);
    obj x = lisp_read(&in, 0, EOFMARK);
    if (used)
        *used = in.pos;
    in_free(&in);
    return x;
}

/* only white space and comments left? */
int in_at_end(instream *in)
{
    int (*r)(instream *) = in->refill;
    in->refill = NULL;
    int c = skip_ws(in);
    in->refill = r;
    return c < 0;
}
