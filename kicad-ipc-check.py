#!/usr/bin/env python3
"""Prove the IPC path end to end: connect, identify KiCad, read the open document.

Run inside the container by `scripts/kicad-ipc --check`. It is deliberately small — its
job is to be a CHECK THAT CANNOT PASS WITHOUT PROVING SOMETHING, so it asks for a value
only a live KiCad can produce (its build string) and then for content only an opened
document can produce (the net list / stackup).

It passes NO KICAD_API_TOKEN, on purpose. MEASURED 2026-09-07: KiCad 10.0.6 answers a
client it did not launch without one. If a future KiCad refuses, this check fails loudly
rather than quietly skipping — which is the whole point of it existing.
"""
import sys
import time

SOCKET = "ipc:///tmp/kicad/api.sock"


def main() -> int:
    from kipy import KiCad

    last = None
    for attempt in range(30):
        try:
            kicad = KiCad(socket_path=SOCKET)
            version = kicad.get_version()
            print(f"kicad-ipc-check: connected with no token in ~{attempt}s -> KiCad {version}")
            break
        except Exception as exc:                      # noqa: BLE001 - report, do not classify
            last = f"{type(exc).__name__}: {exc}"
            time.sleep(1)
    else:
        print(f"kicad-ipc-check: never became ready. last error: {last}", file=sys.stderr)
        print("  A modal dialog owning the main loop reports exactly this. Check the", file=sys.stderr)
        print("  seeded config: containers/kicad-first-run.sh", file=sys.stderr)
        return 1

    try:
        board = kicad.get_board()
    except Exception as exc:                          # noqa: BLE001
        print(f"kicad-ipc-check: connected, but no board document: {exc}", file=sys.stderr)
        return 1

    nets = board.get_nets()
    stackup = board.get_stackup()
    layers = len(getattr(stackup, "layers", []))
    print(f"kicad-ipc-check: document has {len(nets)} net(s), stackup has {layers} layer(s)")
    if layers == 0:
        print("kicad-ipc-check: a stackup with no layers is not a board", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
