# -*- coding: utf-8 -*-
# 手に持つ無線機 ta_radio を Blender で組み立て、Sollumz で FiveM 用に書き出す
# 先に py -3.13 make_textures.py でテクスチャを作ってから:
#   blender -b --python build_model.py  （--factory-startup を付けると Sollumz の依存 szio が読めない）
# 出力: ../stream/ta_radio.ydr, ta_radio.ytyp
#       ./ta_radio.blend（Blender で開いて直せる）、./preview/*.png（確認用の描画）、../install/radio.png（ox_inventory のアイコン）
#       ./stats.json（三角形の数と外形。verify_model.py が読み直した結果と比べる）
#       ../html/img/radio-device.png と ../html/device-layout.css（NUI の無線機の絵と、その中の液晶・ボタンの位置）
# 軸と原点は純正の prop_cs_hand_radio と同じ（正面 -Y・上 +Z・原点は本体の中）。寸法は PARTS.md
import bpy, bmesh, json, math, os, sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEX = os.path.join(HERE, "tex")
STREAM = os.path.join(ROOT, "stream")
PREVIEW = os.path.join(HERE, "preview")
INSTALL = os.path.join(ROOT, "install")
for p in (STREAM, PREVIEW, INSTALL):
    os.makedirs(p, exist_ok=True)

sys.path.insert(0, HERE)
import common
from common import add_bounds, convert_obj_to_drawable

NAME = "ta_radio"
LAYOUT = json.load(open(os.path.join(TEX, "layout.json"), encoding="utf-8"))
MAT_BODY, MAT_GLOW = 0, 1
MAX_TRIS = 2000
MAX_ERR = 0.001

# 部品表の外形（PARTS.md）。ビルドの終わりに、できた形と比べる
EXPECT_MIN = (-0.031, -0.0185, -0.122)
EXPECT_MAX = (0.035, 0.028, 0.135)

# 正面の液晶とボタンの位置（m）。NUI の絵の中の位置もここから計算する
LCD = (-0.025, 0.025, -0.003, 0.033)  # x0, x1, z0, z1（50 x 36 mm）
KEY_XS = (-0.016, 0.0, 0.016)
KEY_W, KEY_Z = 0.012, (-0.0145, -0.0095)

common.reset_scene()


