/* Pocket Lisp -- numbers: 31-bit fixnums and doubles. An integer result
 * past 31 bits becomes a float, as CPC Lisp's past 15 (lib/float.asm). */
#include "lisp.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

obj mkint(int64_t n)
{
    if (n >= FIX_MIN && n <= FIX_MAX)
        return mkfix((int32_t)n);
    return mkfloat((double)n);
}

obj check_number(obj o)
{
    if (!isnumber(o))
        lisp_error("not a number:", o);
    return o;
}

double num_double(obj o)
{
    check_number(o);
    return isfix(o) ? (double)fixval(o) : floatval(o);
}

obj num_add(obj a, obj b)
{
    if (isfix(a) && isfix(b))
        return mkint((int64_t)fixval(a) + fixval(b));
    return mkfloat(num_double(a) + num_double(b));
}

obj num_sub(obj a, obj b)
{
    if (isfix(a) && isfix(b))
        return mkint((int64_t)fixval(a) - fixval(b));
    return mkfloat(num_double(a) - num_double(b));
}

obj num_mul(obj a, obj b)
{
    if (isfix(a) && isfix(b))
        return mkint((int64_t)fixval(a) * fixval(b));
    return mkfloat(num_double(a) * num_double(b));
}

obj num_div(obj a, obj b)
{
    if (isfix(a) && isfix(b)) {
        int32_t y = fixval(b);
        if (y == 0)
            lisp_error0("division by zero");
        if (fixval(a) % y == 0)
            return mkint((int64_t)fixval(a) / y);
    }
    double y = num_double(b);
    if (y == 0)
        lisp_error0("division by zero");
    return mkfloat(num_double(a) / y);
}

int num_cmp(obj a, obj b)
{
    if (isfix(a) && isfix(b))
        return fixval(a) < fixval(b) ? -1 : fixval(a) > fixval(b);
    double x = num_double(a), y = num_double(b);
    return x < y ? -1 : x > y;
}

static obj f_plus(int c, obj *a)
{
    obj s = mkfix(0);
    for (int i = 0; i < c; i++)
        s = num_add(s, check_number(a[i]));
    return s;
}

static obj f_minus(int c, obj *a)
{
    if (c == 1)
        return num_sub(mkfix(0), check_number(a[0]));
    obj s = check_number(a[0]);
    for (int i = 1; i < c; i++)
        s = num_sub(s, check_number(a[i]));
    return s;
}

static obj f_times(int c, obj *a)
{
    obj s = mkfix(1);
    for (int i = 0; i < c; i++)
        s = num_mul(s, check_number(a[i]));
    return s;
}

static obj f_divide(int c, obj *a)
{
    if (c == 1)
        return num_div(mkfix(1), check_number(a[0]));
    obj s = check_number(a[0]);
    for (int i = 1; i < c; i++)
        s = num_div(s, check_number(a[i]));
    return s;
}

static obj f_1plus(int c, obj *a) { (void)c; return num_add(check_number(a[0]), mkfix(1)); }
static obj f_1minus(int c, obj *a) { (void)c; return num_sub(check_number(a[0]), mkfix(1)); }

static obj two_values(obj q, obj r)
{
    mv_vals[0] = q;
    mv_vals[1] = r;
    mv_count = 3;
    return q;
}

