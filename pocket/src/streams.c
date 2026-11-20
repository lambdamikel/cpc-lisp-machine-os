/* Pocket Lisp -- streams, the pretty printer, files (CPC Lisp's
 * lib/streams.asm, lib/pp.asm, lib/disc.asm).
 *
 * A stream is NIL or T (the screen and keyboard, or *standard-output*),
 * #S(STRING-OUTPUT-STREAM chunks), #S(STRING-INPUT-STREAM string index) or
 * #S(FILE-STREAM name direction open-p): the one file open for input or
 * the one open for output, as on the CPC. */
#include "lisp.h"
#include "read.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/statvfs.h>

extern int loading_library;
void sink_set_tag(sink *s, obj t);
obj sink_tag(sink *s);
int syms_flags_userdef(obj s);
void put_to_screen(sink *s, int c);
obj get_prop(obj s, obj ind, obj dflt);

void init_far(void);
static obj S_STRING_OUTPUT_STREAM, S_STRING_INPUT_STREAM, S_FILE_STREAM,
    S_KW_INPUT, S_KW_OUTPUT, S_DEFUN, S_DEFMACRO, S_DEFPARAMETER;

instream *kbd_in;               /* the REPL's line(s) */
int screen_cols = 60;

/* ---- output ---- */

static FILE *fout;              /* the file open for output */
static int fout_col;
static instream fin;            /* the file open for input, read whole */
static int fin_open;

typedef struct { sink s; sink *prev; obj stream; } streamsink;

static void ram_putc(int c);

static void put_to_file(sink *s, int c)
{
    (void)s;
    if (fout)
        fputc(c, fout);
    else
        ram_putc(c);
}

static obj struct_kind(obj s)
{
    return isstruct(s) ? vec_elts(s)[0] : NIL;
}

static void __attribute__((noreturn)) not_open(obj s) { lisp_error("the stream is not open", s); }

/* stream_sink: printing to a stream -> the sink pushed for the call (NULL:
 * the screen, as it is) */
sink *stream_sink(obj stream)
{
    if (stream == NIL || stream == S_T) {
        stream = SYM(S_STDOUT)->value;
        if (stream == NIL || stream == S_T || stream == UNBOUND)
            return NULL;
    }
    obj k = struct_kind(stream);
    if (k == S_STRING_OUTPUT_STREAM) {
        sink *s = push_string_sink();
        sink_set_tag(s, stream);
        return s;
    }
    if (k == S_FILE_STREAM) {
        if (vec_elts(stream)[3] == NIL || vec_elts(stream)[2] != S_KW_OUTPUT)
            not_open(stream);
        streamsink *ss = calloc(1, sizeof *ss);
        ss->s.put = put_to_file;
        ss->s.col = fout_col;
        ss->prev = out;
        ss->stream = stream;
        out = &ss->s;
        return &ss->s;
    }
    lisp_error("the stream is not open", stream);
}

void stream_done(sink *s, obj stream)
{
    if (!s)
        return;
    (void)stream;
    if (s->put == put_to_file) {
        streamsink *ss = (streamsink *)s;
        fout_col = s->col;
        out = ss->prev;
        free(ss);
        return;
    }
    /* a string output stream: the text a chunk of it */
    obj st = sink_tag(s);
    obj str = pop_string_sink(s);
    if (str_len(str) > 0)
        vec_elts(st)[1] = cons(str, vec_elts(st)[1]);
}

/* ---- input ---- */

/* the keyboard: the REPL's line; past its end, the next line typed */
extern int plain_refill;

/* keys typed (the tests' "!type"): read-char and its kin at the keyboard
 * take keys, not lines */
static char keyq[1024];
static int kq_n;

void push_keys(const char *s)
{
    while (*s && kq_n < (int)sizeof keyq)
        keyq[kq_n++] = *s++;
}

static int key_take(int peek)
{
    if (kq_n == 0)
        return -1;
    int c = (uint8_t)keyq[0];
    if (!peek) {
        memmove(keyq, keyq + 1, --kq_n);
    }
    return c;
}

static void key_unread(int c)
{
    if (kq_n < (int)sizeof keyq) {
        memmove(keyq + 1, keyq, kq_n++);
        keyq[0] = (char)c;
    }
}

static int is_kbd(obj stream) { return stream == NIL || stream == S_T; }