class Builder(common.Builder):
    # 単色の場所は縁から 4px 内側を使う（DXT1 とミップマップで隣の色がにじまないように）
    def solid(self, name):
        x, y, w, h = self.layout[name]
        W, H = self.size
        return ((x + 4) / W, 1 - (y + h - 4) / H, (x + w - 4) / W, 1 - (y + 4) / H)

    # 角を丸めた箱を Z 方向に伸ばす。上下の縁は chamfer だけ内側へ寄せて面取りする
    # 側面の UV は周の長さと高さで rect の中に広げる。ふたは rect の中に平らに置く
    def rounded_prism(self, x0, x1, y0, y1, z0, z1, r, chamfer, side, cap, bottom=None, seg=5):
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hx, hy = (x1 - x0) / 2, (y1 - y0) / 2

        def ring(inset):
            pts = []
            rr = max(r - inset, 0.0005)
            ex, ey = hx - inset - rr, hy - inset - rr
            for k, (sx, sy, a0) in enumerate(((1, -1, -90), (1, 1, 0), (-1, 1, 90), (-1, -1, 180))):
                for i in range(seg + 1):
                    a = math.radians(a0 + 90 * i / seg)
                    pts.append(Vector((cx + sx * ex + rr * math.cos(a), cy + sy * ey + rr * math.sin(a))))
            return pts

        levels = [(z0, chamfer), (z0 + chamfer, 0.0), (z1 - chamfer, 0.0), (z1, chamfer)]
        rings = [[Vector((p.x, p.y, z)) for p in ring(ins)] for z, ins in levels]
        n = len(rings[0])
        su0, sv0, su1, sv1 = self.solid(side[0]) if isinstance(side[0], str) else side[0]
        center = Vector((cx, cy, (z0 + z1) / 2))
        for li in range(3):
            a, b = rings[li], rings[li + 1]
            for k in range(n):
                k2 = (k + 1) % n
                ps = [a[k], a[k2], b[k2], b[k]]
                if (ps[0] - ps[1]).length < 1e-7:
                    continue
                t0, t1 = k / n, (k + 1) / n
                v0 = sv0 + (sv1 - sv0) * (levels[li][0] - z0) / (z1 - z0)
                v1 = sv0 + (sv1 - sv0) * (levels[li + 1][0] - z0) / (z1 - z0)
                uvs = [(su0 + (su1 - su0) * t0, v0), (su0 + (su1 - su0) * t1, v0), (su0 + (su1 - su0) * t1, v1), (su0 + (su1 - su0) * t0, v1)]
                mid = sum(ps, Vector()) / 4
                out = Vector((mid.x - center.x, mid.y - center.y, 0)).normalized() + Vector((0, 0, (mid.z - center.z) * 4))
                self.quad(ps, uvs, side[1], out)
        for ringpts, rect, up in ((rings[-1], cap, 1), (rings[0], bottom or cap, -1)):
            u0, v0, u1, v1 = self.solid(rect[0]) if isinstance(rect[0], str) else rect[0]
            vs = [self.bm.verts.new(p) for p in ringpts]
            f = self.bm.faces.new(vs)
            f.material_index = rect[1]
            f.normal_update()
            if f.normal.z * up < 0:
                f.normal_flip()
            for loop in f.loops:
                p = loop.vert.co
                loop[self.uv].uv = (u0 + (u1 - u0) * (p.x - x0) / (x1 - x0), v0 + (v1 - v0) * (p.y - y0) / (y1 - y0))

    # 正面（-Y）に貼る板。y は本体の面から 0.4mm 手前
    # 絵の縁は 2px 内側を使う（隣の場所の色がにじまないように）
    def front_plate(self, x0, x1, z0, z1, y, rect, mat):
        x, yy, w, h = self.layout[rect]
        W, H = self.size
        u0, v0, u1, v1 = (x + 2) / W, 1 - (yy + h - 2) / H, (x + w - 2) / W, 1 - (yy + 2) / H
        self.quad([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], mat, Vector((0, -1, 0)))


def material(shader, emissive=None, name=None):
    return common.material(TEX, shader, "ta_radio_atlas", emissive, name)