/* the integer division family: kind 0 truncate, 1 floor, 2 ceiling, 3 round */
static obj divide_int(int c, obj *a, int kind)
{
    obj x = check_number(a[0]);
    obj y = c > 1 ? check_number(a[1]) : mkfix(1);
    if (isfix(x) && isfix(y)) {
        int64_t n = fixval(x), d = fixval(y);
        if (d == 0)
            lisp_error0("division by zero");
        int64_t q = n / d, r = n % d;
        if (kind == 1 && r != 0 && ((r < 0) != (d < 0))) { q--; r += d; }
        if (kind == 2 && r != 0 && ((r < 0) == (d < 0))) { q++; r -= d; }
        if (kind == 3) {
            int64_t twice = 2 * (r < 0 ? -r : r), ad = d < 0 ? -d : d;
            if (twice > ad || (twice == ad && (q & 1))) {
                if ((r < 0) == (d < 0)) { q++; r -= d; } else { q--; r += d; }
            }
        }
        return two_values(mkint(q), mkint(r));
    }
    double n = num_double(x), d = num_double(y);
    if (d == 0)
        lisp_error0("division by zero");
    double qq = n / d, q;
    if (kind == 0) q = trunc(qq);
    else if (kind == 1) q = floor(qq);
    else if (kind == 2) q = ceil(qq);
    else q = nearbyint(qq);
    double r = n - q * d;
    obj qo = (q >= FIX_MIN && q <= FIX_MAX) ? mkfix((int32_t)q) : mkfloat(q);
    return two_values(qo, mkfloat(r));
}

static obj f_truncate(int c, obj *a) { return divide_int(c, a, 0); }
static obj f_floor(int c, obj *a) { return divide_int(c, a, 1); }
static obj f_ceiling(int c, obj *a) { return divide_int(c, a, 2); }
static obj f_round(int c, obj *a) { return divide_int(c, a, 3); }

static obj f_mod(int c, obj *a)
{
    divide_int(c, a, 1);
    mv_count = 0;
    return mv_vals[1];
}

static obj f_rem(int c, obj *a)
{
    divide_int(c, a, 0);
    mv_count = 0;
    return mv_vals[1];
}

static obj f_abs(int c, obj *a)
{
    (void)c;
    obj x = check_number(a[0]);
    if (isfix(x))
        return fixval(x) < 0 ? mkint(-(int64_t)fixval(x)) : x;
    return floatval(x) < 0 ? mkfloat(-floatval(x)) : x;
}

static obj f_max(int c, obj *a)
{
    obj m = check_number(a[0]);
    for (int i = 1; i < c; i++)
        if (num_cmp(check_number(a[i]), m) > 0)
            m = a[i];
    return m;
}

static obj f_min(int c, obj *a)
{
    obj m = check_number(a[0]);
    for (int i = 1; i < c; i++)
        if (num_cmp(check_number(a[i]), m) < 0)
            m = a[i];
    return m;
}

static obj compare(int c, obj *a, int op)
{
    for (int i = 0; i < c; i++)
        check_number(a[i]);
    if (op == 5) {                  /* /=: all different */
        for (int i = 0; i < c; i++)
            for (int j = i + 1; j < c; j++)
                if (num_cmp(a[i], a[j]) == 0)
                    return NIL;
        return S_T;
    }
    for (int i = 0; i + 1 < c; i++) {
        int r = num_cmp(a[i], a[i + 1]);
        int ok = op == 0 ? r < 0 : op == 1 ? r > 0 : op == 2 ? r <= 0
            : op == 3 ? r >= 0 : r == 0;
        if (!ok)
            return NIL;
    }
    return S_T;
}

static obj f_lt(int c, obj *a) { return compare(c, a, 0); }
static obj f_gt(int c, obj *a) { return compare(c, a, 1); }
static obj f_le(int c, obj *a) { return compare(c, a, 2); }
static obj f_ge(int c, obj *a) { return compare(c, a, 3); }
static obj f_numeq(int c, obj *a) { return compare(c, a, 4); }
static obj f_numne(int c, obj *a) { return compare(c, a, 5); }
static obj f_zerop(int c, obj *a) { (void)c; return bool_obj(num_double(a[0]) == 0); }
static obj f_plusp(int c, obj *a) { (void)c; return bool_obj(num_double(a[0]) > 0); }
static obj f_minusp(int c, obj *a) { (void)c; return bool_obj(num_double(a[0]) < 0); }
static obj f_evenp(int c, obj *a) { (void)c; return bool_obj(!(check_int(a[0]) & 1)); }
static obj f_oddp(int c, obj *a) { (void)c; return bool_obj(check_int(a[0]) & 1); }

