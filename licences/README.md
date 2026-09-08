# What is in the published image, and where its source is

The image `ghcr.io/danielmeza/orbion-kicad-release` is **public**, and publishing it is
*conveying* the software inside it. Most of that software is GPL, so this directory carries the
directions GPLv3 §6(d) asks for: for each component, the licence and **where its Corresponding
Source lives**. It is copied into the image at `/usr/share/doc/orbion-kicad-release/`.

Nothing here is modified. Every binary is the upstream package, installed unchanged from the
archive named below, so the Corresponding Source is the one that archive publishes.

| Component | Licence | Corresponding Source |
|---|---|---|
| Ubuntu 26.04 base | various, per package | `http://archive.ubuntu.com/ubuntu` — `apt-get source <pkg>` inside the image |
| KiCad 10.0.6 (`kicad`) | GPL-3.0-or-later | `ppa:kicad/kicad-10.0-releases` on Launchpad, and <https://gitlab.com/kicad/code/kicad> at tag `10.0.6` |
| `kicad-symbols`, `kicad-footprints` | **CC-BY-SA 4.0 with the KiCad exception** — `kicad-libraries-LICENSE.md` here | <https://gitlab.com/kicad/libraries> |
| KiBot 1.9.1 | GPL-3.0 | <https://github.com/INTI-CMNB/KiBot> at `v1.9.1` (PyPI sdist carries the same) |
| InteractiveHtmlBom | MIT | <https://github.com/INTI-CMNB/InteractiveHtmlBom> at the pinned `IBOM_REF` |
| kicad-python (`kipy`) | as published on PyPI | <https://gitlab.com/kicad/code/kicad-python> |
| the `kicad-*` helper scripts | **see below** | <https://github.com/danielmeza/orbion-kicad-container> |

## The one row that is not settled: our own scripts

`orbion-kicad` ships **no LICENSE file**, so the six helper scripts copied into this image carry
no stated terms. With nothing said, the default is all rights reserved — which is a coherent
position for an internal tool, but it is not *stated*, and an image on a public registry
invites the question.

This is a decision for the repository's owner, not something to be inferred here. Until it is
made, this row says what is true rather than a licence nobody chose. Adding a `LICENSE` at the
repository root settles it, and this row should then name it.

Nothing about the row blocks anything: the scripts are ours, and every component that carries an
obligation is accounted for above.

## Why the two library packages get a file here and the rest do not

Debian and Ubuntu packages carry their licence at `/usr/share/doc/<pkg>/copyright`, and the
base image keeps those on purpose — `/etc/dpkg/dpkg.cfg.d/excludes` drops `/usr/share/doc/*`
but re-includes `*/copyright` and `*/changelog.*`.

MEASURED 2026-09-08 in the published image: `kicad` has its `copyright` (141 lines), and
**`kicad-symbols` and `kicad-footprints` have none** — their `/usr/share/doc/` directories hold
only a `changelog.gz`. That is an omission in the PPA's packaging, upstream of us, and it
leaves a public image carrying CC-BY-SA material with no licence text beside it. Copying the
text in costs 2 kB and closes it.

## What this does NOT require

**The Containerfile does not have to be published.** It is a build recipe, this repository's own
work; it does not incorporate or link against any of the software above, so no copyleft licence
reaches it (GPLv3 §5, mere aggregation). What is owed for conveying the binaries is their
licence text and directions to their source — the two things this directory is.

That answer changes the day anything here is **patched**. A modified KiCad or KiBot binary in
the image would put the modified source under the same obligation as the original, and pointing
at upstream would no longer be true.

Not legal advice — it is the reading this repository operates on, written down so it can be
checked rather than assumed.