def build():
    B = Builder(LAYOUT, (512, 512))
    S = B.solid
    body = (S("body"), MAT_BODY)
    rubber = (S("rubber"), MAT_BODY)
    metal = (S("metal"), MAT_BODY)

    # 本体
    B.rounded_prism(-0.031, 0.031, -0.017, 0.017, -0.122, 0.040, 0.006, 0.002, body, body, bottom=(B.uvrect("bottom"), MAT_BODY))

    # 正面: 液晶・操作ボタン・スピーカー
    yf = -0.0174
    x0, x1, z0, z1 = LCD
    B.box((x0 - 0.0015, yf - 0.0006, z0 - 0.0015), (x1 + 0.0015, -0.0165, z1 + 0.0015), {}, body)  # 液晶の枠
    B.front_plate(x0, x1, z0, z1, yf - 0.0008, "lcd", MAT_GLOW)
    for x in KEY_XS:
        B.box((x - KEY_W / 2, -0.0185, KEY_Z[0]), (x + KEY_W / 2, -0.0168, KEY_Z[1]), {"front": ("key", MAT_BODY)}, rubber)
    B.front_plate(-0.024, 0.024, -0.104, -0.024, yf, "grille", MAT_BODY)

    # 上面: アンテナ（左）・つまみ 2 つ・表示灯
    B.cylinder((-0.017, 0.0, 0.046), "Z", 0.0085, 0.012, 16, rubber, rubber)
    # ゴムの棒は根元の筒の上（0.052）から、先の丸みの中心（0.1295）まで。先の丸みの上が 0.135
    B.cylinder((-0.017, 0.0, (0.052 + 0.1295) / 2), "Z", 0.0055, 0.1295 - 0.052, 12, rubber, None)
    B.sphere((-0.017, 0.0, 0.1295), 0.0055, 12, 6, S("rubber"), MAT_BODY)
    B.cylinder((0.006, 0.0, 0.0415), "Z", 0.0080, 0.003, 16, metal, metal)  # つまみの根元の金属の輪
    B.cylinder((0.006, 0.0, 0.0490), "Z", 0.0075, 0.012, 16, (S("knurl"), MAT_BODY), rubber,
               side_uv=lambda t, a: (B.uvrect("knurl")[0] + a * (B.uvrect("knurl")[2] - B.uvrect("knurl")[0]), B.uvrect("knurl")[1] + t * (B.uvrect("knurl")[3] - B.uvrect("knurl")[1])))
    B.cylinder((0.022, 0.0, 0.0455), "Z", 0.0060, 0.009, 14, (S("knurl"), MAT_BODY), rubber,
               side_uv=lambda t, a: (B.uvrect("knurl")[0] + a * (B.uvrect("knurl")[2] - B.uvrect("knurl")[0]), B.uvrect("knurl")[1] + t * (B.uvrect("knurl")[3] - B.uvrect("knurl")[1])))
    B.sphere((0.022, -0.011, 0.040), 0.0022, 8, 4, S("led"), MAT_GLOW)

    # 側面（+X）: 送信ボタンと小さなボタン
    B.box((0.0305, -0.010, -0.040), (0.0350, 0.010, 0.012), {}, rubber)
    B.box((0.0305, -0.006, -0.058), (0.0335, 0.006, -0.048), {}, rubber)

    # 背面: 電池とベルトクリップ
    B.rounded_prism(-0.028, 0.028, 0.0165, 0.022, -0.118, 0.022, 0.003, 0.001, (S("battery"), MAT_BODY), (S("battery"), MAT_BODY))
    B.box((-0.015, 0.022, -0.055), (0.015, 0.0265, 0.030), {}, (S("battery"), MAT_BODY))
    B.box((-0.015, 0.0265, -0.060), (0.015, 0.028, 0.035), {}, (S("battery"), MAT_BODY))
    B.cylinder((0.0, 0.025, 0.033), "X", 0.003, 0.034, 10, metal, metal)

    mats = [material("default.sps", name="ta_radio_body"), material("emissive.sps", 1.2, name="ta_radio_glow")]
    obj = B.to_object(NAME, mats)
    d = convert_obj_to_drawable(obj)
    d.name = NAME
    # 純正と同じく、本体を包む箱 1 つ（手に持つときはクライアントで当たりを切る）
    add_bounds(d, [((-0.031, -0.017, -0.122), (0.031, 0.022, 0.040))], "PLASTIC")
    return d, obj


radio, mesh_obj = build()

# ---------------------------------------------------------------------------
# 三角形の数と外形を部品表と比べる
# ---------------------------------------------------------------------------
bpy.context.view_layer.update()
model = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == radio and "bound" not in str(o.sollum_type).lower()]
tris = 0
mn, mx = Vector((9, 9, 9)), Vector((-9, -9, -9))
for o in model:
    tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        mn = Vector(map(min, mn, w))
        mx = Vector(map(max, mx, w))
err = max(max(abs(a - b) for a, b in zip(mn, EXPECT_MIN)), max(abs(a - b) for a, b in zip(mx, EXPECT_MAX)))
print("tris %d / %d" % (tris, MAX_TRIS))
print("bounds min %s max %s" % (tuple(round(v, 4) for v in mn), tuple(round(v, 4) for v in mx)))
print("size error %.2f mm / %.2f mm" % (err * 1000, MAX_ERR * 1000))
assert tris <= MAX_TRIS, "三角形が多すぎる"
assert err <= MAX_ERR, "外形が部品表と合わない"
json.dump({"meshes": len(model), "tris": tris, "min": [round(v, 4) for v in mn], "max": [round(v, 4) for v in mx]},
          open(os.path.join(HERE, "stats.json"), "w", encoding="utf-8", newline="\n"), indent=1)

# ---------------------------------------------------------------------------
# ytyp・書き出し・保存
# ---------------------------------------------------------------------------
ytyp = common.make_ytyp(NAME, (radio,))
for a in ytyp.archetypes:
    a.lod_dist = 60.0
    a.hd_texture_dist = 15.0
