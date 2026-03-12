#!/usr/bin/env python3
"""Fix artwork images - tighter corners for AboutArtwork, remove border for AppIconArtwork."""

from PIL import Image, ImageDraw
from pathlib import Path
import numpy as np

BRANDING_DIR = Path(__file__).parent.parent / "Sources" / "ClawMailApp" / "Resources" / "Branding"

def fix_about_artwork():
    """Tighter corners for AboutArtwork.png"""
    img = Image.open(BRANDING_DIR / "AboutArtwork.png").convert("RGBA")
    
    # Tighter radius - 18% instead of 28%
    radius = int(min(img.width, img.height) * 0.18)
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, img.width-1, img.height-1], radius=radius, fill=255)
    
    # Apply mask
    result = Image.new("RGBA", img.size, (0, 0, 0, 0))
    result.paste(img, (0, 0), mask)
    result.save(BRANDING_DIR / "AboutArtwork.png", "PNG")
    print(f"Fixed AboutArtwork.png with radius={radius}px")

def fix_app_icon_artwork():
    """Remove white border and round corners for AppIconArtwork.png"""
    img = Image.open(BRANDING_DIR / "AppIconArtwork.png").convert("RGBA")
    arr = np.array(img)
    
    # Find content bounds by looking for non-white pixels
    height, width = arr.shape[:2]
    threshold = 30
    
    rows_with_content = []
    cols_with_content = []
    
    for y in range(height):
        row = arr[y, :, :3]
        if np.any(np.abs(row.astype(int) - 254) > threshold):
            rows_with_content.append(y)
    
    for x in range(width):
        col = arr[:, x, :3]
        if np.any(np.abs(col.astype(int) - 254) > threshold):
            cols_with_content.append(x)
    
    if not rows_with_content or not cols_with_content:
        print("No content found in AppIconArtwork")
        return
    
    # Crop to content
    top = min(rows_with_content)
    bottom = max(rows_with_content)
    left = min(cols_with_content)
    right = max(cols_with_content)
    
    # Add small padding
    padding = 10
    top = max(0, top - padding)
    bottom = min(height, bottom + padding)
    left = max(0, left - padding)
    right = min(width, right + padding)
    
    cropped = img.crop((left, top, right, bottom))
    
    # Resize back to 1024x1024
    cropped = cropped.resize((1024, 1024), Image.Resampling.LANCZOS)
    
    # Apply macOS-style rounded corners (22% radius)
    radius = int(1024 * 0.22)
    mask = Image.new("L", (1024, 1024), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, 1023, 1023], radius=radius, fill=255)
    
    result = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    result.paste(cropped, (0, 0), mask)
    result.save(BRANDING_DIR / "AppIconArtwork.png", "PNG")
    print(f"Fixed AppIconArtwork.png - cropped to content and rounded corners")

def main():
    fix_about_artwork()
    fix_app_icon_artwork()

if __name__ == "__main__":
    main()
