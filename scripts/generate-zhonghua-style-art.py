#!/usr/bin/env python3
"""Regenerate the locally authored Zhonghua-themed DeskPuff package artwork."""

from pathlib import Path
import math
import random

from PIL import Image, ImageDraw, ImageEnhance, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
BOX = ROOT / "Sources/DeskPuff/Resources/StylePackages/cigarette-boxes/zhonghua-classic"
TRAY = ROOT / "Sources/DeskPuff/Resources/StylePackages/ashtrays/zhonghua-porcelain"
RED = (173, 17, 30)
GOLD = (226, 187, 105)
GOLD_LIGHT = (250, 226, 164)
GOLD_DARK = (116, 67, 27)
SONGTI = "/System/Library/Fonts/Supplemental/Songti.ttc"
HEITI = "/System/Library/Fonts/STHeiti Medium.ttc"


def font(size: int, style: str = "song") -> ImageFont.FreeTypeFont:
    path, index = (SONGTI, 0) if style == "song" else (HEITI, 1)
    return ImageFont.truetype(path, size, index=index)


def metallic_gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(height):
        t = y / max(1, height - 1)
        for x in range(width):
            sheen = 0.07 * math.exp(-((x / max(1, width - 1) - 0.34) / 0.18) ** 2)
            pixels[x, y] = tuple(min(255, max(0, int(a * (1 - t) + b * t + 255 * sheen))) for a, b in zip(top, bottom))
    return image


def paper_texture(image: Image.Image, seed: int, amount: int = 4) -> Image.Image:
    random.seed(seed)
    noise = Image.new("L", image.size)
    noise.putdata([random.randrange(120, 136) for _ in range(image.width * image.height)])
    noise = noise.filter(ImageFilter.GaussianBlur(0.65))
    overlay = Image.new("RGB", image.size, (255, 255, 255))
    blend = Image.blend(image.convert("RGB"), overlay, 0.025)
    return Image.blend(blend, Image.composite(blend, image.convert("RGB"), noise), amount / 100)


def glaze_highlight(size: tuple[int, int], bounds: tuple[int, int, int, int], strength: int, blur: int) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(bounds, fill=(255, 237, 195, strength))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def draw_centered(draw: ImageDraw.ImageDraw, point: tuple[int, int], text: str, typeface: ImageFont.FreeTypeFont,
                  fill: tuple[int, int, int], stroke: int = 0, stroke_fill: tuple[int, int, int] = GOLD_DARK) -> None:
    draw.text(point, text, font=typeface, fill=fill, anchor="mm", stroke_width=stroke, stroke_fill=stroke_fill)


def draw_building(draw: ImageDraw.ImageDraw, center_x: int, top: int, scale: float = 1.0, line: int = 4) -> None:
    """Small engraved Tiananmen-inspired gate, drawn as fine gold foil strokes."""
    def xy(x: float, y: float) -> tuple[int, int]:
        return round(center_x + x * scale), round(top + y * scale)

    shadow = tuple(int(v * 0.58) for v in GOLD_DARK)
    for offset, color, width in [(3, shadow, line + 2), (0, GOLD_LIGHT, line)]:
        d = draw
        def poly(coords: list[tuple[float, float]], fill=None, outline=color, w=width):
            pts = [xy(x, y + offset) for x, y in coords]
            if fill:
                d.polygon(pts, fill=fill)
            d.line(pts + [pts[0]], fill=outline, width=max(1, w), joint="curve")
        # Three tiered tiled roofs and central tower.
        poly([(-148, 58), (-122, 45), (-96, 24), (-82, 44), (-34, 36), (0, 18), (34, 36), (82, 44), (96, 24), (122, 45), (148, 58)])
        poly([(-125, 65), (-100, 54), (-78, 40), (-65, 56), (-25, 50), (0, 35), (25, 50), (65, 56), (78, 40), (100, 54), (125, 65)])
        poly([(-106, 75), (-79, 66), (-54, 62), (-34, 55), (0, 44), (34, 55), (54, 62), (79, 66), (106, 75)])
        d.rectangle([xy(-112, 76), xy(112, 154)], outline=color, width=max(1, width))
        d.line([xy(-112, 100), xy(112, 100)], fill=color, width=max(1, width - 1))
        d.line([xy(-124, 154), xy(124, 154)], fill=color, width=max(1, width))
        d.line([xy(-139, 163), xy(139, 163)], fill=color, width=max(1, width + 1))
        # Pillars, doorways, windows and the flag mast.
        for x in [-93, -67, -38, 0, 38, 67, 93]:
            d.line([xy(x, 104), xy(x, 153)], fill=color, width=max(1, width - 1))
        d.rectangle([xy(-22, 111), xy(22, 154)], outline=color, width=max(1, width - 1))
        d.line([xy(0, 111), xy(0, 153)], fill=color, width=max(1, width - 1))
        d.line([xy(0, 18), xy(0, -6)], fill=color, width=max(1, width - 1))
        d.polygon([xy(0, -6), xy(19, 0), xy(0, 6)], fill=color)


