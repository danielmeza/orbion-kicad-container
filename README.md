# orbion-kicad-release

A container image with **KiCad 10.0.6**, **KiBot 1.9.1** and the glue needed to run KiCad headless —
for board CI, design-rule gates and manufacturing outputs.

```sh
docker pull ghcr.io/danielmeza/orbion-kicad-release:10.0.6
docker run --rm ghcr.io/danielmeza/orbion-kicad-release:10.0.6      # prints a how-to
```

Run a check against a board:

```sh
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/danielmeza/orbion-kicad-release:10.0.6 \
  kicad-cli sch erc --exit-code-violations --severity-error \
    --format json -o out/erc.json hardware/main/main.kicad_sch
```

This repository is the source of that image. It's public so the image is auditable and so you can
rebuild it yourself.

## Why another KiCad image

The published ones lag. When we needed 10.0.6, every tag on `inti-cmnb/kicad10_auto` was 10.0.1 or
10.0.4, and 10.0.6 won't install into that base — it wants `glibc >= 2.43` and the base is Debian 13.
Ubuntu 26.04 is the only distribution KiCad publishes 10.0.6 for, so that's the base here, with KiBot
from pip on top.

That's not pedantry. Our board previews are signed with the renderer's identity, so CI on 10.0.4
against previews rendered on 10.0.6 marks all of them stale and fails the pipeline on correct
pictures. A green pipeline and a green laptop have to be the same KiCad.

## What's inside

| | |
|---|---|
| KiCad | 10.0.6, from `ppa:kicad/kicad-10.0-releases` |
| KiBot | 1.9.1 in `/opt/kibot`, with InteractiveHtmlBom baked in |
| kicad-python | 0.8.0 in `/opt/kipy`, for the IPC API |
| also | Xvfb, rsvg-convert, imagemagick, ghostscript, xdotool |

**One KiCad.** The Containerfile also has a `dev` stage with the nightly (10.99, the future 11)
alongside, and a `debug` stage with gdb and symbols. Neither is published — a release shouldn't be
built by a nightly. Build them yourself:

```sh
podman build --target dev   -t kicad-dev   -f Containerfile .
podman build --target debug -t kicad-debug -f Containerfile .
```

Pass `--target release` when you build the normal one. Three stages, and a build with no target
builds the last one.

## The helper scripts

KiCad's IPC API is served by `pcbnew` and `eeschema` — not `kicad-cli` — and needs no token. What
blocks it headless is a modal dialog, which never shows up in a log.

| Script | What it does |
|---|---|
| `kicad-first-run.sh` | Seeds a config so KiCad doesn't stop to ask anything. The start wizard holds the main loop and makes every request answer *"KiCad is not ready to reply"*. |
| `kicad-ipc-server.sh` | Starts an editor under Xvfb and hands back its socket once KiCad has actually answered. The socket appears about a second before the editor can reply. |
| `kicad-screenshot.sh` | Shows you what the editor is displaying. How we found the modal. |
| `kicad-unlock.sh` | Clears a stale `~*.lck`, and only one with our own hostname on it. |
| `kicad-flavor.sh` | `KICAD_FLAVOR=stable\|nightly` picks the binaries and config directory. |
| `orbion-help.sh` | The image's default command. |

Heads up: eeschema 10.0.6 answers almost nothing over IPC — it has no `GetVersion` handler at all.
The schematic commands arrive in KiCad 11.

## Which build am I running

The version tag doesn't move when the recipe changes, so every push also carries a `ctx-<hash>` tag
over the Containerfile and the files it copies in.

```sh
docker inspect --format '{{index .Config.Labels "io.orbion.container.context"}}' \
  ghcr.io/danielmeza/orbion-kicad-release:10.0.6

./context-hash.sh          # the same hash, from this source
./image-published.sh       # is there an image for this source? no credential needed
```

## Licences

`licences/README.md` lists every component, its licence and where its corresponding source lives; it
ships in the image at `/usr/share/doc/orbion-kicad-release/`. Nothing here is modified — every binary
is the upstream package, unchanged.

`kicad-symbols` and `kicad-footprints` ship no `copyright` file in the PPA, so the KiCad Libraries
licence is committed here and installed as theirs.

The scripts in this repository don't have a stated licence yet.
