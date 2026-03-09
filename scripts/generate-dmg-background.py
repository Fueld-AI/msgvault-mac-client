#!/usr/bin/env python3
"""
Generates the DMG installer background image for MsgVaultMacDesktop.
Output: scripts/dmg-background.png  (660 x 400 px, @1x; also writes @2x at 1320x800)

Layout (icon centres used by create-dmg):
  App icon      centre-x = 165, centre-y = 185
  Applications  centre-x = 495, centre-y = 185
"""

import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Pillow is required. Run:  pip3 install pillow")

# ---------------------------------------------------------------------------
# Dimensions
# ---------------------------------------------------------------------------
W, H = 660, 400
SCALE = 2          # produce @2x for Retina; create-dmg handles both

# ---------------------------------------------------------------------------
# Palette  (teal brand theme)
# ---------------------------------------------------------------------------
BG_TOP    = (18, 22, 36)       # deep navy-black
BG_BOT    = (12, 16, 28)       # slightly darker at bottom
TEAL      = (48, 176, 199)     # SwiftUI .teal (approx)
TEAL_DIM  = (32, 120, 138)
WHITE     = (255, 255, 255)
GREY_LT   = (180, 190, 205)
GREY_DK   = (80, 95, 115)
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

    # --- Subtle teal glow in the top-centre ---
    glow_w, glow_h = int(w * 0.55), int(h * 0.45)
    glow_cx, glow_cy = w // 2, 0
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    steps = 30
    for i in range(steps, 0, -1):
        alpha = int(28 * (i / steps) ** 2)
        scale_f = i / steps
        rw = int(glow_w * scale_f)
        rh = int(glow_h * scale_f)
        gdraw.ellipse([
            glow_cx - rw, glow_cy - rh,
            glow_cx + rw, glow_cy + rh,
        ], fill=(*TEAL, alpha))
    img.paste(glow, (0, 0), glow)

    # --- Thin teal accent line at top ---
    bar_h = max(2, int(3 * (w / W)))
    draw.rectangle([0, 0, w, bar_h], fill=TEAL)

    # --- App label (left icon zone) ---
    icon_cx, icon_cy = int(165 * w / W), int(185 * h / H)
    apps_cx = int(495 * w / W)

    # Icon placeholder ring (the actual icon is overlaid by create-dmg)
    ring_r = int(62 * w / W)
    draw.ellipse([
        icon_cx - ring_r, icon_cy - ring_r,
        icon_cx + ring_r, icon_cy + ring_r,
    ], outline=(*TEAL_DIM, 180), width=max(1, int(1.5 * w / W)))

    # --- Arrow ---
    arrow_cx = (icon_cx + apps_cx) // 2
    arrow_cy = icon_cy
    draw_arrow(draw, arrow_cx, arrow_cy, w / W)

    # --- Applications placeholder ring ---
    draw.ellipse([
        apps_cx - ring_r, icon_cy - ring_r,
        apps_cx + ring_r, icon_cy + ring_r,
    ], outline=(*TEAL_DIM, 180), width=max(1, int(1.5 * w / W)))

    # --- Text labels ---
    # Try to load a system font; fall back to default
    font_lg = font_sm = None
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                font_lg = ImageFont.truetype(path, int(15 * w / W))
                font_sm = ImageFont.truetype(path, int(12 * w / W))
                break
            except Exception:
                continue

    def centred_text(text, cx, cy, font, color, offset_y=0):
        if font:
            bbox = draw.textbbox((0, 0), text, font=font)
            tw = bbox[2] - bbox[0]
            draw.text((cx - tw // 2, cy + offset_y), text, font=font, fill=color)
        else:
            draw.text((cx, cy + offset_y), text, fill=color)

    label_y = icon_cy + ring_r + int(10 * h / H)
    centred_text("MsgVaultMacDesktop", icon_cx, label_y, font_lg, GREY_LT)
    centred_text("Applications", apps_cx, label_y, font_lg, GREY_LT)

    # --- Bottom hint ---
    hint_y = h - int(28 * h / H)
    centred_text(
        "Drag MsgVaultMacDesktop to the Applications folder to install",
        w // 2, hint_y, font_sm, GREY_DK,
    )

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
