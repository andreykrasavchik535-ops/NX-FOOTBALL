--[[
	SoccerShared/Stadiums (ModuleScript)
	Registry of stadiums. The existing Tottenham model is preserved and is the only
	ENABLED stadium now. Future stadiums are listed but marked Coming Soon and are
	NOT selectable, so nothing shows as working when it is not ready.
]]
local Stadiums = {}

Stadiums.List = {
	{ Id = "Tottenham", Name = "Tottenham Stadium", Model = "Tottenham",
		Enabled = true, ComingSoon = false,
		Description = "The full imported stadium, preserved exactly as in the source project." },
	{ Id = "NXArena", Name = "NX Arena", Model = nil,
		Enabled = false, ComingSoon = true,
		Description = "A future NX-branded arena. Not built yet." },
}

Stadiums.ById = {}
for _, s in ipairs(Stadiums.List) do
	Stadiums.ById[s.Id] = s
end

Stadiums.Default = "Tottenham"

function Stadiums.Get(id)
	return Stadiums.ById[id]
end

function Stadiums.IsAvailable(id)
	local s = Stadiums.ById[id]
	return s ~= nil and s.Enabled == true
end

function Stadiums.EnabledList()
	local out = {}
	for _, s in ipairs(Stadiums.List) do
		if s.Enabled then
			table.insert(out, s)
		end
	end
	return out
end

return Stadiums
