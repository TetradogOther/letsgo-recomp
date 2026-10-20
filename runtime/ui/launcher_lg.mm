// Let's Go Recomp start screen, in tabs: Game (the game files - picked once, set up and recompiled here:
// runtime/gamesetup.c - and the game options), Graphics (the window, then the F12 menu's graphics page:
// runtime/ui/settings_ui.mm), Image and sound (the same as the F12 menu's), Controls (keyboard / mouse) and Mods
// (mods/: game files replaced, a translation for one; installed from a downloaded file: runtime/mods.c); Play below
// them. The look is the F12 menu's. In English, or in Portuguese when the system's language is (LARECOMP_LANG=en|pt
// chooses; the shared pages speak Russian too). The choices go to larecomp.ini (settings.c; bind_key_* from
// runtime/hle/bindings.c).
// Tests: LARECOMP_LAUNCHER_SHOT=<frame> saves build/launcher.png (or LARECOMP_SHOT_PATH) and exits;
// LARECOMP_LAUNCHER_TAB=<n> opens that tab; LARECOMP_LAUNCHER_AUTOPLAY=1 plays as soon as the game files are ready; LARECOMP_SETUP_DIR=<folder> sets them up
// from that folder at once; LARECOMP_MOD_INSTALL=<file or folder> installs a mod at once;
// LARECOMP_LAUNCHER_KEYS=1 opens the Controls tab, =<slot> also waits for a new key for that input
// (runtime/input_bind.h BIND_*), and <slot>:<key name> presses that key for it.
#include <SDL3/SDL.h>
#include <float.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "imgui.h"
#include "imgui_impl_vulkan.h"
#include "imgui_impl_sdl3.h"
#include "settings_ui.h"

extern "C" {
#include "gamesetup.h"
#include "input_bind.h"
#include "mods.h"
#include "paths.h"
#include "settings.h"
#include "ui2x.h"
void settings_save(void);
void ui_window_init(void);
SDL_Window *ui_window(void);
void menu_apply_window_requests(void *sdl_window);
bool vk_frame_begin(const float clear[4]);
void vk_frame_end(const char *shot_path);
void *vk_frame_cmd(void);
bool vk_imgui_backend_init(void);
void vk_imgui_backend_shutdown(void);
}

// ------------------------------------------------------------------ language
// (runtime/ui/settings_ui.h picks it; this screen's own strings are English or Portuguese)
static bool g_pt;
#define T(en, pt) (g_pt ? (pt) : (en))
static float g_scale = 1;  // the window's height over 1080 (ui_scale): fixed sizes below are for 1080 px

// ------------------------------------------------------------------ keyboard
// The game's actions with the key bound to each. Click one, then press the new key (Esc or 5 s cancels; a key already
// in use swaps over). Controllers keep their buttons: nothing to set for them.
static const struct { int slot; const char *en, *pt; } k_actions[] = {
    {BIND_LS_UP, "Walk up", "Andar para cima"},             {BIND_A, "A (or Enter): confirm", "A (ou Enter): confirmar"},
    {BIND_LS_DOWN, "Walk down", "Andar para baixo"},         {BIND_B, "B (or Backspace): back", "B (ou Backspace): cancelar"},
    {BIND_LS_LEFT, "Walk left", "Andar para a esquerda"},    {BIND_X, "X: menu", "X: menu"},
    {BIND_LS_RIGHT, "Walk right", "Andar para a direita"},   {BIND_Y, "Y: options / box", "Y: opções / caixa"},
    {BIND_UP, "D-pad up", "Direcional cima"},                {BIND_L, "L: move Pokémon / items", "L: mover Pokémon / itens"},
    {BIND_DOWN, "D-pad down", "Direcional baixo"},           {BIND_R, "R: move Pokémon / items", "R: mover Pokémon / itens"},
    {BIND_LEFT, "D-pad left", "Direcional esquerda"},        {BIND_PLUS, "+: partner", "+: parceiro"},
    {BIND_RIGHT, "D-pad right", "Direcional direita"},       {BIND_MINUS, "-: Pokédex", "-: Pokédex"},
};

