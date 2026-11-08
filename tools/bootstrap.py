#!/usr/bin/env python3
"""Compile the compiler with itself, for the VM ROM.

    tools/bootstrap.py lib/compiler.lsp lib/vm.asm build/vmcode.asm

lib/compiler.lsp is too big to run interpreted on a CPC (5500 cells), so it
is run here instead -- by a small interpreter of the Lisp it is written in
(a subset of CPC Lisp) -- on its own defuns, and what it makes goes into
the VM ROM as bytecode (build/vmcode.asm): the compiler, compiled, runs from
there and costs no heap.

Each compiled function (an inner lambda too) becomes one of the VM ROM's
functions, numbered after its natives (the ';@vm' lines of lib/vm.asm),
its bytecode at vb_K+2 (the length before it). They share one pool of
constants, read the first time one of them runs (vm_pool):

    vm_pooldata:  dw its text; db how many references, then for each the
                  constant's index and the function it is
    vm_pooltext:  (constant...) as text

A constant that names one of these functions -- or a native -- becomes a
reference to it: the compiler's own functions need no symbols on the CPC.
Each has a ';@vmcode NAME vb_K+2' line, which tools/mklib.py makes an
entry of the VM's table and, for the few meant to be called by name, a
name in part 1 (the rest have '-').
"""
import re, sys

# ---------------------------------------------------------------- data

class Sym:
    __slots__ = ('name', 'value', 'fn', 'plist', 'special')
    def __init__(self, name):
        self.name, self.value, self.fn, self.plist, self.special = name, UNBOUND, None, None, False
    def __repr__(self):
        return self.name

class Cons:
    __slots__ = ('car', 'cdr')
    def __init__(self, a, d):
        self.car, self.cdr = a, d

class Char:
    __slots__ = ('code',)
    def __init__(self, c):
        self.code = c
    def __eq__(self, o):
        return isinstance(o, Char) and o.code == self.code
    def __hash__(self):
        return self.code

class Code:
    """what %make-code makes"""
    def __init__(self, data, consts, name):
        self.bytes, self.consts, self.name = data, consts, name

class Lambda:
    def __init__(self, name, ll, body, env):
        self.name, self.ll, self.body, self.env = name, ll, body, env

UNBOUND = object()
SYMS = {}
def intern(name):
    s = SYMS.get(name)
    if s is None:
        s = SYMS[name] = Sym(name)
    return s

NIL = intern('NIL'); T = intern('T')
NIL.value = NIL; T.value = T

def lst(*xs, tail=None):
    r = NIL if tail is None else tail
    for x in reversed(xs):
        r = Cons(x, r)
    return r

def pylist(x):
    out = []
    while isinstance(x, Cons):
        out.append(x.car)
        x = x.cdr
    return out

def truth(x):
    return x is not NIL

def boolean(b):
    return T if b else NIL

# ---------------------------------------------------------------- reader

CHARNAMES = {'SPACE': 32, 'NEWLINE': 10, 'TAB': 9, 'RETURN': 13}

class Reader:
    def __init__(self, text):
        self.t, self.i = text, 0

    def skip(self):
        t = self.t
        while self.i < len(t):
            c = t[self.i]
            if c in ' \t\r\n':
                self.i += 1
            elif c == ';':
                while self.i < len(t) and t[self.i] != '\n':
                    self.i += 1
            elif t.startswith('#|', self.i):
                self.i = t.index('|#', self.i) + 2
            else:
                return

    def read(self):
        self.skip()
        t = self.t
        if self.i >= len(t):
            raise EOFError
        c = t[self.i]
        if c == '(':
            self.i += 1
            items, tail = [], NIL
            while True:
                self.skip()
                if t[self.i] == ')':
                    self.i += 1
                    return lst(*items, tail=tail)
                if t[self.i] == '.' and t[self.i + 1] in ' \t\r\n':
                    self.i += 1
                    tail = self.read()
                    continue
                items.append(self.read())
        if c == ')':
            raise SyntaxError('unexpected )')
        if c == "'":
            self.i += 1
            return lst(intern('QUOTE'), self.read())
        if c == '`':
            self.i += 1
            return lst(intern('QUASIQUOTE'), self.read())
        if c == ',':
            self.i += 1
            if t[self.i] == '@':
                self.i += 1
                return lst(intern('UNQUOTE-SPLICING'), self.read())
            return lst(intern('UNQUOTE'), self.read())
        if t.startswith("#'", self.i):
            self.i += 2
            return lst(intern('FUNCTION'), self.read())
        if t.startswith('#\\', self.i):
            j = self.i + 3
            while j < len(t) and (t[j].isalnum() or t[j] == '-'):
                j += 1
            name = t[self.i + 2:j]
            self.i = j
            if len(name) == 1:
                return Char(ord(name))
            return Char(CHARNAMES[name.upper()])
        if c == '"':
            j, out = self.i + 1, []
            while t[j] != '"':
                if t[j] == '\\':
                    j += 1
                out.append(t[j])
                j += 1
            self.i = j + 1
            return ''.join(out)
        j = self.i
        while j < len(t) and t[j] not in ' \t\r\n()";\'`,':
            j += 1
        tok = t[self.i:j]
        self.i = j
        if re.fullmatch(r'[+-]?\d+', tok):
            return int(tok)
        return intern(tok.upper())

