/* Pocket Lisp -- the evaluator: eval with proper tail calls, apply, lambda
 * lists, the special forms, frames for leaving early (block, catch,
 * unwind-protect, %catch-errors) and errors. CPC Lisp's src/eval.asm. */
#include "lisp.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ---- frames ---- */

enum { F_TOP, F_BLOCK, F_CATCH, F_UNWIND, F_ERRORS };
typedef struct frame {
    struct frame *prev;
    int kind;
    obj tag;                    /* a block's name, a catch's tag */
    obj cleanup, env;           /* unwind-protect's forms and their env */
    obj specials;               /* the special bindings when it was made */
    int depth;
    obj value;                  /* what is handed to it */
    sink *out;                  /* the output when it was made */
    jmp_buf jb;
} frame;
static frame *frames;
static obj specials;            /* ((symbol . old value) ...) */
static int depth;
#define MAX_DEPTH 20000
obj tail_form, tail_env;
extern obj S_EXPANDED;
obj mv_vals[64];
int mv_count;

void mark_extra_roots(void (*mark)(obj))
{
    mark(specials);
    mark(tail_form);
    mark(tail_env);
    for (int i = 0; i < 64; i++)
        mark(mv_vals[i]);
    for (frame *f = frames; f; f = f->prev) {
        mark(f->tag);
        mark(f->cleanup);
        mark(f->env);
        mark(f->specials);
        mark(f->value);
    }
}

static void unbind_to(obj saved)
{
    while (specials != saved && specials != NIL) {
        obj b = car(specials);
        SYM(car(b))->value = cdr(b);
        specials = cdr(specials);
    }
}

static void bind_special(obj sym, obj val)
{
    specials = cons(cons(sym, SYM(sym)->value), specials);
    SYM(sym)->value = val;
}

/* leave to frame f, running the cleanups of the unwind-protects passed */
static void __attribute__((noreturn)) unwind_to(frame *f, obj value)
{
    while (frames != f) {
        frame *g = frames;
        frames = g->prev;
        if (g->kind == F_UNWIND) {
            unbind_to(g->specials);
            depth = g->depth;
            progn(g->cleanup, g->env);
        }
    }
    unbind_to(f->specials);
    depth = f->depth;
    f->value = value;
    out = f->out;
    longjmp(f->jb, 1);
}

#define PUSH_FRAME(fr, k, t) do { (fr).prev = frames; (fr).kind = (k); \
    (fr).tag = (t); (fr).cleanup = NIL; (fr).env = NIL; \
    (fr).specials = specials; (fr).depth = depth; (fr).value = NIL; \
    (fr).out = out; frames = &(fr); } while (0)

/* ---- errors ---- */

static int uncatchable(obj msg)
{
    static const char *never[] = {"break", "out of memory", "stack overflow", NULL};
    if (!isstring(msg))
        return 0;
    for (int i = 0; never[i]; i++)
        if (str_len(msg) == strlen(never[i]) && !memcmp(str_chars(msg), never[i], str_len(msg)))
            return 1;
    return 0;
}

static void __attribute__((noreturn)) lisp_raise(obj msg, obj objs)
{
    int catchable = !uncatchable(msg);
    for (frame *f = frames; f; f = f->prev) {
        if (f->kind == F_ERRORS && catchable)
            unwind_to(f, cons(msg, objs));
        if (f->kind == F_TOP) {
            extern void reset_sinks(void);
            reset_sinks();
            fresh_line();
            putstr("Error: ");
            princ(msg);
            for (obj l = objs; iscons(l); l = cdr(l)) {
                putch(' ');
                prin1(car(l));
            }
            newline();
            unwind_to(f, NIL);
        }
    }
    fprintf(stderr, "pocket: an error with no top level\n");
    exit(1);
}

void lisp_error(const char *msg, obj o)
{
    obj m = mkstr(msg);
    lisp_raise(m, o == NOOBJ ? NIL : cons(o, NIL));
}

void lisp_error0(const char *msg)
{
    lisp_raise(mkstr(msg), NIL);
}

void lisp_error_msg(obj msg)
{
    lisp_raise(msg, NIL);
}

/* drop_lazy: when the cells run out, every function read lazily from its
 * file (%LAZY: (stub file . position)) goes back to its stub, to be read
 * again when next called -- as CPC Lisp's lib/short.asm does */
void drop_lazy(void)
{
    obj ind = find_symbol("%LAZY", 5);
    if (ind == UNBOUND)
        return;
    for (uint32_t i = 1; i < nsyms; i++) {
        obj s = mksym(i);
        for (obj p = SYM(s)->plist; iscons(p) && iscons(cdr(p)); p = cdr(cdr(p)))
            if (car(p) == ind) {
                obj e = car(cdr(p));
                if (iscons(e) && SYM(s)->fn != car(e) && (SYM(s)->flags & SF_LIBDEF))
                    SYM(s)->fn = car(e);
                break;
            }
    }
}

