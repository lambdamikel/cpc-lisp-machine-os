;; CPC Lisp -- the builtin symbols.
;;
;; One entry per symbol, in slot order: entry i becomes symbol slot i at
;; boot, so S_name is a constant the code can use. An entry is also the
;; symbol's function object when it has one -- its pointer is the entry + 2,
;; the same tag-10 shape as a typed cell:
;;
;;   +0 header   HDR_SUBR, HDR_FSUBR (special form) or HDR_NOFN
;;   +2 code
;;   +4 min, max arguments (max 255: any number)
;;   +6 flags    SF_SPECIAL, SF_CONST
;;   +7 value    0 unbound, 1 itself, 2 NIL
;;   +8 name     [length word][characters] -- the symbol's name points here
;;
;; Entries are 4-aligned so that entry + 2 has the tag bits 10.

symidx = 0

macro SYMENTRY lbl,str,hdr,code,mn,mx,flags,init
    align 4
S_{lbl} equ SYM_LO+2+8*symidx
E_{lbl}:
    dw {hdr}
    dw {code}
    db {mn},{mx},{flags},{init}
    dw .e-.n
.n:
    db {str}
.e:
symidx = symidx+1
mend

macro SUBR lbl,str,code,mn,mx
    SYMENTRY {lbl},{str},HDR_SUBR,{code},{mn},{mx},0,0
mend

macro FSUBR lbl,str,code
    SYMENTRY {lbl},{str},HDR_FSUBR,{code},0,0,0,0
mend

macro SYMBOL lbl,str,flags,init
    SYMENTRY {lbl},{str},HDR_NOFN,0,0,0,{flags},{init}
mend

    align 4                             ; the first entry IS symtab
