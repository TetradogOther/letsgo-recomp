// The look and the settings pages shared by the start screen and the F12 menu (runtime/ui/settings_ui.h).
#include <SDL3/SDL.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "settings_ui.h"

extern "C" {
#include "../paths.h"
#include "../settings.h"
bool vk_fg_available(void);  // runtime/nvn/vulkan/device.c: AMD's frame generation swapchain can be made
}

// ------------------------------------------------------------------ language
int g_ui_lang;
void ui_pick_language(void) {
    const char *e = getenv("LARECOMP_LANG"), *lang = e && *e ? e : "";
    SDL_Locale **l = NULL;
    int n = 0;
    if (!*lang && (l = SDL_GetPreferredLocales(&n)) && n > 0 && l[0]->language) lang = l[0]->language;
    g_ui_lang = !strncmp(lang, "pt", 2) ? 1 : !strncmp(lang, "ru", 2) ? 2 : 0;
    SDL_free(l);
}

// ------------------------------------------------------------------ look
const ImVec4 UI_GOLD(0.93f, 0.76f, 0.33f, 1), UI_GREEN_TEXT(0.45f, 0.85f, 0.50f, 1), UI_RED_TEXT(1.0f, 0.45f, 0.40f, 1);

UiFonts ui_load_fonts(void) {
    ImGuiIO &io = ImGui::GetIO();
    ImFontConfig cfg;
    cfg.OversampleH = 2;
    static const ImWchar ranges[] = {0x20, 0xFF, 0x400, 0x45F, 0};  // (Latin-1: Portuguese accents; Cyrillic)
    UiFonts f = {};
    const char *paths[] = {"C:/Windows/Fonts/segoeui.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                           "/usr/share/fonts/TTF/DejaVuSans.ttf", "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"};
    for (const char *p : paths) {
        if (FILE *fp = fopen(p, "rb")) fclose(fp);  // (a missing file is an assertion in ImGui, not a NULL return)
        else continue;
        f.body = io.Fonts->AddFontFromFileTTF(p, 34, &cfg, ranges);
        f.big = io.Fonts->AddFontFromFileTTF(p, 56, &cfg, ranges);
        break;
    }
    char baloo[1024];
    if (rt_resource("Baloo2-SemiBold.ttf", "third_party/fonts/Baloo2/Baloo2-SemiBold.ttf", baloo, sizeof baloo))
        f.title = io.Fonts->AddFontFromFileTTF(baloo, 50, &cfg, ranges);
    if (!f.body) f.body = io.Fonts->AddFontDefault();
    if (!f.big) f.big = f.body;
    if (!f.title || g_ui_lang == 2) f.title = f.body;
    return f;
}

void ui_style(void) {
    ImGuiStyle &s = ImGui::GetStyle();
    ImGui::StyleColorsDark();
    s.WindowRounding = 14, s.FrameRounding = 8, s.GrabRounding = 8, s.TabRounding = 8;
    s.WindowPadding = ImVec2(28, 24), s.FramePadding = ImVec2(14, 8), s.ItemSpacing = ImVec2(14, 12);
    s.WindowBorderSize = 0;
    ImVec4 *c = s.Colors;
    ImVec4 green(0.15f, 0.36f, 0.25f, 1);
    c[ImGuiCol_WindowBg] = ImVec4(0.06f, 0.09f, 0.08f, 0.94f);
    c[ImGuiCol_PopupBg] = ImVec4(0.07f, 0.10f, 0.09f, 0.98f);
    c[ImGuiCol_Text] = ImVec4(0.96f, 0.94f, 0.88f, 1);
    c[ImGuiCol_TextDisabled] = ImVec4(0.62f, 0.64f, 0.58f, 1);
    c[ImGuiCol_FrameBg] = ImVec4(0.13f, 0.19f, 0.16f, 1);
    c[ImGuiCol_FrameBgHovered] = green;
    c[ImGuiCol_FrameBgActive] = ImVec4(0.19f, 0.45f, 0.31f, 1);
    c[ImGuiCol_Button] = ImVec4(0.14f, 0.22f, 0.18f, 1);
    c[ImGuiCol_ButtonHovered] = green;
    c[ImGuiCol_ButtonActive] = ImVec4(0.21f, 0.50f, 0.34f, 1);
    c[ImGuiCol_Header] = ImVec4(0.14f, 0.22f, 0.18f, 1);
    c[ImGuiCol_HeaderHovered] = green;
    c[ImGuiCol_HeaderActive] = ImVec4(0.21f, 0.50f, 0.34f, 1);
    c[ImGuiCol_CheckMark] = UI_GOLD;
    c[ImGuiCol_SliderGrab] = ImVec4(0.30f, 0.62f, 0.44f, 1);
    c[ImGuiCol_SliderGrabActive] = UI_GOLD;
    c[ImGuiCol_Tab] = ImVec4(0.10f, 0.15f, 0.13f, 1);
    c[ImGuiCol_TabHovered] = green;
    c[ImGuiCol_TabSelected] = ImVec4(0.18f, 0.40f, 0.28f, 1);
    c[ImGuiCol_TabSelectedOverline] = UI_GOLD;
    c[ImGuiCol_TabDimmed] = c[ImGuiCol_Tab];
    c[ImGuiCol_TabDimmedSelected] = c[ImGuiCol_TabSelected];
    c[ImGuiCol_Separator] = ImVec4(0.22f, 0.30f, 0.26f, 1);
    c[ImGuiCol_PlotHistogram] = ImVec4(0.30f, 0.62f, 0.44f, 1);
    c[ImGuiCol_NavCursor] = UI_GOLD;
}

float ui_scale(UiScaler &s, float window_h) {
    float scale = window_h / 1080.0f;
    if (scale < 0.45f) scale = 0.45f;
    ImGui::GetIO().FontGlobalScale = scale;
    if (s.scale < 0) s.base = ImGui::GetStyle();
    if (fabsf(s.scale - scale) > 0.01f) {
        ImGui::GetStyle() = s.base;
        ImGui::GetStyle().ScaleAllSizes(scale);
        s.scale = scale;
    }
    return scale;
}

void ui_title(ImFont *title, const char *text) {
    ImGui::PushFont(title);
    ImGui::TextColored(UI_GOLD, "%s", text);
    ImGui::PopFont();
}

void ui_heading(const char *text) {
    ImGui::Spacing();
    ImGui::TextColored(UI_GOLD, "%s", text);
}

float ui_label_x(const char *const *labels, int n) {
    float w = 0;
    for (int i = 0; i < n; i++) w = fmaxf(w, ImGui::CalcTextSize(labels[i]).x);
    return w + ImGui::GetStyle().WindowPadding.x + ImGui::GetStyle().ItemSpacing.x * 2;
}

void ui_row(const char *label, float x) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label);
    ImGui::SameLine(x);
    ImGui::SetNextItemWidth(-1);
}

