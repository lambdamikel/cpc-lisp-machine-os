/* Pocket Lisp -- input streams for the reader */
#ifndef READ_H
#define READ_H
#include "lisp.h"

struct instream {
    char *buf;
    size_t len, pos, cap;
    size_t consumed;                    /* characters taken (file-position) */
    int (*refill)(instream *);          /* more text appended -> 1; 0 at the end */
    void *data;
};

void in_init(instream *in, const char *text, size_t n);
void in_append(instream *in, const char *text, size_t n);
void in_free(instream *in);
int in_getc(instream *in);
int in_peek(instream *in);
void in_unget(instream *in);
int in_at_end(instream *in);

#endif
