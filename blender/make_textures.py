# -*- coding: utf-8 -*-
# 無線機のテクスチャを作る（Pillow）
# py -3 make_textures.py  → blender/tex/ta_radio_atlas.dds と確認用の .png、場所の表 layout.json
# 色は ta-radio の画面と同じ考え方。本体は黒鉛色、色を持つのは液晶と表示灯の琥珀色だけ
import json, os, random
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tex")
os.makedirs(OUT, exist_ok=True)

SIZE = 512
A = Image.new("RGBA", (SIZE, SIZE), (30, 32, 35, 255))
layout = {}
rnd = random.Random(7)  # 毎回同じ絵になるように


def font(paths, size):
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


MONO = font(["C:/Windows/Fonts/consolab.ttf", "C:/Windows/Fonts/consola.ttf", "C:/Windows/Fonts/arialbd.ttf"], 64)
SMALL = font(["C:/Windows/Fonts/arialbd.ttf"], 18)


def put(name, im, x, y):
    A.alpha_composite(im, (x, y))
    layout[name] = [x, y, im.width, im.height]


# 樹脂。ごく弱いざらつきを入れ、単色のつるつるに見えないようにする
def plastic(color, w=64, h=64, grain=5):
    im = Image.new("RGBA", (w, h), color + (255,))
    px = im.load()
    for yy in range(h):
        for xx in range(w):
            d = rnd.randint(-grain, grain)
            r, g, b, a = px[xx, yy]
            px[xx, yy] = (max(0, r + d), max(0, g + d), max(0, b + d), a)
    return im


BODY = (38, 41, 45)
put("body", plastic(BODY), 0, 0)
put("battery", plastic((48, 52, 57)), 64, 0)
put("rubber", plastic((22, 23, 25), grain=3), 128, 0)
put("metal", plastic((138, 143, 150), grain=8), 192, 0)
put("gold", plastic((196, 160, 80), grain=6), 256, 0)
put("led", Image.new("RGBA", (32, 32), (255, 186, 92, 255)), 320, 0)

# つまみの側面の刻み（縦じま）
knurl = Image.new("RGBA", (128, 32), (22, 23, 25, 255))
d = ImageDraw.Draw(knurl)
for xx in range(0, 128, 8):
    d.rectangle((xx, 0, xx + 3, 31), fill=(44, 46, 50, 255))
put("knurl", knurl, 352, 0)

# 液晶 256x128。暗い琥珀の地に、明るい琥珀で無線番号・信号の棒・「CH」
lcd = Image.new("RGBA", (256, 128), (34, 22, 8, 255))
d = ImageDraw.Draw(lcd)
d.rectangle((0, 0, 255, 127), outline=(16, 11, 5, 255), width=6)
amber = (255, 190, 100, 255)
dim = (92, 62, 26, 255)
# 信号の棒 3 本（左上）
for i, hgt in enumerate((10, 17, 24)):
    x0 = 18 + i * 9
    d.rectangle((x0, 40 - hgt, x0 + 5, 40), fill=amber)
d.text((236, 14), "CH", font=SMALL, fill=amber, anchor="ra")
d.text((128, 82), "102.5", font=MONO, fill=amber, anchor="mm")
# 下の細い目盛り（電池の残り）
for i in range(5):
    d.rectangle((22 + i * 14, 108, 32 + i * 14, 114), fill=amber if i < 4 else dim)
put("lcd", lcd, 0, 64)

# スピーカー 128x160。本体の色に横長の穴の列
grille = Image.new("RGBA", (128, 160), BODY + (255,))
grille.alpha_composite(plastic(BODY, 128, 160), (0, 0))
d = ImageDraw.Draw(grille)
for row in range(9):
    yy = 10 + row * 16
    d.rounded_rectangle((10, yy, 117, yy + 7), 3, fill=(10, 11, 12, 255))
put("grille", grille, 256, 64)

# 底面 64x64。充電の端子 2 つ
bottom = plastic(BODY)
d = ImageDraw.Draw(bottom)
for xx in (18, 38):
    d.rectangle((xx, 26, xx + 8, 38), fill=(196, 160, 80, 255))
put("bottom", bottom, 384, 64)

# 操作ボタンの表（ゴムに細い線の印）
key = Image.new("RGBA", (64, 32), (24, 25, 28, 255))
d = ImageDraw.Draw(key)
d.line((22, 16, 42, 16), fill=(90, 94, 100, 255), width=3)
put("key", key, 384, 128)

json.dump(layout, open(os.path.join(OUT, "layout.json"), "w", encoding="utf-8", newline="\n"), indent=1)
A.convert("RGB").save(os.path.join(OUT, "ta_radio_atlas.png"))
A.convert("RGB").save(os.path.join(OUT, "ta_radio_atlas.dds"), pixel_format="DXT1")
print("ok", sorted(layout))
