#!/bin/sh
# Clear the KiCad lock files left by a previous headless session of OUR OWN making.
#
#   kicad-unlock <file.kicad_pcb|.kicad_sch>
#
# WHY. KiCad writes `~<name>.lck` next to a document it opens, holding
# {"hostname":…,"username":…}. A session that is killed rather than closed leaves it behind,
# and the next open puts up a modal "File Open Warning" — which holds the main loop and makes
# the IPC API answer "KiCad is not ready to reply" forever. MEASURED 2026-09-07: five stale
# locks from killed probe runs, and the failure looked exactly like the start-wizard one.
#
# WHY IT DOES NOT JUST DELETE THEM. A lock may belong to a colleague with the board open on a
# shared checkout, and deleting that invites two editors writing one file. So the container
# runs with a FIXED HOSTNAME (`--hostname orbion-kicad-ipc`, set in scripts/kicad-ipc and
# scripts/kicad-shot) and only a lock carrying that hostname is removed. Anything else is
# reported, with the holder named, and the caller decides.
set -eu

[ $# -ge 1 ] || { echo "usage: kicad-unlock <file>" >&2; exit 2; }

DOC=$1
DIR=$(dirname "$DOC")
BASE=$(basename "$DOC")
STEM=${BASE%.*}
OURS="${ORBION_LOCK_HOSTNAME:-orbion-kicad-ipc}"
rc=0

for f in "$DIR/~$BASE.lck" "$DIR/~$STEM.kicad_pro.lck" "$DIR/~$STEM.kicad_sch.lck" "$DIR/~$STEM.kicad_pcb.lck"; do
    [ -f "$f" ] || continue
    holder=$(sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p' "$f" 2>/dev/null || true)
    if [ "$holder" = "$OURS" ]; then
        rm -f "$f"
        echo "kicad-unlock: cleared our own stale lock $f" >&2
    else
        echo "kicad-unlock: $f is held by hostname '$holder' - NOT removing it." >&2
        echo "  If that machine no longer has the file open, delete the lock by hand." >&2
        rc=1
    fi
done

exit $rc
