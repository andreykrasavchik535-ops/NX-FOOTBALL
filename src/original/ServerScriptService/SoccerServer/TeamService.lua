--[[
	ServerScriptService/SoccerServer/TeamService (ModuleScript)
	RED (shown as AWAY) / BLUE (shown as HOME) teams, player choice (no auto team), balance rule, goalkeeper role, which end each team defends.
]]
local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TeamService = {}

local teamObjs = {}
local members = { RED = {}, BLUE = {} } -- set: [player] = true
local teamOf = {}                      -- [player] = "RED" / "BLUE"
local roleOf = {}                      -- [player] = "FIELD" / "GK"
local defendSign = { RED = -1, BLUE = 1 } -- which goal line (local Z sign) each team defends
local buckets = {}

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
end

local function removeFromTeam(player)
	local name = teamOf[player]
	if name then
		members[name][player] = nil
		teamOf[player] = nil
	end
	roleOf[player] = nil
	player.Team = nil
	player.Neutral = true
	applyAttributes(player)
end

-- The player CHOOSES a team (no automatic distribution). pref: "RED" | "BLUE".
-- Rules: a team can not be joined when it is full, or when it already has Config.TEAM_MAX_LEAD (2) more players than
-- the other team (Config.AUTO_BALANCE = false switches the second rule off).
function TeamService.Join(player, pref)
	if pref ~= "RED" and pref ~= "BLUE" then
		return false, "Choose a team"
	end
	local current = teamOf[player]
	if current == pref then
		return true, "Already in team"
	end
	local counts = { RED = count("RED"), BLUE = count("BLUE") }
	if current then
		counts[current] = counts[current] - 1 -- he leaves his old team when he moves
	end
	local target = pref
	if counts[target] >= Config.TEAM_SIZE then
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
	player.Team = teamObjs[target]
	player.Neutral = false
	applyAttributes(player)
	changed:Fire(player, target)
	return true, "Joined " .. (target == "RED" and "AWAY" or "HOME")
end

function TeamService.Leave(player)
	if teamOf[player] then
		removeFromTeam(player)
		changed:Fire(player, nil)
	end
end

function TeamService.SetRole(player, role)
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
	else
		roleOf[player] = "FIELD"
	end
	applyAttributes(player)
	changed:Fire(player, name)
	return true, role
end

function TeamService.GetTeam(player)
	return teamOf[player]
end

function TeamService.GetRole(player)
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
		-- no automatic team: the player picks one on the CHOOSE A TEAM screen
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onAdded(p)
	end
	Players.PlayerAdded:Connect(onAdded)
	Players.PlayerRemoving:Connect(function(player)
		TeamService.Leave(player)
		buckets[player] = nil
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
end

return TeamService