static const char *key_name(int sc) {
    switch (sc) {
    case SDL_SCANCODE_SPACE: return T("Space", "Espaço");
    case SDL_SCANCODE_RETURN: return "Enter";
    case SDL_SCANCODE_UP: return T("Up arrow", "Seta cima");
    case SDL_SCANCODE_DOWN: return T("Down arrow", "Seta baixo");
    case SDL_SCANCODE_LEFT: return T("Left arrow", "Seta esquerda");
    case SDL_SCANCODE_RIGHT: return T("Right arrow", "Seta direita");
    case 0: return T("(none)", "(nenhuma)");
    default: return bind_key_label(sc);
    }
}

static void keys_section(void) {
    int cap_dev, cap_slot, ms_left;
    bind_capture_active(&cap_dev, &cap_slot, &ms_left);
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(ImGui::GetStyle().ItemSpacing.x, 2));
    ImGui::PushStyleVar(ImGuiStyleVar_CellPadding, ImVec2(ImGui::GetStyle().CellPadding.x, 1));
    if (ImGui::BeginTable("##keys", 4, ImGuiTableFlags_SizingStretchProp)) {
        for (int c = 0; c < 4; c++) ImGui::TableSetupColumn(NULL, c & 1 ? ImGuiTableColumnFlags_WidthStretch : ImGuiTableColumnFlags_WidthFixed);
        for (size_t i = 0; i < sizeof k_actions / sizeof k_actions[0]; i++) {
            int slot = k_actions[i].slot;
            ImGui::TableNextColumn();
            ImGui::AlignTextToFramePadding();
            ImGui::TextUnformatted(T(k_actions[i].en, k_actions[i].pt));
            ImGui::TableNextColumn();
            bool waiting = cap_dev == BIND_DEV_KEY && cap_slot == slot;
            char lbl[96];
            if (waiting) snprintf(lbl, sizeof lbl, "%s %d##k%d", T("Press a key...", "Aperte a tecla..."), (ms_left + 999) / 1000, slot);
            else snprintf(lbl, sizeof lbl, "%s##k%d", key_name(g_bind_key[slot]), slot);
            int pushed = 0;
            if (waiting) { ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.55f, 0.42f, 0.12f, 1)); pushed++; }
            if (!bind_is_default_slot(BIND_DEV_KEY, slot)) { ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.98f, 0.82f, 0.38f, 1)); pushed++; }
            if (ImGui::Button(lbl, ImVec2(-FLT_MIN, 0))) {
                if (waiting) bind_capture_cancel();
                else bind_capture_begin(BIND_DEV_KEY, slot);
            }
            ImGui::PopStyleColor(pushed);
        }
        ImGui::EndTable();
    }
    ImGui::PopStyleVar(2);
    if (cap_dev == BIND_DEV_KEY)
        ImGui::TextDisabled("%s", T("Press the new key. Esc cancels; a key already in use swaps over.",
                                    "Aperte a nova tecla. Esc cancela; uma tecla já usada troca de lugar."));
    if (!bind_is_default(BIND_DEV_KEY) && ImGui::Button(T("Restore default keys", "Restaurar teclas padrão"))) bind_reset(BIND_DEV_KEY);
    ImGui::TextUnformatted(T("Mouse while aiming a Poké Ball: move = aim, left = throw.",
                             "Mouse na mira da Poké Ball: mover = mirar, esquerdo = arremessar."));
    ImGui::TextUnformatted(T("Otherwise: left = touch screen (Play with your partner). Right = B.",
                             "Fora dela: esquerdo = tocar na tela (Brincar com o parceiro). Direito = B."));
    const char *sl[] = {T("Mouse sensitivity", "Sensibilidade do mouse"), T("Controller stick dead zone", "Zona morta do analógico")};
    float x = ui_label_x(sl, 2);
    ui_row(sl[0], x);
    ImGui::SliderFloat("##mouse", &g_settings.mouse_sens, 0.02f, 0.30f, "%.2f");
    ui_row(sl[1], x);
    ImGui::SliderFloat("##dead", &g_settings.stick_deadzone, 0.0f, 0.40f, "%.2f");
}