void lisp_signal(obj condition)
{
    lisp_raise(condition, NIL);
}

/* ---- variables ---- */

static obj env_lookup(obj sym, obj env)
{
    for (; env != NIL; env = cdr(env)) {
        obj b = car(env);
        if (car(b) == sym)
            return b;
    }
    return NIL;
}

obj sym_value(obj sym)
{
    obj v = SYM(sym)->value;
    if (v == UNBOUND)
        lisp_error("unbound variable", sym);
    return v;
}

static obj var_value(obj sym, obj env)
{
    if (!(SYM(sym)->flags & SF_SPECIAL)) {
        obj b = env_lookup(sym, env);
        if (b != NIL)
            return cdr(b);
    }
    return sym_value(sym);
}

void set_value(obj sym, obj v)
{
    if (SYM(sym)->flags & SF_CONST)
        lisp_error("cannot change a constant:", sym);
    SYM(sym)->value = v;
}

static void set_var(obj sym, obj v, obj env)
{
    if (!issym(sym))
        lisp_error("not a variable:", sym);
    if (!(SYM(sym)->flags & SF_SPECIAL)) {
        obj b = env_lookup(sym, env);
        if (b != NIL) {
            cdr(b) = v;
            return;
        }
    }
    set_value(sym, v);
}

/* a function name in env (flet, labels: ((name) . fn)), else global */
static obj fn_lookup(obj sym, obj env)
{
    for (; env != NIL; env = cdr(env)) {
        obj b = car(env);
        if (iscons(car(b)) && car(car(b)) == sym)
            return cdr(b);
    }
    return SYM(sym)->fn;
}

/* ---- closures and lambda lists ---- */

static obj make_closure(obj lambda, obj env)
{
    return mktyped(T_CLOSURE, cons(lambda, env));
}

static int is_amp(obj s)
{
    return s == S_AMP_OPTIONAL || s == S_AMP_REST || s == S_AMP_BODY
        || s == S_AMP_KEY || s == S_AMP_AUX;
}

static obj bind_var(obj var, obj val, obj env)
{
    if (!issym(var) || var == NIL || (SYM(var)->flags & SF_CONST))
        lisp_error0("bad lambda list");
    if (SYM(var)->flags & SF_SPECIAL) {
        bind_special(var, val);
        return env;
    }
    return cons(cons(var, val), env);
}

/* a keyword argument for var? a plain var X takes :X, by name */
static int key_matches(obj key, obj name)
{
    if (!issym(key) || !issym(name))
        return 0;
    if (key == name)
        return 1;
    obj ks = SYM(key)->name, ns = SYM(name)->name;
    uint32_t kn = str_len(ks), nn = str_len(ns);
    return kn == nn + 1 && str_chars(ks)[0] == ':'
        && !memcmp(str_chars(ks) + 1, str_chars(ns), nn);
}

/* bind: the lambda list params to the list args, in env -> the new env.
 * Destructuring: a list where a variable goes takes the argument apart. */
static obj bind(obj params, obj args, obj env)
{
    enum { REQ, OPT, REST, KEY, AUX } state = REQ;
    obj keyargs = NIL;
    int had_rest = 0;
    while (params != NIL) {
        obj p;
        if (!iscons(params)) {          /* (a b . rest) */
            env = bind_var(params, args, env);
            args = NIL;
            had_rest = 1;
            break;
        }
        p = car(params);
        params = cdr(params);
        if (is_amp(p)) {
            if (p == S_AMP_OPTIONAL) state = OPT;
            else if (p == S_AMP_REST || p == S_AMP_BODY) state = REST;
            else if (p == S_AMP_KEY) {
                state = KEY;
                if (!had_rest)
                    keyargs = args;
                else
                    keyargs = args;
            } else state = AUX;
            continue;
        }
        if (issym(p) && p != NIL && SYM(p)->name != NIL) {
            obj nm = SYM(p)->name;
            if (str_len(nm) > 0 && str_chars(nm)[0] == '&') {  /* &allow-other-keys... */
                continue;
            }
        }
        switch (state) {
        case REQ:
            if (args == NIL)
                lisp_error0("too few arguments");
            if (iscons(p)) {
                obj a = car(args);
                if (!listp(a))
                    lisp_error("not a list:", a);
                env = bind(p, a, env);
            } else
                env = bind_var(p, car(args), env);
            args = cdr(args);
            break;
        case OPT: {
            obj var = p, init = NIL, svar = NIL;
            if (iscons(p)) {
                var = car(p);
                if (iscons(cdr(p))) {
                    init = car(cdr(p));
                    if (iscons(cdr(cdr(p))))
                        svar = car(cdr(cdr(p)));
                }
            }
            if (args != NIL) {
                env = bind_var(var, car(args), env);
                args = cdr(args);
                if (svar != NIL)
                    env = bind_var(svar, S_T, env);
            } else {
                obj v = eval(init, env);
                env = bind_var(var, v, env);
                if (svar != NIL)
                    env = bind_var(svar, NIL, env);
            }
            break;
        }
        case REST:
            env = bind_var(p, args, env);
            keyargs = args;
            args = NIL;
            had_rest = 1;
            break;
        case KEY: {
            obj var = p, key = p, init = NIL, svar = NIL;
            if (iscons(p)) {
                var = car(p);
                key = var;
                if (iscons(var)) {          /* ((:key var) init) */
                    key = car(var);
                    var = car(cdr(var));
                }
                if (iscons(cdr(p))) {
                    init = car(cdr(p));
                    if (iscons(cdr(cdr(p))))
                        svar = car(cdr(cdr(p)));
                }
            }
            obj found = UNBOUND;
            for (obj k = keyargs; iscons(k) && iscons(cdr(k)); k = cdr(cdr(k)))
                if (key_matches(car(k), key)) {
                    found = car(cdr(k));
                    break;
                }
            if (found != UNBOUND) {
                env = bind_var(var, found, env);
                if (svar != NIL)
                    env = bind_var(svar, S_T, env);
            } else {
                obj v = eval(init, env);
                env = bind_var(var, v, env);
                if (svar != NIL)
                    env = bind_var(svar, NIL, env);
            }
            break;
        }
        case AUX: {
            obj var = p, init = NIL;
            if (iscons(p)) {
                var = car(p);
                if (iscons(cdr(p)))
                    init = car(cdr(p));
            }
            env = bind_var(var, eval(init, env), env);
            break;
        }
        }
    }
    if (state == KEY || had_rest)
        return env;
    if (args != NIL && state != AUX)
        lisp_error0("too many arguments");
    if (args != NIL)
        lisp_error0("too many arguments");
    return env;
}