def read_all(text):
    r, out = Reader(text), []
    while True:
        try:
            out.append(r.read())
        except EOFError:
            return out

# ---------------------------------------------------------------- evaluator

class BlockExit(Exception):
    def __init__(self, tag, value):
        self.tag, self.value = tag, value

class Thrown(Exception):
    def __init__(self, tag, value):
        self.tag, self.value = tag, value

class LispError(Exception):
    pass

class Env:
    __slots__ = ('vars', 'fns', 'blocks', 'up')
    def __init__(self, up=None):
        self.vars, self.fns, self.blocks, self.up = {}, {}, {}, up

def lookup_var(sym, env):
    if sym.special:
        return sym.value
    e = env
    while e:
        if sym in e.vars:
            return e.vars[sym]
        e = e.up
    if sym.value is UNBOUND:
        raise LispError(f'unbound variable {sym.name}')
    return sym.value

def set_var(sym, val, env):
    if not sym.special:
        e = env
        while e:
            if sym in e.vars:
                e.vars[sym] = val
                return val
            e = e.up
    sym.value = val
    return val

def lookup_fn(sym, env):
    e = env
    while e:
        if sym in e.fns:
            return e.fns[sym]
        e = e.up
    if sym.fn is None:
        raise LispError(f'undefined function {sym.name}')
    return sym.fn

def S(name):
    return intern(name)

SPECIAL = {}
def special(name):
    def deco(f):
        SPECIAL[intern(name)] = f
        return f
    return deco

def ev(x, env):
    if isinstance(x, Sym):
        if x is NIL or x is T or x.name.startswith(':'):
            return x
        return lookup_var(x, env)
    if not isinstance(x, Cons):
        return x
    op = x.car
    if isinstance(op, Sym):
        h = SPECIAL.get(op)
        if h:
            return h(x.cdr, env)
        f = lookup_fn(op, env)
    elif isinstance(op, Cons) and op.car is S('LAMBDA'):
        f = Lambda(None, op.cdr.car, op.cdr.cdr, env)
    else:
        raise LispError(f'bad call {x}')
    args = [ev(a, env) for a in pylist(x.cdr)]
    return call(f, args)

def call(f, args):
    if isinstance(f, Sym):
        f = lookup_fn(f, None)
    if callable(f):
        return f(*args)
    if isinstance(f, Lambda):
        env = Env(f.env)
        saved = bind_params(f.ll, args, env)
        try:
            return progn(f.body, env)
        finally:
            for s, v in saved:
                s.value = v
    raise LispError(f'not a function {f}')

def bind1(sym, val, env, saved):
    if sym.special:
        saved.append((sym, sym.value))
        sym.value = val
    else:
        env.vars[sym] = val