def box_body() -> Image.Image:
    size = (640, 896)
    base = metallic_gradient(size, (195, 33, 42), (119, 5, 17))
    base = paper_texture(base, 7124, amount=5).convert("RGBA")
    overlay = Image.new("RGBA", size)
    d = ImageDraw.Draw(overlay)
    d.rounded_rectangle((22, 20, 617, 876), radius=12, outline=GOLD_DARK + (240,), width=5)
    d.rounded_rectangle((29, 27, 610, 869), radius=9, outline=GOLD_LIGHT + (230,), width=3)
    d.rounded_rectangle((40, 38, 599, 858), radius=6, outline=GOLD + (155,), width=1)
    # Narrow vertical foil glints mimic lacquered paper without a fake bevel.
    d.line((46, 48, 46, 848), fill=(255, 218, 152, 80), width=2)
    d.line((593, 48, 593, 848), fill=(75, 10, 11, 85), width=3)
    # Gold cartouche and etched landmark.
    d.rounded_rectangle((86, 130, 554, 558), radius=15, outline=GOLD_DARK + (230,), width=6)
    d.rounded_rectangle((91, 135, 549, 553), radius=12, outline=GOLD_LIGHT + (235,), width=3)
    d.ellipse((153, 174, 487, 508), outline=(236, 198, 120, 115), width=2)
    d.ellipse((163, 184, 477, 498), outline=(236, 198, 120, 75), width=1)
    draw_building(d, 320, 278, scale=1.0, line=4)
    draw_centered(d, (320, 605), "中华香烟", font(33), GOLD_LIGHT, stroke=1)
    d.line((135, 641, 505, 641), fill=GOLD + (190,), width=2)
    draw_centered(d, (320, 688), "CHUNGHWA  ·  CLASSIC", font(20, "hei"), (238, 211, 157))
    # Fine warning copy anchors the package in the Chinese hard-pack visual language.
    draw_centered(d, (320, 778), "吸烟有害健康", font(31), (255, 220, 174), stroke=1)
    draw_centered(d, (320, 819), "请勿在禁烟场所吸烟", font(22), (250, 214, 166))
    draw_centered(d, (320, 846), "20支装  ·  FILTER CIGARETTES", font(15, "hei"), (238, 198, 142))
    base = Image.alpha_composite(base, glaze_highlight(size, (-180, 38, 390, 1020), 34, 92))
    base = Image.alpha_composite(base, glaze_highlight(size, (440, 260, 760, 690), 20, 74))
    return Image.alpha_composite(base, overlay)


def lid_outside() -> Image.Image:
    size = (640, 180)
    image = metallic_gradient(size, (196, 31, 39), (128, 8, 17)).convert("RGBA")
    d = ImageDraw.Draw(image)
    d.rectangle((7, 6, 632, 173), outline=GOLD_DARK + (255,), width=5)
    d.rectangle((12, 11, 627, 168), outline=GOLD_LIGHT + (240,), width=2)
    d.line((19, 157, 621, 157), fill=(255, 222, 157, 95), width=1)
    draw_centered(d, (320, 90), "中华", font(112), GOLD_LIGHT, stroke=2)
    return image


