#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LuckyGlass 应用图标生成器 — the app icon, rendered from `Design/LuckyMark.swift`'s geometry.

`LuckyMark` draws the in-app mark: a gradient plate with a white bracket-and-chevrons glyph,
normalised to a unit square precisely so that this script can reproduce it at 1024×1024 without a
second set of numbers to keep in sync. Everything below the `# MARK: geometry` banner is a literal
transcription of that file; change one and change the other.

Three opaque variants are written, which is what Xcode 16+ / iOS 26 asks for:

  AppIcon-Light.png    the light `LuckyMark` plate and its white glyph
  AppIcon-Dark.png     the dark palette's plate and white glyph
  AppIcon-Tinted.png   the same mark in greyscale, ready for the system tint

`Contents.json` is checked in beside the PNGs rather than written here — it is a reviewed file, not
a generated one, and it names these three filenames.

The plate runs full-bleed because iOS owns the final app-icon mask. Its `size * 0.2315` contour is
still drawn as `white.opacity(0.22)` with the original `size * 0.012` stroke, and the glyph uses the
unmodified coordinates, width, round caps and round joins from `LuckyMark`. Thus the asset and the
in-app mark share one geometry; only their outer masking differs.

Usage (no arguments):

    python3 Icon/make_icon.py

Requires Pillow. In this project's Linux workspace: `pip install pillow --break-system-packages`.
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

# MARK: - geometry (transcribed from Design/LuckyMark.swift)

#: `StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round)`.
STROKE = 0.085

#: The plate's corner radius. Unused by the icon (see departure 1) but kept so the two files can be
#: diffed line for line.
PLATE_RADIUS = 0.2315

#: `path.move(to:)` / `addLine(to:)`, one list per subpath. The bar, then the two chevrons that
#: `for start in [0.455, 0.635]` produces.
POLYLINES: list[list[tuple[float, float]]] = [
    [(0.290, 0.290), (0.290, 0.710)],
] + [
    [(start, 0.335), (start + 0.165, 0.500), (start, 0.665)]
    for start in (0.455, 0.635)
]

# MARK: - palette (transcribed from Design/LuckyTheme.swift)

#: `bloomTeal` → `accent` → `violet`, light values, `startPoint: .topLeading` to
#: `endPoint: .bottomTrailing`.
LIGHT_PLATE = ("#38D6C6", "#0E9C93", "#5B4BDB")

#: `bloomTeal` → `accent` → `violet`, dark values. `LuckyMark` resolves these through the
#: current trait collection; the alternate dark asset therefore uses the corresponding dark trio.
DARK_PLATE = ("#1E9C93", "#2ED3C6", "#9A8CFF")

#: A luminance-only rendition of the three-stop plate. The system supplies hue in tinted mode; this
#: image supplies only relative lightness and the silhouette.
TINTED_PLATE = ("#A9A9A9", "#737373", "#353535")

# MARK: - output

SIZE = 1024
#: Supersampling factor for the contour and glyph masks.
SUPERSAMPLE = 4
#: `strokeBorder(... lineWidth: size * 0.012)` around the in-app plate.
PLATE_STROKE = 0.012
#: iOS's own app-icon corner radius, used by the preview sheet only.
MASK_RADIUS = 0.2237

VARIANTS = ("Light", "Dark", "Tinted")


# MARK: - 颜色与渐变


def hex_rgb(value: str) -> tuple[int, int, int]:
    """`#RRGGBB` → a byte triple. The theme stores `0xRRGGBB`; the strings above are the same
    numbers in the form a designer can paste."""
    text = value.lstrip("#")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def ramp(stops: tuple[str, ...], count: int) -> bytes:
    """`count` evenly spaced samples of a multi-stop linear gradient, as raw RGB bytes.

    SwiftUI spaces unlocated stops evenly, so three stops put the middle one at t = 0.5.
    """
    colours = [hex_rgb(stop) for stop in stops]
    segments = len(colours) - 1
    out = bytearray()
    for index in range(count):
        position = index / (count - 1) * segments
        segment = min(int(position), segments - 1)
        fraction = position - segment
        first, second = colours[segment], colours[segment + 1]
        out += bytes(
            round(first[channel] + (second[channel] - first[channel]) * fraction)
            for channel in range(3)
        )
    return bytes(out)


def diagonal(size: int, stops: tuple[str, ...]) -> Image.Image:
    """`LinearGradient(startPoint: .topLeading, endPoint: .bottomTrailing)` on a square.

    Projected onto that axis a pixel's position is `(x + y) / 2(size - 1)`, so the gradient is
    constant along every anti-diagonal — one lookup table of `2·size - 1` samples, sliced once per
    row, builds the whole image without touching a pixel twice.
    """
    lut = ramp(stops, 2 * size - 1)
    rows = [lut[3 * y:3 * (y + size)] for y in range(size)]
    return Image.frombytes("RGB", (size, size), b"".join(rows))