/* ---- eval and apply ---- */

obj progn(obj body, obj env)
{
    obj v = NIL;
    for (; iscons(body); body = cdr(body))
        v = eval(car(body), env);
    return v;
}

/* a body, all but its last form evaluated: the last is the tail */
static obj body_tail(obj body, obj env)
{
    if (body == NIL)
        return NIL;
    while (iscons(cdr(body))) {
        eval(car(body), env);
        body = cdr(body);
    }
    return car(body);
}

static obj args_to_list(int argc, obj *argv)
{
    obj l = NIL;
    for (int i = argc - 1; i >= 0; i--)
        l = cons(argv[i], l);
    return l;
}

static void check_args(obj fn, const builtin *b, int argc)
{
    if (argc < b->min || (b->max != ANY && argc > b->max))
        lisp_error("wrong number of arguments for", fn);
}

/* a closure applied: its body evaluated (not a tail call) */
static obj apply_closure(obj fn, obj args)
{
    obj d = DATA(fn);
    obj lambda = car(d);
    obj saved = specials;
    obj env = bind(car(lambda), args, cdr(d));
    obj v = progn(cdr(lambda), env);
    unbind_to(saved);
    return v;
}

obj apply(obj fn, int argc, obj *argv)
{
    mv_count = 0;
    if (issym(fn))
        fn = coerce_fn(fn);
    if (istype(fn, T_SUBR)) {
        const builtin *b = &builtins[DATA(fn)];
        if (b->special)
            lisp_error("not a function:", fn);
        check_args(fn, b, argc);
        return ((subr_fn)b->fn)(argc, argv);
    }
    if (istype(fn, T_CLOSURE))
        return apply_closure(fn, args_to_list(argc, argv));
    lisp_error("not a function:", fn);
}

obj apply_list(obj fn, obj args)
{
    int n = lisp_length(args);
    obj argv[n > 0 ? n : 1];
    for (int i = 0; i < n; i++, args = cdr(args))
        argv[i] = car(args);
    return apply(fn, n, argv);
}

obj funcall1(obj fn, obj a) { return apply(fn, 1, &a); }
obj funcall2(obj fn, obj a, obj b) { obj v[2] = {a, b}; return apply(fn, 2, v); }

obj coerce_fn(obj f)
{
    if (issym(f)) {
        obj g = SYM(f)->fn;
        if (g == UNBOUND)
            lisp_error("not a function:", f);
        if (istype(g, T_MACRO) || (istype(g, T_SUBR) && builtins[DATA(g)].special))
            lisp_error("not a function:", f);
        return g;
    }
    if (istype(f, T_CLOSURE) || istype(f, T_SUBR) || istype(f, T_CODE))
        return f;
    lisp_error("not a function:", f);
}

/* macroexpand_1: a macro call's expansion (*expanded set), else the form */
obj macroexpand_1(obj form, obj env, int *expanded)
{
    *expanded = 0;
    if (!iscons(form) || !issym(car(form)))
        return form;
    obj m = fn_lookup(car(form), env);
    if (!istype(m, T_MACRO))
        return form;
    *expanded = 1;
    return apply_closure(DATA(m), cdr(form));
}

static obj quasi(obj x, obj env, int level);

int break_armed;
long break_countdown;

