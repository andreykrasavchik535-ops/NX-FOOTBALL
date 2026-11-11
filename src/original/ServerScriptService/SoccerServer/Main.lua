--[[
	ServerScriptService/SoccerServer/Main (Script)
	Boots the game in dependency order and drives the per-frame loops.
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

-- The state folder is created first so clients (HUD, buttons) never wait for it, even if a later system fails.
if not ReplicatedStorage:FindFirstChild("SoccerState") then
	local f = Instance.new("Folder")
	f.Name = "SoccerState"
	f.Parent = ReplicatedStorage
end

-- We ship our own shift lock (client ShiftLock module, works on phones); Roblox's built-in one would fight it.
pcall(function()
	game:GetService("StarterPlayer").EnableMouseLockOption = false
end)

-- Every system starts protected: one failing Init is reported in Output and must not stop the others.
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

-- One failing system must never freeze the others: every step runs protected, errors are reported once per second.
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
end)

print("[NX: Next Football] server started")
