#!/bin/bash
# tools/linux/build_appimage.sh: the AppImage, build/dist/letsgo-recomp-<version>-<arch>.AppImage
#
# One file with everything the player needs (the runtime, the game code generator, the Zig compiler that builds the
# game code on their machine, the headers, the icon and the font). It runs without being installed and without
# anything else on the system but a Vulkan 1.3 driver (and the usual desktop libraries).
#
# What it needs:
#   sudo apt install clang lld make pkg-config python3-venv pipx libsdl3-dev libavformat-dev libavcodec-dev
#     libavutil-dev libswscale-dev libvulkan-dev libshaderc-dev libvulkan-memory-allocator-dev libarchive-tools
#     squashfs-tools patchelf file
#
# What it does:
#   1. the runtime (the launcher and everything that stands in for the Switch);
#   2. the game code generator, frozen with PyInstaller (the start screen runs it on the player's own game files to
#      translate them into C);
#   3. zig: the compiler the start screen builds that C with on the player's machine;
#   4. the tree (the AppDir) and the libraries the program needs, bundled (BUNDLE_LIBS=0 leaves them to the system);
#   5. the AppImage: the runtime with the tree's squashfs image appended.
#
# The game's own files are not in the AppImage: the player brings their own copy.
#
# Environment: WITH_ZIG=0 (no zig inside: the game code is built with the system's clang), WITH_HELPER=0 (no
# generator inside: it only shows the start screen), BUNDLE_LIBS=0 (the libraries are the system's, as in the .deb),
# JOBS=<n>, ARCH=amd64|arm64 (the default: this machine's).
set -euo pipefail
cd "$(dirname "$0")/../.."

WITH_ZIG=${WITH_ZIG:-1}
WITH_HELPER=${WITH_HELPER:-1}
BUNDLE_LIBS=${BUNDLE_LIBS:-1}
JOBS=${JOBS:-$(nproc)}
DEPS=${DEPS:-}
source tools/linux/stage.sh
pkg_arch

VERSION=$(pkg_app_version)
# the AppImage's architecture name (x86_64 / aarch64), not the distribution's (amd64 / arm64)
case "$PKG_ARCH" in
    amd64) AI_ARCH=x86_64 ;;
    arm64) AI_ARCH=aarch64 ;;
esac
OUT=build/dist/letsgo-recomp_${VERSION}_${AI_ARCH}.AppImage
APPDIR=build/appimage/letsgo-recomp.AppDir

pkg_build_runtime
pkg_build_helper
pkg_fetch_zig
pkg_stage_tree "$APPDIR"

# 4. the libraries, inside (so the AppImage runs on a system without SDL3 or FFmpeg)
if [ "$BUNDLE_LIBS" = 1 ]; then
    echo "==> the libraries (inside)"
    bash tools/linux/bundle_libs.sh "$APPDIR/usr/bin/letsgo-recomp" "$APPDIR/usr/lib"
    if [ -x "$APPDIR/usr/lib/$RT_PKG_DIR/lasgen/lasgen" ]; then
        bash tools/linux/bundle_libs.sh "$APPDIR/usr/lib/$RT_PKG_DIR/lasgen/lasgen" "$APPDIR/usr/lib/$RT_PKG_DIR/lasgen"
    fi
else
    echo "==> the libraries: the system's (BUNDLE_LIBS=0)"
fi

# the entry point: the AppImage runtime runs this
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
# AppRun: the entry point of the AppImage (the AppImage runtime runs this).
HERE="$(dirname "$(readlink -f "$0")")"
export ARGV0=letsgo-recomp
exec "$HERE/usr/bin/letsgo-recomp" "$@"
EOF
chmod 755 "$APPDIR/AppRun"

# the desktop entry and the icon, at the root of the AppDir (the desktop integration needs them there)
cp debian/org.tetradogother.letsgo-recomp.desktop "$APPDIR/org.tetradogother.letsgo-recomp.desktop"
cp docs/icon/hicolor/256x256/apps/letsgo-recomp.png "$APPDIR/letsgo-recomp.png"
cp docs/icon/icon.svg "$APPDIR/letsgo-recomp.svg"

# 5. the AppImage: the runtime with the tree's squashfs image appended
echo "==> the AppImage runtime"
APPIMAGE_ARCH=$AI_ARCH bash tools/fetch_appimage_runtime.sh
RUNTIME=build/appimage/runtime-$AI_ARCH
command -v mksquashfs >/dev/null || { echo "build_appimage: squashfs-tools is needed (mksquashfs)"; exit 1; }

echo "==> the squashfs image"
rm -f build/appimage/appimage.squashfs
mksquashfs "$APPDIR" build/appimage/appimage.squashfs -root-owned -noappend -comp xz -b 128K >/dev/null

echo "==> $OUT"
mkdir -p build/dist
cat "$RUNTIME" build/appimage/appimage.squashfs > "$OUT"
chmod 755 "$OUT"
ls -la "$OUT"
echo "build_appimage: $OUT"