def bind_params(ll, args, env):
    saved, mode, i = [], 'req', 0
    for p in pylist(ll):
        if p is S('&OPTIONAL'):
            mode = 'opt'; continue
        if p is S('&REST') or p is S('&BODY'):
            mode = 'rest'; continue
        if p is S('&KEY'):
            mode = 'key'; continue
        if mode == 'req':
            if i >= len(args):
                raise LispError('too few arguments')
            bind1(p, args[i], env, saved); i += 1
        elif mode == 'opt':
            var, init = (p.car, p.cdr.car if p.cdr is not NIL else NIL) if isinstance(p, Cons) else (p, NIL)
            if i < len(args):
                bind1(var, args[i], env, saved); i += 1
            else:
                bind1(var, ev(init, env), env, saved)
        elif mode == 'rest':
            bind1(p, lst(*args[i:]), env, saved); i = len(args)
        else:
            raise LispError('&key in the bootstrap')
    if i < len(args) and mode != 'rest':
        raise LispError('too many arguments')
    return saved

def progn(body, env):
    r = NIL
    while isinstance(body, Cons):
        r = ev(body.car, env)
        body = body.cdr
    return r

@special('QUOTE')
def _(a, env): return a.car

@special('FUNCTION')
def _(a, env):
    f = a.car
    if isinstance(f, Sym):
        return lookup_fn(f, env)
    return Lambda(None, f.cdr.car, f.cdr.cdr, env)

@special('LAMBDA')
def _(a, env): return Lambda(None, a.car, a.cdr, env)

@special('IF')
def _(a, env):
    if truth(ev(a.car, env)):
        return ev(a.cdr.car, env)
    return progn(a.cdr.cdr, env)

@special('WHEN')
def _(a, env): return progn(a.cdr, env) if truth(ev(a.car, env)) else NIL

@special('UNLESS')
def _(a, env): return NIL if truth(ev(a.car, env)) else progn(a.cdr, env)

@special('COND')
def _(a, env):
    for c in pylist(a):
        v = ev(c.car, env)
        if truth(v):
            return progn(c.cdr, env) if c.cdr is not NIL else v
    return NIL

@special('CASE')
def _(a, env):
    k = ev(a.car, env)
    for c in pylist(a.cdr):
        keys = c.car
        if keys is T or keys is S('OTHERWISE') or \
           (k in pylist(keys) if isinstance(keys, Cons) else eql(k, keys)):
            return progn(c.cdr, env)
    return NIL

@special('AND')
def _(a, env):
    v = T
    for f in pylist(a):
        v = ev(f, env)
        if v is NIL:
            return NIL
    return v

@special('OR')
def _(a, env):
    for f in pylist(a):
        v = ev(f, env)
        if v is not NIL:
            return v
    return NIL

@special('PROGN')
def _(a, env): return progn(a, env)

@special('PROG1')
def _(a, env):
    v = ev(a.car, env)
    progn(a.cdr, env)
    return v

@special('SETQ')
def _(a, env):
    v = NIL
    while a is not NIL:
        v = set_var(a.car, ev(a.cdr.car, env), env)
        a = a.cdr.cdr
    return v

def setf_place(place, v, env):
    if isinstance(place, Sym):
        return set_var(place, v, env)
    acc = place.car
    if acc is S('CAR'):
        ev(place.cdr.car, env).car = v
    elif acc is S('CDR'):
        ev(place.cdr.car, env).cdr = v
    elif acc is S('SYMBOL-FUNCTION'):
        ev(place.cdr.car, env).fn = v
    else:
        raise LispError(f'setf {place}')
    return v

@special('SETF')
def _(a, env):
    v = NIL
    while a is not NIL:
        v = setf_place(a.car, ev(a.cdr.car, env), env)
        a = a.cdr.cdr
    return v

@special('INCF')
def _(a, env):
    d = ev(a.cdr.car, env) if a.cdr is not NIL else 1
    return set_var(a.car, lookup_var(a.car, env) + d, env)

@special('DECF')
def _(a, env):
    d = ev(a.cdr.car, env) if a.cdr is not NIL else 1
    return set_var(a.car, lookup_var(a.car, env) - d, env)

@special('PUSH')
def _(a, env):
    v = ev(a.car, env)
    return set_var(a.cdr.car, Cons(v, lookup_var(a.cdr.car, env)), env)

@special('POP')
def _(a, env):
    l = lookup_var(a.car, env)
    set_var(a.car, l.cdr, env)
    return l.car

