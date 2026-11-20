/* Pocket Lisp -- the extended LOOP's expander, %loop-expand (CPC Lisp's
 * lib/loop.asm; the macro LOOP is lib/loop.lsp's). The expansion:
 *
 *   (block name
 *     (let* bindings
 *       initially...
 *       (block %loop (return-from name (%loop top... body... steps...)))
 *       finally...
 *       result))
 *
 * A for clause that runs out leaves the inner block (%LOOP), so the
 * finally forms run; (return x) in the body leaves %LOOP's own block and
 * returns x past them, as in CL. Temporaries are the interned %0, %1... */
#include "lisp.h"
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

typedef struct {
    obj name, bindings, initially, top, body, steps, finally, result;
    obj clauses;
    int ntemp;
    obj acc_default;            /* the default accumulator's kind, or NIL */
} loopst;

static obj sym(const char *s) { return intern_cstr(s); }

static obj L(int n, ...)
{
    va_list ap;
    obj v[16];
    va_start(ap, n);
    for (int i = 0; i < n; i++)
        v[i] = va_arg(ap, obj);
    va_end(ap);
    obj l = NIL;
    for (int i = n - 1; i >= 0; i--)
        l = cons(v[i], l);
    return l;
}

static obj append1(obj l, obj x)
{
    obj cell = cons(x, NIL);
    if (l == NIL)
        return cell;
    obj t = l;
    while (iscons(cdr(t)))
        t = cdr(t);
    cdr(t) = cell;
    return l;
}

static obj temp(loopst *s)
{
    char b[16];
    snprintf(b, sizeof b, "%%%d", s->ntemp++);
    return sym(b);
}

/* is x the loop keyword k (by name, or as a keyword :k)? */
static int kw(obj x, const char *k)
{
    if (!issym(x) || x == NIL)
        return 0;
    obj n = SYM(x)->name;
    const char *p = str_chars(n);
    uint32_t len = str_len(n);
    if (len && p[0] == ':') { p++; len--; }
    return len == strlen(k) && !memcmp(p, k, len);
}

static int is_loop_keyword(obj x)
{
    static const char *words[] = {"FOR", "AS", "WITH", "AND", "REPEAT", "WHILE", "UNTIL",
        "NAMED", "INITIALLY", "FINALLY", "DO", "DOING", "COLLECT", "COLLECTING", "APPEND",
        "APPENDING", "NCONC", "NCONCING", "SUM", "SUMMING", "COUNT", "COUNTING", "MAXIMIZE",
        "MAXIMIZING", "MINIMIZE", "MINIMIZING", "INTO", "WHEN", "IF", "UNLESS", "ELSE",
        "END", "RETURN", "ALWAYS", "NEVER", "THEREIS", NULL};
    for (int i = 0; words[i]; i++)
        if (kw(x, words[i]))
            return 1;
    return 0;
}

static obj next(loopst *s)
{
    if (!iscons(s->clauses))
        lisp_error0("LOOP: a clause is cut short");
    obj x = car(s->clauses);
    s->clauses = cdr(s->clauses);
    return x;
}

static int peek_kw(loopst *s, const char *k)
{
    return iscons(s->clauses) && kw(car(s->clauses), k);
}

static void bind(loopst *s, obj var, obj init)
{
    s->bindings = append1(s->bindings, L(2, var, init));
}

/* the symbols of a destructuring pattern, bound to NIL */
static void bind_pattern(loopst *s, obj p)
{
    if (p == NIL)
        return;
    if (issym(p)) {
        bind(s, p, NIL);
        return;
    }
    if (iscons(p)) {
        bind_pattern(s, car(p));
        bind_pattern(s, cdr(p));
    }
}

/* forms setting the pattern's variables from the value form e */
static obj set_pattern(obj p, obj e, obj forms)
{
    if (p == NIL)
        return forms;
    if (issym(p))
        return append1(forms, L(3, sym("SETQ"), p, e));
    if (iscons(p)) {
        forms = set_pattern(car(p), L(2, sym("CAR"), e), forms);
        forms = set_pattern(cdr(p), L(2, sym("CDR"), e), forms);
    }
    return forms;
}

static obj leave(void) { return L(3, sym("RETURN-FROM"), sym("%LOOP"), NIL); }