// ------------------------------------------------------------------ tabs
static int g_tab_want = -1;  // the tab L1 / R1 asked for, selected at its next ui_tab
void ui_tabs_begin(int *current, int count) {
    int step = ImGui::IsKeyPressed(ImGuiKey_GamepadL1, false) ? -1 : ImGui::IsKeyPressed(ImGuiKey_GamepadR1, false) ? 1 : 0;
    if (step && count > 0) g_tab_want = *current = (*current + step + count) % count;
}
bool ui_tab(const char *label, int index, int *current) {
    bool open = ImGui::BeginTabItem(label, NULL, g_tab_want == index ? ImGuiTabItemFlags_SetSelected : 0);
    if (open && g_tab_want == index) g_tab_want = -1;
    if (open && g_tab_want < 0) *current = index;  // (a click on another tab: that one now)
    return open;
}
void ui_tab_select(int index) { g_tab_want = index; }

// ------------------------------------------------------------------ the graphics page
static const char *const *graphics_labels(int *n) {
    static const char *l[8];
    l[0] = UI_T("Frame rate limit", "Limite de quadros", "Лимит кадров");
    l[1] = UI_T("Ambient occlusion (SSAO)", "Oclusão de ambiente (SSAO)", "Затенение (SSAO)");
    l[2] = UI_T("Indirect light (GI)", "Luz indireta (GI)", "Непрямой свет (GI)");
    l[3] = UI_T("Shadow filter", "Filtro das sombras", "Фильтр теней");
    l[4] = UI_T("Anti-aliasing", "Antisserrilhado", "Сглаживание");
    l[5] = UI_T("Upscaler", "Escalonador", "Масштабирование");
    l[6] = UI_T("FSR 3.1 mode", "Modo do FSR 3.1", "Режим FSR 3.1");
    l[7] = UI_T("Frame generation", "Geração de quadros", "Генерация кадров");
    *n = 8;
    return l;
}

