# -*- coding: utf-8 -*-
# 書き出した ../stream/ta_radio.ydr と ta_radio.ytyp を空の場面に読み込み直し、build_model.py の stats.json と比べる
#   blender -b --python verify_model.py
# 合わないときは終了コード 1。読み直した形を ./preview/reimport.png に描画する
import bpy, importlib, json, os, sys
from mathutils import Vector

importlib.import_module("bl_ext.user_default.sollumz")

HERE = os.path.dirname(os.path.abspath(__file__))
STREAM = os.path.join(os.path.dirname(HERE), "stream")
stats = json.load(open(os.path.join(HERE, "stats.json"), encoding="utf-8"))

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)

print("import ydr", bpy.ops.sollumz.import_assets(directory=STREAM, files=[{"name": "ta_radio.ydr"}]))
bpy.context.view_layer.update()

bad = []
drawables = [o for o in bpy.data.objects if o.sollum_type == "sollumz_drawable"]
models = [o for o in bpy.data.objects if o.type == "MESH" and o.sollum_type == "sollumz_drawable_model"]
bounds = [o for o in bpy.data.objects if "bound" in str(o.sollum_type).lower()]
tris = 0
mn, mx = Vector((9, 9, 9)), Vector((-9, -9, -9))
mats = set()
for o in models:
    tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    mats.update(m.name for m in o.data.materials)
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        mn = Vector(map(min, mn, w))
        mx = Vector(map(max, mx, w))
print("drawables", len(drawables), "models", len(models), "bounds", len(bounds), "tris", tris, "materials", sorted(mats))
print("min", tuple(round(v, 4) for v in mn), "max", tuple(round(v, 4) for v in mx))

if len(drawables) != 1:
    bad.append("drawable が 1 つでない")
if len(models) != stats["meshes"]:
    bad.append("メッシュの数が違う %d / %d" % (len(models), stats["meshes"]))
if tris != stats["tris"]:
    bad.append("三角形の数が違う %d / %d" % (tris, stats["tris"]))
err = max(max(abs(a - b) for a, b in zip(mn, stats["min"])), max(abs(a - b) for a, b in zip(mx, stats["max"])))
if err > 0.0005:
    bad.append("外形が %.2f mm ずれている" % (err * 1000))
if len(mats) != 2:
    bad.append("材質が 2 つでない")
if not bounds:
    bad.append("コリジョンが無い")
# テクスチャが ydr に埋め込まれているか（ytd を別に作っていない）
images = [im for im in bpy.data.images if im.size[0] > 0]
print("images", [(im.name, tuple(im.size)) for im in images])
if not any(tuple(im.size) == (512, 512) for im in images):
    bad.append("512x512 のテクスチャが読めない")

# ytyp
print("import ytyp", bpy.ops.sollumz.import_assets(directory=STREAM, files=[{"name": "ta_radio.ytyp"}]))
ytyps = list(bpy.context.scene.ytyps)
names = [a.name for y in ytyps for a in y.archetypes]
print("archetypes", names)
if names != ["ta_radio"]:
    bad.append("ytyp の archetype が ta_radio 1 つでない")

# 読み直した形を描画
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x, scene.render.resolution_y = 600, 800
for o in bounds:
    o.hide_render = True
for k in dir(scene.render):
    if k.startswith("use_stamp"):
        setattr(scene.render, k, False)
cd = bpy.data.cameras.new("c")
cam = bpy.data.objects.new("c", cd)
bpy.context.collection.objects.link(cam)
scene.camera = cam
cam.location = (0.30, -0.42, 0.20)
cam.rotation_euler = (Vector((0, 0, 0.005)) - cam.location).to_track_quat("-Z", "Y").to_euler()
cd.lens = 50
scene.render.filepath = os.path.join(HERE, "preview", "reimport.png")
bpy.ops.render.render(write_still=True)

if bad:
    print("NG:", "; ".join(bad))
    sys.exit(1)
print("verify OK")
