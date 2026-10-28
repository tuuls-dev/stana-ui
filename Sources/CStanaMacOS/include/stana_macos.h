#ifndef STANA_MACOS_H
#define STANA_MACOS_H
#include "stana_abi.h"
#include "stana_window.h"
#ifdef __cplusplus
extern "C" {
#endif
uint32_t stn_abi_version(void);
void stn_app_initialize(void);
void stn_app_run(void);
void stn_app_stop(void);
stn_window stn_window_create(stn_utf8, double, double, void *, stn_event_callback, stn_draw_callback,
                             stn_text_callback);
void stn_window_show(stn_window);
void stn_window_redraw(stn_window);
void stn_window_title(stn_window, stn_utf8);
void stn_window_destroy(stn_window);
void stn_window_focus_text(stn_window, bool);
void stn_window_discard_marked(stn_window);
void stn_window_text_options(stn_window, uint64_t, bool, bool, bool, const int32_t *, size_t);
bool stn_text_service_enabled(int32_t, int32_t);
double stn_caret_interval(bool);
size_t stn_text_selection_rects(stn_utf8, double, double, uint64_t, uint64_t, stn_rect *, size_t);
void stn_window_text_state(stn_window, stn_utf8, uint64_t, uint64_t, uint64_t, uint64_t, stn_rect, const double *,
                           size_t, uint64_t, bool);
void stn_window_text_geometry(stn_window, uint64_t, stn_utf8, uint64_t, uint64_t, uint64_t, uint64_t, stn_rect,
                              const double *, size_t, uint64_t, bool, stn_affine, bool, uint64_t);
void stn_window_publish_semantics(stn_window, uint64_t, const stn_semantic_node *, size_t);
void stn_window_semantic_text(stn_window, uint64_t, stn_utf8, uint64_t, uint64_t, stn_rect, const double *, size_t,
                              uint64_t, bool);
// Graphics retain an offscreen sRGB backing store. Every present supplies its
// complete image to AppKit; incremental drawing never relies on window pixels.
bool stn_frame_begin(stn_window, double, double, const stn_rect *, size_t, bool);
void stn_draw_fill(stn_window, stn_rect, stn_color, double);
void stn_draw_stroke(stn_window, stn_rect, stn_color, double, double);
void stn_draw_text(stn_window, stn_utf8, stn_rect, double, double, stn_color, bool);
void stn_draw_image(stn_window, const uint8_t *, size_t, stn_rect);
void stn_draw_clip_push(stn_window, stn_rect);
void stn_draw_clip_pop(stn_window);
void stn_draw_opacity_push(stn_window, double);
void stn_draw_opacity_pop(stn_window);
void stn_draw_transform_push(stn_window, double, double, double, double, double, double);
void stn_draw_rounded_clip_push(stn_window, stn_rect, double);
void stn_frame_end(stn_window);
// Asynchronous hybrid rendering. Payload bytes are copied before returning.
bool stn_metal_initialize(stn_window);
bool stn_metal_submit(stn_window, const uint8_t *, size_t);
void stn_metal_invalidate(stn_window);
void stn_metal_detach(stn_window);
void stn_metal_animation(stn_window, bool);
void stn_metal_pause_observations(stn_window, bool);
void stn_metal_retry(stn_window, uint64_t);
// Owned JSON diagnostics; release using stn_string_free.
char *stn_metal_copy_diagnostics(stn_window);
typedef void (*stn_json_callback)(void *, stn_utf8);
void stn_metal_diagnostics(stn_window, void *, stn_json_callback);
void stn_metal_ui_timing(stn_window, uint64_t, double, double);
bool stn_metal_export(stn_window, const char *, bool);
typedef void (*stn_readback_callback)(void *, const uint8_t *, size_t, size_t, size_t, bool, uint64_t, stn_utf8);
// Completes once on the main thread. Bytes/error text are borrowed during callback.
void stn_metal_readback(stn_window, void *, stn_readback_callback);
// Per-host probes: 0 adaptive, 1 persistent, 2 direct, 3 full-final, 4 untiled/full.
void stn_metal_test_configuration(stn_window, int32_t, double, bool);
// Text functions are pure and may be used without creating NSApplication.
stn_text_metrics stn_text_measure(stn_utf8, double, double, double, bool);
double stn_text_offset(stn_utf8, double, double, uint64_t);
void stn_text_offsets(stn_utf8, double, double, double *, size_t);
uint64_t stn_text_index(stn_utf8, double, double, double);
void stn_clipboard_write(stn_utf8);
// Returned string is owned by caller and released with stn_string_free.
char *stn_clipboard_copy(size_t *);
void stn_string_free(char *);
void stn_menu_reset(void *, stn_command_callback);
uint64_t stn_menu_add(uint64_t, stn_utf8, uint64_t, stn_utf8, uint32_t, bool, bool);
void stn_menu_update(uint64_t, stn_utf8, bool, bool);
// Dialog callback executes once on the main thread. status: 0 success, 1 cancel.
// Path strings are borrowed UTF-8; no native UI pointer crosses the ABI.
void stn_file_dialog(stn_window, bool, stn_utf8, void *, stn_dialog_callback);
void stn_alert(stn_window, stn_utf8, stn_utf8, void *, stn_dialog_callback);
// Test-only diagnostics.
bool stn_window_test_text_action(stn_window, stn_utf8, bool);
bool stn_window_test_checked_replace(stn_window, stn_utf8, uint64_t, uint64_t, uint64_t, uint64_t);
// Test-only diagnostics. No user text is returned.
size_t stn_window_semantic_count(stn_window);
uint64_t stn_window_semantic_revision(stn_window);
uint64_t stn_window_pixel_hash(stn_window);
bool stn_window_export_png(stn_window, const char *);
bool stn_window_test_key_equivalent(stn_window, stn_utf8);
#ifdef __cplusplus
}
#endif
#endif