static obj f_float(int c, obj *a) { (void)c; return mkfloat(num_double(a[0])); }
static obj f_floatp(int c, obj *a) { (void)c; return bool_obj(isfloat(a[0])); }

static obj result(double d)
{
    if (isnan(d))
        lisp_error0("integer overflow");
    return mkfloat(d);
}

static obj f_sqrt(int c, obj *a) { (void)c; return result(sqrt(num_double(a[0]))); }
static obj f_exp(int c, obj *a) { (void)c; return result(exp(num_double(a[0]))); }
static obj f_sin(int c, obj *a) { (void)c; return result(sin(num_double(a[0]))); }
static obj f_cos(int c, obj *a) { (void)c; return result(cos(num_double(a[0]))); }
static obj f_tan(int c, obj *a) { (void)c; return result(tan(num_double(a[0]))); }

static obj f_log(int c, obj *a)
{
    double x = num_double(a[0]);
    if (c > 1)
        return result(log(x) / log(num_double(a[1])));
    return result(log(x));
}

static obj f_atan(int c, obj *a)
{
    if (c > 1)
        return result(atan2(num_double(a[0]), num_double(a[1])));
    return result(atan(num_double(a[0])));
}

static obj f_pow(int c, obj *a)
{
    (void)c;
    if (isfix(a[0]) && isfix(a[1]) && fixval(a[1]) >= 0) {
        int64_t r = 1, b = fixval(a[0]);
        for (int32_t e = fixval(a[1]); e > 0; e--) {
            r *= b;
            if (r > FIX_MAX || r < FIX_MIN)
                return mkfloat(pow((double)fixval(a[0]), (double)fixval(a[1])));
        }
        return mkint(r);
    }
    return result(pow(num_double(a[0]), num_double(a[1])));
}

static obj f_pi(int c, obj *a) { (void)c; (void)a; return mkfloat(M_PI); }

static uint32_t rand_state = 12345;

static obj f_random(int c, obj *a)
{
    (void)c;
    obj n = check_number(a[0]);
    rand_state = rand_state * 1103515245u + 12345u;
    uint32_t r = rand_state >> 1;
    if (isfix(n)) {
        if (fixval(n) <= 0)
            lisp_error("index out of range", n);
        return mkfix((int32_t)(r % (uint32_t)fixval(n)));
    }
    return mkfloat(floatval(n) * (r / 2147483648.0));
}

static obj logop(int c, obj *a, int op)
{
    int32_t r = op == 0 ? -1 : 0;
    for (int i = 0; i < c; i++) {
        int32_t x = check_int(a[i]);
        r = op == 0 ? (r & x) : op == 1 ? (r | x) : (r ^ x);
    }
    return mkfix(r);
}

static obj f_logand(int c, obj *a) { return logop(c, a, 0); }
static obj f_logior(int c, obj *a) { return logop(c, a, 1); }
static obj f_logxor(int c, obj *a) { return logop(c, a, 2); }
static obj f_lognot(int c, obj *a) { (void)c; return mkfix(~check_int(a[0])); }

static obj f_ash(int c, obj *a)
{
    (void)c;
    int64_t x = check_int(a[0]);
    int32_t s = check_int(a[1]);
    if (s >= 0)
        return s > 40 ? (x ? mkfloat(ldexp((double)x, s)) : mkfix(0)) : mkint(x << s);
    return mkfix((int32_t)(s < -40 ? (x < 0 ? -1 : 0) : (x >> -s)));
}

/* format_float: d the CPC's way, digits as few as read back exactly:
 * fixed from 0.001 up to below 10^7, else d.ddde+n */
