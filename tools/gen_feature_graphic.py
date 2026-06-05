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
draw.text((tx + 6, ty + 200), "Le service, l'information.", font=f_tag, fill=GRAY)

out = os.path.join(OUT_DIR, "feature_graphic.png")
img.save(out, "PNG")
print("OK ->", out, img.size)