static void for_clause(loopst *s)
{
    obj var = next(s);
    obj how = next(s);
    if (kw(how, "IN") || kw(how, "ON")) {
        int on = kw(how, "ON");
        obj list = next(s);
        obj k = temp(s);
        bind(s, k, list);
        bind_pattern(s, var);
        obj test = on ? L(2, sym("ATOM"), k) : L(2, sym("ENDP"), k);
        s->top = append1(s->top, L(3, sym("WHEN"), test, leave()));
        s->top = set_pattern(var, on ? k : L(2, sym("CAR"), k), s->top);
        obj step = L(2, sym("CDR"), k);
        if (peek_kw(s, "BY")) {
            next(s);
            step = L(3, sym("FUNCALL"), next(s), k);
        }
        s->steps = append1(s->steps, L(3, sym("SETQ"), k, step));
        return;
    }
    if (kw(how, "ACROSS")) {
        obj v = temp(s), i = temp(s);
        bind(s, v, next(s));
        bind(s, i, mkfix(0));
        bind_pattern(s, var);
        s->top = append1(s->top, L(3, sym("WHEN"), L(3, sym(">="), i, L(2, sym("LENGTH"), v)), leave()));
        s->top = set_pattern(var, L(3, sym("AREF"), v, i), s->top);
        s->steps = append1(s->steps, L(3, sym("SETQ"), i, L(2, sym("1+"), i)));
        return;
    }
    if (kw(how, "=")) {
        obj init = next(s);
        if (peek_kw(s, "THEN")) {
            next(s);
            obj then = next(s);
            if (issym(var))
                bind(s, var, init);
            else {
                bind_pattern(s, var);
                obj t = temp(s);
                bind(s, t, init);
                s->initially = set_pattern(var, t, s->initially);
            }
            s->steps = set_pattern(var, then, s->steps);
        } else {
            bind_pattern(s, var);
            s->top = set_pattern(var, init, s->top);
        }
        return;
    }
    if (kw(how, "BEING")) {
        obj w = next(s);
        if (kw(w, "THE") || kw(w, "EACH"))
            w = next(s);
        int keys = kw(w, "HASH-KEYS") || kw(w, "HASH-KEY");
        int vals = kw(w, "HASH-VALUES") || kw(w, "HASH-VALUE");
        if (!keys && !vals)
            lisp_error("LOOP: what FOR does not know:", w);
        obj of = next(s);
        if (!kw(of, "OF") && !kw(of, "IN"))
            lisp_error("LOOP: what FOR does not know:", of);
        obj table = next(s);
        obj other = NIL;
        if (peek_kw(s, "USING")) {
            next(s);
            obj u = next(s);            /* (hash-value v) or (hash-key k) */
            if (iscons(u) && iscons(cdr(u)))
                other = car(cdr(u));
        }
        obj k = temp(s);
        bind(s, k, L(2, sym("%HASH-PAIRS"), table));
        bind_pattern(s, var);
        if (other != NIL)
            bind(s, other, NIL);
        s->top = append1(s->top, L(3, sym("WHEN"), L(2, sym("ENDP"), k), leave()));
        obj pair = L(2, sym("CAR"), k);
        s->top = append1(s->top, L(3, sym("SETQ"), var, L(2, sym(keys ? "CAR" : "CDR"), pair)));
        if (other != NIL)
            s->top = append1(s->top, L(3, sym("SETQ"), other, L(2, sym(keys ? "CDR" : "CAR"), pair)));
        s->steps = append1(s->steps, L(3, sym("SETQ"), k, L(2, sym("CDR"), k)));
        return;
    }
    /* numbers: from/downfrom/upfrom, to/upto/below/downto/above, by */
    obj start = mkfix(0), limit = UNBOUND, step = mkfix(1);
    int down = 0, inclusive = 1, have_limit = 0;
    for (;;) {
        if (kw(how, "FROM") || kw(how, "UPFROM")) start = next(s);
        else if (kw(how, "DOWNFROM")) { start = next(s); down = 1; }
        else if (kw(how, "TO") || kw(how, "UPTO")) { limit = next(s); have_limit = 1; }
        else if (kw(how, "BELOW")) { limit = next(s); have_limit = 1; inclusive = 0; }
        else if (kw(how, "DOWNTO")) { limit = next(s); have_limit = 1; down = 1; }
        else if (kw(how, "ABOVE")) { limit = next(s); have_limit = 1; down = 1; inclusive = 0; }
        else if (kw(how, "BY")) step = next(s);
        else lisp_error("LOOP: what FOR does not know:", how);
        if (iscons(s->clauses) && issym(car(s->clauses))
            && (kw(car(s->clauses), "FROM") || kw(car(s->clauses), "UPFROM")
                || kw(car(s->clauses), "DOWNFROM") || kw(car(s->clauses), "TO")
                || kw(car(s->clauses), "UPTO") || kw(car(s->clauses), "BELOW")
                || kw(car(s->clauses), "DOWNTO") || kw(car(s->clauses), "ABOVE")
                || kw(car(s->clauses), "BY")))
            how = next(s);
        else
            break;
    }
    bind(s, var, start);
    obj st = step;
    if (!isfix(step)) {
        st = temp(s);
        bind(s, st, step);
    }
    if (have_limit) {
        obj lim = limit;
        if (!isfix(limit)) {
            lim = temp(s);
            bind(s, lim, limit);
        }
        const char *op = down ? (inclusive ? "<" : "<=") : (inclusive ? ">" : ">=");
        s->top = append1(s->top, L(3, sym("WHEN"), L(3, sym(op), var, lim), leave()));
    }
    s->steps = append1(s->steps, L(3, sym("SETQ"), var, L(3, sym(down ? "-" : "+"), var, st)));
}

