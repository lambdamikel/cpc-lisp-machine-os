/* Pocket Lisp -- the library's natives, part 1: printing, values, symbols,
 * list searching (CPC Lisp's lib/streams.asm, lib/lists.asm...). */
#include "lisp.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

obj get_prop(obj s, obj ind, obj dflt);
obj put_prop(obj s, obj ind, obj v);

/* ---- streams: NIL and T the screen; others come later ---- */

typedef struct { sink *s; } outctx;

/* stream_out: a stream argument -> the sink pushed for the call (or none) */
sink *stream_sink(obj stream);
void stream_done(sink *s, obj stream);

static obj f_print(int c, obj *a)
{
    sink *s = stream_sink(c > 1 ? a[1] : NIL);
    newline();
    prin1(a[0]);
    putch(' ');
    stream_done(s, c > 1 ? a[1] : NIL);
    return a[0];
}

static obj f_prin1(int c, obj *a)
{
    sink *s = stream_sink(c > 1 ? a[1] : NIL);
    prin1(a[0]);
    stream_done(s, c > 1 ? a[1] : NIL);
    return a[0];
}

static obj f_princ(int c, obj *a)
{
    sink *s = stream_sink(c > 1 ? a[1] : NIL);
    princ(a[0]);
    stream_done(s, c > 1 ? a[1] : NIL);
    return a[0];
}

static obj f_terpri(int c, obj *a)
{
    sink *s = stream_sink(c > 0 ? a[0] : NIL);
    newline();
    stream_done(s, c > 0 ? a[0] : NIL);
    return NIL;
}

static obj f_fresh_line(int c, obj *a)
{
    sink *s = stream_sink(c > 0 ? a[0] : NIL);
    int was = out->col != 0;
    fresh_line();
    stream_done(s, c > 0 ? a[0] : NIL);
    return bool_obj(was);
}

static obj f_write_string(int c, obj *a)
{
    check_string(a[0]);
    sink *s = stream_sink(c > 1 ? a[1] : NIL);
    princ(a[0]);
    stream_done(s, c > 1 ? a[1] : NIL);
    return a[0];
}

static obj f_write_line(int c, obj *a)
{
    check_string(a[0]);
    sink *s = stream_sink(c > 1 ? a[1] : NIL);
    princ(a[0]);
    newline();
    stream_done(s, c > 1 ? a[1] : NIL);
    return a[0];
}

static obj f_write_char(int c, obj *a)
{
    if (!ischar(a[0]))
        lisp_error("not a character:", a[0]);
    sink *s = stream_sink(c > 1 ? a[1] : NIL);
    putch((int)charval(a[0]));
    stream_done(s, c > 1 ? a[1] : NIL);
    return a[0];
}

/* (write object &key stream escape...) */
static obj f_write(int c, obj *a)
{
    obj stream = NIL;
    int escape = 1;
    for (int i = 1; i + 1 < c; i += 2) {
        if (a[i] == intern_cstr(":STREAM")) stream = a[i + 1];
        else if (a[i] == intern_cstr(":ESCAPE")) escape = a[i + 1] != NIL;
    }
    sink *s = stream_sink(stream);
    print_obj(a[0], escape);
    stream_done(s, stream);
    return a[0];
}

static obj f_prin1_to_string(int c, obj *a)
{
    (void)c;
    sink *s = push_string_sink();
    prin1(a[0]);
    return pop_string_sink(s);
}

static obj f_princ_to_string(int c, obj *a)
{
    (void)c;
    sink *s = push_string_sink();
    princ(a[0]);
    return pop_string_sink(s);
}

/* ---- values ---- */

static obj f_values(int c, obj *a)
{
    if (c == 1) {
        mv_count = 0;
        return a[0];
    }
    int n = c < 63 ? c : 63;
    for (int i = 0; i < n; i++)
        mv_vals[i] = a[i];
    mv_count = n + 1;
    if (c == 0) {
        mv_vals[0] = NIL;
        return NIL;
    }
    return a[0];
}

/* ---- symbols ---- */

