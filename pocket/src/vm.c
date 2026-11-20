/* Pocket Lisp -- the bytecode machine (CPC Lisp's lib/vm.asm): runs what
 * lib/compiler.lsp makes, byte for byte the same code.
 *
 * A compiled function is a typed cell T_CODE whose data is its code
 * vector V -- [bytecode string][name][constants...] -- or (V . env) for a
 * closure. The machine is CPC Lisp's: a stack of words growing down, a
 * frame from IX up --
 *
 *     ix+0  ENV   the closure's environment (CLO k is its kth)
 *     ix+1..3     (CPC Lisp's CB, PB, GCN: unused here, fixnum 0)
 *     ix+4  V     the code vector
 *     ix+5..9     (the caller's IX and four words: unused, 0)
 *     ix+10 the arguments, the last first: arg i at ix + 10 + (n-1-i)
 *
 * -- and locals below IX. The compiler's operands are the Z80's byte
 * offsets (LOC 20 is the last argument, LOC -2 the first local): halved
 * here, each place a 32-bit word. The stack is a GC root. */
#include "lisp.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VMWORDS (1 << 16)
static obj vmstack[VMWORDS];
static int vsp = VMWORDS;               /* the top: vmstack[vsp] */

#define F_ENV 0
#define F_V 4
#define F_ARGS 10

static obj S_SET_AREF;

void vm_mark_roots(void (*mark)(obj))
{
    for (int i = vsp; i < VMWORDS; i++)
        if (!isfix(vmstack[i]))
            mark(vmstack[i]);
}

static inline void push(obj o)
{
    if (vsp <= 64)
        lisp_error0("stack overflow");
    vmstack[--vsp] = o;
}

#define POP() (vmstack[vsp++])
#define TOP() (vmstack[vsp])

static obj code_vector(obj fn, obj *env)
{
    obj d = DATA(fn);
    if (iscons(d)) {
        *env = cdr(d);
        return car(d);
    }
    *env = NIL;
    return d;
}

static const uint8_t *bytes_of(obj v) { return (const uint8_t *)str_chars(vec_elts(v)[0]); }

static obj nth_env(obj env, int k)
{
    while (k-- > 0 && iscons(env))
        env = cdr(env);
    return iscons(env) ? car(env) : NIL;
}

static obj check_cons(obj o)
{
    if (!iscons(o))
        lisp_error("not a list:", o);
    return o;
}

extern obj seq_ref(obj seq, obj i);
extern int break_armed;
extern void poll_break(void);
void unbind_specials_to(obj saved);
obj specials_now(void);
void bind_special_pub(obj sym, obj val);

/* the arguments of a call: argc of them on the stack under the top's
 * place, the first deepest -> a C array copy */
static obj vm_apply(obj fn, int argc);

/* lay out a frame for fn with argc arguments already pushed */
static int make_frame(obj fn, int argc, obj *V)
{
    obj env;
    obj v = code_vector(fn, &env);
    *V = v;
    for (int i = 9; i >= 0; i--) {
        obj w = mkfix(0);
        if (i == F_V) w = v;
        else if (i == F_ENV) w = env;
        else if (i == 9) w = mkfix(argc);
        push(w);
    }
    return vsp;
}

/* run fn, its argc arguments pushed (the first deepest) -> its value; the
 * arguments are gone from the stack after */