static void kbd_next_line(int plain)
{
    if (!kbd_in)
        return;
    /* only the line's end left, or nothing: the next line is what is read */
    if (kbd_in->pos >= kbd_in->len
        || (kbd_in->pos + 1 == kbd_in->len && kbd_in->buf[kbd_in->pos] == '\n')) {
        kbd_in->pos = kbd_in->len;
        if (kbd_in->refill) {
            plain_refill = plain;
            kbd_in->refill(kbd_in);
            plain_refill = 0;
        }
    }
}

typedef struct {
    instream tmp;
    instream *in;               /* what is read from */
    obj stream;
    int kind;                   /* 0 keyboard, 1 string, 2 file */
} source;

static int open_source_how(obj stream, source *src, int plain)
{
    src->stream = stream;
    if (stream == NIL || stream == S_T) {
        if (!kbd_in)
            lisp_error0("end of file");
        kbd_next_line(plain);
        src->in = kbd_in;
        src->kind = 0;
        return 1;
    }
    obj k = struct_kind(stream);
    if (k == S_STRING_INPUT_STREAM) {
        obj s = vec_elts(stream)[1];
        int32_t idx = check_int(vec_elts(stream)[2]);
        uint32_t n = str_len(s);
        if ((uint32_t)idx > n) idx = (int32_t)n;
        in_init(&src->tmp, str_chars(s) + idx, n - idx);
        src->in = &src->tmp;
        src->kind = 1;
        return 1;
    }
    if (k == S_FILE_STREAM) {
        if (vec_elts(stream)[3] == NIL || vec_elts(stream)[2] != S_KW_INPUT || !fin_open)
            not_open(stream);
        src->in = &fin;
        src->kind = 2;
        return 1;
    }
    lisp_error("the stream is not open", stream);
}

static int open_source(obj stream, source *src) { return open_source_how(stream, src, 1); }

static void close_source(source *src)
{
    if (src->kind == 1) {
        obj st = src->stream;
        vec_elts(st)[2] = mkfix(fixval(vec_elts(st)[2]) + (int32_t)src->tmp.pos);
        in_free(&src->tmp);
    }
}

static obj eof_result(int c, obj *a, int from)
{
    int eof_error = c > from ? a[from] != NIL : 1;
    if (eof_error)
        lisp_error0("end of file");
    return c > from + 1 ? a[from + 1] : NIL;
}

static obj f_read(int c, obj *a)
{
    source src;
    open_source_how(c > 0 ? a[0] : NIL, &src, 0);
    obj x = lisp_read(src.in, 0, EOFMARK);
    close_source(&src);
    if (x == EOFMARK)
        return eof_result(c, a, 1);
    return x;
}

static obj f_read_line(int c, obj *a)
{
    source src;
    open_source(c > 0 ? a[0] : NIL, &src);
    int ch = in_getc(src.in);
    if (ch < 0) {
        close_source(&src);
        return eof_result(c, a, 1);
    }
    char *buf = NULL;
    size_t n = 0, cap = 0;
    while (ch >= 0 && ch != '\n') {
        if (ch != '\r') {
            if (n == cap) { cap = cap ? cap * 2 : 64; buf = realloc(buf, cap); }
            buf[n++] = (char)ch;
        }
        ch = in_getc(src.in);
    }
    close_source(&src);
    obj r = mkstring(buf ? buf : "", n);
    free(buf);
    return r;
}

static obj f_read_char(int c, obj *a)
{
    if (is_kbd(c > 0 ? a[0] : NIL)) {
        int ch = key_take(0);
        if (ch < 0)
            return eof_result(c, a, 1);
        return mkchar(ch);
    }
    source src;
    open_source(c > 0 ? a[0] : NIL, &src);
    int ch = in_getc(src.in);
    close_source(&src);
    if (ch < 0)
        return eof_result(c, a, 1);
    return mkchar(ch);
}

static obj f_read_char_no_hang(int c, obj *a)
{
    if (is_kbd(c > 0 ? a[0] : NIL)) {
        int ch = key_take(0);
        return ch < 0 ? NIL : mkchar(ch);
    }
    return f_read_char(c, a);
}

static obj f_peek_char(int c, obj *a)
{
    obj type = c > 0 ? a[0] : NIL;
    if (is_kbd(c > 1 ? a[1] : NIL)) {
        int ch = key_take(1);
        if (ch < 0)
            return eof_result(c, a, 2);
        return mkchar(ch);
    }
    source src;
    open_source(c > 1 ? a[1] : NIL, &src);
    int ch;
    for (;;) {
        ch = in_peek(src.in);
        if (ch < 0 || type == NIL)
            break;
        if (type == S_T && !isspace(ch))
            break;
        if (ischar(type) && ch == (int)charval(type))
            break;
        in_getc(src.in);
    }
    close_source(&src);
    if (ch < 0)
        return eof_result(c, a, 2);
    return mkchar(ch);
}

