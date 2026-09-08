# The release container, on the newest KiCad there is.
#
# WHY THIS EXISTS. Releases are built by KiBot inside a container so they are reproducible.
# The obvious image, ghcr.io/inti-cmnb/kicad10_auto, ships **KiCad 10.0.4** and cannot be
# upgraded in place: MEASURED 2026-09-07, `apt install kicad` from the 10.0.6 PPA inside it
# fails with `kicad Depends libc6 (>= 2.43) but none of the choices are installable` — the
# image is Debian 13.2 and 10.0.6 is built against Ubuntu 26.04's glibc. No tag in that
# registry carries 10.0.6 either (100 tags, all k10.0.1 or k10.0.4).
#
# So the base is Ubuntu 26.04, which is the only distribution the KiCad project publishes
# 10.0.6 for, and KiBot comes from pip on top of it.
#
#   podman build -t localhost/orbion/kicad-release:10.0.6 -f containers/Containerfile .
#   mise run image        # the same thing, with the version read from .mise.toml
FROM docker.io/library/ubuntu:26.04 AS release

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/kibot/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates gpg-agent; \
    add-apt-repository -y ppa:kicad/kicad-10.0-releases; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        kicad kicad-symbols kicad-footprints \
        python3-pip python3-venv python3-wxgtk4.0 \
        git bash coreutils zip \
        librsvg2-bin imagemagick ghostscript xvfb x11-utils xdotool; \
    rm -rf /var/lib/apt/lists/*

# rsvg-convert, imagemagick, ghostscript and xvfb are the tools KiBot shells out to for
# PDF/SVG/PNG outputs — measured by listing them inside the upstream image, which is the
# only honest source for "what does KiBot actually need at run time".
#
# Two pip flags, both non-obvious, both measured by getting them wrong first:
#
#   --system-site-packages  KiBot imports `pcbnew`, which comes from the kicad package and
#                           lives in the system interpreter. A plain venv cannot see it.
#   --no-compile            KiBot generates part of itself at import time from `kibot.macros`.
#                           Installed the normal way, every run dies with "cannot import name
#                           'macros' from 'kibot.macros'" — KiBot's own error text names the
#                           flag, which is the only reason this was a five-minute problem.
RUN set -eux; \
    python3 -m venv --system-site-packages /opt/kibot; \
    /opt/kibot/bin/pip install --no-cache-dir --upgrade pip; \
    /opt/kibot/bin/pip install --no-cache-dir --no-compile kibot \
        lxml xlsxwriter qrcodegen requests colorama markdown2 numpy Pillow

# InteractiveHtmlBom, pinned and installed rather than downloaded. MEASURED: without it
# KiBot prints "Trying to download Interactive HTML BoM" and fetches a release from GitHub
# DURING THE BUILD — a manufacturing package whose contents depend on what a third party
# was serving that minute, and which fails outright on a machine with no network. The
# upstream image ships it at /usr/bin/generate_interactive_bom.py; so does this one.
ARG IBOM_REF=v2.10.1
RUN set -eux; \
    /opt/kibot/bin/pip install --no-cache-dir --no-compile \
        "git+https://github.com/INTI-CMNB/InteractiveHtmlBom@${IBOM_REF}#egg=InteractiveHtmlBom" \
    || /opt/kibot/bin/pip install --no-cache-dir --no-compile \
        "git+https://github.com/INTI-CMNB/InteractiveHtmlBom#egg=InteractiveHtmlBom"; \
    ln -sf /opt/kibot/lib/python3*/site-packages/InteractiveHtmlBom/generate_interactive_bom.py \
        /usr/bin/generate_interactive_bom.py; \
    test -x /usr/bin/generate_interactive_bom.py || chmod +x /usr/bin/generate_interactive_bom.py

