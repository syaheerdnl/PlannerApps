"""Draws Bayar's app icon and notification icon, and writes every size Android and iOS need.

Run from the project root:  python3 tool/make_icons.py     (needs Pillow)
The mark is a receipt with a check: a bill, paid.
"""
import os
from PIL import Image, ImageDraw

TEAL = (14, 107, 92, 255)      # AppColors.brand
WHITE = (255, 255, 255, 255)
SS = 4                         # draw 4x bigger, then shrink: smooth edges


def receipt(draw, s, fill, check_fill):
    """A receipt (rounded top, zig-zag bottom) with a check mark, centred in an s*s canvas."""
    w, h = s * 0.46, s * 0.58
    x0, y0 = (s - w) / 2, (s - h) / 2
    r = w * 0.10
    teeth, tooth = 6, w / 6
    # body: rounded top corners, then a zig-zag along the bottom
    draw.rounded_rectangle([x0, y0, x0 + w, y0 + h * 0.9], r, fill=fill)
    pts = [(x0, y0 + h * 0.85)]
    for i in range(teeth):
        pts += [(x0 + tooth * (i + 0.5), y0 + h), (x0 + tooth * (i + 1), y0 + h * 0.85)]
    draw.polygon(pts, fill=fill)
    # check mark
    t = w * 0.095
    p1 = (x0 + w * 0.26, y0 + h * 0.43)
    p2 = (x0 + w * 0.44, y0 + h * 0.58)
    p3 = (x0 + w * 0.76, y0 + h * 0.28)
    draw.line([p1, p2, p3], fill=check_fill, width=int(t * 2), joint="curve")
    for p in (p1, p3):
        draw.ellipse([p[0] - t, p[1] - t, p[0] + t, p[1] + t], fill=check_fill)


def canvas(size, bg=None):
    return Image.new("RGBA", (size * SS, size * SS), bg or (0, 0, 0, 0))


def shrink(im, size):
    return im.resize((size, size), Image.LANCZOS)


def app_icon(size):  # full-bleed teal square; the OS rounds the corners
    im = canvas(size, TEAL)
    receipt(ImageDraw.Draw(im), size * SS, WHITE, TEAL)
    return shrink(im, size)


def foreground(size):  # Android adaptive layer: transparent, mark kept inside the central safe zone
    # Launchers crop this layer to a circle or squircle, so draw the mark at 78% size.
    inner = int(size * 0.78)
    mark = canvas(inner)
    receipt(ImageDraw.Draw(mark), inner * SS, WHITE, TEAL)
    im = canvas(size)
    off = (im.width - mark.width) // 2
    im.paste(mark, (off, off), mark)
    return shrink(im, size)


def notification(size):  # white silhouette; the check is cut out so it shows through
    im = canvas(size)
    receipt(ImageDraw.Draw(im), size * SS * 1.25, WHITE, (0, 0, 0, 0))
    # the 1.25 enlarge fills more of the small canvas; re-centre by drawing on a bigger canvas and cropping
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    mark = canvas(int(size * 1.25))
    d = ImageDraw.Draw(mark)
    receipt(d, int(size * 1.25) * SS, WHITE, (0, 0, 0, 0))
    off = ((size * SS) - mark.width) // 2
    big.paste(mark, (off, off))
    # transparent check: punch out by compositing
    return shrink(big, size)


res = "android/app/src/main/res"
legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
status = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}

for d, px in legacy.items():
    app_icon(px).save(f"{res}/mipmap-{d}/ic_launcher.png")
for d, px in adaptive.items():
    foreground(px).save(f"{res}/mipmap-{d}/ic_launcher_foreground.png")
for d, px in status.items():
    os.makedirs(f"{res}/drawable-{d}", exist_ok=True)
    notification(px).save(f"{res}/drawable-{d}/ic_stat_bayar.png")

os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w").write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n')
open(f"{res}/values/ic_launcher_background.xml", "w").write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    '    <color name="ic_launcher_background">#0E6B5C</color>\n</resources>\n')

# iOS: opaque squares (no transparency allowed), every size listed in the asset catalogue
import json
ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for img in json.load(open(f"{ios}/Contents.json"))["images"]:
    base = float(img["size"].split("x")[0]) * int(img["scale"].rstrip("x"))
    app_icon(int(round(base))).convert("RGB").save(f"{ios}/{img['filename']}")
print("icons written")
