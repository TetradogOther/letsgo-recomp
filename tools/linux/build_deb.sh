#!/bin/bash
# tools/linux/build_deb.sh: the Debian package, build/dist/letsgo-recomp-<version>-<arch>.deb
#
# What it needs (Debian 13 "trixie" or Ubuntu 24.04):
#   sudo apt install clang lld make pkg-config python3-venv pipx libsdl3-dev libavformat-dev libavcodec-dev
#     libavutil-dev libswscale-dev libvulkan-dev libshaderc-dev libvulkan-memory-allocator-dev libarchive-tools
#     dpkg-dev file
#
# What it does:
#   1. the runtime (the launcher and everything that stands in for the Switch) - against the distribution's
#      libraries, so the package has no library of its own inside;
#   2. the game code generator, frozen with PyInstaller (build/deb/helper/lasgen/): the start screen runs it on
#      the player's own game files to translate them into C;
#   3. zig (build/zig/): the compiler the start screen builds that C with on the player's machine (as on
#      Windows). WITH_ZIG=0 leaves it out and the package depends on clang instead;
#   4. the headers the game code is built against (runtime/cpu.h, simd.h, ...) and the assets (the icon, the
#      start screen's font);
#   5. the tree, and dpkg-deb.
#
# The game's own files are not in the package: the player brings their own copy.
#
# Environment: WITH_ZIG=0 (no zig in the package), WITH_HELPER=0 (no generator in the package: the package then
# only shows the launcher), JOBS=<n> (how many compilers at once), ARCH=amd64|arm64 (the default: this machine's).
set -euo pipefail
cd "$(dirname "$0")/../.."

WITH_ZIG=${WITH_ZIG:-1}
WITH_HELPER=${WITH_HELPER:-1}
JOBS=${JOBS:-$(nproc)}
DEPS=${DEPS:-}  # a prefix with SDL3 / FFmpeg / shaderc (the distribution's, by default: empty)
ARCH=${ARCH:-$(dpkg --print-architecture)}
case "$ARCH" in
    amd64) ZIG_ARCH=x86_64; DEB_ARCH=amd64 ;;
    arm64) ZIG_ARCH=aarch64; DEB_ARCH=arm64 ;;
    *) echo "build_deb: ARCH $ARCH not supported (amd64, arm64)"; exit 1 ;;
esac
VERSION=$(sed -n 's/^#define RT_APP_VERSION "\(.*\)".*/\1/p' runtime/paths.h)
B=build/deb
STAGE=$B/stage
OUT=build/dist/letsgo-recomp_${VERSION}_${DEB_ARCH}.deb

echo "==> the runtime (build/deb/obj)"
make -j"$JOBS" LD= DEPS="$DEPS" B=$B/obj "$B/obj/lasrecomp"

if [ "$WITH_HELPER" = 1 ]; then
    if [ ! -x "$B/helper/lasgen/lasgen" ]; then
        echo "==> the game code generator (PyInstaller)"
        python3 -m venv "$B/venv"
        "$B/venv/bin/pip" install -q --upgrade pip
        "$B/venv/bin/pip" install -q capstone unicorn lz4 pyinstaller
        "$B/venv/bin/python" -m PyInstaller --noconfirm --clean --log-level WARN \
            --distpath "$B/helper" --workpath "$B/pyinstaller" tools/lasgen.spec
    fi
fi

if [ "$WITH_ZIG" = 1 ]; then
    echo "==> zig (the compiler of the game code)"
    ZIG_TARGET=$ZIG_ARCH-linux tools/fetch_zig.sh
fi

echo "==> the package tree"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/share/letsgo-recomp" "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/doc/letsgo-recomp" "$STAGE/usr/share/icons/hicolor/scalable/apps" \
         "$STAGE/usr/share/icons/hicolor/1024x1024/apps" "$STAGE/usr/share/man/man1"
cp "$B/obj/lasrecomp" "$STAGE/usr/bin/letsgo-recomp"
chmod 755 "$STAGE/usr/bin/letsgo-recomp"

# what the program ships: the generator, the compiler and the headers the game code is built against
if [ "$WITH_HELPER" = 1 ]; then
    cp -R "$B/helper/lasgen" "$STAGE/usr/share/letsgo-recomp/"
    chmod -R a+rX "$STAGE/usr/share/letsgo-recomp/lasgen"
fi
if [ "$WITH_ZIG" = 1 ]; then
    cp -R build/zig "$STAGE/usr/share/letsgo-recomp/zig"
    chmod -R a+rX "$STAGE/usr/share/letsgo-recomp/zig"
fi
mkdir -p "$STAGE/usr/share/letsgo-recomp/gamelib-src"
cp runtime/cpu.h runtime/simd.h runtime/simd_fp.h runtime/gamelib.h tools/gamelib_entry.c \
   runtime/hle/hle_symbols.txt "$STAGE/usr/share/letsgo-recomp/gamelib-src/"
cp docs/icon/icon_1024.png "$STAGE/usr/share/letsgo-recomp/icon.png"
cp docs/icon/icon.svg "$STAGE/usr/share/icons/hicolor/scalable/apps/letsgo-recomp.svg"
cp docs/icon/icon_1024.png "$STAGE/usr/share/icons/hicolor/1024x1024/apps/letsgo-recomp.png"
cp third_party/fonts/Baloo2/Baloo2-SemiBold.ttf "$STAGE/usr/share/letsgo-recomp/"
cp third_party/fonts/Baloo2/OFL.txt "$STAGE/usr/share/letsgo-recomp/Baloo2-OFL.txt"
cp LICENSE "$STAGE/usr/share/doc/letsgo-recomp/LICENSE.txt"
cp LICENSE-LASRecomp "$STAGE/usr/share/doc/letsgo-recomp/LICENSE-LASRecomp.txt"
cp docs/release-README.txt "$STAGE/usr/share/doc/letsgo-recomp/README.txt"
cp debian/letsgo-recomp.desktop "$STAGE/usr/share/applications/"
cp debian/letsgo-recomp.1 "$STAGE/usr/share/man/man1/"

# the metadata
sed -e "s/^Version: .*/Version: $VERSION-1/" -e "s/^Architecture: .*/Architecture: $DEB_ARCH/" debian/control \
    > "$STAGE/DEBIAN/control"
if [ "$WITH_ZIG" = 0 ]; then
    # no zig in the package: the game code is built with the system's compiler
    sed -i -e 's/libarchive-tools, curl, ca-certificates/clang, lld, libarchive-tools, curl, ca-certificates/' \
        "$STAGE/DEBIAN/control"
fi
cp debian/copyright "$STAGE/DEBIAN/copyright"
gzip -9nc debian/changelog > "$STAGE/DEBIAN/changelog.Debian.gz"
chmod 644 "$STAGE/DEBIAN/"*
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/usr/bin/letsgo-recomp"

echo "==> $OUT"
mkdir -p build/dist
dpkg-deb --root-owner-group --build "$STAGE" "$OUT"
dpkg-deb --info "$OUT" | head -20
ls -la "$OUT"