// ------------------------------------------------------------------ the interface at 2x (runtime/ui2x.c)
// Made once from the player's own game files on request (the upscaler is downloaded then); used when made and on.
static void ui2x_section(bool ready, bool *on) {
    ui_heading(T("Sharper interface", "Interface mais nítida"));
    int n = ui2x_running() ? 0 : ui2x_count();
    int st = ui2x_state();
    if (ui2x_running()) {
        static const char *const en[] = {"", "Downloading the upscaler (waifu2x, 35 MB)...", "Reading the interface images...",
                                         "Upscaling them (a few minutes)...", "Saving them..."};
        static const char *const pt[] = {"", "Baixando o ampliador (waifu2x, 35 MB)...", "Lendo as imagens da interface...",
                                         "Ampliando (alguns minutos)...", "Salvando..."};
        ImGui::TextUnformatted(st >= UI2X_DOWNLOADING && st <= UI2X_PACKING ? (g_pt ? pt : en)[st] : "...");
        ImGui::ProgressBar(ui2x_progress(), ImVec2(-FLT_MIN, 0));
        return;
    }
    if (n) {
        char label[160];
        snprintf(label, sizeof label, T("Interface images at 2x (%d)", "Imagens da interface em 2x (%d)"), n);
        ImGui::Checkbox(label, on);
    } else {
        ImGui::TextDisabled("%s", T("The game's menu and interface images, redrawn at twice their resolution.",
                                    "As imagens dos menus e da interface do jogo, redesenhadas no dobro da resolução."));
    }
    ImGui::BeginDisabled(!ready);
    if (ImGui::SmallButton(n ? T("Make them again", "Gerar de novo") : T("Make the 2x images", "Gerar as imagens em 2x"))) ui2x_generate_start();
    ImGui::EndDisabled();
    if (ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled))
        ImGui::SetTooltip("%s", !ready ? T("Set up the game files first.", "Configure os arquivos do jogo antes.")
                                       : T("From your own game files, with waifu2x (downloaded once from GitHub, 35 MB). Takes a few minutes and about 1 GB in cache/.",
                                           "A partir dos seus arquivos do jogo, com o waifu2x (baixado uma vez do GitHub, 35 MB). Leva alguns minutos e ocupa cerca de 1 GB em cache/."));
    if (st >= UI2X_FAIL_DOWNLOAD) {
        static const char *const en[] = {"Couldn't download the upscaler: check the connection.",
                                         "The upscaler failed (details in lasrecomp.log): try again.",
                                         "Couldn't read the game files or write cache/."};
        static const char *const pt[] = {"Não foi possível baixar o ampliador: confira a conexão.",
                                         "O ampliador falhou (detalhes no lasrecomp.log): tente de novo.",
                                         "Não foi possível ler os arquivos do jogo ou gravar em cache/."};
        ImGui::SameLine();
        ImGui::TextColored(ImVec4(1.0f, 0.45f, 0.40f, 1), "%s", (g_pt ? pt : en)[st - UI2X_FAIL_DOWNLOAD]);
    }
}

// ------------------------------------------------------------------ file dialogs (SDL calls back on any thread)
static pthread_mutex_t g_pick_lock = PTHREAD_MUTEX_INITIALIZER;
static char g_pick_game[1024], g_pick_mod[1024];
static void SDLCALL picked_game(void *, const char *const *files, int) {
    if (!files || !files[0]) return;
    pthread_mutex_lock(&g_pick_lock);
    snprintf(g_pick_game, sizeof g_pick_game, "%s", files[0]);
    pthread_mutex_unlock(&g_pick_lock);
}
static void SDLCALL picked_mod(void *, const char *const *files, int) {
    if (!files || !files[0]) return;
    pthread_mutex_lock(&g_pick_lock);
    snprintf(g_pick_mod, sizeof g_pick_mod, "%s", files[0]);
    pthread_mutex_unlock(&g_pick_lock);
}
static bool take(char *slot, char *out, size_t n) {
    pthread_mutex_lock(&g_pick_lock);
    bool got = slot[0] != 0;
    if (got) snprintf(out, n, "%s", slot), slot[0] = 0;
    pthread_mutex_unlock(&g_pick_lock);
    return got;
}

// ------------------------------------------------------------------ the game files section
static const ImVec4 &k_green = UI_GREEN_TEXT, &k_red = UI_RED_TEXT;