void poll_break(void)
{
    if (break_armed && --break_countdown <= 0) {
        break_armed = 0;
        lisp_error0("break");
    }
}

#define STACK_LIMIT (6u << 20)

obj eval(obj form, obj env)
{
    char probe;
    if (stack_base - (uintptr_t)&probe > STACK_LIMIT)
        lisp_error0("stack overflow");
    ++depth;
    if (break_armed)
        poll_break();
    obj saved_specials = specials;
    int bound = 0;
    obj v;
loop:
    if (issym(form)) {
        if (form == NIL || form == S_T) { v = form; goto done; }
        v = var_value(form, env);
        goto done;
    }
    if (!iscons(form)) { v = form; goto done; }
    {
        obj op = car(form);
        obj fn;
        if (issym(op)) {
            fn = fn_lookup(op, env);
            if (fn == UNBOUND)
                lisp_error("undefined function", op);
        } else if (iscons(op) && car(op) == S_LAMBDA) {
            fn = make_closure(cdr(op), env);
        } else {
            lisp_error("illegal function call", form);
        }
        if (istype(fn, T_SUBR) && builtins[DATA(fn)].special) {
            v = ((fsubr_fn)builtins[DATA(fn)].fn)(cdr(form), env);
            if (v == TAILCALL) {
                form = tail_form;
                env = tail_env;
                goto loop;
            }
            goto done;
        }
        if (istype(fn, T_MACRO)) {
            obj exp = apply_closure(DATA(fn), cdr(form));
            /* the call becomes (%EXPANDED (macro . expansion) op . args):
             * the expansion kept for the next time */
            obj rest = cons(car(form), cdr(form));
            obj kept = cons(cons(fn, exp), rest);
            car(form) = S_EXPANDED;
            cdr(form) = kept;
            form = exp;
            goto loop;
        }
        int n = 0;
        for (obj a = cdr(form); iscons(a); a = cdr(a))
            n++;
        obj argv[n > 0 ? n : 1];
        int i = 0;
        for (obj a = cdr(form); iscons(a); a = cdr(a)) {
            obj x = car(a);
            argv[i++] = (issym(x) && x != NIL && x != S_T) ? var_value(x, env)
                : iscons(x) ? eval(x, env) : x;
        }
        mv_count = 0;
        if (istype(fn, T_CLOSURE)) {
            obj d = DATA(fn);
            obj lambda = car(d);
            obj args = args_to_list(n, argv);
            obj before = specials;
            env = bind(car(lambda), args, cdr(d));
            if (specials != before)
                bound = 1;
            form = body_tail(cdr(lambda), env);
            goto loop;
        }
        if (istype(fn, T_SUBR)) {
            const builtin *b = &builtins[DATA(fn)];
            check_args(fn, b, n);
            v = ((subr_fn)b->fn)(n, argv);
            goto done;
        }
        lisp_error("not a function:", op);
    }
done:
    if (bound)
        unbind_to(saved_specials);
    depth--;
    return v;
}

/* ---- special forms ---- */

#define TAIL(f, e) (tail_form = (f), tail_env = (e), TAILCALL)

static obj sf_quote(obj args, obj env) { (void)env; return car(args); }

static obj sf_function(obj args, obj env)
{
    obj f = car(args);
    if (iscons(f) && car(f) == S_LAMBDA)
        return make_closure(cdr(f), env);
    if (issym(f)) {
        obj g = fn_lookup(f, env);
        if (g == UNBOUND)
            lisp_error("undefined function", f);
        return g;
    }
    lisp_error("not a function:", f);
}

static obj sf_lambda(obj args, obj env) { return make_closure(args, env); }

static obj quasi_list(obj x, obj env, int level)
{
    /* x a list template: its elements, unquote-splicing spliced */
    obj head = NIL, tail = NIL;
    while (iscons(x)) {
        obj e = car(x);
        if (e == S_UNQUOTE || e == S_QUASIQUOTE) {  /* `(a . ,b) */
            obj rest = quasi(x, env, level);
            if (tail == NIL) return rest;
            cdr(tail) = rest;
            return head;
        }
        obj part;
        if (iscons(e) && car(e) == S_UNQUOTE_SPLICING && level == 1) {
            part = eval(car(cdr(e)), env);
            /* copy all but the last list spliced (it may be shared) */
            if (iscons(cdr(x))) {
                obj c = NIL, ct = NIL;
                for (obj p = part; iscons(p); p = cdr(p)) {
                    obj n = cons(car(p), NIL);
                    if (ct == NIL) c = n; else cdr(ct) = n;
                    ct = n;
                }
                part = c;
            }
            if (part == NIL) { x = cdr(x); continue; }
            if (tail == NIL) head = part; else cdr(tail) = part;
            tail = part;
            while (iscons(cdr(tail)))
                tail = cdr(tail);
        } else {
            obj n = cons(quasi(e, env, level), NIL);
            if (tail == NIL) head = n; else cdr(tail) = n;
            tail = n;
        }
        x = cdr(x);
    }
    if (x != NIL) {
        obj r = quasi(x, env, level);
        if (tail == NIL) return r;
        cdr(tail) = r;
    }
    return head;
}

