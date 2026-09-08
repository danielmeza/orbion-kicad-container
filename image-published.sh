#!/bin/sh
# Is there a published image built from THIS containers/ directory?
#
#   containers/image-published.sh          -> exit 0 when yes, 1 when no
#
# Read-only and anonymous. GHCR mints a pull token for anyone on a public package, so this
# needs no credential and runs in CI, in a hook, and on a laptop the same way.
#
# WHAT IT ACTUALLY ASKS. Not "does the image exist" -- `10.0.6` always exists. It asks whether
# the tag `ctx-<hash>` exists, where the hash is containers/context-hash.sh over everything the
# image is built from. That tag can only be there if somebody published AFTER the last change
# to this directory.
#
# MEASURED 2026-09-08, which is why it exists: ghcr.io/danielmeza/orbion-kicad-release:10.0.6
# @sha256:1d952e2e... was built on 2026-09-07 09:21 and carried neither
# /usr/local/bin/kicad-flavor nor the readiness fix in kicad-ipc-server, both of which had been
# on main for a day. CI pulled it, every gate was green, and the image was not the one the
# source describes. The version tag never moves, so nothing could have noticed.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=${ORBION_IMAGE_REPO:-danielmeza/orbion-kicad-release}
ctx=$("$here/context-hash.sh")

token=$(curl -fsS "https://ghcr.io/token?scope=repository:$repo:pull" \
        | tr ',' '\n' | grep '"token"' | cut -d'"' -f4)

code=$(curl -s -o /dev/null -w '%{http_code}' -I \
       -H "Authorization: Bearer $token" \
       -H 'Accept: application/vnd.oci.image.index.v1+json' \
       -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
       -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
       "https://ghcr.io/v2/$repo/manifests/ctx-$ctx")

if [ "$code" = 200 ]; then
    echo "ok: ghcr.io/$repo:ctx-$ctx is published, so the image matches containers/"
    exit 0
fi

echo "containers/ changed and no image was published for it (no tag ctx-$ctx, HTTP $code)." >&2
echo "  Every gate and every release would run in an image that is NOT the one this" >&2
echo "  source describes, and nothing else would say so." >&2
echo "  Fix:  mise run image-publish" >&2
exit 1
