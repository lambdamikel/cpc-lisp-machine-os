/* Pocket Lisp -- format (CPC Lisp's lib/format.asm): CL's directives but
 * ~/name/, with parameters (n, 'c, V, #) and the modifiers : and @;
 * ~{ ~[ ~( ~< recursively. */
#include "lisp.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

void format_float(double d, char *buf);
sink *stream_sink(obj stream);
void stream_done(sink *s, obj stream);

typedef struct {
    obj *v;             /* the arguments */
    int n, pos;
} fargs;

#define MAXP 5
typedef struct {
    int np;
    int has[MAXP];
    int32_t p[MAXP];
    int colon, at;
    char dir;
    size_t start, end;  /* the directive in the control string */
} directive;

static jmp_buf *up_target;      /* ~^ inside ~{: leave the iteration */

static void __attribute__((noreturn)) bad(void) { lisp_error0("bad format directive"); }

static obj next_arg(fargs *A)
{
    if (A->pos >= A->n)
        lisp_error0("too few arguments");
    return A->v[A->pos++];
}

/* parse the directive at ctl[i] (just past the ~) */
static size_t parse_dir(const char *ctl, size_t len, size_t i, fargs *A, directive *d)
{
    memset(d, 0, sizeof *d);
    d->start = i - 1;
    for (;;) {
        if (i >= len) bad();
        char c = ctl[i];
        if (d->np < MAXP && (c == '-' || c == '+' || (c >= '0' && c <= '9'))) {
            int neg = c == '-';
            if (c == '-' || c == '+') i++;
            int32_t v = 0;
            while (i < len && ctl[i] >= '0' && ctl[i] <= '9')
                v = v * 10 + (ctl[i++] - '0');
            d->p[d->np] = neg ? -v : v;
            d->has[d->np] = 1;
        } else if (c == '\'') {
            if (i + 1 >= len) bad();
            d->p[d->np] = (uint8_t)ctl[i + 1];
            d->has[d->np] = 1;
            i += 2;
        } else if (c == 'V' || c == 'v') {
            obj a = next_arg(A);
            if (a != NIL) {
                d->p[d->np] = ischar(a) ? (int32_t)charval(a) : check_int(a);
                d->has[d->np] = 1;
            }
            i++;
        } else if (c == '#') {
            d->p[d->np] = A->n - A->pos;
            d->has[d->np] = 1;
            i++;
        } else if (c == ',') {
            /* an empty parameter */
        } else
            goto mods;
        if (i < len && ctl[i] == ',') {
            d->np++;
            if (d->np >= MAXP) bad();
            i++;
            continue;
        }
        d->np++;
        break;
    }
mods:
    while (i < len && (ctl[i] == ':' || ctl[i] == '@')) {
        if (ctl[i] == ':') d->colon = 1; else d->at = 1;
        i++;
    }
    if (i >= len) bad();
    d->dir = ctl[i];
    if (d->dir >= 'a' && d->dir <= 'z')
        d->dir -= 32;
    d->end = i + 1;
    return i + 1;
}

static int32_t P(directive *d, int k, int32_t dflt) { return k < d->np && d->has[k] ? d->p[k] : dflt; }

/* the closing directive of ~[ ~{ ~( ~< at i, and its ~; separators:
 * seps[] the indices of each clause's start; returns the index past it */
typedef struct { size_t starts[64], ends[64]; int n; int last_colon; directive close; int sep_colon[64]; } clauses;

static size_t skip_params(const char *ctl, size_t len, size_t i)
{
    /* past a directive's parameters and modifiers -> the index of its letter */
    while (i < len) {
        char c = ctl[i];
        if (c == '\'') { i += 2; continue; }
        if ((c >= '0' && c <= '9') || c == ',' || c == '-' || c == '+' || c == 'V'
            || c == 'v' || c == '#' || c == ':' || c == '@') { i++; continue; }
        break;
    }
    return i;
}

