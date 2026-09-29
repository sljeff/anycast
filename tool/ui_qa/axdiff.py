#!/usr/bin/env python3
"""Diff two QA crawl state dumps (e.g. Flutter reference vs native build).

Usage: python3 tool/ui_qa/axdiff.py <dir-a> <dir-b> [--out diff.md] [--move 4] [--size 2]

Each dir is a crawl run dir containing states/<state>/axdump.json
(produced by report.py). Elements match on (type, normalized label) —
falling back to #identifier — and are reported as
missing / extra / moved / resized / enabled-flipped per state.

The Flutter build's AX tree is coarser (labels come from semantics nodes),
so expect some unmatched noise on unlabeled decorative nodes; the valuable
signal is on labeled controls and text.
"""
import argparse
import json
import re
import sys
from pathlib import Path

MOVE_TOL_DEFAULT = 4.0
SIZE_TOL_DEFAULT = 2.0


def norm(label: str) -> str:
    return re.sub(r"\s+", " ", (label or "").strip().lower())


# Elements worth comparing across runtimes: the Flutter semantics tree and
# the UIKit view tree diverge wildly at the container level, so only
# labeled/identified nodes carry a trustworthy signal. Keyboard/system
# chrome leaks in when a field stayed focused during a capture.
_DROP_TYPES = {"key", "keyboard", "window", "statusBar"}


def keep(el) -> bool:
    if el.get("type") in _DROP_TYPES:
        return False
    # Normalize the label the same way element_key does, so an element kept
    # here always has a matchable key (label or identifier) — the unlabeled
    # "nearest frame" re-pairing that used to live in match_elements could
    # never see one of these.
    label = norm(el.get("label") or "")
    ident = el.get("identifier") or ""
    if not label and not ident:
        return False
    if "scroll bar" in label.lower() or ident.startswith("PopoverDismissRegion"):
        return False
    f = el.get("frame") or [0, 0, 0, 0]
    if f[2] <= 0 or f[3] <= 0:
        return False
    return True


def load_states(run_dir: Path):
    states = {}
    states_root = run_dir / "states"
    if not states_root.exists():
        return states
    for state_dir in states_root.iterdir():
        dump = state_dir / "axdump.json"
        if dump.exists():
            data = json.loads(dump.read_text())
            states[state_dir.name] = [e for e in data.get("elements", []) if keep(e)]
    return states


def element_key(el) -> str:
    label = norm(el.get("label", ""))
    if label:
        return f"{el['type']}|{label}"
    ident = el.get("identifier", "")
    if ident:
        return f"{el['type']}|#{ident}"
    return f"{el['type']}|@"


def center(el):
    f = el["frame"]
    return (f[0] + f[2] / 2, f[1] + f[3] / 2)


def match_elements(a_list, b_list):
    """Return (matched pairs, missing_in_b, extra_in_b)."""
    buckets = {}
    for el in b_list:
        buckets.setdefault(element_key(el), []).append(el)
    matched, missing = [], []
    for el in a_list:
        key = element_key(el)
        candidates = buckets.get(key, [])
        if not candidates:
            missing.append(el)
            continue
        # nearest center wins when the key is duplicated
        cx, cy = center(el)
        best = min(candidates, key=lambda c: (center(c)[0] - cx) ** 2 + (center(c)[1] - cy) ** 2)
        candidates.remove(best)
        matched.append((el, best))
    extra = [el for bucket in buckets.values() for el in bucket]
    return matched, missing, extra


def describe(el) -> str:
    label = el.get("label") or ""
    ident = el.get("identifier") or ""
    f = [round(v) for v in el["frame"]]
    tag = f" '{label[:40]}'" if label else (f" #{ident}" if ident else "")
    return f"{el['type']}{tag}@({f[0]},{f[1]},{f[2]}x{f[3]})"


def diff_states(a_states, b_states, move_tol, size_tol):
    lines = []
    states = sorted(set(a_states) | set(b_states))
    totals = {"missing": 0, "extra": 0, "moved": 0, "resized": 0, "flipped": 0}
    for state in states:
        if state not in a_states:
            lines.append(f"\n## {state} — only in B (new state)\n")
            continue
        if state not in b_states:
            lines.append(f"\n## {state} — only in A (state never reached)\n")
            continue
        matched, missing, extra = match_elements(a_states[state], b_states[state])
        rows = []
        for el in missing:
            totals["missing"] += 1
            rows.append(("missing-in-B", describe(el), ""))
        for el in extra:
            totals["extra"] += 1
            rows.append(("extra-in-B", describe(el), ""))
        for a, b in matched:
            af, bf = a["frame"], b["frame"]
            dx, dy = bf[0] - af[0], bf[1] - af[1]
            dw, dh = bf[2] - af[2], bf[3] - af[3]
            if abs(dx) > move_tol or abs(dy) > move_tol:
                totals["moved"] += 1
                rows.append(("moved", describe(a), f"Δ({dx:+.0f},{dy:+.0f})"))
            if abs(dw) > size_tol or abs(dh) > size_tol:
                totals["resized"] += 1
                rows.append(("resized", describe(a), f"Δ({dw:+.0f}x{dh:+.0f})"))
            if a.get("enabled") != b.get("enabled"):
                totals["flipped"] += 1
                rows.append(("enabled-flip", describe(a), f"{a.get('enabled')}→{b.get('enabled')}"))
        if rows:
            lines.append(f"\n## {state} — {len(rows)} diffs\n")
            lines.append("| kind | element | delta |")
            lines.append("|---|---|---|")
            for kind, el, delta in rows:
                lines.append(f"| {kind} | `{el}` | {delta} |")
    header = (
        f"**Totals:** missing-in-B {totals['missing']}, extra-in-B {totals['extra']}, "
        f"moved {totals['moved']}, resized {totals['resized']}, "
        f"enabled-flips {totals['flipped']}\n"
    )
    return header + "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dir_a", type=Path, help="reference run dir (e.g. Flutter)")
    parser.add_argument("dir_b", type=Path, help="candidate run dir (e.g. native)")
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--move", type=float, default=MOVE_TOL_DEFAULT)
    parser.add_argument("--size", type=float, default=SIZE_TOL_DEFAULT)
    args = parser.parse_args()

    a_states = load_states(args.dir_a)
    b_states = load_states(args.dir_b)
    if not a_states:
        print(f"no states under {args.dir_a}/states", file=sys.stderr)
        return 2
    if not b_states:
        print(f"no states under {args.dir_b}/states", file=sys.stderr)
        return 2

    body = (
        f"# AX diff: {args.dir_a.name} (A) → {args.dir_b.name} (B)\n\n"
        + diff_states(a_states, b_states, args.move, args.size)
    )
    if args.out:
        args.out.write_text(body)
        print(f"[axdiff] wrote {args.out}")
    else:
        print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
