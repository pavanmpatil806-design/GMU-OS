#!/usr/bin/env python3
"""Generate the binary assets embedded in the GMU OS 64 desktop (needs Pillow + numpy).
Output goes to source/assets/ (already shipped, so building the OS does not need this)."""
import os, math, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "source", "assets")
FD = "/usr/share/fonts/opentype/inter/"
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ fonts
def make_font(path, size, name):
    f = ImageFont.truetype(path, size)
    asc, desc = f.getmetrics()
    cell_h = asc + desc + 1
    recs, data = [], bytearray()
    for code in range(32, 127):
        ch = chr(code)
        adv = int(round(f.getlength(ch)))
        w = adv + 2
        img = Image.new("L", (w, cell_h), 0)
        ImageDraw.Draw(img).text((1, 0), ch, font=f, fill=255)
        recs.append((max(adv, 1), w, len(data)))
        data += img.tobytes()
    blob = bytearray([cell_h, 0])
    for adv, w, off in recs:
        blob += struct.pack("<BBH", adv, w, off)
    blob += data
    open(os.path.join(OUT, name), "wb").write(blob)
    print(name, len(blob), "cell", cell_h)

make_font(FD + "Inter-Regular.otf", 14, "font_ui.bin")
make_font(FD + "Inter-SemiBold.otf", 14, "font_bold.bin")
make_font(FD + "Inter-SemiBold.otf", 22, "font_big.bin")

def text_image(path, size, text, name):
    f = ImageFont.truetype(path, size)
    l, t, r, b = f.getbbox(text)
    img = Image.new("L", (r + 6, b + 6), 0)
    ImageDraw.Draw(img).text((2, 2), text, font=f, fill=255)
    bb = img.getbbox()
    img = img.crop(bb)
    blob = struct.pack("<HH", img.width, img.height) + img.tobytes()
    open(os.path.join(OUT, name), "wb").write(blob)
    print(name, img.size)
    return img

text_image(FD + "Inter-Bold.otf", 64, "GMU OS", "title.bin")
text_image(FD + "Inter-Light.otf", 26, "Custom Operating System", "subtitle.bin")

# ------------------------------------------------------------------ icons
SS = 4

def grad(size, c1, c2, vertical=True):
    w, h = size
    a = np.zeros((h, w, 4), np.uint8)
    t = np.linspace(0, 1, h if vertical else w)
    for i in range(3):
        v = (c1[i] + (c2[i] - c1[i]) * t).astype(np.uint8)
        a[:, :, i] = v[:, None] if vertical else v[None, :]
    a[:, :, 3] = 255
    return Image.fromarray(a, "RGBA")

def paste_masked(img, fill_img, mask):
    img.paste(fill_img, (0, 0), mask)

def rr_mask(size, box, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, r, fill=255)
    return m

def new(n):
    return Image.new("RGBA", (n * SS, n * SS), (0, 0, 0, 0))

def finish(img, n):
    return img.resize((n, n), Image.LANCZOS)

def font_at(n, size, bold=True):
    return ImageFont.truetype(FD + ("Inter-Bold.otf" if bold else "Inter-Regular.otf"), int(size * n * SS))

def center_text(img, n, text, size, fill, dx=0, dy=0, bold=True):
    d = ImageDraw.Draw(img)
    f = font_at(n, size, bold)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    W = n * SS
    d.text(((W - (r - l)) / 2 - l + dx * W, (W - (b - t)) / 2 - t + dy * W), text, font=f, fill=fill)

def folder(n, c1=(255, 214, 90), c2=(240, 160, 30), c3=(255, 233, 150)):
    img = new(n); W = n * SS
    back = rr_mask(img.size, (W * .06, W * .2, W * .94, W * .85), W * .07)
    tab = rr_mask(img.size, (W * .06, W * .12, W * .45, W * .36), W * .06)
    paste_masked(img, grad(img.size, c3, c1), back)
    paste_masked(img, grad(img.size, c3, c1), tab)
    front = rr_mask(img.size, (W * .06, W * .32, W * .94, W * .88), W * .07)
    paste_masked(img, grad(img.size, c1, c2), front)
    return img