static obj vm_run(obj fn, int argc)
{
    obj V;
    int ix, n, pc;
    obj saved_specials = specials_now();
enter:
    n = argc;
    ix = make_frame(fn, argc, &V);
    pc = 0;
    for (;;) {
        const uint8_t *code = bytes_of(V);
        int op = code[pc++] / 3;
        obj a, b, x;
        switch (op) {
        case 1: push(vec_elts(V)[2 + code[pc++]]); break;          /* CONST */
        case 2: push(NIL); break;
        case 3: push(S_T); break;
        case 4: push(mkfix((int8_t)code[pc++])); break;             /* FIX */
        case 5: push(vmstack[ix + (int8_t)code[pc++] / 2]); break;  /* LOC */
        case 6: vmstack[ix + (int8_t)code[pc++] / 2] = TOP(); break;/* SETLOC */
        case 7: push(car(check_cons(vmstack[ix + (int8_t)code[pc++] / 2]))); break;
        case 8: car(vmstack[ix + (int8_t)code[pc++] / 2]) = TOP(); break;
        case 9: push(nth_env(vmstack[ix + F_ENV], code[pc++])); break;  /* CLO */
        case 10: push(car(nth_env(vmstack[ix + F_ENV], code[pc++]))); break;
        case 11: car(nth_env(vmstack[ix + F_ENV], code[pc++])) = TOP(); break;
        case 12: push(sym_value(vec_elts(V)[2 + code[pc++]])); break;   /* GLOB */
        case 13: set_value(vec_elts(V)[2 + code[pc++]], TOP()); break;
        case 14: x = cons(TOP(), NIL); TOP() = x; break;            /* BOX */
        case 15: case 16: case 17: case 18: push(vmstack[ix + F_ARGS + op - 15]); break;
        case 19: case 20: case 21: case 22: push(vmstack[ix - (op - 18)]); break;
        case 23: vsp++; break;                                      /* DROP */
        case 24: x = TOP(); push(x); break;                         /* DUP */
        case 25: x = POP(); vsp += code[pc++]; push(x); break;      /* SLIDE */
        case 26: pc += 2 + (int16_t)(code[pc] | code[pc + 1] << 8); if (break_armed) poll_break(); break;
        case 27: x = POP(); pc += x == NIL ? 2 + (int16_t)(code[pc] | code[pc + 1] << 8) : 2; break;
        case 28: x = POP(); pc += x != NIL ? 2 + (int16_t)(code[pc] | code[pc + 1] << 8) : 2; break;
        case 29: if (TOP() == NIL) pc += 2 + (int16_t)(code[pc] | code[pc + 1] << 8); else { vsp++; pc += 2; } break;
        case 30: if (TOP() != NIL) pc += 2 + (int16_t)(code[pc] | code[pc + 1] << 8); else { vsp++; pc += 2; } break;
        case 31: {                                                  /* CALL b */
            int k = code[pc++];
            x = vm_apply(vmstack[vsp + k], k);
            vsp++;                                                  /* the function */
            push(x);
            break;
        }
        case 32: case 77: {                                         /* TCALL b, TCALLG k n */
            int k;
            obj f;
            if (op == 32) {
                k = code[pc++];
                f = vmstack[vsp + k];
            } else {
                f = vec_elts(V)[2 + code[pc++]];
                k = code[pc++];
            }
            if (issym(f)) {
                obj g = SYM(f)->fn;
                if (g == UNBOUND)
                    lisp_error("undefined function", f);
                f = g;
            }
            if (break_armed)
                poll_break();
            if (istype(f, T_CODE)) {
                /* it takes this frame's place: its arguments where ours were */
                obj args[k > 0 ? k : 1];
                for (int i = 0; i < k; i++)
                    args[i] = vmstack[vsp + k - 1 - i];
                vsp = ix + F_ARGS + n;
                for (int i = 0; i < k; i++)
                    push(args[i]);
                fn = f;
                argc = k;
                goto enter;
            }
            x = vm_apply(f, k);
            if (op == 32) vsp++;
            vsp = ix + F_ARGS + n;
            unbind_specials_to(saved_specials);
            return x;
        }
        case 33:                                                    /* RET */
            x = POP();
            vsp = ix + F_ARGS + n;
            unbind_specials_to(saved_specials);
            return x;
        case 34:                                                    /* ENTER b */
            if (code[pc++] != n)
                lisp_error("wrong number of arguments for", vec_elts(V)[1]);
            break;
        case 35: {                                                  /* ARGS */
            int nreq = code[pc++], nopt = code[pc++], flags = code[pc++];
            int kc = 0, nk = 0;
            if (flags & 2) {
                kc = code[pc++];
                nk = code[pc++];
            }
            if (n < nreq)
                lisp_error("wrong number of arguments for", vec_elts(V)[1]);
            int c = nreq + nopt;
            int m = n < c ? n : c;
            for (int i = 0; i < m; i++)
                push(vmstack[ix + F_ARGS + n - 1 - i]);
            for (int i = m; i < c; i++)
                push(UNBOUND);
            int more = n > c ? n - c : 0;
            if (!(flags & 3) && more)
                lisp_error("wrong number of arguments for", vec_elts(V)[1]);
            if (flags & 1) {
                obj l = NIL;
                for (int i = n - 1; i >= c; i--)
                    l = cons(vmstack[ix + F_ARGS + n - 1 - i], l);
                push(l);
            }
            if (flags & 2) {
                for (int j = 0; j < nk; j++) {
                    obj kwd = vec_elts(V)[2 + kc + j];
                    obj val = UNBOUND;
                    for (int i = c; i + 1 < n; i += 2)
                        if (vmstack[ix + F_ARGS + n - 1 - i] == kwd) {
                            val = vmstack[ix + F_ARGS + n - 2 - i];
                            break;
                        }
                    push(val);
                }
            }
            break;
        }
        case 36: {                                                  /* MKCLO b c */
            obj f = vec_elts(V)[2 + code[pc++]];
            int k = code[pc++];
            if (k == 0) {
                push(f);
                break;
            }
            obj env = NIL;
            for (int i = 0; i < k; i++)
                env = cons(vmstack[vsp + i], env);
            vsp += k;
            obj fv = DATA(f);
            if (iscons(fv)) fv = car(fv);
            x = mktyped(T_CODE, cons(fv, env));
            push(x);
            break;
        }
        case 37: {                                                  /* GFN b */
            obj s = vec_elts(V)[2 + code[pc++]];
            obj g = SYM(s)->fn;
            if (g == UNBOUND)
                lisp_error("undefined function", s);
            push(g);
            break;
        }
        case 38: x = TOP(); TOP() = x == NIL ? NIL : car(check_cons(x)); break;
        case 39: x = TOP(); TOP() = x == NIL ? NIL : cdr(check_cons(x)); break;
        case 40: b = POP(); a = TOP(); TOP() = cons(a, b); break;
        case 41: b = POP(); TOP() = bool_obj(TOP() == b); break;
        case 42: TOP() = bool_obj(TOP() == NIL); break;
        case 43: TOP() = bool_obj(iscons(TOP())); break;
        case 44: TOP() = bool_obj(!iscons(TOP())); break;
        case 45: b = POP(); TOP() = num_add(check_number(TOP()), check_number(b)); break;
        case 46: b = POP(); TOP() = num_sub(check_number(TOP()), check_number(b)); break;
        case 47: TOP() = num_add(check_number(TOP()), mkfix(1)); break;
        case 48: TOP() = num_sub(check_number(TOP()), mkfix(1)); break;
        case 49: b = POP(); TOP() = bool_obj(num_cmp(check_number(TOP()), check_number(b)) < 0); break;
        case 50: b = POP(); TOP() = bool_obj(num_cmp(check_number(TOP()), check_number(b)) > 0); break;
        case 51: b = POP(); TOP() = bool_obj(num_cmp(check_number(TOP()), check_number(b)) <= 0); break;
        case 52: b = POP(); TOP() = bool_obj(num_cmp(check_number(TOP()), check_number(b)) >= 0); break;
        case 53: b = POP(); TOP() = bool_obj(num_cmp(check_number(TOP()), check_number(b)) == 0); break;
        case 54: b = POP(); a = TOP(); if (!iscons(a)) lisp_error("not a cons:", a); car(a) = b; TOP() = b; break;
        case 55: b = POP(); a = TOP(); if (!iscons(a)) lisp_error("not a cons:", a); cdr(a) = b; TOP() = b; break;
        case 56: x = TOP(); x = x == NIL ? NIL : cdr(check_cons(x)); TOP() = x == NIL ? NIL : car(check_cons(x)); break;
        case 57: x = TOP(); x = x == NIL ? NIL : cdr(check_cons(x)); TOP() = x == NIL ? NIL : cdr(check_cons(x)); break;
        case 58: b = POP(); TOP() = bool_obj(eql(TOP(), b)); break;
        case 59: TOP() = bool_obj(num_cmp(check_number(TOP()), mkfix(0)) == 0); break;
        case 60: push(specials_now()); break;                       /* SPECS */
        case 61: {                                                  /* BIND b */
            obj s = vec_elts(V)[2 + code[pc++]];
            x = POP();
            bind_special_pub(s, x);
            break;
        }
        case 62: {                                                  /* LIST b */
            int k = code[pc++];
            obj l = NIL;
            for (int i = 0; i < k; i++)
                l = cons(vmstack[vsp + i], l);
            vsp += k;
            push(l);
            break;
        }
        case 63: {                                                  /* MVLIST */
            x = TOP();
            obj l;
            if (mv_count && mv_vals[0] == x) {
                l = NIL;
                for (int i = mv_count - 2; i >= 0; i--)
                    l = cons(mv_vals[i], l);
            } else
                l = cons(x, NIL);
            mv_count = 0;
            TOP() = l;
            break;
        }
        case 64: TOP() = bool_obj(issym(TOP())); break;
        case 65: {                                                  /* JSUP s w */
            int s = (int8_t)code[pc++];
            if (vmstack[ix + s / 2] != UNBOUND)
                pc += 2 + (int16_t)(code[pc] | code[pc + 1] << 8);
            else
                pc += 2;
            break;
        }
        case 66: push(bool_obj(vmstack[ix + (int8_t)code[pc++] / 2] != UNBOUND)); break;
        case 67: mv_count = 0; break;
        case 68: unbind_specials_to(vmstack[ix + (int8_t)code[pc++] / 2]); break;
        case 69: vsp = ix; break;                                   /* SPIX */
        case 70: vmstack[ix + (int8_t)code[pc++] / 2] = POP(); break;
        case 71: pc += 1 + (int8_t)code[pc]; if (break_armed) poll_break(); break;
        case 72: x = POP(); pc += x == NIL ? 1 + (int8_t)code[pc] : 1; break;
        case 73: x = POP(); pc += x != NIL ? 1 + (int8_t)code[pc] : 1; break;
        case 74: if (TOP() == NIL) pc += 1 + (int8_t)code[pc]; else { vsp++; pc++; } break;
        case 75: if (TOP() != NIL) pc += 1 + (int8_t)code[pc]; else { vsp++; pc++; } break;
        case 76: {                                                  /* CALLG k n */
            obj f = vec_elts(V)[2 + code[pc++]];
            int k = code[pc++];
            /* the arguments are the top k; vm_apply takes them under a
             * function's place: give it one */
            obj args[k > 0 ? k : 1];
            for (int i = 0; i < k; i++)
                args[i] = vmstack[vsp + k - 1 - i];
            vsp += k;
            push(f);
            for (int i = 0; i < k; i++)
                push(args[i]);
            x = vm_apply(f, k);
            vsp++;
            push(x);
            break;
        }
        case 80: TOP() = bool_obj(check_int(TOP()) & 1); break;
        case 81: TOP() = bool_obj(!(check_int(TOP()) & 1)); break;
        case 82: b = POP(); TOP() = num_mul(check_number(TOP()), check_number(b)); break;
        case 83: b = POP(); TOP() = seq_ref(TOP(), b); break;       /* AREF */
        case 84: {                                                  /* SETAREF k */
            obj f = vec_elts(V)[2 + code[pc++]];
            obj xv = vmstack[vsp], iv = vmstack[vsp + 1], vv = vmstack[vsp + 2];
            if (isvector(vv) && isfix(iv) && fixval(iv) >= 0 && (uint32_t)fixval(iv) < vec_len(vv)) {
                vec_elts(vv)[fixval(iv)] = xv;
                vsp += 2;
                TOP() = xv;
            } else {
                obj argv3[3] = {vv, iv, xv};
                x = apply(coerce_fn(f), 3, argv3);
                vsp += 2;
                TOP() = x;
            }
            break;
        }
        default:
            lisp_error("not a function:", vec_elts(V)[1]);
        }
    }
}

