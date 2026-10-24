#!/bin/bash
# tools/linux/build_deb.sh: the Debian package, build/dist/letsgo-recomp-<version>-<arch>.deb
#
# What it needs (Debian 13 "trixie" or Ubuntu 24.04):
#   sudo apt install clang lld make pkg-config python3-venv python3-pip libpython3-dev libsdl3-dev libavformat-dev
#     libavcodec-dev libavutil-dev libswscale-dev libvulkan-dev libshaderc-dev libvulkan-memory-allocator-dev
#     libarchive-tools dpkg-dev file
#
# What it does:
#   1. the runtime (the launcher and everything that stands in for the Switch) - against the distribution's
#      libraries, so the package has no library of its own inside;
#   2. the game code generator, frozen with PyInstaller (build/pkg/helper/lasgen/): the start screen runs it on
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
source tools/linux/stage.sh
pkg_arch

VERSION=$(pkg_app_version)
# The Debian version: the app's version and a revision that changes with every build (the commit and the time), so
# that apt takes the new package over the one already installed. DEB_REVISION=<r> sets it by hand (a release).
if [ -n "${DEB_REVISION:-}" ]; then
    DEB_VERSION="$VERSION-$DEB_REVISION"
else
    HASH=$(git rev-parse --short HEAD 2>/dev/null || echo local)
    DEB_VERSION="$VERSION-1.$HASH.$(date -u +%Y%m%d%H%M)"
fi
STAGE=$PKG_BUILD/stage
OUT=build/dist/letsgo-recomp_${DEB_VERSION}_${PKG_ARCH}.deb

pkg_build_runtime
pkg_build_helper
pkg_fetch_zig
pkg_stage_tree "$STAGE"

# the metadata
mkdir -p "$STAGE/DEBIAN"
sed -e "s/^Version: .*/Version: $DEB_VERSION/" -e "s/^Architecture: .*/Architecture: $PKG_ARCH/" debian/control \
    > "$STAGE/DEBIAN/control"
if [ "$WITH_ZIG" = 0 ]; then
    # no zig in the package: the game code is built with the system's compiler
    sed -i -e 's/libarchive-tools, curl, ca-certificates/clang, lld, libarchive-tools, curl, ca-certificates/' \
        "$STAGE/DEBIAN/control"
fi
# the copyright and the changelog go in the documentation folder (the Debian policy: the ones in DEBIAN/ are only
# for the packages built from a source package, and lintian counts them as unknown control files)
sed "0,/^letsgo-recomp ([^)]*)/s/^letsgo-recomp ([^)]*)/letsgo-recomp ($DEB_VERSION)/" debian/changelog \
    | gzip -9n > "$STAGE/usr/share/doc/letsgo-recomp/changelog.Debian.gz"

echo "==> $OUT"
mkdir -p build/dist
dpkg-deb --root-owner-group --build "$STAGE" "$OUT"
dpkg-deb --info "$OUT" | head -20
ls -la "$OUT"
