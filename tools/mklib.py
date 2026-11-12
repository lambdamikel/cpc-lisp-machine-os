#!/usr/bin/env python3
"""Make the library ROMs' symbol tables.

    tools/mklib.py OUTDIR lib/lib.asm lib/lib2.asm ...

Each argument is a part's main file; its table goes to OUTDIR/<name>tab.asm
(lib.asm -> libtab.asm), which the main file includes. The main file's
includes are followed (those found next to it). Native functions come from
';@ NAME MIN MAX label' lines (MAX 255: any number); ';@lisp file.lsp'
names Lisp text for the part. From that, each top-level (defun NAME ...) or
(defmacro NAME ...) becomes an autoload entry with its text, comments
stripped and blanks squeezed; every other top-level form is a boot form,
evaluated when the core starts.

The names are hashed into 64 buckets exactly as the core's intern does
(src/sym.asm, hash_name), because the core looks a new symbol up in the
bucket it would itself use. An entry is

    [next][kind][min][max][address][length][name]

kind 1 native (address = code), 2 autoload (address = text). A name the
core already has is an error: the core's would always win; so is a name
defined twice, in any of the parts, counting the variables boot forms
define.
"""
import os, re, sys

def hash_name(name):
    c = 0
    for ch in name.encode('latin-1'):
        c = ((c << 1) | (c >> 7)) & 0xFF
        c = (c + ch) & 0xFF
    return c & 63

def core_names():
    names = set()
    for line in open('src/symtab.asm'):
        m = re.match(r'\s+(SUBR|FSUBR|SYMBOL)\s+\w+,"([^"]*)"', line)
        if m:
            names.add(m.group(2))
    return names

def lisp_forms(text, path):
    """Top-level forms of a Lisp file, each squeezed to one line."""
    forms, i, n = [], 0, len(text)
    out, depth, start_line = [], 0, 0
    def emit(tok):
        if out and tok not in ')' and out[-1] not in '(\'`,@' and not (out[-1] == ' '):
            if not (tok == ')' or out[-1] == '(' ):
                out.append(' ')
        out.append(tok)
    line = 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
        if c in ' \t\r\n':
            i += 1
            if out and out[-1] not in '( ':
                out.append(' ')
            continue
        if c == ';':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if text.startswith('#|', i):
            j = text.index('|#', i)
            line += text.count('\n', i, j)
            i = j + 2
            continue
        if depth == 0 and not out:
            start_line = line
        if c == '"':
            j = i + 1
            while text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            tok = text[i:j + 1]
            i = j + 1
        elif text.startswith('#\\', i):
            j = i + 3
            while j < n and (text[j].isalnum() or text[j] in '-'):
                j += 1
            tok = text[i:j]
            i = j
        elif c in '()':
            tok = c
            i += 1
        elif c in "'`":
            tok = c
            i += 1
        elif c == ',':
            tok = ',@' if text.startswith(',@', i) else ','
            i += len(tok)
        elif text.startswith("#'", i):
            tok = "#'"
            i += 2
        else:
            j = i
            while j < n and text[j] not in ' \t\r\n()";\'`,':
                j += 1
            tok = text[i:j]
            i = j
        # squeeze: no blank after "(" or a quote, none before ")"
        if tok == ')' and out and out[-1] == ' ':
            out.pop()
        out.append(tok)
        if tok == '(':
            depth += 1
        elif tok == ')':
            depth -= 1
            if depth < 0:
                sys.exit(f'{path}:{line}: unbalanced )')
        if depth == 0 and tok not in ("'", '`', ',', ',@', "#'"):
            while out and out[-1] == ' ':
                out.pop()
            forms.append((''.join(out).strip(), path, start_line))
            out = []
    if depth:
        sys.exit(f'{path}: unbalanced at the end')
    return forms

def asm_bytes(label, data):
    lines = [f'{label}:']
    for k in range(0, len(data), 16):
        lines.append('    db ' + ','.join(str(b) for b in data[k:k + 16]))
    return lines

# the machine's own files (tools/build.sh: MACH), found when not beside
# the file that includes them
MACHDIR = os.path.join('mach', os.environ.get('MACH', 'cpc'))