static void game_files_section(SDL_Window *win) {
    ui_heading(T("Game files", "Arquivos do jogo"));
    int st = setup_state();
    if (setup_running()) {
        static const char *const en[] = {"", "Looking for the game files...", "Copying the game files...",
                                         "Building the game data image...", "Reading the game code...",
                                         "Recompiling the game code...", "Finishing..."};
        static const char *const pt[] = {"", "Procurando os arquivos do jogo...", "Copiando os arquivos do jogo...",
                                         "Montando a imagem de dados do jogo...", "Lendo o código do jogo...",
                                         "Recompilando o código do jogo...", "Finalizando..."};
        ImGui::TextUnformatted(st >= 1 && st <= 6 ? T(en[st], pt[st]) : "...");
        ImGui::ProgressBar(setup_progress(), ImVec2(-FLT_MIN, 0));
        ImGui::TextDisabled("%s", T("This takes a while (10-30 minutes), only once. The game can be played when it's done.",
                                    "Isso demora (de 10 a 30 minutos), só uma vez. O jogo fica liberado quando terminar."));
        return;
    }
    bool ready = setup_ready();
    if (ready) {
        const char *name = game_name("extracted/exefs");
        ImGui::TextColored(k_green, g_pt ? "Pokémon: Let's Go, %s! - pronto para jogar" : "Pokémon: Let's Go, %s! - ready to play",
                           name ? name : "Eevee");
        ImGui::SameLine();
        if (ImGui::SmallButton(T("Change...", "Trocar..."))) SDL_ShowOpenFolderDialog(picked_game, NULL, win, NULL, false);
        return;
    }
    if (st >= SETUP_FAIL_NOT_FOUND) {
        static const char *const en[] = {"No game files found in that folder.", "Those are packed game files (.xci / .nsp).",
                                         "That's not Pokémon: Let's Go, Eevee! or Pikachu!.", "The files couldn't be copied.",
                                         "The game code didn't build.", "The game code builder is missing from this copy."};
        static const char *const pt[] = {"Nenhum arquivo do jogo nessa pasta.", "Esses são arquivos do jogo empacotados (.xci / .nsp).",
                                         "Isso não é o Pokémon: Let's Go, Eevee! nem o Pikachu!.", "Os arquivos não puderam ser copiados.",
                                         "O código do jogo não compilou.", "O compilador do código do jogo não está nesta cópia."};
        static const char *const en_h[] = {"Choose the folder that holds exefs and romfs.", "Extract them first (exefs and romfs).",
                                           "Pick the folder of your own extracted Let's Go, Eevee! or Pikachu!.", "Check there are about 6 GB free and try again.",
                                           "Check there are about 2 GB free and try again; details in lasrecomp.log.", "Download the release again."};
        static const char *const pt_h[] = {"Escolha a pasta que tem exefs e romfs.", "Extraia antes (exefs e romfs).",
                                           "Escolha a pasta do seu Let's Go, Eevee! ou Pikachu! extraído.", "Confira se há uns 6 GB livres e tente de novo.",
                                           "Confira se há uns 2 GB livres e tente de novo; detalhes no lasrecomp.log.", "Baixe a release de novo."};
        int k = st - SETUP_FAIL_NOT_FOUND;
        ImGui::TextColored(k_red, "%s", T(en[k], pt[k]));
        ImGui::TextDisabled("%s", T(en_h[k], pt_h[k]));
    } else {
        ImGui::PushTextWrapPos(0);
        ImGui::TextUnformatted(T("Select the folder with your own extracted Pokémon: Let's Go, Eevee! or Pikachu! (exefs and romfs).",
                                 "Selecione a pasta com o seu Pokémon: Let's Go, Eevee! ou Pikachu! extraído (exefs e romfs)."));
        ImGui::PopTextWrapPos();
    }
    if (ImGui::Button(T("Select game folder...", "Selecionar pasta do jogo..."), ImVec2(-FLT_MIN, 0)))
        SDL_ShowOpenFolderDialog(picked_game, NULL, win, NULL, false);
}

// ------------------------------------------------------------------ the Mods tab
// The folders under mods/ that hold a romfs/ (runtime/mods.h): one active at a time, or none (the game as it is)
static const char *lang_name(const char *code) {
    static const struct { const char *code, *en, *pt; } k[] = {
        {"en-US", "English", "inglês"}, {"es", "Spanish", "espanhol"}, {"fr", "French", "francês"}, {"de", "German", "alemão"},
        {"it", "Italian", "italiano"}, {"ja", "Japanese", "japonês"}, {"ko", "Korean", "coreano"},
        {"zh-CN", "Simplified Chinese", "chinês simplificado"}, {"zh-TW", "Traditional Chinese", "chinês tradicional"}};
    for (size_t i = 0; i < sizeof k / sizeof k[0]; i++) if (!strcmp(k[i].code, code)) return T(k[i].en, k[i].pt);
    return code;
}

