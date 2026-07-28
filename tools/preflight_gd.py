#!/usr/bin/env python3
"""Catch the GDScript parse errors that only headless Godot would find.

We have lost two CI cycles and one 30-minute render to errors this
script would have found in under a second:

  1. `var x := <Variant expression>` — indexing an array literal or
     calling into a runtime-`load()`ed script yields Variant, which `:=`
     cannot infer. (Cost: a hung capture job, diagnosed as "slow".)
  2. A variable declared twice in one function. GDScript scopes to the
     whole function, not the block, so an `if`/`for` body re-declaring a
     name is a hard parse error. (Cost: one red CI run.)

Run before pushing:  python3 tools/preflight_gd.py
Exit 0 = clean, 1 = problems found.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# `:=` cannot infer from these right-hand sides.
VARIANT_RHS = (
    re.compile(r"^\[.*\]\["),            # ["a","b"][i]  -> Variant
    re.compile(r"^\w+\.get\("),          # dict.get(...) -> Variant
    re.compile(r"^\w+\.get_meta\("),     # node.get_meta -> Variant
)

FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)")
DECL = re.compile(r"^\s*var\s+(\w+)\s*(:=|:|=)")


def indent_of(raw: str) -> int:
    return len(raw) - len(raw.lstrip("\t "))


def check(path: pathlib.Path) -> list[str]:
    """Scope-aware duplicate detection.

    GDScript permits the same name in SIBLING blocks (two separate for
    loops may each declare `n`). What it refuses is a declaration that
    SHADOWS one already live in an enclosing scope. So we keep a stack
    of (indent, names) and pop everything at or deeper than the current
    line before looking for a collision.
    """
    problems: list[str] = []
    func_name = "<file scope>"
    stack: list[tuple[int, dict[str, int]]] = []
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        if not raw.strip() or raw.strip().startswith("#"):
            continue
        m = FUNC.match(raw)
        if m:
            func_name = m.group(1)
            stack = [(indent_of(raw), {})]
            continue
        d = DECL.match(raw)
        if not d:
            continue
        ind = indent_of(raw)
        while len(stack) > 1 and stack[-1][0] >= ind:
            stack.pop()
        if not stack:
            stack = [(ind, {})]
        name = d.group(1)
        clash = next(((sc[name], si) for si, (_, sc) in enumerate(stack) if name in sc), None)
        if clash is not None:
            problems.append(
                f"{path}:{n}: '{name}' shadows the declaration at line {clash[0]} "
                f"in func {func_name}() — GDScript refuses this"
            )
        else:
            stack.append((ind, {name: n}))
        # Type-inference hazards.
        if d.group(2) == ":=":
            rhs = raw.split(":=", 1)[1].strip()
            if any(p.match(rhs) for p in VARIANT_RHS):
                problems.append(
                    f"{path}:{n}: '{name} := {rhs[:44]}' cannot infer a type "
                    f"(Variant) — annotate it explicitly"
                )
    return problems


def main() -> int:
    problems: list[str] = []
    for path in sorted((ROOT / "game").rglob("*.gd")):
        problems += check(path)
    if problems:
        print("GDScript pre-flight FAILED:\n")
        for p in problems:
            print("  " + p)
        print("\nFix these before pushing — headless Godot will refuse the file.")
        return 1
    print("GDScript pre-flight clean.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
