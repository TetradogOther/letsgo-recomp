// In-game overlay (Dear ImGui on the Vulkan renderer; input fed from SDL events): the "close the game?" question
// (Esc, F1 or Minus + Plus on a controller), the F12 settings (tabs: graphics, image and sound, advanced - the same
// pages as the start screen's, runtime/ui/settings_ui.mm), the name entry the game asks for (runtime/hle/swkbd.c), the
// FPS counter and the controller's finger on the touch screen (runtime/hle/input.c).
// LARECOMP_MENU_KEY=<SDL scancode name> ("F10", "Insert"...): another key for the F12 settings (Steam takes F12 for
// screenshots by default).
//
// Threads: SDL events arrive on the main thread and are queued; the overlay is laid out and drawn on the render
// thread inside backend_present, after the game image, into the same window image.
#include <SDL3/SDL.h>
#include <math.h>
#include <pthread.h>
#include <atomic>
#include <vector>

#include "imgui.h"
#include "imgui_impl_vulkan.h"
#include "osk.h"
#include "settings_ui.h"
extern "C" bool vk_imgui_backend_init(void);  // runtime/nvn/vulkan/imgui_glue.cpp

extern "C" {
#include "../hle.h"
#include "../settings.h"
#include "menu.h"
#include "../paths.h"
void input_reset(void);
uint64_t rt_addr(uint64_t eevee);  // runtime/fnhook.c (0: a build without the tables the frame rate modes need)
bool input_finger_cursor(float *x, float *y, bool *down);  // runtime/hle/input.c
}

// ------------------------------------------------------------------ language
// English, Portuguese or Russian (issue #1), from the system's language (runtime/ui/settings_ui.h)
#define M UI_T

// ------------------------------------------------------------------ state shared with the main thread
static std::atomic<bool> g_open{false};  // the "close the game?" question is up
static std::atomic<bool> g_cfg{false};   // the F12 settings are up
static int g_cfg_tab;                    // the F12 settings' tab: graphics, image and sound, advanced (render thread)
static std::atomic<bool> g_want_fullscreen_apply{false};

struct QEvent {
    enum { KEY, ANALOG, MOUSE_POS, MOUSE_BUTTON, WHEEL, TEXT } kind;
    ImGuiKey key;
    bool down;
    float value, x, y;
    int button;
    char text[32];
};
static pthread_mutex_t q_lock = PTHREAD_MUTEX_INITIALIZER;
static std::vector<QEvent> q_events;
static float g_pixel_density = 1;

static void push(const QEvent &e) {
    pthread_mutex_lock(&q_lock);
    q_events.push_back(e);
    pthread_mutex_unlock(&q_lock);
}

bool menu_is_open(void) { return g_open.load(); }
static void set_open(bool open) {
    if (open == g_open.load()) return;
    g_open.store(open);
    input_reset();  // nothing held while the question had focus leaks into the game
    if (!open) settings_save();
}
static void set_cfg(bool open) {
    if (open == g_cfg.load()) return;
    if (open) set_open(false);
    g_cfg.store(open);
    input_reset();
    if (!open) settings_save();
}
// (LARECOMP_MENU_AT: runtime/nvn/vulkan/device.c; LARECOMP_MENU_PAGE=cfg / adv / <tab number>: the F12 settings on that
// tab instead - cfg the first, adv the advanced one)
extern "C" void menu_test_open(void) {
    const char *pg = getenv("LARECOMP_MENU_PAGE");
    if (!pg) { set_open(true); return; }
    g_cfg_tab = !strcmp(pg, "adv") ? 2 : atoi(pg);
    ui_tab_select(g_cfg_tab);
    set_cfg(true);
}