static obj quasi(obj x, obj env, int level)
{
    if (isvector(x)) {
        obj l = NIL;
        uint32_t n = vec_len(x);
        for (uint32_t i = n; i > 0; i--)
            l = cons(vec_elts(x)[i - 1], l);
        l = quasi_list(l, env, level);
        int m = lisp_length(l);
        obj v = make_blob(T_VECTOR, m * 4);
        for (int i = 0; i < m; i++, l = cdr(l))
            vec_elts(v)[i] = car(l);
        return v;
    }
    if (!iscons(x))
        return x;
    if (car(x) == S_UNQUOTE) {
        if (level == 1)
            return eval(car(cdr(x)), env);
        return list2(S_UNQUOTE, quasi(car(cdr(x)), env, level - 1));
    }
    if (car(x) == S_QUASIQUOTE)
        return list2(S_QUASIQUOTE, quasi(car(cdr(x)), env, level + 1));
    return quasi_list(x, env, level);
}

static obj sf_quasiquote(obj args, obj env) { return quasi(car(args), env, 1); }

static obj sf_if(obj args, obj env)
{
    obj c = eval(car(args), env);
    if (c != NIL)
        return TAIL(car(cdr(args)), env);
    obj e = cdr(cdr(args));
    return iscons(e) ? TAIL(car(e), env) : NIL;
}

static obj sf_when(obj args, obj env)
{
    if (eval(car(args), env) == NIL)
        return NIL;
    return TAIL(body_tail(cdr(args), env), env);
}

static obj sf_unless(obj args, obj env)
{
    if (eval(car(args), env) != NIL)
        return NIL;
    return TAIL(body_tail(cdr(args), env), env);
}

static obj sf_cond(obj args, obj env)
{
    for (; iscons(args); args = cdr(args)) {
        obj clause = car(args);
        obj t = eval(car(clause), env);
        if (t != NIL) {
            if (cdr(clause) == NIL)
                return t;
            return TAIL(body_tail(cdr(clause), env), env);
        }
    }
    return NIL;
}

static obj sf_case(obj args, obj env)
{
    obj k = eval(car(args), env);
    for (obj cl = cdr(args); iscons(cl); cl = cdr(cl)) {
        obj clause = car(cl);
        obj keys = car(clause);
        int hit = 0;
        if (keys == S_T || keys == S_OTHERWISE)
            hit = 1;
        else if (iscons(keys)) {
            for (; iscons(keys); keys = cdr(keys))
                if (eql(car(keys), k)) { hit = 1; break; }
        } else
            hit = eql(keys, k);
        if (hit)
            return TAIL(body_tail(cdr(clause), env), env);
    }
    return NIL;
}

static obj sf_and(obj args, obj env)
{
    if (args == NIL)
        return S_T;
    while (iscons(cdr(args))) {
        if (eval(car(args), env) == NIL)
            return NIL;
        args = cdr(args);
    }
    return TAIL(car(args), env);
}

static obj sf_or(obj args, obj env)
{
    if (args == NIL)
        return NIL;
    while (iscons(cdr(args))) {
        obj v = eval(car(args), env);
        if (v != NIL)
            return v;
        args = cdr(args);
    }
    return TAIL(car(args), env);
}

static obj sf_progn(obj args, obj env) { return TAIL(body_tail(args, env), env); }

static obj sf_prog1(obj args, obj env)
{
    obj v = eval(car(args), env);
    progn(cdr(args), env);
    return v;
}

static obj sf_setq(obj args, obj env)
{
    obj v = NIL;
    while (iscons(args)) {
        obj s = car(args);
        if (!iscons(cdr(args)))
            lisp_error0("too few arguments");
        v = eval(car(cdr(args)), env);
        set_var(s, v, env);
        args = cdr(cdr(args));
    }
    return v;
}

/* ---- setf: places ---- */

extern obj setf_place(obj place, obj value, obj env);   /* subrs.c */
extern obj place_value(obj place, obj env);

obj setf_place(obj place, obj value, obj env);

static obj sf_setf(obj args, obj env)
{
    obj v = NIL;
    while (iscons(args)) {
        if (!iscons(cdr(args)))
            lisp_error0("too few arguments");
        obj place = car(args);
        v = eval(car(cdr(args)), env);
        if (issym(place))
            set_var(place, v, env);
        else
            v = setf_place(place, v, env);
        args = cdr(cdr(args));
    }
    return v;
}

/* the value at a place, read as a form */
obj place_value(obj place, obj env) { return eval(place, env); }

static obj incdec(obj args, obj env, int sign)
{
    obj place = car(args);
    obj delta = iscons(cdr(args)) ? eval(car(cdr(args)), env) : mkfix(1);
    obj old = eval(place, env);
    obj v = sign > 0 ? num_add(old, delta) : num_sub(old, delta);
    if (issym(place))
        set_var(place, v, env);
    else
        setf_place(place, v, env);
    return v;
}

