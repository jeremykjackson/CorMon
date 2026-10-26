"""Renders the CorMon app icon (dark green monitor with a yellow heartbeat trace).

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
    # One calm stretch, then a classic P-QRS-T complex, repeated twice.
    shape = [
        (0.00, 0.0), (0.10, 0.0), (0.14, -0.10), (0.18, 0.0), (0.24, 0.0),
        (0.27, 0.16), (0.31, -1.0), (0.35, 0.55), (0.38, 0.0), (0.46, -0.18),
        (0.52, 0.0), (0.60, 0.0), (0.63, -0.10), (0.66, 0.0), (0.70, 0.0),
        (0.73, 0.16), (0.77, -1.0), (0.81, 0.55), (0.84, 0.0), (0.91, -0.18),
        (0.96, 0.0), (1.00, 0.0),
    ]
    return [(x0 + (x1 - x0) * fx, mid + amp * fy) for fx, fy in shape]


def render():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    # Squircle-ish tile with the standard macOS icon margin.
    m = 100 * SS
    tile_box = (m, m, W - m, W - m)
    radius = 185 * SS

    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (m, m + 18 * SS, W - m, W - m + 18 * SS), radius=radius, fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22 * SS))
    img.alpha_composite(shadow)

    tile = vertical_gradient((W, W), (24, 84, 58), (6, 38, 26))
    img.paste(tile, (0, 0), rounded_mask((W, W), tile_box, radius))

    # Inner "screen" recess.
    inset = 150 * SS
    screen_box = (inset, inset + 40 * SS, W - inset, W - inset - 40 * SS)
    screen_r = 70 * SS
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(screen_box, radius=screen_r, fill=(4, 26, 17, 255))
    # Bezel highlight
    d.rounded_rectangle(screen_box, radius=screen_r, outline=(70, 130, 95, 255), width=6 * SS)

    # Faint grid on the screen.
    grid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    x0, y0, x1, y1 = screen_box
    step = 62 * SS
    for x in range(x0 + step, x1, step):
        gd.line([(x, y0 + 10 * SS), (x, y1 - 10 * SS)], fill=(60, 120, 85, 70), width=2 * SS)
    for y in range(y0 + step, y1, step):
        gd.line([(x0 + 10 * SS, y), (x1 - 10 * SS, y)], fill=(60, 120, 85, 70), width=2 * SS)
    img.paste(grid, (0, 0), Image.composite(grid, Image.new("RGBA", (W, W)),
                                            rounded_mask((W, W), screen_box, screen_r)).split()[3])

    # Heartbeat trace with a warm glow.
    mid = (y0 + y1) / 2 + 30 * SS
    pts = ecg_points(x0 + 40 * SS, x1 - 40 * SS, mid, 190 * SS)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(pts, fill=(255, 205, 40, 200), width=46 * SS, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(24 * SS))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    d.line(pts, fill=(255, 208, 52, 255), width=22 * SS, joint="curve")
    d.line(pts, fill=(255, 238, 150, 255), width=7 * SS, joint="curve")
    for p in (pts[0], pts[-1]):
        r = 11 * SS
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=(255, 208, 52, 255))

    # Soft top sheen on the tile.
    sheen = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse((-W * 0.2, -W * 0.75, W * 1.2, W * 0.42), fill=(255, 255, 255, 22))
    sheen.putalpha(Image.composite(sheen.split()[3], Image.new("L", (W, W), 0),
                                   rounded_mask((W, W), tile_box, radius)))
    img.alpha_composite(sheen)

    return img.resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.icns"
    icon = render()
    icon.save(out.replace(".icns", ".png"))
    icon.save(out, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("wrote", out)
