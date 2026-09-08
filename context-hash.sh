#!/bin/sh
# The identity of the container image's SOURCE, as one short hash.
#
#   containers/context-hash.sh   ->  a1b2c3d4e5f6
#
# WHY THIS EXISTS. The published image is tagged with the KiCad version, `10.0.6`, and that tag
# does not change when the Containerfile does. MEASURED 2026-09-08: the image CI was pulling,
# ghcr.io/danielmeza/orbion-kicad-release:10.0.6 @sha256:1d952e2e..., was built on 2026-09-07
# 09:21 and carried NEITHER /usr/local/bin/kicad-flavor NOR the readiness fix in
# kicad-ipc-server -- both of which had been on main for a day. Nothing failed and nothing
# warned: the gates ran, in an image that was not the one the source describes.
#
# So every publish also carries `ctx-<hash>`, and containers/image-published.sh can ask the
# registry a question with a yes-or-no answer. A tag that does not exist is the only reliable
# evidence that nobody republished.
#
# WHAT GOES IN, AND WHY IT IS NOT A GLOB. The Containerfile, plus exactly the files it COPYs --
# READ OUT OF THE COPY LINES rather than listed here or matched with *.sh. This directory also
# holds the publishing tooling (this script, image-publish.sh, image-published.sh), and none of
# it ends up in the image; hashing it would demand a republish for a comment fix. A hand-written
# list would answer that, and then go stale the first time a COPY line is added. So the recipe
# names its own inputs.
set -eu

# LC_ALL=C, AND THAT IS NOT COSMETIC. `sort` collates by the locale, and `sed`'s character
# classes are locale-dependent too, so without this the hash of the SAME FILES differs between
# machines. MEASURED 2026-09-08: this directory hashed to d901d791d39d under en_US.UTF-8 and
# 82c1352ae0c4 under C, because en_US ignores case in collation and orders
# licences/kicad-libraries-LICENSE.md before licences/README.md while C does the opposite.
#
# CI runs under C and a laptop usually does not, so the gate flipped between "published" and
# "not published" depending on where it ran -- a false signal from the one check whose whole
# purpose is to be trustworthy. A content hash that depends on the machine is not a content
# hash.
export LC_ALL=C

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cf="$here/Containerfile"

{
    printf 'Containerfile\n'
    cat "$cf"

    # `COPY containers/x.sh /usr/local/bin/x` -> x.sh. Sorted, so the hash does not depend on
    # the order the lines happen to appear in, and content only: mtime and mode are not part
    # of what the image is.
    sed -n 's/^COPY[[:space:]]\{1,\}containers\/\([^[:space:]]*\).*/\1/p' "$cf" | sort -u |
    while IFS= read -r name; do
        [ -f "$here/$name" ] || { echo "context-hash: Containerfile COPYs containers/$name, which does not exist" >&2; exit 1; }
        printf '%s\n' "$name"
        cat "$here/$name"
    done
} | sha256sum | cut -c1-12