/* an accumulation: collect, append... into var or the default */
static obj accumulate(loopst *s, obj what)
{
    obj x = next(s);
    obj var = NIL;
    if (peek_kw(s, "INTO")) {
        next(s);
        var = next(s);
    }
    int list = kw(what, "COLLECT") || kw(what, "COLLECTING") || kw(what, "APPEND")
        || kw(what, "APPENDING") || kw(what, "NCONC") || kw(what, "NCONCING");
    int sum = kw(what, "SUM") || kw(what, "SUMMING") || kw(what, "COUNT") || kw(what, "COUNTING");
    if (var == NIL) {
        var = sym("%C");
        if (s->acc_default == NIL) {
            s->acc_default = what;
            bind(s, var, sum ? mkfix(0) : NIL);
            s->result = var;
        }
    } else {
        int bound = 0;
        for (obj b = s->bindings; iscons(b); b = cdr(b))
            if (car(car(b)) == var)
                bound = 1;
        if (!bound)
            bind(s, var, sum ? mkfix(0) : NIL);
    }
    (void)list;
    if (kw(what, "COLLECT") || kw(what, "COLLECTING"))
        return L(3, sym("SETQ"), var, L(3, sym("NCONC"), var, L(2, sym("LIST"), x)));
    if (kw(what, "APPEND") || kw(what, "APPENDING"))
        return L(3, sym("SETQ"), var, L(3, sym("APPEND"), var, x));
    if (kw(what, "NCONC") || kw(what, "NCONCING"))
        return L(3, sym("SETQ"), var, L(3, sym("NCONC"), var, x));
    if (kw(what, "SUM") || kw(what, "SUMMING"))
        return L(3, sym("SETQ"), var, L(3, sym("+"), var, x));
    if (kw(what, "COUNT") || kw(what, "COUNTING"))
        return L(3, sym("WHEN"), x, L(3, sym("SETQ"), var, L(2, sym("1+"), var)));
    obj t = temp(s);
    const char *f = (kw(what, "MAXIMIZE") || kw(what, "MAXIMIZING")) ? "MAX" : "MIN";
    return L(3, sym("LET"), L(1, L(2, t, x)),
             L(3, sym("SETQ"), var, L(4, sym("IF"), var, L(3, sym(f), var, t), t)));
}

static int is_accumulation(obj x)
{
    return kw(x, "COLLECT") || kw(x, "COLLECTING") || kw(x, "APPEND") || kw(x, "APPENDING")
        || kw(x, "NCONC") || kw(x, "NCONCING") || kw(x, "SUM") || kw(x, "SUMMING")
        || kw(x, "COUNT") || kw(x, "COUNTING") || kw(x, "MAXIMIZE") || kw(x, "MAXIMIZING")
        || kw(x, "MINIMIZE") || kw(x, "MINIMIZING");
}

static obj compound_forms(loopst *s)
{
    obj forms = NIL;
    while (iscons(s->clauses) && iscons(car(s->clauses)))
        forms = append1(forms, next(s));
    return forms;
}

static obj selectable(loopst *s);

/* when/if/unless: test, clauses joined by and, else..., end */
static obj conditional(loopst *s, int negate)
{
    obj test = next(s);
    if (negate)
        test = L(2, sym("NOT"), test);
    obj yes = L(1, selectable(s));
    while (peek_kw(s, "AND")) {
        next(s);
        yes = append1(yes, selectable(s));
    }
    obj no = NIL;
    if (peek_kw(s, "ELSE")) {
        next(s);
        no = L(1, selectable(s));
        while (peek_kw(s, "AND")) {
            next(s);
            no = append1(no, selectable(s));
        }
    }
    if (peek_kw(s, "END"))
        next(s);
    return L(4, sym("IF"), test, cons(sym("PROGN"), yes), cons(sym("PROGN"), no));
}

