--[[
	SoccerShared/Formations (ModuleScript)
	Named formations for 5v5 and 11v11 (extensible). Every slot is a REAL player
	position; no bots fill empty slots. The only AI is the goalkeeper, which spawns
	only when no real player occupies the GK slot.

	Coordinates are fractions in the team's OWN half:
	  x : -1..1 across the width (times Field.halfW)
	  z : 0..1 depth from own goal line (0) to halfway line (1)
	  Local Z = defendSign * Field.halfL * (1 - z)  (same convention as MatchService)
	role: "GK" or "FIELD". id unique inside a formation; label shown in the UI.
]]
local Formations = {}

local function slot(id, label, role, x, z)
	return { Id = id, Label = label, Role = role, X = x, Z = z }
end

Formations.BySize = {
	[5] = {
		{ Id = "1-2-1", Name = "1-2-1 (Balanced)", Slots = {
			slot("GK","GK","GK",0,0.06), slot("CB","CB","FIELD",0,0.28),
			slot("LM","LM","FIELD",-0.5,0.55), slot("RM","RM","FIELD",0.5,0.55),
			slot("ST","ST","FIELD",0,0.82) } },
		{ Id = "2-1-1", Name = "2-1-1 (Solid)", Slots = {
			slot("GK","GK","GK",0,0.06), slot("LB","LB","FIELD",-0.5,0.30),
			slot("RB","RB","FIELD",0.5,0.30), slot("CM","CM","FIELD",0,0.55),
			slot("ST","ST","FIELD",0,0.82) } },
		{ Id = "1-1-2", Name = "1-1-2 (Attack)", Slots = {
			slot("GK","GK","GK",0,0.06), slot("CB","CB","FIELD",0,0.30),
			slot("CM","CM","FIELD",0,0.55), slot("LW","LW","FIELD",-0.5,0.80),
			slot("RW","RW","FIELD",0.5,0.80) } },
	},
	[11] = {
		{ Id = "4-4-2", Name = "4-4-2 (Classic)", Slots = {
			slot("GK","GK","GK",0,0.05), slot("LB","LB","FIELD",-0.7,0.28),
			slot("CB1","CB","FIELD",-0.25,0.24), slot("CB2","CB","FIELD",0.25,0.24),
			slot("RB","RB","FIELD",0.7,0.28), slot("LM","LM","FIELD",-0.7,0.55),
			slot("CM1","CM","FIELD",-0.25,0.52), slot("CM2","CM","FIELD",0.25,0.52),
			slot("RM","RM","FIELD",0.7,0.55), slot("ST1","ST","FIELD",-0.3,0.82),
			slot("ST2","ST","FIELD",0.3,0.82) } },
		{ Id = "4-3-3", Name = "4-3-3 (Attack)", Slots = {
			slot("GK","GK","GK",0,0.05), slot("LB","LB","FIELD",-0.7,0.28),
			slot("CB1","CB","FIELD",-0.25,0.24), slot("CB2","CB","FIELD",0.25,0.24),
			slot("RB","RB","FIELD",0.7,0.28), slot("CM1","CM","FIELD",-0.4,0.50),
			slot("CM2","CM","FIELD",0,0.55), slot("CM3","CM","FIELD",0.4,0.50),
			slot("LW","LW","FIELD",-0.65,0.82), slot("ST","ST","FIELD",0,0.85),
			slot("RW","RW","FIELD",0.65,0.82) } },
		{ Id = "3-5-2", Name = "3-5-2 (Wide)", Slots = {
			slot("GK","GK","GK",0,0.05), slot("CB1","CB","FIELD",-0.4,0.26),
			slot("CB2","CB","FIELD",0,0.24), slot("CB3","CB","FIELD",0.4,0.26),
			slot("LM","LM","FIELD",-0.8,0.50), slot("CM1","CM","FIELD",-0.35,0.52),
			slot("CM2","CM","FIELD",0,0.55), slot("CM3","CM","FIELD",0.35,0.52),
			slot("RM","RM","FIELD",0.8,0.50), slot("ST1","ST","FIELD",-0.3,0.82),
			slot("ST2","ST","FIELD",0.3,0.82) } },
		{ Id = "4-2-3-1", Name = "4-2-3-1 (Control)", Slots = {
			slot("GK","GK","GK",0,0.05), slot("LB","LB","FIELD",-0.7,0.28),
			slot("CB1","CB","FIELD",-0.25,0.24), slot("CB2","CB","FIELD",0.25,0.24),
			slot("RB","RB","FIELD",0.7,0.28), slot("CDM1","CDM","FIELD",-0.25,0.42),
			slot("CDM2","CDM","FIELD",0.25,0.42), slot("CAM1","CAM","FIELD",-0.5,0.65),
			slot("CAM2","CAM","FIELD",0,0.68), slot("CAM3","CAM","FIELD",0.5,0.65),
			slot("ST","ST","FIELD",0,0.85) } },
	},
}

Formations.Default = { [5] = "1-2-1", [11] = "4-4-2" }
Formations.Sizes = { 5, 11 }

function Formations.List(size)
	return Formations.BySize[size] or {}
end

function Formations.Get(size, id)
	local list = Formations.BySize[size]
	if not list then
		return nil
	end
	for _, f in ipairs(list) do
		if f.Id == id then
			return f
		end
	end
	return nil
end

function Formations.DefaultFor(size)
	local id = Formations.Default[size]
	return Formations.Get(size, id) or (Formations.BySize[size] or {})[1]
end

function Formations.SlotCount(size, id)
	local f = Formations.Get(size, id)
	return f and #f.Slots or 0
end

return Formations
