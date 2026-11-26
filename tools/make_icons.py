"""앱 아이콘 합성: python3 tools/make_icons.py <얼굴 렌더 PNG>
얼굴 렌더는  ICON=/tmp/icon_kid.png xvfb-run godot --rendering-method gl_compatibility --resolution 1024x1024 --path . -s tools/render_assets.gd
결과 (icons/):
  icon.png            1024 정사각 (둥근 모서리, 프로젝트·웹·창 아이콘)
  icon.ico            Windows 실행 파일용 (16~256)
  android_192.png     안드로이드 기본 아이콘
  android_fg_432.png  안드로이드 적응형 아이콘 앞면 (투명 배경, 가운데 안전 영역)
  android_bg_432.png  안드로이드 적응형 아이콘 뒷면
  splash.png          시작 화면 그림
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

INK = (29, 53, 87); CREAM = (255, 247, 232); RAY = (255, 226, 160); RED = (230, 57, 70); YELLOW = (255, 183, 3)
OUT = os.path.join(os.path.dirname(__file__), '..', 'icons')
os.makedirs(OUT, exist_ok=True)
kid = Image.open(sys.argv[1]).convert('RGBA')


def background(S, band=True):
    im = Image.new('RGBA', (S, S), CREAM)
    d = ImageDraw.Draw(im)
    cx, cy = S * .5, S * .58
    for i in range(18):
        a0 = i * 2 * math.pi / 18
        a1 = a0 + math.pi / 18
        R = S * 1.2
        d.polygon([(cx, cy), (cx + R * math.cos(a0), cy + R * math.sin(a0)), (cx + R * math.cos(a1), cy + R * math.sin(a1))], fill=RAY)
    glow = Image.new('L', (S, S), 0)
    ImageDraw.Draw(glow).ellipse([cx - S * .36, cy - S * .36, cx + S * .36, cy + S * .36], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(S * .08))
    im = Image.composite(Image.new('RGBA', (S, S), CREAM), im, glow)
    if band:
        d = ImageDraw.Draw(im)
        top = int(S * .8); cell = S / 10
        d.rectangle([0, top - S * .025, S, top], fill=INK)
        for r in range(3):
            for c in range(11):
                if (r + c) % 2 == 0:
                    d.rectangle([c * cell, top + r * cell, (c + 1) * cell, top + (r + 1) * cell], fill=RED)
    return im


def rock(S):
    """오른쪽 위에서 떨어지는 작은 돌 + 속도선"""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = S * .07; cx, cy = S * .83, S * .25
    for k in range(3):
        x = cx - r * .5 + k * r * .5
        d.line([(x, cy - r * 1.2 - S * .12), (x, cy - r * 1.2)], fill=(*INK, 150), width=max(2, int(S * .012)))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(150, 150, 158), outline=INK, width=max(2, int(S * .014)))
    d.ellipse([cx - r * .55, cy - r * .6, cx - r * .05, cy - r * .2], fill=(190, 190, 198))
    return im


def kid_layer(S, scale=1.0, dy=0.0):
    k = kid.crop((40, 0, 984, 944)).resize((int(S * .98 * scale), int(S * .98 * scale)), Image.LANCZOS)
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    im.alpha_composite(k, (int((S - k.width) / 2), int(S - k.height + S * dy)))
    return im


def rounded(im, radius, border):
    S = im.width
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    if border:
        ImageDraw.Draw(out).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, outline=INK, width=border)
    return out


S = 1024
full = background(S)
full.alpha_composite(rock(S))
full.alpha_composite(kid_layer(S, .86, -.03))
icon = rounded(full, int(S * .22), int(S * .035))
icon.save(os.path.join(OUT, 'icon.png'))
icon.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, 'android_192.png'))
icon.save(os.path.join(OUT, 'icon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
# 적응형: 앞면은 가운데 66% 안에 얼굴, 뒷면은 무늬
fg = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
fg.alpha_composite(kid_layer(432, .66, -.17))
fg.alpha_composite(rock(432).resize((432, 432)).transform((432, 432), Image.AFFINE, (1.3, 0, -60, 0, 1.3, -40)), (0, 0))
fg.save(os.path.join(OUT, 'android_fg_432.png'))
background(432).save(os.path.join(OUT, 'android_bg_432.png'))
# 시작 화면: 크림 바탕 위 아이콘 (배경색은 project.godot 의 boot_splash/bg_color 와 같게)
sp = Image.new('RGBA', (640, 640), (0, 0, 0, 0))
sp.alpha_composite(icon.resize((440, 440), Image.LANCZOS), (100, 60))
sp.save(os.path.join(OUT, 'splash.png'))
print('icons ->', os.path.abspath(OUT))
