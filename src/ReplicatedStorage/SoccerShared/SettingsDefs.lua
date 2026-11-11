--[[
	SoccerShared/SettingsDefs (ModuleScript)
	Default player settings + a strict validator shared by client and server.
	The client applies settings locally; the server persists them (SettingsService).
	Validation means a malformed / malicious payload can never store out-of-range values.
]]
local SettingsDefs = {}

SettingsDefs.Version = 1

SettingsDefs.Defaults = {
	Volume = { Master = 0.8, Music = 0.6, SFX = 0.8, Crowd = 0.5 },
	Camera = { ShiftLock = false, Sensitivity = 1.0 },
	Graphics = { Quality = "Auto" },
	Controls = {
		Shoot = "F", Pass = "E", Long = "R", Tackle = "Q", Slide = "X",
		Sprint = "LeftShift", Lock = "L", Side = "G", FeintPanel = "V",
		DiveLeft = "Z", DiveRight = "C",
	},
}

local QUALITY = { Auto = true, Low = true, Medium = true, High = true }

local VALID_KEYS = {
	F=true,E=true,R=true,Q=true,X=true,G=true,L=true,V=true,Z=true,C=true,T=true,Y=true,U=true,
	H=true,J=true,K=true,B=true,N=true,M=true,P=true,
	One=true,Two=true,Three=true,Four=true,Five=true,Six=true,Seven=true,Eight=true,Nine=true,Zero=true,
	LeftShift=true,RightShift=true,LeftControl=true,RightControl=true,LeftAlt=true,RightAlt=true,
	Space=true,Tab=true,
}

local function clampNum(v, lo, hi, fallback)
	if type(v) ~= "number" or v ~= v then
		return fallback
	end
	return math.clamp(v, lo, hi)
end

function SettingsDefs.Validate(raw)
	local d = SettingsDefs.Defaults
	local out = { Volume = {}, Camera = {}, Graphics = {}, Controls = {} }
	raw = (type(raw) == "table") and raw or {}

	local rv = (type(raw.Volume) == "table") and raw.Volume or {}
	for k, def in pairs(d.Volume) do
		out.Volume[k] = clampNum(rv[k], 0, 1, def)
	end

	local rc = (type(raw.Camera) == "table") and raw.Camera or {}
	out.Camera.ShiftLock = (rc.ShiftLock == true)
	out.Camera.Sensitivity = clampNum(rc.Sensitivity, 0.2, 3.0, d.Camera.Sensitivity)

	local rg = (type(raw.Graphics) == "table") and raw.Graphics or {}
	out.Graphics.Quality = QUALITY[rg.Quality] and rg.Quality or d.Graphics.Quality

	local rk = (type(raw.Controls) == "table") and raw.Controls or {}
	for action, def in pairs(d.Controls) do
		local key = rk[action]
		if type(key) == "string" and VALID_KEYS[key] then
			out.Controls[action] = key
		else
			out.Controls[action] = def
		end
	end

	return out
end

function SettingsDefs.Copy()
	return SettingsDefs.Validate(SettingsDefs.Defaults)
end

return SettingsDefs
