#!/bin/bash
# tools/linux/build_container.sh: the Linux packages, built in a container (Debian 13), so the result does not depend
# on what the machine has installed. The checkout is mounted at /src and the packages are written to build/dist/.
#
# Needs podman (or docker):
#   tools/linux/build_container.sh                          # the .deb and the AppImage
#   tools/linux/build_container.sh deb                      # only the .deb
#   tools/linux/build_container.sh appimage                 # only the AppImage
#   tools/linux/build_container.sh deb WITH_ZIG=0           # the environment goes to the build script
set -euo pipefail
cd "$(dirname "$0")/../.."

if command -v podman >/dev/null; then
    ENGINE=podman
elif command -v docker >/dev/null; then
    ENGINE=docker
else
    echo "build_container: podman or docker needed"; exit 1
fi
RUN="$ENGINE run --rm"

WHAT=${1:-all}
[ $# -gt 0 ] && shift || true

echo "==> the image (Debian 13)"
$ENGINE build -q -t localhost/letsgo-recomp-build:debian13 -f tools/linux/Containerfile tools/linux >/dev/null

# the container runs with the user's own id, so the files it writes in the checkout belong to the user (and not to
# root): HOME and the caches go to a temporary folder, which everyone can write
build() {
    $RUN -v "$PWD:/src" -w /src \
        -u "$(id -u):$(id -g)" \
        -e HOME=/tmp -e TMPDIR=/tmp \
        -e ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache -e ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache \
        localhost/letsgo-recomp-build:debian13 "$@"
}

case "$WHAT" in
    deb) build bash tools/linux/build_deb.sh "$@" ;;
    appimage) build bash tools/linux/build_appimage.sh "$@" ;;
    all)
        build bash tools/linux/build_deb.sh "$@"
        build bash tools/linux/build_appimage.sh "$@"
        ;;
    *) echo "build_container: what to build? (deb, appimage, all)"; exit 1 ;;
esac

ls -la build/dist/
