/* Pocket Lisp -- the core's functions (CPC Lisp's src/subrs.asm and the
 * builtin symbols of src/symtab.asm), helpers, and setf's places. */
#include "lisp.h"
#include <string.h>
#include <stdlib.h>

builtin *builtins;
int nbuiltins;
static int cap_builtins;

static obj register_builtin(const char *name, void *fn, int min, int max, int special)
{
    if (nbuiltins == cap_builtins) {
        cap_builtins = cap_builtins ? cap_builtins * 2 : 512;
        builtins = realloc(builtins, cap_builtins * sizeof(builtin));
    }
    builtin *b = &builtins[nbuiltins];
    b->name = name;
    b->fn = fn;
    b->min = (int8_t)min;
    b->max = (int8_t)max;
    b->special = (uint8_t)special;
    obj s = intern_cstr(name);
    SYM(s)->fn = mktyped(T_SUBR, (obj)nbuiltins);
    nbuiltins++;
    return s;
}

obj defsubr(const char *name, subr_fn fn, int min, int max)
{
    return register_builtin(name, (void *)fn, min, max, 0);
}

obj defspecial(const char *name, fsubr_fn fn)
{
    return register_builtin(name, (void *)fn, 0, ANY, 1);
}

/* ---- helpers ---- */

obj bool_obj(int b) { return b ? S_T : NIL; }
obj list2(obj a, obj b) { return cons(a, cons(b, NIL)); }
obj list3(obj a, obj b, obj c) { return cons(a, cons(b, cons(c, NIL))); }

obj check_list(obj o)
{
    if (!listp(o))
        lisp_error("not a list:", o);
    return o;
}

obj check_sym(obj o)
{
    if (!issym(o))
        lisp_error("not a symbol:", o);
    return o;
}

obj check_string(obj o)
{
    if (!isstring(o))
        lisp_error("not a string:", o);
    return o;
}

int32_t check_int(obj o)
{
    if (!isfix(o))
        lisp_error("not a number:", o);
    return fixval(o);
}

obj nreverse(obj l)
{
    obj r = NIL;
    while (iscons(l)) {
        obj n = cdr(l);
        cdr(l) = r;
        r = l;
        l = n;
    }
    return r;
}

int32_t lisp_length(obj l)
{
    int32_t n = 0;
    for (; iscons(l); l = cdr(l))
        n++;
    if (l != NIL)
        lisp_error("not a list:", l);
    return n;
}

int eql(obj a, obj b)
{
    if (a == b)
        return 1;
    if (isfloat(a) && isfloat(b))
        return floatval(a) == floatval(b);
    return 0;
}

int equal(obj a, obj b)
{
    for (;;) {
        if (eql(a, b))
            return 1;
        if (iscons(a) && iscons(b)) {
            if (!equal(car(a), car(b)))
                return 0;
            a = cdr(a);
            b = cdr(b);
            continue;
        }
        if (isstring(a) && isstring(b))
            return str_len(a) == str_len(b)
                && !memcmp(str_chars(a), str_chars(b), str_len(a));
        return 0;
    }
}

obj string_designator(obj o)
{
    if (isstring(o))
        return o;
    if (issym(o))
        return SYM(o)->name;
    if (ischar(o)) {
        char c = (char)charval(o);
        return mkstring(&c, 1);
    }
    lisp_error("not a string:", o);
}

/* ---- lists ---- */

static obj xcar(obj o)
{
    if (o == NIL)
        return NIL;
    if (!iscons(o))
        lisp_error("not a list:", o);
    return car(o);
}

static obj xcdr(obj o)
{
    if (o == NIL)
        return NIL;
    if (!iscons(o))
        lisp_error("not a list:", o);
    return cdr(o);
}

