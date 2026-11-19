/* Pocket Lisp -- the library's natives, part 2: characters and strings,
 * sequences, arrays, structures, hash tables, coerce (CPC Lisp's
 * lib/strings.asm, lib/seqfn.asm, lib/seq.asm, lib/structs.asm,
 * lib/lists.asm). */
#include "lisp.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

obj seq_ref(obj seq, obj i);

static int upc(int c) { return (c >= 'a' && c <= 'z') ? c - 32 : c; }
static int lowc(int c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }

static int check_char(obj o)
{
    if (!ischar(o))
        lisp_error("not a character:", o);
    return (int)charval(o);
}

/* a copy of a string's characters in C memory (it may move) */
static char *cstr_copy(obj s, uint32_t *n)
{
    *n = str_len(s);
    char *p = malloc(*n + 1);
    memcpy(p, str_chars(s), *n);
    p[*n] = 0;
    return p;
}

/* ---- characters ---- */

static obj f_char_upcase(int c, obj *a) { (void)c; return mkchar(upc(check_char(a[0]))); }
static obj f_char_downcase(int c, obj *a) { (void)c; return mkchar(lowc(check_char(a[0]))); }
static obj f_upper_case_p(int c, obj *a) { (void)c; int x = check_char(a[0]); return bool_obj(x >= 'A' && x <= 'Z'); }
static obj f_lower_case_p(int c, obj *a) { (void)c; int x = check_char(a[0]); return bool_obj(x >= 'a' && x <= 'z'); }
static obj f_alpha_char_p(int c, obj *a) { (void)c; int x = check_char(a[0]); return bool_obj(isalpha(x) && x < 128); }
static obj f_both_case_p(int c, obj *a) { return f_alpha_char_p(c, a); }
static obj f_alphanumericp(int c, obj *a) { (void)c; int x = check_char(a[0]); return bool_obj(isalnum(x) && x < 128); }
static obj f_graphic_char_p(int c, obj *a) { (void)c; int x = check_char(a[0]); return bool_obj(x >= 32 && x != 127); }

static obj f_digit_char_p(int c, obj *a)
{
    int x = check_char(a[0]);
    int radix = c > 1 ? check_int(a[1]) : 10;
    int w = (x >= '0' && x <= '9') ? x - '0' : (x >= 'a' && x <= 'z') ? x - 'a' + 10
        : (x >= 'A' && x <= 'Z') ? x - 'A' + 10 : 99;
    return w < radix ? mkfix(w) : NIL;
}

static obj f_digit_char(int c, obj *a)
{
    int w = check_int(a[0]);
    int radix = c > 1 ? check_int(a[1]) : 10;
    if (w < 0 || w >= radix)
        return NIL;
    return mkchar(w < 10 ? '0' + w : 'A' + w - 10);
}

static obj f_code_char(int c, obj *a)
{
    (void)c;
    int n = check_int(a[0]);
    if (n < 0 || n > 255)
        lisp_error("index out of range", a[0]);
    return mkchar(n);
}

/* char= char< ...: op 0 =, 1 /=, 2 <, 3 >, 4 <=, 5 >=; fold: case ignored */
static obj char_compare(int c, obj *a, int op, int fold)
{
    for (int i = 0; i < c; i++)
        check_char(a[i]);
    if (op == 1) {
        for (int i = 0; i < c; i++)
            for (int j = i + 1; j < c; j++) {
                int x = (int)charval(a[i]), y = (int)charval(a[j]);
                if (fold) { x = upc(x); y = upc(y); }
                if (x == y)
                    return NIL;
            }
        return S_T;
    }
    for (int i = 0; i + 1 < c; i++) {
        int x = (int)charval(a[i]), y = (int)charval(a[i + 1]);
        if (fold) { x = upc(x); y = upc(y); }
        int ok = op == 0 ? x == y : op == 2 ? x < y : op == 3 ? x > y : op == 4 ? x <= y : x >= y;
        if (!ok)
            return NIL;
    }
    return S_T;
}

#define CHARCMP(nm, op, fold) static obj nm(int c, obj *a) { return char_compare(c, a, op, fold); }
CHARCMP(f_char_eq, 0, 0) CHARCMP(f_char_ne, 1, 0) CHARCMP(f_char_lt, 2, 0)
CHARCMP(f_char_gt, 3, 0) CHARCMP(f_char_le, 4, 0) CHARCMP(f_char_ge, 5, 0)
CHARCMP(f_char_equal, 0, 1) CHARCMP(f_char_not_equal, 1, 1) CHARCMP(f_char_lessp, 2, 1)
CHARCMP(f_char_greaterp, 3, 1) CHARCMP(f_char_not_greaterp, 4, 1) CHARCMP(f_char_not_lessp, 5, 1)

