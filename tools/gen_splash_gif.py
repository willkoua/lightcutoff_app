"""Génère un GIF animé du splash NJUKA : ampoule + halo ambre qui pulse.
Reproduit l'animation native du SplashScreen (aperçu / usage marketing).
Sortie : store_assets/splash_halo.gif
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BULB = os.path.join(ROOT, "assets/icon/njuka_foreground.png")
OUT_DIR = os.path.join(ROOT, "store_assets")
os.makedirs(OUT_DIR, exist_ok=True)

W = H = 420
DARK = (26, 26, 26)
AMBER = (248, 142, 1)
N = 24  # frames
BULB_PX = 150

bulb = Image.open(BULB).convert("RGBA").resize((BULB_PX, BULB_PX), Image.LANCZOS)

frames = []
for i in range(N):
    # 0 → 1 → 0 doux (sinus) pour une respiration continue.
    t = (math.sin(2 * math.pi * i / N - math.pi / 2) + 1) / 2

    base = Image.new("RGBA", (W, H), DARK + (255,))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = 60 + 70 * t
    alpha = int(25 + 75 * t)
    gd.ellipse(
        [W / 2 - r, H / 2 - r, W / 2 + r, H / 2 + r], fill=AMBER + (alpha,)
    )
    glow = glow.filter(ImageFilter.GaussianBlur(42))

    base = Image.alpha_composite(base, glow)
    base.alpha_composite(bulb, (int(W / 2 - BULB_PX / 2), int(H / 2 - BULB_PX / 2)))
    frames.append(base.convert("RGB").convert("P", palette=Image.ADAPTIVE))

out = os.path.join(OUT_DIR, "splash_halo.gif")
frames[0].save(
    out,
    save_all=True,
    append_images=frames[1:],
    duration=58,  # ms/frame → cycle ≈ 1,4 s (comme l'anim native)
    loop=0,
    disposal=2,
    optimize=True,
)
print("OK ->", out)