static obj f_unread_char(int c, obj *a)
{
    if (!ischar(a[0]))
        lisp_error("not a character:", a[0]);
    if (is_kbd(c > 1 ? a[1] : NIL)) {
        key_unread((int)charval(a[0]));
        return NIL;
    }
    source src;
    open_source(c > 1 ? a[1] : NIL, &src);
    if (src.kind == 1) {
        obj st = src.stream;
        in_free(&src.tmp);
        int32_t i = fixval(vec_elts(st)[2]);
        if (i > 0) vec_elts(st)[2] = mkfix(i - 1);
        return NIL;
    }
    in_unget(src.in);
    if (src.kind == 2 && src.in->pos < src.in->len)
        src.in->buf[src.in->pos] = (char)charval(a[0]);
    return NIL;
}

static obj f_listen(int c, obj *a)
{
    obj stream = c > 0 ? a[0] : NIL;
    if (stream == NIL || stream == S_T)
        return bool_obj(kq_n > 0);
    source src;
    open_source(stream, &src);
    int r = src.in->pos < src.in->len;
    close_source(&src);
    return bool_obj(r);
}

/* ---- the pretty printer ---- */

static int pp_width = 40;
static int pp_data;

static int printed_length(obj o)
{
    sink *s = push_string_sink();
    prin1(o);
    obj str = pop_string_sink(s);
    return (int)str_len(str);
}

static int pp_fits(obj o, int col)
{
    int room = pp_width - col - 1;
    if (room < 0) room = 0;
    return printed_length(o) <= room;
}

static void pp_newline(int col)
{
    newline();
    for (int i = 0; i < col; i++)
        putch(' ');
}

static int body_count(obj op)
{
    static const struct { const char *n; int k; } forms[] = {
        {"DEFUN", 2}, {"DEFMACRO", 2}, {"LAMBDA", 1}, {"LET", 1}, {"LET*", 1},
        {"FLET", 1}, {"LABELS", 1}, {"WHEN", 1}, {"UNLESS", 1}, {"DOLIST", 1},
        {"DOTIMES", 1}, {"BLOCK", 1}, {"LOOP", 0}, {"PROGN", 0}, {"PROG1", 1},
        {"CASE", 1}, {"CATCH", 1}, {"DO", 2}, {"DO*", 2}, {"UNWIND-PROTECT", 1},
        {NULL, 0}};
    obj nm = SYM(op)->name;
    for (int i = 0; forms[i].n; i++)
        if (str_len(nm) == strlen(forms[i].n) && !memcmp(str_chars(nm), forms[i].n, str_len(nm)))
            return forms[i].k;
    return -1;
}

extern obj S_EXPANDED;

static void pp(obj o);

static void pp_lines(obj rest, int col)
{
    while (iscons(rest)) {
        pp_newline(col);
        pp(car(rest));
        rest = cdr(rest);
    }
    if (rest != NIL) {
        putstr(" . ");
        prin1(rest);
    }
    putch(')');
}

static void pp(obj o)
{
    if (!iscons(o) || pp_fits(o, out->col)) {
        prin1(o);
        return;
    }
    if (car(o) == S_EXPANDED && iscons(cdr(o)) && iscons(cdr(cdr(o)))) {
        pp(cdr(cdr(o)));
        return;
    }
    obj a = car(o);
    if (issym(a) && iscons(cdr(o)) && cdr(cdr(o)) == NIL) {
        const char *pre = NULL;
        if (a == S_QUOTE) pre = "'";
        else if (a == S_FUNCTION) pre = "#'";
        else if (a == S_QUASIQUOTE) pre = "`";
        else if (a == S_UNQUOTE) pre = ",";
        else if (a == S_UNQUOTE_SPLICING) pre = ",@";
        if (pre) {
            putstr(pre);
            int saved = pp_data;
            pp_data |= a == S_QUOTE;
            pp(car(cdr(o)));
            pp_data = saved;
            return;
        }
    }
    int col0 = out->col;
    putch('(');
    obj first = car(o), rest = cdr(o);
    if (iscons(first)) {
        pp(first);
        pp_lines(rest, col0 + 1);
        return;
    }
    prin1(first);
    int n = issym(first) && !pp_data ? body_count(first) : -2;
    if (n == -2) {                      /* data: as many to a line as fit */
        int col = col0 + 1;
        while (iscons(rest)) {
            obj e = car(rest);
            if (pp_fits(e, out->col + 1)) {
                putch(' ');
            } else
                pp_newline(col);
            pp(e);
            rest = cdr(rest);
        }
        if (rest != NIL) {
            putstr(" . ");
            prin1(rest);
        }
        putch(')');
        return;
    }
    if (n >= 0) {                       /* a form with a body */
        while (n-- > 0 && iscons(rest)) {
            putch(' ');
            pp(car(rest));
            rest = cdr(rest);
        }
        pp_lines(rest, col0 + 2);
        return;
    }
    if (!iscons(rest)) {                /* a call */
        pp_lines(rest, col0 + 1);
        return;
    }
    if (out->col >= pp_width / 2) {
        pp_lines(rest, col0 + 1);
        return;
    }
    putch(' ');
    int col = out->col;
    pp(car(rest));
    pp_lines(cdr(rest), col);
}