static ImGuiKey key_from_scancode(SDL_Scancode sc) {
    switch (sc) {
    case SDL_SCANCODE_UP: return ImGuiKey_UpArrow;
    case SDL_SCANCODE_DOWN: return ImGuiKey_DownArrow;
    case SDL_SCANCODE_LEFT: return ImGuiKey_LeftArrow;
    case SDL_SCANCODE_RIGHT: return ImGuiKey_RightArrow;
    case SDL_SCANCODE_RETURN: return ImGuiKey_Enter;
    case SDL_SCANCODE_KP_ENTER: return ImGuiKey_KeypadEnter;
    case SDL_SCANCODE_SPACE: return ImGuiKey_Space;
    case SDL_SCANCODE_TAB: return ImGuiKey_Tab;
    case SDL_SCANCODE_BACKSPACE: return ImGuiKey_Backspace;
    case SDL_SCANCODE_DELETE: return ImGuiKey_Delete;
    case SDL_SCANCODE_HOME: return ImGuiKey_Home;
    case SDL_SCANCODE_END: return ImGuiKey_End;
    case SDL_SCANCODE_LSHIFT: return ImGuiKey_LeftShift;
    case SDL_SCANCODE_RSHIFT: return ImGuiKey_RightShift;
    case SDL_SCANCODE_LCTRL: return ImGuiKey_LeftCtrl;
    case SDL_SCANCODE_RCTRL: return ImGuiKey_RightCtrl;
    case SDL_SCANCODE_A: return ImGuiKey_A;
    case SDL_SCANCODE_C: return ImGuiKey_C;
    case SDL_SCANCODE_V: return ImGuiKey_V;
    case SDL_SCANCODE_X: return ImGuiKey_X;
    case SDL_SCANCODE_Z: return ImGuiKey_Z;
    default: return ImGuiKey_None;
    }
}

// Nintendo layout: the right face button (A) confirms, the bottom one (B) goes back.
static ImGuiKey key_from_pad(Uint8 b) {
    switch (b) {
    case SDL_GAMEPAD_BUTTON_EAST: return ImGuiKey_GamepadFaceDown;   // activate
    case SDL_GAMEPAD_BUTTON_SOUTH: return ImGuiKey_GamepadFaceRight; // cancel / back
    case SDL_GAMEPAD_BUTTON_NORTH: return ImGuiKey_GamepadFaceUp;
    case SDL_GAMEPAD_BUTTON_WEST: return ImGuiKey_GamepadFaceLeft;
    case SDL_GAMEPAD_BUTTON_DPAD_UP: return ImGuiKey_GamepadDpadUp;
    case SDL_GAMEPAD_BUTTON_DPAD_DOWN: return ImGuiKey_GamepadDpadDown;
    case SDL_GAMEPAD_BUTTON_DPAD_LEFT: return ImGuiKey_GamepadDpadLeft;
    case SDL_GAMEPAD_BUTTON_DPAD_RIGHT: return ImGuiKey_GamepadDpadRight;
    case SDL_GAMEPAD_BUTTON_LEFT_SHOULDER: return ImGuiKey_GamepadL1;
    case SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER: return ImGuiKey_GamepadR1;
    case SDL_GAMEPAD_BUTTON_START: return ImGuiKey_GamepadStart;
    case SDL_GAMEPAD_BUTTON_BACK: return ImGuiKey_GamepadBack;
    default: return ImGuiKey_None;
    }
}

// ---- software keyboard (runtime/hle/swkbd.c: the game's name entry) ------------------------------------------
// The game thread waits in menu_keyboard_run (re-presenting the last frame); this dialog takes the text: typed
// directly when the player last used a keyboard, an on-screen keyboard (d-pad + A, B deletes, Start / + OK) when
// they last used a controller.
static std::atomic<int> g_kbd{0};  // 1 open, 2 confirmed, 3 cancelled
static std::atomic<bool> g_last_pad{false};
static char g_kbd_text[96];
static int g_kbd_max = 8;
static bool capturing() { return g_open.load() || g_cfg.load() || g_kbd.load() == 1; }
// The game gets no input while this is true (runtime/hle/input.c): the question, the settings or the name entry is up.
extern "C" bool menu_input_captured(void) { return capturing(); }