static obj f_car(int c, obj *a) { (void)c; return xcar(a[0]); }
static obj f_cdr(int c, obj *a) { (void)c; return xcdr(a[0]); }
static obj f_second(int c, obj *a) { (void)c; return xcar(xcdr(a[0])); }
static obj f_third(int c, obj *a) { (void)c; return xcar(xcdr(xcdr(a[0]))); }
static obj f_caar(int c, obj *a) { (void)c; return xcar(xcar(a[0])); }
static obj f_cdar(int c, obj *a) { (void)c; return xcdr(xcar(a[0])); }
static obj f_cddr(int c, obj *a) { (void)c; return xcdr(xcdr(a[0])); }
static obj f_cdddr(int c, obj *a) { (void)c; return xcdr(xcdr(xcdr(a[0]))); }
static obj f_cons(int c, obj *a) { (void)c; return cons(a[0], a[1]); }

static obj f_list(int c, obj *a)
{
    obj l = NIL;
    for (int i = c - 1; i >= 0; i--)
        l = cons(a[i], l);
    return l;
}

static obj f_liststar(int c, obj *a)
{
    obj l = a[c - 1];
    for (int i = c - 2; i >= 0; i--)
        l = cons(a[i], l);
    return l;
}

static obj f_append(int c, obj *a)
{
    if (c == 0)
        return NIL;
    obj result = a[c - 1];
    for (int i = c - 2; i >= 0; i--) {
        obj l = check_list(a[i]);
        if (l == NIL)
            continue;
        obj head = NIL, tail = NIL;
        for (; iscons(l); l = cdr(l)) {
            obj n = cons(car(l), NIL);
            if (tail == NIL) head = n; else cdr(tail) = n;
            tail = n;
        }
        cdr(tail) = result;
        result = head;
    }
    return result;
}

static obj f_length(int c, obj *a)
{
    (void)c;
    obj o = a[0];
    if (isstring(o))
        return mkfix(str_len(o));
    if (isvector(o))
        return mkfix(vec_len(o));
    return mkfix(lisp_length(o));
}

static obj f_nthcdr(int c, obj *a)
{
    (void)c;
    int32_t n = check_int(a[0]);
    obj l = a[1];
    while (n-- > 0 && l != NIL)
        l = xcdr(l);
    return l;
}

static obj f_nth(int c, obj *a) { return xcar(f_nthcdr(c, a)); }

static obj f_last(int c, obj *a)
{
    (void)c;
    obj l = check_list(a[0]);
    if (l == NIL)
        return NIL;
    while (iscons(cdr(l)))
        l = cdr(l);
    return l;
}

static obj f_rplaca(int c, obj *a)
{
    (void)c;
    if (!iscons(a[0]))
        lisp_error("not a cons:", a[0]);
    car(a[0]) = a[1];
    return a[0];
}

static obj f_rplacd(int c, obj *a)
{
    (void)c;
    if (!iscons(a[0]))
        lisp_error("not a cons:", a[0]);
    cdr(a[0]) = a[1];
    return a[0];
}

static obj map_common(int c, obj *a, int collect)
{
    obj fn = coerce_fn(a[0]);
    int n = c - 1;
    obj lists[n > 0 ? n : 1];
    for (int i = 0; i < n; i++)
        lists[i] = check_list(a[i + 1]);
    obj head = NIL, tail = NIL;
    obj args[n > 0 ? n : 1];
    for (;;) {
        for (int i = 0; i < n; i++) {
            if (!iscons(lists[i]))
                goto end;
            args[i] = car(lists[i]);
            lists[i] = cdr(lists[i]);
        }
        obj v = apply(fn, n, args);
        if (collect) {
            obj cell = cons(v, NIL);
            if (tail == NIL) head = cell; else cdr(tail) = cell;
            tail = cell;
        }
    }
end:
    return collect ? head : a[1];
}

static obj f_mapcar(int c, obj *a) { return map_common(c, a, 1); }
static obj f_mapc(int c, obj *a) { return map_common(c, a, 0); }