void pretty_print(obj o, int width)
{
    int saved_w = pp_width, saved_d = pp_data;
    pp_width = width;
    pp_data = 0;
    pp(o);
    pp_width = saved_w;
    pp_data = saved_d;
}

static obj f_pprint(int c, obj *a)
{
    obj stream = c > 1 ? a[1] : NIL;
    sink *s = stream_sink(stream);
    newline();
    pretty_print(a[0], s && s->put == put_to_file ? 72 : screen_cols);
    stream_done(s, stream);
    return NIL;
}

/* ---- files ---- */

/* the RAM disc M:: files in memory (PSRAM on the device), kept in the
 * order they were made -- as the 512K CPC's (mach/cpc512/ramdisc.asm) */
typedef struct { char name[13]; uint8_t *data; size_t len; } ramfile;
static ramfile ram[63];
static int nram;
static uint8_t *ram_out;                /* the output file, while open on M: */
static size_t ram_out_len, ram_out_cap;
static char ram_out_name[13];
static int ram_out_open;

static long ram_cap_k(void)
{
    const char *e = getenv("POCKET_RAMDISC_K");
    return e ? atol(e) : 4096;
}

/* used: the 1 KB directory and the files packed after it */
static long ram_used_k(void)
{
    size_t bytes = 1024;
    for (int i = 0; i < nram; i++)
        bytes += ram[i].len;
    return (long)((bytes + 1023) / 1024);
}

static int ram_find(const char *nm)
{
    for (int i = 0; i < nram; i++)
        if (!strcmp(ram[i].name, nm))
            return i;
    return -1;
}

static void ram_delete_at(int i)
{
    free(ram[i].data);
    memmove(&ram[i], &ram[i + 1], (size_t)(nram - i - 1) * sizeof(ramfile));
    nram--;
}

/* a CPC name -> the file's name here: upper case, .LSP if it has no
 * extension, a drive letter dropped; *is_ram for M:, whose names must be
 * 8.3 */
static void file_name_ram(obj name, char *buf, size_t sz, int *is_ram)
{
    name = string_designator(name);
    uint32_t n = str_len(name);
    const char *s = str_chars(name);
    char tmp[256];
    size_t k = 0;
    *is_ram = 0;
    if (n >= 2 && s[1] == ':') {
        if (s[0] == 'm' || s[0] == 'M')
            *is_ram = 1;
        s += 2;
        n -= 2;
    }
    int dot = -1;
    for (uint32_t i = 0; i < n && k < sizeof tmp - 5; i++) {
        char ch = s[i];
        if (ch == '.' && dot < 0) dot = (int)k;
        tmp[k++] = (char)toupper((uint8_t)ch);
    }
    tmp[k] = 0;
    if (n == 0)
        lisp_error("bad file name:", name);
    if (*is_ram) {
        int nl = dot < 0 ? (int)k : dot;
        int el = dot < 0 ? 3 : (int)k - dot - 1;
        if (nl == 0 || nl > 8 || el > 3)
            lisp_error("bad file name:", name);
    }
    snprintf(buf, sz, "%s%s", tmp, dot >= 0 ? "" : ".LSP");
}

static void file_name(obj name, char *buf, size_t sz)
{
    int r;
    file_name_ram(name, buf, sz, &r);
}

/* "NAME    .EXT not found", as the disc ROM says it */
static void amsdos_name(const char *path, char *out8_3)
{
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    const char *dot = strchr(base, '.');
    int nl = dot ? (int)(dot - base) : (int)strlen(base);
    snprintf(out8_3, 16, "%-8.*s.%-3s", nl > 8 ? 8 : nl, base, dot ? dot + 1 : "");
}

