"""Generate Glass Action Bars' own button rim into Media/ as an uncompressed 32-bit TGA.

    python Tools/make_rim.py

The generator is the source of truth; Media/ButtonRim.tga is its committed output.

Why our own: LibGlass's rims are subtle by design (rim_thin_small peaks at 86/255),
so on the action bars, once the body went clear, the outline was too faint for the
mockup even at full alpha (owner, 2026-10-13). This one has near-full alpha at its
brightest so /gab tune has headroom; the defaults keep it well below that.

The owner's constraints:
- The same geometry as LibGlass's body_mask_small: 32x32, radius 7 from an inset of
  0.5 px, 9-sliced with margins 8. The corners render 1:1 (never scale margins down),
  so the line is the width drawn here at the button's size.
- A thin, crisp line, about 1.3 px, just inside the edge.
- Strongest along the top edge and the upper corners, fading down the sides, the
  bottom edge subdued. In the 9-slice, rows 8..24 stretch over the button's middle,
  so the fade down the sides stretches with it.
- A transparent centre; the only glow is a faint band hugging the line's inside.
- White everywhere, the shape in alpha only (LibGlass's convention): colour and
  intensity are runtime decisions (vertex colour, SetAlpha).

The SDF helpers are LibGlass's Tools/make_textures.py (MIT, same author), so the
corner matches its mask exactly. If this rim moves into LibGlass (LibGlass issue),
it moves with them.
"""

import os
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media")

SIZE, INSET, RADIUS = 32, 0.5, 7          # LibGlass body_mask_small
LINE = 1.3                                 # px, the line's width inside the edge
GLOW = 1.6                                 # px, the faint band just inside the line
GLOW_ALPHA = 0.22                          # the band's strength, relative to the line
TOP, SIDE_TOP, SIDE_BOTTOM, BOTTOM = 1.0, 0.85, 0.38, 0.24   # the line's strength by height


def write_tga(name, rgba):
    """rgba: float array (h, w, 4) in 0..1, row 0 = top (LibGlass's writer)."""
    h, w, _ = rgba.shape
    assert w & (w - 1) == 0 and h & (h - 1) == 0, f"{name}: not power of two"
    px = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
    bgra = px[::-1, :, [2, 1, 0, 3]]            # flip to bottom-left origin, RGBA -> BGRA
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    w & 255, w >> 8, h & 255, h >> 8, 32, 0x08])
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header)
        f.write(bgra.tobytes())
    print(f"  {name}.tga  {w}x{h}")


def rounded_rect_sdf(w, h, inset, radius):
    """Signed distance (px) to a rounded rect inset from the texture edge; negative inside."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    cx, cy = w / 2.0, h / 2.0
    hx, hy = w / 2.0 - inset, h / 2.0 - inset
    qx = np.abs(xs - cx) - (hx - radius)
    qy = np.abs(ys - cy) - (hy - radius)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside - radius


def coverage(d, soft=0.75):
    """Antialiased fill from a signed distance: 1 inside, 0 outside."""
    return np.clip(0.5 - d / (2 * soft), 0, 1)


def band(d, lo, hi, soft=0.75):
    """Antialiased band where lo <= d <= hi (d negative inside)."""
    return coverage(d - hi, soft) * (1 - coverage(d - lo, soft))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def height_weight(size):
    """The line's strength by row: TOP over the top corner rows, SIDE_TOP at the top of
    the stretched middle, easing to SIDE_BOTTOM at its foot, BOTTOM along the bottom edge."""
    ys = np.arange(size, dtype=np.float64) + 0.5
    m0, m1 = 8.0, size - 8.0                     # the stretched middle (slice margins 8)
    w = np.empty(size)
    top = ys < m0
    mid = (ys >= m0) & (ys <= m1)
    bot = ys > m1
    w[top] = TOP + (SIDE_TOP - TOP) * smoothstep(0, m0, ys[top])
    w[mid] = SIDE_TOP + (SIDE_BOTTOM - SIDE_TOP) * smoothstep(m0, m1, ys[mid])
    w[bot] = SIDE_BOTTOM + (BOTTOM - SIDE_BOTTOM) * smoothstep(m1, size, ys[bot])
    return w[:, None]


def button_rim():
    d = rounded_rect_sdf(SIZE, SIZE, INSET, RADIUS)
    line = band(d, -LINE, 0.0, soft=0.55)
    glow = band(d, -(LINE + GLOW), -LINE, soft=0.8) * GLOW_ALPHA
    alpha = np.maximum(line, glow) * height_weight(SIZE)
    rgba = np.ones((SIZE, SIZE, 4))
    rgba[..., 3] = alpha
    return rgba


# The hover halo (#34): the same rounded boundary (radius 7) centred in 16 px of
# transparent padding, so the glow outside the line isn't clipped. 64x64,
# 9-sliced with margins 24, anchored 16 UI px beyond the button so the line sits
# on its edge. A thicker line, a soft glow outward, a faint inner fill (the wash
# over the icon). White; the warm colour is a vertex colour.
HALO, HALO_PAD = 64, 16
HALO_LINE, HALO_GLOW, HALO_GLOW_ALPHA, HALO_FILL = 2.5, 4.0, 0.55, 0.16


def button_halo():
    d = rounded_rect_sdf(HALO, HALO, HALO_PAD + INSET, RADIUS)
    line = band(d, -HALO_LINE, 0.0, soft=0.6)
    glow = np.where(d > 0, HALO_GLOW_ALPHA * np.exp(-np.maximum(d, 0) / HALO_GLOW), 0.0)
    fill = coverage(d + HALO_LINE) * HALO_FILL
    rgba = np.ones((HALO, HALO, 4))
    rgba[..., 3] = np.maximum(np.maximum(line, glow), fill)
    return rgba


def button_ripple():
    """The press ripple: a soft white disc, strongest in the middle, fading to the edge."""
    ys, xs = np.mgrid[0:64, 0:64].astype(np.float64) + 0.5
    r = np.hypot(xs - 32, ys - 32) / 31.0
    rgba = np.ones((64, 64, 4))
    rgba[..., 3] = np.clip(1 - r, 0, 1) ** 0.8 * 0.9
    return rgba


def button_mask():
    """The button's rounded square as a mask (unsliced, stretched over the button)."""
    rgba = np.ones((SIZE, SIZE, 4))
    rgba[..., 3] = coverage(rounded_rect_sdf(SIZE, SIZE, INSET, RADIUS))
    return rgba


