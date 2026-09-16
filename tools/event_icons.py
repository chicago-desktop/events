#!/usr/bin/env python3
"""Draws Event Viewer's picture: assets/images/{32,16}/event_viewer.png.

A log sheet with three entries, each with the mark of its kind — a red error,
a yellow warning, a blue information — the three kinds the classic Event
Viewer listed. Own pixel art, drawn pixel by pixel below, under the module's
licence.

Needs Pillow:

    python3 tools/event_icons.py
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "assets" / "images"

CLEAR = (0, 0, 0, 0)
BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
FACE = (192, 192, 192, 255)
SHADOW = (128, 128, 128, 255)
RED = (224, 0, 0, 255)
DARK_RED = (128, 0, 0, 255)
YELLOW = (255, 224, 0, 255)
BLUE = (0, 0, 224, 255)
NAVY = (0, 0, 128, 255)


def sheet(draw, x0, y0, x1, y1, fold):
    """A white page with a black outline and its top-right corner folded."""
    draw.polygon([(x0, y0), (x1 - fold, y0), (x1, y0 + fold), (x1, y1), (x0, y1)], fill=WHITE, outline=BLACK)
    # The fold: the turned corner in grey, its edge black.
    draw.polygon([(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)], fill=FACE, outline=BLACK)
    # A shadow along the right and bottom edges, as the icons of the era had.
    draw.line([(x0 + 1, y1 + 1), (x1 + 1, y1 + 1)], fill=SHADOW)
    draw.line([(x1 + 1, y0 + fold + 1), (x1 + 1, y1 + 1)], fill=SHADOW)


# The three marks, 9×9, one character a pixel: at this size a drawn circle
# or triangle comes out as a blob, so they are set by hand.
MARKS = {
    "error": (
        "..DDDDD..",
        ".DRRRRRD.",
        "DRWRRRWRD",
        "DRRWRWRRD",
        "DRRRWRRRD",
        "DRRWRWRRD",
        "DRWRRRWRD",
        ".DRRRRRD.",
        "..DDDDD..",
    ),
    "warning": (
        "....K....",
        "...KYK...",
        "...KYK...",
        "..KYKYK..",
        "..KYKYK..",
        ".KYYKYYK.",
        ".KYYYYYK.",
        "KYYYKYYYK",
        "KKKKKKKKK",
    ),
    "info": (
        "..NNNNN..",
        ".NBBWBBN.",
        "NBBBBBBBN",
        "NBBWWBBBN",
        "NBBBWBBBN",
        "NBBBWBBBN",
        "NBBWWWBBN",
        ".NBBBBBN.",
        "..NNNNN..",
    ),
}
INK = {"D": DARK_RED, "R": RED, "W": WHITE, "K": BLACK, "Y": YELLOW, "N": NAVY, "B": BLUE}


def mark(image, x, y, name):
    for row, line in enumerate(MARKS[name]):
        for column, char in enumerate(line):
            if char in INK:
                image.putpixel((x + column, y + row), INK[char])


def icon32():
    image = Image.new("RGBA", (32, 32), CLEAR)
    draw = ImageDraw.Draw(image)
    sheet(draw, 3, 0, 27, 30, 6)
    for y, name, length in ((3, "error", 7), (12, "warning", 5), (21, "info", 6)):
        mark(image, 6, y, name)
        # Two lines of text beside the mark, the second shorter.
        draw.line([(17, y + 2), (17 + length, y + 2)], fill=SHADOW)
        draw.line([(17, y + 5), (17 + length - 3, y + 5)], fill=SHADOW)
    return image


def icon16():
    image = Image.new("RGBA", (16, 16), CLEAR)
    draw = ImageDraw.Draw(image)
    sheet(draw, 2, 0, 13, 14, 3)
    # At 16 px a mark is its colour alone: an outline would eat it.
    for y, color in ((3, RED), (7, YELLOW), (11, BLUE)):
        draw.rectangle([4, y - 1, 6, y + 1], fill=color)
        draw.line([(8, y), (11, y)], fill=SHADOW)
    return image


def main(argv):
    root = Path(argv[1]) if len(argv) > 1 else ROOT
    for size, draw in ((32, icon32), (16, icon16)):
        target = root / str(size) / "event_viewer.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        draw().save(target, optimize=True)
        print(f"wrote {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
