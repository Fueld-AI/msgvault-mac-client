#!/usr/bin/env python3
"""
Generates the DMG installer background image for MailTrawl.
Output: scripts/dmg-background.png  (660 x 400 px, @1x; also writes @2x at 1320x800)

Layout (icon centres used by create-dmg):
  App icon      centre-x = 165, centre-y = 185
  Applications  centre-x = 495, centre-y = 185
"""

import math
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is required. Run:  pip3 install pillow")

# ---------------------------------------------------------------------------
# Dimensions
# ---------------------------------------------------------------------------
W, H = 660, 400
SCALE = 2          # produce @2x for Retina; create-dmg handles both

# ---------------------------------------------------------------------------
# Palette  (light, clean — forces Finder to render labels as dark, crisp text)
# ---------------------------------------------------------------------------
BG_TOP    = (245, 247, 250)    # near-white cool light
BG_BOT    = (235, 238, 243)    # very subtle grey at bottom
TEAL      = (48, 176, 199)     # SwiftUI .teal (approx)
ARROW_CLR = (48, 176, 199)


def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.ellipse([x0, y0, x0 + radius * 2, y0 + radius * 2], fill=fill)
    draw.ellipse([x1 - radius * 2, y0, x1, y0 + radius * 2], fill=fill)
    draw.ellipse([x0, y1 - radius * 2, x0 + radius * 2, y1], fill=fill)
    draw.ellipse([x1 - radius * 2, y1 - radius * 2, x1, y1], fill=fill)


def draw_arrow(draw, cx, cy, s):
    """Draw a rightward chevron arrow centred at (cx, cy), scaled by s."""
    tip_x  = cx + int(28 * s)
    tail_x = cx - int(28 * s)
    h_arm  = int(16 * s)   # half-height of arrow head wings
    shaft_h = int(7 * s)   # half-height of shaft

    # shaft
    draw.polygon([
        (tail_x, cy - shaft_h),
        (cx + int(4 * s), cy - shaft_h),
        (cx + int(4 * s), cy + shaft_h),
        (tail_x, cy + shaft_h),
    ], fill=ARROW_CLR)

    # arrowhead
    draw.polygon([
        (cx + int(4 * s), cy - h_arm),
        (tip_x, cy),
        (cx + int(4 * s), cy + h_arm),
    ], fill=ARROW_CLR)


def build_image(w, h):
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)

    # --- Vertical gradient background ---
    for y in range(h):
        t = y / (h - 1)
        draw.line([(0, y), (w, y)], fill=lerp_color(BG_TOP, BG_BOT, t))

    # --- Teal accent bar at top ---
    bar_h = max(3, int(4 * (w / W)))
    draw.rectangle([0, 0, w, bar_h], fill=TEAL)

    # --- Subtle teal wash radiating from top-centre ---
    glow_w, glow_h = int(w * 0.6), int(h * 0.5)
    glow_cx, glow_cy = w // 2, 0
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    steps = 30
    for i in range(steps, 0, -1):
        alpha = int(18 * (i / steps) ** 2)
        scale_f = i / steps
        rw = int(glow_w * scale_f)
        rh = int(glow_h * scale_f)
        gdraw.ellipse([
            glow_cx - rw, glow_cy - rh,
            glow_cx + rw, glow_cy + rh,
        ], fill=(*TEAL, alpha))
    img.paste(glow, (0, 0), glow)

    # --- App label (left icon zone) ---
    icon_cx, icon_cy = int(165 * w / W), int(185 * h / H)
    apps_cx = int(495 * w / W)

    # --- Arrow ---
    arrow_cx = (icon_cx + apps_cx) // 2
    arrow_cy = icon_cy
    draw_arrow(draw, arrow_cx, arrow_cy, w / W)

    return img


# ---------------------------------------------------------------------------
# Write @1x and @2x
# ---------------------------------------------------------------------------
script_dir = os.path.dirname(os.path.abspath(__file__))
out_1x = os.path.join(script_dir, "dmg-background.png")
out_2x = os.path.join(script_dir, "dmg-background@2x.png")

img1x = build_image(W, H)
img1x.save(out_1x, "PNG")
print(f"Saved {out_1x}  ({W}x{H})")

img2x = build_image(W * SCALE, H * SCALE)
img2x.save(out_2x, "PNG")
print(f"Saved {out_2x}  ({W*SCALE}x{H*SCALE})")
