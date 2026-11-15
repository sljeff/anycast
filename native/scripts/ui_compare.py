#!/usr/bin/env python3
"""Compare fresh screen captures with the committed baselines.

    python3 scripts/ui_compare.py <captures_dir> <baselines_root> <out_dir>

Both trees use the `iOS-<major>/<name>.png` layout written by
ScreenBaselineCaptureTests. Writes `<out_dir>/summary.txt` (printed too) and
`<out_dir>/changed.png`, a contact sheet of changed/new screens as
baseline | capture pairs.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat

SCALE = 2                  # captures are @2x
STATUS_BAR_PT = 60         # masked: clock and battery differ on every run
CHANNEL_THRESHOLD = 24     # per-channel diff that counts as a changed pixel
SAME_RATIO = 0.005         # below this a screen is "same"
DATA_PREFIXES = ("S4", "S8", "S9")  # network-fed screens vary with live data
MAX_SUMMARY_LINES = 30
SHEET_PAIR_WIDTH = 300     # each half of a pair
SHEET_COLUMNS = 3
LABEL_HEIGHT = 22
GUTTER = 12


def compare(baseline_path, capture_path):
    """Returns (status, ratio, mean_abs_diff, note)."""
    if baseline_path is None:
        return "new", 1.0, 0.0, ""
    base = Image.open(baseline_path).convert("RGB")
    cap = Image.open(capture_path).convert("RGB")
    if base.size != cap.size:
        return "changed", 1.0, 0.0, f"size {base.size[0]}x{base.size[1]} vs {cap.size[0]}x{cap.size[1]}"
    top = STATUS_BAR_PT * SCALE
    box = (0, top, base.width, base.height)
    base, cap = base.crop(box), cap.crop(box)
    diff = ImageChops.difference(base, cap)
    r, g, b = diff.split()
    worst = ImageChops.lighter(ImageChops.lighter(r, g), b)
    changed = sum(worst.histogram()[CHANNEL_THRESHOLD + 1:])
    ratio = changed / (diff.width * diff.height)
    mean = sum(ImageStat.Stat(diff).mean) / 3
    return ("same" if ratio < SAME_RATIO else "changed"), ratio, mean, ""


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10.1 has a fixed-size default only
        return ImageFont.load_default()


def thumbnail(path):
    if path is None:
        return None
    image = Image.open(path).convert("RGB")
    height = round(image.height * SHEET_PAIR_WIDTH / image.width)
    return image.resize((SHEET_PAIR_WIDTH, height), Image.LANCZOS)


def contact_sheet(rows, out_path):
    """rows: [(label, baseline_path | None, capture_path)]"""
    cells = []
    for label, baseline, capture in rows:
        cells.append((label, thumbnail(baseline), thumbnail(capture)))
    cell_height = max(c[2].height for c in cells)
    cell_width = SHEET_PAIR_WIDTH * 2 + GUTTER
    columns = min(SHEET_COLUMNS, len(cells))
    grid_rows = (len(cells) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (columns * (cell_width + GUTTER) + GUTTER,
         grid_rows * (cell_height + LABEL_HEIGHT + GUTTER) + GUTTER),
        (235, 235, 235),
    )
    draw = ImageDraw.Draw(sheet)
    small = font(13)
    for index, (label, baseline, capture) in enumerate(cells):
        x = GUTTER + (index % columns) * (cell_width + GUTTER)
        y = GUTTER + (index // columns) * (cell_height + LABEL_HEIGHT + GUTTER)
        draw.text((x, y + 3), label, fill=(20, 20, 20), font=small)
        y += LABEL_HEIGHT
        if baseline is None:
            draw.rectangle((x, y, x + SHEET_PAIR_WIDTH - 1, y + cell_height - 1), fill=(210, 210, 210))
            draw.text((x + 8, y + 8), "no baseline", fill=(90, 90, 90), font=small)
        else:
            sheet.paste(baseline, (x, y))
        sheet.paste(capture, (x + SHEET_PAIR_WIDTH + GUTTER, y))
    sheet.save(out_path)


def main(captures_dir, baselines_root, out_dir):
    captures_dir, baselines_root, out_dir = map(Path, (captures_dir, baselines_root, out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    results = {}   # name -> {os_dir: (status, ratio, mean, note)}
    sheet_rows = []
    counts = {}    # os_dir -> {status: n}
    for os_dir in sorted(p for p in captures_dir.glob("iOS-*") if p.is_dir()):
        tally = counts.setdefault(os_dir.name, {"same": 0, "changed": 0, "new": 0, "missing": 0})
        captured = set()
        for capture in sorted(os_dir.glob("*.png")):
            captured.add(capture.name)
            baseline = baselines_root / os_dir.name / capture.name
            baseline = baseline if baseline.exists() else None
            status, ratio, mean, note = compare(baseline, capture)
            tally[status] += 1
            results.setdefault(capture.stem, {})[os_dir.name] = (status, ratio, mean, note)
            if status != "same":
                label = f"{os_dir.name} {capture.stem}  {status}"
                if status == "changed":
                    label += f" {ratio:.1%}"
                sheet_rows.append((label, baseline, capture))
        # A baseline with no capture means the test did not produce it.
        for baseline in sorted((baselines_root / os_dir.name).glob("*.png")):
            if baseline.name not in captured:
                tally["missing"] += 1
                results.setdefault(baseline.stem, {})[os_dir.name] = ("missing", 0.0, 0.0, "")

    lines = []
    for os_dir, tally in counts.items():
        lines.append(f"{os_dir}: " + ", ".join(f"{n} {k}" for k, n in tally.items()))
    if not counts:
        lines.append("no captures found in " + str(captures_dir))

    def sort_key(name):
        digits = "".join(c for c in name.split("-")[0] if c.isdigit())
        return (int(digits) if digits else 999, name)

    detail = []
    same_names = []
    for name in sorted(results, key=sort_key):
        parts = []
        for os_dir, (status, ratio, mean, note) in sorted(results[name].items()):
            if status == "same":
                same_names.append(f"{name}@{os_dir[4:]}")
                continue
            text = f"{os_dir[4:]}: {status}"
            if status == "changed":
                text += f" {ratio:.1%} (mad {mean:.1f})" + (f" [{note}]" if note else "")
            parts.append(text)
        if parts:
            tag = " (data)" if name.startswith(DATA_PREFIXES) else ""
            detail.append(f"{name}{tag}: " + " | ".join(parts))
    lines += detail
    if same_names:
        lines.append("same: " + ", ".join(same_names))

    if len(lines) > MAX_SUMMARY_LINES:
        extra = len(lines) - (MAX_SUMMARY_LINES - 1)
        lines = lines[:MAX_SUMMARY_LINES - 1] + [f"... {extra} more lines omitted"]

    if sheet_rows:
        contact_sheet(sheet_rows, out_dir / "changed.png")
        if len(lines) < MAX_SUMMARY_LINES:
            lines.append(f"sheet: {out_dir / 'changed.png'}")
    summary = "\n".join(lines) + "\n"
    (out_dir / "summary.txt").write_text(summary)
    print(summary, end="")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