static uint32_t gensym_counter = 1;

static obj f_gensym(int c, obj *a)
{
    char buf[64];
    const char *prefix = "G";
    char pbuf[48];
    if (c > 0 && isstring(a[0])) {
        uint32_t n = str_len(a[0]);
        if (n > sizeof pbuf - 1) n = sizeof pbuf - 1;
        memcpy(pbuf, str_chars(a[0]), n);
        pbuf[n] = 0;
        prefix = pbuf;
    }
    snprintf(buf, sizeof buf, "%s%u", prefix, gensym_counter++);
    return make_symbol(mkstr(buf));
}

static obj f_intern(int c, obj *a)
{
    (void)c;
    obj s = check_string(a[0]);
    uint32_t n = str_len(s);
    char *tmp = malloc(n + 1);
    memcpy(tmp, str_chars(s), n);
    obj r = intern(tmp, n);
    free(tmp);
    return r;
}

static obj f_remprop(int c, obj *a)
{
    (void)c;
    obj s = check_sym(a[0]);
    obj prev = NIL;
    for (obj p = SYM(s)->plist; iscons(p) && iscons(cdr(p)); p = cdr(cdr(p))) {
        if (car(p) == a[1]) {
            if (prev == NIL)
                SYM(s)->plist = cdr(cdr(p));
            else
                cdr(cdr(prev)) = cdr(cdr(p));
            return S_T;
        }
        prev = p;
    }
    return NIL;
}

/* ---- lists ---- */

static obj f_reverse(int c, obj *a)
{
    (void)c;
    obj s = a[0];
    if (isstring(s)) {
        uint32_t n = str_len(s);
        obj r = make_blob(T_STRING, n);
        for (uint32_t i = 0; i < n; i++)
            str_chars(r)[i] = str_chars(s)[n - 1 - i];
        return r;
    }
    if (isvector(s)) {
        uint32_t n = vec_len(s);
        obj r = make_blob(T_VECTOR, n * 4);
        for (uint32_t i = 0; i < n; i++)
            vec_elts(r)[i] = vec_elts(s)[n - 1 - i];
        return r;
    }
    obj r = NIL;
    for (obj l = check_list(s); iscons(l); l = cdr(l))
        r = cons(car(l), r);
    return r;
}

static obj f_nreverse(int c, obj *a)
{
    (void)c;
    obj s = a[0];
    if (isstring(s)) {
        char *p = str_chars(s);
        for (uint32_t i = 0, j = str_len(s); i + 1 < j; i++, j--) {
            char t = p[i]; p[i] = p[j - 1]; p[j - 1] = t;
        }
        return s;
    }
    if (isvector(s)) {
        obj *p = vec_elts(s);
        for (uint32_t i = 0, j = vec_len(s); i + 1 < j; i++, j--) {
            obj t = p[i]; p[i] = p[j - 1]; p[j - 1] = t;
        }
        return s;
    }
    return nreverse(check_list(s));
}

static obj f_nreconc(int c, obj *a)
{
    (void)c;
    obj l = check_list(a[0]), r = a[1];
    while (iscons(l)) {
        obj n = cdr(l);
        cdr(l) = r;
        r = l;
        l = n;
    }
    return r;
}

/* keyword arguments :test :test-not :key, from a[from] on */
typedef struct { obj test, test_not, key; int from_end; obj start, end, count; } kwargs;

static void get_kwargs(int c, obj *a, int from, kwargs *k)
{
    k->test = k->test_not = k->key = NIL;
    k->from_end = 0;
    k->start = k->end = k->count = NIL;
    for (int i = from; i + 1 < c; i += 2) {
        obj kw = a[i], v = a[i + 1];
        if (kw == S_KW_TEST) k->test = v;
        else if (kw == S_KW_TEST_NOT) k->test_not = v;
        else if (kw == S_KW_KEY) k->key = v;
        else if (kw == S_KW_FROM_END) k->from_end = v != NIL;
        else if (kw == S_KW_START) k->start = v;
        else if (kw == S_KW_END) k->end = v;
        else if (kw == S_KW_COUNT) k->count = v;
    }
}