static obj sf_incf(obj args, obj env) { return incdec(args, env, 1); }
static obj sf_decf(obj args, obj env) { return incdec(args, env, -1); }

static obj sf_push(obj args, obj env)
{
    obj item = eval(car(args), env);
    obj place = car(cdr(args));
    obj v = cons(item, eval(place, env));
    if (issym(place))
        set_var(place, v, env);
    else
        setf_place(place, v, env);
    return v;
}

static obj sf_pop(obj args, obj env)
{
    obj place = car(args);
    obj l = eval(place, env);
    if (!listp(l))
        lisp_error("not a list:", l);
    obj rest = l == NIL ? NIL : cdr(l);
    if (issym(place))
        set_var(place, rest, env);
    else
        setf_place(place, rest, env);
    return l == NIL ? NIL : car(l);
}

/* ---- let, flet ---- */

static obj sf_let_common(obj args, obj env, int star)
{
    obj saved = specials;
    obj newenv = env;
    obj specs = NIL;            /* let: specials bound after all are evaluated */
    for (obj b = car(args); iscons(b); b = cdr(b)) {
        obj var = car(b), init = NIL;
        if (iscons(var)) {
            init = iscons(cdr(var)) ? car(cdr(var)) : NIL;
            var = car(var);
        }
        obj v = eval(init, star ? newenv : env);
        if (!issym(var) || var == NIL || (SYM(var)->flags & SF_CONST))
            lisp_error("not a variable:", var);
        if (SYM(var)->flags & SF_SPECIAL) {
            if (star)
                bind_special(var, v);
            else
                specs = cons(cons(var, v), specs);
        } else
            newenv = cons(cons(var, v), newenv);
    }
    for (; specs != NIL; specs = cdr(specs))
        bind_special(car(car(specs)), cdr(car(specs)));
    if (specials == saved)
        return TAIL(body_tail(cdr(args), newenv), newenv);
    obj v = progn(cdr(args), newenv);
    unbind_to(saved);
    return v;
}

static obj sf_let(obj args, obj env) { return sf_let_common(args, env, 0); }
static obj sf_letstar(obj args, obj env) { return sf_let_common(args, env, 1); }

static obj block_wrap(obj name, obj body)
{
    return cons(cons(S_BLOCK, cons(name, body)), NIL);
}

/* a function's lambda: (params . body) with its body in a block named
 * after it; a leading documentation string dropped */
static obj named_lambda(obj name, obj params, obj body)
{
    if (iscons(body) && isstring(car(body)) && iscons(cdr(body)))
        body = cdr(body);
    obj decls = NIL, dt = NIL;
    while (iscons(body) && iscons(car(body)) && car(car(body)) == S_DECLARE) {
        obj n = cons(car(body), NIL);
        if (dt == NIL) decls = n; else cdr(dt) = n;
        dt = n;
        body = cdr(body);
    }
    obj b = block_wrap(name, body);
    if (dt != NIL) { cdr(dt) = b; b = decls; }
    return cons(params, b);
}

static obj sf_flet_common(obj args, obj env, int labels)
{
    obj newenv = env;
    obj cells_ = NIL;
    for (obj d = car(args); iscons(d); d = cdr(d)) {
        obj def = car(d);
        obj name = car(def);
        obj b = cons(cons(name, NIL), NIL);
        newenv = cons(b, newenv);
        cells_ = cons(cons(b, def), cells_);
    }
    for (obj c = cells_; c != NIL; c = cdr(c)) {
        obj b = car(car(c)), def = cdr(car(c));
        obj lam = named_lambda(car(def), car(cdr(def)), cdr(cdr(def)));
        cdr(b) = make_closure(lam, labels ? newenv : env);
    }
    return TAIL(body_tail(cdr(args), newenv), newenv);
}

static obj sf_flet(obj args, obj env) { return sf_flet_common(args, env, 0); }
static obj sf_labels(obj args, obj env) { return sf_flet_common(args, env, 1); }

/* ---- definitions ---- */

extern int loading_library;

static uint32_t def_counter;

void mark_def_seq(obj name) { SYM(name)->defseq = ++def_counter; }

static void mark_def(obj name)
{
    mark_def_seq(name);
    if (loading_library) {
        SYM(name)->flags |= SF_LIBDEF;
        SYM(name)->flags &= ~SF_USERDEF;
    } else {
        SYM(name)->flags |= SF_USERDEF;
        SYM(name)->flags &= ~SF_LIBDEF;
    }
}

static obj sf_defun(obj args, obj env)
{
    obj name = check_sym(car(args));
    obj lam = named_lambda(name, car(cdr(args)), cdr(cdr(args)));
    SYM(name)->fn = make_closure(lam, env);
    mark_def(name);
    return name;
}

