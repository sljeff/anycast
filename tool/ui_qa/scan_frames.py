#!/usr/bin/env python3
"""Heuristic scan over record.sh frames: flag frames worth a human look.

Usage: python3 tool/ui_qa/scan_frames.py <run-dir>
    <run-dir> is a record.sh output dir containing frames/f_*.png.

Detectors (deliberately cheap — they nominate, humans decide):
  * near-blank:  per-channel pixel stdev below ~4 (blank/void screens)
  * frozen:      >=5 consecutive byte-identical frames after a moving stretch
                 (stuck UI; a loading loop keeps animating, a frozen app does not)
  * dominant:    a single color covering >66% of the frame (giant flat shapes —
                 the oversized-lottie bug class)

Also emits contact-*.jpg grids (6 columns, labeled thumbnails) so a whole
walkthrough can be eyeballed in a few images, and writes suspicious.md.
"""
import hashlib
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    # Pillow is not part of a stock python3 install and is not vendored here;
    # it is declared in tool/ui_qa/requirements.txt.
    print(
        "scan_frames.py requires Pillow, which is not installed.\n"
        "Install it with: python3 -m pip install -r tool/ui_qa/requirements.txt",
        file=sys.stderr,
    )
    sys.exit(1)

THUMB_W = 240
COLS = 6


def frame_stats(path: Path):
    img = Image.open(path).convert("RGB")
    small = img.resize((96, 160))
    pixels = list(small.getdata())
    n = len(pixels)
    mean = [sum(p[i] for p in pixels) / n for i in range(3)]
    var = [sum((p[i] - mean[i]) ** 2 for p in pixels) / n for i in range(3)]
    std = sum(var) / 3
    # dominant color share on a coarse 16-level palette
    buckets = {}
    for p in pixels:
        key = (p[0] >> 4, p[1] >> 4, p[2] >> 4)
        buckets[key] = buckets.get(key, 0) + 1
    dominant = max(buckets.values()) / n
    digest = hashlib.md5(small.tobytes()).hexdigest()
    return std, dominant, digest


def main() -> int:
    run_dir = Path(sys.argv[1])
    frames_dir = run_dir / "frames"
    frames = sorted(frames_dir.glob("*.png"))
    if not frames:
        print(f"no frames under {frames_dir}", file=sys.stderr)
        return 2

    stats = []
    for frame in frames:
        stats.append((frame, *frame_stats(frame)))

    flags = []
    run_start = None
    for index, (frame, std, dominant, digest) in enumerate(stats):
        if std < 3.5:
            flags.append((frame.name, "near-blank", f"stdev {std:.1f}"))
        if dominant > 0.66:
            flags.append((frame.name, "dominant-color", f"{dominant:.0%} of frame"))
        if index > 0 and digest == stats[index - 1][3]:
            if run_start is None:
                run_start = index - 1
        else:
            if run_start is not None and index - run_start >= 5:
                flags.append((stats[run_start][0].name, "frozen",
                              f"{index - run_start} identical frames"))
            run_start = None
    if run_start is not None and len(stats) - run_start >= 5:
        flags.append((stats[run_start][0].name, "frozen",
                      f"{len(stats) - run_start} identical frames"))

    # Contact sheets.
    contact_dir = run_dir / "contact"
    contact_dir.mkdir(exist_ok=True)
    flagged_names = {name for name, _, _ in flags}
    for sheet_index, start in enumerate(range(0, len(frames), COLS * 8)):
        batch = frames[start:start + COLS * 8]
        rows = (len(batch) + COLS - 1) // COLS
        thumb_h = int(THUMB_W * 16 / 9)
        sheet = Image.new("RGB", (COLS * THUMB_W, rows * (thumb_h + 16)), "#111")
        draw = ImageDraw.Draw(sheet)
        for i, frame in enumerate(batch):
            img = Image.open(frame).convert("RGB")
            img.thumbnail((THUMB_W, thumb_h))
            x, y = (i % COLS) * THUMB_W, (i // COLS) * (thumb_h + 16)
            sheet.paste(img, (x, y))
            color = "#ff5555" if frame.name in flagged_names else "#cccccc"
            draw.text((x + 4, y + thumb_h + 2), frame.stem, fill=color)
        out = contact_dir / f"contact-{sheet_index:02d}.jpg"
        sheet.save(out, quality=80)

    lines = ["# Suspicious frames", ""]
    if flags:
        lines += ["| frame | flag | detail |", "|---|---|---|"]
        lines += [f"| {n} | {k} | {d} |" for n, k, d in flags]
    else:
        lines.append("nothing flagged")
    lines += ["", f"contact sheets: `contact/` ({(len(frames) + COLS * 8 - 1) // (COLS * 8)} files)"]
    (run_dir / "suspicious.md").write_text("\n".join(lines) + "\n")
    print(f"[scan] {len(frames)} frames, {len(flags)} flags → {run_dir}/suspicious.md, contact/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
