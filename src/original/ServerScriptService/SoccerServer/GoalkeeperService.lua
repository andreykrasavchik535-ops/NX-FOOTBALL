--[[
	ServerScriptService/SoccerServer/GoalkeeperService (ModuleScript)
	Goalkeeper role: hands in the own penalty area (catch / parry), dive, hold-and-release.
	BallService asks this module for catch parameters through Params().
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Field = require(script.Parent:WaitForChild("FieldService"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))
local StaminaService = require(script.Parent:WaitForChild("StaminaService"))
local BallService = require(script.Parent:WaitForChild("BallService"))
local MatchService = require(script.Parent:WaitForChild("MatchService"))

local GK = {}
local diveUntil, diveCd, buckets = {}, {}, {}

function GK.IsGK(player)
	return TeamService.GetTeam(player) ~= nil and TeamService.GetRole(player) == "GK"
end

-- Is worldPos inside this player's own penalty area (their defended end)?
function GK.InOwnBox(player, worldPos)
	local team = TeamService.GetTeam(player)
	if not team then
		return false
	end
	local sign = TeamService.GetDefendSign(team)
	local f = Field.Get()
	local lp = Field.ToLocal(worldPos)
	local depthFromLine = f.halfL - sign * lp.Z -- distance in front of own goal line
	return depthFromLine >= -f.goalDepth and depthFromLine <= f.penaltyDepth + 0.5 and math.abs(lp.X) <= f.penaltyHalfW
end

-- Used by BallService when evaluating a pickup. Returns nil for non-keepers / outside the box.
function GK.Params(player, ballPos, now)
	if not GK.IsGK(player) or not GK.InOwnBox(player, ballPos) then
		return nil
	end
	local diving = diveUntil[player] and now < diveUntil[player]
	return {
		radius = Config.GK_CATCH_RADIUS * (diving and Config.GK_DIVE_RADIUS_MULT or 1),
		maxHeight = Config.GK_CATCH_HEIGHT,
		maxSpeed = Config.GK_CATCH_MAX_SPEED * (diving and 1.25 or 1),
		canParry = true,
	}
end

local function countSave(player, now)
	local shooter, untilT = BallService.GetShot()
	if shooter and now < untilT and TeamService.GetTeam(shooter) ~= TeamService.GetTeam(player) then
		MatchService.AddStat(player, "Saves", 1)
		Remotes.get("Notify"):FireClient(player, "good", "Save!")
	end
end

function GK.OnCatch(player, now)
	countSave(player, now)
	Remotes.get("CatchPlayed"):FireAllClients(player.UserId)
	Remotes.get("Notify"):FireClient(player, "info", "Ball caught - PASS / LONG / SHOOT to release (" .. Config.GK_HOLD_TIME .. "s)")
end

function GK.OnParry(player, now)
	countSave(player, now)
end

local function onDive(player, side)
	local b = buckets[player]
	if not b or not b:take() then
		return
	end
	if not Util.isNum(side, -1, 1) then
		return
	end
	side = side < -0.3 and -1 or (side > 0.3 and 1 or 0)
	local now = os.clock()
	if not GK.IsGK(player) or not MatchService.CanPlay() then
		return
	end
	local _, _, hrp = Util.getCharParts(player)
	if not hrp or now < (diveCd[player] or 0) then
		return
	end
	if not StaminaService.Spend(player, Config.GK_DIVE_STAMINA) then
		Remotes.get("ActionResult"):FireClient(player, "GKDIVE", false, "stamina", 0)
		return
	end
	diveCd[player] = now + Config.GK_DIVE_COOLDOWN
	diveUntil[player] = now + Config.GK_DIVE_DURATION
	Remotes.get("DiveApproved"):FireAllClients(player.UserId, side)
	Remotes.get("ActionResult"):FireClient(player, "GKDIVE", true, "", Config.GK_DIVE_COOLDOWN)
end

function GK.Init()
	Remotes.get("GKDive").OnServerEvent:Connect(onDive)
	local function add(p)
		buckets[p] = Util.newBucket(Config.RATE_ACTION.rate, Config.RATE_ACTION.burst)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		add(p)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p], diveUntil[p], diveCd[p] = nil, nil, nil
	end)
end

return GK