static obj keyed(kwargs *k, obj x)
{
    return k->key != NIL ? funcall1(k->key, x) : x;
}

static int matches(kwargs *k, obj item, obj x)
{
    if (k->test != NIL)
        return funcall2(k->test, item, x) != NIL;
    if (k->test_not != NIL)
        return funcall2(k->test_not, item, x) == NIL;
    return eql(item, x);
}

static obj f_member(int c, obj *a)
{
    kwargs k;
    get_kwargs(c, a, 2, &k);
    obj l = check_list(a[1]);
    for (; iscons(l); l = cdr(l))
        if (matches(&k, a[0], keyed(&k, car(l))))
            return l;
    if (l != NIL)
        lisp_error("not a list:", l);
    return NIL;
}

static obj f_assoc(int c, obj *a)
{
    kwargs k;
    get_kwargs(c, a, 2, &k);
    for (obj l = check_list(a[1]); iscons(l); l = cdr(l))
        if (iscons(car(l)) && matches(&k, a[0], keyed(&k, car(car(l)))))
            return car(l);
    return NIL;
}

static obj f_rassoc(int c, obj *a)
{
    kwargs k;
    get_kwargs(c, a, 2, &k);
    for (obj l = check_list(a[1]); iscons(l); l = cdr(l))
        if (iscons(car(l)) && matches(&k, a[0], keyed(&k, cdr(car(l)))))
            return car(l);
    return NIL;
}

/* ---- the system ---- */

static obj f_libdef(int c, obj *a)
{
    (void)c;
    obj s = check_sym(a[0]);
    SYM(s)->flags |= SF_LIBDEF;
    SYM(s)->flags &= ~SF_USERDEF;
    return s;
}

static obj f_time(int c, obj *a)
{
    (void)c; (void)a;
    return mkfix((int32_t)(mach_ticks() & FIX_MAX));
}

static obj f_room(int c, obj *a)
{
    (void)c; (void)a;
    gc();
    char buf[96];
    snprintf(buf, sizeof buf, "%u cells free, %u bytes of strings free",
             cells_free_after_gc, blocks_free());
    fresh_line();
    putstr(buf);
    newline();
    return mkfix(cells_free_after_gc);
}

void init_lib2(void);
void init_seq(void);
void init_format(void);
void init_stubs(void);

void init_lib(void)
{
    defsubr("PRINT", f_print, 1, 2);
    defsubr("PRIN1", f_prin1, 1, 2);
    defsubr("PRINC", f_princ, 1, 2);
    defsubr("TERPRI", f_terpri, 0, 1);
    defsubr("FRESH-LINE", f_fresh_line, 0, 1);
    defsubr("WRITE-STRING", f_write_string, 1, 2);
    defsubr("WRITE-LINE", f_write_line, 1, 2);
    defsubr("WRITE-CHAR", f_write_char, 1, 2);
    defsubr("WRITE", f_write, 1, ANY);
    defsubr("PRIN1-TO-STRING", f_prin1_to_string, 1, 1);
    defsubr("PRINC-TO-STRING", f_princ_to_string, 1, 1);
    defsubr("VALUES", f_values, 0, ANY);
    defsubr("GENSYM", f_gensym, 0, 1);
    defsubr("INTERN", f_intern, 1, 1);
    defsubr("REMPROP", f_remprop, 2, 2);
    defsubr("REVERSE", f_reverse, 1, 1);
    defsubr("NREVERSE", f_nreverse, 1, 1);
    defsubr("NRECONC", f_nreconc, 2, 2);
    defsubr("MEMBER", f_member, 2, ANY);
    defsubr("ASSOC", f_assoc, 2, ANY);
    defsubr("RASSOC", f_rassoc, 2, ANY);
    defsubr("%LIBDEF", f_libdef, 1, 1);
    defsubr("TIME", f_time, 0, 0);
    defsubr("ROOM", f_room, 0, 1);
    init_lib2();
    init_seq();
    init_format();
    init_stubs();
}
