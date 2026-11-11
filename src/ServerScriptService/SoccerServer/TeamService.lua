--[[
	ServerScriptService/SoccerServer/TeamService (ModuleScript)
	RED (AWAY) / BLUE (HOME) sides, player choice, balance rule, goalkeeper role, defended end.
	Extended for NX26: per-side CLUB + KIT, formation POSITION assignment, a match lock (no team/role
	changes during a live match) and support for the AI goalkeeper "pseudo-player" entities.

	AI entities are tables with IsAI=true. GetTeam/GetRole understand them, but they are NEVER added to
	GetMembers/AllPlayers, so passes / tackles / feints never target them and they never count as players.
]]
local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Clubs = require(Shared:WaitForChild("Clubs"))
local Formations = require(Shared:WaitForChild("Formations"))

local TeamService = {}

local teamObjs = {}
local members = { RED = {}, BLUE = {} }
local teamOf = {}
local roleOf = {}
local positionOf = {}                    -- [player] = formation slot Id
local defendSign = { RED = -1, BLUE = 1 }
local buckets = {}
local locked = false                     -- true while a match is running (set by MatchService)

local clubOf = { RED = Clubs.DefaultAway, BLUE = Clubs.DefaultHome }
local kitOf = { RED = "Away", BLUE = "Home" }
local formationSize = Config.TEAM_SIZE
local formationId = (Formations.DefaultFor(Config.TEAM_SIZE) or { Id = "1-2-1" }).Id

local changed = Instance.new("BindableEvent")
TeamService.Changed = changed.Event

local function other(name)
	return name == "RED" and "BLUE" or "RED"
end
TeamService.Other = other

local function count(name)
	local n = 0
	for _ in pairs(members[name]) do
		n = n + 1
	end
	return n
end

local function mkTeam(name, color)
	local t = Teams:FindFirstChild(name)
	if not t then
		t = Instance.new("Team")
		t.Name = name
		t.Parent = Teams
	end
	t.TeamColor = color
	t.AutoAssignable = false
	return t
end

local function applyAttributes(player)
	player:SetAttribute("SoccerTeam", teamOf[player] or "")
	player:SetAttribute("SoccerRole", roleOf[player] or "FIELD")
	player:SetAttribute("SoccerPosition", positionOf[player] or "")
end

local function removeFromTeam(player)
	local name = teamOf[player]
	if name then
		members[name][player] = nil
		teamOf[player] = nil
	end
	roleOf[player] = nil
	positionOf[player] = nil
	player.Team = nil
	player.Neutral = true
	applyAttributes(player)
end

-- Kit application: ONLY when a real template id is set. Empty template = keep the avatar's own clothing.
local function applyKit(player)
	local team = teamOf[player]
	if not team then
		return
	end
	local kit = Clubs.GetKit(clubOf[team], kitOf[team])
	local char = player.Character
	if not char then
		return
	end
	if Clubs.HasTemplate(kit.ShirtTemplate) then
		local shirt = char:FindFirstChildOfClass("Shirt")
		if not shirt then
			shirt = Instance.new("Shirt")
			shirt.Parent = char
		end
		shirt.ShirtTemplate = kit.ShirtTemplate
	end
	if Clubs.HasTemplate(kit.PantsTemplate) then
		local pants = char:FindFirstChildOfClass("Pants")
		if not pants then
			pants = Instance.new("Pants")
			pants.Parent = char
		end
		pants.PantsTemplate = kit.PantsTemplate
	end
end
TeamService.ApplyKit = applyKit

function TeamService.SetLocked(value)
	locked = value and true or false
end

function TeamService.IsLocked()
	return locked
end

function TeamService.Join(player, pref)
	if locked then
		return false, "Match in progress"
	end
	if pref ~= "RED" and pref ~= "BLUE" then
		return false, "Choose a team"
	end
	local current = teamOf[player]
	if current == pref then
		return true, "Already in team"
	end
	local counts = { RED = count("RED"), BLUE = count("BLUE") }
	if current then
		counts[current] = counts[current] - 1
	end
	local target = pref
	if counts[target] >= formationSize then
		return false, "Team is full"
	end
	if Config.AUTO_BALANCE and counts[target] - counts[other(target)] >= (Config.TEAM_MAX_LEAD or 2) then
		return false, "This team already has " .. (Config.TEAM_MAX_LEAD or 2) .. " more players"
	end
	if current then
		removeFromTeam(player)
	end
	members[target][player] = true
	teamOf[player] = target
	roleOf[player] = "FIELD"
	positionOf[player] = nil
	player.Team = teamObjs[target]
	player.Neutral = false
	applyAttributes(player)
	changed:Fire(player, target)
	task.delay(0.5, applyKit, player)
	return true, "Joined " .. (target == "RED" and "AWAY" or "HOME")
end

function TeamService.Leave(player)
	if teamOf[player] then
		removeFromTeam(player)
		changed:Fire(player, nil)
	end
end

function TeamService.SetRole(player, role)
	if locked then
		return false, "Match in progress"
	end
	local name = teamOf[player]
	if not name then
		return false, "Join a team first"
	end
	if role == "GK" then
		for p in pairs(members[name]) do
			if p ~= player and roleOf[p] == "GK" then
				return false, "Your team already has a goalkeeper"
			end
		end
		roleOf[player] = "GK"
		positionOf[player] = "GK"
	else
		roleOf[player] = "FIELD"
		if positionOf[player] == "GK" then
			positionOf[player] = nil
		end
	end
	applyAttributes(player)
	changed:Fire(player, name)
	return true, role