def lid_outside_open() -> Image.Image:
    size = (640, 420)
    image = metallic_gradient(size, (194, 31, 40), (116, 6, 16)).convert("RGBA")
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((10, 10, 630, 410), radius=12, outline=GOLD_DARK + (255,), width=6)
    d.rounded_rectangle((17, 17, 623, 403), radius=9, outline=GOLD_LIGHT + (240,), width=3)
    d.ellipse((140, 50, 500, 385), outline=GOLD + (180,), width=3)
    d.ellipse((150, 60, 490, 375), outline=GOLD_LIGHT + (110,), width=1)
    draw_centered(d, (320, 205), "中华", font(122), GOLD_LIGHT, stroke=2)
    draw_centered(d, (320, 298), "CHUNGHWA", font(24, "hei"), (244, 215, 158))
    return Image.alpha_composite(image, glaze_highlight(size, (70, -90, 475, 400), 30, 70))


def pack_preview(body: Image.Image, lid: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (360, 360), (236, 234, 229, 255))
    cropped_body = body.resize((220, 308), Image.Resampling.LANCZOS)
    canvas.alpha_composite(cropped_body, (70, 38))
    canvas.alpha_composite(lid.resize((220, 62), Image.Resampling.LANCZOS), (70, 38))
    return canvas


def draw_tray_building(draw: ImageDraw.ImageDraw, center_x: int, center_y: int) -> None:
    draw_building(draw, center_x, center_y - 45, scale=0.35, line=3)


def ashtray() -> Image.Image:
    width, height = 568, 232
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    # Outer porcelain base: soft celadon-white edge, cinnabar body, warm gilding.
    shell = metallic_gradient((width, height), (238, 224, 200), (147, 107, 67)).convert("RGBA")
    alpha = Image.new("L", (width, height), 0)
    ImageDraw.Draw(alpha).ellipse((4, 5, width - 5, height - 6), fill=255)
    shell.putalpha(alpha)
    image.alpha_composite(shell)
    d = ImageDraw.Draw(image)
    d.ellipse((12, 10, width - 13, height - 15), fill=(123, 17, 28, 255), outline=GOLD_DARK + (255,), width=5)
    d.ellipse((19, 15, width - 20, height - 20), outline=GOLD_LIGHT + (245,), width=3)
    # Deep red glazed basin and concentric, polished gold rim.
    basin = metallic_gradient((width - 52, height - 55), (173, 24, 34), (76, 8, 16)).convert("RGBA")
    basin_alpha = Image.new("L", basin.size, 0)
    ImageDraw.Draw(basin_alpha).ellipse((2, 2, basin.width - 3, basin.height - 4), fill=255)
    basin.putalpha(basin_alpha)
    image.alpha_composite(basin, (26, 28))
    d = ImageDraw.Draw(image)
    d.ellipse((27, 28, width - 28, height - 30), outline=GOLD + (255,), width=4)
    d.ellipse((35, 34, width - 36, height - 37), outline=(250, 223, 158, 190), width=2)
    # The painted medallion is deliberately restrained so ashes remain visible.
    d.ellipse((198, 66, 370, 172), fill=(123, 11, 22, 155), outline=(232, 190, 105, 175), width=2)
    draw_tray_building(d, width // 2, 112)
    d.arc((45, 29, width - 46, 189), 195, 345, fill=(255, 238, 195, 160), width=2)
    # Avoid the broad blurred ellipse that bleeds above the oval rim and reads
    # as a detached rectangular gradient. Rim reflections are already drawn above.
    return image


def main() -> None:
    (BOX / "artwork").mkdir(parents=True, exist_ok=True)
    (TRAY / "artwork").mkdir(parents=True, exist_ok=True)
    body = box_body()
    lid = lid_outside()
    lid_open = lid_outside_open()
    body.save(BOX / "artwork/body.png", optimize=True)
    body.save(BOX / "artwork/body-scaled.png", optimize=True)
    lid.save(BOX / "artwork/lid-outside.png", optimize=True)
    lid_open.save(BOX / "artwork/lid-outside-open.png", optimize=True)
    pack_preview(body, lid).save(BOX / "preview.png", optimize=True)
    ashtray().save(TRAY / "artwork/ashtray.png", optimize=True)
    ashtray().resize((360, 220), Image.Resampling.LANCZOS).save(TRAY / "preview.png", optimize=True)


if __name__ == "__main__":
    main()
