#!/usr/bin/env python3
"""Organize a crawl run's exported attachments into states/ and emit report.md.

Usage: python3 tool/ui_qa/report.py <run-dir>

Reads <run-dir>/attachments/manifest.json (produced by
`xcresulttool export attachments`), moves each attachment into
<run-dir>/states/<state>/ based on its name (axdump-<state>.json /
shot-<state>), collects findings.json, and writes report.md summarizing
findings by severity with links to the state screenshots.
"""
import json
import re
import shutil
import sys
from pathlib import Path

SEVERITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "info": 3}


NAME_SUFFIX = re.compile(r"^(?P<name>.*)_\d+_[0-9A-Fa-f-]{36}$")


def iter_attachments(node):
    """Yield (name, exportedFileName) pairs from any manifest shape.

    xcresulttool's manifest exposes `suggestedHumanReadableName` like
    'shot-inbox_0_<UUID>.png' — the original XCTAttachment name is the
    leading part and the extension lives on exportedFileName.
    """
    if isinstance(node, dict):
        name = node.get("name") or node.get("attachmentName")
        exported = node.get("exportedFileName")
        if not name:
            suggested = node.get("suggestedHumanReadableName")
            if suggested and exported:
                stem = Path(str(suggested)).stem
                match = NAME_SUFFIX.match(stem)
                name = match.group("name") if match else stem
        if name and exported:
            yield str(name), str(exported)
        for value in node.values():
            yield from iter_attachments(value)
    elif isinstance(node, list):
        for item in node:
            yield from iter_attachments(item)


def main() -> int:
    run_dir = Path(sys.argv[1])
    attach_dir = run_dir / "attachments"
    manifest_path = attach_dir / "manifest.json"
    states_dir = run_dir / "states"
    states_dir.mkdir(exist_ok=True)

    pairs = list(iter_attachments(json.loads(manifest_path.read_text()))) \
        if manifest_path.exists() else []
    for name, exported in pairs:
        src = attach_dir / exported
        if not src.exists():
            # Some schema versions nest files per test directory.
            matches = list(attach_dir.rglob(exported))
            src = matches[0] if matches else src
        if not src.exists():
            continue
        if name.startswith("axdump-"):
            state = name[len("axdump-"):]
            dest = states_dir / state / "axdump.json"
        elif name.startswith("shot-"):
            state = name[len("shot-"):]
            dest = states_dir / state / "shot.png"
        elif name == "findings":
            dest = run_dir / "findings.json"
        else:
            dest = run_dir / "attachments-extra" / f"{name}{src.suffix}"
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)

    findings = []
    findings_path = run_dir / "findings.json"
    if findings_path.exists():
        findings = json.loads(findings_path.read_text())

    states = sorted(p.name for p in states_dir.iterdir() if p.is_dir())
    counts = {}
    for f in findings:
        severity = f.get("severity", "unknown")
        counts[severity] = counts.get(severity, 0) + 1
    # An unknown severity value must not crash the report — bucket it after
    # the known ones (a bare SEVERITY_ORDER.get key yields None → TypeError
    # on the first comparison) and warn so the drift is visible.
    for severity in sorted(s for s in counts if s not in SEVERITY_ORDER):
        print(f"[report] warning: unknown severity {severity!r} — bucketed last")

    # Provenance canary: a UIKit app exposes element types Flutter's semantics
    # tree can never produce (real UICollectionView/UITableView cells, text
    # fields with a native placeholderValue). Reference runs write
    # reference-app.txt; if the dumps still look like UIKit, the crawl drove
    # the wrong binary and every comparison against it is void.
    provenance_bad = []
    if (run_dir / "reference-app.txt").exists():
        for state in states:
            dump = states_dir / state / "axdump.json"
            if not dump.exists():
                continue
            try:
                elements = json.loads(dump.read_text()).get("elements", [])
            except json.JSONDecodeError:
                continue
            for e in elements:
                if e.get("type") in ("collectionView", "cell") or "placeholderValue" in e:
                    provenance_bad.append(state)
                    break

    lines = [
        f"# QA crawl report — {run_dir.name}",
        "",
        f"States captured: {len(states)}  |  "
        + "  ".join(
            f"{k}: {counts[k]}"
            for k in sorted(counts, key=lambda k: SEVERITY_ORDER.get(k, len(SEVERITY_ORDER)))
        )
        if counts else "States captured: %d  |  no findings" % len(states),
        "",
    ]
    if provenance_bad:
        lines += [
            "**REFERENCE RUN CONTAMINATED** — these states contain UIKit-only "
            "element types; the crawl captured the native app, not the "
            f"reference binary: {', '.join(provenance_bad)}",
            "",
        ]
    lines += [
        "## Findings",
        "",
        "| Severity | State | Kind | Element | Detail |",
        "|---|---|---|---|---|",
    ]
    for f in sorted(findings, key=lambda x: (SEVERITY_ORDER.get(x["severity"], 9), x["state"])):
        detail = f["detail"].replace("|", "\\|")
        element = f["element"].replace("|", "\\|")
        lines.append(f"| {f['severity']} | {f['state']} | {f['kind']} | `{element}` | {detail} |")

    lines += ["", "## States", ""]
    for state in states:
        shot = states_dir / state / "shot.png"
        dump = states_dir / state / "axdump.json"
        links = []
        if shot.exists():
            links.append(f"[shot]({shot.relative_to(run_dir)})")
        if dump.exists():
            links.append(f"[axdump]({dump.relative_to(run_dir)})")
        state_findings = [f for f in findings if f["state"] == state]
        flag = f" — {len(state_findings)} findings" if state_findings else ""
        lines.append(f"- **{state}**{flag}: {' '.join(links)}")

    (run_dir / "report.md").write_text("\n".join(lines) + "\n")
    if provenance_bad:
        print("[report] WARNING: reference run captured a UIKit binary — "
              f"native-only element types in: {', '.join(provenance_bad)}")
    print(f"[report] {len(findings)} findings, {len(states)} states → {run_dir}/report.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