static obj sf_defmacro(obj args, obj env)
{
    obj name = check_sym(car(args));
    obj lam = named_lambda(name, car(cdr(args)), cdr(cdr(args)));
    SYM(name)->fn = mktyped(T_MACRO, make_closure(lam, env));
    mark_def(name);
    return name;
}

static obj sf_defvar(obj args, obj env)
{
    obj name = check_sym(car(args));
    SYM(name)->flags |= SF_SPECIAL;
    if (iscons(cdr(args)) && SYM(name)->value == UNBOUND)
        SYM(name)->value = eval(car(cdr(args)), env);
    mark_def(name);
    return name;
}

static obj sf_defparameter(obj args, obj env)
{
    obj name = check_sym(car(args));
    SYM(name)->flags |= SF_SPECIAL;
    SYM(name)->value = eval(car(cdr(args)), env);
    mark_def(name);
    return name;
}

static obj sf_defconstant(obj args, obj env)
{
    obj name = check_sym(car(args));
    SYM(name)->value = eval(car(cdr(args)), env);
    SYM(name)->flags |= SF_CONST;
    mark_def(name);
    return name;
}

/* ---- leaving early ---- */

static obj sf_block(obj args, obj env)
{
    frame f;
    PUSH_FRAME(f, F_BLOCK, car(args));
    obj v;
    if (setjmp(f.jb)) {
        frames = f.prev;
        return f.value;
    }
    v = progn(cdr(args), env);
    frames = f.prev;
    return v;
}

static obj return_from(obj name, obj value)
{
    for (frame *f = frames; f; f = f->prev)
        if (f->kind == F_BLOCK && f->tag == name)
            unwind_to(f, value);
    lisp_error("no block or catch for", name);
}

static obj sf_return_from(obj args, obj env)
{
    obj v = iscons(cdr(args)) ? eval(car(cdr(args)), env) : NIL;
    return return_from(car(args), v);
}

static obj sf_return(obj args, obj env)
{
    obj v = iscons(args) ? eval(car(args), env) : NIL;
    return return_from(NIL, v);
}

static obj sf_catch(obj args, obj env)
{
    frame f;
    obj tag = eval(car(args), env);
    PUSH_FRAME(f, F_CATCH, tag);
    if (setjmp(f.jb)) {
        frames = f.prev;
        return f.value;
    }
    obj v = progn(cdr(args), env);
    frames = f.prev;
    return v;
}

static obj sf_throw(obj args, obj env)
{
    obj tag = eval(car(args), env);
    obj v = eval(car(cdr(args)), env);
    for (frame *f = frames; f; f = f->prev)
        if (f->kind == F_CATCH && eql(f->tag, tag))
            unwind_to(f, v);
    lisp_error("no block or catch for", tag);
}

static obj sf_unwind_protect(obj args, obj env)
{
    frame f;
    PUSH_FRAME(f, F_UNWIND, NIL);
    f.cleanup = cdr(args);
    f.env = env;
    obj v = eval(car(args), env);
    int n = mv_count;
    obj keep[64];
    memcpy(keep, mv_vals, sizeof keep);
    frames = f.prev;
    progn(cdr(args), env);
    mv_count = n;
    memcpy(mv_vals, keep, sizeof keep);
    return v;
}

static obj sf_catch_errors(obj args, obj env)
{
    frame f;
    PUSH_FRAME(f, F_ERRORS, NIL);
    if (setjmp(f.jb)) {
        frames = f.prev;
        return cons(NIL, f.value);
    }
    obj v = eval(car(args), env);
    frames = f.prev;
    return cons(S_T, v);
}

/* ---- iteration ---- */

static obj sf_dolist(obj args, obj env)
{
    frame f;
    PUSH_FRAME(f, F_BLOCK, NIL);
    if (setjmp(f.jb)) {
        frames = f.prev;
        return f.value;
    }
    obj spec = car(args);
    obj var = car(spec);
    obj l = eval(car(cdr(spec)), env);
    if (!listp(l))
        lisp_error("not a list:", l);
    obj saved = specials;
    obj newenv = bind_var(var, NIL, env);
    obj cellb = newenv != env ? car(newenv) : NIL;
    for (; iscons(l); l = cdr(l)) {
        if (cellb != NIL) cdr(cellb) = car(l); else SYM(var)->value = car(l);
        progn(cdr(args), newenv);
    }
    if (cellb != NIL) cdr(cellb) = NIL; else SYM(var)->value = NIL;
    obj v = iscons(cdr(cdr(spec))) ? eval(car(cdr(cdr(spec))), newenv) : NIL;
    unbind_to(saved);
    frames = f.prev;
    return v;
}

