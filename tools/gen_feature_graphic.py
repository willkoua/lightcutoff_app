"""Génère le feature graphic Play Store (1024x500) à la charte NJUKA.
Sortie : store_assets/feature_graphic.png
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "assets/icon/njuka_foreground.png")
OUT_DIR = os.path.join(ROOT, "store_assets")
os.makedirs(OUT_DIR, exist_ok=True)

W, H = 1024, 500
DARK = (26, 26, 26)
AMBER = (248, 142, 1)
SKY = (14, 165, 233)
WHITE = (255, 255, 255)
GRAY = (176, 176, 176)

FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REG = "/System/Library/Fonts/Helvetica.ttc"

# Fond charbon + léger dégradé vertical pour la profondeur.
img = Image.new("RGB", (W, H), DARK)
for y in range(H):
    t = y / H
    shade = int(26 + 10 * t)  # 26 -> 36
    for_col = (shade, shade, shade)
    ImageDraw.Draw(img).line([(0, y), (W, y)], fill=for_col)

# Halo ambre diffus derrière l'ampoule.
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
cx, cy = 250, 250
gd.ellipse([cx - 190, cy - 190, cx + 190, cy + 190], fill=AMBER + (120,))
glow = glow.filter(ImageFilter.GaussianBlur(70))
img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")

# Ampoule (foreground transparent) redimensionnée.
icon = Image.open(ICON).convert("RGBA")
size = 360
icon = icon.resize((size, size), Image.LANCZOS)
img.paste(icon, (cx - size // 2, cy - size // 2), icon)

draw = ImageDraw.Draw(img)

# Wordmark NJUKA.
f_title = ImageFont.truetype(FONT_BOLD, 150)
title = "NJUKA"
tx = 470
ty = 150
# léger espacement de lettres
spacing = 8
x = tx
for ch in title:
    draw.text((x, ty), ch, font=f_title, fill=WHITE)
    w = draw.textlength(ch, font=f_title)
    x += w + spacing

# Filet ambre sous le wordmark.
draw.rectangle([tx + 4, ty + 168, tx + 250, ty + 176], fill=AMBER)

# Tagline.
f_tag = ImageFont.truetype(FONT_REG, 38)
draw.text((tx + 6, ty + 198), "Le service, l'information.", font=f_tag, fill=GRAY)


def draw_bolt(d, x, y, s, fill):
    """Petit éclair (électricité), boîte ~s de haut, ancré en (x, y) haut-gauche."""
    pts = [
        (x + s * 0.55, y),
        (x + s * 0.15, y + s * 0.58),
        (x + s * 0.45, y + s * 0.58),
        (x + s * 0.30, y + s),
        (x + s * 0.80, y + s * 0.38),
        (x + s * 0.48, y + s * 0.38),
    ]
    d.polygon(pts, fill=fill)


def draw_drop(d, cx, cy, r, fill):
    """Goutte d'eau centrée sur le cercle bas (cx, cy), rayon r."""
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)
    d.polygon(
        [(cx - r * 0.92, cy - r * 0.25), (cx, cy - r * 2.4), (cx + r * 0.92, cy - r * 0.25)],
        fill=fill,
    )
    # petit reflet
    d.ellipse([cx - r * 0.45, cy - r * 0.15, cx - r * 0.05, cy + r * 0.3], fill=(190, 228, 250))


# Sous-titre multi-service + pictos électricité / eau.
f_sub = ImageFont.truetype(FONT_REG, 30)
sy = ty + 268
# Picto éclair (ambre) + label.
draw_bolt(draw, tx + 8, sy, 34, AMBER)
draw.text((tx + 52, sy - 1), "Électricité", font=f_sub, fill=WHITE)
ex = tx + 52 + draw.textlength("Électricité", font=f_sub) + 40
# Séparateur.
draw.text((ex - 24, sy - 1), "·", font=f_sub, fill=GRAY)
# Picto goutte (sky) + label.
draw_drop(draw, ex + 14, sy + 30, 16, SKY)
draw.text((ex + 40, sy - 1), "Eau", font=f_sub, fill=WHITE)

out = os.path.join(OUT_DIR, "feature_graphic.png")
img.save(out, "PNG")
print("OK ->", out, img.size)
