#!/usr/bin/env python3
"""Generate the IPso Facto app icon, following the DefaultKit flat-glyph
design language (see ../../DefaultKit/docs/app-icons.md): a warm cream field,
charcoal ink silhouette, restrained accent colour, thick rounded shapes, one
unmistakable idea.

Glyph: a location pin -- the universal "you are here" mark -- with a small
coral address marker and a rising teal signal arc inside its aperture,
standing in for "your address, broadcasting." A more literal read on the
app's job (find and show this Mac's address) than the earlier magnifying-
glass design, same warm cream field and restrained two-accent palette.

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

    cx = MASTER_SIZE / 2
    head_cy = 430.0
    head_r = 195.0

    # Pin silhouette: a circular head and a tapering point, drawn as two
    # filled ink shapes that visually merge into one rounded teardrop --
    # matching the shared grammar's "broad curves, no hairlines" rule.
    tangent_dx = 125.0
    tangent_y = head_cy + 150.0
    tip_y = 830.0
    draw.ellipse(
        [s(cx - head_r), s(head_cy - head_r), s(cx + head_r), s(head_cy + head_r)],
        fill=INK,
    )
    draw.polygon(
        [
            (s(cx - tangent_dx), s(tangent_y)),
            (s(cx + tangent_dx), s(tangent_y)),
            (s(cx), s(tip_y)),
        ],
        fill=INK,
    )

    # Punch a cream aperture through the head -- the pin's traditional
    # hole, and the stage for the address glyph inside it.
    hole_r = 115.0
    draw.ellipse(
        [s(cx - hole_r), s(head_cy - hole_r), s(cx + hole_r), s(head_cy + hole_r)],
        fill=CREAM,
    )

    # Inside the aperture: a coral address marker with a teal signal arc
    # rising from it -- "your address, broadcasting." Kept well clear of
    # the aperture's inner edge (32 px minimum-gap rule).
    marker_cx, marker_cy = cx, head_cy + 10.0
    dot_r = 30.0
    draw.ellipse(
        [s(marker_cx - dot_r), s(marker_cy - dot_r), s(marker_cx + dot_r), s(marker_cy + dot_r)],
        fill=CORAL,
    )
    arc_r = 68.0
    bbox = [
        s(marker_cx - arc_r), s(marker_cy - arc_r),
        s(marker_cx + arc_r), s(marker_cy + arc_r),
    ]
    draw.arc(bbox, start=205, end=335, fill=TEAL, width=s(22))

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