def part_sources(main):
    """The .asm files of a part (main and what it includes, in order) and
    its Lisp files."""
    import os
    asms, lisps, seen = [], [], set()
    def walk(path):
        if path in seen:
            return
        seen.add(path)
        asms.append(path)
        for line in open(path):
            m = re.match(r'\s+include\s+"([^"]+)"', line)
            if m:
                for d in (os.path.dirname(path), MACHDIR):
                    inc = os.path.join(d, m.group(1))
                    if os.path.exists(inc):
                        walk(inc)
                        break
            m = re.match(r';@lisp\s+(\S+)\s*$', line)
            if m:
                lisps.append(os.path.join(os.path.dirname(path), m.group(1)))
    walk(main)
    return asms, lisps

def part_lines(main):
    """The lines of a part as the assembler reads them: an included file's
    in place of its include line."""
    out, seen = [], set()
    def walk(path):
        if path in seen:
            return
        seen.add(path)
        for line in open(path):
            m = re.match(r'\s+include\s+"([^"]+)"', line)
            if m:
                for d in (os.path.dirname(path), MACHDIR):
                    inc = os.path.join(d, m.group(1))
                    if os.path.exists(inc):
                        walk(inc)
                        break
            else:
                out.append(line)
    walk(main)
    return out

def part_table(main):
    """-> (natives, autoloads, boots, variables) of one part"""
    natives, autoloads, boots, variables = [], [], [], []
    asms, lisps = part_sources(main)
    for line in part_lines(main):
        m = re.match(r';@\s+(\S+)\s+(\d+)\s+(\d+)\s+(\w+)\s*$', line)
        if m:
            natives.append((m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)))
    for path in lisps:
        for form, p, line in lisp_forms(open(path, encoding='latin-1').read(), path):
            m = re.match(r'\((defun|defmacro)\s+([^\s()]+)', form, re.I)
            if m:
                autoloads.append((m.group(2).upper(), form, p, line))
            else:
                boots.append((form, p, line))
                v = re.match(r'\((defvar|defparameter|defconstant)\s+([^\s()]+)', form, re.I)
                if v:
                    variables.append(v.group(2).upper())
    return natives, autoloads, boots, variables

def vm_table(vm):
    """The VM ROM's functions: ';@vm NAME MIN MAX label' lines in its sources,
    then the defuns of its ';@vmlisp file.lsp' files (min 254: Lisp text,
    read the first time it is called), numbered in order. Their other
    top-level forms are boot forms of the part that names them.
    -> ([(name, min, max, label)], [texts], [boot forms], [variables])"""
    import os
    fns, texts, boots, variables = [], [], [], []
    srcs = part_sources(vm)[0]
    code = os.path.join('build', 'vmcode.asm')
    for path in srcs + ([code] if os.path.exists(code) else []):
        for line in open(path):
            m = re.match(r';@vm\s+(\S+)\s+(\d+)\s+(\d+)\s+(\w+)\s*$', line)
            if m:
                fns.append((m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)))
            m = re.match(r';@vmcode\s+(\S+)\s+(\S+)\s*$', line)
            if m:
                fns.append((m.group(1), 255, 0, m.group(2)))
            m = re.match(r';@vmlisp\s+(\S+)\s*$', line)
            if m:
                lsp = os.path.join(os.path.dirname(path), m.group(1))
                for form, p, ln in lisp_forms(open(lsp, encoding='latin-1').read(), lsp):
                    d = re.match(r'\(defun\s+([^\s()]+)', form, re.I)
                    if d:
                        fns.append((d.group(1).upper(), 254, 0, f'vt_{len(texts)}'))
                        texts.append(form)
                    elif re.match(r'\(defmacro\s', form, re.I):
                        sys.exit(f'{p}:{ln}: no macros in the VM ROM')
                    else:
                        boots.append((form, p, ln))
                        v = re.match(r'\((defvar|defparameter|defconstant)\s+([^\s()]+)', form, re.I)
                        if v:
                            variables.append(v.group(2).upper())
    return fns, texts, boots, variables

def write_vmtab(fns, texts):
    out = ['; made by tools/mklib.py -- do not edit', '',
           f'VM_NFNS equ {len(fns)}', 'vm_fntab:']
    for k, (name, mn, mx, label) in enumerate(fns):
        out.append(f'    db {mn},{mx}')
        out.append(f'    dw {label}                ; {k} {name}')
    nbytes = 0
    for k, form in enumerate(texts):
        data = form.encode('latin-1') + b'\0'
        nbytes += len(data)
        out += asm_bytes(f'vt_{k}', data)
    return '\n'.join(out) + '\n', nbytes