def let_common(a, env, star):
    new, saved = Env(env), []
    for b in pylist(a.car):
        name, init = (b.car, b.cdr.car if b.cdr is not NIL else NIL) if isinstance(b, Cons) else (b, NIL)
        bind1(name, ev(init, new if star else env), new, saved)
    try:
        return progn(a.cdr, new)
    finally:
        for s, v in reversed(saved):
            s.value = v

@special('LET')
def _(a, env): return let_common(a, env, False)

@special('LET*')
def _(a, env): return let_common(a, env, True)

def block(name, thunk):
    tag = object()
    try:
        return thunk(tag)
    except BlockExit as e:
        if e.tag is tag:
            return e.value
        raise

def find_block(name, env):
    e = env
    while e:
        if name in e.blocks:
            return e.blocks[name]
        e = e.up
    raise LispError(f'no block {name}')

@special('BLOCK')
def _(a, env):
    def run(tag):
        e = Env(env); e.blocks[a.car] = tag
        return progn(a.cdr, e)
    return block(a.car, run)

@special('RETURN-FROM')
def _(a, env):
    raise BlockExit(find_block(a.car, env), ev(a.cdr.car, env) if a.cdr is not NIL else NIL)

@special('RETURN')
def _(a, env):
    raise BlockExit(find_block(NIL, env), ev(a.car, env) if a is not NIL else NIL)

@special('%LOOP')
def _(a, env):
    def run(tag):
        e = Env(env); e.blocks[NIL] = tag
        while True:
            progn(a, e)
    return block(NIL, run)

@special('DOLIST')
def _(a, env):
    spec = a.car
    def run(tag):
        e = Env(env); e.blocks[NIL] = tag
        for x in pylist(ev(spec.cdr.car, env)):
            e.vars[spec.car] = x
            progn(a.cdr, e)
        e.vars[spec.car] = NIL
        return ev(spec.cdr.cdr.car, e) if spec.cdr.cdr is not NIL else NIL
    return block(NIL, run)

@special('DOTIMES')
def _(a, env):
    spec = a.car
    def run(tag):
        e = Env(env); e.blocks[NIL] = tag
        n = ev(spec.cdr.car, env)
        for i in range(n):
            e.vars[spec.car] = i
            progn(a.cdr, e)
        e.vars[spec.car] = n
        return ev(spec.cdr.cdr.car, e) if spec.cdr.cdr is not NIL else NIL
    return block(NIL, run)

@special('CATCH')
def _(a, env):
    tag = ev(a.car, env)
    try:
        return progn(a.cdr, env)
    except Thrown as t:
        if t.tag is tag:
            return t.value
        raise

@special('THROW')
def _(a, env): raise Thrown(ev(a.car, env), ev(a.cdr.car, env))

@special('DEFUN')
def _(a, env):
    a.car.fn = Lambda(a.car, a.cdr.car, a.cdr.cdr, None)
    return a.car

@special('DEFVAR')
def _(a, env):
    s = a.car
    s.special = True
    if s.value is UNBOUND and a.cdr is not NIL:
        s.value = ev(a.cdr.car, env)
    return s

@special('DECLARE')
def _(a, env): return NIL

# ---------------------------------------------------------------- builtins

def eql(a, b):
    if isinstance(a, int) and isinstance(b, int):
        return a == b and not isinstance(a, bool)
    if isinstance(a, Char) and isinstance(b, Char):
        return a.code == b.code
    return a is b

def defn(name):
    def deco(f):
        intern(name).fn = f
        return f
    return deco

def car(x): return NIL if x is NIL else x.car
def cdr(x): return NIL if x is NIL else x.cdr
def nth(n, l):
    for _ in range(n):
        l = cdr(l)
    return car(l)

def nthcdr(n, l):
    for _ in range(n):
        l = cdr(l)
    return l

def keyargs(rest):
    return {rest[i].name: rest[i + 1] for i in range(0, len(rest), 2)}

def test_of(kw):
    t = kw.get(':TEST')
    return (lambda a, b: truth(call(t, [a, b]))) if t else eql

def position(x, seq, *rest):
    kw = keyargs(list(rest))
    start = kw.get(':START', 0)
    items = list(seq) if isinstance(seq, str) else pylist(seq)
    for i in range(start, len(items)):
        y = items[i]
        if isinstance(seq, str):
            y = Char(ord(y))
        if eql(x, y):
            return i
    return NIL

