"""Convert SpellActivationOverlay's Eclipse texture into Media/Eclipse_Moon.tga.

    python Tools/make_eclipse.py [path to SAO's textures/eclipse_moon.blp]

The druid's Eclipse proc alert (#115, docs/PLAN-procs.md) uses SAO's own eclipse_moon.blp: the
client's fileDataID 450914 isn't usable on Forever (SAO's textures/texname.lua). The BLP is SAO's
(MIT, LICENSE's third-party section). Pillow reads BLP; the output is an uncompressed 32-bit TGA,
the format Media/ already ships (Tools/make_lock.py). Media/Eclipse_Moon.tga is the committed
output; run this again only if SAO's file changes.
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Eclipse_Moon.tga")
SRC = os.path.join(os.path.dirname(ROOT), "References", "Addons", "Combat", "SpellActivationOverlay",
                   "SpellActivationOverlay", "textures", "eclipse_moon.blp")


def write_tga(path, img):
    """img: a Pillow RGBA image. Bottom-up rows, BGRA, as make_lock.py writes."""
    w, h = img.size
    px = np.asarray(img, dtype=np.uint8)
    bgra = px[::-1, :, [2, 1, 0, 3]]
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    w & 255, w >> 8, h & 255, h >> 8, 32, 0x08])
    with open(path, "wb") as f:
        f.write(header)
        f.write(bgra.tobytes())


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    img = Image.open(src).convert("RGBA")
    write_tga(OUT, img)
    print("wrote", OUT, img.size)


if __name__ == "__main__":
    main()