def icon_computer(n):
    img = new(n); W = n * SS
    d = ImageDraw.Draw(img)
    body = rr_mask(img.size, (W * .08, W * .1, W * .92, W * .72), W * .06)
    paste_masked(img, grad(img.size, (210, 222, 240), (130, 150, 185)), body)
    scr = rr_mask(img.size, (W * .14, W * .16, W * .86, W * .64), W * .03)
    paste_masked(img, grad(img.size, (90, 190, 255), (20, 90, 220)), scr)
    d.rectangle((W * .4, W * .72, W * .6, W * .84), fill=(150, 165, 195, 255))
    d.rounded_rectangle((W * .26, W * .82, W * .74, W * .9), W * .03, fill=(190, 202, 225, 255))
    return finish(img, n)

def icon_documents(n):
    return finish(folder(n), n)

def icon_pictures(n):
    img = new(n); W = n * SS
    fr = rr_mask(img.size, (W * .08, W * .12, W * .92, W * .88), W * .07)
    paste_masked(img, grad(img.size, (255, 255, 255), (215, 225, 240)), fr)
    inner = rr_mask(img.size, (W * .15, W * .2, W * .85, W * .8), W * .04)
    sky = grad(img.size, (120, 205, 255), (60, 150, 235))
    paste_masked(img, sky, inner)
    d = ImageDraw.Draw(img)
    hills = Image.new("L", img.size, 0)
    hd = ImageDraw.Draw(hills)
    hd.ellipse((W * .0, W * .52, W * .6, W * 1.1), fill=255)
    hd.ellipse((W * .35, W * .45, W * 1.0, W * 1.1), fill=255)
    hills = Image.composite(hills, Image.new("L", img.size, 0), inner)
    paste_masked(img, grad(img.size, (90, 200, 90), (40, 140, 60)), hills)
    d.ellipse((W * .6, W * .26, W * .74, W * .4), fill=(255, 235, 120, 255))
    return finish(img, n)

def icon_terminal(n):
    img = new(n); W = n * SS
    body = rr_mask(img.size, (W * .06, W * .12, W * .94, W * .88), W * .08)
    paste_masked(img, grad(img.size, (70, 78, 96), (30, 34, 44)), body)
    inner = rr_mask(img.size, (W * .1, W * .26, W * .9, W * .84), W * .05)
    paste_masked(img, grad(img.size, (38, 42, 54), (16, 18, 26)), inner)
    d = ImageDraw.Draw(img)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        cx = W * (.17 + i * .09); cy = W * .19
        d.ellipse((cx - W * .025, cy - W * .025, cx + W * .025, cy + W * .025), fill=c + (255,))
    center_text(img, n, ">_", .34, (235, 240, 250, 255), dy=.07)
    return finish(img, n)

def gear(img, cx, cy, R, fill, hole=None, teeth=8, tr=1.0):
    d = ImageDraw.Draw(img)
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        w = R * .24; l0 = R * .7; l1 = R * 1.12
        pts = [(cx + ux * l0 + px * w, cy + uy * l0 + py * w), (cx + ux * l1 + px * w * .8, cy + uy * l1 + py * w * .8),
               (cx + ux * l1 - px * w * .8, cy + uy * l1 - py * w * .8), (cx + ux * l0 - px * w, cy + uy * l0 - py * w)]
        d.polygon(pts, fill=fill)
    d.ellipse((cx - R * .85, cy - R * .85, cx + R * .85, cy + R * .85), fill=fill)
    if hole:
        d.ellipse((cx - R * .38, cy - R * .38, cx + R * .38, cy + R * .38), fill=hole)

def icon_ccomp(n):
    img = new(n); W = n * SS
    body = rr_mask(img.size, (W * .06, W * .06, W * .94, W * .94), W * .2)
    paste_masked(img, grad(img.size, (70, 170, 255), (20, 70, 215)), body)
    center_text(img, n, "C", .62, (255, 255, 255, 255), dx=-.04, dy=-.02)
    g = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gear(g, W * .74, W * .74, W * .2, (225, 232, 245, 255), hole=(35, 85, 200, 255))
    img.alpha_composite(g)
    return finish(img, n)

