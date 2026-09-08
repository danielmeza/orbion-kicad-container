#!/bin/sh
# What this image is and how to drive it, printed by the image itself.
#
# It is the default CMD, so `podman run --rm ghcr.io/danielmeza/orbion-kicad-release:10.0.6`
# with no command explains itself. A registry page can go stale or lose its description; the
# image cannot -- this text ships in the same layer as the tools it describes.
cat <<'TEXT'
orbion-kicad-release — the image every Orbion board gate and release runs in.

  KiCad        10.0.6 (Ubuntu 26.04, ppa:kicad/kicad-10.0-releases)
  KiBot        1.9.1, with InteractiveHtmlBom, in /opt/kibot
  kicad-python 0.8.0 (kipy), in /opt/kipy
  Xvfb, rsvg-convert, imagemagick, ghostscript, xdotool

  THIS IMAGE CARRIES ONE KiCad: 10.0.6. The Containerfile also builds a `dev` stage with
  the nightly (10.99.0, the future 11) beside it and a `debug` stage with gdb and both
  symbol sets, but NEITHER IS PUBLISHED — a release must not be built by a nightly.
  Build them yourself:  mise run image-dev  /  mise run image-debug

WHAT IT IS FOR
  Running the gates and the manufacturing outputs of a board repo, so a green pipeline and
  a green laptop are the same KiCad. Mount the repo at /work (the working directory).

    podman run --rm -v "$PWD:/work" -w /work ghcr.io/danielmeza/orbion-kicad-release:10.0.6 \
      kicad-cli sch erc --exit-code-violations --severity-error \
        --format json -o out/erc.json hardware/main/main.kicad_sch

THE HELPERS THIS IMAGE ADDS
  kicad-first-run     seed a config that will not stop to ask a human anything. KiCad 10's
                      start wizard owns the main loop and makes every API request answer
                      "KiCad is not ready to reply"; this writes the answers before launch.
  kicad-ipc-server    start pcbnew or eeschema headless under Xvfb and hand back its socket,
                      after proving KiCad actually answered -- the socket file appears about
                      a second before it can.
                        kicad-ipc-server <file.kicad_pcb|.kicad_sch> [command ...]
  kicad-screenshot    <file> <out.png> — look at what the editor is showing. A modal dialog
                      is invisible in every log; this is how you see it.
  kicad-unlock        clear a stale ~*.lck, and ONLY one carrying our own hostname.
  kicad-flavor        sourced by the others; KICAD_FLAVOR=stable|nightly picks the binaries.
                      'nightly' needs the dev stage and refuses here, on purpose.

  The API is served by pcbnew and eeschema, never by kicad-cli, and needs no token. Note
  that eeschema 10.0.6 registers almost nothing over IPC: the schematic commands arrive in
  KiCad 11.

LICENCES AND SOURCE
  /usr/share/doc/orbion-kicad-release/README.md — every component, its licence, and where
  its Corresponding Source lives. Nothing here is modified; each binary is the upstream
  package installed unchanged.

WHICH BUILD IS THIS
  podman inspect --format '{{index .Labels "io.orbion.container.context"}}' <image>
  That hash is of the Containerfile and the files it COPYs, so it identifies the source
  this image was built from -- the version tag alone does not move when the recipe does.
TEXT
