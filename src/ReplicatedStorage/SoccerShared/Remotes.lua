--[[
	SoccerShared/Remotes (ModuleScript)
	Creates (server) or waits for (client) the RemoteEvents in ReplicatedStorage.SoccerRemotes.
	Every event is listed here once, so names cannot drift between scripts.
]]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = {
	-- client -> server (intents only, never results)
	"ActionStart", "ActionRelease", "Tackle", "Feint", "Sprint", "JoinTeam", "SetRole", "AssignPosition", "GKDive", "MatchControl", "SettingsSync",
	-- server -> client
	"ActionResult", "FeintApproved", "TackleApproved", "DiveApproved", "Notify", "GoalScored", "MatchEnded", "ComboHit",
	"KickPlayed",   -- (userId, action, chargeFraction)   a shot / pass / long ball was struck
	"CatchPlayed",  -- (userId)                           the goalkeeper caught the ball
}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("SoccerRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SoccerRemotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(NAMES) do
		if not folder:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("SoccerRemotes")
end

local Remotes = {}

function Remotes.get(name)
	return folder:WaitForChild(name)
end

return Remotes
