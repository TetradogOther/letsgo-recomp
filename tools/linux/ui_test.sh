#!/bin/bash
# tools/linux/ui_test.sh: the e2e UI test of the start screen (the launcher), the way tools/repro.sh replays the
# game: a scripted run, the captures, a contact sheet and the log checked.
#
#   tools/linux/ui_test.sh [executable] [out folder]
#
# It walks through every page of the start screen (Game, Graphics, Image and sound, Controls, Mods) and the key
# binding capture (the Controls page waiting for a key), takes a picture of each one, and fails if any run writes
# an error in the log.
#
# The executable: the AppImage, the .deb's program, or a build in the source tree. With an AppImage and no FUSE
# on this machine, it extracts itself and runs (APPIMAGE_EXTRACT_AND_RUN).
#
# What it leaves: <out>/tab-N.png, <out>/keys.png, <out>/contact.png and <out>/report.txt.
set -uo pipefail
cd "$(dirname "$0")/../.."

EXE=${1:-./build/dist/letsgo-recomp_0.6.0_x86_64.AppImage}
OUT=${2:-build/ui-test}
[ -x "$EXE" ] || { echo "ui_test: $EXE not there"; exit 1; }

# the pages of the start screen (runtime/ui/launcher_lg.mm): Game, Graphics, Image and sound, Controls, Mods
PAGES=("Game" "Graphics" "Image" "Controls" "Mods")

# the paths are absolute: the app changes to its data folder before it writes
OUT=$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)/$(basename "$OUT")
EXE=$(realpath "$EXE")
rm -rf "$OUT"
mkdir -p "$OUT"
export APPIMAGE_EXTRACT_AND_RUN=1   # (an AppImage without FUSE: it extracts itself and runs)

fail=0
report="$OUT/report.txt"
: > "$report"

shot() {  # shot <name> <tab> [keys]
    local name=$1 tab=$2 keys=${3:-}
    local data="$OUT/data-$name"
    rm -rf "$data" && mkdir -p "$data"
    # (env: an assignment that comes from an expansion is not an assignment for the shell)
    env LARECOMP_DATA_ROOT="$data" \
        LARECOMP_LAUNCHER_TAB="$tab" \
        LARECOMP_LAUNCHER_SHOT=90 \
        LARECOMP_SHOT_PATH="$OUT/$name.png" \
        ${keys:+LARECOMP_LAUNCHER_KEYS=$keys} \
        timeout 120 "$EXE" >"$OUT/$name.out" 2>&1
    local rc=$?
    local png="$OUT/$name.png"
    local log="$data/lasrecomp.log"
    local errs=""
    [ -f "$log" ] && errs=$(grep -E "FATAL|error:|failed" "$log" | grep -v "the game code hasn't been built" || true)
    local ok=1
    {
        if [ -f "$png" ]; then
            echo "PASS: $name drew ($(stat -c %s "$png") bytes)"
        else
            echo "FAIL: $name did not draw (rc=$rc)"
            ok=0
        fi
        if [ -n "$errs" ]; then
            echo "FAIL: $name: the log has an error:"
            echo "$errs" | sed 's/^/    /'
            ok=0
        fi
    } | tee -a "$report"
    [ "$ok" = 1 ] || fail=1     # (the pipe above runs in a subshell: the flag is set here)
    rm -rf "$data"
}

echo "==> the start screen: $EXE"
for i in "${!PAGES[@]}"; do
    echo "--- ${PAGES[$i]}"
    shot "tab-$i" "$i"
done
echo "--- the key binding capture"
shot "keys" 3 1

echo "==> the contact sheet"
if ! command -v ffmpeg >/dev/null; then
    echo "    (ffmpeg is not there)"
else
    pics=("$OUT"/tab-*.png)
    [ -f "$OUT/keys.png" ] && pics+=("$OUT/keys.png")
    if [ ! -f "${pics[0]}" ]; then
        echo "    (no pictures to put together)"
    else
        python3 tools/contact_sheet.py "$OUT/contact.png" "${pics[@]}" >/dev/null 2>&1 \
            && echo "    $OUT/contact.png" || echo "    (could not be made)"
    fi
fi

{
    echo
    if [ "$fail" = 0 ]; then echo "READY"; else echo "NOT READY"; fi
} | tee -a "$report"
exit $fail
