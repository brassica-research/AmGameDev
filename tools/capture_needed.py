#!/usr/bin/env python3
"""Would a new capture actually look different?

Run this BEFORE bumping demo/capture-request.txt. A capture costs ~16
minutes of runner time and produces a byte-identical film if nothing
that affects rendering changed — which happened, and left a finished
run looking indistinguishable from a hung one for eighteen hours.

    python3 tools/capture_needed.py [<base-ref>]

Exit 0 = film it. Exit 1 = don't; nothing on screen would change.
"""
import subprocess
import sys

# Anything that can change a pixel or a simulated event.
RENDER_AFFECTING = (
    "game/src/presentation/",   # scenes, figures, scenery, look dev
    "game/src/sim/",            # what actually happens on screen
    "game/src/world/",
    "game/src/combat/",
    "game/src/campaign/",
    "game/data/",               # missions, cutscenes, worlds
    "game/scenes/",
    "game/assets/",
    "game/project.godot",
    ".github/workflows/demo-capture.yml",   # framing, length, flags
)

# Changes that never reach the screen.
NEVER_RENDERS = (
    "game/tests/",
    "docs/",
    "demo/",
    "README",
    "tools/",
)


def changed_files(base: str) -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    # Include uncommitted work too — usually the point of the check.
    out += subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    return sorted(set(out))


def last_capture() -> str:
    """The commit that produced the film currently on the branch.

    That is the honest baseline: the question is never "does this branch
    contain art changes" but "has anything changed SINCE the last film".
    """
    out = subprocess.run(
        ["git", "log", "-1", "--format=%H", "--", "demo/demo.mp4"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return out or "origin/main"


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else last_capture()
    files = changed_files(base)
    short = base[:7] if len(base) > 12 else base
    print("Comparing against the last filmed commit: %s" % short)
    if not files:
        print("Nothing has changed since that film — nothing to shoot.")
        return 1
    render = [f for f in files
              if f.startswith(RENDER_AFFECTING) and not f.startswith(NEVER_RENDERS)]
    inert = [f for f in files if f not in render]
    if render:
        print("FILM IT — %d change(s) reach the screen:" % len(render))
        for f in render:
            print("   ", f)
        if inert:
            print("(%d other file(s) ignored: tests, docs, tooling.)" % len(inert))
        return 0
    print("SKIP — nothing here changes a pixel. Changed files:")
    for f in files:
        print("   ", f)
    print("\nA capture would render a byte-identical film and commit no new")
    print("footage. Deliver the existing film instead, or make a rendering")
    print("change first.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