/* ---- strings ---- */

static obj string_case(obj s, int how)
{
    s = string_designator(s);
    uint32_t n = str_len(s);
    obj r = make_blob(T_STRING, n);
    const char *src = str_chars(s);
    char *d = str_chars(r);
    int start = 1;
    for (uint32_t i = 0; i < n; i++) {
        int ch = (uint8_t)src[i];
        if (how == 0) ch = upc(ch);
        else if (how == 1) ch = lowc(ch);
        else {
            ch = start ? upc(ch) : lowc(ch);
            start = !isalnum(ch);
        }
        d[i] = (char)ch;
    }
    return r;
}

static obj f_string_upcase(int c, obj *a) { (void)c; return string_case(a[0], 0); }
static obj f_string_downcase(int c, obj *a) { (void)c; return string_case(a[0], 1); }
static obj f_string_capitalize(int c, obj *a) { (void)c; return string_case(a[0], 2); }

/* compare two strings -> <0, 0, >0; *mismatch the first index that differs */
static int str_compare(obj x, obj y, int fold, uint32_t *mismatch)
{
    x = string_designator(x);
    y = string_designator(y);
    uint32_t nx = str_len(x), ny = str_len(y);
    const char *p = str_chars(x), *q = str_chars(y);
    uint32_t i = 0;
    for (; i < nx && i < ny; i++) {
        int a = (uint8_t)p[i], b = (uint8_t)q[i];
        if (fold) { a = upc(a); b = upc(b); }
        if (a != b) {
            *mismatch = i;
            return a - b;
        }
    }
    *mismatch = i;
    return nx == ny ? 0 : nx < ny ? -1 : 1;
}

static obj string_cmp(obj *a, int op, int fold)
{
    uint32_t m;
    int r = str_compare(a[0], a[1], fold, &m);
    int ok = op == 0 ? r == 0 : op == 1 ? r != 0 : op == 2 ? r < 0 : op == 3 ? r > 0
        : op == 4 ? r <= 0 : r >= 0;
    if (!ok)
        return NIL;
    return op == 0 ? S_T : mkfix(m);
}

#define STRCMP(nm, op, fold) static obj nm(int c, obj *a) { (void)c; return string_cmp(a, op, fold); }
STRCMP(f_string_eq, 0, 0) STRCMP(f_string_ne, 1, 0) STRCMP(f_string_lt, 2, 0)
STRCMP(f_string_gt, 3, 0) STRCMP(f_string_le, 4, 0) STRCMP(f_string_ge, 5, 0)
STRCMP(f_string_equal, 0, 1) STRCMP(f_string_not_equal, 1, 1) STRCMP(f_string_lessp, 2, 1)
STRCMP(f_string_greaterp, 3, 1) STRCMP(f_string_not_greaterp, 4, 1) STRCMP(f_string_not_lessp, 5, 1)

static int in_bag(obj bag, int ch)
{
    if (isstring(bag)) {
        for (uint32_t i = 0; i < str_len(bag); i++)
            if ((uint8_t)str_chars(bag)[i] == ch)
                return 1;
        return 0;
    }
    for (obj l = bag; iscons(l); l = cdr(l))
        if (ischar(car(l)) && (int)charval(car(l)) == ch)
            return 1;
    if (isvector(bag))
        for (uint32_t i = 0; i < vec_len(bag); i++)
            if (ischar(vec_elts(bag)[i]) && (int)charval(vec_elts(bag)[i]) == ch)
                return 1;
    return 0;
}

static obj string_trim(obj bag, obj s, int left, int right)
{
    s = string_designator(s);
    uint32_t n;
    char *p = cstr_copy(s, &n);
    uint32_t i = 0, j = n;
    if (left)
        while (i < j && in_bag(bag, (uint8_t)p[i]))
            i++;
    if (right)
        while (j > i && in_bag(bag, (uint8_t)p[j - 1]))
            j--;
    obj r = mkstring(p + i, j - i);
    free(p);
    return r;
}

static obj f_string_trim(int c, obj *a) { (void)c; return string_trim(a[0], a[1], 1, 1); }
static obj f_string_left_trim(int c, obj *a) { (void)c; return string_trim(a[0], a[1], 1, 0); }
static obj f_string_right_trim(int c, obj *a) { (void)c; return string_trim(a[0], a[1], 0, 1); }