static void amsdos_not_found(const char *path)
{
    char nm[16];
    amsdos_name(path, nm);
    fresh_line();
    newline();
    putstr(nm);
    putstr(" not found");
    newline();
}

static void open_input(obj name)
{
    if (fin_open)
        lisp_error("a file is open that way already:", name);
    char path[300];
    int is_ram;
    file_name_ram(name, path, sizeof path, &is_ram);
    if (is_ram) {
        int i = ram_find(path);
        if (i < 0)
            lisp_error("cannot open", name);
        in_init(&fin, (const char *)ram[i].data, ram[i].len);
        fin_open = 1;
        return;
    }
    FILE *f = fopen(path, "rb");
    if (!f) {
        amsdos_not_found(path);
        lisp_error("cannot open", name);
    }
    char *buf = NULL;
    size_t n = 0, cap = 0, got;
    char chunk[4096];
    while ((got = fread(chunk, 1, sizeof chunk, f)) > 0) {
        if (n + got > cap) { cap = (n + got) * 2; buf = realloc(buf, cap); }
        memcpy(buf + n, chunk, got);
        n += got;
    }
    fclose(f);
    in_init(&fin, buf ? buf : "", n);
    free(buf);
    fin_open = 1;
}

static void close_input(void)
{
    if (fin_open) {
        in_free(&fin);
        fin_open = 0;
    }
}

static int output_open(void) { return fout != NULL || ram_out_open; }

static void ram_putc(int c)
{
    if (ram_out_len == ram_out_cap) {
        ram_out_cap = ram_out_cap ? ram_out_cap * 2 : 1024;
        ram_out = realloc(ram_out, ram_out_cap);
    }
    ram_out[ram_out_len++] = (uint8_t)c;
}

static void open_output(obj name)
{
    if (output_open())
        lisp_error("a file is open that way already:", name);
    char path[300];
    int is_ram;
    file_name_ram(name, path, sizeof path, &is_ram);
    if (is_ram) {
        snprintf(ram_out_name, sizeof ram_out_name, "%s", path);
        ram_out_len = 0;
        ram_out_open = 1;
        fout_col = 0;
        return;
    }
    fout = fopen(path, "wb");
    if (!fout)
        lisp_error("cannot open", name);
    fout_col = 0;
}

/* closed: on M: the file made (in its old place if the name was there);
 * one that does not fit is dropped -> 0 */
static int close_output(void)
{
    if (fout) {
        fclose(fout);
        fout = NULL;
        return 1;
    }
    if (!ram_out_open)
        return 1;
    ram_out_open = 0;
    int i = ram_find(ram_out_name);
    size_t bytes = 1024 + ram_out_len;
    for (int k = 0; k < nram; k++)
        if (k != i)
            bytes += ram[k].len;
    if ((long)((bytes + 1023) / 1024) > ram_cap_k() || (i < 0 && nram >= 63)) {
        if (i >= 0)
            ram_delete_at(i);
        return 0;
    }
    uint8_t *data = malloc(ram_out_len ? ram_out_len : 1);
    memcpy(data, ram_out, ram_out_len);
    if (i >= 0) {
        free(ram[i].data);
        ram[i].data = data;
        ram[i].len = ram_out_len;
    } else {
        snprintf(ram[nram].name, sizeof ram[nram].name, "%s", ram_out_name);
        ram[nram].data = data;
        ram[nram].len = ram_out_len;
        nram++;
    }
    return 1;
}

static void abandon_output(void)
{
    if (fout) {
        fclose(fout);
        fout = NULL;
    }
    ram_out_open = 0;
}

/* toplevel: files left open by an error are abandoned */
void abandon_files(void)
{
    close_input();
    abandon_output();
}

static obj f_open(int c, obj *a)
{
    (void)c;
    if (a[1] != NIL) open_output(a[0]); else open_input(a[0]);
    return S_T;
}

static obj f_close(int c, obj *a)
{
    (void)c;
    if (a[0] != NIL)
        return bool_obj(close_output());
    close_input();
    return S_T;
}

/* (%file-pos): the characters read from the input file, NIL if none is
 * open; (%file-skip n): on to character n (forward only) */
static obj f_file_pos(int c, obj *a)
{
    (void)c; (void)a;
    return fin_open ? mkfix((int32_t)fin.pos) : NIL;
}

static obj f_file_skip(int c, obj *a)
{
    (void)c;
    int32_t n = check_int(a[0]);
    if (!fin_open || n < 0 || (size_t)n < fin.pos)
        return NIL;                     /* forward only */
    if ((size_t)n > fin.len) {
        fin.pos = fin.len;              /* past the end: there, and NIL */
        return NIL;
    }
    fin.pos = (size_t)n;
    return S_T;
}

