// No controller screen at start (launcher "Skip controller selection", larecomp.ini skip_controller = 1): the game
// starts at the Game Freak logo, with the controller already chosen, instead of "Press a button on the controller you
// want to use" and its confirmation.
//
// How the game does it (Pikachu and Eevee 1.0.0, the same address in both): the start sequence runs a controller step
// once per frame until it says it is done (f_700004eb50, x0 = the step, true when done). Its mode at [+0x130]:
//  - 0: it looks at the three players' controllers ([controller manager + 0xb40], 0x80 each) and is done at once when
//    fewer than two are set and none is of a kind it doesn't take - else it asks, as below;
//  - otherwise (1 at start): it builds the controller settings app (bin/app/setting_cnt: "main menu", "detail menu",
//    "palma button switch"...) into [+0x88] and waits for it.
// At start the one controller the runtime presents (handheld, npad 0x20: runtime/hle/input.c) is player 0's already,
// so the step is turned to mode 0 before its first run: it finds that controller and ends, as a check after the app
// would. Only the first time per boot - the same step may ask again while playing (a controller lost), and asks then.
// LARECOMP_SKIP_CONTROLLER=0/1 overrides the setting (tests).
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "../hle.h"
#include "../settings.h"

void rt_register_fnhook(uint64_t addr, int (*fn)(Cpu *c, uint64_t addr));  // runtime/fnhook.c
uint64_t rt_addr(uint64_t eevee);  // runtime/fnhook.c: an Eevee 1.0.0 address in the running build (0: unknown build)

#define CONTROLLER_STEP 0x700004eb50ull  // the start sequence's controller step (x0 = it)
#define STEP_APP 0x88                    // its controller settings app, once built
#define STEP_MODE 0x130                  // 0: check the players' controllers; 1 (start): ask

static bool g_on, g_done;  // on (this boot); the start's step seen
RT_ON_RESET(controller_skip_reset) { g_done = false; }

static int step_hook(Cpu *c, uint64_t addr) {
    (void)addr;
    if (!g_on || g_done) return 0;
    uint8_t *step = (uint8_t *)(uintptr_t)c->x[0];
    g_done = true;
    if (!*(uint64_t *)(step + STEP_APP) && *(uint32_t *)(step + STEP_MODE) == 1) {
        *(uint32_t *)(step + STEP_MODE) = 0;
        LOG("[ctlskip] the controller screen skipped\n");
    }
    return 0;  // (the game's step runs, in mode 0)
}

// Before each boot (runtime/main.c), like the other launcher options that hook the game
void controller_skip_configure(void) {
    static bool hooked;
    extern void settings_load(void);
    settings_load();  // (read once; without the launcher it would come later, in boot)
    const char *e = getenv("LARECOMP_SKIP_CONTROLLER");
    g_on = (e && *e ? atoi(e) != 0 : g_settings.skip_controller) && rt_addr(CONTROLLER_STEP);
    if (!g_on || hooked) return;
    hooked = true;
    rt_register_fnhook(CONTROLLER_STEP, step_hook);
}