def icon_filemgr(n):
    img = folder(n); W = n * SS
    d = ImageDraw.Draw(img)
    cx, cy, r = W * .62, W * .62, W * .17
    d.ellipse((cx - r - W * .04, cy - r - W * .04, cx + r + W * .04, cy + r + W * .04), fill=(40, 80, 150, 255))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(190, 225, 255, 255))
    d.line((cx + r * .8, cy + r * .8, W * .9, W * .9), fill=(40, 80, 150, 255), width=int(W * .08))
    return finish(img, n)

def icon_settings(n):
    img = new(n); W = n * SS
    gear(img, W * .5, W * .5, W * .4, (150, 160, 178, 255), hole=(70, 80, 100, 255))
    g2 = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gear(g2, W * .5, W * .5, W * .39, (205, 214, 228, 255), hole=(70, 80, 100, 255))
    img.alpha_composite(g2.filter(ImageFilter.GaussianBlur(W * .004)))
    return finish(img, n)

def icon_recycle(n):
    img = new(n); W = n * SS
    d = ImageDraw.Draw(img)
    d.polygon([(W * .22, W * .28), (W * .78, W * .28), (W * .7, W * .9), (W * .3, W * .9)], fill=(168, 178, 192, 255))
    d.polygon([(W * .22, W * .28), (W * .5, W * .28), (W * .42, W * .9), (W * .3, W * .9)], fill=(205, 213, 225, 255))
    d.rounded_rectangle((W * .16, W * .16, W * .84, W * .28), W * .04, fill=(120, 132, 150, 255))
    d.rectangle((W * .4, W * .1, W * .6, W * .17), fill=(120, 132, 150, 255))
    d.ellipse((W * .34, W * .42, W * .66, W * .74), outline=(30, 140, 255, 255), width=int(W * .045))
    d.polygon([(W * .56, W * .44), (W * .68, W * .46), (W * .6, W * .56)], fill=(30, 140, 255, 255))
    return finish(img, n)

def icon_texteditor(n):
    img = new(n); W = n * SS
    pg = rr_mask(img.size, (W * .16, W * .08, W * .8, W * .92), W * .06)
    paste_masked(img, grad(img.size, (255, 255, 255), (222, 230, 242)), pg)
    d = ImageDraw.Draw(img)
    for i in range(5):
        y = W * (.26 + i * .12)
        d.line((W * .26, y, W * (.7 if i % 2 == 0 else .58), y), fill=(150, 165, 190, 255), width=int(W * .035))
    d.polygon([(W * .62, W * .72), (W * .86, W * .3), (W * .94, W * .36), (W * .7, W * .78)], fill=(255, 176, 40, 255))
    d.polygon([(W * .62, W * .72), (W * .7, W * .78), (W * .6, W * .86)], fill=(80, 80, 90, 255))
    return finish(img, n)

def circle_icon(n, c1, c2, draw_fn):
    img = new(n); W = n * SS
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).ellipse((W * .06, W * .06, W * .94, W * .94), fill=255)
    paste_masked(img, grad(img.size, c1, c2), m)
    draw_fn(img, W)
    return finish(img, n)

def icon_help(n):
    def f(img, W):
        center_text(img, n, "?", .66, (255, 255, 255, 255))
    return circle_icon(n, (80, 170, 255), (20, 90, 230), f)

def icon_about(n):
    def f(img, W):
        d = ImageDraw.Draw(img)
        d.ellipse((W * .4, W * .22, W * .6, W * .42), fill=(255, 255, 255, 255))
        d.pieslice((W * .26, W * .48, W * .74, W * 1.0), 180, 360, fill=(255, 255, 255, 255))
    return circle_icon(n, (80, 170, 255), (20, 90, 230), f)

