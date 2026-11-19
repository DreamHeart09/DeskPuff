#!/usr/bin/env python3
"""Align one generated closed-pack master to DeskPuff's moving-lid geometry.

The master stays intact. This script trims transparent backdrop/glow, writes a
body texture with a transparent moving-lid band, slices the matching lid print,
and exports a list preview. It never draws or rewrites package branding.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image

BODY_HEIGHT = 1376  # 2x the 688 px body template; width follows pack proportions.
PREVIEW_SIZE = (256, 356)
BODY_ASPECT = 55 / 86


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("master", type=Path)
    parser.add_argument("output", type=Path, help="package artwork/ directory")
    parser.add_argument("--seam", type=float, required=True,
                        help="lid seam as a fraction from the top edge of the trimmed pack")
    args = parser.parse_args()
    if not 0.20 <= args.seam <= 0.42:
        parser.error("--seam must be between 0.20 and 0.42")

    image = Image.open(args.master).convert("RGBA")
    alpha = image.getchannel("A")
    # Remove low-opacity generated backdrop/glow while retaining carton edges.
    alpha = alpha.point(lambda value: 0 if value < 150 else value)
    image.putalpha(alpha)
    bounds = alpha.getbbox()
    if not bounds:
        parser.error("master image has no visible pack")
    pack = image.crop(bounds)
    pack_aspect = pack.width / pack.height
    seam_y = round(pack.height * args.seam)
    body_width = round(BODY_HEIGHT * pack_aspect)
    body_seam = round(BODY_HEIGHT * args.seam)
    if seam_y <= 0 or seam_y >= pack.height:
        parser.error("seam falls outside the pack")

    args.output.mkdir(parents=True, exist_ok=True)
    # Keep the real pack ratio. Match the seam exactly to geometry.lidBandFraction,
    # then leave that moving band transparent in the body texture.
    body = pack.resize((body_width, BODY_HEIGHT), Image.Resampling.LANCZOS)
    body_alpha = body.getchannel("A")
    body_alpha.paste(0, (0, 0, body_width, body_seam))
    body.putalpha(body_alpha)
    body.save(args.output / "body.png", optimize=True)

    lid_height = round(body_width * args.seam / pack_aspect)
    lid_crop = pack.crop((0, 0, pack.width, seam_y))
    lid = lid_crop.resize((body_width, lid_height), Image.Resampling.LANCZOS)
    lid.save(args.output / "lid-outside.png", optimize=True)

    preview = pack.copy()
    preview.thumbnail(PREVIEW_SIZE, Image.Resampling.LANCZOS)
    preview_canvas = Image.new("RGBA", PREVIEW_SIZE, (0, 0, 0, 0))
    preview_canvas.alpha_composite(preview, ((PREVIEW_SIZE[0] - preview.width) // 2,
                                              (PREVIEW_SIZE[1] - preview.height) // 2))
    preview_canvas.save(args.output.parent / "preview.png", optimize=True)
    print(f"aspect={pack_aspect:.6f} body={body_width}x{BODY_HEIGHT} "
          f"lid={body_width}x{lid_height} seam={args.seam:.4f}")


if __name__ == "__main__":
    main()