# MARK: - 图形


def glyph_mask(size: int) -> Image.Image:
    """The glyph as an 8-bit coverage mask, using `LuckyMark`'s coordinates unchanged.

    Pillow's `line` rounds joins with `joint="curve"` but has no round *cap*, so a disc of the
    stroke's diameter is stamped at every vertex — covering both caps and joins exactly as
    `lineCap: .round, lineJoin: .round` does.
    """
    canvas = size * SUPERSAMPLE
    mask = Image.new("L", (canvas, canvas), 0)
    draw = ImageDraw.Draw(mask)
    width = STROKE * canvas
    radius = width / 2
    for line in POLYLINES:
        points = [(x * canvas, y * canvas) for x, y in line]
        draw.line(points, fill=255, width=max(1, round(width)), joint="curve")
        for x, y in points:
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def plate_contour(size: int) -> Image.Image:
    """`LuckyMark`'s rounded white 22%-opacity `strokeBorder`, as an alpha mask.

    The fill stays full-bleed and opaque for an App Store-safe icon. This contour preserves the
    in-app plate geometry while iOS remains responsible for clipping the outer corners.
    """
    canvas = size * SUPERSAMPLE
    width = PLATE_STROKE * canvas
    inset = width / 2
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, canvas - inset, canvas - inset),
        radius=PLATE_RADIUS * canvas,
        outline=round(255 * 0.22),
        width=max(1, round(width)),
    )
    return mask.resize((size, size), Image.LANCZOS)


def rounded_mask(size: int) -> Image.Image:
    """iOS's app-icon mask, for the preview sheet only. Never applied to a shipped PNG — the system
    owns the corners and an icon that pre-rounds them loses a ring of pixels."""
    canvas = size * SUPERSAMPLE
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, canvas - 1, canvas - 1), radius=MASK_RADIUS * canvas, fill=255
    )
    return mask.resize((size, size), Image.LANCZOS)


# MARK: - 三个变体


def build_icon(stops: tuple[str, ...], mask: Image.Image,
               contour: Image.Image) -> Image.Image:
    """One opaque plate: theme gradient, LuckyMark contour, then its white glyph."""
    icon = diagonal(SIZE, stops)
    icon.paste(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), (0, 0), contour)
    icon.paste(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), (0, 0), mask)
    return icon


def build_light(mask: Image.Image, contour: Image.Image) -> Image.Image:
    """`LuckyMark` resolved in the light appearance."""
    return build_icon(LIGHT_PLATE, mask, contour)


def build_dark(mask: Image.Image, contour: Image.Image) -> Image.Image:
    """`LuckyMark` resolved in the dark appearance."""
    return build_icon(DARK_PLATE, mask, contour)


def build_tinted(mask: Image.Image, contour: Image.Image) -> Image.Image:
    """An opaque greyscale `LuckyMark`; the system supplies the chosen tint."""
    return build_icon(TINTED_PLATE, mask, contour)


def build_preview(icons: dict[str, Image.Image]) -> Image.Image:
    """A contact sheet, masked the way iOS will mask them.

    This project is developed on Windows against a macOS runner, so the icon cannot be seen on a
    home screen until CI has built the app. The sheet is the stand-in: it is not part of the
    bundle and Xcode never reads it.
    """
    tile, gap = 256, 32
    sheet = Image.new("RGB", (tile * 3 + gap * 4, tile + gap * 2), hex_rgb("#F6F8FA"))
    shape = rounded_mask(tile)
    for index, name in enumerate(VARIANTS):
        art = icons[name].resize((tile, tile), Image.LANCZOS)
        sheet.paste(art, (gap + index * (tile + gap), gap), shape)
    return sheet


# MARK: - 入口


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    appiconset = os.path.join(here, os.pardir, "LuckyGlass", "Assets.xcassets",
                              "AppIcon.appiconset")
    os.makedirs(appiconset, exist_ok=True)

    mask = glyph_mask(SIZE)
    contour = plate_contour(SIZE)
    icons = {
        "Light": build_light(mask, contour),
        "Dark": build_dark(mask, contour),
        "Tinted": build_tinted(mask, contour),
    }
    for name in VARIANTS:
        path = os.path.join(appiconset, "AppIcon-%s.png" % name)
        # No `optimize=True`: the asset compiler re-encodes every icon anyway, and a reproducible
        # byte stream is worth more here than a few kilobytes in the repository.
        icons[name].save(path, "PNG")
        print("wrote %s (%s)" % (os.path.relpath(path, here), icons[name].mode))

    preview = os.path.join(here, "preview.png")
    build_preview(icons).save(preview, "PNG")
    print("wrote %s" % os.path.relpath(preview, here))


if __name__ == "__main__":
    main()
