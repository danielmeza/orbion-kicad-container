#!/bin/sh
# Seed a KiCad configuration that will not stop to ask a human anything.
#
# WHY THIS EXISTS. KiCad 10 added a START WIZARD (`common/startwizard/`, the "Welcome to
# KiCad 10.0" wxWizard). It is MODAL: it owns the main loop from the moment the editor
# starts. The IPC server still opens its socket and still accepts connections — so every
# outward sign says the API is up — and then answers every single request with
#
#     ApiError: KiCad returned error: KiCad is not ready to reply
#
# MEASURED 2026-09-07: that error persisted for 30 s of retries and looked exactly like an
# authentication problem. It was not. A screenshot of the virtual display showed the wizard
# sitting on top of pcbnew, waiting for a click. Clicking through it (xdotool, by
# coordinate — there is no window manager on an Xvfb display, so keystrokes go nowhere)
# made the very next request succeed. The fix is to write the answers before launch.
#
# THREE THINGS ARE NEEDED, and two of them are not obvious:
#
#   1. api.enable_server = true in kicad_common.json. The server is OFF by default.
#   2. The three NESTED LIBRARY TABLES below. These are what the wizard's libraries
#      provider writes when a human clicks Next, and their absence is what makes it run.
#      Copying KiCad's own big template tables into place does NOT satisfy it — measured,
#      the wizard still appeared. It wants a table of type "Table" pointing AT the template.
#   3. `kicad-cli version` first. It is headless, it never shows the wizard, and it writes
#      a complete kicad_common.json — which is a far better starting point than a
#      hand-written stub, because KiCad migrates a file it considers old.
#
# `system.first_run_shown` looks like the switch and is NOT: it is an APP_SETTINGS_BASE key,
# it lives per-editor, and it still reads false after the wizard has been completed.
set -eu

. /usr/local/bin/kicad-flavor

VER="${ORBION_KICAD_CONFIG_VERSION:-$KICAD_CONFIG_VERSION}"
if [ -n "${KICAD_CONFIG_HOME:-}" ]; then
    CFG="$KICAD_CONFIG_HOME/$VER"
else
    CFG="${XDG_CONFIG_HOME:-$HOME/.config}/kicad/$VER"
fi
mkdir -p "$CFG"

"kicad-cli$KICAD_SUFFIX" version >/dev/null 2>&1 || true

# A nested row must point at a table that EXISTS. MEASURED 2026-09-07: this image's
# /usr/share/kicad/template/ holds only fp-lib-table, sym-lib-table and kicad.kicad_pro —
# there is no design-block-lib-table — and a row pointing at the missing file makes KiCad
# show a warning triangle on that library forever. So each row is written only when its
# target is there, and the file is still created either way, because its ABSENCE is what
# makes the start wizard run.
#
# Note the spelling, which is not a typo: the FILE is hyphenated and the TAG inside is
# underscored. KiCad opens `design-block-lib-table` and parses `(design_block_lib_table`.
for f in sym-lib-table fp-lib-table design-block-lib-table; do
    case "$f" in
        sym-lib-table)          tag=sym_lib_table ;;
        fp-lib-table)           tag=fp_lib_table ;;
        design-block-lib-table) tag=design_block_lib_table ;;
    esac
    src="/usr/share/kicad/template/$f"
    if [ -f "$src" ]; then
        row="	(lib (name \"KiCad\") (type \"Table\") (uri \"$src\") (options \"\") (descr \"KiCad Default Libraries\"))"
    else
        row=""
    fi
    {
        printf '(%s\n\t(version 7)\n' "$tag"
        [ -n "$row" ] && printf '%s\n' "$row"
        printf ')\n'
    } > "$CFG/$f"
done

python3 - "$CFG/kicad_common.json" <<'PY'
import json, os, sys

path = sys.argv[1]
try:
    with open(path) as fh:
        data = json.load(fh)
except (OSError, ValueError):
    # kicad-cli could not run, or wrote nothing readable. A stub is worse than a complete
    # file but still better than no file: without it the wizard is certain.
    data = {}

data.setdefault("api", {})["enable_server"] = True
# Every one of these is a dialog that would block the main loop the same way the wizard does.
for key in data.get("do_not_show_again", {}):
    data["do_not_show_again"][key] = True

tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
os.replace(tmp, path)
print(f"kicad-first-run: seeded {path} (api.enable_server=true)")
PY