/* (%load name): every form in the file evaluated -> T */
static obj f_load(int c, obj *a)
{
    (void)c;
    open_input(a[0]);
    int was = loading_library;
    loading_library = 0;
    for (;;) {
        obj x = lisp_read(&fin, 0, EOFMARK);
        if (x == EOFMARK)
            break;
        eval(x, NIL);
    }
    loading_library = was;
    close_input();
    return S_T;
}

/* a symbol's definition, as save writes it */
static obj definition(obj s)
{
    obj f = SYM(s)->fn;
    int macro = istype(f, T_MACRO);
    if (macro)
        f = DATA(f);
    if (!istype(f, T_CLOSURE))
        return NIL;
    obj lambda = car(DATA(f));
    obj params = car(lambda), body = cdr(lambda);
    /* the body in its (block name ...): unwrapped */
    if (iscons(body) && cdr(body) == NIL && iscons(car(body)) && car(car(body)) == S_BLOCK
        && iscons(cdr(car(body))) && car(cdr(car(body))) == s)
        body = cdr(cdr(car(body)));
    return cons(macro ? S_DEFMACRO : S_DEFUN, cons(s, cons(params, body)));
}

static int has_def(obj s)
{
    obj f = SYM(s)->fn;
    return istype(f, T_CLOSURE) || istype(f, T_MACRO) || SYM(s)->value != UNBOUND;
}

static obj f_save(int c, obj *a)
{
    obj saved_syms = NIL;
    if (c > 1) {
        for (int i = c - 1; i >= 1; i--) {
            obj s = check_sym(a[i]);
            if (!has_def(s))
                lisp_error("nothing to save for", s);
            saved_syms = cons(s, saved_syms);
        }
    } else {
        /* the user's definitions, in the order they were made */
        uint32_t last = 0xFFFFFFFFu;
        for (;;) {
            uint32_t best = 0, bi = 0;
            for (uint32_t i = 1; i < nsyms; i++) {
                obj s = mksym(i);
                uint32_t q = SYM(s)->defseq;
                if (syms_flags_userdef(s) && has_def(s) && q < last && q > best) {
                    best = q;
                    bi = i;
                }
            }
            if (!bi)
                break;
            saved_syms = cons(mksym(bi), saved_syms);
            last = best;
        }
        if (saved_syms == NIL)
            lisp_error0("nothing to save");
    }
    if (output_open())
        lisp_error("a file is open that way already:", a[0]);
    open_output(a[0]);
    streamsink ss = {{put_to_file, 0, NULL}, out, NIL};
    out = &ss.s;
    for (obj l = saved_syms; iscons(l); l = cdr(l)) {
        obj s = car(l);
        obj d = definition(s);
        if (d == NIL || (!istype(SYM(s)->fn, T_CLOSURE) && !istype(SYM(s)->fn, T_MACRO)))
            d = list3(S_DEFPARAMETER, s, list2(S_QUOTE, SYM(s)->value));
        pretty_print(d, 72);
        newline();
        newline();
    }
    out = ss.prev;
    if (!close_output())
        lisp_error0("cannot write the file");
    return saved_syms;
}

int syms_flags_userdef(obj s) { return (SYM(s)->flags & SF_USERDEF) != 0; }

static obj f_delete_file(int c, obj *a)
{
    (void)c;
    char path[300];
    int is_ram;
    file_name_ram(a[0], path, sizeof path, &is_ram);
    if (is_ram) {
        int i = ram_find(path);
        if (i < 0)
            lisp_error("no such file:", a[0]);
        ram_delete_at(i);
        return S_T;
    }
    if (remove(path) != 0)
        amsdos_not_found(path);
    return S_T;
}

static int cmp_names(const void *x, const void *y)
{
    return strcmp(*(char *const *)x, *(char *const *)y);
}

/* (%dir [m]): the files and their sizes, two to a line, and what is
 * free -- laid out as AMSDOS does. POCKET_DISC_K sets a disc's size (the
 * tests: a CPC data disc, 178 K); else the free space is the medium's. */