static obj sf_dotimes(obj args, obj env)
{
    frame f;
    PUSH_FRAME(f, F_BLOCK, NIL);
    if (setjmp(f.jb)) {
        frames = f.prev;
        return f.value;
    }
    obj spec = car(args);
    obj var = car(spec);
    obj nv = eval(car(cdr(spec)), env);
    int32_t n = check_int(nv);
    obj saved = specials;
    obj newenv = bind_var(var, mkfix(0), env);
    obj cellb = newenv != env ? car(newenv) : NIL;
    for (int32_t i = 0; i < n; i++) {
        if (cellb != NIL) cdr(cellb) = mkfix(i); else SYM(var)->value = mkfix(i);
        progn(cdr(args), newenv);
    }
    if (cellb != NIL) cdr(cellb) = mkfix(n < 0 ? 0 : n); else SYM(var)->value = mkfix(n < 0 ? 0 : n);
    obj v = iscons(cdr(cdr(spec))) ? eval(car(cdr(cdr(spec))), newenv) : NIL;
    unbind_to(saved);
    frames = f.prev;
    return v;
}

static obj sf_loop(obj args, obj env)
{
    frame f;
    PUSH_FRAME(f, F_BLOCK, NIL);
    if (setjmp(f.jb)) {
        frames = f.prev;
        return f.value;
    }
    for (;;) {
        if (break_armed)
            poll_break();
        progn(args, env);
    }
}

static obj sf_declare(obj args, obj env) { (void)args; (void)env; return NIL; }

static obj sf_the(obj args, obj env) { return TAIL(car(cdr(args)), env); }

static obj sf_mvlist(obj args, obj env)
{
    mv_count = 0;
    obj v = eval(car(args), env);
    if (mv_count && mv_vals[0] == v) {
        obj l = NIL;
        for (int i = mv_count - 2; i >= 0; i--)
            l = cons(mv_vals[i], l);
        mv_count = 0;
        return l;
    }
    mv_count = 0;
    return cons(v, NIL);
}

/* (%EXPANDED (macro . expansion) op . args): the expansion, if op is
 * still that macro; else the call afresh */
static obj sf_expanded(obj args, obj env)
{
    obj kept = car(args);
    obj call = cdr(args);
    obj m = fn_lookup(car(call), env);
    if (m == car(kept))
        return TAIL(cdr(kept), env);
    if (istype(m, T_MACRO)) {
        obj exp = apply_closure(DATA(m), cdr(call));
        car(args) = cons(m, exp);
        return TAIL(exp, env);
    }
    return TAIL(call, env);
}

/* the special forms, for init_builtins */
struct sfdef { const char *name; fsubr_fn fn; };
const struct sfdef special_forms[] = {
    {"QUOTE", sf_quote}, {"FUNCTION", sf_function}, {"LAMBDA", sf_lambda},
    {"QUASIQUOTE", sf_quasiquote}, {"IF", sf_if}, {"WHEN", sf_when},
    {"UNLESS", sf_unless}, {"COND", sf_cond}, {"CASE", sf_case},
    {"AND", sf_and}, {"OR", sf_or}, {"PROGN", sf_progn}, {"PROG1", sf_prog1},
    {"SETQ", sf_setq}, {"SETF", sf_setf}, {"INCF", sf_incf}, {"DECF", sf_decf},
    {"PUSH", sf_push}, {"POP", sf_pop}, {"LET", sf_let}, {"LET*", sf_letstar},
    {"FLET", sf_flet}, {"LABELS", sf_labels}, {"DEFUN", sf_defun},
    {"DEFMACRO", sf_defmacro}, {"DEFVAR", sf_defvar},
    {"DEFPARAMETER", sf_defparameter}, {"DEFCONSTANT", sf_defconstant},
    {"BLOCK", sf_block}, {"RETURN-FROM", sf_return_from}, {"RETURN", sf_return},
    {"CATCH", sf_catch}, {"THROW", sf_throw}, {"DOLIST", sf_dolist},
    {"DOTIMES", sf_dotimes}, {"%LOOP", sf_loop}, {"DECLARE", sf_declare},
    {"THE", sf_the}, {"UNWIND-PROTECT", sf_unwind_protect},
    {"MULTIPLE-VALUE-LIST", sf_mvlist}, {"%EXPANDED", sf_expanded},
    {"%CATCH-ERRORS", sf_catch_errors},
    {0, 0}
};

/* ---- the top level ---- */

static frame top;

/* toplevel_run: fn() under a top-level frame -> 0, or 1 after an error
 * (printed, cleanups run) */
int toplevel_run(void (*fn)(void *), void *arg)
{
    frame *outer = frames;
    obj saved = specials;
    PUSH_FRAME(top, F_TOP, NIL);
    if (setjmp(top.jb)) {
        frames = outer;
        unbind_to(saved);
        depth = 0;
        mv_count = 0;
        return 1;
    }
    fn(arg);
    frames = outer;
    return 0;
}

obj bind_lambda_list(obj params, obj args, obj env) { return bind(params, args, env); }
obj setq_var(obj s, obj v, obj env) { set_var(s, v, env); return v; }
obj closure_apply_list(obj fn, obj args) { return apply_closure(fn, args); }
obj make_closure_pub(obj lambda, obj env) { return make_closure(lambda, env); }
obj fn_lookup_pub(obj sym, obj env) { return fn_lookup(sym, env); }