def icon_power(n):
    def f(img, W):
        d = ImageDraw.Draw(img)
        d.arc((W * .27, W * .27, W * .73, W * .73), -55, 235, fill=(255, 255, 255, 255), width=int(W * .07))
        d.line((W * .5, W * .22, W * .5, W * .5), fill=(255, 255, 255, 255), width=int(W * .07))
    return circle_icon(n, (255, 90, 90), (200, 20, 40), f)

def icon_usb(n):
    img = new(n); W = n * SS
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((W * .24, W * .1, W * .76, W * .9), W * .08, fill=(215, 222, 235, 255))
    d.rectangle((W * .34, W * .02, W * .66, W * .2), fill=(150, 160, 180, 255))
    d.rectangle((W * .4, W * .06, W * .45, W * .14), fill=(60, 70, 90, 255))
    d.rectangle((W * .55, W * .06, W * .6, W * .14), fill=(60, 70, 90, 255))
    d.rounded_rectangle((W * .32, W * .4, W * .68, W * .8), W * .05, fill=(70, 110, 190, 255))
    return finish(img, n)

def icon_volume(n):
    img = new(n); W = n * SS
    d = ImageDraw.Draw(img)
    c = (245, 248, 255, 255)
    d.polygon([(W * .1, W * .38), (W * .3, W * .38), (W * .5, W * .2), (W * .5, W * .8), (W * .3, W * .62), (W * .1, W * .62)], fill=c)
    for r in (.17, .30):
        d.arc((W * (.48 - r), W * (.5 - r), W * (.48 + r), W * (.5 + r)), -50, 50, fill=c, width=int(W * .06))
    return finish(img, n)

def icon_search(n):
    img = new(n); W = n * SS
    d = ImageDraw.Draw(img)
    c = (215, 225, 245, 255)
    d.ellipse((W * .14, W * .14, W * .64, W * .64), outline=c, width=int(W * .09))
    d.line((W * .56, W * .56, W * .86, W * .86), fill=c, width=int(W * .1))
    return finish(img, n)

def icon_logo(n):
    img = new(n); W = n * SS
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((W * .06, W * .06, W * .94, W * .94), W * .24, fill=255)
    paste_masked(img, grad(img.size, (70, 215, 255), (30, 100, 240), vertical=False), m)
    center_text(img, n, "G", .66, (255, 255, 255, 255), dy=-.01)
    return finish(img, n)

def icon_printer(n):
    img = new(n); W = n * SS
    d = ImageDraw.Draw(img)
    # paper going in (back) and coming out (front)
    d.rounded_rectangle((W * .27, W * .08, W * .73, W * .42), W * .03, fill=(250, 252, 255, 255))
    for i in range(2):
        y = W * (.16 + i * .08)
        d.line((W * .34, y, W * .66, y), fill=(170, 185, 210, 255), width=int(W * .025))
    body = rr_mask(img.size, (W * .07, W * .34, W * .93, W * .74), W * .09)
    paste_masked(img, grad(img.size, (205, 214, 230), (120, 134, 160)), body)
    d.rounded_rectangle((W * .12, W * .40, W * .88, W * .5), W * .04, fill=(70, 82, 108, 255))
    d.ellipse((W * .74, W * .56, W * .82, W * .64), fill=(60, 220, 110, 255))
    d.rounded_rectangle((W * .22, W * .62, W * .78, W * .92), W * .03, fill=(255, 255, 255, 255))
    for i in range(3):
        y = W * (.7 + i * .067)
        d.line((W * .3, y, W * .7 if i != 2 else W * .55, y), fill=(150, 165, 195, 255), width=int(W * .025))
    return finish(img, n)

DESK = [icon_computer, icon_documents, icon_pictures, icon_terminal, icon_ccomp, icon_filemgr, icon_settings, icon_recycle, icon_printer]
SMALL = [icon_filemgr, icon_terminal, icon_ccomp, icon_texteditor, icon_settings, icon_help, icon_about, icon_power,
         icon_usb, icon_volume, icon_search, icon_logo, icon_printer]