static obj f_make_string(int c, obj *a)
{
    int32_t n = check_int(a[0]);
    int ch = ' ';
    for (int i = 1; i + 1 < c; i += 2)
        if (a[i] == S_KW_INITIAL_ELEMENT)
            ch = check_char(a[i + 1]);
    if (n < 0)
        lisp_error("index out of range", a[0]);
    obj r = make_blob(T_STRING, (size_t)n);
    memset(str_chars(r), ch, (size_t)n);
    return r;
}

static obj f_subseq_string(int c, obj *a)
{
    obj s = check_string(a[0]);
    uint32_t n = str_len(s);
    int32_t start = check_int(a[1]);
    int32_t end = (c > 2 && a[2] != NIL) ? check_int(a[2]) : (int32_t)n;
    if (start < 0 || end > (int32_t)n || start > end)
        lisp_error("index out of range", start < 0 || start > end ? a[1] : a[2]);
    uint32_t len;
    char *p = cstr_copy(s, &len);
    obj r = mkstring(p + start, (size_t)(end - start));
    free(p);
    return r;
}

static obj f_concatenate_strings(int c, obj *a)
{
    size_t total = 0;
    for (int i = 1; i < c; i++)
        total += str_len(check_string(a[i]));
    obj r = make_blob(T_STRING, total);
    size_t k = 0;
    for (int i = 1; i < c; i++) {
        uint32_t n = str_len(a[i]);
        memcpy(str_chars(r) + k, str_chars(a[i]), n);
        k += n;
    }
    return r;
}

static obj f_parse_integer(int c, obj *a)
{
    (void)c;
    obj s = check_string(a[0]);
    uint32_t n;
    char *p = cstr_copy(s, &n);
    uint32_t i = 0;
    while (i < n && isspace((uint8_t)p[i]))
        i++;
    int neg = 0;
    if (i < n && (p[i] == '+' || p[i] == '-')) {
        neg = p[i] == '-';
        i++;
    }
    uint32_t d0 = i;
    int64_t v = 0;
    while (i < n && isdigit((uint8_t)p[i]))
        v = v * 10 + (p[i++] - '0');
    while (i < n && isspace((uint8_t)p[i]))
        i++;
    int bad = i == d0 || i != n;
    free(p);
    if (bad)
        return NIL;
    return mkint(neg ? -v : v);
}

static obj f_read_from_string(int c, obj *a)
{
    (void)c;
    obj s = check_string(a[0]);
    uint32_t n;
    char *p = cstr_copy(s, &n);
    size_t used;
    obj x = read_from_cstr(p, n, &used);
    free(p);
    (void)used;
    if (x == EOFMARK)
        lisp_error0("unexpected end of text");
    return x;
}

/* ---- sequences: worked on as a C array of their elements ---- */

typedef struct { obj *v; int n; int kind; } seqv;   /* kind 0 list, 1 vector, 2 string */

static void seq_get(obj s, seqv *q)
{
    if (isstring(s)) {
        q->kind = 2;
        q->n = (int)str_len(s);
        q->v = malloc(sizeof(obj) * (q->n + 1));
        for (int i = 0; i < q->n; i++)
            q->v[i] = mkchar((uint8_t)str_chars(s)[i]);
    } else if (isvector(s)) {
        q->kind = 1;
        q->n = (int)vec_len(s);
        q->v = malloc(sizeof(obj) * (q->n + 1));
        memcpy(q->v, vec_elts(s), sizeof(obj) * q->n);
    } else {
        if (!listp(s))
            lisp_error("not a sequence:", s);
        q->kind = 0;
        q->n = lisp_length(s);
        q->v = malloc(sizeof(obj) * (q->n + 1));
        int i = 0;
        for (obj l = s; iscons(l); l = cdr(l))
            q->v[i++] = car(l);
    }
}

/* the elements v[0..n) as a sequence of the kind */
static obj seq_make(obj *v, int n, int kind)
{
    if (kind == 2) {
        obj r = make_blob(T_STRING, (size_t)n);
        for (int i = 0; i < n; i++) {
            if (!ischar(v[i]))
                lisp_error("not a character:", v[i]);
            str_chars(r)[i] = (char)charval(v[i]);
        }
        return r;
    }
    if (kind == 1) {
        obj r = make_blob(T_VECTOR, (size_t)n * 4);
        memcpy(vec_elts(r), v, (size_t)n * 4);
        return r;
    }
    obj l = NIL;
    for (int i = n - 1; i >= 0; i--)
        l = cons(v[i], l);
    return l;
}

typedef struct { obj test, test_not, key, start, end, count; int from_end; } kw;