symtab:
    SYMBOL NIL,"NIL",SF_CONST,2         ; slot 0: NIL itself is 0
    SYMBOL T,"T",SF_CONST,1
    SYMBOL AMP_OPTIONAL,"&OPTIONAL",SF_CONST,0  ; (constants: apply_closure_stack)
    SYMBOL AMP_REST,"&REST",SF_CONST,0
    SYMBOL AMP_BODY,"&BODY",SF_CONST,0
    SYMBOL AMP_KEY,"&KEY",SF_CONST,0
    SYMBOL AMP_AUX,"&AUX",SF_CONST,0           ; (bind: these five together)
    assert S_AMP_AUX-S_AMP_OPTIONAL == 32
    assert (S_AMP_OPTIONAL >> 8) == (S_AMP_AUX >> 8)
    SYMBOL OTHERWISE,"OTHERWISE",0,0
    SYMBOL UNQUOTE,"UNQUOTE",0,0
    SYMBOL UNQUOTE_SPLICING,"UNQUOTE-SPLICING",0,0

    ; special forms
    FSUBR QUOTE,"QUOTE",sf_quote
    FSUBR FUNCTION,"FUNCTION",sf_function
    FSUBR LAMBDA,"LAMBDA",sf_lambda
    FSUBR QUASIQUOTE,"QUASIQUOTE",sf_quasiquote
    FSUBR IF,"IF",sf_if
    FSUBR WHEN,"WHEN",sf_when
    FSUBR UNLESS,"UNLESS",sf_unless
    FSUBR COND,"COND",sf_cond
    FSUBR CASE,"CASE",sf_case
    FSUBR AND,"AND",sf_and
    FSUBR OR,"OR",sf_or
    FSUBR PROGN,"PROGN",sf_progn
    FSUBR PROG1,"PROG1",sf_prog1
    FSUBR SETQ,"SETQ",sf_setq
    FSUBR SETF,"SETF",sf_setf
    FSUBR INCF,"INCF",sf_incf
    FSUBR DECF,"DECF",sf_decf
    FSUBR PUSH,"PUSH",sf_push
    FSUBR POP,"POP",sf_pop
    FSUBR LET,"LET",sf_let
    FSUBR LETSTAR,"LET*",sf_letstar
    FSUBR FLET,"FLET",sf_flet
    FSUBR LABELS,"LABELS",sf_labels
    FSUBR DEFUN,"DEFUN",sf_defun
    FSUBR DEFMACRO,"DEFMACRO",sf_defmacro
    FSUBR DEFVAR,"DEFVAR",sf_defvar
    FSUBR DEFPARAMETER,"DEFPARAMETER",sf_defparameter
    FSUBR DEFCONSTANT,"DEFCONSTANT",sf_defconstant
    FSUBR BLOCK,"BLOCK",sf_block
    FSUBR RETURN_FROM,"RETURN-FROM",sf_return_from
    FSUBR RETURN,"RETURN",sf_return
    FSUBR CATCH,"CATCH",sf_catch
    FSUBR THROW,"THROW",sf_throw
    FSUBR DOLIST,"DOLIST",sf_dolist
    FSUBR DOTIMES,"DOTIMES",sf_dotimes
    FSUBR LOOP,"LOOP",sf_loop
    FSUBR DECLARE,"DECLARE",sf_declare
    FSUBR THE,"THE",sf_the
    FSUBR UNWIND_PROTECT,"UNWIND-PROTECT",sf_unwind_protect
    FSUBR MULTIPLE_VALUE_LIST,"MULTIPLE-VALUE-LIST",sf_mvlist
    FSUBR EXPANDED,"%EXPANDED",sf_expanded  ; a macro call, its expansion cached

    ; lists
    SUBR CAR,"CAR",car,1,1
    SUBR CDR,"CDR",cdr,1,1
    SUBR FIRST,"FIRST",car,1,1
    SUBR REST,"REST",cdr,1,1
    SUBR SECOND,"SECOND",subr_cadr,1,1
    SUBR THIRD,"THIRD",subr_caddr,1,1
    SUBR CAAR,"CAAR",subr_caar,1,1
    SUBR CADR,"CADR",subr_cadr,1,1
    SUBR CDAR,"CDAR",subr_cdar,1,1
    SUBR CDDR,"CDDR",subr_cddr,1,1
    SUBR CADDR,"CADDR",subr_caddr,1,1
    SUBR CDDDR,"CDDDR",subr_cdddr,1,1
    SUBR CONS,"CONS",cons,2,2
    SUBR LIST,"LIST",args_to_list,0,255
    SUBR LISTSTAR,"LIST*",liststar_args,1,255
    SUBR APPEND,"APPEND",subr_append,0,255
    SUBR LENGTH,"LENGTH",subr_length,1,1
    SUBR NTH,"NTH",subr_nth,2,2
    SUBR NTHCDR,"NTHCDR",subr_nthcdr,2,2
    SUBR LAST,"LAST",subr_last,1,1
    SUBR RPLACA,"RPLACA",subr_rplaca,2,2
    SUBR RPLACD,"RPLACD",subr_rplacd,2,2
    SUBR MAPCAR,"MAPCAR",subr_mapcar,2,255
    SUBR MAPC,"MAPC",subr_mapc,2,255
    SUBR APPLY,"APPLY",subr_apply,2,255
    SUBR FUNCALL,"FUNCALL",subr_funcall,1,255

    ; predicates
    SUBR NULL,"NULL",subr_null,1,1
    SUBR NOT,"NOT",subr_null,1,1
    SUBR ATOM,"ATOM",subr_atom,1,1
    SUBR CONSP,"CONSP",subr_consp,1,1
    SUBR LISTP,"LISTP",subr_listp,1,1
    SUBR SYMBOLP,"SYMBOLP",subr_symbolp,1,1
    SUBR NUMBERP,"NUMBERP",subr_numberp,1,1
    SUBR INTEGERP,"INTEGERP",subr_integerp,1,1
    SUBR STRINGP,"STRINGP",subr_stringp,1,1
    SUBR CHARACTERP,"CHARACTERP",subr_characterp,1,1
    SUBR FUNCTIONP,"FUNCTIONP",subr_functionp,1,1
    SUBR KEYWORDP,"KEYWORDP",subr_keywordp,1,1
    SUBR EQ,"EQ",subr_eq,2,2
    SUBR EQL,"EQL",subr_eql,2,2
    SUBR EQUAL,"EQUAL",subr_equal,2,2

    ; numbers
    SUBR PLUS,"+",subr_plus,0,255
    SUBR MINUS,"-",subr_minus,1,255
    SYMENTRY TIMES,"*",HDR_SUBR,subr_times,0,255,SF_SPECIAL,2 ; and the last value
    SYMBOL STAR2,"**",SF_SPECIAL,2       ;   the REPL printed, the one before,
    SYMBOL STAR3,"***",SF_SPECIAL,2      ;   and the one before that
    SUBR ONEPLUS,"1+",subr_inc,1,1
    SUBR ONEMINUS,"1-",subr_dec,1,1
    SUBR TRUNCATE,"TRUNCATE",subr_truncate,1,2
    SUBR FLOOR,"FLOOR",subr_floor,1,2
    SUBR MOD,"MOD",subr_mod,2,2
    SUBR REM,"REM",subr_rem,2,2
    SUBR ABS,"ABS",subr_abs,1,1
    SUBR MAX,"MAX",subr_max,1,255
    SUBR MIN,"MIN",subr_min,1,255
    SUBR LT,"<",subr_lt,1,255
    SUBR GT,">",subr_gt,1,255
    SUBR LE,"<=",subr_le,1,255
    SUBR GE,">=",subr_ge,1,255
    SUBR NUMEQ,"=",subr_numeq,1,255
    SUBR NUMNE,"/=",subr_numne,1,255
    SUBR ZEROP,"ZEROP",subr_zerop,1,1
    SUBR PLUSP,"PLUSP",subr_plusp,1,1
    SUBR MINUSP,"MINUSP",subr_minusp,1,1
    SUBR EVENP,"EVENP",subr_evenp,1,1
    SUBR ODDP,"ODDP",subr_oddp,1,1
    SUBR RANDOM,"RANDOM",subr_random,1,1

    ; symbols
    SUBR SYMBOL_NAME,"SYMBOL-NAME",subr_symbol_name,1,1
    SUBR SYMBOL_VALUE,"SYMBOL-VALUE",subr_symbol_value,1,1
    SUBR SYMBOL_FUNCTION,"SYMBOL-FUNCTION",subr_symbol_function,1,1
    SUBR SYMBOL_PLIST,"SYMBOL-PLIST",subr_symbol_plist,1,1
    SUBR SET,"SET",subr_set,2,2
    SUBR BOUNDP,"BOUNDP",subr_boundp,1,1
    SUBR FBOUNDP,"FBOUNDP",subr_fboundp,1,1
    SUBR MAKUNBOUND,"MAKUNBOUND",subr_makunbound,1,1
    SUBR FMAKUNBOUND,"FMAKUNBOUND",subr_fmakunbound,1,1
    SUBR GET,"GET",subr_get,2,3

    ; characters and strings
    SUBR CHAR_CODE,"CHAR-CODE",subr_char_code,1,1
    SUBR CODE_CHAR,"CODE-CHAR",subr_code_char,1,1
    SUBR CHAR,"CHAR",subr_char,2,2
    SUBR MAKE_ARRAY,"MAKE-ARRAY",subr_make_array,1,255
    SUBR VECTOR,"VECTOR",subr_vector,0,255
    SUBR AREF,"AREF",subr_aref,2,2
    SUBR SVREF,"SVREF",subr_aref,2,2
    SUBR ELT,"ELT",subr_elt,2,2
    SUBR VECTORP,"VECTORP",subr_vectorp,1,1
    SYMBOL KW_INITIAL_ELEMENT,":INITIAL-ELEMENT",SF_CONST,1
    SYMBOL KW_TEST,":TEST",SF_CONST,1         ; for the library's keywords
    SYMBOL KW_TEST_NOT,":TEST-NOT",SF_CONST,1
    SYMBOL KW_KEY,":KEY",SF_CONST,1
    SYMBOL KW_START,":START",SF_CONST,1
    SYMBOL KW_END,":END",SF_CONST,1
    SYMBOL KW_FROM_END,":FROM-END",SF_CONST,1
    SYMBOL KW_COUNT,":COUNT",SF_CONST,1
    SUBR STRING,"STRING",subr_string,1,1

    ; input, output, evaluation
    SUBR PRINT,"PRINT",subr_print,1,1
    SUBR PRIN1,"PRIN1",prin1,1,1
    SUBR PRINC,"PRINC",princ,1,1
    SUBR TERPRI,"TERPRI",subr_terpri,0,0
    SUBR WRITE_CHAR,"WRITE-CHAR",subr_write_char,1,1
    SUBR READ,"READ",subr_read,0,0
    SUBR EVAL,"EVAL",subr_eval,1,1
    SUBR MACROEXPAND_1,"MACROEXPAND-1",subr_macroexpand_1,1,1
    SUBR MACROEXPAND,"MACROEXPAND",subr_macroexpand,1,1
    SUBR ERROR,"ERROR",subr_error,1,255

    ; the system
    SUBR GC,"GC",subr_gc,0,0

    align 4
    dw 0                                ; the end
NBUILTIN equ symidx
    assert NBUILTIN < NSYMS
