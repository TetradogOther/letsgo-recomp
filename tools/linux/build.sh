#!/bin/bash
# tools/linux/build.sh: the .deb and the AppImage, in one go.
#
#   tools/linux/build.sh                 # both, on this machine
#   tools/linux/build.sh --deb           # only the .deb
#   tools/linux/build.sh --appimage      # only the AppImage
#   tools/linux/build.sh --container     # both, in the Debian 13 container (what the CI does)
#   DEB_REVISION=1 tools/linux/build.sh  # a fixed package version (a release)
#
# The runtime, the game code generator and the Zig compiler are built once and used by both packages (they share
# the tree: tools/linux/stage.sh), so the second package costs a couple of minutes, not another half hour.
#
# What it needs on this machine (Debian 13 or Ubuntu 24.04):
#   sudo apt install clang lld make pkg-config python3-venv python3-pip libpython3-dev libsdl3-dev libavformat-dev \
#     libavcodec-dev libavutil-dev libswscale-dev libvulkan-dev libshaderc-dev libvulkan-memory-allocator-dev \
#     libarchive-tools squashfs-tools patchelf file
# (with --container, only podman or docker is needed)
set -euo pipefail
cd "$(dirname "$0")/../.."

WHAT=both
IN_CONTAINER=0
for a in "$@"; do
    case "$a" in
        --deb) WHAT=deb ;;
        --appimage) WHAT=appimage ;;
        --both) WHAT=both ;;
        --container) IN_CONTAINER=1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "build: unknown option ($a)"; exit 1 ;;
    esac
done

echo "==> the packages: $WHAT$([ "$IN_CONTAINER" = 1 ] && echo " (in the container)"; )"

if [ "$IN_CONTAINER" = 1 ]; then
    case "$WHAT" in
        deb) tools/linux/build_container.sh deb ;;
        appimage) tools/linux/build_container.sh appimage ;;
        both) tools/linux/build_container.sh ;;
    esac
else
    # the runtime, the generator and the compiler: built once, used by both (they check if they are there)
    source tools/linux/stage.sh
    pkg_arch
    pkg_build_runtime
    pkg_build_helper
    pkg_fetch_zig
    case "$WHAT" in
        deb) tools/linux/build_deb.sh ;;
        appimage) tools/linux/build_appimage.sh ;;
        both)
            tools/linux/build_deb.sh
            tools/linux/build_appimage.sh
            ;;
    esac
fi

echo
echo "==> what is in build/dist"
ls -la build/dist/
for f in build/dist/*.deb build/dist/*.AppImage; do
    [ -f "$f" ] || continue
    printf '    %s  %s\n' "$(sha256sum "$f" | cut -c1-16)" "$(basename "$f")"
done
