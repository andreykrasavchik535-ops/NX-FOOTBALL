--[[
	SoccerShared/SoundIds (ModuleScript)      <<<  PUT YOUR SOUND IDs HERE  >>>
	Every slot is EMPTY ("") on purpose. No invented / fake asset ids are used.
	An empty slot is skipped safely: no sound for that event, never an error.
	Publish your own sounds and paste the id between the quotes.
	Accepted: "rbxassetid://123", "123", or 123 (Normalize adds the prefix).
]]
local SoundIds = {}

SoundIds.Slots = {
	Whistle = "", Kick = "", Pass = "", Post = "", Goal = "",
	Save = "", Tackle = "", UIClick = "", UIHover = "", Crowd = "",
}

SoundIds.Settings = {
	Whistle = { Volume = 0.7, Loop = false },
	Kick = { Volume = 0.8, Loop = false },
	Pass = { Volume = 0.6, Loop = false },
	Post = { Volume = 0.9, Loop = false },
	Goal = { Volume = 0.9, Loop = false },
	Save = { Volume = 0.7, Loop = false },
	Tackle = { Volume = 0.6, Loop = false },
	UIClick = { Volume = 0.5, Loop = false },
	UIHover = { Volume = 0.25, Loop = false },
	Crowd = { Volume = 0.35, Loop = true },
}

function SoundIds.Normalize(id)
	if type(id) == "number" and id > 0 and id == math.floor(id) then
		return "rbxassetid://" .. string.format("%d", id)
	end
	if type(id) ~= "string" then
		return nil
	end
	local digits = string.match(id, "^%s*rbxassetid://(%d+)%s*$") or string.match(id, "^%s*(%d+)%s*$")
	if digits and tonumber(digits) and tonumber(digits) > 0 then
		return "rbxassetid://" .. digits
	end
	return nil
end

function SoundIds.Get(key)
	return SoundIds.Normalize(SoundIds.Slots[key])
end

function SoundIds.GetSettings(key)
	local s = SoundIds.Settings[key]
	if s then
		return s
	end
	return { Volume = 0.6, Loop = false }
end

function SoundIds.Has(key)
	return SoundIds.Get(key) ~= nil
end

return SoundIds
