#!/bin/sh
# Push this directory to the PUBLIC GitHub repository the image points at.
#
#   containers/mirror-publish.sh [--check]
#
# WHY A MIRROR EXISTS AT ALL. GHCR renders the README of the GitHub repository a package is
# linked to, and the link is org.opencontainers.image.source. MEASURED 2026-09-08: with that
# annotation naming an Azure DevOps URL, GHCR could not read it, the package reported
# `repository: null`, and the page showed the BASE IMAGE's blurb -- "The Ubuntu container image
# maintained by Canonical..." -- because buildah copies the base's annotations forward. No label
# and no annotation can fix that page; only a linked GitHub repo can.
#
# So the annotation now names the mirror, and the mirror has to actually exist and match.
#
# WHY A COPY IS DANGEROUS, AND WHAT IS DONE ABOUT IT. A mirror that drifts is the same defect as
# a stale image: it looks like documentation and describes something else. The commit message
# carries `ctx-<hash>` -- the same hash `context-hash.sh` computes over the Containerfile and the
# files it COPYs -- so "is the mirror current?" is a question with a yes-or-no answer, and
# --check asks it without pushing anything.
#
# WHAT IS AND IS NOT PUBLISHED. Everything in containers/, which is the whole source of the
# image and nothing else: the recipe, the six scripts it copies in, the publishing tooling and
# the licence files. Audited 2026-09-08 for internal identifiers -- the only one was the Azure
# DevOps URL, which this change replaces with the mirror's own. No credential is read, written
# or copied here; GHCR_TOKEN is used by image-publish.sh and never leaves it.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=${ORBION_MIRROR_REPO:-danielmeza/orbion-kicad-container}
ctx=$("$here/context-hash.sh")

# The mirror's own identity, which is NOT the image's. context-hash.sh covers the Containerfile and
# the files it COPYs -- deliberately, so a comment fix does not demand a republished image. But the
# mirror also publishes the tooling and mirror-README.md, and editing the README changed neither the
# image nor its hash, so the check said "current" and the public page kept the old text. Found by
# rewriting that README and watching nothing happen.
#
# So the mirror is tracked by a hash of everything the mirror actually publishes.
mirror=$(LC_ALL=C; export LC_ALL; find "$here" -type f ! -name CONTEXT ! -name MIRROR \
         | sort | while IFS= read -r f; do printf '%s\n' "${f#$here/}"; cat "$f"; done \
         | sha256sum | cut -c1-12)
check=no
[ "${1:-}" = "--check" ] && check=yes

# The mirror carries a CONTEXT file naming the hash it was generated from, and the check is a
# string compare against it. Two earlier attempts were wrong in instructive ways: reading the
# commit message through the API meant parsing JSON-escaped, nested text, and reading
# raw.githubusercontent 404s for minutes after a file first appears -- MEASURED 2026-09-08, the
# push had succeeded and the API served CONTEXT immediately while raw still said 404, so the
# check called a correct mirror stale.
#
# The contents API with the raw Accept header has neither problem. raw is kept as a fallback
# because it is not rate-limited once warm, and this runs on every build.
published=$(curl -fsS -H 'Accept: application/vnd.github.raw' \
              "https://api.github.com/repos/$repo/contents/MIRROR" 2>/dev/null \
            || curl -fsS "https://raw.githubusercontent.com/$repo/main/MIRROR" 2>/dev/null \
            || true)
published=$(printf '%s' "$published" | tr -d '\r\n')
if [ "$published" = "$mirror" ]; then
    echo "ok: $repo is current (mirror $mirror, image ctx-$ctx)"
    exit 0
fi

if [ "$check" = yes ]; then
    echo "$repo is at '${published:-nothing}' and containers/ is at $mirror, so the public source is behind." >&2
    echo "  The image's org.opencontainers.image.source would point at a stale repository." >&2
    echo "  Fix:  containers/mirror-publish.sh" >&2
    exit 1
fi

token=${GHCR_TOKEN:-}
if [ -z "$token" ] && command -v gh >/dev/null 2>&1; then
    token=$(gh auth token 2>/dev/null || true)
fi
[ -n "$token" ] || { echo "mirror-publish: no GitHub credential (GHCR_TOKEN or gh auth)" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Copy the source, then the README the mirror shows. mirror-README.md is versioned beside the
# thing it describes on purpose: a README kept only in the public repo drifts the first time
# anything here changes, and nothing would say so.
cp -R "$here/." "$work/"
mv "$work/mirror-README.md" "$work/README.md"
printf '%s\n' "$ctx"    > "$work/CONTEXT"
printf '%s\n' "$mirror" > "$work/MIRROR"

cd "$work"
git init -q
git checkout -qb main
git add -A
git -c user.name="Orbion" -c user.email="noreply@users.noreply.github.com" \
    commit -qm "The source of ghcr.io/danielmeza/orbion-kicad-release, at ctx-$ctx (mirror $mirror)

Generated from containers/ by containers/mirror-publish.sh. Do not edit here: the
commit message names the context hash the image is built from, and mirror-publish.sh
--check refuses when this repository stops matching it."

git push -q --force "https://x-access-token:$token@github.com/$repo.git" main
echo "mirrored containers/ to https://github.com/$repo at ctx-$ctx"
