--[[
	ServerScriptService/SoccerServer/MatchService (ModuleScript)
	Match flow: Waiting -> Intermission -> Kickoff -> Live (half 1) -> HalfTime -> Kickoff -> Live (half 2) -> Finished.
	Handles score, clock, kickoffs, set pieces (throw-in / corner / goal kick), spawning into formation, stats.
	Public state is mirrored as attributes on ReplicatedStorage.SoccerState for the HUD.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Field = require(script.Parent:WaitForChild("FieldService"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))
local BallService = require(script.Parent:WaitForChild("BallService"))
local StaminaService = require(script.Parent:WaitForChild("StaminaService"))
local Rules = require(script.Parent:WaitForChild("RulesService"))

local MatchService = {}
MatchService.OnReset = nil -- function() called at every kickoff (Main wires FeintService.Reset here)

local R = Config.BALL_DIAMETER / 2
local stateFolder
local state, half, clock = "Waiting", 1, 0
local score = { RED = 0, BLUE = 0 }
local events = {}
local stats = {}
local slotLocal = {}
local firstKickoff = "RED"

-- State publishing --------------------------------------------------------------------------------------

local function setAttr(name, value)
	if stateFolder:GetAttribute(name) ~= value then
		stateFolder:SetAttribute(name, value)
	end
end

local function setState(newState, message)
	state = newState
	setAttr("State", newState)
	setAttr("Message", message or "")
end

local function publishScore()
	setAttr("RedScore", score.RED)
	setAttr("BlueScore", score.BLUE)
	setAttr("Half", half)
end

local function publishClock()
	setAttr("Clock", math.ceil(clock))
end

function MatchService.CanPlay()
	return state == "Live"
end

function MatchService.GetState()
	return state
end

function MatchService.AddStat(player, key, n)
	local s = stats[player]
	if not s then
		s = { Goals = 0, Assists = 0, Saves = 0, Tackles = 0 }
		stats[player] = s
	end
	s[key] = (s[key] or 0) + (n or 1)
end

local function enoughPlayers()
	local r, b = TeamService.Count("RED"), TeamService.Count("BLUE")
	if Config.TEST_MODE then
		return r + b >= Config.MIN_PLAYERS_TO_START
	end
	return r >= 1 and b >= 1 and r + b >= Config.MIN_PLAYERS_TO_START
end

-- Placement -----------------------------------------------------------------------------------------------

local function teleportLocal(player, x, z, faceLocal)
	local char, hum, hrp = Util.getCharParts(player)
	if not hrp then
		return false
	end
	local f = Field.Get()
	local p = Field.ToWorld(Vector3.new(x, 0, z))
	local pos = Vector3.new(p.X, f.ground + Util.hipOffset(hum, hrp) + 0.25, p.Z)
	local look = Field.DirToWorld(faceLocal)
	char:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)))
	hrp.AssemblyLinearVelocity = Vector3.zero
	StaminaService.NoteTeleport(player)
	return true
end

local function layout(m)
	if m <= 0 then
		return {}
	end
	local rowCount = (m <= 2) and 1 or ((m <= 6) and 2 or 3)
	local zs = ({ { 0.6 }, { 0.42, 0.74 }, { 0.3, 0.55, 0.78 } })[rowCount]
	local rows, left = {}, m
	for i = 1, rowCount do
		local n = math.ceil(left / (rowCount - i + 1))
		rows[i] = n
		left = left - n
	end
	local slots = {}
	for i = 1, rowCount do
		for k = 1, rows[i] do
			table.insert(slots, { x = ((k - 0.5) / rows[i] - 0.5) * 1.5, zf = zs[i] })
		end
	end
	return slots
end

local function placeSlot(p, x, z, face)
	slotLocal[p] = { x = x, z = z, face = face }
	teleportLocal(p, x, z, Vector3.new(0, 0, face))
end