# KiCad's IPC API, served headless. MEASURED 2026-09-07: the API is compiled into KiCad 10
# and served by pcbnew/eeschema (never by kicad-cli, which does not contain it), the socket
# appears ~2 s after launch under Xvfb, and a client KiCad did not launch is answered with
# NO KICAD_API_TOKEN. What blocks it is not authentication: it is KiCad 10's modal start
# wizard, which owns the main loop and makes every request answer "KiCad is not ready to
# reply". kicad-first-run writes the answers before launch — read it, the two non-obvious
# parts are commented there.
#
# kicad-python (kipy) is KiCad's own reference client, in its own venv because the KiBot
# venv is --system-site-packages and must keep its dependency set exactly as KiBot pins it.
COPY containers/orbion-help.sh       /usr/local/bin/orbion-kicad-help
COPY containers/kicad-flavor.sh      /usr/local/bin/kicad-flavor
COPY containers/kicad-first-run.sh   /usr/local/bin/kicad-first-run
COPY containers/kicad-ipc-server.sh  /usr/local/bin/kicad-ipc-server
COPY containers/kicad-ipc-check.py   /usr/local/bin/kicad-ipc-check
COPY containers/kicad-screenshot.sh  /usr/local/bin/kicad-screenshot
COPY containers/kicad-unlock.sh      /usr/local/bin/kicad-unlock
RUN set -eux; \
    chmod +x /usr/local/bin/orbion-kicad-help /usr/local/bin/kicad-first-run \
             /usr/local/bin/kicad-ipc-server \
             /usr/local/bin/kicad-ipc-check /usr/local/bin/kicad-screenshot \
             /usr/local/bin/kicad-unlock; \
    chmod 0644 /usr/local/bin/kicad-flavor; \
    python3 -m venv /opt/kipy; \
    /opt/kipy/bin/pip install --no-cache-dir kicad-python

# Both must answer, or the image is not the thing it claims to be.
RUN kicad-cli --version && kibot --version && /opt/kipy/bin/python -c "import kipy; print('kipy', kipy.__name__)"

WORKDIR /work

# Run the image with no command and it explains itself. A registry page can go stale or lose
# its description -- MEASURED 2026-09-08, this package's page still showed Ubuntu's, because
# GHCR renders the README of the GitHub repo named by org.opencontainers.image.source and ours
# names an Azure DevOps URL it cannot read. The image cannot go stale about itself: this text
# ships in the same layer as the tools it describes.
#
# Only the DEFAULT is set. Every existing caller passes a command (`kicad-cli ...`, a mise
# task, an Azure Pipelines `container:` job), and a CMD is ignored the moment one is given.
CMD ["orbion-kicad-help"]

