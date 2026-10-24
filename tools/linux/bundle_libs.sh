#!/bin/bash
# tools/linux/bundle_libs.sh: the libraries the runtime needs, inside the AppImage (so it runs on a system that has
# no SDL3 or FFmpeg installed).
#
#   tools/linux/bundle_libs.sh <program> <lib folder> [rpath]
#
# What it does: reads the program's dependencies (ldd), copies them into the folder, and points the program at them
# (patchelf, with a RUNPATH of $ORIGIN, so only our own programs use them - the driver's own libraries are the
# system's). The rpath is the one the program gets ($ORIGIN/../lib by default: the libraries one folder up).
#
# What it does NOT bundle:
#   - the C library and the loader (the system's: the AppImage is built on one distribution and runs on others);
#   - the Vulkan loader and the graphics driver's libraries (libvulkan, libGL, libEGL, libdrm, libgbm, libnvidia...):
#     the loader is what talks to the driver, and the driver must be the system's;
#   - the X11 / Wayland and the audio stacks (libX11, libwayland, libasound, libpulse...): they are on every
#     desktop, and the system's are the ones that match the session.
# What is bundled: SDL3, the FFmpeg libraries, shaderc and their own dependencies (the ones that are big and
# version-specific).
set -euo pipefail

BIN=${1:?the program}
LIBDIR=${2:?the folder for the libraries}
RPATH=${3:-\$ORIGIN/../lib}   # (the libraries' own: $ORIGIN, so each one finds the others)

# the libraries that stay on the system (the patterns are matched against the file name)
keep_on_system() {
    case "$1" in
        ld-linux*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libresolv.so*|libutil.so*|libnsl.so*) return 0 ;;
        libvulkan*|libGL*|libEGL*|libGLX*|libOpenCL*|libnvidia*|libamd*|libdrm*|libgbm*|libglapi*|libGLX*) return 0 ;;
        libwayland-*|libxkbcommon*|libX11*|libXext*|libXi*|libXcursor*|libXfixes*|libXrandr*|libXrender*|libXss*) return 0 ;;
        libXau*|libXdmcp*|libxcb*|libasound*|libpulse*|libpulsecommon*|libsndio*|libjack*|libudev*) return 0 ;;
        *) return 1 ;;
    esac
}

command -v patchelf >/dev/null || { echo "bundle_libs: patchelf is needed"; exit 1; }
mkdir -p "$LIBDIR"

# the dependencies (the resolved paths), of the program and of everything it loads
collect() {
    ldd "$1" 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i}'
}

COPIED=0
SKIPPED=0
for lib in $(collect "$BIN" | sort -u); do
    base=$(basename "$lib")
    if keep_on_system "$base"; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    [ -e "$lib" ] || continue
    # the real file (the one the system's path points to): copied as it is, a link would dangle in the bundle
    real=$(readlink -f "$lib")
    [ -f "$real" ] || continue
    file=$(basename "$real")
    cp -a "$real" "$LIBDIR/$file" 2>/dev/null || continue
    COPIED=$((COPIED + 1))
    # the SONAME may differ from the file name (libfoo.so.1.2.3 with SONAME libfoo.so.1): the loader looks for
    # the SONAME, so it gets a name of its own
    soname=$(patchelf --print-soname "$real" 2>/dev/null || true)
    if [ -n "$soname" ] && [ "$soname" != "$file" ]; then
        ln -sf "$file" "$LIBDIR/$soname"
    fi
done

# the program and the libraries: the RUNPATH ($ORIGIN) - the loader looks there before the system's cache, and the
# driver's libraries are not affected by it (a RUNPATH is not inherited by the dependencies)
patchelf --set-rpath "$RPATH" "$BIN"
for f in "$LIBDIR"/*.so*; do
    [ -e "$f" ] || continue
    [ -L "$f" ] && continue
    patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

echo "bundle_libs: $COPIED libraries bundled, $SKIPPED left to the system ($(du -sh "$LIBDIR" | cut -f1))"
