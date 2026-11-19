/* Pocket Lisp -- the CPC's own functions with nothing behind them on
 * Linux yet: graphics, sound, the card, keys. They take their arguments
 * and do nothing, so that programs written for the CPC run. */
#include "lisp.h"

static obj f_nil(int c, obj *a) { (void)c; (void)a; return NIL; }
static obj f_zero(int c, obj *a) { (void)c; (void)a; return mkfix(0); }
static obj f_four(int c, obj *a) { (void)c; (void)a; return mkfix(4); }
static obj f_origin(int c, obj *a) { (void)c; (void)a; return list2(mkfix(0), mkfix(0)); }

void init_stubs(void)
{
    static const struct { const char *n; int min, max, kind; } t[] = {
        {"CIRCLE", 3, 4, 0}, {"DISC", 3, 4, 0}, {"BOX", 4, 5, 0}, {"FILL-BOX", 4, 5, 0},
        {"FORWARD", 1, 1, 0}, {"BACK", 1, 1, 0}, {"RIGHT", 1, 1, 0}, {"LEFT", 1, 1, 0},
        {"SET-HEADING", 1, 1, 0}, {"HEADING", 0, 0, 1}, {"PEN-UP", 0, 0, 0},
        {"PEN-DOWN", 0, 0, 0}, {"HOME", 0, 0, 0}, {"SET-POSITION", 2, 2, 0},
        {"TURTLE-POSITION", 0, 0, 3}, {"CLS", 0, 0, 0}, {"MODE", 1, 1, 0},
        {"LOCATE", 2, 2, 0}, {"PEN", 1, 1, 0}, {"PAPER", 1, 1, 0}, {"INK", 2, 3, 0},
        {"BORDER", 1, 2, 0}, {"RESET", 0, 0, 0}, {"PLOT", 2, 3, 0}, {"PLOTR", 2, 3, 0},
        {"DRAW", 2, 3, 0}, {"DRAWR", 2, 3, 0}, {"MOVE", 2, 3, 0}, {"MOVER", 2, 3, 0},
        {"TEST", 2, 2, 1}, {"TESTR", 2, 2, 1}, {"ORIGIN", 2, 2, 0}, {"CLG", 0, 1, 0},
        {"GRAPHICS-PEN", 1, 1, 0}, {"GRAPHICS-PAPER", 1, 1, 0}, {"XPOS", 0, 0, 1},
        {"YPOS", 0, 0, 1}, {"SOUND", 2, 7, 0}, {"INKEY", 0, 0, 0}, {"WAIT-KEY", 0, 0, 0},
        {"KEY-DOWN-P", 1, 1, 0}, {"FRAME", 0, 0, 0}, {"SAY", 1, 1, 0},
        {"SPEECH-STOP", 0, 0, 0}, {"SPEECH-VOICE", 1, 1, 0}, {"SPEECH-RATE", 1, 1, 0},
        {"SPEECH-VOLUME", 1, 1, 0}, {"MIDI-OUT", 0, ANY, 0}, {"MIDI-OFF", 0, 0, 0},
        {"BASIC", 0, 1, 0}, {"PLAYCITY", 1, 1, 0}, {"PC-TONE", 2, 3, 0}, {"PC-OFF", 0, 0, 0},
        {"ED", 0, 1, 0}, {"SYMBOL", 1, 9, 0}, {"FLOOD-FILL", 2, 3, 0}, {"INK-MODE", 1, 1, 0},
        {"WINDOW", 4, 4, 0}, {"TAG", 1, 1, 0}, {"TRANSPARENT", 1, 1, 0},
        {"FLASH-SPEED", 2, 2, 0}, {"TEXT-CURSOR", 0, 0, 0}, {"JOYSTICK", 0, 1, 1},
        {"PEEK", 1, 1, 1}, {"POKE", 2, 2, 0}, {"ENVELOPE", 4, 16, 0},
        {"TONE-ENVELOPE", 4, 16, 0}, {"RELEASE", 1, 1, 0}, {"SOUND-CHECK", 1, 1, 2},
        {"SOUND-HOLD", 0, 0, 0}, {"SOUND-CONTINUE", 0, 0, 0}, {NULL, 0, 0, 0}};
    for (int i = 0; t[i].n; i++)
        defsubr(t[i].n, t[i].kind == 1 ? f_zero : t[i].kind == 2 ? f_four
                : t[i].kind == 3 ? f_origin : f_nil, t[i].min, t[i].max);
}
