# NX26 — KeyframeSequence to Blender Converter

Pipeline: Roblox KeyframeSequence -> JSON -> Blender Actions -> FBX -> Roblox Studio.

Converts the 37 existing NX26 procedural animations (4 locomotion + 5 actions + 28 feints; feints also
export a _Left variant -> 65 JSON files). Does NOT create new animations, does NOT touch game physics.

## Files
- nx26_anim_gen.py : re-implements the 37 generators faithfully -> exports all JSON (no Roblox needed). TESTED in Python.
- NX26_Roblox_Exporter.lua : Studio plugin, reads the ACTUAL KeyframeSequence -> JSON (copy from dock). NOT run in Studio here.
- NX26_Blender_Importer.py : Blender add-on, JSON -> R15 armature + Actions. NOT run in Blender here.
- anim_json/*.json : the 65 exported animations. Generated + math-verified.
- example_RunNoBall.json : example / test animation.

## Quick start (get JSON without Roblox/Blender)
    python nx26_anim_gen.py        # writes anim_json/*.json (65 files)
The procedural animations only exist as temporary KeyframeSequences at runtime, so this script reproduces
them deterministically from the same sampler math. Verified: 13584 poses, all rotation matrices orthonormal,
det=+1, timestamps exact (t0=0, tlast=duration).

## Import into Blender
1. Blender -> Edit -> Preferences -> Add-ons -> Install -> pick NX26_Blender_Importer.py -> enable.
2. File -> Import -> NX26 Animation JSON -> pick a file (start with example_RunNoBall.json).
3. It builds an NX26_R15 armature and an Action; press Play to preview; edit keyframes freely.
4. Export FBX (File -> Export -> FBX) for re-import to Roblox.

## Export from Roblox Studio (ground truth)
1. Add the BuildSeq function to ProceduralAnimations (see header of the .lua) - additive, safe.
2. Install NX26_Roblox_Exporter.lua as a Studio plugin, restart Studio.
3. Open the NX26 Export dock, pick an animation, Export, copy the JSON.

## HONEST STATUS / needs manual verification
- Blender was NOT run in this environment (bpy has no installable build here). Importer implemented but UNTESTED in Blender.
- CFrame -> Blender conversion uses a basis change (Roblox Y-up -> Blender Z-up) and applies each joint rotation
  relative to the bone rest pose. REST_HEAD positions/orientations are a STARTING SKELETON - calibrate them against
  your real R15 rig (REST_HEAD table + bone rolls) so limbs are not flipped/deformed.
- Studio plugin not run here; traversal uses standard Keyframe:GetPoses() / Pose:GetSubPoses() / CFrame:GetComponents().
- Test order requested: RunNoBall -> Elastico -> RainbowFlick (JSON for all three generated + verified).

## Verified here
- JSON generation for all 65; keyframe count, timestamps, 16 R15 joints.
- Every pose rotation matrix orthonormal, determinant +1.
- Feint left/right mirroring (side=-1 negates lateral components).

## NOT verified
- Actual Blender import / limb orientation / FBX round-trip (no Blender here).
- Studio plugin runtime (no Studio here).