# NX26: NEXT FOOTBALL — FINAL Development Report

Branch: `dev/final` (original `main` untouched; v3 preserved as backup). Output: `NX26_Next_Football_FINAL.rbxl`.

## Environment honesty
- Roblox Studio is NOT available here. Nothing was runtime-tested. All gameplay below is IMPLEMENTED BUT NOT TESTED at runtime.
- Verified statically: binary structure re-parse, Lua syntax (base 41/41 earlier; modified files pass balance check this session), and presence of every fix in the built file.

## What changed in FINAL (vs v3)
1. Set-piece reliability (Phase 2):
   - Added MatchService.IsSetPiece(); ActionService (shoot/pass/long + tackles) and FeintService now reject normal actions during a set piece (previously state stayed Live and normal kicks could bypass the set piece).
   - SetPiece.End("kick") now clears restart exclusivity, so the ball is LIVE immediately after a free kick/penalty: the goalkeeper can save it and opponents can rebound (previously a 2.5s block prevented saves/rebounds).
2. Animation architecture (Phase 4): AnimationIds extended to a full categorized table (movement, ball control, shooting, passing, defending, goalkeeper) while preserving all 28 skill-move slots. Blender guide + AnimationId table included.
3. Menu (Phase 6): KICK OFF featured card now shows a real 3D ball via ViewportFrame (pcall-guarded, falls back to 2D if unavailable). No static image substitution.

## Preserved (verified)
- Tottenham stadium byte-identical: 357 MeshPart + 349 SurfaceAppearance; only script Source changed.
- 28 skill moves + 8 combos; 8 clubs; formations; SetPieceService/SetPieceUI; AI-only goalkeepers; server-authoritative scoring/actions.

## Status by category
### IMPLEMENTED AND STATIC-VERIFIED (not runtime-tested)
- Set-piece action gating + live-ball-after-kick; extended AnimationId table; menu 3D ball preview; project structure & syntax.

### IMPLEMENTED BUT NOT TESTED (runtime)
- Ball physics (free physical ball, server-owned), passing/shooting/long/through/lob, tackles, 28 feints, GK AI (positioning/dive/catch/parry), match flow (kickoff/halves/full-time/results), 5v5/11v11 team assignment, PC/mobile/gamepad controls, HUD, settings, sound hooks, main menu.

### PARTIALLY IMPLEMENTED
- Locomotion state machine: auto Run/Idle wired; extended movement slots (turns/backpedal/shuffle/accel/decel) prepared but not auto-wired.
- Set pieces: FreeKick + Penalty use the aimed UI; corners/throw-ins/goal-kicks use the generic restart placement (no aimed UI).
- 3D kits: template pipeline ready (Clubs.lua Home/Away); actual 3D geometry not supplied.

### NOT IMPLEMENTED
- Ultimate Team / Career / Clubs (marked COMING SOON in menu).
- Broadcast camera (kept existing camera + shift-lock to avoid breaking aiming; not tested).
- Real 3D kit meshes, custom animations, goal-celebration choreography.

### REQUIRES HUMAN ASSET CREATION
- 3D kit geometry (Home/Away/Third/GK), Blender animations (see BLENDER_GUIDE.md), sounds (SoundIds), original club badges.

## Fixed bugs (this session)
- Normal actions could bypass set pieces -> gated.
- Goalkeeper/opponents blocked 2.5s after a set-piece kick (no penalty saves) -> ball live after kick.

## Remaining / to verify in Studio
- Run a full match: set pieces (free kick/penalty), GK saves, rebounds, no frozen players after restarts.
- Fill animation/sound/kit assets and confirm they load (owned by you/group).
- Multiplayer with real players (not tested here).

## How to open
Download NX26_Next_Football_FINAL.rbxl from branch dev/final -> Roblox Studio -> File > Open. Play. See BLENDER_GUIDE.md and ANIMATION_TABLE.md to add assets.