static SDL_Scancode cfg_key(void) {
    static SDL_Scancode k = SDL_SCANCODE_UNKNOWN;
    if (k == SDL_SCANCODE_UNKNOWN) {
        const char *e = getenv("LARECOMP_MENU_KEY");
        k = e && *e ? SDL_GetScancodeFromName(e) : SDL_SCANCODE_UNKNOWN;
        if (k == SDL_SCANCODE_UNKNOWN) k = SDL_SCANCODE_F12;
    }
    return k;
}

bool menu_handle_event(const SDL_Event *e) {
    static bool back_down, start_down;
    if (e->type == SDL_EVENT_KEY_DOWN) g_last_pad = false;
    if (e->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN) g_last_pad = true;
    bool typing = g_kbd.load() == 1;  // (the name entry: keys are text, not shortcuts)
    if (typing && e->type == SDL_EVENT_KEY_DOWN && !e->key.repeat) {  // Enter confirms, Esc cancels
        if (e->key.scancode == SDL_SCANCODE_RETURN || e->key.scancode == SDL_SCANCODE_KP_ENTER) { g_kbd = 2; return true; }
        if (e->key.scancode == SDL_SCANCODE_ESCAPE) { g_kbd = 3; return true; }
    }
    if (typing && e->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN && e->gbutton.button == SDL_GAMEPAD_BUTTON_START) {
        g_kbd = 2;
        return true;
    }
    switch (e->type) {
    case SDL_EVENT_KEY_DOWN:
        if (!e->key.repeat && !typing && (e->key.scancode == cfg_key() || (e->key.scancode == SDL_SCANCODE_ESCAPE && g_cfg.load()))) {
            set_cfg(e->key.scancode == SDL_SCANCODE_ESCAPE ? false : !g_cfg.load());  // (Esc closes the settings)
            return true;
        }
        if (!e->key.repeat && (e->key.scancode == SDL_SCANCODE_F1 ||
                               (e->key.scancode == SDL_SCANCODE_ESCAPE && !g_open.load()))) {
            if (!typing) { set_cfg(false); set_open(!g_open.load()); }  // (Esc with the question up goes to it below: "Não")
            return true;
        }
        if (!e->key.repeat && (e->key.scancode == SDL_SCANCODE_F11 ||
                               (e->key.scancode == SDL_SCANCODE_RETURN && (e->key.mod & (SDL_KMOD_ALT | SDL_KMOD_GUI))))) {
            g_settings.fullscreen = !g_settings.fullscreen;
            g_want_fullscreen_apply.store(true);
            settings_save();
            return true;
        }
        /* fallthrough */
    case SDL_EVENT_KEY_UP: {
        if (!capturing()) return false;
        bool down = e->type == SDL_EVENT_KEY_DOWN;
        if (down && e->key.scancode == SDL_SCANCODE_ESCAPE) {
            QEvent q = {};
            q.kind = QEvent::KEY; q.key = ImGuiKey_Escape; q.down = true; push(q);
            q.down = false; push(q);
            return true;
        }
        ImGuiKey k = key_from_scancode(e->key.scancode);
        if (k != ImGuiKey_None) { QEvent q = {}; q.kind = QEvent::KEY; q.key = k; q.down = down; push(q); }
        return true;
    }
    case SDL_EVENT_TEXT_INPUT:
        if (!capturing()) return false;
        { QEvent q = {}; q.kind = QEvent::TEXT; strlcpy(q.text, e->text.text, sizeof q.text); push(q); }
        return true;
    case SDL_EVENT_GAMEPAD_BUTTON_DOWN: case SDL_EVENT_GAMEPAD_BUTTON_UP: {
        bool down = e->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN;
        if (e->gbutton.button == SDL_GAMEPAD_BUTTON_BACK) back_down = down;
        if (e->gbutton.button == SDL_GAMEPAD_BUTTON_START) start_down = down;
        if (down && !typing && ((back_down && start_down) || e->gbutton.button == SDL_GAMEPAD_BUTTON_GUIDE)) {
            set_cfg(false);
            set_open(!g_open.load());
            return true;
        }
        if (!capturing()) return false;
        ImGuiKey k = key_from_pad(e->gbutton.button);
        if (k != ImGuiKey_None) { QEvent q = {}; q.kind = QEvent::KEY; q.key = k; q.down = down; push(q); }
        return true;
    }
    case SDL_EVENT_GAMEPAD_AXIS_MOTION: {
        if (!capturing()) return false;
        float v = e->gaxis.value / 32767.0f;
        QEvent q = {};
        q.kind = QEvent::ANALOG;
        switch (e->gaxis.axis) {
        case SDL_GAMEPAD_AXIS_LEFTX:
            q.key = ImGuiKey_GamepadLStickLeft; q.value = v < -0.3f ? -v : 0; push(q);
            q.key = ImGuiKey_GamepadLStickRight; q.value = v > 0.3f ? v : 0; push(q);
            break;
        case SDL_GAMEPAD_AXIS_LEFTY:
            q.key = ImGuiKey_GamepadLStickUp; q.value = v < -0.3f ? -v : 0; push(q);
            q.key = ImGuiKey_GamepadLStickDown; q.value = v > 0.3f ? v : 0; push(q);
            break;
        default: break;
        }
        return true;
    }
    case SDL_EVENT_MOUSE_MOTION:
        if (!capturing()) return false;
        { QEvent q = {}; q.kind = QEvent::MOUSE_POS; q.x = e->motion.x * g_pixel_density; q.y = e->motion.y * g_pixel_density; push(q); }
        return true;
    case SDL_EVENT_MOUSE_BUTTON_DOWN: case SDL_EVENT_MOUSE_BUTTON_UP:
        if (!capturing()) return false;
        {
            QEvent q = {};
            q.kind = QEvent::MOUSE_BUTTON;
            q.button = e->button.button == SDL_BUTTON_LEFT ? 0 : e->button.button == SDL_BUTTON_RIGHT ? 1 : 2;
            q.down = e->type == SDL_EVENT_MOUSE_BUTTON_DOWN;
            push(q);
        }
        return true;
    case SDL_EVENT_MOUSE_WHEEL:
        if (!capturing()) return false;
        { QEvent q = {}; q.kind = QEvent::WHEEL; q.x = e->wheel.x; q.y = e->wheel.y; push(q); }
        return true;
    default:
        return false;
    }
}

