#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw


REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "Design" / "SourceArtwork"
ICON_SOURCE = SOURCE_DIR / "app-icon-source.png"
SPLASH_SOURCE = SOURCE_DIR / "splash-image-source.png"

RESOURCE_DIR = REPO_ROOT / "Sources" / "ClawMailApp" / "Resources"
BRANDING_DIR = RESOURCE_DIR / "Branding"
APP_ICON_OUTPUT = RESOURCE_DIR / "AppIcon.icns"
APP_ICON_ARTWORK_OUTPUT = BRANDING_DIR / "AppIconArtwork.png"
SPLASH_OUTPUT = BRANDING_DIR / "SplashArtwork.png"
SPLASH_SQUARE_OUTPUT = BRANDING_DIR / "SplashArtworkSquare.png"

ICON_CANVAS_SIZE = 1024
ICON_RENDER_SIZE = 900
ICON_CORNER_RADIUS = 190
ICON_BODY_PADDING = 12
BODY_SATURATION_THRESHOLD = 18
BODY_BRIGHTNESS_THRESHOLD = 190


def load_image(path: Path) -> Image.Image:
    if not path.exists():
        raise FileNotFoundError(f"Missing required source artwork: {path}")
    return Image.open(path).convert("RGBA")


def is_icon_body_pixel(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    if alpha == 0:
        return False

    saturation = max(red, green, blue) - min(red, green, blue)
    brightness = (red + green + blue) / 3
    return saturation >= BODY_SATURATION_THRESHOLD or brightness <= BODY_BRIGHTNESS_THRESHOLD


def find_icon_body_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    pixels = image.load()
    width, height = image.size
    center_y = height // 2
    center_x = width // 2

    horizontal = [x for x in range(width) if is_icon_body_pixel(pixels[x, center_y])]
    vertical = [y for y in range(height) if is_icon_body_pixel(pixels[center_x, y])]

    if not horizontal or not vertical:
        raise RuntimeError("Could not locate the icon body in the source artwork.")

    left = max(0, min(horizontal) - ICON_BODY_PADDING)
    top = max(0, min(vertical) - ICON_BODY_PADDING)
    right = min(width, max(horizontal) + ICON_BODY_PADDING + 1)
    bottom = min(height, max(vertical) + ICON_BODY_PADDING + 1)
    return left, top, right, bottom


def normalize_icon_artwork(image: Image.Image) -> Image.Image:
    body_bounds = find_icon_body_bounds(image)
    trimmed = image.crop(body_bounds)
    resized = trimmed.resize((ICON_RENDER_SIZE, ICON_RENDER_SIZE), Image.Resampling.LANCZOS)

    mask = Image.new("L", (ICON_RENDER_SIZE, ICON_RENDER_SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (0, 0, ICON_RENDER_SIZE - 1, ICON_RENDER_SIZE - 1),
        radius=ICON_CORNER_RADIUS,
        fill=255,
    )
    resized.putalpha(mask)

    canvas = Image.new("RGBA", (ICON_CANVAS_SIZE, ICON_CANVAS_SIZE), (0, 0, 0, 0))
    offset = (
        (ICON_CANVAS_SIZE - resized.width) // 2,
        (ICON_CANVAS_SIZE - resized.height) // 2,
    )
    canvas.alpha_composite(resized, dest=offset)
    return canvas


def save_iconset(artwork: Image.Image, output_path: Path) -> None:
    size_pairs = [16, 32, 128, 256, 512]

    with tempfile.TemporaryDirectory() as temp_dir:
        iconset_dir = Path(temp_dir) / "AppIcon.iconset"
        iconset_dir.mkdir(parents=True, exist_ok=True)

        for base_size in size_pairs:
            standard = artwork.resize((base_size, base_size), Image.Resampling.LANCZOS)
            retina_size = base_size * 2
            retina = artwork.resize((retina_size, retina_size), Image.Resampling.LANCZOS)

            standard.save(iconset_dir / f"icon_{base_size}x{base_size}.png")
            retina.save(iconset_dir / f"icon_{base_size}x{base_size}@2x.png")

        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(output_path)],
            check=True,
        )


def generate_splash_assets() -> None:
    shutil.copy2(SPLASH_SOURCE, SPLASH_OUTPUT)

    splash = load_image(SPLASH_SOURCE)
    square_size = min(splash.width, splash.height)
    left = (splash.width - square_size) // 2
    top = (splash.height - square_size) // 2
    square = splash.crop((left, top, left + square_size, top + square_size))
    square.save(SPLASH_SQUARE_OUTPUT)


def main() -> None:
    BRANDING_DIR.mkdir(parents=True, exist_ok=True)

    icon_artwork = normalize_icon_artwork(load_image(ICON_SOURCE))
    icon_artwork.save(APP_ICON_ARTWORK_OUTPUT)
    save_iconset(icon_artwork, APP_ICON_OUTPUT)

    generate_splash_assets()


if __name__ == "__main__":
    main()