void format_float(double d, char *buf)
{
    if (isinf(d) || isnan(d)) {
        strcpy(buf, d < 0 ? "-inf" : isnan(d) ? "nan" : "inf");
        return;
    }
    if (d == 0) {
        strcpy(buf, signbit(d) ? "-0.0" : "0.0");
        return;
    }
    char tmp[64];
    int p;
    for (p = 1; p <= 17; p++) {
        snprintf(tmp, sizeof tmp, "%.*e", p - 1, d);
        if (strtod(tmp, NULL) == d)
            break;
    }
    /* tmp: [-]d.ddde[+-]xx */
    char digits[32];
    int nd = 0, neg = 0, i = 0;
    if (tmp[0] == '-') { neg = 1; i = 1; }
    for (; tmp[i] && tmp[i] != 'e'; i++)
        if (tmp[i] != '.')
            digits[nd++] = tmp[i];
    while (nd > 1 && digits[nd - 1] == '0')
        nd--;
    digits[nd] = 0;
    int e = atoi(tmp + i + 1);          /* d = 0.digits x 10^(e+1) */
    char *o = buf;
    if (neg) *o++ = '-';
    double ad = fabs(d);
    if (ad >= 1e-3 && ad < 1e7) {
        if (e < 0) {
            *o++ = '0';
            *o++ = '.';
            for (int k = -1; k > e; k--)
                *o++ = '0';
            for (int k = 0; k < nd; k++)
                *o++ = digits[k];
        } else {
            for (int k = 0; k <= e; k++)
                *o++ = k < nd ? digits[k] : '0';
            *o++ = '.';
            if (nd > e + 1)
                for (int k = e + 1; k < nd; k++)
                    *o++ = digits[k];
            else
                *o++ = '0';
        }
        *o = 0;
    } else {
        *o++ = digits[0];
        *o++ = '.';
        if (nd > 1)
            for (int k = 1; k < nd; k++)
                *o++ = digits[k];
        else
            *o++ = '0';
        sprintf(o, "e%d", e);
    }
}

void init_num(void)
{
    defsubr("+", f_plus, 0, ANY);
    defsubr("-", f_minus, 1, ANY);
    defsubr("*", f_times, 0, ANY);
    defsubr("/", f_divide, 1, ANY);
    defsubr("1+", f_1plus, 1, 1);
    defsubr("1-", f_1minus, 1, 1);
    defsubr("TRUNCATE", f_truncate, 1, 2);
    defsubr("FLOOR", f_floor, 1, 2);
    defsubr("CEILING", f_ceiling, 1, 2);
    defsubr("ROUND", f_round, 1, 2);
    defsubr("MOD", f_mod, 2, 2);
    defsubr("REM", f_rem, 2, 2);
    defsubr("ABS", f_abs, 1, 1);
    defsubr("MAX", f_max, 1, ANY);
    defsubr("MIN", f_min, 1, ANY);
    defsubr("<", f_lt, 1, ANY);
    defsubr(">", f_gt, 1, ANY);
    defsubr("<=", f_le, 1, ANY);
    defsubr(">=", f_ge, 1, ANY);
    defsubr("=", f_numeq, 1, ANY);
    defsubr("/=", f_numne, 1, ANY);
    defsubr("ZEROP", f_zerop, 1, 1);
    defsubr("PLUSP", f_plusp, 1, 1);
    defsubr("MINUSP", f_minusp, 1, 1);
    defsubr("EVENP", f_evenp, 1, 1);
    defsubr("ODDP", f_oddp, 1, 1);
    defsubr("FLOAT", f_float, 1, 1);
    defsubr("FLOATP", f_floatp, 1, 1);
    defsubr("SQRT", f_sqrt, 1, 1);
    defsubr("EXP", f_exp, 1, 1);
    defsubr("SIN", f_sin, 1, 1);
    defsubr("COS", f_cos, 1, 1);
    defsubr("TAN", f_tan, 1, 1);
    defsubr("LOG", f_log, 1, 2);
    defsubr("ATAN", f_atan, 1, 2);
    defsubr("%POW", f_pow, 2, 2);
    defsubr("%PI", f_pi, 0, 0);
    defsubr("RANDOM", f_random, 1, 1);
    defsubr("LOGAND", f_logand, 0, ANY);
    defsubr("LOGIOR", f_logior, 0, ANY);
    defsubr("LOGXOR", f_logxor, 0, ANY);
    defsubr("LOGNOT", f_lognot, 1, 1);
    defsubr("ASH", f_ash, 2, 2);
}
