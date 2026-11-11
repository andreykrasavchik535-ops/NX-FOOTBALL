--[[
	ServerScriptService/SoccerServer/Main (Script)
	Boots the game in dependency order and drives the per-frame loops.
	NX26 adds: MatchControlService (menu/host/setup), SettingsService, LobbyService, SoundRunner,
	and the AI goalkeeper step. The stadium and the core physics are unchanged.
]]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
require(Shared:WaitForChild("Remotes")) -- creates the RemoteEvents first

local S = script.Parent
local FieldService = require(S:WaitForChild("FieldService"))
local TeamService = require(S:WaitForChild("TeamService"))
local StaminaService = require(S:WaitForChild("StaminaService"))
local BallService = require(S:WaitForChild("BallService"))
local RulesService = require(S:WaitForChild("RulesService"))
local MatchService = require(S:WaitForChild("MatchService"))
local GoalkeeperService = require(S:WaitForChild("GoalkeeperService"))
local FeintService = require(S:WaitForChild("FeintService"))
local ActionService = require(S:WaitForChild("ActionService"))
local MatchControlService = require(S:WaitForChild("MatchControlService"))
local SettingsService = require(S:WaitForChild("SettingsService"))
local LobbyService = require(S:WaitForChild("LobbyService"))
local SoundRunner = require(S:WaitForChild("SoundRunner"))

if not ReplicatedStorage:FindFirstChild("SoccerState") then
	local f = Instance.new("Folder")
	f.Name = "SoccerState"
	f.Parent = ReplicatedStorage
end

pcall(function()
	game:GetService("StarterPlayer").EnableMouseLockOption = false
end)

local function start(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[NX] " .. name .. " failed to start: " .. tostring(err))
	end
	return ok
end

start("FieldService.Init", FieldService.Init)
start("TeamService.Init", TeamService.Init)
start("StaminaService.Init", StaminaService.Init)
start("BallService.Init", BallService.Init)
start("BallService.Configure", BallService.Configure, {
	roster = TeamService.AllPlayers,
	getTeam = TeamService.GetTeam,
	feint = FeintService,
	gk = GoalkeeperService,
})
start("GoalkeeperService.Init", GoalkeeperService.Init)
start("FeintService.Init", FeintService.Init)
start("ActionService.Init", ActionService.Init)
MatchService.OnReset = FeintService.Reset
start("MatchService.Init", MatchService.Init)
start("MatchControlService.Init", MatchControlService.Init)
start("SettingsService.Init", SettingsService.Init)
start("LobbyService.Init", LobbyService.Init)
start("SoundRunner.Init", SoundRunner.Init)

local lastWarn = {}
local function safe(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local now = os.clock()
		if now - (lastWarn[name] or 0) > 1 then
			lastWarn[name] = now
			warn("[NX] " .. name .. " error: " .. tostring(err))
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	safe("BallService.Step", BallService.Step, dt)
	safe("RulesService.Step", RulesService.Step)
	safe("FeintService.Tick", FeintService.Tick, dt, os.clock())
	safe("GoalkeeperService.Step", GoalkeeperService.Step, dt)
end)

print("[NX: Next Football] server started (menu-driven, AI keepers enabled)")