/* fn with its k arguments on the stack (the first deepest, the function's
 * place under them) -> its value; the arguments popped, the place left */
static obj vm_apply(obj fn, int k)
{
    if (issym(fn)) {
        obj g = SYM(fn)->fn;
        if (g == UNBOUND)
            lisp_error("undefined function", fn);
        fn = g;
    }
    mv_count = 0;
    if (istype(fn, T_CODE))
        return vm_run(fn, k);
    obj args[k > 0 ? k : 1];
    for (int i = 0; i < k; i++)
        args[i] = vmstack[vsp + k - 1 - i];
    obj v = apply(fn, k, args);
    vsp += k;
    return v;
}

/* from the interpreter: a compiled function applied to argv */
obj vm_call(obj fn, int argc, obj *argv)
{
    int saved = vsp;
    for (int i = 0; i < argc; i++)
        push(argv[i]);
    obj v = vm_run(fn, argc);
    vsp = saved;
    return v;
}

/* after an error, a frame the longjmp left: the stack back to what it was */
int vm_depth(void) { return vsp; }
void vm_reset(int to) { vsp = to; }

/* ---- the compiler's natives ---- */

static obj make_code(obj bytes_str, obj consts, obj name)
{
    int n = lisp_length(consts);
    obj v = make_blob(T_VECTOR, (size_t)(n + 2) * 4);
    vec_elts(v)[0] = bytes_str;
    vec_elts(v)[1] = name;
    int i = 2;
    for (obj l = consts; iscons(l); l = cdr(l))
        vec_elts(v)[i++] = car(l);
    return mktyped(T_CODE, v);
}

