--[[
	ServerScriptService/SoccerServer/FeintService (ModuleScript)

	Server side of the feint system. The client only sends "I want feint X on side S".
	The server checks that the ball is within reach, speed and stamina, then plays the feint by steering the
	(free, physical) ball through BallService.Drive (path phases) or BallService.Launch (one-off kick).

	NO COOLDOWNS: no per-feint timers and no global timer. Limits are stamina (the ball is optional: without it only the body move happens) and
	Config.FEINT_INTERRUPT_AT (0 = a new feint may replace the running one immediately).
	Also grants tackle immunity ("evade windows"), makes defenders "bite" (Fool) and detects combos.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Defs = require(Shared:WaitForChild("FeintDefs"))

local TeamService = require(script.Parent:WaitForChild("TeamService"))
local StaminaService = require(script.Parent:WaitForChild("StaminaService"))
local BallService = require(script.Parent:WaitForChild("BallService"))
local MatchService = require(script.Parent:WaitForChild("MatchService"))

local FeintService = {}

local runs = {}      -- [player] = active run
local history = {}   -- [player] = { {id=, startT=, endT=}, ... }
local buckets = {}
local BALL_R = Config.BALL_DIAMETER / 2

local function result(player, id, ok, reason)
	Remotes.get("ActionResult"):FireClient(player, "FEINT:" .. id, ok, reason or "", 0)
end

local function sample(keys, u)
	local n = #keys
	if u <= keys[1].t then
		return keys[1].f, keys[1].r, keys[1].u
	end
	for i = 2, n do
		local a, b = keys[i - 1], keys[i]
		if u <= b.t then
			local span = math.max(b.t - a.t, 1e-4)
			local x = (u - a.t) / span
			x = x * x * (3 - 2 * x) -- smoothstep between keys
			return a.f + (b.f - a.f) * x, a.r + (b.r - a.r) * x, a.u + (b.u - a.u) * x
		end
	end
	local last = keys[n]
	return last.f, last.r, last.u
end

local function nearestOpponentDir(player, hrp, fwd)
	local myTeam = TeamService.GetTeam(player)
	local bestDir, bestD
	for _, opp in ipairs(TeamService.AllPlayers()) do
		if TeamService.GetTeam(opp) ~= myTeam then
			local _, _, ohrp = Util.getCharParts(opp)
			if ohrp then
				local to = Vector3.new(ohrp.Position.X - hrp.Position.X, 0, ohrp.Position.Z - hrp.Position.Z)
				local d = to.Magnitude
				if d > 1 and d <= 18 and to.Unit:Dot(fwd) > 0.5 and (not bestD or d < bestD) then
					bestDir, bestD = to.Unit, d
				end
			end
		end
	end
	return bestDir
end

-- Defenders in front of a fake "bite": slowed for a moment.
local function applyFool(player, def, hrp, fwd)
	local fool = def.Fool
	if not fool or not Config.FEINT_FOOL_ENABLED then
		return
	end
	local myTeam = TeamService.GetTeam(player)
	for _, opp in ipairs(TeamService.AllPlayers()) do
		if TeamService.GetTeam(opp) ~= myTeam then
			local _, _, ohrp = Util.getCharParts(opp)
			if ohrp then
				local to = Vector3.new(ohrp.Position.X - hrp.Position.X, 0, ohrp.Position.Z - hrp.Position.Z)
				local d = to.Magnitude
				if d > 0.1 and d <= fool.radius and to.Unit:Dot(fwd) > 0.2 then
					StaminaService.Slow(opp, fool.factor, fool.seconds)
				end
			end
		end
	end
end

local function checkCombo(player, run)
	local h = history[player]
	for _, combo in ipairs(Defs.Combos) do
		local seq = combo.Sequence
		local n = #seq
		if #h >= n then
			local match = true
			for i = 1, n do
				if h[#h - n + i].id ~= seq[i] then
					match = false
					break
				end
			end
			if match then
				-- every step must follow the previous one within the combo window
				for i = #h - n + 2, #h do
					if h[i].startT - h[i - 1].endT > Config.COMBO_WINDOW then
						match = false
						break
					end
				end
			end
			if match then
				local r = combo.Reward
				StaminaService.Add(player, (r.staminaRefund or 0) * Defs.ById[seq[n]].Stamina)
				run.evadeTo = run.evadeTo + (r.evadeBonus or 0)
				Remotes.get("ComboHit"):FireClient(player, combo.Name)
				history[player] = {}
				return
			end
		end
	end
end

local function endRun(player)
	if runs[player] then
		runs[player] = nil
		BallService.EndDrive(player)
	end
end

local function request(player, id, side, aim)
	local b = buckets[player]
	if not b or not b:take() or type(id) ~= "string" then
		return
	end
	local def = Defs.ById[id]
	if not def then
		return
	end
	side = (side == -1) and -1 or 1
	local now = os.clock()
	if not history[player] then
		return
	end

	if not MatchService.CanPlay() then
		return result(player, id, false, "not live")
	end
	if BallService.GetHolder() == player then
		return result(player, id, false, "holding")
	end
	-- A feint works with or without the ball. With the ball within reach it also moves the ball; without it,
	-- it is only the body move (animation, spin/burst on the client), the evade window and the "fool" effect.
	local withBall = BallService.CanControl(player, Config.FEINT_REACH, Config.FEINT_MAX_HEIGHT)
	local active = runs[player]
	if active and Config.FEINT_INTERRUPT_AT > 0 and now < active.t0 + active.def.Duration * Config.FEINT_INTERRUPT_AT then
		return result(player, id, false, "busy")
	end
	local _, _, hrp = Util.getCharParts(player)
	if not hrp then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local hv = Vector3.new(v.X, 0, v.Z)
	local speed = hv.Magnitude
	if speed < (def.MinSpeed or 0) then
		return result(player, id, false, "need speed")
	end
	if def.MaxSpeed and speed > def.MaxSpeed then
		return result(player, id, false, "too fast")
	end
	if not StaminaService.Spend(player, def.Stamina) then
		return result(player, id, false, "stamina")
	end

	local fwd
	if speed > 3 then
		fwd = hv.Unit
	elseif Util.isFiniteVec(aim) and Vector3.new(aim.X, 0, aim.Z).Magnitude > 0.1 then
		fwd = Vector3.new(aim.X, 0, aim.Z).Unit
	else
		fwd = Util.flatUnit(hrp.CFrame.LookVector)
	end
	if def.AimOpponent then
		fwd = nearestOpponentDir(player, hrp, fwd) or fwd
	end
	local right = fwd:Cross(Vector3.new(0, 1, 0))

	if active then
		endRun(player)
	end
	local run = {
		def = def, side = side, t0 = now, fwd = fwd, right = right,
		phase = 1, phaseT0 = now, launched = 0, evadeTo = def.Evade[2], driveDone = not withBall,
	}
	runs[player] = run
	local h = history[player]
	table.insert(h, { id = id, startT = now, endT = now + def.Duration })
	while #h > 6 do
		table.remove(h, 1)
	end
	checkCombo(player, run)
	applyFool(player, def, hrp, fwd)

	Remotes.get("FeintApproved"):FireAllClients(player.UserId, id, side, fwd, def.Duration)
	result(player, id, true, "")
end

-- Called every Heartbeat (after BallService.Step): steers the ball for every running feint.
function FeintService.Tick(dt, now)
	now = now or os.clock()
	for player, run in pairs(runs) do
		local def = run.def
		local _, hum, hrp = Util.getCharParts(player)
		local elapsed = now - run.t0
		if not hrp or not player.Parent or not MatchService.CanPlay() or elapsed > math.max(def.Duration, run.evadeTo) + 0.25 then
			endRun(player)
		elseif not run.driveDone then
			local ph = def.Phases[run.phase]
			local pt = now - run.phaseT0
			while ph and pt >= ph.dur do
				run.phaseT0 = run.phaseT0 + ph.dur
				run.phase = run.phase + 1
				ph = def.Phases[run.phase]
				pt = now - run.phaseT0
			end
			if not ph then
				run.driveDone = true
				BallService.EndDrive(player)
			else
				local sgn = def.NoMirror and 1 or run.side
				if ph.kind == "path" then
					local f, r, u = sample(ph.keys, math.clamp(pt / ph.dur, 0, 1))
					local base = hrp.Position
					local ground = Util.groundY(hum, hrp)
					local target = Vector3.new(base.X, ground + BALL_R + u, base.Z) + run.fwd * f + run.right * (r * sgn)
					if not BallService.Drive(player, target, dt, u > 0.05) then
						run.driveDone = true -- ball lost / taken: the move is over, the evade window still runs out
					end
				elseif ph.kind == "launch" and run.launched ~= run.phase then
					run.launched = run.phase
					local carry = (ph.carry or 0) * Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
					local vel = run.fwd * ph.vf + run.right * (ph.vr * sgn) + Vector3.new(0, ph.vu, 0) + carry
					BallService.Launch(player, vel, { ghost = ph.ghost })
				end
			end
		end
	end
end

function FeintService.IsEvading(player, now)
	local run = runs[player]
	if not run then
		return false
	end
	local t = (now or os.clock()) - run.t0
	return t >= run.def.Evade[1] and t <= run.evadeTo
end

function FeintService.Cancel(player)
	endRun(player)
end

function FeintService.Reset()
	for p in pairs(runs) do
		BallService.EndDrive(p)
	end
	runs = {}
	for p in pairs(history) do
		history[p] = {}
	end
end

function FeintService.Init()
	Remotes.get("Feint").OnServerEvent:Connect(request)
	local function add(p)
		history[p] = {}
		buckets[p] = Util.newBucket(Config.RATE_FEINT.rate, Config.RATE_FEINT.burst)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		add(p)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(function(p)
		endRun(p)
		history[p], buckets[p] = nil, nil
	end)
end

return FeintService
