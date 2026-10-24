#!/usr/bin/env python3
"""Generates Resources/AppIcon.icns and docs/icon.png.

The icon is a 24-hour timeline: green off-peak with the two red peak windows
(01:00-04:00 and 06:00-10:00 UTC) and a white "now" marker.
"""

from __future__ import annotations

import pathlib
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersampling factor
W = SIZE * SS

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
DOCS = ROOT / "docs"

GREEN = (31, 164, 95)
RED = (226, 59, 59)
WHITE = (255, 255, 255)


def gradient(size: int) -> Image.Image:
    top = np.array([14, 18, 30], dtype=np.float64)
    bottom = np.array([34, 43, 68], dtype=np.float64)
    ramp = np.linspace(0.0, 1.0, size)[:, None, None]
    pixels = top[None, None, :] * (1 - ramp) + bottom[None, None, :] * ramp
    pixels = np.repeat(pixels, size, axis=1).astype(np.uint8)
    return Image.fromarray(pixels, "RGB").convert("RGBA")


def squircle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    radius = int(size * 0.2237)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def build() -> Image.Image:
    image = gradient(W)
    image.putalpha(squircle_mask(W))

    radius = int(W * 0.2237)
    border = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        [6 * SS, 6 * SS, W - 6 * SS - 1, W - 6 * SS - 1],
        radius=radius - 4 * SS,
        outline=(255, 255, 255, 32),
        width=2 * SS,
    )
    image = Image.alpha_composite(image, border)

    left, right = int(W * 0.12), int(W * 0.88)
    bar_top, bar_bottom = int(W * 0.43), int(W * 0.57)
    bar_radius = (bar_bottom - bar_top) // 2

    def x_for(hour: float) -> float:
        return left + (right - left) * (hour / 24.0)

    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left - 6 * SS, bar_top + 10 * SS, right + 6 * SS, bar_bottom + 22 * SS],
        radius=bar_radius,
        fill=(0, 0, 0, 150),
    )
    image = Image.alpha_composite(image, shadow.filter(ImageFilter.GaussianBlur(22 * SS)))

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        [left, bar_top, right, bar_bottom], radius=bar_radius, fill=GREEN + (255,)
    )
    for start_hour, end_hour in ((1, 4), (6, 10)):
        draw.rounded_rectangle(
            [x_for(start_hour), bar_top, x_for(end_hour), bar_bottom],
            radius=10 * SS,
            fill=RED + (255,),
        )
    image = Image.alpha_composite(image, layer)

    marker_x = x_for(13.4)
    half_width = 11 * SS
    marker_top, marker_bottom = bar_top - 40 * SS, bar_bottom + 40 * SS

    marker_shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(marker_shadow).rounded_rectangle(
        [marker_x - half_width, marker_top, marker_x + half_width, marker_bottom],
        radius=half_width,
        fill=(0, 0, 0, 120),
    )
    image = Image.alpha_composite(image, marker_shadow.filter(ImageFilter.GaussianBlur(9 * SS)))

    marker = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(marker).rounded_rectangle(
        [marker_x - half_width, marker_top, marker_x + half_width, marker_bottom],
        radius=half_width,
        fill=WHITE + (255,),
    )
    image = Image.alpha_composite(image, marker)

    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    RESOURCES.mkdir(exist_ok=True)
    DOCS.mkdir(exist_ok=True)
    icon = build()
    icon.save(DOCS / "icon.png")
    icon.save(ROOT / "Resources" / "AppIcon.png")

    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        variants = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png"),
        ]
        for size, name in variants:
            icon.resize((size, size), Image.LANCZOS).save(iconset / name)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(RESOURCES / "AppIcon.icns")],
            check=True,
        )

    print(f"wrote {RESOURCES / 'AppIcon.icns'}")
    print(f"wrote {DOCS / 'icon.png'}")


if __name__ == "__main__":
    main()