/* (%make-code bytes constants name) */
static obj f_make_code(int c, obj *a)
{
    (void)c;
    int n = lisp_length(a[0]);
    obj s = make_blob(T_STRING, (size_t)n);
    int i = 0;
    for (obj l = a[0]; iscons(l); l = cdr(l))
        str_chars(s)[i++] = (char)check_int(car(l));
    return make_code(s, a[1], a[2]);
}

/* (%code hex constants name): from compile-file's text */
static obj f_code(int c, obj *a)
{
    (void)c;
    size_t total = 0;
    for (obj l = a[0]; iscons(l); l = cdr(l))
        total += str_len(check_string(car(l))) / 2;
    obj s = make_blob(T_STRING, total);
    size_t k = 0;
    for (obj l = a[0]; iscons(l); l = cdr(l)) {
        const char *h = str_chars(car(l));
        uint32_t m = str_len(car(l));
        for (uint32_t i = 0; i + 1 < m; i += 2) {
            char t[3] = {h[i], h[i + 1], 0};
            str_chars(s)[k++] = (char)strtol(t, NULL, 16);
        }
    }
    return make_code(s, a[1], a[2]);
}

static obj f_vm_release(int c, obj *a) { (void)c; (void)a; return NIL; }

/* (%fn-info x): 0 nothing, 1 a macro, 2 interpreted, 3 compiled, 4 another */
static obj f_fn_info(int c, obj *a)
{
    (void)c;
    obj f = a[0];
    if (issym(f)) {
        f = SYM(f)->fn;
        if (f == UNBOUND)
            return mkfix(0);
    }
    if (istype(f, T_MACRO)) return mkfix(1);
    if (istype(f, T_CLOSURE)) return mkfix(2);
    if (istype(f, T_CODE)) return mkfix(3);
    if (istype(f, T_SUBR)) return mkfix(builtins[DATA(f)].special ? 0 : 4);
    return mkfix(0);
}