void menu_apply_window_requests(void *win) {
    SDL_Window *w = (SDL_Window *)win;
    g_pixel_density = SDL_GetWindowPixelDensity(w);
    static bool text_input;
    bool want_text = capturing();
    if (want_text != text_input) {
        if (want_text) SDL_StartTextInput(w);
        else SDL_StopTextInput(w);
        text_input = want_text;
    }
    static bool first = true;
    if (first || g_want_fullscreen_apply.exchange(false)) {
        first = false;
        SDL_SetWindowFullscreen(w, g_settings.fullscreen);
    }
}

// ------------------------------------------------------------------ render thread
static bool g_inited;
static ImGuiContext *g_ctx;  // ours: the start screen has its own context
static ImFont *g_font, *g_font_big;  // the FPS counter and the name entry
static ImFont *g_menu_font;          // the "close the game?" question (Baloo 2, as on the start screen)

static void init(void) {
    IMGUI_CHECKVERSION();
    ui_pick_language();
    g_ctx = ImGui::CreateContext();
    ImGui::SetCurrentContext(g_ctx);
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard | ImGuiConfigFlags_NavEnableGamepad;
    io.BackendFlags |= ImGuiBackendFlags_HasGamepad;
    io.IniFilename = NULL;
    UiFonts f = ui_load_fonts();
    g_font = f.body, g_font_big = f.big, g_menu_font = f.title;
    ui_style();
    vk_imgui_backend_init();
    g_inited = true;
}