/* the RAM disc's catalogue, as the 512K CPC's: in the order made */
static obj ram_dir(void)
{
    fresh_line();
    newline();
    putstr("Drive M: (RAM)");
    newline();
    for (int i = 0; i < nram; i++) {
        char field[40];
        snprintf(field, sizeof field, "%-14s%ldK", ram[i].name, (long)((ram[i].len + 1023) / 1024));
        putstr(field);
        if (i % 2 == 0) {
            for (int k = (int)strlen(field); k < 20; k++)
                putch(' ');
            if (i + 1 == nram)
                newline();
        } else
            newline();
    }
    char line[32];
    snprintf(line, sizeof line, "%ldK free", ram_cap_k() - ram_used_k());
    putstr(line);
    newline();
    return NIL;
}

static obj f_dir(int c, obj *a)
{
    int ram = c > 0 && a[0] != NIL;
    if (ram)
        return ram_dir();
    const char *dirname = ram ? "M" : ".";
    DIR *d = opendir(dirname);
    char *names[1024];
    long ks[1024];
    int n = 0;
    long used = 0;
    if (d) {
        struct dirent *e;
        while ((e = readdir(d)) && n < 1024) {
            if (e->d_name[0] == '.')
                continue;
            char path[600];
            snprintf(path, sizeof path, "%s/%s", dirname, e->d_name);
            struct stat st;
            if (stat(path, &st) || !S_ISREG(st.st_mode))
                continue;
            names[n] = strdup(e->d_name);
            ks[n] = st.st_size ? (long)((st.st_size + 1023) / 1024) : 0;
            used += ks[n];
            n++;
        }
        closedir(d);
    }
    /* sorted by name, the sizes with them */
    for (int i2 = 1; i2 < n; i2++)
        for (int j2 = i2; j2 > 0 && strcmp(names[j2 - 1], names[j2]) > 0; j2--) {
            char *t = names[j2]; names[j2] = names[j2 - 1]; names[j2 - 1] = t;
            long k = ks[j2]; ks[j2] = ks[j2 - 1]; ks[j2 - 1] = k;
        }
    fresh_line();
    newline();
    putstr(ram ? "Drive M: user  0" : "Drive A: user  0");
    newline();
    newline();
    for (int i2 = 0; i2 < n; i2++) {
        char nm[16], line[48];
        amsdos_name(names[i2], nm);
        snprintf(line, sizeof line, "%s%4ldK", nm, ks[i2]);
        putstr(line);
        if (i2 % 2 == 0 && i2 + 1 < n)
            putstr("   ");
        else
            newline();
        free(names[i2]);
    }
    if (n)
        newline();
    long free_k;
    const char *dk = getenv("POCKET_DISC_K");
    if (dk)
        free_k = atol(dk) - used;
    else {
        struct statvfs vs;
        free_k = statvfs(dirname, &vs) == 0 ? (long)(vs.f_bavail * vs.f_frsize / 1024) : 0;
    }
    char line[32];
    snprintf(line, sizeof line, "%ldK free", free_k);
    putstr(line);
    newline();
    newline();
    return NIL;
}

static obj f_cd(int c, obj *a)
{
    if (c == 0)
        return mkstr("A:");
    if (a[0] == NIL)
        return S_T;
    obj s = string_designator(a[0]);
    if (str_len(s) == 0)
        return NIL;
    int ch = toupper((uint8_t)str_chars(s)[0]);
    return bool_obj(ch == 'A');
}

void init_lib2(void)
{
    S_STRING_OUTPUT_STREAM = intern_cstr("STRING-OUTPUT-STREAM");
    S_STRING_INPUT_STREAM = intern_cstr("STRING-INPUT-STREAM");
    S_FILE_STREAM = intern_cstr("FILE-STREAM");
    S_KW_INPUT = intern_cstr(":INPUT");
    S_KW_OUTPUT = intern_cstr(":OUTPUT");
    S_DEFUN = intern_cstr("DEFUN");
    S_DEFMACRO = intern_cstr("DEFMACRO");
    S_DEFPARAMETER = intern_cstr("DEFPARAMETER");
    defsubr("READ", f_read, 0, 4);
    defsubr("READ-LINE", f_read_line, 0, 4);
    defsubr("READ-CHAR", f_read_char, 0, 4);
    defsubr("READ-CHAR-NO-HANG", f_read_char_no_hang, 0, 4);
    defsubr("PEEK-CHAR", f_peek_char, 0, 5);
    defsubr("UNREAD-CHAR", f_unread_char, 1, 2);
    defsubr("LISTEN", f_listen, 0, 1);
    defsubr("PPRINT", f_pprint, 1, 2);
    defsubr("%OPEN", f_open, 2, 2);
    defsubr("%CLOSE", f_close, 1, 1);
    defsubr("%FILE-POS", f_file_pos, 0, 0);
    defsubr("%FILE-SKIP", f_file_skip, 1, 1);
    defsubr("%LOAD", f_load, 1, 1);
    defsubr("SAVE", f_save, 1, ANY);
    defsubr("DELETE-FILE", f_delete_file, 1, 1);
    defsubr("%DIR", f_dir, 0, 1);
    defsubr("CD", f_cd, 0, 1);
    init_far();
}