static size_t find_clauses(const char *ctl, size_t len, size_t i, char close, clauses *cl)
{
    int depth = 0;
    cl->n = 0;
    cl->starts[0] = i;
    while (i < len) {
        if (ctl[i] != '~') { i++; continue; }
        size_t dstart = i;
        size_t k = skip_params(ctl, len, i + 1);
        if (k >= len) bad();
        char c = ctl[k];
        if (c >= 'a' && c <= 'z') c -= 32;
        int colon = 0;
        for (size_t m = i + 1; m < k; m++)
            if (ctl[m] == ':') colon = 1;
        if (c == '[' || c == '{' || c == '(' || c == '<')
            depth++;
        else if (c == ']' || c == '}' || c == ')' || c == '>') {
            if (depth == 0) {
                if (c != close) bad();
                cl->ends[cl->n] = dstart;
                cl->n++;
                memset(&cl->close, 0, sizeof cl->close);
                cl->close.colon = colon;
                cl->close.dir = c;
                return k + 1;
            }
            depth--;
        } else if (c == ';' && depth == 0) {
            cl->ends[cl->n] = dstart;
            cl->sep_colon[cl->n] = colon;
            cl->n++;
            if (cl->n >= 63) bad();
            cl->starts[cl->n] = k + 1;
        }
        i = k + 1;
    }
    bad();
}

static void run(const char *ctl, size_t len, fargs *A);

/* ---- printing helpers ---- */

static void pad(int n, int c)
{
    while (n-- > 0)
        putch(c);
}

static void put_padded(const char *s, int mincol, int colinc, int minpad, int padc, int left)
{
    int n = (int)strlen(s);
    int padn = minpad;
    if (colinc < 1) colinc = 1;
    while (n + padn < mincol)
        padn += colinc;
    if (left) pad(padn, padc);
    putstr(s);
    if (!left) pad(padn, padc);
}

static char *to_cstr(obj o, int escape)
{
    sink *s = push_string_sink();
    print_obj(o, escape);
    obj str = pop_string_sink(s);
    size_t n = str_len(str);
    char *r = malloc(n + 1);
    memcpy(r, str_chars(str), n);
    r[n] = 0;
    return r;
}

static void fmt_as(directive *d, fargs *A, int escape)
{
    obj a = next_arg(A);
    char *s = (d->colon && a == NIL) ? strdup("()") : to_cstr(a, escape);
    put_padded(s, P(d, 0, 0), P(d, 1, 1), P(d, 2, 0), P(d, 3, ' '), d->at);
    free(s);
}

static void put_int(int64_t v, int base, directive *d, int pfrom)
{
    char digits[80];
    int n = 0;
    uint64_t u = v < 0 ? (uint64_t)(-v) : (uint64_t)v;
    do {
        int x = (int)(u % base);
        digits[n++] = (char)(x < 10 ? '0' + x : 'A' + x - 10);
        u /= base;
    } while (u);
    int commachar = P(d, pfrom + 2, ','), interval = P(d, pfrom + 3, 3);
    char buf[160];
    int k = 0;
    if (v < 0) buf[k++] = '-';
    else if (d->at) buf[k++] = '+';
    for (int i = n - 1; i >= 0; i--) {
        buf[k++] = digits[i];
        if (d->colon && i > 0 && i % interval == 0)
            buf[k++] = (char)commachar;
    }
    buf[k] = 0;
    put_padded(buf, P(d, pfrom, 0), 1, 0, P(d, pfrom + 1, ' '), 1);
}

static void fmt_radix(directive *d, fargs *A, int base, int pfrom)
{
    obj a = next_arg(A);
    if (isfloat(a) && floatval(a) == floor(floatval(a)) && fabs(floatval(a)) < 9e15) {
        put_int((int64_t)floatval(a), base, d, pfrom);
        return;
    }
    if (!isfix(a)) {
        char *s = to_cstr(a, 0);
        put_padded(s, P(d, pfrom, 0), 1, 0, ' ', 1);
        free(s);
        return;
    }
    put_int(fixval(a), base, d, pfrom);
}

static const char *ones[] = {"zero", "one", "two", "three", "four", "five", "six", "seven",
    "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
    "sixteen", "seventeen", "eighteen", "nineteen"};
static const char *tens[] = {"", "", "twenty", "thirty", "forty", "fifty", "sixty",
    "seventy", "eighty", "ninety"};
static const char *ordones[] = {"zeroth", "first", "second", "third", "fourth", "fifth",
    "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth",
    "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth"};
static const char *ordtens[] = {"", "", "twentieth", "thirtieth", "fortieth", "fiftieth",
    "sixtieth", "seventieth", "eightieth", "ninetieth"};

