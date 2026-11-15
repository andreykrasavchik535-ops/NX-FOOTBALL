# NX26 — Blender to Roblox Animation Guide

The project uses R15 characters. All animation slots are in `ReplicatedStorage/SoccerShared/AnimationIds` (see ANIMATION_TABLE.md). Empty slots are safe; the game keeps working with default Roblox animations.

## 1. Get the R15 rig
- In Roblox Studio use a standard R15 rig (Avatar rig). Export it to FBX (Studio: select rig -> Export), or download the official Roblox R15 reference rig.
- Import the FBX into Blender. Keep the bone names intact (Roblox retargeting expects them).

## 2. Animate in Blender
- 30 FPS recommended. Keep the character IN PLACE (no root motion) — gameplay code moves the character; animations are body motion only.
- Locomotion (Idle/Walk/Jog/Sprint/Run): make them loop seamlessly. Set the slot Looped=true (Locomotion group already defaults to Looped).
- Actions (shots/passes/tackles/feints/GK): one-shot. For kicks, put the ball-contact pose around 0.05-0.12s from the start (the server launches the ball immediately on input).
- Mirrored skill moves: export a left-sided version and fill the `_Left` slot; otherwise the right version is reused.

## 3. Export from Blender
- Select the armature + mesh, File > Export > FBX. Apply transforms, bake animation, disable Add Leaf Bones.

## 4. Import & publish in Roblox Studio
- Open Animation Editor, select an R15 rig, Import the FBX. Retarget if prompted.
- Publish to Roblox (the animation must be owned by YOU or your GROUP, otherwise it will not load in-game).
- Copy the animation id from Creator Hub.

## 5. Wire it
- Paste the id into the matching slot in `ReplicatedStorage/SoccerShared/AnimationIds`, e.g. `Shoot = "rbxassetid://123456789"`.
- Priorities/fades are configured in AnimationIds.Settings (Locomotion=Movement looped, Actions/Feints=Action one-shot). Overrides per slot are supported.
- The AnimationController plays locomotion automatically from speed/HasBall and plays action/feint slots on the corresponding events. Empty slots are skipped without errors.

## 6. Verify
- Play in Studio. The Output prints how many slots are filled. A wrong/unowned id loads with length 0 and warns once.
- NOTE: extended movement slots (TurnLeft/Backpedal/Shuffle/etc.) are prepared but the locomotion state machine currently auto-uses Run/Idle; wire extra states as you add them.

## Assets still needed (human creation)
- Real 3D kit geometry (Home/Away/Third/GK) — layered clothing or MeshParts. The kit template pipeline (Clubs.lua) is ready; supply the meshes.
- All custom animations (this guide).
- Sounds (SoundIds slots) and original club badges.
