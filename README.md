# NX26: Next Football

**Latest: `NX26_Next_Football_v3.rbxl`** — menu redesign + audit fixes. Open this file in Roblox Studio.

## Versions
- `NX26_Next_Football_v3.rbxl` — CURRENT (redesigned main menu, ClientMain hang fixed, server-authoritative sounds).
- `NX26_Next_Football_v2_2.rbxl` — previous (adds set pieces).
- `NX26_Next_Football_v2.rbxl`, `NX26_Next_Football_Updated.rbxl` — older.

## v3 changes
- Fixed ClientMain infinite WaitForChild (Remotes) that prevented the client from starting.
- SoundRunner now triggers world sounds from authoritative server hooks only (no client-spoofable events).
- SoundIds.Resolve + NXSounds folder support; SoundController per-player volumes.
- Main menu fully redesigned (original PES-Master-League-inspired): navy panels, featured KICK OFF card,
  COMING SOON locks, matchday rail, adaptive hints, PC/touch/gamepad, responsive.
- Preserved: stadium (357 MeshPart / 349 SurfaceAppearance byte-identical), 28 feints + 8 combos,
  set pieces, AI-only goalkeepers, server authority.

## Docs
- `docs/REPORT_v3.md` — full audit & redesign report.
- `NX26_v3_sources.zip` — all v3 scripts (Explorer paths) + report.

## Note
Static checks only (structure re-parse + Lua syntax). Not run in Roblox Studio here; verify on first Play.