// The mods in their order (the active ones first, as larecomp.ini lists them: "<name>|<name>..."), and which are on
static char g_mods[MODS_MAX][128];
static bool g_mod_on[MODS_MAX];
static int g_nmods;
// Reads mods/ again: the names in `active` ('|' between them) on and first, in that order; the rest after, off
static void mods_reload(const char *active) {
    char found[MODS_MAX][128];
    int n = mods_list(found, MODS_MAX);
    bool used[MODS_MAX] = {};
    g_nmods = 0;
    char list[sizeof g_settings.mod];
    snprintf(list, sizeof list, "%s", active);
    for (char *save = NULL, *name = strtok_r(list, "|", &save); name; name = strtok_r(NULL, "|", &save))
        for (int i = 0; i < n; i++)
            if (!used[i] && !strcmp(found[i], name)) {
                used[i] = true;
                snprintf(g_mods[g_nmods], sizeof g_mods[0], "%s", found[i]);
                g_mod_on[g_nmods++] = true;
            }
    for (int i = 0; i < n; i++)
        if (!used[i]) snprintf(g_mods[g_nmods], sizeof g_mods[0], "%s", found[i]), g_mod_on[g_nmods++] = false;
}
// The active ones, in order, as larecomp.ini keeps them
static void mods_active(char *out, size_t cap) {
    out[0] = 0;
    for (int i = 0; i < g_nmods; i++)
        if (g_mod_on[i]) {
            if (out[0]) strncat(out, "|", cap - strlen(out) - 1);
            strncat(out, g_mods[i], cap - strlen(out) - 1);
        }
}

static void mods_section(SDL_Window *win, int inst) {
    static const SDL_DialogFileFilter filters[] = {{"Mod (.zip, .rar, .7z)", "zip;rar;7z"}};
    ImGui::PushTextWrapPos(0);
    ImGui::TextUnformatted(T("Mods that replace the game's files (a romfs folder, as Atmosphere's LayeredFS): translations, textures, models. "
                             "Mods of the game's code (exefs, IPS patches, cheats) don't work in this port.",
                             "Mods que trocam arquivos do jogo (uma pasta romfs, como o LayeredFS do Atmosphere): traduções, texturas, modelos. "
                             "Mods do código do jogo (exefs, patches IPS, cheats) não funcionam neste port."));
    ImGui::PopTextWrapPos();
    ui_heading(T("Mods", "Mods"));
    ImGui::PushTextWrapPos(0);
    ImGui::TextDisabled("%s", T("Tick the ones to use (several at once). Where two change the same file, the higher one wins: the arrows move it.",
                                "Marque os que vão ser usados (vários ao mesmo tempo). Se dois trocam o mesmo arquivo, vale o de cima: as setas mudam a ordem."));
    ImGui::PopTextWrapPos();
    int move = -1, dir = 0;
    for (int i = 0; i < g_nmods; i++) {
        ImGui::PushID(i);
        ImGui::BeginDisabled(i == 0);
        if (ImGui::ArrowButton("##up", ImGuiDir_Up)) move = i, dir = -1;
        ImGui::EndDisabled();
        ImGui::SameLine(0, ImGui::GetStyle().ItemSpacing.x * 0.4f);
        ImGui::BeginDisabled(i == g_nmods - 1);
        if (ImGui::ArrowButton("##down", ImGuiDir_Down)) move = i, dir = 1;
        ImGui::EndDisabled();
        ImGui::SameLine();
        ImGui::Checkbox(g_mods[i], &g_mod_on[i]);
        const char *lang = mod_language(g_mods[i]);
        if (lang) {
            ImGui::SameLine();
            ImGui::TextDisabled(g_pt ? "(troca os textos em %s)" : "(replaces the %s texts)", lang_name(lang));
        }
        ImGui::PopID();
    }
    if (move >= 0) {  // (swapped with the one above / below it)
        int j = move + dir;
        char name[128];
        bool on = g_mod_on[move];
        memcpy(name, g_mods[move], sizeof name), memcpy(g_mods[move], g_mods[j], sizeof name), memcpy(g_mods[j], name, sizeof name);
        g_mod_on[move] = g_mod_on[j], g_mod_on[j] = on;
    }
    if (!g_nmods) ImGui::TextDisabled("%s", T("No mods in the mods folder yet: the game as it is.", "Nenhum mod na pasta mods ainda: o jogo original."));
    ImGui::Spacing();
    if (inst == MOD_INSTALL_RUNNING) ImGui::TextDisabled("%s", T("Installing the mod...", "Instalando o mod..."));
    else if (ImGui::Button(T("Install a mod...", "Instalar mod..."))) SDL_ShowOpenFileDialog(picked_mod, NULL, win, filters, 1, NULL, false);
    ImGui::SameLine();
    if (ImGui::Button(T("Open the mods folder", "Abrir a pasta de mods"))) {
        char url[1200];
        snprintf(url, sizeof url, "file:///%s", mods_dir_abs());
        for (char *c = url; *c; c++) if (*c == '\\') *c = '/';
        SDL_OpenURL(url);
    }
    if (ImGui::IsItemHovered())
        ImGui::SetTooltip("%s", T("A mod copied there by hand (its folder, with a romfs inside) shows up here when you come back.",
                                  "Um mod copiado para lá à mão (a pasta dele, com uma romfs dentro) aparece aqui quando você voltar."));
    if (inst == MOD_INSTALL_FAIL_UNPACK || inst == MOD_INSTALL_FAIL_NOT_MOD)
        ImGui::TextColored(k_red, "%s", inst == MOD_INSTALL_FAIL_UNPACK ? T("Couldn't unpack that file.", "Não foi possível abrir esse arquivo.")
                                                                        : T("No mod for this game in that file (no romfs folder).",
                                                                            "Esse arquivo não tem mod para este jogo (nenhuma pasta romfs)."));
}