/* ---- far arrays: files NAME.FAR on M: -- "F", the element type (0 T: an
 * object's word, 4 bytes; 1 (unsigned-byte 8), 2 character: a byte), the
 * elements -- read and written in place (CPC Lisp's lib/farray.asm) ---- */

static obj S_FAR_ARRAY;

static int far_esize(int type) { return type == 0 ? 4 : 1; }

/* the far array a's file on M: -> its index; its type in *type */
static int far_file(obj a, int *type)
{
    if (!isstruct(a) || vec_elts(a)[0] != S_FAR_ARRAY)
        lisp_error("not the structure it should be:", a);
    char path[300];
    int is_ram;
    file_name_ram(vec_elts(a)[1], path, sizeof path, &is_ram);
    int i = ram_find(path);
    if (i < 0 || ram[i].len < 2 || ram[i].data[0] != 'F')
        lisp_error("no such far array:", a);
    *type = ram[i].data[1];
    return i;
}

static uint32_t far_index(int f, int type, obj idx)
{
    uint32_t n = (uint32_t)((ram[f].len - 2) / far_esize(type));
    if (!isfix(idx) || fixval(idx) < 0 || (uint32_t)fixval(idx) >= n)
        lisp_error("index out of range", idx);
    return (uint32_t)fixval(idx);
}

static obj f_far_ref(int c, obj *a)
{
    (void)c;
    int type;
    int f = far_file(a[0], &type);
    uint32_t i = far_index(f, type, a[1]);
    uint8_t *p = ram[f].data + 2 + i * far_esize(type);
    if (type == 1)
        return mkfix(*p);
    if (type == 2)
        return mkchar(*p);
    obj o;
    memcpy(&o, p, 4);
    return o;
}

static obj f_far_set(int c, obj *a)
{
    (void)c;
    int type;
    int f = far_file(a[0], &type);
    uint32_t i = far_index(f, type, a[1]);
    obj v = a[2];
    uint8_t *p = ram[f].data + 2 + i * far_esize(type);
    if (type == 1) {
        if (!isfix(v) || fixval(v) < 0 || fixval(v) > 255)
            lisp_error("a far array cannot hold:", v);
        *p = (uint8_t)fixval(v);
    } else if (type == 2) {
        if (!ischar(v))
            lisp_error("a far array cannot hold:", v);
        *p = (uint8_t)charval(v);
    } else {
        if (!(isfix(v) || ischar(v) || v == NIL || v == S_T))
            lisp_error("a far array cannot hold:", v);
        memcpy(p, &v, 4);
    }
    return v;
}

static obj f_far_length(int c, obj *a)
{
    (void)c;
    int type;
    int f = far_file(a[0], &type);
    return mkfix((int32_t)((ram[f].len - 2) / far_esize(type)));
}

static obj f_far_open(int c, obj *a)
{
    (void)c;
    char path[300];
    int is_ram;
    file_name_ram(a[0], path, sizeof path, &is_ram);
    int i = ram_find(path);
    if (i < 0 || ram[i].len < 2 || ram[i].data[0] != 'F')
        return NIL;
    return mkfix(ram[i].data[1]);
}

/* (%far-fill n type): into the file open for output, a far array's header
 * and n elements of 0 -> T */
static obj f_far_fill(int c, obj *a)
{
    (void)c;
    int32_t n = check_int(a[0]);
    int type = check_int(a[1]);
    if (!ram_out_open)
        lisp_error0("cannot write the file");
    ram_putc('F');
    ram_putc(type);
    long bytes = (long)n * far_esize(type);
    long room = (ram_cap_k() - ram_used_k()) * 1024L + 1024;
    for (long k = 0; k < bytes && (long)ram_out_len < room; k++)
        ram_putc(0);
    return S_T;
}

void init_far(void)
{
    S_FAR_ARRAY = intern_cstr("FAR-ARRAY");
    defsubr("FAR-REF", f_far_ref, 2, 2);
    defsubr("%FAR-SET", f_far_set, 3, 3);
    defsubr("FAR-LENGTH", f_far_length, 1, 1);
    defsubr("%FAR-OPEN", f_far_open, 1, 1);
    defsubr("%FAR-FILL", f_far_fill, 2, 2);
}
