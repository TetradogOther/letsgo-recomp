#!/bin/bash
# tools/fetch_hactool.sh: hactool (the program that reads the console's keys and decrypts the game's content),
# built from source into build/hactool/hactool. It is not in Debian (a circumvention tool does not go into a
# package), so the port asks the user for their own: this is for the packaging, which ships it in the data folder
# (the user can also point the launcher at their own).
#
# The pinned version: SciresM/hactool 1.4.0 (the commit is checked).
#
# Needs: git, make, a C compiler, and the mbedtls submodule (cloned with it).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=https://github.com/SciresM/hactool
COMMIT=3121a5bf08cd81d3a99719feb2cab3b60767afd5   # (the tag 1.4.0)
SRC=build/hactool-src
OUT=build/hactool

if [ -x "$OUT/hactool" ]; then
    echo "build/hactool: already there"
    exit 0
fi

echo "==> hactool (the source, the pinned commit)"
rm -rf "$SRC"
git clone --quiet --recursive "$REPO" "$SRC"
git -C "$SRC" checkout --quiet "$COMMIT"
git -C "$SRC" submodule update --init --recursive --quiet

echo "==> building it"
(cd "$SRC" && cp -n config.mk.template config.mk && make -j"$(nproc)")

rm -rf "$OUT" && mkdir -p "$OUT"
cp "$SRC/hactool" "$OUT/hactool"
chmod 755 "$OUT/hactool"
"$OUT/hactool" --version 2>&1 | head -2 || true
echo "build/hactool: hactool built ($(du -sh "$OUT" | cut -f1))"