/* words for 0 < n < 1000 into buf; ordinal: the last word an ordinal */
static void words999(int n, char *buf, int ordinal)
{
    char t[128] = "";
    int h = n / 100, r = n % 100;
    if (h) {
        strcat(t, ones[h]);
        strcat(t, r ? " hundred " : (ordinal ? " hundredth" : " hundred"));
    }
    if (r) {
        if (r < 20)
            strcat(t, ordinal ? ordones[r] : ones[r]);
        else {
            if (r % 10) {
                strcat(t, tens[r / 10]);
                strcat(t, "-");
                strcat(t, ordinal ? ordones[r % 10] : ones[r % 10]);
            } else
                strcat(t, ordinal ? ordtens[r / 10] : tens[r / 10]);
        }
    }
    strcat(buf, t);
}

static void english(int64_t v, int ordinal)
{
    char buf[512] = "";
    if (v == 0) {
        putstr(ordinal ? "zeroth" : "zero");
        return;
    }
    if (v < 0) {
        strcat(buf, "negative ");
        v = -v;
    }
    static const char *scale[] = {"", " thousand", " million", " billion", " trillion"};
    int groups[6], ng = 0;
    while (v > 0 && ng < 6) {
        groups[ng++] = (int)(v % 1000);
        v /= 1000;
    }
    int lastnz = 0;
    for (int i = 0; i < ng; i++)
        if (groups[i]) { lastnz = i; break; }
    int first = 1;
    for (int i = ng - 1; i >= 0; i--) {
        if (!groups[i]) continue;
        if (!first) strcat(buf, " ");
        first = 0;
        int ord = ordinal && i == lastnz && i == 0;
        words999(groups[i], buf, ord);
        if (i > 0) {
            strcat(buf, scale[i]);
            if (ordinal && i == lastnz)
                strcat(buf, "th");
        }
    }
    putstr(buf);
}

static void roman(int64_t v, int old)
{
    if (v <= 0 || v >= 4000) {
        char b[24];
        snprintf(b, sizeof b, "%lld", (long long)v);
        putstr(b);
        return;
    }
    static const int vals[] = {1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1};
    static const char *syms[] = {"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"};
    for (int i = 0; i < 13; i++) {
        if (old && (vals[i] == 900 || vals[i] == 400 || vals[i] == 90 || vals[i] == 40
                    || vals[i] == 9 || vals[i] == 4))
            continue;
        while (v >= vals[i]) {
            putstr(syms[i]);
            v -= vals[i];
        }
    }
}

static void fmt_r(directive *d, fargs *A)
{
    if (d->np > 0 && d->has[0]) {
        int base = d->p[0];
        if (base < 2 || base > 36) bad();
        fmt_radix(d, A, base, 1);
        return;
    }
    obj a = next_arg(A);
    int64_t v = isfix(a) ? fixval(a) : (int64_t)num_double(a);
    if (d->at)
        roman(v, d->colon);
    else
        english(v, d->colon);
}

/* fixed point: d digits after the point (-1: as many as it takes) */
static void fixed(double x, int digits, char *buf, size_t sz)
{
    if (digits < 0) {
        char t[64];
        format_float(x, t);
        if (!strchr(t, 'e')) {
            snprintf(buf, sz, "%s", t);
            return;
        }
        for (int prec = 0; prec < 40; prec++) {
            snprintf(buf, sz, "%.*f", prec, x);
            if (strtod(buf, NULL) == x) break;
        }
        if (!strchr(buf, '.'))
            strncat(buf, ".0", sz - strlen(buf) - 1);
        return;
    }
    double scale = pow(10, digits);
    double r = round(x * scale) / scale;    /* halves away from zero */
    snprintf(buf, sz, "%.*f", digits, r);
    if (digits == 0)
        strncat(buf, ".", sz - strlen(buf) - 1);
}

static void fmt_f(directive *d, fargs *A, int has_d)
{
    obj a = next_arg(A);
    if (!isnumber(a)) {
        char *s = to_cstr(a, 0);
        put_padded(s, P(d, 0, 0), 1, 0, ' ', 1);
        free(s);
        return;
    }
    double x = num_double(a);
    char buf[128];
    fixed(x, has_d ? P(d, 1, -1) : -1, buf, sizeof buf);
    char out[140];
    snprintf(out, sizeof out, "%s%s", (d->at && x >= 0) ? "+" : "", buf);
    put_padded(out, P(d, 0, 0), 1, 0, P(d, 4, ' '), 1);
}