static obj f_apply(int c, obj *a)
{
    obj fn = coerce_fn(a[0]);
    obj last = check_list(a[c - 1]);
    int n = c - 2 + lisp_length(last);
    obj argv[n > 0 ? n : 1];
    int k = 0;
    for (int i = 1; i < c - 1; i++)
        argv[k++] = a[i];
    for (; iscons(last); last = cdr(last))
        argv[k++] = car(last);
    return apply(fn, n, argv);
}

static obj f_funcall(int c, obj *a) { return apply(coerce_fn(a[0]), c - 1, a + 1); }

/* ---- predicates ---- */

static obj f_null(int c, obj *a) { (void)c; return bool_obj(a[0] == NIL); }
static obj f_atom(int c, obj *a) { (void)c; return bool_obj(!iscons(a[0])); }
static obj f_consp(int c, obj *a) { (void)c; return bool_obj(iscons(a[0])); }
static obj f_listp(int c, obj *a) { (void)c; return bool_obj(listp(a[0])); }
static obj f_symbolp(int c, obj *a) { (void)c; return bool_obj(issym(a[0])); }
static obj f_numberp(int c, obj *a) { (void)c; return bool_obj(isnumber(a[0])); }
static obj f_integerp(int c, obj *a) { (void)c; return bool_obj(isfix(a[0])); }
static obj f_stringp(int c, obj *a) { (void)c; return bool_obj(isstring(a[0])); }
static obj f_characterp(int c, obj *a) { (void)c; return bool_obj(ischar(a[0])); }
static obj f_functionp(int c, obj *a)
{
    (void)c;
    obj f = a[0];
    return bool_obj(istype(f, T_CLOSURE) || istype(f, T_CODE)
                    || (istype(f, T_SUBR) && !builtins[DATA(f)].special));
}
static obj f_keywordp(int c, obj *a)
{
    (void)c;
    obj s = a[0];
    return bool_obj(issym(s) && s != NIL && str_len(SYM(s)->name) > 0
                    && str_chars(SYM(s)->name)[0] == ':');
}
static obj f_eq(int c, obj *a) { (void)c; return bool_obj(a[0] == a[1]); }
static obj f_eql(int c, obj *a) { (void)c; return bool_obj(eql(a[0], a[1])); }
static obj f_equal(int c, obj *a) { (void)c; return bool_obj(equal(a[0], a[1])); }
static obj f_vectorp(int c, obj *a) { (void)c; return bool_obj(isvector(a[0]) || isstring(a[0])); }

/* ---- symbols ---- */

static obj f_symbol_name(int c, obj *a) { (void)c; return SYM(check_sym(a[0]))->name; }
static obj f_symbol_value(int c, obj *a) { (void)c; return sym_value(check_sym(a[0])); }
static obj f_symbol_function(int c, obj *a)
{
    (void)c;
    obj f = SYM(check_sym(a[0]))->fn;
    if (f == UNBOUND)
        lisp_error("undefined function", a[0]);
    return f;
}
static obj f_symbol_plist(int c, obj *a) { (void)c; return SYM(check_sym(a[0]))->plist; }
static obj f_set(int c, obj *a) { (void)c; set_value(check_sym(a[0]), a[1]); return a[1]; }
static obj f_boundp(int c, obj *a) { (void)c; return bool_obj(SYM(check_sym(a[0]))->value != UNBOUND); }
static obj f_fboundp(int c, obj *a) { (void)c; return bool_obj(SYM(check_sym(a[0]))->fn != UNBOUND); }
static obj f_makunbound(int c, obj *a) { (void)c; SYM(check_sym(a[0]))->value = UNBOUND; return a[0]; }
static obj f_fmakunbound(int c, obj *a) { (void)c; SYM(check_sym(a[0]))->fn = UNBOUND; return a[0]; }

obj get_prop(obj s, obj ind, obj dflt)
{
    for (obj p = SYM(s)->plist; iscons(p) && iscons(cdr(p)); p = cdr(cdr(p)))
        if (car(p) == ind)
            return car(cdr(p));
    return dflt;
}

