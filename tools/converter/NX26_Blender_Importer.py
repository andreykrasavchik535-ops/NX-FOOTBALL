bl_info = {
    "name": "NX26 KeyframeSequence Importer",
    "author": "NX26",
    "version": (1, 0, 0),
    "blender": (3, 0, 0),
    "location": "File > Import > NX26 Animation JSON",
    "description": "Import NX26 procedural Roblox animation JSON as Blender Actions on an R15 armature",
    "category": "Import-Export",
}
import bpy, json, math
from mathutils import Matrix, Vector, Quaternion
# Roblox (X right, Y up, Z back) -> Blender (X right, Y forward, Z up): (x,y,z)->(x,z,-y)
B = Matrix(((1,0,0),(0,0,1),(0,-1,0)))
BT = B.transposed()
HIER = {
 "HumanoidRootPart":["Root"], "Root":["Waist","LeftHip","RightHip"],
 "Waist":["Neck","LeftShoulder","RightShoulder"], "Neck":[],
 "LeftShoulder":["LeftElbow"], "LeftElbow":["LeftWrist"], "LeftWrist":[],
 "RightShoulder":["RightElbow"], "RightElbow":["RightWrist"], "RightWrist":[],
 "LeftHip":["LeftKnee"], "LeftKnee":["LeftAnkle"], "LeftAnkle":[],
 "RightHip":["RightKnee"], "RightKnee":["RightAnkle"], "RightAnkle":[],
}
# Starting skeleton rest heads (Roblox studs, Y up). CALIBRATE against your real R15 rig.
REST_HEAD = {
 "HumanoidRootPart":(0,3.0,0), "Root":(0,3.0,0), "Waist":(0,3.5,0), "Neck":(0,4.6,0),
 "LeftShoulder":(0.9,4.3,0), "LeftElbow":(1.5,3.4,0), "LeftWrist":(1.7,2.5,0),
 "RightShoulder":(-0.9,4.3,0), "RightElbow":(-1.5,3.4,0), "RightWrist":(-1.7,2.5,0),
 "LeftHip":(0.5,2.8,0), "LeftKnee":(0.5,1.5,0), "LeftAnkle":(0.5,0.3,0),
 "RightHip":(-0.5,2.8,0), "RightKnee":(-0.5,1.5,0), "RightAnkle":(-0.5,0.3,0),
}
BONE_LEN = 0.5
def cf_to_blender(comp):
    pos = B @ Vector(comp[0:3])
    r = Matrix((comp[3:6], comp[6:9], comp[9:12]))
    return pos, (B @ r @ BT)
def build_armature(name="NX26_R15"):
    if name in bpy.data.objects: return bpy.data.objects[name]
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones; made = {}
    def mk(j):
        if j in made: return made[j]
        b = eb.new(j); hb = B @ Vector(REST_HEAD.get(j,(0,3,0)))
        b.head = hb; b.tail = hb + Vector((0,0,BONE_LEN)); b.roll = 0
        made[j] = b; return b
    for j in HIER: mk(j)
    for j,ch in HIER.items():
        for c in ch:
            made[c].parent = made[j]; made[c].use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj
def import_json(filepath, armature_name="NX26_R15"):
    data = json.load(open(filepath,"r",encoding="utf-8"))
    obj = build_armature(armature_name)
    fps = data.get("fps",30); dur = data.get("duration",1.0)
    nframes = max(1,int(round(dur*fps)))
    act = bpy.data.actions.new(data.get("name","NX26_anim"))
    obj.animation_data_create(); obj.animation_data.action = act
    bpy.context.scene.render.fps = fps
    bpy.context.scene.frame_start = 1; bpy.context.scene.frame_end = nframes+1
    for pb in obj.pose.bones: pb.rotation_mode = 'QUATERNION'
    for kf in data["keyframes"]:
        frame = 1 + int(round(kf["time"]*fps))
        for j,comp in kf["poses"].items():
            if j not in obj.pose.bones: continue
            pb = obj.pose.bones[j]
            pos, rb = cf_to_blender(comp)
            rest = obj.data.bones[j].matrix_local
            basis = rest.inverted() @ rb.to_4x4() @ rest
            pb.rotation_quaternion = basis.to_quaternion()
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if j in ("HumanoidRootPart","Root"):
                pb.location = pos
                pb.keyframe_insert(data_path="location", frame=frame)
    if data.get("loop"):
        for fc in act.fcurves: fc.modifiers.new('CYCLES')
    return act
class IMPORT_OT_nx26(bpy.types.Operator):
    bl_idname = "import_anim.nx26_json"
    bl_label = "Import NX26 Animation JSON"
    filepath: bpy.props.StringProperty(subtype='FILE_PATH')
    def execute(self, context):
        import_json(self.filepath)
        self.report({'INFO'}, "NX26 animation imported")
        return {'FINISHED'}
    def invoke(self, context, event):
        context.window_manager.fileselect_add(self)
        return {'RUNNING_MODAL'}
def menu_fn(self, context):
    self.layout.operator(IMPORT_OT_nx26.bl_idname, text="NX26 Animation JSON (.json)")
def register():
    bpy.utils.register_class(IMPORT_OT_nx26)
    bpy.types.TOPBAR_MT_file_import.append(menu_fn)
def unregister():
    bpy.types.TOPBAR_MT_file_import.remove(menu_fn)
    bpy.utils.unregister_class(IMPORT_OT_nx26)
if __name__ == "__main__":
    register()