static void fmt_dollar(directive *d, fargs *A)
{
    obj a = next_arg(A);
    double x = num_double(a);
    int digits = P(d, 0, 2), mind = P(d, 1, 1), w = P(d, 2, 0), padc = P(d, 3, ' ');
    char buf[128];
    snprintf(buf, sizeof buf, "%.*f", digits, fabs(x));
    int intdigits = (int)(strchr(buf, '.') ? strchr(buf, '.') - buf : (long)strlen(buf));
    char out[200];
    int k = 0;
    if (x < 0) out[k++] = '-';
    else if (d->at) out[k++] = '+';
    for (int i = intdigits; i < mind; i++) out[k++] = '0';
    strcpy(out + k, buf);
    put_padded(out, w, 1, 0, padc, 1);
}

static void fmt_c(directive *d, fargs *A)
{
    obj a = next_arg(A);
    if (!ischar(a))
        lisp_error("not a character:", a);
    if (d->at)
        prin1(a);
    else if (d->colon) {
        extern const char *char_name(int c);
        int c = (int)charval(a);
        const char *nm = (c <= ' ' || c == 127) ? char_name(c) : NULL;
        if (nm) putstr(nm); else putch(c);
    } else
        putch((int)charval(a));
}

/* ---- the control string ---- */

static void case_convert(const char *s, size_t n, directive *d)
{
    int start = 1, first_done = 0;
    for (size_t i = 0; i < n; i++) {
        int c = (uint8_t)s[i];
        int alnum = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
        if (d->colon && d->at)
            c = (c >= 'a' && c <= 'z') ? c - 32 : c;
        else if (d->colon) {
            if (alnum) {
                if (start) c = (c >= 'a' && c <= 'z') ? c - 32 : c;
                else c = (c >= 'A' && c <= 'Z') ? c + 32 : c;
            }
        } else if (d->at) {
            if (alnum && !first_done) {
                c = (c >= 'a' && c <= 'z') ? c - 32 : c;
                first_done = 1;
            } else
                c = (c >= 'A' && c <= 'Z') ? c + 32 : c;
            if (alnum) first_done = 1;
        } else
            c = (c >= 'A' && c <= 'Z') ? c + 32 : c;
        start = !alnum;
        putch(c);
    }
}

/* the text printed by running ctl[a..b) -> a malloc'd string */
static char *capture(const char *ctl, size_t a, size_t b, fargs *A, size_t *n)
{
    sink *s = push_string_sink();
    s->col = out ? 0 : 0;
    run(ctl + a, b - a, A);
    obj str = pop_string_sink(s);
    *n = str_len(str);
    char *r = malloc(*n + 1);
    memcpy(r, str_chars(str), *n);
    r[*n] = 0;
    return r;
}

typedef struct { int up; } upflag;
static upflag *cur_up;

static void iterate(const char *ctl, size_t a, size_t b, directive *d, int at_least_once, fargs *A)
{
    obj body_override = UNBOUND;
    const char *body = ctl + a;
    size_t blen = b - a;
    char *owned = NULL;
    (void)body_override;
    if (blen == 0) {                    /* ~{~}: nothing to do (as CPC Lisp) */
        if (!d->at)
            next_arg(A);
        return;
    }
    int max = P(d, 0, 1 << 30);
    fargs L;
    obj list = NIL;
    if (d->at) {
        L = *A;
    } else {
        list = check_list(next_arg(A));
        int n = lisp_length(list);
        L.v = malloc(sizeof(obj) * (n + 1));
        L.n = n;
        L.pos = 0;
        int i = 0;
        for (obj l = list; iscons(l); l = cdr(l))
            L.v[i++] = car(l);
    }
    int count = 0;
    for (;;) {
        if (count >= max) break;
        if (L.pos >= L.n && !(at_least_once && count == 0)) break;
        count++;
        upflag uf = {0}, *saved = cur_up;
        cur_up = &uf;
        if (d->colon) {
            obj sub = check_list(next_arg(&L));
            int n = lisp_length(sub);
            fargs S;
            S.v = malloc(sizeof(obj) * (n + 1));
            S.n = n;
            S.pos = 0;
            int i = 0;
            for (obj l = sub; iscons(l); l = cdr(l))
                S.v[i++] = car(l);
            run(body, blen, &S);
            free(S.v);
            cur_up = saved;
            if (uf.up == 2) break;      /* ~:^ */
        } else {
            run(body, blen, &L);
            cur_up = saved;
            if (uf.up) break;
        }
    }
    if (d->at)
        A->pos = L.pos;
    else
        free(L.v);
    free(owned);
}

static int line_width(void) { return 80; }

