#ifndef STANA_WINDOW_H
#define STANA_WINDOW_H
#include "stana_abi.h"
#ifdef __cplusplus
extern "C" {
#endif
// Preferences: 0 automatic, 1 enabled, 2 disabled. All values are Stana-owned.
typedef struct {
	int32_t frame, role, appearance, shadow;
	double opacity;
	bool automatic_level, has_minimized_title, has_tab_title, has_tab_tooltip, frame_aspect, frame_increments;
	stn_color background;
	int32_t title_visibility, title_transparent, full_size_content, separator;
	int32_t close_visibility, close_enabled, minimize_visibility, minimize_enabled, zoom_visibility, zoom_enabled;
	bool resizable, can_close, can_minimize, movable, background_dragging, ignores_mouse, mouse_moved;
	int32_t can_key, can_main, key_only_if_needed, inactive_tooltips;
	int32_t hides_on_deactivate, can_hide, floating_panel, works_when_modal, prevents_termination;
	bool excluded_from_menu, visible_without_login;
	int32_t level, animation, spaces, management, application_membership, cycle, fullscreen, tiling, tabbing;
	int32_t preserves_content;
	stn_rect min_content, max_content, min_frame, max_frame, aspect, increments, min_fullscreen, max_fullscreen;
	bool has_content_border;
	stn_rect content_border; // x leading, y top, width trailing, height bottom
	stn_utf8 subtitle, represented_url, minimized_title, dock_badge, tabbing_identifier, tab_title, tab_tooltip;
	bool document_edited;
	const uint8_t *minimized_image;
	size_t minimized_image_length;
} stn_window_config;
typedef struct {
	bool visible, key, main, minimized, zoomed, fullscreen, live_resize, active_space, occluded, has_sheet, is_sheet;
	bool has_sharing;
	int32_t fullscreen_transition;
	stn_rect frame, content, safe_content;
	double scale;
	uint64_t identity, parent, selected_tab;
	bool tab_bar_visible, tab_overview_visible;
	const uint64_t *children, *tabs;
	size_t child_count, tab_count;
	stn_utf8 screen_id;
} stn_window_state;
typedef void (*stn_window_state_callback)(void *, const stn_window_state *);
// Pointer phase: 0 down, 1 move, 2 up, 3 side-effect-free keyboard-focus inquiry.
typedef int32_t (*stn_window_pointer_callback)(void *, int32_t, double, double, bool, int32_t, int32_t);
typedef bool (*stn_window_close_callback)(void *);
typedef void (*stn_window_idle_callback)(void *);
typedef void (*stn_window_operation_callback)(void *, uint64_t, int32_t, int32_t);
typedef struct {
	stn_window_state_callback state;
	stn_window_pointer_callback pointer;
	stn_window_close_callback should_close;
	stn_window_idle_callback idle;
	stn_window_operation_callback operation;
	stn_command_callback command;
} stn_window_callbacks;
// Operation status: 0 success, 1 unsupported, 2 invalid state, 3 native failure, 4 cancelled.
stn_window stn_window_create_role(stn_utf8, double, double, int32_t, void *, stn_event_callback, stn_draw_callback,
                                  stn_text_callback);
stn_window stn_window_create_host(stn_utf8, double, double, int32_t, stn_window, void *, stn_event_callback,
                                  stn_draw_callback, stn_text_callback);
void stn_window_set_callbacks(stn_window, stn_window_callbacks);
void stn_window_publish_state(stn_window);
int32_t stn_window_validate_config(stn_window, const stn_window_config *);
void stn_window_apply(stn_window, const stn_window_config *);
bool stn_window_busy(stn_window);
int32_t stn_window_action(stn_window, int32_t);
int32_t stn_window_fullscreen(stn_window, bool, uint64_t);
int32_t stn_window_set_frame(stn_window, stn_rect, bool);
int32_t stn_window_set_content_size(stn_window, double, double);
int32_t stn_window_relate(stn_window, stn_window, int32_t);
int32_t stn_window_begin_sheet(stn_window, stn_window, bool, uint64_t);
int32_t stn_window_end_sheet(stn_window, int32_t);
int32_t stn_window_share(stn_window, stn_window, uint64_t);
void stn_window_place(stn_window, stn_utf8, stn_utf8, stn_utf8, bool, double, double);
void stn_window_erase_saved_frame(stn_utf8);
int32_t stn_window_manage_frame(stn_window, stn_utf8, bool, bool *);
typedef struct {
	stn_utf8 identifier, name;
	stn_rect frame, visible_frame;
	double scale;
} stn_screen;
typedef void (*stn_screen_callback)(void *, const stn_screen *);
void stn_screens(void *, stn_screen_callback);
typedef struct stn_toolbar_item {
	stn_utf8 identifier, title, tooltip;
	int32_t kind, priority;
	uint64_t command;
	bool enabled, checked;
	const uint8_t *image;
	size_t image_length;
	const struct stn_toolbar_item *children;
	size_t child_count;
	stn_window surface;
} stn_toolbar_item;
int32_t stn_window_toolbar(stn_window, stn_utf8, const stn_toolbar_item *, size_t, const stn_utf8 *, size_t, bool, bool,
                           bool, bool, int32_t, int32_t);
void stn_window_toolbar_update(stn_window, uint64_t, stn_utf8, bool, bool);
typedef struct {
	stn_utf8 identifier;
	int32_t placement;
	double fullscreen_minimum_height;
	bool hidden;
	stn_window surface;
} stn_window_accessory;
int32_t stn_window_tab_accessory(stn_window, stn_window);
int32_t stn_window_accessories(stn_window, const stn_window_accessory *, size_t);
// Test-only native facts: style, role, opaque, standard buttons, limits.
uint64_t stn_window_test_style(stn_window);
bool stn_window_test_marked_text(stn_window, stn_utf8, bool);
double stn_window_test_property(stn_window, int32_t);
#ifdef __cplusplus
}
#endif
#endif