float ui_graphics_x(const char *const *extra, int n_extra) {
    int n;
    const char *const *l = graphics_labels(&n);
    float x = ui_label_x(l, n);
    return extra && n_extra ? fmaxf(x, ui_label_x(extra, n_extra)) : x;
}

void ui_page_graphics(float x, bool known) {
    int n;
    const char *const *l = graphics_labels(&n);
    // the world's frame rate (runtime/hle/fps60.c, switched at the next present): the game's 30, 60, or 120 (more
    // experimental); menus stay at 30 with an in-between image (60), battles and captures at 30
    {
        const char *fr[] = {UI_T("30 fps (original)", "30 fps (original)", "30 fps (оригинал)"), "60 fps",
                            UI_T("120 fps (experimental)", "120 fps (experimental)", "120 fps (экспериментально)")};
        int f = !known ? 0 : g_settings.fps == 120 ? 2 : g_settings.fps == 60 ? 1 : 0;
        ui_row(l[0], x);
        ImGui::BeginDisabled(!known);
        if (ImGui::Combo("##fps", &f, fr, 3)) g_settings.fps = f == 2 ? 120 : f == 1 ? 60 : 30;
        ImGui::EndDisabled();
        if (ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled))
            ImGui::SetTooltip("%s", !known ? UI_T("Only with version 1.0.0 (the base game) of Eevee or Pikachu for now.",
                                                  "Por enquanto só na versão 1.0.0 (o jogo base) do Eevee ou do Pikachu.",
                                                  "Пока только с версией 1.0.0 (базовая игра) Eevee или Pikachu.")
                                           : UI_T("The world at 60 or 120 fps; menus and the Pokédex smoothed; battles and captures stay at 30.",
                                                  "Mundo a 60 ou 120 fps; menus e Pokédex suavizados; batalhas e capturas continuam a 30.",
                                                  "Мир на 60 или 120 к/с; меню и Покедекс сглажены; бои и поимки остаются на 30."));
    }
    ImGui::Separator();
    // SSAO and GI by quality level (their parameters: settings_apply_levels; high = what they had before the levels)
    const char *lv[] = {UI_T("Off", "Desligado", "Выкл."), UI_T("Low", "Baixo", "Низкое"), UI_T("Medium", "Médio", "Среднее"),
                        UI_T("High", "Alto", "Высокое")};
    ui_row(l[1], x);
    ImGui::Combo("##ssao_lv", &g_settings.ssao_level, lv, 4);
    ui_row(l[2], x);
    ImGui::Combo("##gi_lv", &g_settings.gi_level, lv, 4);
    // the shadow map's filter (runtime/nvn/vulkan/textures.c vk_sampler, runtime/nvn/maxwell/translate.c shpcf)
    const char *sh[] = {UI_T("Game's", "Do jogo", "Как в игре"), UI_T("Bilinear", "Bilinear", "Билинейный"), UI_T("Smooth", "Suave", "Мягкий")};
    ui_row(l[3], x);
    ImGui::Combo("##shadow_filter", &g_settings.shadow_filter, sh, 3);
    ImGui::Separator();
    // anti-aliasing: SMAA on the final image (the interface too), TAA on the scene (jittered, motion vectors:
    // runtime/nvn/vulkan/exec.c taa_run), or FSR 3.1 - temporal (jittered scene, motion vectors, the interface masked:
    // exec.c, fsr3.cpp), it anti-aliases and upscales a lower render resolution (its mode, below). Otherwise the upscaler
    // picked below: FSR 1 or bilinear. The upscaler row offers FSR 3.1 too: the same choice, the two rows follow each
    // other; leaving FSR 3.1 there brings back the anti-aliasing it replaced.
    static int last_aa = AA_SMAA;
    if (g_settings.antialias != AA_FSR3) last_aa = g_settings.antialias;
    const char *aa[] = {UI_T("Off", "Desligado", "Выкл."), "SMAA", "TAA", "FSR 3.1"};
    ui_row(l[4], x);
    if (ImGui::Combo("##aa", &g_settings.antialias, aa, 4)) settings_apply_levels();
    {
        const char *up[] = {UI_T("Bilinear", "Bilinear", "Билинейный"), "FSR 1", "FSR 3.1"};
        int u = g_settings.antialias == AA_FSR3 ? 2 : g_settings.upscaler_pick == UPSCALE_BILINEAR ? 0 : 1;
        ui_row(l[5], x);
        if (ImGui::Combo("##up", &u, up, 3)) {
            if (u == 2) g_settings.antialias = AA_FSR3;
            else {
                g_settings.upscaler_pick = u ? UPSCALE_SHARP : UPSCALE_BILINEAR;
                if (g_settings.antialias == AA_FSR3) g_settings.antialias = last_aa;
            }
            settings_apply_levels();
        }
    }
    // FSR 3.1's presets: the render resolution is the window's divided by the ratio (runtime/nvn/output_scale.c)
    if (g_settings.antialias == AA_FSR3) {
        const char *pr[] = {UI_T("Native AA (1.0x)", "AA nativo (1,0x)", "Нативное AA (1,0x)"),
                            UI_T("Quality (1.5x)", "Qualidade (1,5x)", "Качество (1,5x)"),
                            UI_T("Balanced (1.7x)", "Equilibrado (1,7x)", "Баланс (1,7x)"),
                            UI_T("Performance (2.0x)", "Desempenho (2,0x)", "Производительность (2,0x)"),
                            UI_T("Ultra Performance (3.0x)", "Ultra desempenho (3,0x)", "Макс. производительность (3,0x)")};
        ui_row(l[6], x);
        ImGui::Combo("##fsr3p", &g_settings.fsr3_preset, pr, 5);
    }
    // FSR 3.1 frame generation (exec.c vk_fg_present; AMD's swapchain is switched to at the next frame: device.c). FSR
    // 3.1 makes one frame between two (several is FSR 4's, which has no Vulkan version): off or 2x.
    {
        bool can = g_settings.antialias == AA_FSR3 && vk_fg_available();
        const char *fg[] = {UI_T("Off", "Desligado", "Выкл."), "2x"};
        int cur = can && g_settings.frame_gen == 2 ? 1 : 0;
        ui_row(l[7], x);
        ImGui::BeginDisabled(!can);
        if (ImGui::Combo("##fg", &cur, fg, 2)) g_settings.frame_gen = cur ? 2 : 0;
        ImGui::EndDisabled();
        if (!can && ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled))
            ImGui::SetTooltip("%s", vk_fg_available() ? UI_T("With FSR 3.1 anti-aliasing", "Com o antisserrilhado FSR 3.1", "Со сглаживанием FSR 3.1")
                                                      : UI_T("amd_fidelityfx_vk.dll is missing", "Falta amd_fidelityfx_vk.dll", "Нет amd_fidelityfx_vk.dll"));
    }
    settings_apply_levels();
}