obj put_prop(obj s, obj ind, obj v)
{
    for (obj p = SYM(s)->plist; iscons(p) && iscons(cdr(p)); p = cdr(cdr(p)))
        if (car(p) == ind) {
            car(cdr(p)) = v;
            return v;
        }
    SYM(s)->plist = cons(ind, cons(v, SYM(s)->plist));
    return v;
}

static obj f_get(int c, obj *a)
{
    return get_prop(check_sym(a[0]), a[1], c > 2 ? a[2] : NIL);
}

/* ---- characters, strings, vectors ---- */

static obj f_char_code(int c, obj *a)
{
    (void)c;
    if (!ischar(a[0]))
        lisp_error("not a character:", a[0]);
    return mkfix(charval(a[0]));
}

static int32_t check_index(obj i, uint32_t n)
{
    if (!isfix(i))
        lisp_error("not a number:", i);
    int32_t k = fixval(i);
    if (k < 0 || (uint32_t)k >= n)
        lisp_error("index out of range", i);
    return k;
}

static obj f_char(int c, obj *a)
{
    (void)c;
    obj s = check_string(a[0]);
    int32_t k = check_index(a[1], str_len(s));
    return mkchar((uint8_t)str_chars(s)[k]);
}

obj seq_ref(obj seq, obj i)
{
    if (isstring(seq))
        return mkchar((uint8_t)str_chars(seq)[check_index(i, str_len(seq))]);
    if (isvector(seq))
        return vec_elts(seq)[check_index(i, vec_len(seq))];
    lisp_error("not a vector:", seq);
}

static obj f_aref(int c, obj *a) { (void)c; return seq_ref(a[0], a[1]); }

static obj f_elt(int c, obj *a)
{
    (void)c;
    if (listp(a[0])) {
        obj l = a[0];
        int32_t k = check_int(a[1]);
        while (k-- > 0 && iscons(l))
            l = cdr(l);
        if (!iscons(l))
            lisp_error("index out of range", a[1]);
        return car(l);
    }
    return seq_ref(a[0], a[1]);
}

static obj f_string(int c, obj *a) { (void)c; return string_designator(a[0]); }

/* ---- eval ---- */

static obj f_eval(int c, obj *a) { (void)c; return eval(a[0], NIL); }

static obj f_macroexpand_1(int c, obj *a)
{
    (void)c;
    int e;
    return macroexpand_1(a[0], NIL, &e);
}

static obj f_macroexpand(int c, obj *a)
{
    (void)c;
    int e, any = 0;
    obj f = a[0];
    do {
        f = macroexpand_1(f, NIL, &e);
        any |= e;
    } while (e);
    (void)any;
    return f;
}

static obj f_signal(int c, obj *a) { (void)c; lisp_signal(a[0]); }

static obj f_gc(int c, obj *a)
{
    (void)c; (void)a;
    gc();
    return mkfix(cells_free_after_gc);
}

/* ---- setf's places ---- */

extern obj fn_lookup_pub(obj sym, obj env);

static void set_elt(obj seq, obj i, obj v)
{
    if (isstring(seq)) {
        if (!ischar(v))
            lisp_error("not a character:", v);
        str_chars(seq)[check_index(i, str_len(seq))] = (char)charval(v);
    } else if (isvector(seq)) {
        vec_elts(seq)[check_index(i, vec_len(seq))] = v;
    } else if (listp(seq)) {
        obj l = seq;
        int32_t k = check_int(i);
        while (k-- > 0 && iscons(l))
            l = cdr(l);
        if (!iscons(l))
            lisp_error("index out of range", i);
        car(l) = v;
    } else
        lisp_error("not a vector:", seq);
}

extern obj S_SETF_PROP;