static void drain_events(ImGuiIO &io) {
    pthread_mutex_lock(&q_lock);
    std::vector<QEvent> ev;
    ev.swap(q_events);
    pthread_mutex_unlock(&q_lock);
    for (const QEvent &q : ev) {
        switch (q.kind) {
        case QEvent::KEY: io.AddKeyEvent(q.key, q.down); break;
        case QEvent::ANALOG: io.AddKeyAnalogEvent(q.key, q.value > 0.1f, q.value); break;
        case QEvent::MOUSE_POS: io.AddMousePosEvent(q.x, q.y); break;
        case QEvent::MOUSE_BUTTON: io.AddMouseButtonEvent(q.button, q.down); break;
        case QEvent::WHEEL: io.AddMouseWheelEvent(q.x, q.y); break;
        case QEvent::TEXT: io.AddInputCharactersUTF8(q.text); break;
        }
    }
}

// Reboot (runtime/main.c): the game is gone - the question and the name entry close; the ImGui context stays.
RT_ON_RESET(menu_reset) {
    set_open(false);
    set_cfg(false);
    g_kbd = 0;
    osk_cancel();
    pthread_mutex_lock(&q_lock);
    q_events.clear();
    pthread_mutex_unlock(&q_lock);
}

static void keyboard_draw(ImGuiIO &io, float scale) {
    ImGui::GetBackgroundDrawList()->AddRectFilled(ImVec2(0, 0), io.DisplaySize, IM_COL32(0, 0, 0, 120));
    float w = fminf(io.DisplaySize.x * 0.9f, 1100 * scale);
    ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(w, 0), ImGuiCond_Always);
    ImGui::Begin("##kbd", NULL, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings |
                                    ImGuiWindowFlags_AlwaysAutoResize);
    ImGui::PushFont(g_font_big);
    ImGui::TextColored(ImVec4(0.93f, 0.76f, 0.33f, 1), "%s", M("Enter a name", "Digite o nome", "Введите имя"));
    ImGui::PopFont();
    static bool was_open, was_pad;
    bool pad = g_last_pad.load(), appearing = !was_open || pad != was_pad;  // (switching device: focus the new one)
    was_open = true, was_pad = pad;
    if (!pad) {  // keyboard: type straight into the field
        if (appearing) ImGui::SetKeyboardFocusHere();
        ImGui::SetNextItemWidth(-1);
        ImGui::PushFont(g_font_big);
        ImGui::InputText("##name", g_kbd_text, (size_t)(g_kbd_max * 4 + 1 < (int)sizeof g_kbd_text ? g_kbd_max * 4 + 1 : sizeof g_kbd_text),
                         ImGuiInputTextFlags_CallbackCharFilter,
                         [](ImGuiInputTextCallbackData *d) -> int { return d->EventChar < 0x20 ? 1 : 0; });
        ImGui::PopFont();
        if ((int)strlen(g_kbd_text) > g_kbd_max) g_kbd_text[g_kbd_max] = 0;
        ImGui::TextDisabled("%s      (%d / %d)", M("Enter  confirms      Esc  cancels", "Enter  confirma      Esc  cancela",
                                                   "Enter  готово      Esc  отмена"),
                            (int)strlen(g_kbd_text), g_kbd_max);
    } else {  // controller: on-screen keyboard (osk.mm)
        int r = osk_keys(g_kbd_text, sizeof g_kbd_text, g_kbd_max, appearing, scale, g_font_big);
        if (r) g_kbd = r > 0 ? 2 : 3;  // (Start / + confirms in menu_handle_event too)
    }
    ImGui::End();
    if (g_kbd.load() != 1) was_open = false;
}