def button_socket_rim():
    """Pearl empty socket: the lower lip catches light, the upper edge recedes.

    Same fixed corner geometry and 8 px slices as ButtonRim. No inner halo.
    This is button skin art; the shared LibGlass material remains unchanged.
    """
    d = rounded_rect_sdf(SIZE, SIZE, INSET, RADIUS)
    y = (np.arange(SIZE, dtype=np.float64) + 0.5)[:, None] / SIZE
    weight = 0.18 + 0.82 * smoothstep(0.10, 0.95, y)
    rgba = np.ones((SIZE, SIZE, 4))
    rgba[..., 3] = band(d, -1.15, 0, soft=0.55) * weight
    return rgba


def button_socket_shade():
    """White alpha texture, painted black at runtime: a narrow upper inset."""
    d = rounded_rect_sdf(SIZE, SIZE, INSET, RADIUS)
    y = (np.arange(SIZE, dtype=np.float64) + 0.5)[:, None] / SIZE
    rgba = np.ones((SIZE, SIZE, 4))
    rgba[..., 3] = band(d, -2.4, -0.3, soft=0.65) * (1 - smoothstep(0.10, 0.70, y))
    return rgba


def button_gloss():
    """Pearl's reflection on a filled button (#44): a band over the upper third.

    FFXIV's (the owner's references): an even band, brightest at the top, that
    ends in a soft but definite lower edge; that edge is what reads as a glass
    face. The first version, a bell peaking at 12% that faded out by 43%, had
    no edge and read as a faint grey haze. The edge bows down a little in the
    middle (a curved face) and is gone before the middle of the button; the
    mask at runtime rounds the corners. A static bitmap (not SetGradient, so
    SetAlpha works on Forever), BLEND white, its strength the gloss tune.
    """
    n = 64
    y = (np.arange(n, dtype=np.float64) + 0.5)[:, None] / n
    x = (np.arange(n, dtype=np.float64) + 0.5)[None, :] / n
    edge = 0.30 + 0.03 * (1 - (2 * x - 1) ** 2)          # 0.30 at the sides, 0.33 in the middle
    band = 1 - smoothstep(edge - 0.035, edge + 0.035, y)   # ~4.5 px soft edge at 64 px
    rgba = np.ones((n, n, 4))
    rgba[..., 3] = band * (1 - 0.3 * np.clip(y / 0.33, 0, 1))   # brightest at the top
    return rgba


def main():
    rim = button_rim()
    inner = rim[9:SIZE - 9, 9:SIZE - 9, 3]
    assert inner.max() == 0, "the centre must be fully transparent"
    write_tga("ButtonRim", rim)
    halo = button_halo()
    assert halo[0, 0, 3] < 0.01 and halo[0, HALO // 2, 3] < 0.05, "the halo's padding must fade out"
    write_tga("ButtonHalo", halo)
    write_tga("ButtonRipple", button_ripple())
    write_tga("ButtonMask", button_mask())
    write_tga("ButtonSocketRim", button_socket_rim())
    write_tga("ButtonSocketShade", button_socket_shade())
    write_tga("ButtonGloss", button_gloss())


if __name__ == "__main__":
    main()
