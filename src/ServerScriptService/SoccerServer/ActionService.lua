--[[
	ServerScriptService/SoccerServer/ActionService (ModuleScript)
	Shoot / Pass / Long (hold to charge) and Tackles. The client sends intents only:
	  ActionStart(action)            - begins server-timed charge
	  ActionRelease(action, aimVec)  - strike; power comes from SERVER time, aim is validated and clamped
	  Tackle(kind, aimVec)           - Fast / Slide
	Everything is checked here: match state, possession (or loose-ball reach), cooldown, stamina, rate limit.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TeamService = require(script.Parent:WaitForChild("TeamService"))
local StaminaService = require(script.Parent:WaitForChild("StaminaService"))
local BallService = require(script.Parent:WaitForChild("BallService"))
local MatchService = require(script.Parent:WaitForChild("MatchService"))
local FeintService = require(script.Parent:WaitForChild("FeintService"))

local ActionService = {}

local KICK_ACTIONS = { SHOOT = true, PASS = true, LONG = true }
local charges = {}   -- [player] = { action=, t0= }
local cds = {}       -- [player] = { [key] = readyAt }
local buckets = {}
local tackles = {}   -- [player] = active tackle state

local function notify(player, kind, text)
	Remotes.get("Notify"):FireClient(player, kind, text)
end

local function result(player, key, ok, reason, cooldown)
	Remotes.get("ActionResult"):FireClient(player, key, ok, reason or "", cooldown or 0)
end

-- Clamp the requested aim to within MAX_AIM_ANGLE of where the body faces.
local function resolveDirection(hrp, aim)
	local facing = Util.flatUnit(hrp.CFrame.LookVector)
	if not Util.isFiniteVec(aim) then
		return facing
	end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 0.1 then
		return facing
	end
	flat = flat.Unit
	local ang = Util.signedAngle(facing, flat)
	local maxA = math.rad(Config.MAX_AIM_ANGLE)
	if math.abs(ang) > maxA then
		return Util.rotateY(facing, maxA * (ang > 0 and 1 or -1))
	end
	return flat
end

local function findPassTarget(player, origin, dir)
	local myTeam = TeamService.GetTeam(player)
	local best, bestAng, bestDist
	local maxAng = math.rad(Config.PASS_ASSIST_ANGLE)
	for _, mate in ipairs(TeamService.GetMembers(myTeam)) do
		if mate ~= player then
			local _, _, hrp = Util.getCharParts(mate)
			if hrp then
				local to = Vector3.new(hrp.Position.X - origin.X, 0, hrp.Position.Z - origin.Z)
				local d = to.Magnitude
				if d > 6 and d <= Config.PASS_RANGE then
					local ang = math.acos(math.clamp(dir:Dot(to.Unit), -1, 1))
					if ang <= maxAng and (not bestAng or ang < bestAng) then
						best, bestAng, bestDist = hrp, ang, d
					end
				end
			end
		end
	end
	return best, bestDist
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function executeKick(player, action, aim, chargeFrac, style, side)
	local now = os.clock()
	local c = cds[player]
	if not c then
		return
	end
	if now < (c[action] or 0) then
		return result(player, action, false, "cooldown", (c[action] or 0) - now)
	end
	if not MatchService.CanPlay() then
		return result(player, action, false, "not live", 0)
	end
	local _, _, hrp = Util.getCharParts(player)
	if not hrp then
		return
	end
	if not BallService.CanReach(player) and BallService.GetHolder() ~= player then
		return result(player, action, false, "no ball", 0)
	end
	local ball = BallService.GetBall()

	-- style: only known names are accepted, everything else falls back to the normal kick
	if action == "SHOOT" then
		if type(style) ~= "string" or not Config.SHOT_STYLES[style] then
			style = "Normal"
		end
	elseif action == "PASS" then
		if type(style) ~= "string" or not Config.PASS_STYLES[style] then
			style = "Normal"
		end
	else
		style = "Normal"
	end
	side = (side == -1) and -1 or 1
	local st = Config.SHOT_STYLES[style]
	if action == "SHOOT" and st.minHeight and ball.Position.Y < hrp.Position.Y + st.minHeight then
		return result(player, action, false, "too low", 0) -- a header needs the ball up high
	end

	local mult = (action == "SHOOT" and st.stamina) or 1
	local cost = Config.KICK_STAMINA[action] * mult * (0.5 + 0.5 * chargeFrac)
	if not StaminaService.Spend(player, cost) then
		return result(player, action, false, "stamina", 0)
	end

	local dir = resolveDirection(hrp, aim)
	local staminaFrac = StaminaService.Get(player) / Config.STAMINA_MAX
	local hSpeed, vSpeed
	local opts = { kind = action }

	if action == "SHOOT" then
		local sp = Config.SHOOT_SPEED
		hSpeed = (sp.min + (sp.max - sp.min) * chargeFrac) * st.speed
		local lift = (Config.SHOOT_LIFT.min + (Config.SHOOT_LIFT.max - Config.SHOOT_LIFT.min) * chargeFrac) * st.lift
		vSpeed = hSpeed * lift
		local spread = math.rad(Config.SHOOT_SPREAD_DEG) * st.spread * (1 - staminaFrac * 0.6) * (0.4 + 0.6 * chargeFrac)
		dir = Util.rotateY(dir, (math.random() * 2 - 1) * spread)
		opts.shot = true
		if style == "Header" then
			hSpeed = lerp(30, 72, chargeFrac)
			vSpeed = -2 -- headers go slightly downwards
		end
		if st.curve then
			opts.curve = {
				side = side * st.curve.dir, deg = st.curve.deg * (0.5 + 0.5 * chargeFrac), rate = st.curve.rate, dur = st.curve.dur,
			}
		end
	elseif action == "PASS" then
		local target, dist = findPassTarget(player, ball.Position, dir)
		local sp = Config.PASS_SPEED
		if style == "Lob" then
			-- a chip: ballistic arc that lands about at the teammate (or at a charge-based distance)
			local range = target and dist or lerp(25, 80, chargeFrac)
			if target then
				local to = Vector3.new(target.Position.X - ball.Position.X, 0, target.Position.Z - ball.Position.Z)
				local tv = target.AssemblyLinearVelocity
				local aimed = Util.flatUnit(to + Vector3.new(tv.X, 0, tv.Z) * 0.6, dir)
				dir = Util.flatUnit(dir * (1 - Config.PASS_ASSIST_STRENGTH) + aimed * Config.PASS_ASSIST_STRENGTH, dir)
			end
			local g = game:GetService("Workspace").Gravity * Config.BALL_GRAVITY_SCALE
			local ang = math.rad(Config.LOB_ANGLE_DEG)
			local v = math.sqrt(range * g / math.sin(2 * ang))
			v = math.clamp(v, 28, Config.LONG_SPEED.max)
			hSpeed, vSpeed = v * math.cos(ang), v * math.sin(ang)
		else
			local leadTime = (style == "Through") and 0.9 or 0.5
			if target then
				local to = Vector3.new(target.Position.X - ball.Position.X, 0, target.Position.Z - ball.Position.Z)
				local tv = target.AssemblyLinearVelocity
				local travel = dist / math.max(sp.min, 1)
				local lead = Vector3.new(tv.X, 0, tv.Z) * math.min(travel * leadTime, leadTime)
				local aimed = Util.flatUnit(to + lead, dir)
				dir = Util.flatUnit(dir * (1 - Config.PASS_ASSIST_STRENGTH) + aimed * Config.PASS_ASSIST_STRENGTH, dir)
				hSpeed = math.clamp(dist * Config.PASS_DIST_FACTOR, sp.min, sp.max) * (1 + 0.15 * chargeFrac)
			else
				hSpeed = sp.min + (sp.max - sp.min) * chargeFrac
			end
			if style == "Through" then
				hSpeed = math.min(hSpeed * 1.12, sp.max * 1.1)
			end
			vSpeed = 4
			if style == "Through" then
				vSpeed = 1.5 -- keeps along the ground
			end
		end
	else -- LONG
		local sp = Config.LONG_SPEED
		local speed = sp.min + (sp.max - sp.min) * chargeFrac
		local ang = math.rad(Config.LONG_ANGLE_DEG)
		hSpeed = speed * math.cos(ang)
		vSpeed = speed * math.sin(ang)
	end

	c[action] = now + Config.COOLDOWNS[action]
	FeintService.Cancel(player)
	BallService.Kick(player, dir, hSpeed, vSpeed, opts)
	Remotes.get("KickPlayed"):FireAllClients(player.UserId, action, chargeFrac, style)
	result(player, action, true, "", Config.COOLDOWNS[action])
end

local function onStart(player, action)
	local b = buckets[player]
	if not b or not b:take() or type(action) ~= "string" or not KICK_ACTIONS[action] then
		return
	end
	charges[player] = { action = action, t0 = os.clock() }
end

local function onRelease(player, action, aim, style, side)
	local b = buckets[player]
	if not b or not b:take() or type(action) ~= "string" or not KICK_ACTIONS[action] then
		return
	end
	local ch = charges[player]
	charges[player] = nil
	local frac = 0
	if ch and ch.action == action then
		frac = math.clamp((os.clock() - ch.t0) / Config.CHARGE_TIME, 0, 1)
	end
	executeKick(player, action, aim, frac, style, side)
end

-- Tackles ----------------------------------------------------------------------------------------------------------

local function onTackle(player, kind, aim)
	local b = buckets[player]
	if not b or not b:take() or type(kind) ~= "string" then
		return
	end
	local def = Config.TACKLES[kind]
	if not def then
		return
	end
	local key = "TACKLE:" .. kind
	local now = os.clock()
	local c = cds[player]
	if not c or tackles[player] then
		return
	end
	if now < (c[key] or 0) then
		return result(player, key, false, "cooldown", (c[key] or 0) - now)
	end
	if not MatchService.CanPlay() then
		return result(player, key, false, "not live", 0)
	end
	local _, _, hrp = Util.getCharParts(player)
	if not hrp then
		return
	end
	if BallService.GetController() == player or BallService.GetHolder() == player then
		return result(player, key, false, "you have the ball", 0)
	end
	if not StaminaService.Spend(player, def.stamina) then
		return result(player, key, false, "stamina", 0)
	end
	local dir = resolveDirection(hrp, aim)
	c[key] = now + def.cooldown
	tackles[player] = { def = def, kind = kind, t0 = now, dir = dir, hit = false }
	Remotes.get("TackleApproved"):FireAllClients(player.UserId, kind, dir)
	result(player, key, true, "", def.cooldown)
end

-- The opponent a tackle is aimed at: the one in control of the ball, otherwise the opponent closest to it.
local function findVictim(tackler)
	local myTeam = TeamService.GetTeam(tackler)
	local holder = BallService.GetHolder()
	local c = BallService.GetController()
	if c and c ~= tackler and c ~= holder and TeamService.GetTeam(c) ~= myTeam then
		return c
	end
	local ball = BallService.GetBall()
	if not ball then
		return nil
	end
	local bp = ball.Position
	local best, bestD
	for _, opp in ipairs(TeamService.AllPlayers()) do
		if opp ~= holder and TeamService.GetTeam(opp) ~= myTeam then
			local _, _, ohrp = Util.getCharParts(opp)
			if ohrp then
				local d = Vector3.new(ohrp.Position.X - bp.X, 0, ohrp.Position.Z - bp.Z).Magnitude
				if d <= Config.TACKLE_CHALLENGE_RADIUS and (not bestD or d < bestD) then
					best, bestD = opp, d
				end
			end
		end
	end
	return best
end

local function resolveTackle(tackler, victim, t, now)
	local def = t.def
	t.hit = true
	local _, _, vhrp = Util.getCharParts(victim)
	local _, _, thrp = Util.getCharParts(tackler)
	if not vhrp or not thrp then
		return
	end
	if FeintService.IsEvading(victim, now) then
		notify(tackler, "bad", "Dodged!")
		notify(victim, "good", "Dodged the tackle!")
		StaminaService.Slow(tackler, 0.4, def.recovery * 1.5)
		return
	end
	local chance = def.winChance
	local vv = vhrp.AssemblyLinearVelocity
	local vdir = Util.flatUnit(Vector3.new(vv.X, 0, vv.Z), vhrp.CFrame.LookVector)
	local toTackler = Util.flatUnit(Vector3.new(thrp.Position.X - vhrp.Position.X, 0, thrp.Position.Z - vhrp.Position.Z))
	if vdir:Dot(toTackler) < -0.2 then
		chance = chance + Config.TACKLE_BEHIND_BONUS
	end
	if math.random() < chance then
		MatchService.AddStat(tackler, "Tackles", 1)
		StaminaService.Slow(victim, 0.6, 0.4)
		FeintService.Cancel(victim)
		BallService.TackleBall(tackler, victim, def.clean, t.dir)
		if not def.clean then
			StaminaService.Slow(tackler, 0.55, def.recovery * 0.6)
		end
		notify(tackler, "good", "Tackle won!")
		notify(victim, "bad", "Dispossessed")
	else
		notify(tackler, "bad", "Tackle missed")
		StaminaService.Slow(tackler, 0.4, def.recovery * 1.5)
	end
end

-- No opponent near the ball: the tackle just pokes a loose ball away.
local function pokeLooseBall(tackler, t)
	local def = t.def
	t.hit = true
	local ball = BallService.GetBall()
	if ball and not ball.Anchored then
		BallService.Knock(tackler, t.dir, Config.TACKLE_POP_SPEED * (def.clean and 0.5 or 0.9), def.clean and 2 or 5, { ghost = 0.1 })
	end
end

local function stepTackles(now)
	for player, t in pairs(tackles) do
		local def = t.def
		local elapsed = now - t.t0
		if elapsed > def.window or not player.Parent then
			if not t.hit then
				StaminaService.Slow(player, 0.5, def.recovery) -- whiff: short recovery
			end
			tackles[player] = nil
		elseif not t.hit and MatchService.CanPlay() then
			local _, _, thrp = Util.getCharParts(player)
			local ball = BallService.GetBall()
			if thrp and ball and not ball.Anchored then
				local victim = findVictim(player)
				local vhrp
				if victim then
					local _, _, vh = Util.getCharParts(victim)
					vhrp = vh
				end
				if vhrp then
					local to = Vector3.new(vhrp.Position.X - thrp.Position.X, 0, vhrp.Position.Z - thrp.Position.Z)
					local d = to.Magnitude
					local inCone = d < 0.5 or math.acos(math.clamp(t.dir:Dot(to.Unit), -1, 1)) <= math.rad(Config.TACKLE_CONE_DEG)
					if d <= def.reach and inCone and math.abs(vhrp.Position.Y - thrp.Position.Y) < 5 then
						resolveTackle(player, victim, t, now)
					end
				elseif BallService.GetHolder() == nil then
					local to = Vector3.new(ball.Position.X - thrp.Position.X, 0, ball.Position.Z - thrp.Position.Z)
					local d = to.Magnitude
					local inCone = d < 0.5 or math.acos(math.clamp(t.dir:Dot(to.Unit), -1, 1)) <= math.rad(Config.TACKLE_CONE_DEG)
					if d <= def.reach * 0.7 and inCone then
						pokeLooseBall(player, t)
					end
				end
			end
		end
	end
end

function ActionService.Init()
	local function add(p)
		cds[p] = {}
		buckets[p] = Util.newBucket(Config.RATE_ACTION.rate, Config.RATE_ACTION.burst)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		add(p)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(function(p)
		cds[p], buckets[p], charges[p], tackles[p] = nil, nil, nil, nil
	end)
	Remotes.get("ActionStart").OnServerEvent:Connect(onStart)
	Remotes.get("ActionRelease").OnServerEvent:Connect(onRelease)
	Remotes.get("Tackle").OnServerEvent:Connect(onTackle)
	RunService.Heartbeat:Connect(function()
		stepTackles(os.clock())
	end)
end

return ActionService