// Game thread (runtime/hle/swkbd.c): show the dialog, re-present the last frame until it's answered.
// Returns 1 confirmed (out = text, UTF-8), 0 cancelled.
extern "C" int menu_keyboard_run(const char *initial, int max_len, char *out, int cap) {
    extern void backend_represent(void);
    snprintf(g_kbd_text, sizeof g_kbd_text, "%s", initial ? initial : "");
    g_kbd_max = max_len > 0 && max_len < (int)sizeof g_kbd_text / 4 ? max_len : 8;
    input_reset();
    g_kbd = 1;
    // (test) LARECOMP_KBD_AUTO=<text>: answer at once
    if (getenv("LARECOMP_KBD_AUTO")) { snprintf(g_kbd_text, sizeof g_kbd_text, "%s", getenv("LARECOMP_KBD_AUTO")); g_kbd = 2; }
    while (g_kbd.load() == 1 && !g_rt_unwind) {  // ~60 Hz (a reboot cancels)
        uint64_t t0 = SDL_GetTicks();
        backend_represent();
        uint64_t dt = SDL_GetTicks() - t0;
        if (dt < 16) SDL_Delay((uint32_t)(16 - dt));
    }
    bool ok = g_kbd.load() == 2 && g_kbd_text[0];
    if (ok) snprintf(out, cap, "%s", g_kbd_text);
    g_kbd = 0;
    input_reset();
    return ok;
}

// "Close the game?" - Não has the focus first (Enter / A by reflex keeps playing); B / Esc answer Não.
static void quit_draw(ImGuiIO &io, float scale) {
    ImGui::GetBackgroundDrawList()->AddRectFilled(ImVec2(0, 0), io.DisplaySize, IM_COL32(0, 0, 0, 110));
    ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::Begin("##quit", NULL, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings |
                                     ImGuiWindowFlags_AlwaysAutoResize);
    ImGui::PushFont(g_menu_font);  // (Baloo 2; Segoe UI for Russian: ui_load_fonts)
    ImGui::TextUnformatted(M("Close the game?", "Deseja fechar o jogo?", "Закрыть игру?"));
    ImGui::TextDisabled("%s", M("Progress since the last save will be lost.", "O progresso desde o último save será perdido.",
                                "Прогресс после последнего сохранения будет потерян."));
    ImGui::Spacing();
    float bw = 220 * scale;
    static bool focus_no;
    if (!focus_no) { ImGui::SetKeyboardFocusHere(1); focus_no = true; }
    if (ImGui::Button(M("Yes", "Sim", "Да"), ImVec2(bw, 0))) {
        settings_save();
        SDL_Event q = {};
        q.type = SDL_EVENT_QUIT;
        SDL_PushEvent(&q);
    }
    ImGui::SameLine();
    bool no = ImGui::Button(M("No", "Não", "Нет"), ImVec2(bw, 0));
    if (ImGui::Button(M("Settings (F12)", "Configurações (F12)", "Настройки (F12)"), ImVec2(bw * 2 + ImGui::GetStyle().ItemSpacing.x, 0))) {
        focus_no = false;
        set_cfg(true);  // (closes the question: the way in from a controller)
    } else if (no || ImGui::IsKeyPressed(ImGuiKey_GamepadFaceRight, false) || ImGui::IsKeyPressed(ImGuiKey_Escape, false)) {
        set_open(false);
        focus_no = false;
    }
    ImGui::PopFont();
    ImGui::End();
}