common.export(STREAM)
common.save_blend(os.path.join(HERE, NAME + ".blend"))

# ---------------------------------------------------------------------------
# 確認用の描画
# ---------------------------------------------------------------------------
shot = common.setup_render(PREVIEW)
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = 800, 1000
c = (0.0, 0.0, 0.005)
shot("front", (0.0, -0.55, 0.02), c, 50)
shot("three_quarter", (0.30, -0.42, 0.20), c, 50)
shot("side", (0.55, 0.0, 0.02), c, 50)
shot("back", (-0.30, 0.42, 0.15), c, 50)
shot("top", (0.0, -0.08, 0.30), (0.0, 0.0, 0.04), 60)

# ox_inventory のアイコン。背景は透明、斜め前から
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 256
scene.display.render_aa = "32"
shot("icon", (0.26, -0.40, 0.17), (0.0, 0.0, 0.016), 60)
import shutil
shutil.copyfile(os.path.join(PREVIEW, "icon.png"), os.path.join(INSTALL, "radio.png"))

# ---------------------------------------------------------------------------
# NUI の無線機の絵。正面から平行投影で、液晶だけ空にした絵を描く（液晶の中身は HTML で重ねる）
# 下の方は画面の外に隠れるので、スピーカーの途中（z = -0.070）までで切る
# ---------------------------------------------------------------------------
UI_X, UI_Z, PX = (-0.036, 0.036), (-0.070, 0.137), 8000  # 1 m = 8000 px（1 mm = 8 px）
HTML = os.path.join(ROOT, "html")
os.makedirs(os.path.join(HTML, "img"), exist_ok=True)
ui_atlas = bpy.data.images.load(os.path.join(TEX, "ta_radio_atlas_ui.png"))
for m in bpy.data.materials:
    node = m.node_tree.nodes.get("DiffuseSampler") if m.node_tree else None
    if node is not None and m.name.startswith("ta_radio"):
        node.image = ui_atlas
cam = scene.camera
cam.data.type = "ORTHO"
cam.data.ortho_scale = UI_Z[1] - UI_Z[0]  # 縦長なので、縦の長さが ortho_scale になる
cam.location = ((UI_X[0] + UI_X[1]) / 2, -0.5, (UI_Z[0] + UI_Z[1]) / 2)
cam.rotation_euler = (math.radians(90), 0.0, 0.0)  # +Y の向きを見る（正面は -Y）
scene.render.resolution_x = round((UI_X[1] - UI_X[0]) * PX)
scene.render.resolution_y = round((UI_Z[1] - UI_Z[0]) * PX)
scene.display.shading.show_cavity = False
scene.render.filepath = os.path.join(HTML, "img", "radio-device.png")
bpy.ops.render.render(write_still=True)


# 絵の中の位置を % で書き出す（左・上・幅・高さ）
def pct(x0, x1, z0, z1):
    W, H = UI_X[1] - UI_X[0], UI_Z[1] - UI_Z[0]
    return ((x0 - UI_X[0]) / W * 100, (UI_Z[1] - z1) / H * 100, (x1 - x0) / W * 100, (z1 - z0) / H * 100)


lines = ["/* build_model.py が書き出す。手で直さない（無線機の絵 img/radio-device.png の中の液晶とボタンの位置） */", ".device {",
         "    --device-ratio: %d / %d;" % (scene.render.resolution_x, scene.render.resolution_y)]
for name, r in [("lcd", pct(*LCD))] + [("key%d" % (i + 1), pct(x - KEY_W / 2, x + KEY_W / 2, *KEY_Z)) for i, x in enumerate(KEY_XS)]:
    for k, v in zip(("l", "t", "w", "h"), r):
        lines.append("    --%s-%s: %.3f%%;" % (name, k, v))
lines.append("}")
LF = chr(10)
open(os.path.join(HTML, "device-layout.css"), "w", encoding="utf-8", newline=LF).write(LF.join(lines) + LF)
print("ui", scene.render.resolution_x, scene.render.resolution_y, pct(*LCD))
print("done")
