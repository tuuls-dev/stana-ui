#ifndef STANA_ABI_H
#define STANA_ABI_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#define STN_ABI_VERSION 3
typedef struct { double x, y, width, height; } stn_rect;
typedef struct { double red, green, blue, alpha; } stn_color;
typedef struct { double width, height, baseline; } stn_text_metrics;
typedef void *stn_window;
typedef struct { const char *bytes; size_t length; } stn_utf8;
// Calls are main-thread-only unless documented otherwise. Strings are borrowed
// UTF-8 for the duration of the call; the adapter copies all retained data.
typedef struct {
    int32_t kind; // 1 resize, 2 down, 3 move, 4 up, 5 scroll, 6 key,
                  // 7 close, 8 AT activate, 9 AT focus, 10 appearance, 11 deactivate,
                  // 12/13 image resources, 14 modal, 15 surface focus
    double x, y, a, b;
    uint64_t identity;
    stn_utf8 text;
} stn_event;
typedef void (*stn_event_callback)(void *, const stn_event *);
typedef void (*stn_draw_callback)(void *);
// Text requests: 1 insert, 2 marked, 3 unmark, 4 command, 5 selection, 6 AT value.
// UINT64_MAX means the platform supplies no replacement range.
typedef void (*stn_text_callback)(void *, int32_t, stn_utf8, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
typedef void (*stn_command_callback)(void *, uint64_t);
typedef void (*stn_dialog_callback)(void *, const char *, int32_t);
typedef struct {
    uint64_t identity, parent;
    int32_t role; // 0 window, 1 group, 2 heading, 3 text, 4 button,
                  // 5 checkbox, 6 field, 7 image, 8 scroll area
    stn_utf8 label, hint, value;
    stn_rect bounds;
    bool disabled, focused, offscreen, secure, read_only;
    int32_t heading;
} stn_semantic_node;
#endif