// F12: the settings, applied live (runtime/ui/settings_ui.mm: the start screen's pages); saved to larecomp.ini on closing.
// B / Esc / F12 close; L / R on a controller change the tab.
static void cfg_draw(ImGuiIO &io, float scale) {
    ImGui::GetBackgroundDrawList()->AddRectFilled(ImVec2(0, 0), io.DisplaySize, IM_COL32(0, 0, 0, 70));
    ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    // one size for every tab, as the start screen's window (a page taller than it scrolls; pad navigation follows)
    float ww = fminf(io.DisplaySize.x * 0.9f, 1000 * scale), wh = fminf(io.DisplaySize.y * 0.92f, 780 * scale);
    ImGui::SetNextWindowSize(ImVec2(ww, wh), ImGuiCond_Always);
    ImGui::Begin("##cfg", NULL, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
                                    ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoScrollbar);
    ui_title(g_menu_font, M("Settings", "Configurações", "Настройки"));
    bool known = rt_addr(0x70002f8bb0ull) != 0;
    float footer = ImGui::GetFrameHeight() + ImGui::GetStyle().ItemSpacing.y * 2 + ImGui::GetStyle().WindowPadding.y * 0.5f;
    ui_tabs_begin(&g_cfg_tab, 3);
    if (ImGui::BeginTabBar("##cfg_tabs")) {
        const char *names[] = {M("Graphics", "Gráficos", "Графика"), M("Image and sound", "Imagem e som", "Изображение и звук"),
                               M("Advanced", "Avançado", "Дополнительно")};
        for (int t = 0; t < 3; t++) {
            if (!ui_tab(names[t], t, &g_cfg_tab)) continue;
            ImGui::BeginChild("##page", ImVec2(0, -footer), ImGuiChildFlags_NavFlattened);
            if (t == 0) ui_page_graphics(ui_graphics_x(NULL, 0), known);
            else if (t == 1) ui_page_image_sound();
            else ui_page_advanced();
            ImGui::EndChild();
            ImGui::EndTabItem();
        }
        ImGui::EndTabBar();
    }
    ImGui::Separator();
    bool close = ImGui::Button(M("Close", "Fechar", "Закрыть"), ImVec2(240 * scale, 0)) ||
                 (!ImGui::IsPopupOpen(NULL, ImGuiPopupFlags_AnyPopupId) && ImGui::IsKeyPressed(ImGuiKey_GamepadFaceRight, false));
    ImGui::SameLine();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("%s", M("F12 or Esc closes; L / R change the tab", "F12 ou Esc fecha; L / R trocam de aba", "F12 или Esc — закрыть; L / R — вкладки"));
    ImGui::End();
    if (close) set_cfg(false);
}

void menu_render(void *cmd, uint32_t target_w, uint32_t target_h) {
    bool open = g_open.load(), cfg = g_cfg.load(), kbd = g_kbd.load() == 1;
    float fx, fy;
    bool fdown, finger = !open && !cfg && input_finger_cursor(&fx, &fy, &fdown);
    if (!open && !cfg && !kbd && !g_settings.show_fps && !finger) {
        if (g_inited) { pthread_mutex_lock(&q_lock); q_events.clear(); pthread_mutex_unlock(&q_lock); }
        return;
    }
    if (!g_inited) init();
    ImGui::SetCurrentContext(g_ctx);
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2((float)target_w, (float)target_h);
    io.DisplayFramebufferScale = ImVec2(1, 1);
    static double last;
    double now = SDL_GetTicks() / 1000.0;
    io.DeltaTime = last > 0 && now > last ? (float)(now - last) : 1.0f / 60;
    last = now;
    drain_events(io);
    // fonts are built for a ~1080 px tall output; scale to the window (spacing / rounding too)
    static UiScaler scaler;
    float scale = ui_scale(scaler, (float)target_h);
    ImGui_ImplVulkan_NewFrame();
    ImGui::NewFrame();

    if (g_settings.show_fps) {
        ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x - 16 * scale, 16 * scale), 0, ImVec2(1, 0));
        ImGui::SetNextWindowBgAlpha(0.5f);
        ImGui::Begin("##fps", NULL, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize |
                                        ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoNav | ImGuiWindowFlags_NoFocusOnAppearing);
        ImGui::Text("%.0f fps", io.Framerate);
        ImGui::End();
    }
    if (finger) {  // the controller's finger on the touch screen (right stick moves it, ZR touches)
        ImDrawList *dl = ImGui::GetForegroundDrawList();
        float r = 26 * scale;
        dl->AddCircleFilled(ImVec2(fx, fy), r, fdown ? IM_COL32(255, 255, 255, 170) : IM_COL32(255, 255, 255, 60));
        dl->AddCircle(ImVec2(fx, fy), r, IM_COL32(255, 255, 255, 235), 0, 4 * scale);
    }
    if (open) quit_draw(io, scale);
    else if (cfg && !kbd) cfg_draw(io, scale);
    if (kbd) keyboard_draw(io, scale);
    ImGui::Render();
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), (VkCommandBuffer)cmd);  // inside the window image's rendering
}