static obj f_fn_data(int c, obj *a)
{
    (void)c;
    obj f = a[0];
    if (istype(f, T_MACRO))
        f = DATA(f);
    if (istype(f, T_CLOSURE))
        return DATA(f);
    return NIL;
}

static obj f_symbol_flags(int c, obj *a)
{
    (void)c;
    obj s = a[0];
    if (!issym(s))
        return mkfix(0);
    if (s == NIL || s == S_T)
        return mkfix(2);
    uint32_t f = SYM(s)->flags;
    return mkfix(((f & SF_SPECIAL) ? 1 : 0) | ((f & SF_CONST) ? 2 : 0));
}

static const char *op_names[] = {"BAD", "CONST", "NIL", "T", "FIX", "LOC", "SETLOC",
    "LOCB", "SETLOCB", "CLO", "CLOB", "SETCLOB", "GLOB", "SETGLOB", "BOX", "A0", "A1",
    "A2", "A3", "L0", "L1", "L2", "L3", "DROP", "DUP", "SLIDE", "JMP", "JNIL", "JT",
    "JNILK", "JTK", "CALL", "TCALL", "RET", "ENTER", "ARGS", "MKCLO", "GFN", "CAR", "CDR",
    "CONS", "EQ", "NOT", "CONSP", "ATOM", "ADD", "SUB", "ADD1", "SUB1", "LT", "GT", "LE",
    "GE", "NUMEQ", "SETCAR", "SETCDR", "CADR", "CDDR", "EQL", "ZEROP", "SPECS", "BIND",
    "LIST", "MVLIST", "SYMBOLP", "JSUP", "SUPP", "MVCLR", "UNBINDL", "SPIX", "POPLOC",
    "JMPS", "JNILS", "JTS", "JNILKS", "JTKS", "CALLG", "TCALLG", "CALLR", "TCALLR", "ODDP",
    "EVENP", "MUL", "AREF", "SETAREF"};