// ------------------------------------------------------------------ image and sound
// Volume and the game image's colour, applied live in game (runtime/services/audio.c apply_gain,
// runtime/nvn/vulkan/exec.c post_process, color.frag), and the TAA / FSR 3.1 sharpening at the present
void ui_page_image_sound(void) {
    const char *l_vol = UI_T("Volume", "Volume", "Громкость"), *l_bri = UI_T("Brightness", "Brilho", "Яркость"),
               *l_con = UI_T("Contrast", "Contraste", "Контраст"), *l_sat = UI_T("Saturation", "Saturação", "Насыщенность"),
               *l_shp = UI_T("Sharpness (TAA / FSR 3.1)", "Nitidez (TAA / FSR 3.1)", "Резкость (TAA / FSR 3.1)");
    const char *labels[] = {l_vol, l_bri, l_con, l_sat, l_shp};
    float x = ui_label_x(labels, 5);
    struct Row { const char *label; float *v, lo, hi; } rows[] = {
        {l_vol, &g_settings.volume, 0.0f, 2.0f}, {l_bri, &g_settings.brightness, 0.5f, 1.5f},
        {l_con, &g_settings.contrast, 0.5f, 1.5f}, {l_sat, &g_settings.saturation, 0.0f, 2.0f}};
    for (int i = 0; i < 4; i++) {
        if (i == 1) ImGui::Separator();
        float pct = *rows[i].v * 100;
        ui_row(rows[i].label, x);
        ImGui::PushID(100 + i);
        if (ImGui::SliderFloat("##v", &pct, rows[i].lo * 100, rows[i].hi * 100, "%.0f%%", ImGuiSliderFlags_AlwaysClamp)) *rows[i].v = pct / 100;
        ImGui::PopID();
    }
    ImGui::BeginDisabled(g_settings.antialias != AA_TAA && g_settings.antialias != AA_FSR3);
    {
        float pct = g_settings.taa_sharpness * 100;
        ui_row(l_shp, x);
        if (ImGui::SliderFloat("##taa_s", &pct, 0, 100, "%.0f%%", ImGuiSliderFlags_AlwaysClamp)) g_settings.taa_sharpness = pct / 100;
    }
    ImGui::EndDisabled();
    if (ImGui::Button(UI_T("Reset", "Restaurar", "Сбросить"))) {
        g_settings.volume = g_settings.brightness = g_settings.contrast = g_settings.saturation = 1.0f;
        g_settings.taa_sharpness = 0.5f;
    }
    settings_clamp_color();
}