local function placeAll(kickoffTeam)
	local f = Field.Get()
	for _, team in ipairs({ "RED", "BLUE" }) do
		local sign = TeamService.GetDefendSign(team)
		local face = -sign
		local gk, outfield = nil, {}
		for _, p in ipairs(TeamService.GetMembers(team)) do
			if TeamService.GetRole(p) == "GK" and not gk then
				gk = p
			else
				table.insert(outfield, p)
			end
		end
		if gk then
			placeSlot(gk, 0, sign * (f.halfL - 7), face)
		end
		local slots = layout(#outfield)
		for i, p in ipairs(outfield) do
			local s = slots[i]
			local x = s.x * f.halfW
			local z = sign * f.halfL * (1 - math.min(s.zf, 0.78))
			if team == kickoffTeam and i == #outfield then
				x, z = 0, sign * 4
			end
			placeSlot(p, x, z, face)
		end
	end
end

local function placeLate(player)
	local team = TeamService.GetTeam(player)
	if not team then
		return
	end
	local f = Field.Get()
	local sign = TeamService.GetDefendSign(team)
	local x = (math.random() - 0.5) * f.halfW
	local z = sign * f.halfL * 0.55
	teleportLocal(player, x, z, Vector3.new(0, 0, -sign))
end

local function center()
	return Field.ToWorld(Vector3.new(0, R + 0.1, 0))
end

-- Phases -----------------------------------------------------------------------------------------------------

-- Returns false if abortFn() became true.
local function countdown(seconds, abortFn)
	local untilT = os.clock() + seconds
	while true do
		local remaining = untilT - os.clock()
		if remaining <= 0 then
			break
		end
		setAttr("Countdown", math.ceil(remaining))
		if abortFn and abortFn() then
			setAttr("Countdown", 0)
			return false
		end
		task.wait(0.1)
	end
	setAttr("Countdown", 0)
	return true
end

local function doKickoff(team, seconds)
	Rules.SetActive(false)
	BallService.SetEnabled(false)
	BallService.ClearRestart()
	BallService.ClearHistory()
	StaminaService.SetFrozen(true)
	setState("Kickoff", team .. " kickoff")
	placeAll(team)
	BallService.PlaceAt(center(), seconds + 0.3)
	if MatchService.OnReset then
		MatchService.OnReset()
	end
	countdown(seconds, nil)
	StaminaService.SetFrozen(false)
	BallService.SetEnabled(true)
	BallService.SetRestart(team, Config.KICKOFF_EXCLUSIVE)
	Rules.SetActive(true)
	setState("Live", "")
end

local function nearestToSpot(team, worldSpot, preferGK)
	local best, bestD
	for _, p in ipairs(TeamService.GetMembers(team)) do
		local _, _, hrp = Util.getCharParts(p)
		if hrp then
			local d = (hrp.Position - worldSpot).Magnitude
			if preferGK and TeamService.GetRole(p) == "GK" then
				d = d - 1000
			end
			if not bestD or d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

local function handleOut(ev)
	BallService.ClearRestart()
	BallService.PlaceAt(ev.spot, Config.RESTART_FREEZE)
	BallService.SetRestart(ev.team, Config.RESTART_FREEZE + Config.RESTART_EXCLUSIVE)
	local taker = nearestToSpot(ev.team, ev.spot, ev.restart == "Goal kick")
	if taker then
		local lp = Field.ToLocal(ev.spot)
		local toCenter = Vector3.new(-lp.X, 0, -lp.Z)
		toCenter = toCenter.Magnitude > 0.1 and toCenter.Unit or Vector3.new(0, 0, 1)
		local pos = lp + toCenter * 4
		teleportLocal(taker, pos.X, pos.Z, -toCenter)
	end
	Remotes.get("Notify"):FireAllClients("info", tostring(ev.restart) .. " - " .. ev.team)
	Rules.SetActive(true)
end

local function handleGoal(ev)
	score[ev.scoring] = score[ev.scoring] + 1
	publishScore()
	if ev.scorer and not ev.own then
		MatchService.AddStat(ev.scorer, "Goals", 1)
	end
	if ev.assister then
		MatchService.AddStat(ev.assister, "Assists", 1)
	end
	Remotes.get("GoalScored"):FireAllClients(
		ev.scoring,
		ev.scorer and ev.scorer.DisplayName or "",
		ev.assister and ev.assister.DisplayName or "",
		score.RED, score.BLUE, ev.own and true or false
	)
	setState("GoalPause", ev.scoring .. " scores!")
	BallService.SetEnabled(false)
	Rules.SetActive(false)
	countdown(Config.GOAL_PAUSE_SECONDS, nil)
	if clock > 0 then
		doKickoff(TeamService.Other(ev.scoring), Config.KICKOFF_SECONDS)
	end
end

-- Goal/out callbacks are queued and consumed by the match loop (single owner of state changes).
function MatchService.HandleGoal(scoring, scorer, assister, own)
	if state == "Live" then
		BallService.SetEnabled(false) -- dead ball immediately (nobody can kick it out of the net)
		table.insert(events, { kind = "goal", scoring = scoring, scorer = scorer, assister = assister, own = own })
	end
end

function MatchService.HandleOut(kind, team, spot)
	if state == "Live" then
		table.insert(events, { kind = "out", restart = kind, team = team, spot = spot })
	end
end

local function playHalf()
	local last = os.clock()
	local emptyFor = 0
	while clock > 0 do
		task.wait(0.1)
		local now = os.clock()
		local dt = now - last
		last = now
		if not enoughPlayers() then
			emptyFor = emptyFor + dt
			if emptyFor > Config.ABANDON_AFTER_SECONDS then
				return "abort"
			end
		else
			emptyFor = 0
		end
		local ev = table.remove(events, 1)
		if ev then
			if ev.kind == "goal" then
				handleGoal(ev)
			else
				handleOut(ev)
			end
			last = os.clock()
		elseif state == "Live" and enoughPlayers() then
			clock = math.max(0, clock - dt)
		end
		publishClock()
	end
	return "end"
end

local function resetAll()
	score.RED, score.BLUE = 0, 0
	half = 1
	events = {}
	stats = {}
	clock = Config.HALF_SECONDS
	setAttr("Winner", "")
	publishScore()
	publishClock()
	Rules.SetActive(false)
	BallService.SetEnabled(false)
	BallService.ClearRestart()
	BallService.ClearHistory()
	StaminaService.SetFrozen(false)
	StaminaService.ResetAll()
	BallService.PlaceAt(center(), 1e6)
	TeamService.SetDefendSign("RED", -1)
	TeamService.SetDefendSign("BLUE", 1)
end

local function finishMatch()
	Rules.SetActive(false)
	BallService.SetEnabled(false)
	StaminaService.SetFrozen(false)
	local winner = score.RED > score.BLUE and "RED" or (score.BLUE > score.RED and "BLUE" or "DRAW")
	setAttr("Winner", winner)
	setState("Finished", winner == "DRAW" and "Draw" or (winner .. " wins"))
	local list = {}
	for p, s in pairs(stats) do
		if p.Parent then
			table.insert(list, { name = p.DisplayName, team = TeamService.GetTeam(p) or "", goals = s.Goals, assists = s.Assists, saves = s.Saves, tackles = s.Tackles })
		end
	end
	table.sort(list, function(a, b)
		return (a.goals * 3 + a.assists * 2 + a.saves + a.tackles) > (b.goals * 3 + b.assists * 2 + b.saves + b.tackles)
	end)
	Remotes.get("MatchEnded"):FireAllClients(winner, score.RED, score.BLUE, list)
	countdown(Config.FINISHED_SECONDS, nil)
end

local function playMatch()
	setState("Waiting", "Waiting for players")
	resetAll()
	while not enoughPlayers() do
		task.wait(0.5)
	end
	setState("Intermission", "Match starting soon")
	if not countdown(Config.INTERMISSION_SECONDS, function() return not enoughPlayers() end) then
		return
	end
	resetAll()
	firstKickoff = math.random() < 0.5 and "RED" or "BLUE"
	doKickoff(firstKickoff, Config.KICKOFF_SECONDS + 1)
	if playHalf() == "abort" then
		return
	end
	-- half time
	Rules.SetActive(false)
	BallService.SetEnabled(false)
	setState("HalfTime", "Half time")
	countdown(Config.HALFTIME_SECONDS, nil)
	TeamService.SwapSides()
	events = {}
	half = 2
	clock = Config.HALF_SECONDS
	publishScore()
	publishClock()
	doKickoff(TeamService.Other(firstKickoff), Config.KICKOFF_SECONDS)
	if playHalf() == "abort" then
		return
	end
	finishMatch()
end

function MatchService.Init()
	stateFolder = ReplicatedStorage:FindFirstChild("SoccerState")
	if not stateFolder then
		stateFolder = Instance.new("Folder")
		stateFolder.Name = "SoccerState"
		stateFolder.Parent = ReplicatedStorage
	end
	setAttr("HalfSeconds", Config.HALF_SECONDS)
	setAttr("TeamSize", Config.TEAM_SIZE)
	setAttr("Countdown", 0)
	setAttr("Clock", Config.HALF_SECONDS)
	setAttr("TestMode", Config.TEST_MODE)
	publishScore()

	Rules.OnGoal = MatchService.HandleGoal
	Rules.OnOut = MatchService.HandleOut

	BallService.OnSteal = function(thief, victim, reason)
		if reason ~= "intercept" then
			return
		end
		MatchService.AddStat(thief, "Tackles", 1)
		Remotes.get("Notify"):FireClient(thief, "good", "Intercepted!")
		Remotes.get("Notify"):FireClient(victim, "bad", "Ball lost")
	end

	local function onCharacter(player)
		task.wait(0.35)
		if not TeamService.GetTeam(player) then
			return
		end
		local s = slotLocal[player]
		if s and state ~= "Waiting" and state ~= "Intermission" then
			teleportLocal(player, s.x, s.z, Vector3.new(0, 0, s.face))
		else
			placeLate(player)
		end
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		if player.Character then
			task.spawn(onCharacter, player)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		slotLocal[p] = nil
		stats[p] = nil
	end)
	TeamService.Changed:Connect(function(player, team)
		slotLocal[player] = nil
		if team and player.Character then
			task.delay(0.2, placeLate, player)
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(playMatch)
			if not ok then
				warn("[Soccer] match loop error: " .. tostring(err))
				task.wait(2)
			end
			task.wait(0.5)
		end
	end)
end

return MatchService
