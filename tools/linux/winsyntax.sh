#!/bin/bash
# tools/linux/winsyntax.sh: compiles the runtime for Windows (syntax only) from Linux, to check that the code
# shared with the Windows build still compiles there. The changes of the Linux port touch shared files (the PNG
# reader/writer, the mods, the launcher's icon), and the Windows build needs MSYS2 - this needs only clang and the
# mingw headers.
#
#   sudo apt install clang mingw-w64-x86-64-dev mingw-w64-common
#   tools/linux/winsyntax.sh
#
# What it checks: every source of the runtime, with the Windows defines. It does not link (no SDL3 for Windows
# here) and it does not build the game code.
set -euo pipefail
cd "$(dirname "$0")/../.."

# the mingw headers (Debian: mingw-w64-x86-64-dev + mingw-w64-common)
MINGW=${MINGW:-/usr/x86_64-w64-mingw32}
[ -f "$MINGW/include/windows.h" ] || { echo "winsyntax: the mingw headers are not there ($MINGW/include)"; exit 1; }
# SDL3's headers (the same as the runtime's, on both systems)
SDL3=${SDL3:-/usr/include/SDL3}
[ -f "$SDL3/SDL.h" ] || { echo "winsyntax: the SDL3 headers are not there ($SDL3)"; exit 1; }

FLAGS="--target=x86_64-w64-mingw32 -isystem $MINGW/include -isystem $SDL3/.. -isystem $SDL3
 -D_FILE_OFFSET_BITS=64 -D_POSIX_THREAD_SAFE_FUNCTIONS -D_CRT_RAND_S -DWIN32_LEAN_AND_MEAN -DNOMINMAX
 -Iruntime -Iruntime/nvn -Iruntime/platform -Ithird_party/imgui -Ithird_party/imgui/backends
 -Ithird_party/fidelityfx/include"

SRC="runtime/platform/windows.c runtime/paths.c runtime/png.c runtime/mods.c runtime/ui2x.c
 runtime/nvn/vulkan/device.c runtime/nvn/vulkan/fsr3.cpp runtime/nvn/vulkan/exec.c runtime/gamebuild.c
 runtime/gamelib.c runtime/hle/movie.c runtime/ui/launcher_lg.mm runtime/ui/menu.mm runtime/ui/settings_ui.mm
 runtime/ui/osk.mm runtime/services/fs.c runtime/services/time.c runtime/romfs_build.c runtime/hle/heaps.c
 runtime/hle/input.c runtime/kernel.c runtime/dispatch.c runtime/ipc.c runtime/main.c runtime/settings.c"

fail=0
for f in $SRC; do
    case "$f" in
        *.cpp|*.mm) CC="clang++ -std=c++17 -x c++" ;;
        *) CC="clang" ;;
    esac
    # the C++ standard library's headers are not in the mingw-w64 headers (they come with the GCC C++ runtime:
    # gcc-mingw-w64-x86-64): the files that need them are skipped without it
    if [ ! -f "$MINGW/include/c++/v1/atomic" ] && [ ! -f "$MINGW/include/c++/12/atomic" ] &&
       grep -q "#include <atomic>" "$f" 2>/dev/null; then
        printf "SKIP %s (no C++ standard library headers)\n" "$f"
        continue
    fi
    if $CC $FLAGS -fsyntax-only "$f" 2>/tmp/winsyntax.err; then
        printf "OK   %s\n" "$f"
    else
        printf "FAIL %s\n" "$f"
        head -14 /tmp/winsyntax.err
        fail=1
    fi
done
[ "$fail" = 0 ] && echo "winsyntax: the runtime compiles for Windows"
exit $fail