static void get_kw(int c, obj *a, int from, kw *k)
{
    k->test = k->test_not = k->key = k->start = k->end = k->count = NIL;
    k->from_end = 0;
    for (int i = from; i + 1 < c; i += 2) {
        obj x = a[i], v = a[i + 1];
        if (x == S_KW_TEST) k->test = v;
        else if (x == S_KW_TEST_NOT) k->test_not = v;
        else if (x == S_KW_KEY) k->key = v;
        else if (x == S_KW_START) k->start = v;
        else if (x == S_KW_END) k->end = v;
        else if (x == S_KW_COUNT) k->count = v;
        else if (x == S_KW_FROM_END) k->from_end = v != NIL;
    }
}

/* does element x match? mode 0: item (test), 1: if pred, 2: if-not pred */
static int hit(kw *k, int mode, obj item, obj x)
{
    if (k->key != NIL)
        x = funcall1(k->key, x);
    if (mode == 1)
        return funcall1(item, x) != NIL;
    if (mode == 2)
        return funcall1(item, x) == NIL;
    if (k->test != NIL)
        return funcall2(k->test, item, x) != NIL;
    if (k->test_not != NIL)
        return funcall2(k->test_not, item, x) == NIL;
    return eql(item, x);
}

static void bounds(kw *k, int n, int *s, int *e)
{
    *s = k->start != NIL ? check_int(k->start) : 0;
    *e = k->end != NIL ? check_int(k->end) : n;
    if (*s < 0 || *e > n || *s > *e)
        lisp_error("index out of range", k->start != NIL ? k->start : mkfix(*e));
}

/* find, position, count: what 0 find, 1 position, 2 count */
static obj find_common(int c, obj *a, int mode, int what)
{
    kw k;
    get_kw(c, a, 2, &k);
    seqv q;
    seq_get(a[1], &q);
    int s, e;
    bounds(&k, q.n, &s, &e);
    obj r = what == 2 ? mkfix(0) : NIL;
    int cnt = 0;
    if (k.from_end && what != 2) {
        for (int i = e - 1; i >= s; i--)
            if (hit(&k, mode, a[0], q.v[i])) {
                r = what == 0 ? q.v[i] : mkfix(i);
                break;
            }
    } else {
        for (int i = s; i < e; i++)
            if (hit(&k, mode, a[0], q.v[i])) {
                if (what == 2) { cnt++; continue; }
                r = what == 0 ? q.v[i] : mkfix(i);
                break;
            }
        if (what == 2)
            r = mkfix(cnt);
    }
    free(q.v);
    return r;
}

#define FINDFN(nm, mode, what) static obj nm(int c, obj *a) { return find_common(c, a, mode, what); }
FINDFN(f_find, 0, 0) FINDFN(f_find_if, 1, 0) FINDFN(f_find_if_not, 2, 0)
FINDFN(f_position, 0, 1) FINDFN(f_position_if, 1, 1) FINDFN(f_position_if_not, 2, 1)
FINDFN(f_count, 0, 2) FINDFN(f_count_if, 1, 2) FINDFN(f_count_if_not, 2, 2)

/* remove and its kin; with a new element, substitute and its kin */
static obj remove_common(int c, obj *a, int mode, int subst)
{
    int off = subst ? 1 : 0;
    obj item = a[off], seq = a[off + 1];
    kw k;
    get_kw(c, a, off + 2, &k);
    seqv q;
    seq_get(seq, &q);
    int s, e;
    bounds(&k, q.n, &s, &e);
    int limit = k.count != NIL ? check_int(k.count) : -1;
    char *mark = calloc(q.n + 1, 1);
    int done = 0;
    if (k.from_end) {
        for (int i = e - 1; i >= s && (limit < 0 || done < limit); i--)
            if (hit(&k, mode, item, q.v[i])) { mark[i] = 1; done++; }
    } else {
        for (int i = s; i < e && (limit < 0 || done < limit); i++)
            if (hit(&k, mode, item, q.v[i])) { mark[i] = 1; done++; }
    }
    int m = 0;
    for (int i = 0; i < q.n; i++) {
        if (mark[i]) {
            if (subst)
                q.v[m++] = a[0];
        } else
            q.v[m++] = q.v[i];
    }
    obj r = (done == 0 && !subst) ? seq : seq_make(q.v, m, q.kind);
    free(mark);
    free(q.v);
    return r;
}

#define REMFN(nm, mode, sub) static obj nm(int c, obj *a) { return remove_common(c, a, mode, sub); }
REMFN(f_remove, 0, 0) REMFN(f_remove_if, 1, 0) REMFN(f_remove_if_not, 2, 0)
REMFN(f_substitute, 0, 1) REMFN(f_substitute_if, 1, 1) REMFN(f_substitute_if_not, 2, 1)