// ------------------------------------------------------------------ advanced
// The motion vectors' detail and the debug views (shown at the present instead of the game image: exec.c post_process)
void ui_page_advanced(void) {
    ImGui::Checkbox(UI_T("Per-object motion vectors (TAA, FSR 3.1, frame generation)", "Vetores de movimento por objeto (TAA, FSR 3.1, geração de quadros)",
                         "Векторы движения объектов (TAA, FSR 3.1, генерация кадров)"), &g_settings.mv_objects);
    ui_heading(UI_T("Debug views", "Vistas de depuração", "Отладка"));
    ImGui::BeginDisabled(!g_settings.ssao);
    ImGui::Checkbox(UI_T("Occlusion alone", "Só a oclusão", "Только затенение"), &g_settings.ssao_debug);
    ImGui::EndDisabled();
    ImGui::SameLine();
    ImGui::BeginDisabled(!g_settings.gi);
    ImGui::Checkbox(UI_T("Indirect light alone", "Só a luz indireta", "Только непрямой свет"), &g_settings.gi_debug);
    ImGui::EndDisabled();
    ImGui::SameLine();
    ImGui::Checkbox(UI_T("Motion vectors", "Vetores de movimento", "Векторы движения"), &g_settings.mv_debug);
    if (ImGui::Button(UI_T("Reset", "Restaurar", "Сбросить"))) {
        g_settings.ssao_debug = g_settings.gi_debug = g_settings.mv_debug = false;
        g_settings.mv_objects = true;
    }
}