def write_table(natives, autoloads, boots, vmfns=()):
    entries = []
    for name, mn, mx, label in natives:
        entries.append((name, 1, mn, mx, label))
    for k, (name, mn, mx, label) in enumerate(vmfns):
        if name != '-':
            entries.append((name, 3, 0, 0, str(2 * k + 1)))
    for k, (name, form, p, line) in enumerate(autoloads):
        entries.append((name, 2, 0, 0, f'lt_{k}'))
    buckets = [[] for _ in range(64)]
    for k, e in enumerate(entries):
        buckets[hash_name(e[0])].append(k)
    out = ['; made by tools/mklib.py -- do not edit', '']
    out.append('lib_buckets:')
    for b in buckets:
        out.append(f'    dw {"le_%d" % b[0] if b else 0}')
    out.append('lib_boot:')
    for k in range(len(boots)):
        out.append(f'    dw lb_{k}')
    out.append('    dw 0')
    for b in buckets:
        for pos, k in enumerate(b):
            name, kind, mn, mx, addr = entries[k]
            nxt = f'le_{b[pos + 1]}' if pos + 1 < len(b) else '0'
            out.append(f'le_{k}:')
            out.append(f'    dw {nxt}')
            out.append(f'    db {kind},{mn},{mx}')
            out.append(f'    dw {addr}')
            out.append(f'    db {len(name)}')
            out += ['    db ' + ','.join(str(c) for c in name.encode('latin-1'))]
    textbytes = 0
    for k, (name, form, p, line) in enumerate(autoloads):
        data = form.encode('latin-1') + b'\0'
        textbytes += len(data)
        out += asm_bytes(f'lt_{k}', data)
    for k, (form, p, line) in enumerate(boots):
        data = form.encode('latin-1') + b'\0'
        textbytes += len(data)
        out += asm_bytes(f'lb_{k}', data)
    return '\n'.join(out) + '\n', textbytes

def main():
    import os
    outdir, mains = sys.argv[1], sys.argv[2:]
    vm = vmpart = None
    if '--vm' in mains:
        k = mains.index('--vm')
        vm, vmpart = mains[k + 1], mains[k + 2]
        mains = mains[:k] + mains[k + 3:]
    vmfns, vmtexts, vmboots, vmvars = vm_table(vm) if vm else ([], [], [], [])
    core = core_names()
    seen = {}
    for name in [f[0] for f in vmfns if f[0] != '-'] + vmvars:
        if name in core or name in seen:
            sys.exit(f'mklib: {name} (the VM ROM\'s) is defined twice')
        seen[name] = vm
    parts = []
    for main in mains:
        natives, autoloads, boots, variables = part_table(main)
        for name in [n[0] for n in natives] + [a[0] for a in autoloads] + variables:
            if name in core:
                sys.exit(f'mklib: {name} is a core builtin already')
            if name in seen:
                sys.exit(f'mklib: {name} is defined twice ({seen[name]}, {main})')
            if len(name) > 255:
                sys.exit(f'mklib: {name} is too long')
            seen[name] = main
        if main == vmpart:
            boots = boots + vmboots
        parts.append((main, natives, autoloads, boots))
    if vm:
        text, nbytes = write_vmtab(vmfns, vmtexts)
        with open(os.path.join(outdir, 'vmtab.asm'), 'w') as f:
            f.write(text)
        print(f'mklib: vm: {len(vmfns)} functions ({len(vmtexts)} in Lisp, {nbytes} '
              f'bytes of text), named in {vmpart}', file=sys.stderr)
    for main, natives, autoloads, boots in parts:
        text, textbytes = write_table(natives, autoloads, boots,
                                      vmfns if main == vmpart else ())
        base = os.path.splitext(os.path.basename(main))[0]
        with open(os.path.join(outdir, base + 'tab.asm'), 'w') as f:
            f.write(text)
        print(f'mklib: {base}: {len(natives)} native, {len(autoloads)} in Lisp '
              f'({textbytes} bytes of text), {len(boots)} boot forms', file=sys.stderr)

main()
