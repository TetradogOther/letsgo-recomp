// The look and the settings pages shared by the start screen (runtime/ui/launcher_lg.mm) and the F12 menu
// (runtime/ui/menu.mm), so both look and work alike: the same colours and fonts, and the same rows for the graphics,
// the image and sound, and the advanced settings. Each screen has its own Dear ImGui context; these act on the
// current one. The pages edit g_settings directly (in game they apply at once); the caller saves them.
#pragma once
#include "imgui.h"

// The language: 0 English, 1 Portuguese, 2 Russian (LARECOMP_LANG=en|pt|ru, else the system's)
extern int g_ui_lang;
void ui_pick_language(void);
#define UI_T(en, pt, ru) (g_ui_lang == 2 ? (ru) : g_ui_lang == 1 ? (pt) : (en))

// Fonts into the current context's atlas, built for a 1080 px tall window (ui_scale scales them): Segoe UI for the
// text (Latin-1 and Cyrillic) at 34 px, a bigger one, and Baloo 2 for titles at 50 (no Cyrillic: Segoe UI for Russian).
struct UiFonts { ImFont *body, *big, *title; };
UiFonts ui_load_fonts(void);
void ui_style(void);  // the colours, rounding and spacing (for 1080 px)
// The window's height over 1080 as the scale of the fonts and of the style's sizes (from the unscaled style, kept here)
struct UiScaler { ImGuiStyle base; float scale = -1; };
float ui_scale(UiScaler &s, float window_h);

extern const ImVec4 UI_GOLD, UI_GREEN_TEXT, UI_RED_TEXT;
void ui_title(ImFont *title, const char *text);  // a screen's title, gold
void ui_heading(const char *text);               // a group's heading inside a page, gold
// A label and the control beside it (the next widget fills the rest of the line), the controls lined up at x
float ui_label_x(const char *const *labels, int n);
void ui_row(const char *label, float x);
// A tab bar's tab that L1 / R1 on a controller also selects: ui_tabs_begin once per frame before the tabs with how many
// there are, then ui_tab for each.
void ui_tabs_begin(int *current, int count);
bool ui_tab(const char *label, int index, int *current);
void ui_tab_select(int index);  // that tab at the next frame (a test's or a screen's first)

// The pages. known: the game's build has the address tables the frame rate modes hook (runtime/fnhook.c).
// ui_graphics_x: the column for the graphics page's rows plus the caller's own (extra labels) drawn above it.
float ui_graphics_x(const char *const *extra, int n_extra);
void ui_page_graphics(float x, bool known);
void ui_page_image_sound(void);
void ui_page_advanced(void);
