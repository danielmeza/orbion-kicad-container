#!/bin/sh
# Photograph a KiCad editor running headless, and say what windows are on the display.
#
#   kicad-screenshot <file.kicad_pcb|.kicad_sch> <out.png> [--wait SECONDS] [--click X,Y]...
#
# WHY THIS EXISTS. When KiCad's IPC API answers "KiCad is not ready to reply", the cause is
# almost always a MODAL DIALOG holding the main loop — and nothing in any log says so. The
# editor's stderr under Xvfb is one repeated `Xlib: extension "XFree86-VidModeExtension"
# missing` line and an AT-SPI warning, neither of which is the fault. MEASURED 2026-09-07:
# 30 s of retries against a socket that existed and accepted connections, diagnosed in one
# screenshot as KiCad 10's start wizard sitting on top of pcbnew.
#
# Reading the screen is the only honest instrument for a GUI. Use it before theorising.
#
# --click is by COORDINATE because an Xvfb display has NO WINDOW MANAGER: nothing takes
# input focus, so `xdotool key` goes nowhere, while a pointer click lands on whatever window
# is under it. That is measured too — six Return presses did nothing and six clicks on the
# Next button walked the whole wizard.
set -eu

[ $# -ge 2 ] || { echo "usage: kicad-screenshot <file> <out.png> [--wait N] [--click X,Y]..." >&2; exit 2; }

DOC=$1; OUT=$2; shift 2
WAIT=12
CLICKS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --wait)  WAIT=$2; shift 2 ;;
        --click) CLICKS="$CLICKS $2"; shift 2 ;;
        *) echo "kicad-screenshot: unknown argument: $1" >&2; exit 2 ;;
    esac
done

. /usr/local/bin/kicad-flavor

case "$DOC" in
    *.kicad_sch) APP="eeschema$KICAD_SUFFIX" ;;
    *.kicad_pcb) APP="pcbnew$KICAD_SUFFIX" ;;
    *) echo "kicad-screenshot: $DOC is neither a .kicad_pcb nor a .kicad_sch" >&2; exit 2 ;;
esac
[ -f "$DOC" ] || { echo "kicad-screenshot: no such file: $DOC" >&2; exit 2; }

kicad-first-run >&2

# A lock left by a killed session of ours puts up a modal that blocks everything. See
# kicad-unlock: only a lock carrying our own fixed hostname is removed.
kicad-unlock "$DOC" || true

DISPLAY_NUM="${ORBION_SHOT_DISPLAY:-77}"
LOG="${TMPDIR:-/tmp}/kicad-screenshot.log"

Xvfb ":$DISPLAY_NUM" -screen 0 "${ORBION_SHOT_GEOMETRY:-1400x900x24}" >/dev/null 2>&1 &
XVFB_PID=$!
sleep 2
export DISPLAY=":$DISPLAY_NUM"

"$APP" "$DOC" >"$LOG" 2>&1 &
APP_PID=$!

cleanup() {
    kill "$APP_PID" "$XVFB_PID" 2>/dev/null || true
    pkill -x "$APP" 2>/dev/null || true
    sleep 1
    kicad-unlock "$DOC" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

sleep "$WAIT"

for c in $CLICKS; do
    x=${c%,*}; y=${c#*,}
    xdotool mousemove "$x" "$y" click 1 2>/dev/null || true
    sleep 2
done

import -window root "$OUT"
echo "kicad-screenshot: wrote $OUT ($(stat -c%s "$OUT") bytes) after ${WAIT}s" >&2

# Window geometry is the second half of the instrument: it says whether a dialog exists and
# where its buttons are, which is what --click needs on the next run.
echo "kicad-screenshot: windows on :$DISPLAY_NUM" >&2
xwininfo -root -children 2>/dev/null | sed -n '/[0-9]* child/,$p' | head -20 >&2 || true

# The last few lines of the editor's own output, with the Xvfb noise removed. It is rarely
# the answer, but when the editor died instead of blocking, it is the only answer.
echo "kicad-screenshot: editor log tail" >&2
grep -v 'XFree86-VidModeExtension' "$LOG" | tail -5 >&2 || true
