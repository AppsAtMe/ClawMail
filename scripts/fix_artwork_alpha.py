#!/usr/bin/env python3
"""Fix artwork images to have rounded transparent corners and proper alpha channels."""

from PIL import Image, ImageDraw
import sys
from pathlib import Path

BRANDING_DIR = Path(__file__).parent.parent / "Sources" / "ClawMailApp" / "Resources" / "Branding"

def add_rounded_corners(image_path: Path, output_path: Path, radius: int = 28):
    """Add rounded corners with transparency to an image."""
    img = Image.open(image_path).convert("RGBA")
    
    # Create a mask with rounded corners
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, img.width, img.height], radius=radius, fill=255)
    
    # Apply mask to image
    img.putalpha(mask)
    
    # Save
    img.save(output_path, "PNG")
    print(f"Saved: {output_path}")

def main():
    # Fix AboutArtwork.png (28px radius for hero image)
    about_path = BRANDING_DIR / "AboutArtwork.png"
    if about_path.exists():
        add_rounded_corners(about_path, about_path, radius=28)
    
    # Fix AppIcon-New.png (190px radius to match macOS icon style)
    icon_path = BRANDING_DIR / "AppIcon-New.png"
    if icon_path.exists():
        # For the app icon, we need to ensure it has proper transparency
        # The icon should already be designed for macOS, so just add alpha if missing
        img = Image.open(icon_path).convert("RGBA")
        # Check if there's any actual transparency needed
        # For macOS icons, the corners should be transparent
        mask = Image.new("L", img.size, 255)  # Start fully opaque
        draw = ImageDraw.Draw(mask)
        # macOS icons use ~22% corner radius
        radius = int(min(img.width, img.height) * 0.22)
        draw.rounded_rectangle([0, 0, img.width, img.height], radius=radius, fill=255)
        img.putalpha(mask)
        img.save(icon_path, "PNG")
        print(f"Saved: {icon_path}")

if __name__ == "__main__":
    main()
