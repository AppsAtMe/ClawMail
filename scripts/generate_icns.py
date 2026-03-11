#!/usr/bin/env python3
"""Generate AppIcon.icns from AppIcon-New.png with proper transparency."""

from PIL import Image
import subprocess
import tempfile
from pathlib import Path
import shutil

REPO_ROOT = Path(__file__).parent.parent
SOURCE_ICON = REPO_ROOT / "Sources" / "ClawMailApp" / "Resources" / "Branding" / "AppIcon-New.png"
OUTPUT_ICNS = REPO_ROOT / "Sources" / "ClawMailApp" / "Resources" / "AppIcon.icns"

def main():
    if not SOURCE_ICON.exists():
        print(f"Source icon not found: {SOURCE_ICON}")
        return
    
    # Load the source image
    img = Image.open(SOURCE_ICON).convert("RGBA")
    
    # macOS icon sizes
    size_pairs = [16, 32, 128, 256, 512]
    
    with tempfile.TemporaryDirectory() as temp_dir:
        iconset_dir = Path(temp_dir) / "AppIcon.iconset"
        iconset_dir.mkdir(parents=True, exist_ok=True)
        
        for base_size in size_pairs:
            # Standard size
            standard = img.resize((base_size, base_size), Image.Resampling.LANCZOS)
            standard.save(iconset_dir / f"icon_{base_size}x{base_size}.png")
            
            # Retina (@2x) size
            retina_size = base_size * 2
            retina = img.resize((retina_size, retina_size), Image.Resampling.LANCZOS)
            retina.save(iconset_dir / f"icon_{base_size}x{base_size}@2x.png")
            
            print(f"Generated {base_size}x{base_size} and {retina_size}x{retina_size}")
        
        # Use iconutil to create icns
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(OUTPUT_ICNS)],
            check=True,
        )
        print(f"Created: {OUTPUT_ICNS}")

if __name__ == "__main__":
    main()
