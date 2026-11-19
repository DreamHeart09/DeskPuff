#!/usr/bin/env python3
"""Render the app artwork and menu-bar SVG, then package DeskPuff icon resources."""

from io import BytesIO
import os
from pathlib import Path
import struct
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources/DeskPuff/Resources"
ARTWORK = ROOT / "assets/icons"
PREVIEW = ROOT / ".local-archive/docs/assets/DeskPuff-Icon-Preview.png"


def render_sources(output: Path) -> tuple[Image.Image, Image.Image]:
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", "/private/tmp/deskpuff-icon-clang-cache")
    env.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", "/private/tmp/deskpuff-icon-swift-cache")
    subprocess.run([
        "swift",
        str(ROOT / "scripts/render-icons.swift"),
        str(ARTWORK / "DeskPuff-AppIcon-Art.png"),
        str(ARTWORK / "DeskPuff-MenuBar.svg"),
        str(output),
    ], check=True, cwd=ROOT, env=env)
    app = Image.open(output / "AppIcon.png").convert("RGBA")
    menu = Image.open(output / "MenuBarIcon-4x.png").convert("RGBA")
    return app, menu


def write_icns(app: Image.Image, destination: Path) -> None:
    chunks = []
    # Use the same current ICNS representation families used by bundled macOS
    # application icons. The older icp4/icp5/icp6 tags decode as corrupted
    # pixels in Finder's small list-view representations on current macOS.
    for code, pixels in (("ic11", 32), ("ic12", 64), ("ic07", 128),
                         ("ic13", 256), ("ic08", 256), ("ic09", 512),
                         ("ic14", 512), ("ic10", 1024)):
        png = BytesIO()
        app.resize((pixels, pixels), Image.Resampling.LANCZOS).save(png, format="PNG")
        data = png.getvalue()
        chunks.append(code.encode("ascii") + struct.pack(">I", len(data) + 8) + data)
    payload = b"".join(chunks)
    destination.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)


def icon_preview(app: Image.Image, size: int) -> Image.Image:
    """Apply a rounded mask only to mockups; shipped artwork stays full bleed."""
    tile = app.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=round(size * 0.22), fill=255
    )
    tile.putalpha(mask)
    return tile


def make_preview(app: Image.Image, menu: Image.Image) -> None:
    canvas = Image.new("RGB", (1600, 1080), (28, 33, 37))
    d = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 27)
        small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 19)
    except OSError:
        font = small = ImageFont.load_default()
    d.text((88, 68), "DESKPUFF  /  ICON SYSTEM", fill=(209, 216, 216), font=small)
    d.text((88, 112), "Quiet smoke. Clear silhouette.", fill=(247, 244, 235), font=font)
    tile = icon_preview(app, 430)
    canvas.paste(tile, (100, 220), tile)
    d.text((100, 680), "App icon · 1024 × 1024", fill=(194, 201, 202), font=small)

    dock = Image.new("RGBA", (620, 170), (42, 45, 49, 210))
    dd = ImageDraw.Draw(dock)
    dd.rounded_rectangle((0, 0, 619, 169), radius=34, fill=(73, 77, 81, 205), outline=(166, 171, 173, 90), width=2)
    dock_icon = icon_preview(app, 112)
    dock.alpha_composite(dock_icon, (38, 25))
    for i, color in enumerate(((89, 119, 133), (132, 116, 95), (116, 135, 116), (128, 117, 142))):
        x = 190 + i * 97
        dd.rounded_rectangle((x, 38, x + 68, 112), radius=18, fill=(*color, 225))
        dd.ellipse((x + 23, 128, x + 45, 134), fill=(220, 220, 220, 180))
    canvas.paste(dock, (830, 265), dock)
    d.text((830, 455), "Dock · approximate context", fill=(194, 201, 202), font=small)

    menu_2x = menu.resize((36, 36), Image.Resampling.LANCZOS)
    d.text((830, 545), "Menu bar · light", fill=(194, 201, 202), font=small)
    light = Image.new("RGBA", (620, 80), (231, 234, 237, 255))
    light.alpha_composite(menu_2x, (292, 22))
    canvas.paste(light, (830, 580))
    d.text((830, 690), "Menu bar · dark", fill=(194, 201, 202), font=small)
    dark = Image.new("RGBA", (620, 80), (43, 47, 52, 255))
    white_menu = Image.new("RGBA", menu.size, (255, 255, 255, 0))
    white_menu.putalpha(menu.getchannel("A"))
    dark.alpha_composite(white_menu.resize((36, 36), Image.Resampling.LANCZOS), (292, 22))
    canvas.paste(dark, (830, 725))
    d.text((830, 845), "Actual menu bar glyph · 18 pt / 36 px Retina", fill=(194, 201, 202), font=small)
    actual_size = Image.new("RGBA", (72, 72), (232, 235, 238, 255))
    actual_size.alpha_composite(menu_2x, (18, 18))
    canvas.paste(actual_size, (1090, 886), actual_size)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(PREVIEW)


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="deskpuff-icon-render-") as tmp:
        app, menu = render_sources(Path(tmp))
    app = app.convert("RGBA")
    app.save(RESOURCES / "AppIcon.png")
    menu.resize((36, 36), Image.Resampling.LANCZOS).save(RESOURCES / "MenuBarIcon.png")
    write_icns(app, RESOURCES / "AppIcon.icns")
    make_preview(app, menu)
    print(f"Generated {RESOURCES / 'AppIcon.icns'}")
    print(f"Generated {RESOURCES / 'MenuBarIcon.png'}")
    print(f"Generated {PREVIEW}")


if __name__ == "__main__":
    main()