static void justify(const char *ctl, clauses *cl, directive *d, fargs *A)
{
    int mincol = P(d, 0, 0), colinc = P(d, 1, 1), minpad = P(d, 2, 0), padc = P(d, 3, ' ');
    if (colinc < 1) colinc = 1;
    int first = 0;
    char *prefix = NULL;
    size_t prefix_n = 0;
    if (cl->n > 1 && cl->sep_colon[0]) {        /* ~:; the line-overflow prefix */
        prefix = capture(ctl, cl->starts[0], cl->ends[0], A, &prefix_n);
        first = 1;
    }
    int nseg = cl->n - first;
    char **segs = malloc(sizeof(char *) * (nseg + 1));
    size_t *lens = malloc(sizeof(size_t) * (nseg + 1));
    size_t total = 0;
    int kept = 0;
    for (int i = 0; i < nseg; i++) {
        upflag uf = {0}, *saved = cur_up;
        cur_up = &uf;
        segs[kept] = capture(ctl, cl->starts[first + i], cl->ends[first + i], A, &lens[kept]);
        cur_up = saved;
        total += lens[kept];
        kept++;
        if (uf.up) break;
    }
    int gaps = kept - 1 + (d->colon ? 1 : 0) + (d->at ? 1 : 0);
    if (kept == 1 && !d->colon && !d->at)
        gaps = 1;                       /* one segment alone: to the right */
    int need = (int)total + gaps * minpad;
    int width = mincol;
    while (width < need)
        width += colinc;
    int padding = width - (int)total;
    if (prefix && out->col + width > line_width()) {
        for (size_t i = 0; i < prefix_n; i++) putch((uint8_t)prefix[i]);
    }
    int g = 0;
    for (int i = 0; i < kept; i++) {
        int gap_here = (i == 0) ? (d->colon || (kept == 1 && !d->at)) : 1;
        if (gap_here && gaps > 0) {
            int share = padding / gaps + (g < padding % gaps ? 1 : 0);
            pad(share, padc);
            g++;
        }
        for (size_t k = 0; k < lens[i]; k++) putch((uint8_t)segs[i][k]);
        free(segs[i]);
    }
    if (d->at && gaps > 0) {
        int share = padding / gaps + (g < padding % gaps ? 1 : 0);
        pad(share, padc);
    }
    free(segs);
    free(lens);
    free(prefix);
}