# ---------------------------------------------------------------------------------------
# dev: KiCad 11 (nightly) INSTALLED ALONGSIDE 10.0.6, not instead of it.
# ---------------------------------------------------------------------------------------
# WHY. Two schematic IPC handlers this repo wants -- GetSchematicNetlist and
# GetSchematicHierarchy -- are written and merged (2026-04-17 and 2026-04-23) but exist only
# on master: the 10.0 branch registers exactly ONE eeschema handler (GetOpenDocuments) and
# its schematic_commands.proto does not even declare them. There is no 11.0 branch yet, so
# "the next release" is only reachable as a nightly.
#
# HOW IT COEXISTS. The nightly PPA's SOURCE package is called `kicad`, but its BINARY package
# is `kicad-nightly` -- a different package name, different binaries (`pcbnew-nightly`,
# `eeschema-nightly`, `kicad-cli-nightly`), a different config directory. apt installs it next
# to the stable one rather than over it. Verified against the Launchpad API 2026-09-07: the
# PPA publishes kicad-nightly for `resolute` (Ubuntu 26.04), the same series this image is
# built on, at 202609080239+302b2ba101.
#
# WHAT IT IS NOT FOR. Nothing released is produced from this stage. The `release` stage is
# what CI pulls and what every manufacturing output is built by; it does not contain a
# nightly, and the two stages share every layer up to this point, so nothing here can change
# what a release looks like. This stage exists to answer "does it still do that on master?"
# before filing a bug upstream, and to try handlers that do not exist in any release yet.
# LICENCES, and where the source of everything in here lives.
#
# This image is public, and publishing it is CONVEYING the software inside it. Nothing here is
# modified -- every binary is the upstream package installed unchanged -- so what is owed is
# the licence text and clear directions to the Corresponding Source, which is what
# containers/licences/README.md is (GPLv3 s6(d)).
#
# The two library packages need the text COPYed in. MEASURED 2026-09-08 in the published image:
# the base keeps /usr/share/doc/*/copyright on purpose (/etc/dpkg/dpkg.cfg.d/excludes
# re-includes it), `kicad` has its 141-line copyright -- and `kicad-symbols` and
# `kicad-footprints` have NONE, only a changelog.gz. That is an omission in the PPA's
# packaging, and it left a public image carrying CC-BY-SA material with no licence beside it.
COPY containers/licences/README.md                  /usr/share/doc/orbion-kicad-release/README.md
COPY containers/licences/kicad-libraries-LICENSE.md /usr/share/doc/orbion-kicad-release/kicad-libraries-LICENSE.md
RUN set -eux; \
    for p in kicad-symbols kicad-footprints; do \
        install -Dm644 /usr/share/doc/orbion-kicad-release/kicad-libraries-LICENSE.md \
            "/usr/share/doc/$p/copyright"; \
    done

# Who built this, from what. MEASURED 2026-09-08: the image published to GHCR carried only
# Ubuntu's own labels, so nothing in the registry said which KiCad it held or which source it
# came from -- and the copy CI was pulling turned out to be a day behind the Containerfile
# with no way to see that from the outside. ORBION_CONTEXT is containers/context-hash.sh, the
# hash of everything this image is built from; `mise run image-publish` passes it and also
# pushes it as a tag, so "is there an image for this source?" is a question the registry can
# answer.
ARG ORBION_CONTEXT=unknown
LABEL org.opencontainers.image.title="orbion-kicad-release" \
      org.opencontainers.image.description="KiCad 10.0.6 + KiBot 1.9.1 + kipy and the Orbion IPC helpers - the image every Orbion board gate and release runs in. One KiCad only: the nightly lives in the unpublished dev stage. Run it with no command for a how-to." \
      org.opencontainers.image.source="https://github.com/danielmeza/orbion-kicad-container" \
      org.opencontainers.image.version="10.0.6" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      io.orbion.kicad.version="10.0.6" \
      io.orbion.container.context="${ORBION_CONTEXT}"

FROM release AS dev
RUN set -eux; \
    add-apt-repository -y ppa:kicad/kicad-dev-nightly; \
    apt-get update; \
    apt-get install -y --no-install-recommends kicad-nightly; \
    rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    kicad-cli --version; \
    kicad-cli-nightly --version; \
    sh -c '. /usr/local/bin/kicad-flavor; test "$KICAD_SUFFIX" = ""'; \
    sh -c 'KICAD_FLAVOR=nightly . /usr/local/bin/kicad-flavor; test "$KICAD_SUFFIX" = "-nightly"; echo "nightly config dir: $KICAD_CONFIG_VERSION"' 

# ---------------------------------------------------------------------------------------
# debug: dev plus what a useful upstream bug report needs.
# ---------------------------------------------------------------------------------------
# A backtrace out of a stripped binary names addresses. `kicad-dbg` and `kicad-nightly-dbg`
# carry the symbols and gdb turns a crash into something a KiCad developer can act on. BOTH
# flavours, because the interesting question is usually "it crashes here and not there" and
# that needs a named frame on each side. Kept out of `dev` because the symbols are large and
# only a crash report needs them.
FROM dev AS debug
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends gdb kicad-dbg kicad-nightly-dbg; \
    rm -rf /var/lib/apt/lists/*
