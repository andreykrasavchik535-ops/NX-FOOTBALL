# NX26 Next Football — v3 Audit & Menu Redesign

Base: NX26_Next_Football_v2_2.rbxl (756 instances, 41 scripts). Output: NX26_Next_Football_v3.rbxl.

## Bugs found & fixed
1. ClientMain: load("Remotes") searched SoccerClient (Remotes is in SoccerShared) -> infinite WaitForChild -> client never started. FIXED (require from SoccerShared); SetPieceUI load preserved.
2. SoundRunner: OnServerEvent on KickPlayed/CatchPlayed/GoalScored (server->client events) -> never fired + wrong trust direction. FIXED: world sounds via authoritative server hooks (BallService.OnKick, GK.OnCatch/OnParry wrap, SoccerState.State, ball.Touched). Clients cannot forge goals/kicks.

## Changed scripts (5)
- StarterPlayer/StarterPlayerScripts/SoccerClient/ClientMain (LocalScript)
- StarterPlayer/StarterPlayerScripts/SoccerClient/MainMenu (ModuleScript) — full redesign
- StarterPlayer/StarterPlayerScripts/SoccerClient/SoundController (ModuleScript)
- ServerScriptService/SoccerServer/SoundRunner (ModuleScript)
- ReplicatedStorage/SoccerShared/SoundIds (ModuleScript) — added Resolve

## Menu redesign (original, PES-Master-League philosophy, not a copy)
- Deep-navy translucent panels, white typography, restrained light-blue accents, no neon.
- NX26 / NEXT FOOTBALL logo + accent underline, staggered fade-in.
- Left nav: KICK OFF (featured), ULTIMATE TEAM/CAREER/CLUBS (COMING SOON, locked), SETTINGS.
- Featured card per selection (KICK OFF hero: pitch motif + spinning ball), crossfade transitions.
- Right rail on wide screens: static MATCHDAY + ABOUT (decorative, no fake news system).
- Adaptive control-hints footer; PC hover, touch tap, gamepad D-pad/A; responsive rebuild on resize.
- 3D Tottenham stadium (MenuCamera) behind the translucent UI.

## Preserved (verified)
- Stadium byte-identical: 357 MeshPart + 349 SurfaceAppearance; only script Source chunks rewritten.
- 28 feints + 8 combos; SetPieceService + SetPieceUI; AI only goalkeepers; server authority unchanged.

## Verification (static, NOT Roblox Studio)
- Re-parsed v3: 756 instances, 357 MeshPart, 349 SurfaceAppearance, 41 scripts.
- Syntax: balance 40/41. All 5 fixes confirmed present; every modified source embedded correctly.
- NOT run in Studio: runtime/visuals/screenshot not verified here.

## Optional sounds
Create ReplicatedStorage/NXSounds, drag mp3 in, name: Kick, Crowd, Whistle, Tackle, UIClick, Post, Goal (Save/UIHover optional). Crowd last-2s auto-trimmed. Pass shares Kick.

## Notes
- ULTIMATE TEAM/CAREER/CLUBS remain COMING SOON by design.
- Per-player volume for server world sounds uses client-local SoundGroup volume; confirm in Studio.