def find(x, seq, *rest):
    kw = keyargs(list(rest))
    key = kw.get(':KEY')
    for y in pylist(seq):
        if eql(x, call(key, [y]) if key else y):
            return y
    return NIL

def member(x, l, *rest):
    t = test_of(keyargs(list(rest)))
    while l is not NIL:
        if t(x, l.car):
            return l
        l = l.cdr
    return NIL

def assoc(x, l, *rest):
    t = test_of(keyargs(list(rest)))
    for e in pylist(l):
        if e is not NIL and t(x, e.car):
            return e
    return NIL

def append(*ls):
    if not ls:
        return NIL
    r = ls[-1]
    for l in reversed(ls[:-1]):
        r = lst(*pylist(l), tail=r)
    return r

def lsubseq(seq, start, end=None):
    if isinstance(seq, str):
        return seq[start:end if end is not None and end is not NIL else None]
    items = pylist(seq)
    return lst(*items[start:end if end is not None and end is not NIL else None])

def concatenate(typ, *seqs):
    return ''.join(seqs)

def every(f, l):
    return boolean(all(truth(call(f, [x])) for x in pylist(l)))

def mapcar(f, l):
    return lst(*[call(f, [x]) for x in pylist(l)])

def nreverse(l):
    return lst(*reversed(pylist(l)))

def lerror(msg, *objs):
    raise LispError(f'{msg} {objs}')

MACROS = set()  # CPC Lisp's library macros: the bootstrap cannot expand them

def fn_info(x):
    if isinstance(x, Sym):
        if x.name in MACROS:
            return 1
        f = x.fn
        if f is None:
            return 0
        return 2 if isinstance(f, Lambda) else 4
    return 0

def symbol_flags(s):
    if s is NIL or s is T or s.name.startswith(':'):
        return 2
    return 1 if s.special else 0

BUILTINS = {
    'CAR': car, 'CDR': cdr, 'FIRST': car, 'REST': cdr,
    'CAAR': lambda x: car(car(x)), 'CADR': lambda x: car(cdr(x)), 'CDAR': lambda x: cdr(car(x)),
    'CDDR': lambda x: cdr(cdr(x)), 'CADDR': lambda x: car(cdr(cdr(x))),
    'CDDDR': lambda x: cdr(cdr(cdr(x))), 'SECOND': lambda x: car(cdr(x)),
    'CONS': Cons, 'LIST': lambda *a: lst(*a), 'LIST*': lambda *a: lst(*a[:-1], tail=a[-1]),
    'LENGTH': lambda l: len(l) if isinstance(l, str) else len(pylist(l)),
    'NTH': nth, 'NTHCDR': lambda n, l: nthcdr(n, l),
    'APPEND': append, 'REVERSE': lambda l: lst(*reversed(pylist(l))), 'NREVERSE': nreverse,
    'RPLACA': lambda c, v: (setattr(c, 'car', v), c)[1],
    'RPLACD': lambda c, v: (setattr(c, 'cdr', v), c)[1],
    'MEMBER': member, 'ASSOC': assoc, 'POSITION': position, 'FIND': find,
    'EVERY': every, 'MAPCAR': mapcar, 'SUBSEQ': lsubseq, 'CONCATENATE': concatenate,
    'FUNCALL': lambda f, *a: call(f, list(a)), 'APPLY': lambda f, *a: call(f, list(a[:-1]) + pylist(a[-1])),
    'EQ': lambda a, b: boolean(eql(a, b)),
    'EQL': lambda a, b: boolean(eql(a, b)),
    'NULL': lambda x: boolean(x is NIL), 'NOT': lambda x: boolean(x is NIL),
    'CONSP': lambda x: boolean(isinstance(x, Cons)), 'ATOM': lambda x: boolean(not isinstance(x, Cons)),
    'LISTP': lambda x: boolean(x is NIL or isinstance(x, Cons)),
    'SYMBOLP': lambda x: boolean(isinstance(x, Sym)),
    'NUMBERP': lambda x: boolean(isinstance(x, int)), 'INTEGERP': lambda x: boolean(isinstance(x, int)),
    'CHARACTERP': lambda x: boolean(isinstance(x, Char)),
    'KEYWORDP': lambda x: boolean(isinstance(x, Sym) and x.name.startswith(':')),
    '+': lambda *a: sum(a), '-': lambda a, *b: a - sum(b) if b else -a,
    '*': lambda *a: __import__('math').prod(a),
    '1+': lambda a: a + 1, '1-': lambda a: a - 1,
    '=': lambda a, *b: boolean(all(a == x for x in b)),
    '<': lambda *a: boolean(all(x < y for x, y in zip(a, a[1:]))),
    '>': lambda *a: boolean(all(x > y for x, y in zip(a, a[1:]))),
    '<=': lambda *a: boolean(all(x <= y for x, y in zip(a, a[1:]))),
    '>=': lambda *a: boolean(all(x >= y for x, y in zip(a, a[1:]))),
    'ZEROP': lambda a: boolean(a == 0), 'FLOOR': lambda a, b=1: a // b,
    'MOD': lambda a, b: a % b, 'ODDP': lambda a: boolean(a % 2 == 1),
    'FORMAT': lambda dest, f, *a: f.replace('~A', '{}').format(*[x.name if isinstance(x, Sym) else x for x in a]),
    'LOGAND': lambda *a: __import__('functools').reduce(lambda x, y: x & y, a, -1),
    'LOGIOR': lambda *a: __import__('functools').reduce(lambda x, y: x | y, a, 0),
    'ASH': lambda a, n: a << n if n >= 0 else a >> -n,
    'SYMBOL-NAME': lambda s: s.name, 'SYMBOL-FUNCTION': lambda s: lookup_fn(s, None),
    'INTERN': lambda name: intern(name),
    'GET': lambda s, p, d=NIL: d,
    'CHAR': lambda s, i: Char(ord(s[i])), 'CHAR-CODE': lambda c: c.code,
    'ERROR': lerror,
    'MACROEXPAND-1': lambda x: lerror('a macro in the bootstrap', x),
    '%MAKE-CODE': lambda b, c, n: Code(pylist(b), pylist(c), n),
    '%FN-INFO': fn_info, '%SYMBOL-FLAGS': symbol_flags,
    '%FN-DATA': lambda f: NIL,
}
for k, f in BUILTINS.items():
    intern(k).fn = f