static obj f_nsubstitute(int c, obj *a)
{
    obj r = remove_common(c, a, 0, 1);
    obj seq = a[2];
    if (iscons(seq)) {          /* in place, as CL allows */
        obj l = seq;
        for (obj m = r; iscons(m) && iscons(l); m = cdr(m), l = cdr(l))
            car(l) = car(m);
        return seq;
    }
    return r;
}

/* sort: a merge sort, stable, of the elements; lists sorted in place */
static obj sort_pred, sort_key;

static int sort_less(obj x, obj y)
{
    if (sort_key != NIL) {
        x = funcall1(sort_key, x);
        y = funcall1(sort_key, y);
    }
    return funcall2(sort_pred, x, y) != NIL;
}

static void merge_sort(obj *v, obj *tmp, int n)
{
    if (n < 2)
        return;
    int h = n / 2;
    merge_sort(v, tmp, h);
    merge_sort(v + h, tmp, n - h);
    int i = 0, j = h, k = 0;
    while (i < h && j < n)
        tmp[k++] = sort_less(v[j], v[i]) ? v[j++] : v[i++];
    while (i < h) tmp[k++] = v[i++];
    while (j < n) tmp[k++] = v[j++];
    memcpy(v, tmp, sizeof(obj) * n);
}

static obj f_sort(int c, obj *a)
{
    obj saved_p = sort_pred, saved_k = sort_key;
    sort_pred = coerce_fn(a[1]);
    sort_key = NIL;
    for (int i = 2; i < c; i += 2) {
        if (a[i] != S_KW_KEY || i + 1 >= c) {
            sort_pred = saved_p;
            lisp_error0("sort: :key only");
        }
        sort_key = a[i + 1];
    }
    if (!listp(a[0]) && !isvector(a[0]) && !isstring(a[0]))
        lisp_error("not a list:", a[0]);
    seqv q;
    seq_get(a[0], &q);
    obj *tmp = malloc(sizeof(obj) * (q.n + 1));
    merge_sort(q.v, tmp, q.n);
    free(tmp);
    obj r;
    if (q.kind == 0) {
        int i = 0;
        for (obj l = a[0]; iscons(l); l = cdr(l))
            car(l) = q.v[i++];
        r = a[0];
    } else if (q.kind == 1) {
        memcpy(vec_elts(a[0]), q.v, sizeof(obj) * q.n);
        r = a[0];
    } else {
        for (int i = 0; i < q.n; i++)
            str_chars(a[0])[i] = (char)charval(q.v[i]);
        r = a[0];
    }
    free(q.v);
    sort_pred = saved_p;
    sort_key = saved_k;
    return r;
}

/* ---- coerce, arrays ---- */

static obj f_coerce(int c, obj *a)
{
    (void)c;
    obj x = a[0], t = a[1];
    const char *tn = issym(t) ? str_chars(SYM(t)->name) : "";
    uint32_t tl = issym(t) ? str_len(SYM(t)->name) : 0;
#define TIS(s) (tl == sizeof(s) - 1 && !memcmp(tn, s, tl))
    if (TIS("LIST") || TIS("VECTOR") || TIS("SIMPLE-VECTOR") || TIS("STRING")
        || TIS("SIMPLE-STRING")) {
        int kind = TIS("LIST") ? 0 : (TIS("STRING") || TIS("SIMPLE-STRING")) ? 2 : 1;
        if ((kind == 0 && listp(x)) || (kind == 1 && isvector(x)) || (kind == 2 && isstring(x)))
            return x;
        if (kind == 2 && ischar(x))
            return string_designator(x);
        seqv q;
        seq_get(x, &q);
        obj r = seq_make(q.v, q.n, kind);
        free(q.v);
        return r;
    }
    if (TIS("CHARACTER")) {
        if (ischar(x)) return x;
        if (isstring(x) && str_len(x) == 1) return mkchar((uint8_t)str_chars(x)[0]);
        if (issym(x) && str_len(SYM(x)->name) == 1) return mkchar((uint8_t)str_chars(SYM(x)->name)[0]);
        lisp_error("not a character:", x);
    }
    if (TIS("FLOAT") || TIS("SINGLE-FLOAT") || TIS("DOUBLE-FLOAT") || TIS("REAL"))
        return mkfloat(num_double(x));
    if (TIS("T"))
        return x;
#undef TIS
    lisp_error("cannot coerce to", t);
}

