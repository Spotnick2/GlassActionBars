"""Generate the Utility bar's lock icons into Media/ as uncompressed 32-bit TGAs.

    python Tools/make_lock.py

The generator is the source of truth; Media/LockClosed.tga and Media/LockOpen.tga are its
committed output.

The lock button (#34) toggles "Lock Action Bars". The owner's reference is FFXIV's hotbar lock:
a plain white padlock beside the icons. So: a filled body with the keyhole cut out, a round
shackle as a stroke; open = the shackle lifted with its left leg free. 64x64, white, the shape
in alpha only (LibGlass's convention), drawn smaller than the tile so it reads on the glass.
Antialiased by 4x supersampling.
"""

import os
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media")

SIZE, SS = 64, 4
BODY = (19.0, 30.0, 45.0, 51.0)   # x0, y0, x1, y1 (y down)
BODY_RADIUS = 4.0
SHACKLE_R, SHACKLE_W = 8.2, 3.6   # the arc's centre-line radius, the stroke's width
LIFT = 7.0                        # how far the open shackle rises
KEY_Y, KEY_R = 38.5, 3.0          # the keyhole's round top
SLOT_W, SLOT_BOTTOM = 2.4, 45.5   # its slot


def write_tga(name, rgba):
    """rgba: float array (h, w, 4) in 0..1, row 0 = top (LibGlass's writer, as make_rim.py)."""
    h, w, _ = rgba.shape
    px = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
    bgra = px[::-1, :, [2, 1, 0, 3]]
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    w & 255, w >> 8, h & 255, h >> 8, 32, 0x08])
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header)
        f.write(bgra.tobytes())
    print(f"  {name}.tga  {w}x{h}")


def grid():
    n = SIZE * SS
    c = (np.arange(n) + 0.5) / SS
    return np.meshgrid(c, c)          # x, y in texture pixels


def rounded_box(x, y, x0, y0, x1, y1, r):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    dx, dy = np.abs(x - cx) - hx, np.abs(y - cy) - hy
    return np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0) - r <= 0


def shackle(x, y, lift, left_leg_to):
    cx = (BODY[0] + BODY[2]) / 2
    cy = BODY[1] - 6.0 - lift
    half = SHACKLE_W / 2
    arc = (np.abs(np.hypot(x - cx, y - cy) - SHACKLE_R) <= half) & (y <= cy)
    lx, rx = cx - SHACKLE_R, cx + SHACKLE_R
    left = (np.abs(x - lx) <= half) & (y >= cy) & (y <= left_leg_to)
    right = (np.abs(x - rx) <= half) & (y >= cy) & (y <= BODY[1] + 1)
    return arc | left | right


def keyhole(x, y):
    cx = (BODY[0] + BODY[2]) / 2
    top = np.hypot(x - cx, y - KEY_Y) <= KEY_R
    slot = (np.abs(x - cx) <= SLOT_W / 2) & (y >= KEY_Y) & (y <= SLOT_BOTTOM)
    return top | slot


def lock(open_):
    x, y = grid()
    body = rounded_box(x, y, *BODY, BODY_RADIUS) & ~keyhole(x, y)
    if open_:
        cy = BODY[1] - 6.0 - LIFT
        s = shackle(x, y, LIFT, cy + 3.0)       # the left leg stops short: free of the body
    else:
        s = shackle(x, y, 0.0, BODY[1] + 1)
    a = (body | s).astype(np.float64)
    a = a.reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))
    rgba = np.ones((SIZE, SIZE, 4))
    rgba[..., 3] = a
    return rgba


def main():
    write_tga("LockClosed", lock(False))
    write_tga("LockOpen", lock(True))


if __name__ == "__main__":
    main()
