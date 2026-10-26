"""Renders the CorMon app icon (dark green grid with a single yellow heartbeat).

Usage: python3 Tools/make_icon.py Resources/AppIcon.icns
Writes the .icns plus a 1024px PNG preview next to it.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 2  # supersampling factor
W = S * SS


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    g = Image.new("RGBA", size)
    d = ImageDraw.Draw(g)
    for y in range(size[1]):
        d.line([(0, y), (size[0], y)], fill=lerp(top, bottom, y / (size[1] - 1)) + (255,))
    return g


def ecg_points(x0, x1, mid, amp):
    # A single heartbeat: flat baseline, small P wave, tall QRS spike right of center, T wave.
    shape = [
        (0.00, 0.0), (0.30, 0.0), (0.36, -0.12), (0.42, 0.0), (0.50, 0.0),
        (0.54, 0.14), (0.61, -1.0), (0.68, 0.62), (0.72, 0.0), (0.80, -0.20),
        (0.87, 0.0), (1.00, 0.0),
    ]
    return [(x0 + (x1 - x0) * fx, mid + amp * fy) for fx, fy in shape]


def render():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    # Rounded tile with the standard macOS icon margin.
    m = 100 * SS
    tile_box = (m, m, W - m, W - m)
    radius = 185 * SS
    tile_mask = rounded_mask((W, W), tile_box, radius)

    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (m, m + 18 * SS, W - m, W - m + 18 * SS), radius=radius, fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22 * SS))
    img.alpha_composite(shadow)

    # Everything below is drawn on a layer clipped to the tile, so the grid runs edge to edge.
    art = vertical_gradient((W, W), (22, 78, 54), (5, 34, 23))
    grid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(grid)
    step = 68 * SS
    x0, y0, x1, y1 = tile_box
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    # Grid lines centered on the tile.
    k = 0
    while cx - k * step >= x0 - step:
        for x in {cx - k * step, cx + k * step}:
            d.line([(x, y0), (x, y1)], fill=(90, 165, 115, 70), width=2 * SS)
        k += 1
    k = 0
    while cy - k * step >= y0 - step:
        for y in {cy - k * step, cy + k * step}:
            d.line([(x0, y), (x1, y)], fill=(90, 165, 115, 70), width=2 * SS)
        k += 1
    art.alpha_composite(grid)

    # Heartbeat trace with a warm glow, running across the full width of the tile.
    mid = cy + 40 * SS
    pts = ecg_points(x0 - 20 * SS, x1 + 20 * SS, mid, 250 * SS)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(pts, fill=(255, 205, 40, 210), width=50 * SS, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(26 * SS))
    art.alpha_composite(glow)
    d = ImageDraw.Draw(art)
    d.line(pts, fill=(255, 208, 52, 255), width=24 * SS, joint="curve")
    d.line(pts, fill=(255, 238, 150, 255), width=8 * SS, joint="curve")

    img.paste(art, (0, 0), tile_mask)
    return img.resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.icns"
    icon = render()
    icon.save(out.replace(".icns", ".png"))
    icon.save(out, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("wrote", out)