/* a clause that can go in a when: do, return, an accumulation, a when */
static obj selectable(loopst *s)
{
    obj w = next(s);
    if (kw(w, "DO") || kw(w, "DOING"))
        return cons(sym("PROGN"), compound_forms(s));
    if (kw(w, "RETURN"))
        return L(3, sym("RETURN-FROM"), s->name, next(s));
    if (is_accumulation(w))
        return accumulate(s, w);
    if (kw(w, "WHEN") || kw(w, "IF"))
        return conditional(s, 0);
    if (kw(w, "UNLESS"))
        return conditional(s, 1);
    lisp_error("LOOP: not a clause I know:", w);
}

static obj f_loop_expand(int c, obj *a)
{
    (void)c;
    loopst s;
    memset(&s, 0, sizeof s);
    s.clauses = a[0];
    s.acc_default = NIL;
    if (peek_kw(&s, "NAMED")) {
        next(&s);
        s.name = next(&s);
    }
    while (iscons(s.clauses)) {
        obj w = car(s.clauses);
        if (kw(w, "FOR") || kw(w, "AS")) {
            next(&s);
            for_clause(&s);
            while (peek_kw(&s, "AND")) {
                next(&s);
                for_clause(&s);
            }
        } else if (kw(w, "WITH")) {
            next(&s);
            for (;;) {
                obj var = next(&s);
                obj init = NIL;
                if (peek_kw(&s, "=")) {
                    next(&s);
                    init = next(&s);
                }
                bind(&s, var, init);
                if (!peek_kw(&s, "AND"))
                    break;
                next(&s);
            }
        } else if (kw(w, "REPEAT")) {
            next(&s);
            obj k = temp(&s);
            bind(&s, k, next(&s));
            s.top = append1(s.top, L(3, sym("WHEN"), L(3, sym("<="), k, mkfix(0)), leave()));
            s.top = append1(s.top, L(3, sym("SETQ"), k, L(2, sym("1-"), k)));
        } else if (kw(w, "WHILE") || kw(w, "UNTIL")) {
            next(&s);
            obj test = next(&s);
            s.body = append1(s.body, L(3, sym(kw(w, "WHILE") ? "UNLESS" : "WHEN"), test, leave()));
        } else if (kw(w, "INITIALLY")) {
            next(&s);
            obj f = compound_forms(&s);
            for (; iscons(f); f = cdr(f))
                s.initially = append1(s.initially, car(f));
        } else if (kw(w, "FINALLY")) {
            next(&s);
            obj f = compound_forms(&s);
            for (; iscons(f); f = cdr(f))
                s.finally = append1(s.finally, car(f));
        } else if (kw(w, "ALWAYS") || kw(w, "NEVER") || kw(w, "THEREIS")) {
            next(&s);
            obj x = next(&s);
            if (kw(w, "ALWAYS")) {
                s.body = append1(s.body, L(3, sym("UNLESS"), x, L(3, sym("RETURN-FROM"), s.name, NIL)));
                s.result = S_T;
            } else if (kw(w, "NEVER")) {
                s.body = append1(s.body, L(3, sym("WHEN"), x, L(3, sym("RETURN-FROM"), s.name, NIL)));
                s.result = S_T;
            } else {
                obj t = temp(&s);
                s.body = append1(s.body, L(3, sym("LET"), L(1, L(2, t, x)),
                    L(3, sym("WHEN"), t, L(3, sym("RETURN-FROM"), s.name, t))));
            }
        } else if (kw(w, "NAMED")) {
            next(&s);
            s.name = next(&s);
        } else if (kw(w, "DO") || kw(w, "DOING") || kw(w, "RETURN") || is_accumulation(w)
                   || kw(w, "WHEN") || kw(w, "IF") || kw(w, "UNLESS")) {
            s.body = append1(s.body, selectable(&s));
        } else
            lisp_error("LOOP: not a clause I know:", w);
    }
    /* (block name (let* bindings initially... (block %loop (return-from
     * name (%loop top... body... steps...))) finally... result)) */
    obj pass = s.top;
    for (obj l = s.body; iscons(l); l = cdr(l)) pass = append1(pass, car(l));
    for (obj l = s.steps; iscons(l); l = cdr(l)) pass = append1(pass, car(l));
    obj inner = L(3, sym("BLOCK"), sym("%LOOP"),
                  L(3, sym("RETURN-FROM"), s.name, cons(sym("%LOOP"), pass)));
    obj body = s.initially;
    body = append1(body, inner);
    for (obj l = s.finally; iscons(l); l = cdr(l)) body = append1(body, car(l));
    body = append1(body, s.result);
    obj let = cons(sym("LET*"), cons(s.bindings, body));
    return L(3, sym("BLOCK"), s.name, let);
}

void init_loop(void)
{
    defsubr("%LOOP-EXPAND", f_loop_expand, 1, 1);
}
