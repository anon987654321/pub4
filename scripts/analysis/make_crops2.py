#!/usr/bin/env python3
"""Corrected crops (round 2) for the screenshot review. pyvips / libvips."""
import os
import pyvips

ROOT = "/home/z/my-project/pub4"
OUT = "/tmp/render/sheets"
GAP = 14
BG = 235


def img(path):
    return pyvips.Image.new_from_file(os.path.join(ROOT, path), access="random")


def labelled(ref, text, crop=None, scale=1.0):
    im = ref
    if crop:
        left, top, w, h = crop
        im = im.crop(left, top, w, h)
    if scale != 1.0:
        im = im.resize(scale)
    t = pyvips.Image.text(text, font="DejaVu Sans 22", dpi=72,
                          width=im.width, align="low")
    return t.join(im, "vertical", expand=True, background=BG)


def stack(rows):
    w = max(r.width for r in rows)
    rows = [r.embed(0, 0, w, r.height, background=BG) for r in rows]
    out = rows[0]
    for r in rows[1:]:
        out = out.join(r, "vertical", expand=True, background=BG, shim=GAP)
    return out


def save(image, name):
    image.jpegsave(os.path.join(OUT, name), Q=85)
    print(name, image.width, "x", image.height)


ad = img("RAILS/amber/screenshots/amber-desktop.png")
am = img("RAILS/amber/screenshots/amber-mobile.png")
dd = img("RAILS/brgen_dating/screenshots/dating-desktop.png")
tv = img("RAILS/brgen_radio/screenshots/tv-desktop.png")
rd = img("RAILS/brgen_radio/screenshots/radio-desktop.png")
rm = img("RAILS/brgen_radio/screenshots/radio-mobile.png")
bm = img("RAILS/bsdports/screenshots/bsdports-mobile.png")
mk = img("RAILS/brgen_marketplace/screenshots/marketplace-desktop.png")
md = img("RAILS/brgen_maps/screenshots/maps-desktop.png")

parts = [
    labelled(ad, "amber-desktop: wordmark + nav", crop=(380, 30, 720, 180)),
    labelled(ad, "amber-desktop: Bymorgen tile", crop=(430, 1520, 580, 360)),
    labelled(ad, "amber-desktop: footer wordmark", crop=(420, 2830, 580, 160)),
    labelled(am, "amber-mobile: tile", crop=(0, 580, 390, 320)),
    labelled(dd, "dating-desktop: pills", crop=(560, 110, 760, 200)),
    labelled(tv, "tv-desktop: chips + section", crop=(300, 200, 900, 420), scale=0.85),
    labelled(rd, "radio-desktop: Utvalgt spor + knapp", crop=(380, 380, 700, 200)),
    labelled(rm, "radio-mobile: spor label", crop=(0, 340, 390, 180)),
    labelled(bm, "bsdports-mobile: import row", crop=(0, 1350, 390, 180)),
    labelled(mk, "marketplace-desktop: hero price", crop=(60, 400, 620, 220)),
    labelled(md, "maps-desktop: nav bleed 1:1", crop=(0, 0, 720, 120)),
]
v12 = img("RAILS/mrdamascy/screenshots/12-vipps-login-mock.png")
parts.append(labelled(v12, "mrdamascy 12: buttons", crop=(0, 380, 500, 220)))
v13 = img("RAILS/mrdamascy/screenshots/13-staff-board.png")
parts.append(labelled(v13, "mrdamascy 13: status rows", crop=(0, 100, 500, 220)))
v07 = img("RAILS/mrdamascy/screenshots/07-tracking.png")
parts.append(labelled(v07, "mrdamascy 07: tail lines", crop=(0, 300, 500, 260)))
v08 = img("RAILS/mrdamascy/screenshots/08-loyalty-guest.png")
parts.append(labelled(v08, "mrdamascy 08: stempler line", crop=(0, 50, 500, 140)))

save(stack(parts), "c4-crops-d.jpg")
print("done")