static obj f_make_array(int c, obj *a)
{
    obj dims = a[0];
    if (iscons(dims))
        dims = car(dims);
    int32_t n = check_int(dims);
    if (n < 0)
        lisp_error("index out of range", a[0]);
    obj init = NIL;
    int string = 0;
    for (int i = 1; i + 1 < c; i += 2) {
        if (a[i] == S_KW_INITIAL_ELEMENT)
            init = a[i + 1];
        else if (a[i] == intern_cstr(":ELEMENT-TYPE")) {
            obj t = a[i + 1];
            if (issym(t) && (t == intern_cstr("CHARACTER") || t == intern_cstr("BASE-CHAR")))
                string = 1;
        }
    }
    if (string) {
        obj r = make_blob(T_STRING, (size_t)n);
        memset(str_chars(r), ischar(init) ? (int)charval(init) : ' ', (size_t)n);
        return r;
    }
    obj r = make_blob(T_VECTOR, (size_t)n * 4);
    for (int i = 0; i < n; i++)
        vec_elts(r)[i] = init;
    return r;
}

static obj f_vector(int c, obj *a)
{
    obj r = make_blob(T_VECTOR, (size_t)c * 4);
    memcpy(vec_elts(r), a, (size_t)c * 4);
    return r;
}

/* ---- structures ---- */

static obj f_make_struct(int c, obj *a)
{
    obj r = make_blob(T_STRUCT, (size_t)c * 4);
    memcpy(vec_elts(r), a, (size_t)c * 4);
    return r;
}

static obj check_struct(obj s, obj type)
{
    if (!isstruct(s) || vec_elts(s)[0] != type)
        lisp_error("not the structure it should be:", s);
    return s;
}

static obj f_struct_ref(int c, obj *a)
{
    (void)c;
    obj s = check_struct(a[0], a[2]);
    int32_t i = check_int(a[1]);
    if (i < 1 || (uint32_t)i >= vec_len(s))
        lisp_error("index out of range", a[1]);
    return vec_elts(s)[i];
}

static obj f_struct_set(int c, obj *a)
{
    (void)c;
    obj s = check_struct(a[0], a[3]);
    int32_t i = check_int(a[1]);
    if (i < 1 || (uint32_t)i >= vec_len(s))
        lisp_error("index out of range", a[1]);
    vec_elts(s)[i] = a[2];
    return a[2];
}

static obj f_struct_is(int c, obj *a)
{
    (void)c;
    return bool_obj(isstruct(a[0]) && vec_elts(a[0])[0] == a[1]);
}

static obj f_struct_type(int c, obj *a)
{
    (void)c;
    return isstruct(a[0]) ? vec_elts(a[0])[0] : NIL;
}

static obj f_copy_structure(int c, obj *a)
{
    (void)c;
    if (!isstruct(a[0]))
        lisp_error("not the structure it should be:", a[0]);
    uint32_t n = vec_len(a[0]);
    obj r = make_blob(T_STRUCT, n * 4);
    memcpy(vec_elts(r), vec_elts(a[0]), n * 4);
    return r;
}

/* ---- hashing ---- */

static uint32_t hash_bytes(const char *s, uint32_t n)
{
    uint32_t h = 5381;
    for (uint32_t i = 0; i < n; i++)
        h = h * 33 + (uint8_t)s[i];
    return h;
}

static uint32_t sxhash(obj x, int depth)
{
    if (isstring(x))
        return hash_bytes(str_chars(x), str_len(x));
    if (isfloat(x)) {
        double d = floatval(x);
        return hash_bytes((const char *)&d, 8);
    }
    if (iscons(x)) {
        if (depth > 4)
            return 17;
        return sxhash(car(x), depth + 1) * 31 + sxhash(cdr(x), depth + 1);
    }
    return x * 2654435761u;
}

static obj f_sxhash(int c, obj *a) { (void)c; return mkfix((int32_t)(sxhash(a[0], 0) & 0x3FFFFFFF)); }

static obj f_eqhash(int c, obj *a)
{
    (void)c;
    obj x = a[0];
    uint32_t h = isfloat(x) ? sxhash(x, 0) : x * 2654435761u;
    return mkfix((int32_t)(h & 0x3FFFFFFF));
}

static obj S_HASH_TABLE, S_EQ, S_EQUAL;

static obj check_table(obj h)
{
    if (!isstruct(h) || vec_elts(h)[0] != S_HASH_TABLE)
        lisp_error("not a hash table:", h);
    return h;
}

