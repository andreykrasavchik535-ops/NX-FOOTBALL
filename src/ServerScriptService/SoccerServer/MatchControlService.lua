--[[
	ServerScriptService/SoccerServer/MatchControlService (ModuleScript)
	The ONLY place that may start / stop a match or change the match setup. Everything the client sends
	through the "MatchControl" remote is an intent that is fully validated here:
	  * only the host (lowest UserId present) may edit the setup / start / continue / end,
	  * every setup field is validated against Clubs / Formations / Stadiums / Config,
	  * a match can only start from the Lobby, and only with enough real players.
	The current setup + host are mirrored as attributes on ReplicatedStorage.SoccerState for the menu UI.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Clubs = require(Shared:WaitForChild("Clubs"))
local Formations = require(Shared:WaitForChild("Formations"))
local Stadiums = require(Shared:WaitForChild("Stadiums"))

local TeamService = require(script.Parent:WaitForChild("TeamService"))
local MatchService = require(script.Parent:WaitForChild("MatchService"))

local MatchControl = {}
local stateFolder
local buckets = {}
local hostUserId = 0

local currentSetup = {
	homeClub = Clubs.DefaultHome,
	awayClub = Clubs.DefaultAway,
	homeKit = "Home",
	awayKit = "Away",
	halfSeconds = Config.DEFAULT_HALF_SECONDS,
	teamSize = Config.TEAM_SIZE,
	formation = (Formations.DefaultFor(Config.TEAM_SIZE) or { Id = "1-2-1" }).Id,
	stadium = Stadiums.Default,
}

local function setAttr(name, value)
	if stateFolder:GetAttribute(name) ~= value then
		stateFolder:SetAttribute(name, value)
	end
end

local function publishSetup()
	setAttr("HomeClub", currentSetup.homeClub)
	setAttr("AwayClub", currentSetup.awayClub)
	setAttr("HomeKit", currentSetup.homeKit)
	setAttr("AwayKit", currentSetup.awayKit)
	setAttr("HalfSeconds", currentSetup.halfSeconds)
	setAttr("TeamSize", currentSetup.teamSize)
	setAttr("Formation", currentSetup.formation)
	setAttr("Stadium", currentSetup.stadium)
	setAttr("HostUserId", hostUserId)
end

local function recomputeHost()
	local lowest = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if lowest == 0 or p.UserId < lowest then
			lowest = p.UserId
		end
	end
	hostUserId = lowest
	setAttr("HostUserId", hostUserId)
end

local function isHost(player)
	return player.UserId == hostUserId and hostUserId ~= 0
end

local function inLobby()
	local s = MatchService.GetState()
	return s == "Lobby" or s == "Waiting"
end

local function halfAllowed(v)
	for _, opt in ipairs(Config.HALF_LENGTH_OPTIONS) do
		if v == opt then
			return true
		end
	end
	return false
end

local function sizeAllowed(v)
	for _, s in ipairs(Formations.Sizes) do
		if v == s then
			return true
		end
	end
	return false
end

-- Returns a clean setup table, or (nil, reason).
local function validateSetup(raw)
	if type(raw) ~= "table" then
		return nil, "Bad setup"
	end
	local s = {}
	s.homeClub = raw.homeClub
	s.awayClub = raw.awayClub
	if not Clubs.Get(s.homeClub) or not Clubs.Get(s.awayClub) then
		return nil, "Unknown club"
	end
	if not Config.ALLOW_SAME_CLUB and s.homeClub == s.awayClub then
		return nil, "Clubs must be different"
	end
	s.homeKit = (raw.homeKit == "Away") and "Away" or "Home"
	s.awayKit = (raw.awayKit == "Away") and "Away" or "Home"
	s.halfSeconds = raw.halfSeconds
	if not halfAllowed(s.halfSeconds) then
		return nil, "Bad half length"
	end
	s.teamSize = raw.teamSize
	if not sizeAllowed(s.teamSize) then
		return nil, "Bad team size"
	end
	s.formation = raw.formation
	if not Formations.Get(s.teamSize, s.formation) then
		return nil, "Bad formation"
	end
	s.stadium = raw.stadium
	if not Stadiums.IsAvailable(s.stadium) then
		return nil, "Stadium not available"
	end
	return s
end

local function applySetup(s)
	currentSetup = s
	TeamService.SetClubs(s.homeClub, s.awayClub)
	TeamService.SetKits(s.homeKit, s.awayKit)
	TeamService.SetFormation(s.teamSize, s.formation)
	publishSetup()
end

local function enoughPlayers()
	local r, b = TeamService.Count("RED"), TeamService.Count("BLUE")
	if Config.TEST_MODE then
		return r + b >= Config.MIN_PLAYERS_TO_START
	end
	return r >= 1 and b >= 1 and r + b >= Config.MIN_PLAYERS_TO_START
end

local function notify(player, kind, text)
	Remotes.get("Notify"):FireClient(player, kind, text)
end

local function onControl(player, payload)
	local b = buckets[player]
	if not b or not b:take() or type(payload) ~= "table" then
		return
	end
	local cmd = payload.cmd
	if type(cmd) ~= "string" then
		return
	end

	if cmd == "UpdateSetup" then
		if not isHost(player) then
			return notify(player, "bad", "Only the host can change the setup")
		end
		if not inLobby() then
			return notify(player, "bad", "Setup is locked during a match")
		end
		local s, err = validateSetup(payload.setup)
		if not s then
			return notify(player, "bad", err)
		end
		applySetup(s)
		notify(player, "good", "Setup updated")

	elseif cmd == "StartMatch" then
		if not isHost(player) then
			return notify(player, "bad", "Only the host can start the match")
		end
		if not inLobby() then
			return notify(player, "bad", "A match is already running")
		end
		local s, err = validateSetup(payload.setup or currentSetup)
		if not s then
			return notify(player, "bad", err)
		end
		if not enoughPlayers() then
			return notify(player, "bad", "Need players on both teams")
		end
		applySetup(s)
		MatchService.StartMatch(s)

	elseif cmd == "Continue" then
		if MatchService.GetState() ~= "Results" then
			return
		end
		if not isHost(player) then
			return notify(player, "bad", "Only the host can continue")
		end
		MatchService.ReturnToLobby()

	elseif cmd == "EndMatch" then
		if not isHost(player) then
			return notify(player, "bad", "Only the host can end the match")
		end
		MatchService.AbortMatch()
	end
end

function MatchControlService_GetSetup()
	return currentSetup
end
MatchControl.GetSetup = MatchControlService_GetSetup

function MatchControl.Init()
	stateFolder = ReplicatedStorage:FindFirstChild("SoccerState")
	if not stateFolder then
		stateFolder = Instance.new("Folder")
		stateFolder.Name = "SoccerState"
		stateFolder.Parent = ReplicatedStorage
	end
	local function add(p)
		buckets[p] = Util.newBucket(Config.RATE_MISC.rate, Config.RATE_MISC.burst)
		recomputeHost()
	end
	for _, p in ipairs(Players:GetPlayers()) do
		add(p)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
		task.defer(recomputeHost)
	end)
	Remotes.get("MatchControl").OnServerEvent:Connect(onControl)
	applySetup(currentSetup)
	recomputeHost()
end

return MatchControl