static const char op_kinds[] =
    "0100222224441100000000000433333440456100000000000000000000000140072020288888999900001";

static obj f_op_name(int c, obj *a)
{
    (void)c;
    int k = check_int(a[0]);
    if (k < 0 || k >= (int)(sizeof op_names / sizeof op_names[0]))
        return mkstr("?");
    return mkstr(op_names[k]);
}

static obj f_op_kind(int c, obj *a)
{
    (void)c;
    int k = check_int(a[0]);
    if (k < 0 || k >= (int)strlen(op_kinds))
        return mkfix(0);
    return mkfix(op_kinds[k] - '0');
}

static obj code_v(obj f)
{
    if (issym(f))
        f = SYM(f)->fn;
    if (!istype(f, T_CODE))
        return UNBOUND;
    obj env;
    return code_vector(f, &env);
}

static obj f_code_bytes(int c, obj *a)
{
    (void)c;
    obj v = code_v(a[0]);
    if (v == UNBOUND)
        return NIL;
    obj s = vec_elts(v)[0];
    obj l = NIL;
    for (int i = (int)str_len(s) - 1; i >= 0; i--)
        l = cons(mkfix((uint8_t)str_chars(vec_elts(v)[0])[i]), l);
    return l;
}

static obj f_code_consts(int c, obj *a)
{
    (void)c;
    obj v = code_v(a[0]);
    if (v == UNBOUND)
        return NIL;
    obj l = NIL;
    for (int i = (int)vec_len(v) - 1; i >= 1; i--)
        l = cons(vec_elts(v)[i], l);
    return l;
}

void init_vm(void)
{
    S_SET_AREF = intern_cstr("%SET-AREF");
    defsubr("%MAKE-CODE", f_make_code, 3, 3);
    defsubr("%CODE", f_code, 3, 3);
    defsubr("%VM-RELEASE", f_vm_release, 0, 0);
    defsubr("%FN-INFO", f_fn_info, 1, 1);
    defsubr("%FN-DATA", f_fn_data, 1, 1);
    defsubr("%SYMBOL-FLAGS", f_symbol_flags, 1, 1);
    defsubr("%OP-NAME", f_op_name, 1, 1);
    defsubr("%OP-KIND", f_op_kind, 1, 1);
    defsubr("%CODE-BYTES", f_code_bytes, 1, 1);
    defsubr("%CODE-CONSTS", f_code_consts, 1, 1);
}