end

-- Formation position assignment (FIELD slots only; GK is taken via SetRole).
function TeamService.AssignPosition(player, slotId)
	if locked then
		return false, "Match in progress"
	end
	local name = teamOf[player]
	if not name then
		return false, "Join a team first"
	end
	if type(slotId) ~= "string" then
		return false, "Bad position"
	end
	local formation = Formations.Get(formationSize, formationId)
	if not formation then
		return false, "No formation"
	end
	local target
	for _, s in ipairs(formation.Slots) do
		if s.Id == slotId then
			target = s
			break
		end
	end
	if not target then
		return false, "Unknown position"
	end
	if target.Role == "GK" then
		return false, "Use the goalkeeper role"
	end
	for p in pairs(members[name]) do
		if p ~= player and positionOf[p] == slotId then
			return false, "Position taken"
		end
	end
	positionOf[player] = slotId
	roleOf[player] = "FIELD"
	applyAttributes(player)
	changed:Fire(player, name)
	return true, slotId
end

function TeamService.GetPosition(player)
	return positionOf[player]
end

-- Club / kit / formation configuration (set from the match setup, only while not locked).
function TeamService.SetClubs(homeId, awayId)
	if Clubs.Get(homeId) then
		clubOf.BLUE = homeId
	end
	if Clubs.Get(awayId) then
		clubOf.RED = awayId
	end
end

function TeamService.GetClub(name)
	return clubOf[name]
end

function TeamService.SetKits(homeKit, awayKit)
	if homeKit == "Home" or homeKit == "Away" then
		kitOf.BLUE = homeKit
	end
	if awayKit == "Home" or awayKit == "Away" then
		kitOf.RED = awayKit
	end
end

function TeamService.GetKitSide(name)
	return kitOf[name]
end

function TeamService.SetFormation(size, id)
	if Formations.Get(size, id) then
		formationSize = size
		formationId = id
		for p in pairs(positionOf) do
			positionOf[p] = nil
		end
		for _, name in ipairs({ "RED", "BLUE" }) do
			for p in pairs(members[name]) do
				applyAttributes(p)
			end
		end
	end
end

function TeamService.GetFormationSize()
	return formationSize
end

function TeamService.GetFormationId()
	return formationId
end

function TeamService.GetFormationSlots()
	local f = Formations.Get(formationSize, formationId)
	return f and f.Slots or {}
end

-- AI-aware accessors. AI entities are tables with IsAI=true.
local function isAI(p)
	return type(p) == "table" and p.IsAI == true
end

function TeamService.GetTeam(player)
	if isAI(player) then
		return player.Team
	end
	return teamOf[player]
end

function TeamService.GetRole(player)
	if isAI(player) then
		return "GK"
	end
	return roleOf[player]
end

function TeamService.Count(name)
	return count(name)
end

function TeamService.GetMembers(name)
	local list = {}
	for p in pairs(members[name]) do
		table.insert(list, p)
	end
	table.sort(list, function(a, b) return a.UserId < b.UserId end)
	return list
end

function TeamService.AllPlayers()
	local list = {}
	for _, name in ipairs({ "RED", "BLUE" }) do
		for p in pairs(members[name]) do
			table.insert(list, p)
		end
	end
	return list
end

function TeamService.SetDefendSign(name, sign)
	defendSign[name] = sign
end

function TeamService.GetDefendSign(name)
	return defendSign[name]
end

function TeamService.SwapSides()
	defendSign.RED, defendSign.BLUE = defendSign.BLUE, defendSign.RED
end

function TeamService.Init()
	teamObjs.RED = mkTeam("RED", Config.RED_COLOR)
	teamObjs.BLUE = mkTeam("BLUE", Config.BLUE_COLOR)

	local function onAdded(player)
		buckets[player] = Util.newBucket(Config.RATE_MISC.rate, Config.RATE_MISC.burst)
		player.Team = nil
		player.Neutral = true
		applyAttributes(player)
		player.CharacterAdded:Connect(function()
			task.delay(0.5, applyKit, player)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onAdded(p)
	end
	Players.PlayerAdded:Connect(onAdded)
	Players.PlayerRemoving:Connect(function(player)
		TeamService.Leave(player)
		buckets[player] = nil
		positionOf[player] = nil
	end)

	Remotes.get("JoinTeam").OnServerEvent:Connect(function(player, pref)
		local b = buckets[player]
		if not b or not b:take() or type(pref) ~= "string" then
			return
		end
		local ok, msg = TeamService.Join(player, pref)
		Remotes.get("Notify"):FireClient(player, ok and "good" or "bad", msg)
	end)
	Remotes.get("SetRole").OnServerEvent:Connect(function(player, role)
		local b = buckets[player]
		if not b or not b:take() or (role ~= "GK" and role ~= "FIELD") then
			return
		end
		local ok, msg = TeamService.SetRole(player, role)
		Remotes.get("Notify"):FireClient(player, ok and "good" or "bad", ok and ("Role: " .. role) or msg)
	end)
	Remotes.get("AssignPosition").OnServerEvent:Connect(function(player, slotId)
		local b = buckets[player]
		if not b or not b:take() or type(slotId) ~= "string" then
			return
		end
		local ok, msg = TeamService.AssignPosition(player, slotId)
		Remotes.get("Notify"):FireClient(player, ok and "good" or "bad", ok and ("Position: " .. msg) or msg)
	end)
end

return TeamService