static int key_eq(obj test, obj a, obj b)
{
    if (test == S_EQ)
        return a == b;
    if (test == S_EQUAL)
        return equal(a, b);
    return eql(a, b);
}

/* the bucket's index for key in h */
static uint32_t bucket_of(obj h, obj key)
{
    obj test = vec_elts(h)[1];
    obj buckets = vec_elts(h)[3];
    uint32_t n = vec_len(buckets);
    uint32_t hv = test == S_EQUAL ? sxhash(key, 0) : (isfloat(key) ? sxhash(key, 0) : key * 2654435761u);
    return (hv & 0x3FFFFFFF) % n;
}

static obj f_gethash(int c, obj *a)
{
    obj h = check_table(a[1]);
    obj test = vec_elts(h)[1];
    uint32_t b = bucket_of(h, a[0]);
    for (obj l = vec_elts(vec_elts(h)[3])[b]; iscons(l); l = cdr(l))
        if (key_eq(test, car(car(l)), a[0])) {
            mv_vals[0] = cdr(car(l));
            mv_vals[1] = S_T;
            mv_count = 3;
            return mv_vals[0];
        }
    mv_vals[0] = c > 2 ? a[2] : NIL;
    mv_vals[1] = NIL;
    mv_count = 3;
    return mv_vals[0];
}

static obj f_puthash(int c, obj *a)
{
    obj key = a[0], h = check_table(a[1]);
    obj v = a[c - 1];
    obj test = vec_elts(h)[1];
    uint32_t b = bucket_of(h, key);
    for (obj l = vec_elts(vec_elts(h)[3])[b]; iscons(l); l = cdr(l))
        if (key_eq(test, car(car(l)), key)) {
            cdr(car(l)) = v;
            return v;
        }
    obj e = cons(cons(key, v), NIL);
    obj *bk = &vec_elts(vec_elts(h)[3])[b];
    cdr(e) = *bk;
    vec_elts(vec_elts(h)[3])[b] = e;
    vec_elts(h)[2] = mkfix(fixval(vec_elts(h)[2]) + 1);
    return v;
}

static obj f_remhash(int c, obj *a)
{
    (void)c;
    obj h = check_table(a[1]);
    obj test = vec_elts(h)[1];
    uint32_t b = bucket_of(h, a[0]);
    obj prev = NIL;
    for (obj l = vec_elts(vec_elts(h)[3])[b]; iscons(l); l = cdr(l)) {
        if (key_eq(test, car(car(l)), a[0])) {
            if (prev == NIL)
                vec_elts(vec_elts(h)[3])[b] = cdr(l);
            else
                cdr(prev) = cdr(l);
            vec_elts(h)[2] = mkfix(fixval(vec_elts(h)[2]) - 1);
            return S_T;
        }
        prev = l;
    }
    return NIL;
}