def pack(imgs, name):
    blob = bytearray()
    for im in imgs:
        a = np.array(im.convert("RGBA"))
        # dword 0xAARRGGBB little endian = bytes B, G, R, A
        out = np.stack([a[:, :, 2], a[:, :, 1], a[:, :, 0], a[:, :, 3]], axis=-1)
        blob += out.tobytes()
    open(os.path.join(OUT, name), "wb").write(blob)
    print(name, len(blob))

desk = [f(48) for f in DESK]
small = [f(32) for f in SMALL]
pack(desk, "icons48.bin")
pack(small, "icons32.bin")

# ------------------------------------------------------------------ cursor
CUR = [
"B...........",
"BB..........",
"BWB.........",
"BWWB........",
"BWWWB.......",
"BWWWWB......",
"BWWWWWB.....",
"BWWWWWWB....",
"BWWWWWWWB...",
"BWWWWWWWWB..",
"BWWWWWWWWWB.",
"BWWWWWBBBBBB",
"BWWBWWB.....",
"BWB.BWWB....",
"BB..BWWB....",
"B....BWWB...",
".....BWWB...",
"......BB....",
]
blob = bytearray([12, len(CUR)])
for row in CUR:
    for ch in row:
        blob.append({".": 0, "B": 1, "W": 2}[ch])
open(os.path.join(OUT, "cursor.bin"), "wb").write(blob)

# ------------------------------------------------------------------ wallpaper (low-res, scaled up at run time)
WW, WH = 192, 108
yy, xx = np.mgrid[0:WH, 0:WW].astype(np.float64)
u, v = xx / (WW - 1), yy / (WH - 1)
base = np.zeros((WH, WW, 3))
c_tl = np.array([2, 6, 28.]); c_br = np.array([0, 40, 120.])
t = np.clip(0.55 * u + 0.45 * v, 0, 1)[..., None]
base = c_tl * (1 - t) + c_br * t
def ribbon(yc, width, color, strength):
    d = (v - yc) / width
    return (np.exp(-d * d)[..., None]) * np.array(color) * strength
# sweeping ribbons (S shaped, like the reference picture)
y1 = 0.45 + 0.30 * np.sin(u * 3.0 + 0.2) - 0.35 * u
y2 = 0.60 + 0.26 * np.sin(u * 2.6 + 1.1) - 0.32 * u
base += ribbon(y1, 0.06, (30, 120, 255), 0.55)
base += ribbon(y1 + 0.05, 0.16, (10, 60, 200), 0.55)
base += ribbon(y2, 0.045, (70, 170, 255), 0.55)
base += ribbon(y2 + 0.06, 0.20, (0, 70, 210), 0.5)
glow = np.exp(-(((u - 0.78) / 0.28) ** 2 + ((v - 0.45) / 0.40) ** 2))[..., None] * np.array([10, 90, 230.]) * 0.55
base += glow
vig = 1 - 0.45 * ((u - .5) ** 2 + (v - .5) ** 2)[..., None]
base = base * vig
base = 255 * (1 - np.exp(-base / 230.0))   # soft tone-map, no clipping
base = np.clip(base, 0, 255).astype(np.uint8)
dw = np.zeros((WH, WW, 4), np.uint8)
dw[:, :, 0] = base[:, :, 2]; dw[:, :, 1] = base[:, :, 1]; dw[:, :, 2] = base[:, :, 0]
open(os.path.join(OUT, "wall.bin"), "wb").write(struct.pack("<HH", WW, WH) + dw.tobytes())
Image.fromarray(base).resize((1280, 720), Image.BICUBIC).save("/tmp/wall_preview.png")

# preview sheet of the icons
sheet = Image.new("RGBA", (13 * 60, 140), (20, 40, 90, 255))
for i, im in enumerate(desk):
    sheet.alpha_composite(im, (i * 60 + 6, 6))
for i, im in enumerate(small):
    sheet.alpha_composite(im, (i * 60 + 12, 70))
sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save("/tmp/icons_preview.png")
print("done")
