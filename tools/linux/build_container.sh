#!/bin/bash
# tools/linux/build_container.sh: the Debian package, built in a container (Debian 13), so the result does not depend
# on what the machine has installed. The checkout is mounted at /src and the package is written to build/dist/.
#
# Needs podman (or docker):
#   tools/linux/build_container.sh
#   tools/linux/build_container.sh WITH_ZIG=0 WITH_HELPER=0
set -euo pipefail
cd "$(dirname "$0")/../.."

if command -v podman >/dev/null; then
    RUN="podman run --rm"
elif command -v docker >/dev/null; then
    RUN="docker run --rm"
else
    echo "build_container: podman or docker needed"; exit 1
fi

echo "==> the image (Debian 13)"
podman build -q -t localhost/letsgo-recomp-build:debian13 -f tools/linux/Containerfile tools/linux >/dev/null

echo "==> the package"
$RUN -v "$PWD:/src" -w /src -e HOME=/tmp -e ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache \
    -e ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache localhost/letsgo-recomp-build:debian13 \
    bash tools/linux/build_deb.sh "${@:-}"

ls -la build/dist/
