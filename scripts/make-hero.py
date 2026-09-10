#!/usr/bin/env python3
"""Composes docs/hero.png: the app sitting in a menu bar, popover open.

    python3 scripts/make-hero.py

Sources are the previews the app renders itself, so the hero never drifts from what the
app actually looks like:

    swift build && .build/debug/MonkeyClaudeUsage --render-preview <dir>
    cp <dir>/dark/popover-sixHours.png docs/screenshot.png
    cp <dir>/dark/menubar-two.png docs/menubar-two.png
"""

import os
from PIL import Image, ImageDraw, ImageFilter

DOCS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

POPOVER_WIDTH = 620
MENUBAR_HEIGHT = 50
MARGIN = 46
# Sampled from the app icon, so the plate and the icon read as the same object.
BACKGROUND_TOP = (48, 39, 35)
BACKGROUND_BOTTOM = (23, 20, 19)
MENUBAR_COLOUR = (16, 14, 13, 255)


def main() -> None:
    popover = Image.open(os.path.join(DOCS, "screenshot.png")).convert("RGBA")

    # The menu bar previews are template images — black on white — which is how macOS
    # stores them. Inverted, they are what a dark menu bar actually shows.
    mask = Image.eval(Image.open(os.path.join(DOCS, "menubar-two.png")).convert("L"),
                      lambda value: 255 - value)
    item = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    item.putalpha(mask)

    popover_height = round(popover.height * POPOVER_WIDTH / popover.width)
    width = POPOVER_WIDTH + MARGIN * 2 + 150
    height = MENUBAR_HEIGHT + popover_height + MARGIN + 14

    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    for y in range(height):
        ratio = y / height
        draw.line([(0, y), (width, y)], fill=tuple(
            round(top + (bottom - top) * ratio)
            for top, bottom in zip(BACKGROUND_TOP, BACKGROUND_BOTTOM)
        ))
    draw.rectangle([0, 0, width, MENUBAR_HEIGHT], fill=MENUBAR_COLOUR)

    # A few neighbours, so our item reads as one status item among others.
    x = width - 30
    for _ in range(3):
        draw.ellipse([x - 5, MENUBAR_HEIGHT // 2 - 5, x + 5, MENUBAR_HEIGHT // 2 + 5],
                     fill=(255, 255, 255, 55))
        x -= 30

    item_height = 32
    item_width = round(item.width * item_height / item.height)
    item = item.resize((item_width, item_height), Image.LANCZOS)
    item_x = x - item_width - 14
    canvas.alpha_composite(item, (item_x, (MENUBAR_HEIGHT - item_height) // 2))

    popover = popover.resize((POPOVER_WIDTH, popover_height), Image.LANCZOS)
    corners = Image.new("L", popover.size, 0)
    ImageDraw.Draw(corners).rounded_rectangle(
        [0, 0, POPOVER_WIDTH - 1, popover_height - 1], radius=16, fill=255)
    popover.putalpha(corners)

    # Anchored under the status item, the way AppKit places a popover.
    left = min(item_x + item_width // 2 - POPOVER_WIDTH // 2, width - POPOVER_WIDTH - MARGIN)
    top = MENUBAR_HEIGHT + 12

    shadow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left + 5, top + 9, left + POPOVER_WIDTH + 5, top + popover_height + 9],
        radius=16, fill=(0, 0, 0, 160))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16)))
    canvas.alpha_composite(popover, (left, top))

    output = os.path.join(DOCS, "hero.png")
    canvas.convert("RGB").save(output, optimize=True)
    print(f"wrote {output} ({canvas.width}×{canvas.height})")


if __name__ == "__main__":
    main()
