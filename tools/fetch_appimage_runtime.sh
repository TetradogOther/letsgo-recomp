#!/bin/bash
# tools/fetch_appimage_runtime.sh: the AppImage runtime (the small ELF that mounts the squashfs image and runs it).
# Fetched from the AppImageKit release, checked against a pinned hash and kept in build/appimage/.
#
# The AppImage is the runtime with the squashfs image appended: the runtime mounts it (with FUSE, or by extracting
# it when FUSE is not there) and runs the AppRun inside.
#
#   tools/fetch_appimage_runtime.sh            # for this machine's architecture
#   APPIMAGE_ARCH=aarch64 tools/fetch_appimage_runtime.sh
#
# The hash is of the "continuous" release, which upstream updates from time to time: when it changes, the build
# says so and the new hash goes here (or in APPIMAGE_RUNTIME_SHA256, for a build that only needs it once).
set -euo pipefail
cd "$(dirname "$0")/.."

case "${APPIMAGE_ARCH:-$(uname -m)}" in
    x86_64|amd64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    *) echo "fetch_appimage_runtime: no AppImage runtime for $ARCH"; exit 1 ;;
esac

case "$ARCH" in
    x86_64)  SHA=66f5b22f035022b8bdebb54c066aa6edc7b5db282fe6cdb372e7965f80772557 ;;
    aarch64) SHA=${APPIMAGE_RUNTIME_SHA256:-} ;;
esac
[ -n "$SHA" ] || { echo "fetch_appimage_runtime: pin the sha256 of runtime-$ARCH first"; exit 1; }

DL=build/appimage
mkdir -p "$DL"
RUNTIME=$DL/runtime-$ARCH
URL=https://github.com/AppImage/AppImageKit/releases/download/continuous/runtime-$ARCH
[ -f "$RUNTIME" ] || curl -fL --proto '=https' -o "$RUNTIME" "$URL"
GOT=$( (shasum -a 256 2>/dev/null || sha256sum) < "$RUNTIME" | cut -d' ' -f1)
if [ "$GOT" != "$SHA" ]; then
    echo "runtime-$ARCH: sha256 $GOT, expected $SHA"
    echo "(upstream updated the runtime: put the new hash here, or in APPIMAGE_RUNTIME_SHA256)"
    exit 1
fi
chmod 755 "$RUNTIME"
echo "build/appimage: the AppImage runtime for $ARCH ($(stat -c %s "$RUNTIME") bytes)"
