#!/bin/bash
# tools/linux/smoketest.sh: a quick check that the built runtime works on this machine - the start screen opens and
# draws, the Vulkan device is there, and the log has no error. It does not need the game's files.
#
#   tools/linux/smoketest.sh [build/lasrecomp]
#
# What it leaves: build/smoke/ (the screenshot, the log and report.txt).
set -euo pipefail
cd "$(dirname "$0")/../.."

EXE=${1:-build/linuxtest/lasrecomp}
[ -x "$EXE" ] || { echo "smoketest: $EXE not there (make first)"; exit 1; }
OUT=$PWD/build/smoke
# (the folder can be left by a container's root, or by another user: then the test goes to a temporary folder)
if ! rm -rf "$OUT" 2>/dev/null || ! mkdir -p "$OUT" 2>/dev/null; then
    OUT=$(mktemp -d)
    echo "smoketest: build/smoke is not writable, using $OUT"
fi
SHOT="$OUT/launcher.png"
LOG="$OUT/lasrecomp.log"

echo "==> the start screen"
# (an AppImage without FUSE on this machine: it extracts itself and runs)
export APPIMAGE_EXTRACT_AND_RUN=1
# (the paths are absolute: the app changes to its data folder before it writes)
LARECOMP_LAUNCHER_SHOT=60 LARECOMP_SHOT_PATH="$SHOT" "$EXE" >/dev/null 2>&1 || true
if [ -f "$SHOT" ]; then
    echo "    the screenshot: $SHOT ($(stat -c %s "$SHOT") bytes)"
else
    echo "    FAIL: no screenshot"
fi

# the log: where it is depends on how it was started (a terminal: stderr; else the data folder)
DATA=$(mktemp -d)
# (in a subshell: the app ends with SIGABRT when the game code isn't there, and the shell would say so)
bash -c 'LARECOMP_DATA_ROOT="$1" "$2" --play >/dev/null 2>&1 || true' _ "$DATA" "$EXE" 2>/dev/null
if [ -f "$DATA/lasrecomp.log" ]; then cp "$DATA/lasrecomp.log" "$LOG"; fi
rm -rf "$DATA"

# the game code builder: a folder with a fake main.npdm (the program id of the Eevee) and a fake romfs: the setup
# looks for the game, accepts it and goes for the builder - which has to be there, with the compiler (the log says
# which). The game code itself is not built (the fake main is not a program), so the setup fails after that: what
# matters here is that the builder and the compiler were found.
GAME=$(mktemp -d)
mkdir -p "$GAME/exefs" "$GAME/romfs/bin/message" "$GAME/data"
python3 tools/linux/make_fake_npdm.py eevee "$GAME/exefs/main.npdm" >/dev/null
printf 'not a program\n' > "$GAME/exefs/main"
printf 'x\n' > "$GAME/romfs/bin/message/data.bin"
LARECOMP_DATA_ROOT="$GAME/data" LARECOMP_SETUP_DIR="$GAME" LARECOMP_LAUNCHER_SHOT=300 \
    LARECOMP_SHOT_PATH="$GAME/shot.png" timeout 60 "$EXE" >/dev/null 2>&1 || true
BUILDER=$(grep -o "\[gamebuild\] generator [^,]*" "$GAME/data/lasrecomp.log" 2>/dev/null | head -1)
COMPILER=$(grep -o "\[gamebuild\] generator .*, compiler [^,]*" "$GAME/data/lasrecomp.log" 2>/dev/null | head -1)
rm -rf "$GAME"

fail=0
report="$OUT/report.txt"
{
    echo "smoketest: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "executable: $EXE"
    echo
    if [ -f "$SHOT" ]; then echo "PASS: the start screen drew ($SHOT)"; else echo "FAIL: no screenshot"; fail=1; fi
    if [ -n "$COMPILER" ]; then
        echo "PASS: the game code builder and the compiler are there"
        echo "    $COMPILER" | sed 's/^/    /'
    else
        echo "FAIL: the game code builder (or the compiler) is missing from this copy"
        fail=1
    fi
    if [ -f "$LOG" ]; then
        echo "PASS: the log was written ($LOG)"
        grep -E "^\[vk\] gpu|^\[vk\] using" "$LOG" | sed 's/^/    /' || true
        # (without the game's files the game can't start: that error is expected here)
        errs=$(grep -E "FATAL|error:|failed" "$LOG" | grep -v "the game code hasn't been built" || true)
        if [ -n "$errs" ]; then
            echo "FAIL: the log has an error:"
            echo "$errs" | sed 's/^/    /'
            fail=1
        else
            echo "PASS: no error in the log"
        fi
    else
        echo "WARN: no log (the game files are not set up: the log stops at the setup)"
    fi
    if [ "$fail" = 0 ]; then echo; echo "READY"; else echo; echo "NOT READY"; fi
} | tee "$report"
exit $fail