static void run(const char *ctl, size_t len, fargs *A)
{
    size_t i = 0;
    while (i < len) {
        char c = ctl[i];
        if (c != '~') {
            putch((uint8_t)c);
            i++;
            continue;
        }
        directive d;
        i = parse_dir(ctl, len, i + 1, A, &d);
        switch (d.dir) {
        case 'A': fmt_as(&d, A, 0); break;
        case 'S': fmt_as(&d, A, 1); break;
        case 'D': fmt_radix(&d, A, 10, 0); break;
        case 'B': fmt_radix(&d, A, 2, 0); break;
        case 'O': fmt_radix(&d, A, 8, 0); break;
        case 'X': fmt_radix(&d, A, 16, 0); break;
        case 'R': fmt_r(&d, A); break;
        case 'F': fmt_f(&d, A, 1); break;
        case 'E': case 'G': fmt_f(&d, A, 0); break;
        case '$': fmt_dollar(&d, A); break;
        case 'C': fmt_c(&d, A); break;
        case 'P': {
            obj a;
            if (d.colon) {
                if (A->pos == 0) bad();
                a = A->v[A->pos - 1];
            } else
                a = next_arg(A);
            int one = isfix(a) && fixval(a) == 1;
            if (d.at) putstr(one ? "y" : "ies");
            else if (!one) putch('s');
            break;
        }
        case '%': for (int k = P(&d, 0, 1); k > 0; k--) newline(); break;
        case '&': {
            int k = P(&d, 0, 1);
            if (k > 0) { fresh_line(); k--; }
            while (k-- > 0) newline();
            break;
        }
        case '|': for (int k = P(&d, 0, 1); k > 0; k--) putch(12); break;
        case '~': for (int k = P(&d, 0, 1); k > 0; k--) putch('~'); break;
        case '\n':
            if (d.at) newline();
            if (!d.colon)
                while (i < len && (ctl[i] == ' ' || ctl[i] == '\t'))
                    i++;
            break;
        case 'T': {
            int colnum = P(&d, 0, 1), colinc = P(&d, 1, 1);
            if (d.at) {
                pad(colnum, ' ');
                if (colinc > 1) {
                    int col = out->col;
                    pad((colinc - col % colinc) % colinc, ' ');
                }
            } else {
                int col = out->col;
                if (col < colnum) pad(colnum - col, ' ');
                else if (colinc > 0) pad(colinc - (col - colnum) % colinc, ' ');
            }
            break;
        }
        case '*': {
            int k = P(&d, 0, d.at ? 0 : 1);
            if (d.at) A->pos = k;
            else if (d.colon) A->pos -= k;
            else A->pos += k;
            if (A->pos < 0 || A->pos > A->n)
                lisp_error0("too few arguments");
            break;
        }
        case '?': {
            obj sub = next_arg(A);
            check_string(sub);
            size_t n = str_len(sub);
            char *copy = malloc(n + 1);
            memcpy(copy, str_chars(sub), n);
            if (d.at)
                run(copy, n, A);
            else {
                obj l = check_list(next_arg(A));
                int m = lisp_length(l);
                fargs S;
                S.v = malloc(sizeof(obj) * (m + 1));
                S.n = m;
                S.pos = 0;
                int k = 0;
                for (; iscons(l); l = cdr(l))
                    S.v[k++] = car(l);
                run(copy, n, &S);
                free(S.v);
            }
            free(copy);
            break;
        }
        case '^': {
            int stop;
            if (d.np >= 2 && d.has[0] && d.has[1]) stop = d.p[0] == d.p[1];
            else if (d.np >= 1 && d.has[0]) stop = d.p[0] == 0;
            else stop = A->pos >= A->n;
            if (stop) {
                if (cur_up) cur_up->up = d.colon ? 2 : 1;
                return;
            }
            break;
        }
        case '(': {
            clauses cl;
            size_t after = find_clauses(ctl, len, i, ')', &cl);
            size_t n;
            char *s = capture(ctl, cl.starts[0], cl.ends[0], A, &n);
            case_convert(s, n, &d);
            free(s);
            i = after;
            break;
        }
        case '[': {
            clauses cl;
            size_t after = find_clauses(ctl, len, i, ']', &cl);
            int has_default = cl.n > 1 && cl.sep_colon[cl.n - 2];
            int pick = -1;
            if (d.colon) {
                pick = next_arg(A) == NIL ? 0 : 1;
            } else if (d.at) {
                if (next_arg(A) != NIL) {
                    A->pos--;
                    pick = 0;
                }
            } else {
                int k = (d.np > 0 && d.has[0]) ? d.p[0] : check_int(next_arg(A));
                int ordinary = has_default ? cl.n - 1 : cl.n;
                if (k >= 0 && k < ordinary)
                    pick = k;
                else if (has_default)
                    pick = cl.n - 1;
            }
            if (pick >= 0 && pick < cl.n) {
                run(ctl + cl.starts[pick], cl.ends[pick] - cl.starts[pick], A);
                if (cur_up && cur_up->up) return;
            }
            i = after;
            break;
        }
        case '{': {
            clauses cl;
            size_t after = find_clauses(ctl, len, i, '}', &cl);
            iterate(ctl, cl.starts[0], cl.ends[cl.n - 1], &d, cl.close.colon, A);
            i = after;
            break;
        }
        case '<': {
            clauses cl;
            size_t after = find_clauses(ctl, len, i, '>', &cl);
            justify(ctl, &cl, &d, A);
            i = after;
            break;
        }
        default:
            bad();
        }
    }
}

/* (format destination control arg...) */
static obj f_format(int c, obj *a)
{
    obj dest = a[0];
    obj ctl = check_string(a[1]);
    size_t n = str_len(ctl);
    char *copy = malloc(n + 1);
    memcpy(copy, str_chars(ctl), n);
    fargs A = { a + 2, c - 2, 0 };
    upflag *saved = cur_up;
    cur_up = NULL;
    if (dest == NIL) {
        sink *s = push_string_sink();
        extern int out_col;
        run(copy, n, &A);
        free(copy);
        cur_up = saved;
        return pop_string_sink(s);
    }
    obj stream = dest == S_T ? NIL : dest;
    sink *s = stream_sink(stream);
    run(copy, n, &A);
    stream_done(s, stream);
    free(copy);
    cur_up = saved;
    return NIL;
}

void init_format(void)
{
    defsubr("FORMAT", f_format, 2, ANY);
}
