--[[
	SoccerShared/Clubs (ModuleScript)
	8 original NX clubs. No real-world logos, names or EA Sports FC assets are used.

	KIT TEMPLATES: ShirtTemplate / PantsTemplate are intentionally EMPTY ("").
	When a template is empty the player's ORIGINAL Roblox avatar clothing is kept
	(we never clear or overwrite it). To use a custom kit, publish a Shirt / Pants
	asset and put its id here, e.g. ShirtTemplate = "rbxassetid://123456789".
	Only a non-empty template is applied; an empty one is always skipped.
]]
local Clubs = {}

local function kit(shirt, pants)
	return { ShirtTemplate = shirt or "", PantsTemplate = pants or "" }
end

Clubs.List = {
	{ Id = "Aurora", Name = "NX Aurora", Short = "AUR",
		Primary = Color3.fromRGB(86, 170, 255), Secondary = Color3.fromRGB(245, 248, 255),
		UI = Color3.fromRGB(86, 170, 255), UIText = Color3.fromRGB(10, 16, 28),
		Home = kit(), Away = kit() },
	{ Id = "Crimson", Name = "NX Crimson", Short = "CRM",
		Primary = Color3.fromRGB(225, 60, 60), Secondary = Color3.fromRGB(20, 20, 24),
		UI = Color3.fromRGB(225, 60, 60), UIText = Color3.fromRGB(255, 245, 245),
		Home = kit(), Away = kit() },
	{ Id = "Emerald", Name = "NX Emerald", Short = "EMR",
		Primary = Color3.fromRGB(46, 180, 110), Secondary = Color3.fromRGB(245, 250, 246),
		UI = Color3.fromRGB(46, 180, 110), UIText = Color3.fromRGB(8, 20, 12),
		Home = kit(), Away = kit() },
	{ Id = "Solar", Name = "NX Solar", Short = "SOL",
		Primary = Color3.fromRGB(250, 200, 60), Secondary = Color3.fromRGB(30, 60, 160),
		UI = Color3.fromRGB(250, 200, 60), UIText = Color3.fromRGB(24, 18, 4),
		Home = kit(), Away = kit() },
	{ Id = "Violet", Name = "NX Violet", Short = "VIO",
		Primary = Color3.fromRGB(150, 90, 235), Secondary = Color3.fromRGB(248, 246, 255),
		UI = Color3.fromRGB(150, 90, 235), UIText = Color3.fromRGB(250, 248, 255),
		Home = kit(), Away = kit() },
	{ Id = "Orange", Name = "NX Orange", Short = "ORG",
		Primary = Color3.fromRGB(250, 130, 40), Secondary = Color3.fromRGB(24, 24, 28),
		UI = Color3.fromRGB(250, 130, 40), UIText = Color3.fromRGB(24, 14, 4),
		Home = kit(), Away = kit() },
	{ Id = "Glacier", Name = "NX Glacier", Short = "GLC",
		Primary = Color3.fromRGB(235, 242, 250), Secondary = Color3.fromRGB(120, 180, 230),
		UI = Color3.fromRGB(200, 220, 245), UIText = Color3.fromRGB(14, 22, 36),
		Home = kit(), Away = kit() },
	{ Id = "Noir", Name = "NX Noir", Short = "NOR",
		Primary = Color3.fromRGB(28, 30, 36), Secondary = Color3.fromRGB(220, 180, 80),
		UI = Color3.fromRGB(60, 64, 74), UIText = Color3.fromRGB(240, 220, 160),
		Home = kit(), Away = kit() },
}

Clubs.ById = {}
for _, c in ipairs(Clubs.List) do
	Clubs.ById[c.Id] = c
end

Clubs.DefaultHome = "Aurora"
Clubs.DefaultAway = "Crimson"

function Clubs.Get(id)
	return Clubs.ById[id]
end

function Clubs.GetKit(id, which)
	local c = Clubs.ById[id]
	if not c then
		return kit()
	end
	if which == "Away" then
		return c.Away
	end
	return c.Home
end

function Clubs.HasTemplate(template)
	return type(template) == "string" and template ~= ""
end

function Clubs.Count()
	return #Clubs.List
end

return Clubs
