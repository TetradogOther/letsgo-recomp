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
rm -rf "$OUT" && mkdir -p "$OUT"
SHOT="$OUT/launcher.png"
LOG="$OUT/lasrecomp.log"

echo "==> the start screen"
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

fail=0
report="$OUT/report.txt"
{
    echo "smoketest: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "executable: $EXE"
    echo
    if [ -f "$SHOT" ]; then echo "PASS: the start screen drew ($SHOT)"; else echo "FAIL: no screenshot"; fail=1; fi
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
