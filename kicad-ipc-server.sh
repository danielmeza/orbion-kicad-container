#!/bin/sh
# Start KiCad's IPC API server headless, inside the container, and hand back its socket.
#
#   kicad-ipc-server <board.kicad_pcb | sheet.kicad_sch> [command ...]
#
# With no command it stays in the foreground until killed, which is what the host-side
# `scripts/kicad-ipc` uses. With a command it waits for the socket, runs the command, and
# tears the editor down — which is what a gate wants.
#
# MEASURED 2026-09-07, KiCad 10.0.6 on Ubuntu 26.04 under Xvfb:
#   * `pcbnew` and `eeschema` serve the API. `kicad` (the project manager) starts the API
#     subsystem and never opens a server; `kicad-cli` does not contain it at all
#     (KICAD_API_SERVER: 7 hits in the GUI binary, 0 in kicad-cli).
#   * The socket appears about 2 s after launch, at $TMPDIR/kicad/api.sock.
#   * A client KiCad did not launch connects and is answered WITHOUT a KICAD_API_TOKEN.
#     The token is what a plugin gets so KiCad can tell plugins apart; it is not the
#     admission barrier, and this was measured rather than assumed.
set -eu

if [ $# -lt 1 ]; then
    echo "usage: kicad-ipc-server <file.kicad_pcb|.kicad_sch> [command ...]" >&2
    exit 2
fi

DOC=$1
shift

. /usr/local/bin/kicad-flavor

case "$DOC" in
    *.kicad_sch) APP="eeschema$KICAD_SUFFIX" ;;
    *.kicad_pcb) APP="pcbnew$KICAD_SUFFIX" ;;
    *) echo "kicad-ipc-server: $DOC is neither a .kicad_pcb nor a .kicad_sch" >&2; exit 2 ;;
esac

[ -f "$DOC" ] || { echo "kicad-ipc-server: no such file: $DOC" >&2; exit 2; }

kicad-first-run >&2

# A lock left by a killed session of ours puts up a modal that blocks everything. See
# kicad-unlock: only a lock carrying our own fixed hostname is removed.
kicad-unlock "$DOC" || true

SOCKDIR="${TMPDIR:-/tmp}/kicad"
SOCK="$SOCKDIR/api.sock"
mkdir -p "$SOCKDIR"
rm -f "$SOCK"

LOG="${ORBION_IPC_LOG:-${TMPDIR:-/tmp}/kicad-ipc.log}"
# Everything the editor prints goes to the log. An Xvfb display makes KiCad emit one
# `Xlib: extension "XFree86-VidModeExtension" missing` line per redraw, and dbus emits an
# AT-SPI warning per start; neither is a fault and neither belongs on a terminal.
xvfb-run -a --server-args="-screen 0 1280x1024x24" "$APP" "$DOC" >"$LOG" 2>&1 &
EDITOR_PID=$!

cleanup() {
    kill "$EDITOR_PID" 2>/dev/null || true
    pkill -x "$APP" 2>/dev/null || true
    sleep 1
    kicad-unlock "$DOC" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

i=0
while [ "$i" -lt 60 ]; do
    [ -S "$SOCK" ] && break
    kill -0 "$EDITOR_PID" 2>/dev/null || { echo "kicad-ipc-server: $APP exited early; see $LOG" >&2; tail -5 "$LOG" >&2; exit 1; }
    i=$((i + 1))
    sleep 1
done

if [ ! -S "$SOCK" ]; then
    echo "kicad-ipc-server: no socket after ${i}s; see $LOG" >&2
    exit 1
fi

# THE SOCKET IS NOT READINESS. MEASURED 2026-09-07: the socket file appears about a second
# before the editor can answer anything, and a client that connects in that window gets
# `ApiError: KiCad returned error: KiCad is not ready to reply` - the same sentence a modal
# dialog produces, which is how an hour went into the wrong diagnosis. So this does not claim
# the server is up until KiCad has actually answered a request.
if ! /opt/kipy/bin/python - "$SOCK" <<'READY' >&2
import sys, time
from kipy import KiCad
from kipy.errors import ApiError

# READINESS IS "IT ANSWERED", NOT "IT SAID YES". MEASURED 2026-09-08: eeschema 10.0.6 has no
# GetVersion handler at all -- it registers exactly one command, GetOpenDocuments -- and
# replies AS_UNHANDLED, "no handler available for request of type
# kiapi.common.commands.GetVersion". An earlier version of this probe treated that as not
# ready and timed out after 60 s against an editor that had been answering from the first
# second, then blamed a modal dialog. A refusal IS a reply: the main loop is running, which is
# the only thing this handshake exists to establish.
sock = "ipc://" + sys.argv[1]
last = None
for _ in range(60):
    try:
        KiCad(socket_path=sock).get_version()
        sys.exit(0)
    except ApiError as exc:
        if "no handler available" in str(exc):
            sys.exit(0)
        last = f"{type(exc).__name__}: {exc}"
        time.sleep(1)
    except Exception as exc:              # noqa: BLE001 - any other failure means not ready yet
        last = f"{type(exc).__name__}: {exc}"
        time.sleep(1)
print(f"kicad-ipc-server: socket exists but KiCad never answered. last: {last}", file=sys.stderr)
print("  A modal dialog holding the main loop reports exactly this. Look at it:", file=sys.stderr)
print("  scripts/kicad-shot <the same file>", file=sys.stderr)
sys.exit(1)
READY
then
    exit 1
fi

echo "kicad-ipc-server: $APP answering on ipc://$SOCK (socket in ${i}s, then a handshake)" >&2

if [ $# -gt 0 ]; then
    "$@"
    exit $?
fi

wait "$EDITOR_PID"