obj setf_place(obj place, obj v, obj env)
{
    obj op = car(place);
    obj args = cdr(place);
    if (!issym(op))
        lisp_error("cannot setf", place);
    const char *nm = str_chars(SYM(op)->name);
    uint32_t nl = str_len(SYM(op)->name);
#define IS(s) (nl == sizeof(s) - 1 && !memcmp(nm, s, nl))
    if (IS("CAR") || IS("FIRST") || IS("CDR") || IS("REST")) {
        obj c = eval(car(args), env);
        if (!iscons(c))
            lisp_error("not a cons:", c);
        if (nm[1] == 'A' || nm[0] == 'F') car(c) = v; else cdr(c) = v;
        return v;
    }
    if (IS("CADR") || IS("SECOND") || IS("THIRD") || IS("CADDR") || IS("CDDR")
        || IS("CAAR") || IS("CDAR") || IS("NTH")) {
        obj c;
        if (IS("NTH")) {
            obj n = eval(car(args), env);
            c = eval(car(cdr(args)), env);
            int32_t k = check_int(n);
            while (k-- > 0 && iscons(c))
                c = cdr(c);
            if (!iscons(c))
                lisp_error("not a cons:", c);
            car(c) = v;
            return v;
        }
        c = eval(car(args), env);
        if (IS("CADR") || IS("SECOND")) c = xcdr(c);
        else if (IS("THIRD") || IS("CADDR")) c = xcdr(xcdr(c));
        else if (IS("CDDR")) { c = xcdr(c); if (!iscons(c)) lisp_error("not a cons:", c); cdr(c) = v; return v; }
        else if (IS("CAAR") || IS("CDAR")) {
            c = xcar(c);
            if (!iscons(c)) lisp_error("not a cons:", c);
            if (IS("CAAR")) car(c) = v; else cdr(c) = v;
            return v;
        }
        if (!iscons(c))
            lisp_error("not a cons:", c);
        car(c) = v;
        return v;
    }
    if (IS("AREF") || IS("SVREF") || IS("ELT") || IS("CHAR") || IS("SCHAR")) {
        obj seq = eval(car(args), env);
        obj i = eval(car(cdr(args)), env);
        set_elt(seq, i, v);
        return v;
    }
    if (IS("GET")) {
        obj s = check_sym(eval(car(args), env));
        obj ind = eval(car(cdr(args)), env);
        return put_prop(s, ind, v);
    }
    if (IS("SYMBOL-VALUE")) {
        set_value(check_sym(eval(car(args), env)), v);
        return v;
    }
    if (IS("SYMBOL-FUNCTION") || IS("FDEFINITION")) {
        obj s = check_sym(eval(car(args), env));
        SYM(s)->fn = v;
        SYM(s)->flags |= SF_USERDEF;
        SYM(s)->flags &= ~SF_LIBDEF;
        return v;
    }
    if (IS("SYMBOL-PLIST")) {
        SYM(check_sym(eval(car(args), env)))->plist = v;
        return v;
    }
#undef IS
    obj upd = get_prop(op, S_SETF_PROP, NIL);
    if (upd != NIL) {
        int n = lisp_length(args);
        obj argv[n + 1];
        int i = 0;
        for (obj l = args; iscons(l); l = cdr(l))
            argv[i++] = eval(car(l), env);
        argv[i] = v;
        return apply(coerce_fn(upd), n + 1, argv);
    }
    obj m = fn_lookup_pub(op, env);
    if (istype(m, T_MACRO)) {
        int e;
        obj x = macroexpand_1(place, env, &e);
        if (issym(x)) {
            /* a symbol-macro-ish expansion: a variable */
            extern obj setq_var(obj s, obj v, obj env);
            return setq_var(x, v, env);
        }
        return setf_place(x, v, env);
    }
    lisp_error("cannot setf", place);
}

/* ---- the table ---- */

