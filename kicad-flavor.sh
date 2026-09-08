# Which KiCad the helpers should drive. Sourced, never executed.
#
#   . /usr/local/bin/kicad-flavor
#
# Sets KICAD_SUFFIX (the binary suffix) and KICAD_CONFIG_VERSION (the config sub-directory),
# from KICAD_FLAVOR:
#
#   stable   (default)   kicad-cli, pcbnew, eeschema           ~/.config/kicad/10.0
#   nightly              kicad-cli-nightly, pcbnew-nightly...  ~/.config/kicad/10.99
#
# WHY A SUFFIX IS ENOUGH. MEASURED 2026-09-07 in the `dev` image: the nightly PPA's binary
# package is `kicad-nightly`, separate from `kicad`, and every executable it installs carries
# the suffix -- `eeschema-nightly`, `pcbnew-nightly`, `kicad-cli-nightly` -- with the real
# binaries under /usr/lib/kicad-nightly/bin. Nothing is replaced.
#
# WHY THE VERSION IS ASKED FOR RATHER THAN WRITTEN DOWN. Both flavours use the SAME config
# directory name (`~/.config/kicad`), separated only by a version sub-directory: 10.0 for the
# release, 10.99 for master -- KiCad numbers its development branch X.99 on the way to X+1, so
# "KiCad 11" reports itself as 10.99.0 today. A hardcoded "10.99" would be wrong the week 11.0
# ships and wrong again at 10.0.7, so it is read from the binary that is about to be run.

KICAD_FLAVOR="${KICAD_FLAVOR:-stable}"

case "$KICAD_FLAVOR" in
    stable)  KICAD_SUFFIX="" ;;
    nightly) KICAD_SUFFIX="-nightly" ;;
    *)
        echo "kicad-flavor: KICAD_FLAVOR must be 'stable' or 'nightly', not '$KICAD_FLAVOR'" >&2
        exit 2
        ;;
esac

if ! command -v "kicad-cli$KICAD_SUFFIX" >/dev/null 2>&1; then
    echo "kicad-flavor: KICAD_FLAVOR=$KICAD_FLAVOR needs kicad-cli$KICAD_SUFFIX, which is not" \
         "installed here. The nightly lives in the image's 'dev' stage; the release stage" \
         "carries only the stable KiCad, on purpose." >&2
    exit 2
fi

# 10.0.6 -> 10.0, 10.99.0 -> 10.99. The config directory KiCad picks is the version without
# its patch component.
KICAD_VERSION="$("kicad-cli$KICAD_SUFFIX" --version 2>/dev/null | head -1)"
KICAD_CONFIG_VERSION="${KICAD_VERSION%.*}"

export KICAD_FLAVOR KICAD_SUFFIX KICAD_VERSION KICAD_CONFIG_VERSION