# ---------------------------------------------------------------- output

def text(x):
    """x as CPC Lisp would read it back"""
    if isinstance(x, Sym):
        n = x.name
        if re.fullmatch(r'[A-Z0-9*%+<>=/&:!?$^_.~-]+', n) and not re.fullmatch(r'[+-]?\d+|\.', n):
            return n
        return '|' + n.replace('\\', '\\\\').replace('|', '\\|') + '|'
    if isinstance(x, bool):
        raise ValueError(x)
    if isinstance(x, int):
        return str(x)
    if isinstance(x, str):
        return '"' + x.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(x, Char):
        names = {v: k.capitalize() for k, v in CHARNAMES.items()}
        return '#\\' + (names[x.code] if x.code in names else chr(x.code))
    if isinstance(x, Cons):
        parts = []
        while isinstance(x, Cons):
            parts.append(text(x.car))
            x = x.cdr
        if x is not NIL:
            parts += ['.', text(x)]
        return '(' + ' '.join(parts) + ')'
    raise ValueError(f'cannot write {x!r} as text')

def asm_bytes(label, data):
    out = [f'{label}:']
    for k in range(0, len(data), 16):
        out.append('    db ' + ','.join(str(b) for b in data[k:k + 16]))
    return out

# operation k: its length (ARGS: 4, 6 with keys) and which byte is a
# constant's index, from lib/compiler.lsp's "kinds" in disassemble
KINDS = "0100222224441100000000000433333440456100000000000000000000000140072020288888" "9999" "00001"
LENGTH = {'0': 1, '1': 2, '2': 2, '4': 2, '3': 3, '6': 3, '7': 4, '8': 2, '9': 3}