void init_core_subrs(void)
{
    defsubr("CAR", f_car, 1, 1);
    defsubr("CDR", f_cdr, 1, 1);
    defsubr("FIRST", f_car, 1, 1);
    defsubr("REST", f_cdr, 1, 1);
    defsubr("SECOND", f_second, 1, 1);
    defsubr("THIRD", f_third, 1, 1);
    defsubr("CAAR", f_caar, 1, 1);
    defsubr("CADR", f_second, 1, 1);
    defsubr("CDAR", f_cdar, 1, 1);
    defsubr("CDDR", f_cddr, 1, 1);
    defsubr("CADDR", f_third, 1, 1);
    defsubr("CDDDR", f_cdddr, 1, 1);
    defsubr("CONS", f_cons, 2, 2);
    defsubr("LIST", f_list, 0, ANY);
    defsubr("LIST*", f_liststar, 1, ANY);
    defsubr("APPEND", f_append, 0, ANY);
    defsubr("LENGTH", f_length, 1, 1);
    defsubr("NTH", f_nth, 2, 2);
    defsubr("NTHCDR", f_nthcdr, 2, 2);
    defsubr("LAST", f_last, 1, 1);
    defsubr("RPLACA", f_rplaca, 2, 2);
    defsubr("RPLACD", f_rplacd, 2, 2);
    defsubr("MAPCAR", f_mapcar, 2, ANY);
    defsubr("MAPC", f_mapc, 2, ANY);
    defsubr("APPLY", f_apply, 2, ANY);
    defsubr("FUNCALL", f_funcall, 1, ANY);
    defsubr("NULL", f_null, 1, 1);
    defsubr("NOT", f_null, 1, 1);
    defsubr("ATOM", f_atom, 1, 1);
    defsubr("CONSP", f_consp, 1, 1);
    defsubr("LISTP", f_listp, 1, 1);
    defsubr("SYMBOLP", f_symbolp, 1, 1);
    defsubr("NUMBERP", f_numberp, 1, 1);
    defsubr("INTEGERP", f_integerp, 1, 1);
    defsubr("STRINGP", f_stringp, 1, 1);
    defsubr("CHARACTERP", f_characterp, 1, 1);
    defsubr("FUNCTIONP", f_functionp, 1, 1);
    defsubr("KEYWORDP", f_keywordp, 1, 1);
    defsubr("EQ", f_eq, 2, 2);
    defsubr("EQL", f_eql, 2, 2);
    defsubr("EQUAL", f_equal, 2, 2);
    defsubr("SYMBOL-NAME", f_symbol_name, 1, 1);
    defsubr("SYMBOL-VALUE", f_symbol_value, 1, 1);
    defsubr("SYMBOL-FUNCTION", f_symbol_function, 1, 1);
    defsubr("SYMBOL-PLIST", f_symbol_plist, 1, 1);
    defsubr("SET", f_set, 2, 2);
    defsubr("BOUNDP", f_boundp, 1, 1);
    defsubr("FBOUNDP", f_fboundp, 1, 1);
    defsubr("MAKUNBOUND", f_makunbound, 1, 1);
    defsubr("FMAKUNBOUND", f_fmakunbound, 1, 1);
    defsubr("GET", f_get, 2, 3);
    defsubr("CHAR-CODE", f_char_code, 1, 1);
    defsubr("CHAR", f_char, 2, 2);
    defsubr("AREF", f_aref, 2, 2);
    defsubr("SVREF", f_aref, 2, 2);
    defsubr("ELT", f_elt, 2, 2);
    defsubr("VECTORP", f_vectorp, 1, 1);
    defsubr("STRING", f_string, 1, 1);
    defsubr("EVAL", f_eval, 1, 1);
    defsubr("MACROEXPAND-1", f_macroexpand_1, 1, 1);
    defsubr("MACROEXPAND", f_macroexpand, 1, 1);
    defsubr("%SIGNAL", f_signal, 1, 1);
    defsubr("GC", f_gc, 0, 0);
}
