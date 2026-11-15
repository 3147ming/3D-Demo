# -*- coding: utf-8 -*-
"""
Kenney FBX -> GLB 一键转换（含动画合并）
用法：Blender 顶部切到 Scripting -> New -> 粘贴本文件 -> Run Script (Alt+P)
结果：在 OUT 目录生成 player.glb 和 enemy.glb，直接放进 Godot 项目即可。
"""
import bpy
import os

# ============ 1. 配置（路径不对就改这里） ============
SRC = r"C:\Users\31474\OneDrive\Desktop\指令\游戏\美术\kenney_animated-characters-survivors"
OUT = r"D:\Projects\冒险\ink-blade-godot\assets\models"

# 每个任务 = 一个输出文件，只换贴图（模型和动画共用）
JOBS = [
    {"skin": "survivorMaleB.png", "out": "player.glb"},
    {"skin": "zombieA.png",       "out": "enemy.glb"},
]

# 动画文件 -> 导出的动画名（Godot 里按这些名字匹配）
ANIMS = {
    "idle.fbx": "idle",
    "run.fbx":  "run",
    "jump.fbx": "jump",
}

# ============ 2. 工具函数 ============
def reset_scene():
    """清空场景与残留数据，避免多次运行互相污染"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for coll in (bpy.data.actions, bpy.data.armatures, bpy.data.meshes,
                 bpy.data.materials, bpy.data.images):
        for item in list(coll):
            try:
                coll.remove(item)
            except Exception:
                pass


def import_model():
    """导入 characterMedium.fbx，返回 (armature, [mesh...])"""
    path = os.path.join(SRC, "Model", "characterMedium.fbx")
    if not os.path.exists(path):
        raise FileNotFoundError("找不到模型: " + path)
    bpy.ops.import_scene.fbx(filepath=path)

    arm, meshes = None, []
    for obj in list(bpy.context.scene.objects):
        if obj.type == 'ARMATURE' and arm is None:
            arm = obj
        elif obj.type == 'MESH':
            meshes.append(obj)
        elif obj.type in {'CAMERA', 'LIGHT'}:
            bpy.data.objects.remove(obj, do_unlink=True)
    if arm is None:
        raise RuntimeError("FBX 里没有骨骼，无法合并动画")
    print("模型导入完成，骨骼: %s，网格 %d 个" % (arm.name, len(meshes)))
    return arm, meshes


def import_anims(arm):
    """把每个动画 FBX 的 action 抽出来，重命名后挂到主骨骼上"""
    for fname, label in ANIMS.items():
        path = os.path.join(SRC, "Animations", fname)
        if not os.path.exists(path):
            print("跳过缺失动画: " + fname)
            continue

        before_objs = set(bpy.context.scene.objects)
        before_acts = set(bpy.data.actions)
        bpy.ops.import_scene.fbx(filepath=path)
        new_objs = set(bpy.context.scene.objects) - before_objs
        new_acts = set(bpy.data.actions) - before_acts

        # 保留 action（设 fake_user 防止被清除），删掉导入的临时对象
        for act in new_acts:
            act.name = label
            act.use_fake_user = True
            print("动画 %s -> %s" % (fname, label))
        for obj in new_objs:
            bpy.data.objects.remove(obj, do_unlink=True)

    # 让 idle 成为默认动作，导出器才有可导出的活动动作
    idle = bpy.data.actions.get("idle")
    if idle and arm.animation_data:
        arm.animation_data.action = idle
    elif idle:
        arm.animation_data_create()
        arm.animation_data.action = idle


def apply_skin(meshes, skin_name):
    """把 Skins 里的贴图应用到所有网格"""
    path = os.path.join(SRC, "Skins", skin_name)
    if not os.path.exists(path):
        print("贴图缺失: " + path)
        return
    img = bpy.data.images.load(path)
    img.pack()  # 内嵌进 GLB，避免导出后丢贴图

    for mesh in meshes:
        if len(mesh.data.materials) == 0:
            mesh.data.materials.append(bpy.data.materials.new("skin"))
        for mat in mesh.data.materials:
            mat.use_nodes = True
            nt = mat.node_tree
            bsdf = nt.nodes.get("Principled BSDF")
            if bsdf is None:
                continue
            tex = nt.nodes.new('ShaderNodeTexImage')
            tex.image = img
            nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
            bsdf.inputs['Roughness'].default_value = 0.85
            # Kenney 是纯色卡通贴图，不需要金属度
            bsdf.inputs['Metallic'].default_value = 0.0
    print("贴图已应用: " + skin_name)


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    kwargs = dict(
        filepath=path,
        export_format='GLB',
        export_animations=True,
        export_frame_range=False,      # 用 action 自身范围，而不是场景帧范围
        export_force_sampling=True,    # 烘焙每一帧，Godot 兼容性最好
        export_skins=True,
        export_yup=True,               # Blender Z-up -> Godot Y-up
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_apply=False,
    )
    try:
        # Blender 4.0+
        bpy.ops.export_scene.gltf(export_animation_mode='ACTIONS', **kwargs)
    except TypeError:
        # Blender 3.x 回退
        bpy.ops.export_scene.gltf(export_nla_strips=False, **kwargs)
    print("导出完成: " + path)


# ============ 3. 主流程 ============
if not os.path.isdir(SRC):
    raise FileNotFoundError("源目录不存在，请检查脚本顶部 SRC 路径: " + SRC)

for job in JOBS:
    print("\n===== 生成 %s =====" % job["out"])
    reset_scene()
    arm, meshes = import_model()
    import_anims(arm)
    apply_skin(meshes, job["skin"])
    export_glb(os.path.join(OUT, job["out"]))

print("\n全部完成！文件在: " + OUT)
print("回到 Godot，等它自动导入，然后按 F5 运行。")