def main():
    src, vmasm, out = sys.argv[1:4]
    natives = []
    for line in open(vmasm):
        m = re.match(r';@vm\s+(\S+)\s', line)
        if m:
            natives.append(m.group(1))
    for path in ('lib/lisp.lsp', 'lib/lisp2.lsp', 'lib/loop.lsp'):
        for m in re.finditer(r'^\(defmacro\s+(\S+)', open(path).read(), re.M | re.I):
            MACROS.add(m.group(1).upper())
    forms = read_all(open(src, encoding='latin-1').read())
    defuns = []
    for f in forms:
        ev(f, None)
        if isinstance(f, Cons) and f.car is S('DEFUN'):
            defuns.append(f)
    # compile each defun with the compiler, run here
    cc_top = intern('CC-TOP')
    compiled = {}
    for f in defuns:
        name = f.cdr.car
        compiled[name] = call(cc_top, [name, f.cdr.cdr.car, f.cdr.cdr.cdr])
    # number them all (inner functions too), after the natives
    order, num = [], {}
    def visit(c):
        if id(c) in num:
            return
        num[id(c)] = len(natives) + len(order)
        order.append(c)
        for k in c.consts:
            if isinstance(k, Code):
                visit(k)
    for name in compiled:
        visit(compiled[name])
    byname = {name.name: num[id(c)] for name, c in compiled.items()}
    for k, n in enumerate(natives):
        byname[n] = k
    # one pool of constants for them all: a function's own indices are
    # rewritten to the pool's
    pool, where = [], {}
    def ident(x):
        return ('code', id(x)) if isinstance(x, Code) else ('fn', x.name) \
            if isinstance(x, Sym) and x.name in byname else text(x)
    def pooled(x, fresh=False):
        key = ident(x)
        if fresh or key not in where:
            where.setdefault(key, len(pool))
            pool.append(x)
            return len(pool) - 1
        return where[key]
    def fnum(x):
        if isinstance(x, Code):
            return num[id(x)]
        if isinstance(x, Sym) and x.name in byname:
            return byname[x.name]
        return None
    for c in order:
        b, i = c.bytes, 0
        while i < len(b):
            op = b[i] // 3
            kind = KINDS[op]
            if op in (76, 77) and fnum(c.consts[b[i + 1]]) is not None:
                b[i] = 3 * (op + 2)             # CALLG -> CALLR: the number
                b[i + 1] = fnum(c.consts[b[i + 1]])
                i += 3
                continue
            if kind == '5':
                n = 6 if b[i + 3] & 2 else 4
                if n == 6:
                    keys = c.consts[b[i + 4]:b[i + 4] + b[i + 5]]
                    b[i + 4] = pooled(keys[0], True)
                    for x in keys[1:]:
                        pooled(x, True)
            else:
                n = LENGTH[kind]
                if kind in '169':
                    b[i + 1] = pooled(c.consts[b[i + 1]])
            i += n
    if len(pool) > 256:
        sys.exit(f'bootstrap: {len(pool)} constants: more than 256')
    refs, consts = [], []
    for i, x in enumerate(pool):
        if isinstance(x, Code):
            refs.append((i, num[id(x)])); consts.append(NIL)
        elif isinstance(x, Sym) and x.name in byname:
            refs.append((i, byname[x.name])); consts.append(NIL)
        else:
            consts.append(x)
    exported = {'COMPILE', 'DISASSEMBLE', 'COMPILE-FILE'}
    lines = ['; made by tools/bootstrap.py from lib/compiler.lsp -- do not edit', '',
             'vm_pooldata:', f'    dw vm_pooltext',
             f'    db {len(refs)}']
    for k in range(0, len(refs), 8):
        lines.append('    db ' + ','.join(f'{i},{j}' for i, j in refs[k:k + 8]))
    t = text(lst(*consts)).encode('latin-1')
    lines += asm_bytes('vm_pooltext', list(t) + [0])
    total = 0
    for c in order:
        k = num[id(c)]
        name = c.name if isinstance(c.name, Sym) else NIL
        label = f'vb_{k}'
        lines.append(f';@vmcode {name.name if name.name in exported else "-"} {label}+2')
        lines.append(f'; {k}: {name.name}')
        total += len(c.bytes)
        lines += asm_bytes(label, [len(c.bytes) & 255, len(c.bytes) >> 8] + c.bytes)
    with open(out, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'bootstrap: {len(order)} functions, {total} bytes of code, {len(pool)} constants '
          f'({len(t)} bytes of text)', file=sys.stderr)

if __name__ == '__main__':
    sys.setrecursionlimit(20000)
    main()