void init_seq(void)
{
    S_HASH_TABLE = intern_cstr("HASH-TABLE");
    S_EQ = intern_cstr("EQ");
    S_EQUAL = intern_cstr("EQUAL");
    defsubr("CHAR-UPCASE", f_char_upcase, 1, 1);
    defsubr("CHAR-DOWNCASE", f_char_downcase, 1, 1);
    defsubr("UPPER-CASE-P", f_upper_case_p, 1, 1);
    defsubr("LOWER-CASE-P", f_lower_case_p, 1, 1);
    defsubr("ALPHA-CHAR-P", f_alpha_char_p, 1, 1);
    defsubr("BOTH-CASE-P", f_both_case_p, 1, 1);
    defsubr("ALPHANUMERICP", f_alphanumericp, 1, 1);
    defsubr("GRAPHIC-CHAR-P", f_graphic_char_p, 1, 1);
    defsubr("DIGIT-CHAR-P", f_digit_char_p, 1, 2);
    defsubr("DIGIT-CHAR", f_digit_char, 1, 2);
    defsubr("CODE-CHAR", f_code_char, 1, 1);
    defsubr("CHAR=", f_char_eq, 1, ANY);
    defsubr("CHAR/=", f_char_ne, 1, ANY);
    defsubr("CHAR<", f_char_lt, 1, ANY);
    defsubr("CHAR>", f_char_gt, 1, ANY);
    defsubr("CHAR<=", f_char_le, 1, ANY);
    defsubr("CHAR>=", f_char_ge, 1, ANY);
    defsubr("CHAR-EQUAL", f_char_equal, 1, ANY);
    defsubr("CHAR-NOT-EQUAL", f_char_not_equal, 1, ANY);
    defsubr("CHAR-LESSP", f_char_lessp, 1, ANY);
    defsubr("CHAR-GREATERP", f_char_greaterp, 1, ANY);
    defsubr("CHAR-NOT-GREATERP", f_char_not_greaterp, 1, ANY);
    defsubr("CHAR-NOT-LESSP", f_char_not_lessp, 1, ANY);
    defsubr("STRING-UPCASE", f_string_upcase, 1, 1);
    defsubr("STRING-DOWNCASE", f_string_downcase, 1, 1);
    defsubr("STRING-CAPITALIZE", f_string_capitalize, 1, 1);
    defsubr("STRING=", f_string_eq, 2, 2);
    defsubr("STRING/=", f_string_ne, 2, 2);
    defsubr("STRING<", f_string_lt, 2, 2);
    defsubr("STRING>", f_string_gt, 2, 2);
    defsubr("STRING<=", f_string_le, 2, 2);
    defsubr("STRING>=", f_string_ge, 2, 2);
    defsubr("STRING-EQUAL", f_string_equal, 2, 2);
    defsubr("STRING-NOT-EQUAL", f_string_not_equal, 2, 2);
    defsubr("STRING-LESSP", f_string_lessp, 2, 2);
    defsubr("STRING-GREATERP", f_string_greaterp, 2, 2);
    defsubr("STRING-NOT-GREATERP", f_string_not_greaterp, 2, 2);
    defsubr("STRING-NOT-LESSP", f_string_not_lessp, 2, 2);
    defsubr("STRING-TRIM", f_string_trim, 2, 2);
    defsubr("STRING-LEFT-TRIM", f_string_left_trim, 2, 2);
    defsubr("STRING-RIGHT-TRIM", f_string_right_trim, 2, 2);
    defsubr("MAKE-STRING", f_make_string, 1, 3);
    defsubr("%SUBSEQ", f_subseq_string, 2, 3);
    defsubr("%CONCATENATE", f_concatenate_strings, 1, ANY);
    defsubr("PARSE-INTEGER", f_parse_integer, 1, 1);
    defsubr("READ-FROM-STRING", f_read_from_string, 1, 1);
    defsubr("FIND", f_find, 2, ANY);
    defsubr("FIND-IF", f_find_if, 2, ANY);
    defsubr("FIND-IF-NOT", f_find_if_not, 2, ANY);
    defsubr("POSITION", f_position, 2, ANY);
    defsubr("POSITION-IF", f_position_if, 2, ANY);
    defsubr("POSITION-IF-NOT", f_position_if_not, 2, ANY);
    defsubr("COUNT", f_count, 2, ANY);
    defsubr("COUNT-IF", f_count_if, 2, ANY);
    defsubr("COUNT-IF-NOT", f_count_if_not, 2, ANY);
    defsubr("REMOVE", f_remove, 2, ANY);
    defsubr("DELETE", f_remove, 2, ANY);
    defsubr("REMOVE-IF", f_remove_if, 2, ANY);
    defsubr("DELETE-IF", f_remove_if, 2, ANY);
    defsubr("REMOVE-IF-NOT", f_remove_if_not, 2, ANY);
    defsubr("DELETE-IF-NOT", f_remove_if_not, 2, ANY);
    defsubr("SUBSTITUTE", f_substitute, 3, ANY);
    defsubr("NSUBSTITUTE", f_nsubstitute, 3, ANY);
    defsubr("SUBSTITUTE-IF", f_substitute_if, 3, ANY);
    defsubr("SUBSTITUTE-IF-NOT", f_substitute_if_not, 3, ANY);
    defsubr("SORT", f_sort, 2, 4);
    defsubr("STABLE-SORT", f_sort, 2, 4);
    defsubr("COERCE", f_coerce, 2, 2);
    defsubr("MAKE-ARRAY", f_make_array, 1, ANY);
    defsubr("VECTOR", f_vector, 0, ANY);
    defsubr("%MAKE-STRUCT", f_make_struct, 1, ANY);
    defsubr("%STRUCT-REF", f_struct_ref, 3, 3);
    defsubr("%STRUCT-SET", f_struct_set, 4, 4);
    defsubr("%STRUCT-IS", f_struct_is, 2, 2);
    defsubr("%STRUCT-TYPE", f_struct_type, 1, 1);
    defsubr("COPY-STRUCTURE", f_copy_structure, 1, 1);
    defsubr("SXHASH", f_sxhash, 1, 1);
    defsubr("%EQHASH", f_eqhash, 1, 1);
    defsubr("GETHASH", f_gethash, 2, 3);
    defsubr("%PUTHASH", f_puthash, 3, 4);
    defsubr("REMHASH", f_remhash, 2, 2);
}
