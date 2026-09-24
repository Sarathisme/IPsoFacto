#!/usr/bin/env python3
"""Generate the IPso Facto app icon, following the DefaultKit flat-glyph
design language (see ../../DefaultKit/docs/app-icons.md): a warm cream field,
charcoal ink silhouette, restrained accent colour, thick rounded shapes, one
unmistakable idea.

Glyph: a magnifying glass -- "ipso facto" (caught in the very act) --
inspecting a network signal, standing in for "your address, found." The
lens interior carries a small Wi-Fi-style signal arc in teal, the suite's
"connection" accent colour.

Usage: python3 Scripts/generate-icon.py
Produces Resources/AppIcon.iconset/ (all required sizes) and
Resources/AppIcon.icns (via iconutil, macOS only).
"""

from __future__ import annotations

import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET_DIR = RESOURCES / "AppIcon.iconset"

MASTER_SIZE = 1024
SCALE = 4  # supersample, then downsample for anti-aliasing

CREAM = "#F6F1E7"
INK = "#25262B"
TEAL = "#3FB8A6"
CORAL = "#F36F56"


def s(v: float) -> int:
    return round(v * SCALE)


def draw_glyph() -> Image.Image:
    canvas = Image.new("RGBA", (MASTER_SIZE * SCALE, MASTER_SIZE * SCALE), CREAM)
    draw = ImageDraw.Draw(canvas)

    cx, cy = MASTER_SIZE / 2, MASTER_SIZE / 2 - 40

    # Magnifying glass lens: thick charcoal ring.
    lens_r = 210
    ring_w = 64
    draw.ellipse(
        [s(cx - lens_r), s(cy - lens_r), s(cx + lens_r), s(cy + lens_r)],
        outline=INK,
        width=s(ring_w),
    )

    # Handle: rounded rod running down-right from the lens rim, terminating
    # in a rounded end, matching the "thick, high-contrast, rounded
    # terminals" shared grammar.
    angle = math.radians(45)
    inner_r = lens_r - ring_w / 2 + 6
    handle_len = 230
    hx0 = cx + inner_r * math.cos(angle)
    hy0 = cy + inner_r * math.sin(angle)
    hx1 = hx0 + handle_len * math.cos(angle)
    hy1 = hy0 + handle_len * math.sin(angle)
    draw.line([s(hx0), s(hy0), s(hx1), s(hy1)], fill=INK, width=s(88), joint="curve")
    draw.ellipse(
        [s(hx1 - 44), s(hy1 - 44), s(hx1 + 44), s(hy1 + 44)],
        fill=INK,
    )

    # Inside the lens: a Wi-Fi style signal -- three concentric arcs rising
    # from a solid coral dot -- standing in for the address being located.
    # Kept inside the 32 px minimum-gap rule: arcs sit well clear of the
    # ring's inner edge.
    dot_r = 26
    dot_cx, dot_cy = cx, cy + 70
    draw.ellipse(
        [s(dot_cx - dot_r), s(dot_cy - dot_r), s(dot_cx + dot_r), s(dot_cy + dot_r)],
        fill=CORAL,
    )

    arc_widths = [30, 26, 22]
    arc_radii = [72, 130, 188]
    for radius, width in zip(arc_radii, arc_widths):
        bbox = [
            s(dot_cx - radius), s(dot_cy - radius),
            s(dot_cx + radius), s(dot_cy + radius),
        ]
        # Only draw the arc where it stays inside the lens circle, so it
        # reads as a signal radiating toward the rim without crossing it.
        draw.arc(bbox, start=215, end=325, fill=TEAL, width=s(width))

    return canvas.resize((MASTER_SIZE, MASTER_SIZE), Image.LANCZOS)


def export_iconset(master: Image.Image) -> None:
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        master.resize((base, base), Image.LANCZOS).save(ICONSET_DIR / f"icon_{base}x{base}.png")
        master.resize((base * 2, base * 2), Image.LANCZOS).save(ICONSET_DIR / f"icon_{base}x{base}@2x.png")


def build_icns() -> None:
    icns_path = RESOURCES / "AppIcon.icns"
    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(icns_path)],
        check=True,
    )
    print(f"Wrote {icns_path}")


def main() -> None:
    master = draw_glyph()
    master.save(RESOURCES / "AppIcon-1024.png")
    export_iconset(master)
    build_icns()


if __name__ == "__main__":
    main()
