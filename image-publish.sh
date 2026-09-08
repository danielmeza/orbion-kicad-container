#!/bin/sh
# Build the release image and push it to GHCR, tagged by version AND by source hash.
#
#   containers/image-publish.sh        (mise run image-publish calls this)
#
# A script rather than only a mise task, because CI needs it on a hosted agent where mise is
# not installed and only `docker` is. Everything the task did lives here; the task is one line.
#
# WHY THE SECOND TAG. `10.0.6` does not change when the Containerfile does. MEASURED
# 2026-09-08: the published copy was built 2026-09-07 09:21 and carried neither
# /usr/local/bin/kicad-flavor nor the readiness fix in kicad-ipc-server, both a day old on
# main. `ctx-<hash>` moves with the source, so containers/image-published.sh can ask the
# registry a question with a yes-or-no answer.
#
# Credential: GHCR_TOKEN, a GitHub PAT with write:packages. Locally, `gh auth token` supplies
# it when the CLI is logged in with that scope.
#
# TWO MODES, and the difference is which tags move.
#
#   image-publish.sh              push :<version> AND :ctx-<hash>   -- main
#   image-publish.sh --ctx-only   push :ctx-<hash> only             -- a pull request
#
# `:10.0.6` is what CI and every board repo pull, so it must only ever advance from main.
# `ctx-<hash>` is content-addressed: an image for source that never merges is inert, and
# publishing it is what lets a PR touching containers/ go green at all. Without the split the
# gate deadlocks -- the check fails on the PR, and the only thing that could fix it runs after
# the merge.
set -eu

ctx_only=no
case "${1:-}" in
    --ctx-only) ctx_only=yes ;;
    "") ;;
    *) echo "image-publish: unknown argument: $1" >&2; exit 2 ;;
esac

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)
repo=${ORBION_IMAGE_REPO:-danielmeza/orbion-kicad-release}
image="ghcr.io/$repo"
version=${ORBION_KICAD_EXACT:-10.0.6}
ctx=$("$here/context-hash.sh")

engine=$(command -v podman || command -v docker) || {
    echo "image-publish: neither podman nor docker is installed" >&2; exit 2; }

token=${GHCR_TOKEN:-}
if [ -z "$token" ] && command -v gh >/dev/null 2>&1; then
    token=$(gh auth token 2>/dev/null || true)
fi
if [ -z "$token" ]; then
    echo "image-publish: no credential. Set GHCR_TOKEN to a GitHub PAT with write:packages," >&2
    echo "  or log in with: gh auth login -s write:packages" >&2
    exit 2
fi

# ANNOTATIONS, NOT ONLY LABELS. MEASURED 2026-09-08: the package page on GHCR showed
# Ubuntu's blurb -- "The Ubuntu container image maintained by Canonical..." -- even though the
# image's config carried our own org.opencontainers.image.description. The raw manifest says
# why: buildah copies the BASE IMAGE's annotations forward, so
#
#   annotations.org.opencontainers.image.description = "The Ubuntu container image..."
#
# sat on the manifest while our LABEL sat in the config, and GHCR reads the manifest
# annotation. A LABEL alone can never fix that page. These -- and .created, which was
# otherwise Ubuntu's build date of 2026-08-17 -- overwrite the inherited ones.
created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
description="KiCad 10.0.6 + KiBot 1.9.1 + kipy and the Orbion IPC helpers - the image every Orbion board gate and release runs in. One KiCad only: the nightly lives in the unpublished dev stage. Run it with no command for a how-to."

"$engine" build --target release --build-arg "ORBION_CONTEXT=$ctx" \
    --annotation "org.opencontainers.image.title=orbion-kicad-release" \
    --annotation "org.opencontainers.image.description=$description" \
    --annotation "org.opencontainers.image.source=https://github.com/danielmeza/orbion-kicad-container" \
    --annotation "org.opencontainers.image.licenses=GPL-3.0-or-later" \
    --annotation "org.opencontainers.image.version=$version" \
    --annotation "org.opencontainers.image.created=$created" \
    --annotation "org.opencontainers.image.revision=$ctx" \
    -t "$image:$version" -t "$image:ctx-$ctx" \
    -f "$here/Containerfile" "$root"

# Prove it is the release stage BEFORE it is published. A debug image under the release name
# is exactly what --target exists to prevent, and it would go out in silence.
"$engine" run --rm "$image:$version" sh -c '
    if command -v kicad-cli-nightly >/dev/null; then
        echo "REFUSING: this is the dev or debug stage, not release" >&2
        exit 1
    fi
    kicad-cli --version'

printf '%s' "$token" | "$engine" login ghcr.io -u "${GHCR_USER:-danielmeza}" --password-stdin
"$engine" push "$image:ctx-$ctx"
if [ "$ctx_only" = yes ]; then
    echo "published $image:ctx-$ctx (the version tag is left alone: it advances from main only)"
else
    "$engine" push "$image:$version"
    echo "published $image:$version and :ctx-$ctx"
fi