// ------------------------------------------------------------------ the start screen
extern "C" void launcher_lg_run(const char *root) {
    (void)root;
    ui_pick_language();
    g_pt = g_ui_lang == 1;
    ui_window_init();
    SDL_Window *win = ui_window();
    ImGuiContext *prev_ctx = ImGui::GetCurrentContext();  // (the in-game menu's, when back here after a reboot)
    ImGuiContext *ctx = ImGui::CreateContext();
    ImGui::SetCurrentContext(ctx);
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard | ImGuiConfigFlags_NavEnableGamepad;
    io.IniFilename = NULL;
    UiFonts fonts = ui_load_fonts();
    ui_style();
    UiScaler scaler;
    ImGui_ImplSDL3_InitForVulkan(win);
    vk_imgui_backend_init();

    static const char *const res_en[] = {"Automatic (window size)", "720p", "1080p", "1440p", "4K"};
    static const char *const res_pt[] = {"Automática (tamanho da janela)", "720p", "1080p", "1440p", "4K"};
    static const int res_lines[] = {0, 720, 1080, 1440, 2160};
    int res = 0;
    for (int i = 0; i < 5; i++) if (res_lines[i] == g_settings.res_height) res = i;
    bool ui2x_on = g_settings.ui2x;  // (the interface at 2x: runtime/ui2x.c)
    bool full = g_settings.fullscreen, wildb = g_settings.wild_battle, skipc = g_settings.skip_controller;
    mods_reload(g_settings.mod);  // (the folders under mods/: runtime/mods.h)
    long shot_at = getenv("LARECOMP_LAUNCHER_SHOT") ? atol(getenv("LARECOMP_LAUNCHER_SHOT")) : 0, frame = 0;
    bool autoplay = getenv("LARECOMP_LAUNCHER_AUTOPLAY") != NULL, play = false;
    const char *keys_test = getenv("LARECOMP_LAUNCHER_KEYS");
    enum { TAB_GAME, TAB_GRAPHICS, TAB_IMAGE, TAB_CONTROLS, TAB_MODS, NTABS };
    int tab = getenv("LARECOMP_LAUNCHER_TAB") ? atoi(getenv("LARECOMP_LAUNCHER_TAB")) : keys_test ? TAB_CONTROLS : TAB_GAME;
    if (getenv("LARECOMP_LAUNCHER_TAB") || keys_test) ui_tab_select(tab);
    if (keys_test && atoi(keys_test) > 0) bind_capture_begin(BIND_DEV_KEY, atoi(keys_test));
    if (getenv("LARECOMP_SETUP_DIR")) setup_start(getenv("LARECOMP_SETUP_DIR"));
    if (getenv("LARECOMP_MOD_INSTALL")) mod_install_start(getenv("LARECOMP_MOD_INSTALL"));
    static const float bg[4] = {0.06f, 0.09f, 0.08f, 1};  // (the F12 menu's panel colour)

    while (!play) {
        menu_apply_window_requests(win);
        SDL_Event e;
        bool focus_back = false;
        while (SDL_PollEvent(&e)) {
            if (bind_capture_event(&e)) continue;  // (waiting for a new key: the press is the binding's)
            ImGui_ImplSDL3_ProcessEvent(&e);
            if (e.type == SDL_EVENT_QUIT) exit(0);
            if (e.type == SDL_EVENT_WINDOW_FOCUS_GAINED) focus_back = true;
        }
        char path[1024];
        if (take(g_pick_game, path, sizeof path)) setup_start(path);
        if (take(g_pick_mod, path, sizeof path)) mod_install_start(path);
        static int last_install;
        int inst = mod_install_state();
        if ((inst != last_install && inst == MOD_INSTALL_DONE) || focus_back) {  // a new mod (installed, or copied by hand)
            char was[sizeof g_settings.mod], want[sizeof g_settings.mod + 130];
            mods_active(was, sizeof was);
            if (inst != last_install && inst == MOD_INSTALL_DONE) snprintf(want, sizeof want, "%s%s%s", mod_install_name(), was[0] ? "|" : "", was);
            else snprintf(want, sizeof want, "%s", was);  // (a new one installed: on, and first)
            mods_reload(want);
        }
        last_install = inst;
        bool ready = !setup_running() && setup_ready();
        {   // (tests, LARECOMP_UI2X_GENERATE=1: the 2x interface images made, then exit - status 0 when done)
            static int gen = -1;
            if (gen < 0) gen = getenv("LARECOMP_UI2X_GENERATE") != NULL;
            if (gen == 1 && ready) { ui2x_generate_start(); gen = 2; }
            else if (gen == 2 && !ui2x_running()) exit(ui2x_state() == UI2X_DONE ? 0 : 1);
        }
        if (autoplay && ready && inst != MOD_INSTALL_RUNNING) play = true;
        if (!vk_frame_begin(bg)) { SDL_Delay(16); continue; }
        if (keys_test && strchr(keys_test, ':') && frame == 5) {  // "<slot>:<key name>": the key pressed for the test
            SDL_Event k = {};
            k.type = SDL_EVENT_KEY_DOWN;
            k.key.scancode = SDL_GetScancodeFromName(strchr(keys_test, ':') + 1);
            k.key.down = true;
            SDL_PushEvent(&k);
        }
        ImGui_ImplVulkan_NewFrame();
        ImGui_ImplSDL3_NewFrame();
        g_scale = ui_scale(scaler, io.DisplaySize.y);
        ImGui::NewFrame();
        // the whole window (not a panel inside it): the tabs change what is in it, Play stays at the bottom; the content
        // in a column of up to 1150 px (at 1080) in the middle of a wide window
        ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
        ImGui::SetNextWindowSize(io.DisplaySize, ImGuiCond_Always);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0);
        ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(bg[0], bg[1], bg[2], 1));
        ImGui::Begin("##launcher", NULL, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
                                             ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoScrollbar |
                                             ImGuiWindowFlags_NoBringToFrontOnFocus);
        ImGui::PopStyleColor();
        ImGui::PopStyleVar();
        {
            float avail = ImGui::GetContentRegionAvail().x, colw = fminf(avail, 1150 * g_scale);
            ImGui::SetCursorPosX(ImGui::GetCursorPosX() + (avail - colw) * 0.5f);
            ImGui::BeginChild("##column", ImVec2(colw, 0), ImGuiChildFlags_NavFlattened, ImGuiWindowFlags_NoScrollbar);
        }
        ui_title(fonts.title, RT_APP_NAME);
        ImGui::SameLine(ImGui::GetContentRegionMax().x - ImGui::CalcTextSize("v" RT_APP_VERSION).x);
        ImGui::AlignTextToFramePadding();
        ImGui::TextDisabled("v" RT_APP_VERSION);
        // (the frame rate modes and these options hook game functions by address: builds without tables keep them off)
        bool known = !setup_ready() || game_build("extracted/exefs") != GAME_BUILD_OTHER;
        const char *only = T("Only with version 1.0.0 (the base game) of Eevee or Pikachu for now.",
                             "Por enquanto só na versão 1.0.0 (o jogo base) do Eevee ou do Pikachu.");
        float footer = ImGui::GetFrameHeight() + ImGui::GetStyle().ItemSpacing.y * 2 + ImGui::GetStyle().WindowPadding.y * 0.5f;
        ui_tabs_begin(&tab, NTABS);
        if (ImGui::BeginTabBar("##tabs")) {
            const char *names[NTABS] = {T("Game", "Jogo"), T("Graphics", "Gráficos"), T("Image and sound", "Imagem e som"),
                                        T("Controls", "Controles"), "Mods"};
            for (int t = 0; t < NTABS; t++) {
                if (!ui_tab(names[t], t, &tab)) continue;
                ImGui::BeginChild("##page", ImVec2(0, -footer), ImGuiChildFlags_NavFlattened);
                if (t == TAB_GAME) {
                    game_files_section(win);
                    ui_heading(T("Options", "Opções"));
                    ImGui::BeginDisabled(!known);
                    ImGui::Checkbox(T("Wild battles (experimental)", "Batalhas selvagens (experimental)"), &wildb);
                    if (ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled))
                        ImGui::SetTooltip("%s", !known ? only : T("Touching a wild Pokémon starts a classic battle, then the capture, instead of going straight to the capture.",
                                                                 "Encostar num Pokémon selvagem começa uma batalha clássica e, depois, a captura, em vez de ir direto para a captura."));
                    ImGui::Checkbox(T("Skip controller selection", "Pular a escolha do controle"), &skipc);
                    if (ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled))
                        ImGui::SetTooltip("%s", !known ? only : T("The game starts at the Game Freak logo, with your controller already chosen, instead of asking for a button press first.",
                                                                 "O jogo começa no logo da Game Freak, com o seu controle já escolhido, em vez de pedir antes que se aperte um botão."));
                    ImGui::EndDisabled();
                } else if (t == TAB_GRAPHICS) {
                    const char *extra[] = {T("Render resolution", "Resolução de renderização")};
                    float x = ui_graphics_x(extra, 1);
                    ui_row(extra[0], x);
                    ImGui::Combo("##res", &res, g_pt ? res_pt : res_en, 5);
                    if (ImGui::Checkbox(T("Fullscreen", "Tela cheia"), &full)) SDL_SetWindowFullscreen(win, full);
                    ImGui::Separator();
                    ui_page_graphics(x, known);
                    ui2x_section(ready, &ui2x_on);
                } else if (t == TAB_IMAGE) {
                    ui_page_image_sound();
                } else if (t == TAB_CONTROLS) {
                    keys_section();
                } else {
                    mods_section(win, inst);
                }
                ImGui::EndChild();
                ImGui::EndTabItem();
            }
            ImGui::EndTabBar();
        }
        ImGui::Separator();
        ImGui::BeginDisabled(!ready);
        if (frame == 0 && ready) ImGui::SetKeyboardFocusHere();
        if (ImGui::Button(T("Play", "Jogar"), ImVec2(-FLT_MIN, 0))) play = true;
        ImGui::EndDisabled();
        if (!ready && ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled))
            ImGui::SetTooltip("%s", T("Set up the game files first (Game tab).", "Configure os arquivos do jogo antes (aba Jogo)."));
        ImGui::EndChild();
        ImGui::End();

        ImGui::Render();
        ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), (VkCommandBuffer)vk_frame_cmd());
        bool shot = shot_at && ++frame == shot_at;
        if (!shot_at) frame++;
        vk_frame_end(shot ? (getenv("LARECOMP_SHOT_PATH") ? getenv("LARECOMP_SHOT_PATH") : "build/launcher.png") : NULL);
        if (shot) exit(0);
    }
    g_settings.res_height = res_lines[res];
    g_settings.fullscreen = full;
    settings_apply_levels();  // (the upscaler follows the anti-aliasing)
    g_settings.wild_battle = wildb;
    g_settings.skip_controller = skipc;
    g_settings.ui2x = ui2x_on;
    mods_active(g_settings.mod, sizeof g_settings.mod);
    settings_save();
    vk_imgui_backend_shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImGui::DestroyContext(ctx);
    ImGui::SetCurrentContext(prev_ctx);
}
