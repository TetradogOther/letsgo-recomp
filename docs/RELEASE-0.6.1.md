# Let's Go Recomp 0.6.1 — the Linux port

The runtime now builds and runs on Linux, and there is a Debian package and an AppImage.

**The game itself has not been played through on Linux yet** (it needs the player's own game files), so this release
is marked as a pre-release. Everything around the game - the start screen, the packaging, the mods, the 2x interface -
is tested.

## Downloads

| | |
|---|---|
| `LetsGoRecomp_0.6.1_x86_64.AppImage` | one file, nothing to install: `chmod +x` it and run it (any 64-bit distribution) |
| `letsgo-recomp_0.6.1_amd64.deb` | Debian 13 / Ubuntu 24.04: `sudo apt install ./letsgo-recomp_0.6.1_amd64.deb` |

Both carry the runtime, the game code generator, the Zig compiler the game code is built with on the player's own
machine, the headers, the window icon and the start screen font. **No game files**: you need your own legally
obtained copy of *Let's Go, Eevee!* or *Pikachu!*, extracted (the folder with `exefs` and `romfs`).

The first time, the launcher asks for that folder, copies it, translates the game's ARM64 code to C and compiles it
for the player's computer (once per game: about 20 minutes on a 20-thread CPU).

## What is in this release

- **The runtime builds and runs on Linux** (Debian 13, Ubuntu 24.04): the code that only compiled on Windows was
  fixed (the missing includes, `SDL_LoadPNG` / `SDL_SavePNG` - which needed SDL3_image, a dependency nothing
  declared - now go through the stb_image copy the project already ships), the linker is no longer forced to be
  `lld`, and the distribution's SDL3 links with `--allow-shlib-undefined`.
- **A Debian package**: the runtime, the game code generator (frozen with PyInstaller, so no Python is needed), the
  Zig compiler, the headers, the icon, the font, the menu entry and the man page. It passes `lintian` without a
  single complaint.
- **An AppImage**: the same, in one file, with the libraries it needs (SDL3, FFmpeg, shaderc) inside. The Vulkan
  loader, the driver's own libraries and the X11 / Wayland / audio stacks stay the system's, so the driver is never
  in the way.
- **Mods install on Linux** (they called the Windows' own `tar.exe`): the archive is unpacked with `bsdtar`, or with
  the system's `tar` when there is no libarchive.
- **The 2x interface on Linux**: the upscaler (nihui's waifu2x-ncnn-vulkan) is downloaded from its Linux release.
- **The display's refresh rate on Linux**: it was unknown outside Windows (the frame generation's "Auto" assumed
  60 Hz); it is now read from the display's mode, so the multiplier follows the screen.
- **The frame generation's grid on Linux**: the compositor's timing (what Windows' DWM gives) has no equivalent here,
  but the driver knows when each window image reached the screen (`VK_KHR_present_wait`) - that is the vertical
  blank that showed it. The in-between images are snapped to the display's refresh like on Windows.
- **The data folder** is `~/.local/share/letsgo-recomp` for both packages, so moving from one to the other keeps the
  saves.

## Known issues on Linux

- **FSR 3.1** (the upscale): only Windows has AMD's library. The in-house upscale (2x / 3x / 4x) and FSR 1 work.
- **Frame generation**: works, but its alignment with the screen is not as precise as on Windows.
- **The game has not been played through yet**: it needs the player's own game files, and the first setup compiles
  the game's code on the player's machine (about 20 minutes).
- **No**: multiple players, Poké Ball Plus, nor the online features (the game stays offline, as on Windows).

## Documentation

- [docs/DEBIAN.md](https://github.com/TetradogOther/letsgo-recomp/blob/feature/linux-debian-port/docs/DEBIAN.md) —
  the Debian package
- [docs/APPIMAGE.md](https://github.com/TetradogOther/letsgo-recomp/blob/feature/linux-debian-port/docs/APPIMAGE.md) —
  the AppImage
- [docs/COMPILAR-LINUX.md](https://github.com/TetradogOther/letsgo-recomp/blob/feature/linux-debian-port/docs/COMPILAR-LINUX.md) —
  building from the source
- [docs/ROADMAP-LINUX-DEB.md](https://github.com/TetradogOther/letsgo-recomp/blob/feature/linux-debian-port/docs/ROADMAP-LINUX-DEB.md) —
  the state of the port

A fan project, not affiliated with Nintendo, The Pokémon Company, Game Freak or Creatures.
