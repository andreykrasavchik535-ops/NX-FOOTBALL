--[[
	ServerScriptService/SoccerServer/BallService (ModuleScript)

	The ball. 100% server-authoritative (NX26: catch also considers AI goalkeeper entities) (network owner = nil) and 100% PHYSICAL:

	  * Nobody "owns" the ball and nothing is ever welded, parented or pulled toward a player.
	  * A player affects the ball only by
	      - bumping it with the body (normal Roblox collision),
	      - a FOOT TOUCH: while running into a ball that lies in front of the feet he gives it ONE push
	        (speed = his speed + a little); then the ball just rolls on and slows down by drag, so a
	        dribble is a series of touches and the ball can always be lost, stolen or run away,
	      - a FIRST TOUCH: an arriving pass is cushioned once, it does not stick,
	      - deliberate actions: Kick (shoot / pass / long), Launch + Drive (feints), Knock / TackleBall (tackles).
	  * "Controller" (Player attribute HasBall) is only DERIVED data: the last toucher, while the ball is near him.
	    Animations and tackles read it; it gives no power over the ball.
	  * The ONLY held ball is the goalkeeper's catch inside his own box (Config.GK_AUTO_CATCH).
	  * PlaceAt() resets EVERYTHING (state, velocity, collision group, network ownership, gravity force) so the ball
	    behaves identically before and after a goal.
]]
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Field = require(script.Parent:WaitForChild("FieldService"))

local BallService = {}

local Ball
local RADIUS = Config.BALL_DIAMETER / 2
local TOUCH_CONE_COS = math.cos(math.rad(Config.TOUCH_CONE_DEG))
local UP = Vector3.new(0, 1, 0)

local enabled = false
local holder, holdUntil = nil, 0              -- goalkeeper holding the ball in his hands
local controller = nil                        -- derived: who is "in control" (HasBall)
local lastToucher, lastToucherTeam, lastTouchTime = nil, nil, 0
local prevToucher, prevToucherTeam, prevTouchTime = nil, nil, 0
local lockout = {}                            -- [player] = time until which he cannot touch the ball
local touchReady = {}                         -- [player] = next time a foot touch / trap may happen
local parryCd = {}
local restartTeam, restartUntil = nil, 0
local ghostUntil = 0
local anchoredUntil = nil
local shotBy, shotUntil = nil, 0
local curve = nil -- small bend of a kick: { side, rate, left, untilT } (see Config.SHOT_STYLES)
local touchDebounce = 0
local ownerCheckAt = 0
local driven = { player = nil, t = 0, since = 0, broken = false } -- feint currently steering the ball

local roster = function() return {} end
local getTeam = function() return nil end
local feintProvider, gkProvider

BallService.OnSteal = nil      -- function(thief, victim, reason)
BallService.OnPossession = nil -- function(oldController, newController)
BallService.OnKick = nil       -- function(player, kind)

-- Small helpers ---------------------------------------------------------------------------------------

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function isPlaying(p)
	return getTeam(p) ~= nil
end

local function spinFor(v)
	return UP:Cross(Vector3.new(v.X, 0, v.Z)) / RADIUS
end

local function restartBlocked(p, now)
	return restartTeam ~= nil and now < restartUntil and getTeam(p) ~= restartTeam
end

local function setHasBall(p, value)
	if p and p.Parent then
		pcall(function()
			if p:GetAttribute("HasBall") ~= value then
				p:SetAttribute("HasBall", value)
			end
		end)
	end
end

-- Setup --------------------------------------------------------------------------------------------------

local function setupGroups()
	for _, name in ipairs({ "SoccerPlayers", "SoccerBall", "SoccerBallGhost" }) do
		pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
	end
	PhysicsService:CollisionGroupSetCollidable("SoccerBallGhost", "SoccerPlayers", false)
	PhysicsService:CollisionGroupSetCollidable("SoccerBall", "SoccerPlayers", true)
	PhysicsService:CollisionGroupSetCollidable("SoccerPlayers", "SoccerPlayers", true)
end

function BallService.RegisterCharacter(char)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "SoccerPlayers"
		end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "SoccerPlayers"
		end
	end)
end

local function assignNetworkOwner()
	if Ball and Ball.Parent and not Ball.Anchored then
		pcall(function() Ball:SetNetworkOwner(nil) end)
	end
end

-- (Re)applies every physical property of the ball. Called on creation and on every PlaceAt, so nothing can drift.
local function applyBallProps(b)
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(Config.BALL_DIAMETER, Config.BALL_DIAMETER, Config.BALL_DIAMETER)
	b.Material = Enum.Material.SmoothPlastic
	b.CustomPhysicalProperties = PhysicalProperties.new(Config.BALL_DENSITY, Config.BALL_FRICTION, Config.BALL_ELASTICITY, 1, 1)
	b.CanCollide = true
	b.CanTouch = true
	b.CanQuery = true
	b.Massless = false
	local vf = b:FindFirstChildOfClass("VectorForce")
	if vf then
		vf.Force = Vector3.new(0, b:GetMass() * Workspace.Gravity * (1 - Config.BALL_GRAVITY_SCALE), 0)
	end
end

local function registerTouch(p, now)
	if lastToucher ~= p then
		prevToucher, prevToucherTeam, prevTouchTime = lastToucher, lastToucherTeam, lastTouchTime
	end
	lastToucher = p
	lastToucherTeam = getTeam(p)
	lastTouchTime = now
	curve = nil -- any touch ends a bend
end

local function onBallTouched(part)
	local now = os.clock()
	if now < touchDebounce or holder or not enabled then
		return
	end
	local model = part:FindFirstAncestorOfClass("Model")
	local pl = model and Players:GetPlayerFromCharacter(model)
	if pl and isPlaying(pl) then
		touchDebounce = now + 0.12
		registerTouch(pl, now)
	end
end

local function createBall()
	local b = Instance.new("Part")
	b.Name = "SoccerBall"
	b.Color = Color3.fromRGB(245, 245, 245)
	b.TopSurface = Enum.SurfaceType.Smooth
	b.BottomSurface = Enum.SurfaceType.Smooth
	b.CollisionGroup = "SoccerBall"
	b.Anchored = false
	b:SetAttribute("OwnerUserId", 0)
	local att = Instance.new("Attachment")
	att.Name = "GravityAttachment"
	att.Parent = b
	local vf = Instance.new("VectorForce")
	vf.Name = "GravityOffset"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = b
	applyBallProps(b)
	b.CFrame = CFrame.new(Field.ToWorld(Vector3.new(0, RADIUS + 0.2, 0)))
	b.Parent = Workspace
	applyBallProps(b) -- once more with the final parent (mass is known for sure)
	b.Touched:Connect(onBallTouched)
	return b
end

local function ensureBall()
	if Ball and Ball.Parent then
		return Ball
	end
	if Ball then
		pcall(function() Ball:Destroy() end)
	end
	Ball = createBall()
	assignNetworkOwner()
	return Ball
end

-- Controller (derived, display only) ---------------------------------------------------------------------------

local function setController(p, now)
	if p == controller then
		return
	end
	local old = controller
	controller = p
	setHasBall(old, false)
	setHasBall(p, p ~= nil)
	if Ball then
		Ball:SetAttribute("OwnerUserId", p and p.UserId or 0)
	end
	if BallService.OnPossession then
		BallService.OnPossession(old, p)
	end
end

local function updateController(now)
	local new = nil
	if holder then
		new = holder
	elseif lastToucher and lastToucher.Parent and enabled and not Ball.Anchored
		and now - lastTouchTime <= Config.CONTROL_MEMORY and isPlaying(lastToucher) then
		local _, hum, hrp = Util.getCharParts(lastToucher)
		if hrp then
			local bp = Ball.Position
			local dx, dz = bp.X - hrp.Position.X, bp.Z - hrp.Position.Z
			local h = bp.Y - Util.groundY(hum, hrp)
			if dx * dx + dz * dz <= Config.CONTROL_RADIUS ^ 2 and h <= Config.CONTROL_HEIGHT then
				new = lastToucher
			end
		end
	end
	setController(new, now)
end

-- Goalkeeper hold ---------------------------------------------------------------------------------------------------

local function startHold(p, now)
	holder = p
	holdUntil = now + Config.GK_HOLD_TIME
	lockout[p] = nil
	driven.player = nil
	Ball.CollisionGroup = "SoccerBallGhost"
	registerTouch(p, now)
	updateController(now)
end

local function clearHolder(now, ghostSeconds)
	if not holder then
		return
	end
	local p = holder
	holder = nil
	lockout[p] = now + 0.4
	ghostUntil = now + (ghostSeconds or 0.15)
	Ball.CollisionGroup = "SoccerBallGhost"
	updateController(now)
end

local function stepHolder(dt, now)
	local p = holder
	local _, hum, hrp = Util.getCharParts(p)
	local outOfBox = Config.GK_HOLD_IN_BOX_ONLY and gkProvider and gkProvider.InOwnBox and hrp
		and not gkProvider.InOwnBox(p, hrp.Position)
	if not hrp or not isPlaying(p) or not enabled or outOfBox then
		clearHolder(now, 0.15)
		return
	end
	local look = Util.flatUnit(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	if now >= holdUntil then
		clearHolder(now, 0.2)
		Ball.AssemblyLinearVelocity = look * Config.GK_PUNT_SPEED + Vector3.new(0, 26, 0)
		registerTouch(p, now)
		return
	end
	local bp = Ball.Position
	local hp = hrp.Position
	local ground = Util.groundY(hum, hrp)
	local hv = flat(hrp.AssemblyLinearVelocity)
	local target = Vector3.new(hp.X + look.X * 1.7, ground + 3.3, hp.Z + look.Z * 1.7)
	local v = (target - bp) * 20 + hv
	if v.Magnitude > 70 then
		v = v.Unit * 70
	end
	Ball.AssemblyLinearVelocity = v
	Ball.AssemblyAngularVelocity = Vector3.zero
end

-- Real players + AI goalkeeper entities (the only AI). roster() returns a fresh list, so appending is safe.
local function keeperCandidates()
	local list = roster()
	if gkProvider and gkProvider.AIKeepers then
		for _, k in ipairs(gkProvider.AIKeepers()) do
			table.insert(list, k)
		end
	end
	return list
end

local function stepKeeperCatch(now)
	if not Config.GK_AUTO_CATCH or not gkProvider then
		return false
	end
	local bp = Ball.Position
	local bspeed = Ball.AssemblyLinearVelocity.Magnitude
	for _, p in ipairs(keeperCandidates()) do
		if now >= (lockout[p] or 0) and not restartBlocked(p, now) then
			local gp = gkProvider.Params(p, bp, now)
			if gp then
				local _, hum, hrp = Util.getCharParts(p)
				if hrp then
					local hp = hrp.Position
					local dx, dz = bp.X - hp.X, bp.Z - hp.Z
					local h = bp.Y - Util.groundY(hum, hrp)
					if dx * dx + dz * dz <= gp.radius ^ 2 and h <= gp.maxHeight then
						if bspeed <= gp.maxSpeed then
							startHold(p, now)
							if gkProvider.OnCatch then
								gkProvider.OnCatch(p, now)
							end
							return true
						elseif gp.canParry and now >= (parryCd[p] or 0) then
							-- too fast to catch: parry it away
							parryCd[p] = now + Config.GK_PARRY_COOLDOWN
							local away = Util.flatUnit(Vector3.new(dx, 0, dz), hrp.CFrame.LookVector)
							Ball.AssemblyLinearVelocity = away * (bspeed * 0.45) + Vector3.new(0, 14, 0)
							registerTouch(p, now)
							if gkProvider.OnParry then
								gkProvider.OnParry(p, now)
							end
							return true
						end
					end
				end
			end
		end
	end
	return false
end

-- Foot touches and first touch -----------------------------------------------------------------------------------------

-- "free" | "blocked" | "breaks": what a touch by p means for a feint that is steering the ball right now.
local function driveState(p, now)
	local dp = driven.player
	if not dp or now - driven.t > 0.2 then
		return "free"
	end
	if dp == p then
		return "blocked" -- the feinter's own steering replaces his foot touches
	end
	if getTeam(dp) == getTeam(p) then
		return "blocked" -- team mates leave the feint alone
	end
	if feintProvider and feintProvider.IsEvading(dp, now) then
		return "blocked"
	end
	return "breaks"
end

-- Returns (newFlatVelocity, kind) or nil. kind = "touch" | "trap".
local function computeTouch(hrp, dx, dz, d, bv)
	local pv = hrp.AssemblyLinearVelocity
	local hv = Vector3.new(pv.X, 0, pv.Z)
	local sp = hv.Magnitude
	local look = Util.flatUnit(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	local moveDir = sp > 2 and (hv / sp) or look
	local toBall = d > 1e-3 and Vector3.new(dx / d, 0, dz / d) or moveDir
	local bflat = Vector3.new(bv.X, 0, bv.Z)
	local rel = bflat - hv

	-- foot touch: running into a ball that lies in front of the feet
	if sp >= Config.TOUCH_MIN_SPEED and moveDir:Dot(toBall) >= TOUCH_CONE_COS and rel.Magnitude <= Config.TOUCH_MAX_REL_SPEED then
		local speedFrac = math.clamp(sp / Config.SPRINT_SPEED, 0, 1)
		local push = Config.TOUCH_PUSH_MIN + (Config.TOUCH_PUSH_MAX - Config.TOUCH_PUSH_MIN) * speedFrac
		local target = sp * Config.TOUCH_CARRY + push
		local along = bflat:Dot(moveDir)
		if along < target then -- a ball already running away faster than that is left alone
			local lateral = bflat - moveDir * along
			return moveDir * target + lateral * Config.TOUCH_SIDE_KEEP, "touch"
		end
		return nil
	end

	-- first touch: cushion an arriving ball once
	if Config.TRAP_ENABLED and d <= Config.TRAP_RADIUS then
		local bspeed = bv.Magnitude
		if bspeed >= Config.TRAP_MIN_BALL_SPEED and bspeed <= Config.TRAP_MAX_BALL_SPEED
			and rel:Dot(toBall) < -1 and moveDir:Dot(toBall) > -0.25 then
			return bflat:Lerp(hv * 0.9, Config.TRAP_STRENGTH), "trap"
		end
	end
	return nil
end

local function stepTouches(dt, now)
	local bp = Ball.Position
	local bv = Ball.AssemblyLinearVelocity
	if bp.Y - Field.Get().ground > Config.TOUCH_MAX_HEIGHT + 4 then
		return -- ball is high in the air: nothing to do with the feet
	end
	local reach2 = math.max(Config.TOUCH_RADIUS, Config.TRAP_RADIUS) ^ 2
	local best, bestD, bestVel, bestKind, bestH
	for _, p in ipairs(roster()) do
		if now >= (lockout[p] or 0) and now >= (touchReady[p] or 0) and not restartBlocked(p, now) then
			local _, hum, hrp = Util.getCharParts(p)
			if hrp then
				local hp = hrp.Position
				local dx, dz = bp.X - hp.X, bp.Z - hp.Z
				local d2 = dx * dx + dz * dz
				if d2 <= reach2 then
					local h = bp.Y - Util.groundY(hum, hrp)
					if h <= Config.TOUCH_MAX_HEIGHT and driveState(p, now) ~= "blocked" then
						local d = math.sqrt(d2)
						local vel, kind = computeTouch(hrp, dx, dz, d, bv)
						if vel and (kind ~= "touch" or d <= Config.TOUCH_RADIUS) and (not best or d < bestD) then
							best, bestD, bestVel, bestKind, bestH = p, d, vel, kind, h
						end
					end
				end
			end
		end
	end
	if not best then
		return
	end
	if driveState(best, now) == "breaks" then
		driven.broken = true
	end
	local vy = bv.Y
	if bestKind == "trap" then
		vy = vy * 0.35
	elseif bestH < RADIUS + 0.6 then
		vy = math.min(vy, 0)
	else
		vy = vy * 0.6
	end
	Ball.AssemblyLinearVelocity = Vector3.new(bestVel.X, vy, bestVel.Z)
	Ball.AssemblyAngularVelocity = spinFor(bestVel)
	registerTouch(best, now)
	touchReady[best] = now + (bestKind == "trap" and Config.TRAP_INTERVAL or Config.TOUCH_INTERVAL)
end

-- Free ball drag -------------------------------------------------------------------------------------------------------------

local function applyDrag(dt)
	local f = Field.Get()
	local bp = Ball.Position
	local v = Ball.AssemblyLinearVelocity
	local onGround = (bp.Y - f.ground - RADIUS) < 0.45
	local drag = onGround and Config.BALL_GROUND_DRAG or Config.BALL_AIR_DRAG
	if not enabled then
		drag = drag + Config.BALL_DEAD_DRAG -- dead ball (goal / pause): it settles instead of bouncing around the net
	end
	local k = math.exp(-drag * dt)
	local nv = Vector3.new(v.X * k, v.Y, v.Z * k)
	if onGround and Vector3.new(nv.X, 0, nv.Z).Magnitude < Config.BALL_STOP_SPEED and math.abs(nv.Y) < 1 then
		nv = Vector3.zero
		Ball.AssemblyAngularVelocity = Vector3.zero
	end
	if nv.Magnitude > Config.BALL_MAX_SPEED then
		nv = nv.Unit * Config.BALL_MAX_SPEED
	end
	Ball.AssemblyLinearVelocity = nv
end

-- Main step (called from Main's Heartbeat) ---------------------------------------------------------------------------------------

-- Turns the horizontal velocity by a small angle each frame (speed is kept). Ends by itself.
local function applyCurve(dt, now)
	if not curve then
		return
	end
	if now > curve.untilT or curve.left <= 0 then
		curve = nil
		return
	end
	local v = Ball.AssemblyLinearVelocity
	local hx, hz = v.X, v.Z
	if math.sqrt(hx * hx + hz * hz) < 22 then
		curve = nil
		return
	end
	local da = math.min(curve.rate * dt, curve.left)
	curve.left = curve.left - da
	local a = da * curve.side
	local c, s = math.cos(a), math.sin(a)
	Ball.AssemblyLinearVelocity = Vector3.new(hx * c - hz * s, v.Y, hx * s + hz * c)
end

function BallService.Step(dt)
	if not Ball or not Ball.Parent then
		ensureBall()
		return
	end
	local now = os.clock()
	local bp = Ball.Position
	if bp.X ~= bp.X or bp.Y ~= bp.Y or bp.Magnitude > 1e5 or bp.Y < Field.Get().ground - 150 then
		BallService.PlaceAt(Field.ToWorld(Vector3.new(0, RADIUS + 0.2, 0)), 0)
		return
	end
	if Ball.Anchored then
		if anchoredUntil and now >= anchoredUntil then
			Ball.Anchored = false
			anchoredUntil = nil
			assignNetworkOwner()
		end
		updateController(now)
		return
	end
	-- the ball must stay server-simulated: re-assert it if Roblox gave it back to "automatic"
	if now >= ownerCheckAt then
		ownerCheckAt = now + 0.5
		local ok, auto = pcall(function() return Ball:GetNetworkOwnershipAuto() end)
		if ok and auto then
			assignNetworkOwner()
		end
	end
	if ghostUntil ~= 0 and now >= ghostUntil and not holder and (not driven.player or now - driven.t > 0.2) then
		Ball.CollisionGroup = "SoccerBall"
		ghostUntil = 0
	end
	if holder then
		stepHolder(dt, now)
	else
		applyDrag(dt)
		applyCurve(dt, now)
		if enabled then
			if not stepKeeperCatch(now) then
				stepTouches(dt, now)
			end
		else
			driven.player = nil
		end
	end
	updateController(now)
end

-- Queries -------------------------------------------------------------------------------------------------------------------------------

-- True if the player may act on the ball (kick it, feint with it): it is loose, in play, within reach, not locked out.
function BallService.CanControl(player, reach, maxHeight)
	if not Ball or Ball.Anchored or not enabled or holder then
		return false
	end
	local _, hum, hrp = Util.getCharParts(player)
	if not hrp then
		return false
	end
	local now = os.clock()
	if now < (lockout[player] or 0) or restartBlocked(player, now) then
		return false
	end
	local bp = Ball.Position
	local dx, dz = bp.X - hrp.Position.X, bp.Z - hrp.Position.Z
	local h = bp.Y - Util.groundY(hum, hrp)
	return dx * dx + dz * dz <= reach * reach and h <= maxHeight
end

function BallService.CanReach(player)
	return BallService.CanControl(player, Config.KICK_REACH, Config.KICK_MAX_HEIGHT)
end

-- Actions on the ball ---------------------------------------------------------------------------------------------------------------------

-- dir: horizontal unit vector, hSpeed: studs/s along dir, vSpeed: studs/s up.
function BallService.Kick(player, dir, hSpeed, vSpeed, opts)
	local now = os.clock()
	opts = opts or {}
	if holder == player then
		clearHolder(now, Config.KICK_GHOST_TIME)
	end
	lockout[player] = now + Config.POSSESSION_LOCKOUT
	ghostUntil = now + Config.KICK_GHOST_TIME
	Ball.CollisionGroup = "SoccerBallGhost"
	if driven.player == player then
		driven.player = nil
	end
	local _, _, hrp = Util.getCharParts(player)
	local carry = Vector3.zero
	if hrp then
		carry = flat(hrp.AssemblyLinearVelocity) * Config.KICK_CARRY
	end
	local flatDir = Util.flatUnit(dir, hrp and hrp.CFrame.LookVector or Vector3.new(0, 0, -1))
	local vel = flatDir * hSpeed + carry + Vector3.new(0, vSpeed, 0)
	if vel.Magnitude > Config.BALL_MAX_SPEED then
		vel = vel.Unit * Config.BALL_MAX_SPEED
	end
	Ball.AssemblyLinearVelocity = vel
	Ball.AssemblyAngularVelocity = spinFor(vel) * 0.8
	registerTouch(player, now)
	if opts.curve and opts.curve.deg and opts.curve.deg > 0 then
		curve = {
			side = opts.curve.side >= 0 and 1 or -1, rate = math.rad(opts.curve.rate), left = math.rad(opts.curve.deg),
			untilT = now + opts.curve.dur,
		}
	end
	if opts.shot then
		shotBy, shotUntil = player, now + 3
	end
	updateController(now)
	if BallService.OnKick then
		BallService.OnKick(player, opts.kind or "kick")
	end
end

-- One free kick of the ball by a feint (rainbow flick, nutmeg...). vel is a full world velocity.
function BallService.Launch(player, vel, opts)
	if not Ball or Ball.Anchored or holder or not enabled then
		return false
	end
	opts = opts or {}
	local now = os.clock()
	if vel.Magnitude > Config.BALL_MAX_SPEED then
		vel = vel.Unit * Config.BALL_MAX_SPEED
	end
	Ball.AssemblyLinearVelocity = vel
	Ball.AssemblyAngularVelocity = spinFor(vel) * 0.8
	ghostUntil = now + (opts.ghost or 0.2)
	Ball.CollisionGroup = "SoccerBallGhost"
	lockout[player] = now + (opts.lockout or Config.FEINT_LAUNCH_LOCKOUT)
	if driven.player == player then
		driven.player = nil
	end
	registerTouch(player, now)
	updateController(now)
	return true
end

-- A feint steers the ball toward `target` (world position) for one frame. Returns false when the feint must end
-- (ball lost, stolen, too far, play stopped). The ball is steered with velocity only: it stays a free physics body.
function BallService.Drive(player, target, dt, lift)
	if not Ball or Ball.Anchored or holder or not enabled then
		return false
	end
	local now = os.clock()
	if driven.player ~= player then
		driven.player, driven.since, driven.broken = player, now, false
	end
	if driven.broken then
		driven.player, driven.broken = nil, false
		return false
	end
	local _, hum, hrp = Util.getCharParts(player)
	if not hrp then
		driven.player = nil
		return false
	end
	local bp = Ball.Position
	local ground = Util.groundY(hum, hrp)
	local off = Vector3.new(bp.X - hrp.Position.X, 0, bp.Z - hrp.Position.Z).Magnitude
	if off > Config.FEINT_BREAK_DISTANCE or bp.Y - ground > Config.FEINT_MAX_HEIGHT + 3 then
		driven.player = nil
		return false
	end
	driven.t = now

	local hv = flat(hrp.AssemblyLinearVelocity)
	local bvel = Ball.AssemblyLinearVelocity
	local err = Vector3.new(target.X - bp.X, 0, target.Z - bp.Z)
	local want = hv + err * Config.FEINT_GAIN
	local cap = hv.Magnitude + Config.FEINT_MAX_EXTRA_SPEED
	if want.Magnitude > cap then
		want = want.Unit * cap
	end
	local alpha = 1 - math.exp(-Config.FEINT_SMOOTH * dt)
	local nh = Vector3.new(bvel.X, 0, bvel.Z):Lerp(want, alpha)
	local vy = bvel.Y
	if lift then
		vy = vy + ((target.Y - bp.Y) * Config.FEINT_GAIN * 0.6 - vy) * alpha
	elseif (bp.Y - (ground + RADIUS)) < 0.5 and vy > 0 then
		vy = 0
	end
	Ball.AssemblyLinearVelocity = Vector3.new(nh.X, vy, nh.Z)
	Ball.AssemblyAngularVelocity = spinFor(nh)
	-- pass through bodies while the foot is working on the ball (otherwise it would jam against the feinter's legs)
	ghostUntil = now + 0.12
	if Ball.CollisionGroup ~= "SoccerBallGhost" then
		Ball.CollisionGroup = "SoccerBallGhost"
	end
	registerTouch(player, now)
	return true
end

function BallService.EndDrive(player)
	if driven.player == player then
		driven.player, driven.broken = nil, false
	end
end

function BallService.IsDriving(player)
	return driven.player == player and os.clock() - driven.t <= 0.2
end

-- Knocks the ball in a direction (tackles, pokes). opts: victim (gets the tackled lockout), ghost (seconds).
function BallService.Knock(by, dir, speed, up, opts)
	if not Ball or Ball.Anchored or holder then
		return false
	end
	opts = opts or {}
	local now = os.clock()
	local d = Util.flatUnit(dir, Vector3.new(0, 0, -1))
	local vel = d * speed + Vector3.new(0, up or 0, 0)
	Ball.AssemblyLinearVelocity = vel
	Ball.AssemblyAngularVelocity = spinFor(vel) * 0.8
	if opts.victim then
		lockout[opts.victim] = now + Config.TACKLED_LOCKOUT
		if driven.player == opts.victim then
			driven.player, driven.broken = nil, false
		end
	end
	if opts.ghost then
		ghostUntil = now + opts.ghost
		Ball.CollisionGroup = "SoccerBallGhost"
	end
	if by then
		registerTouch(by, now)
		touchReady[by] = now + Config.TOUCH_INTERVAL
	end
	updateController(now)
	return true
end

-- A won tackle. clean: the ball rolls toward the tackler's feet; otherwise it is knocked away along `dir`.
function BallService.TackleBall(tackler, victim, clean, dir)
	if not Ball or Ball.Anchored or holder then
		return false
	end
	local now = os.clock()
	local _, _, thrp = Util.getCharParts(tackler)
	if clean and thrp then
		local look = Util.flatUnit(dir, thrp.CFrame.LookVector)
		local spot = thrp.Position + look * 2.4
		local bp = Ball.Position
		local to = Vector3.new(spot.X - bp.X, 0, spot.Z - bp.Z)
		local dist = to.Magnitude
		local speed = math.clamp(dist * 5, Config.TACKLE_WIN_SPEED * 0.6, Config.TACKLE_WIN_SPEED * 1.6)
		local vel = (dist > 0.1 and to.Unit or look) * speed + flat(thrp.AssemblyLinearVelocity) * 0.5
		Ball.AssemblyLinearVelocity = vel
		Ball.AssemblyAngularVelocity = spinFor(vel)
		lockout[victim] = now + Config.TACKLED_LOCKOUT
		ghostUntil = now + 0.12
		Ball.CollisionGroup = "SoccerBallGhost"
		if driven.player == victim then
			driven.player, driven.broken = nil, false
		end
		registerTouch(tackler, now)
		updateController(now)
		return true
	end
	return BallService.Knock(tackler, dir, Config.TACKLE_POP_SPEED, 8, { victim = victim, ghost = 0.1 })
end

function BallService.SetLockout(player, seconds)
	lockout[player] = os.clock() + seconds
end

-- API for the match / rules -------------------------------------------------------------------------------------------------------------------

function BallService.SetEnabled(value)
	enabled = value and true or false
	if not enabled then
		driven.player, driven.broken = nil, false
		if holder and Ball then
			clearHolder(os.clock(), 0.15)
		end
	end
end

-- Puts the ball at worldPos and resets EVERY piece of ball state. holdSeconds > 0 freezes it there.
function BallService.PlaceAt(worldPos, holdSeconds)
	ensureBall()
	local now = os.clock()
	holder = nil
	curve = nil
	driven.player, driven.broken = nil, false
	ghostUntil = 0
	lockout, touchReady, parryCd = {}, {}, {}
	setController(nil, now)
	Ball.Anchored = false
	Ball.AssemblyLinearVelocity = Vector3.zero
	Ball.AssemblyAngularVelocity = Vector3.zero
	Ball.CollisionGroup = "SoccerBall"
	applyBallProps(Ball)
	Ball.CFrame = CFrame.new(worldPos)
	Ball.AssemblyLinearVelocity = Vector3.zero
	Ball.AssemblyAngularVelocity = Vector3.zero
	if holdSeconds and holdSeconds > 0 then
		Ball.Anchored = true
		anchoredUntil = now + holdSeconds
	else
		anchoredUntil = nil
		assignNetworkOwner()
	end
end

function BallService.SetRestart(team, seconds)
	restartTeam = team
	restartUntil = os.clock() + (seconds or 0)
end

function BallService.ClearRestart()
	restartTeam = nil
	restartUntil = 0
end

function BallService.ClearHistory()
	lastToucher, lastToucherTeam, prevToucher, prevToucherTeam = nil, nil, nil, nil
	lockout, touchReady = {}, {}
	shotBy = nil
end

function BallService.GetBall() return Ball end
function BallService.GetController() return controller end
function BallService.GetHolder() return holder end
function BallService.GetLastTouch() return lastToucher, lastToucherTeam, prevToucher, prevToucherTeam, prevTouchTime end
function BallService.GetShot() return shotBy, shotUntil end
-- legacy names (the game no longer has an "owner"; these return the derived controller / holder)
function BallService.GetOwner() return controller end
function BallService.GetOwnerMode() return holder and "gkHold" or "free" end

function BallService.Configure(opts)
	roster = opts.roster or roster
	getTeam = opts.getTeam or getTeam
	feintProvider = opts.feint
	gkProvider = opts.gk
end

function BallService.Init()
	setupGroups()
	local function onChar(char)
		BallService.RegisterCharacter(char)
	end
	local function onPlayer(p)
		p:SetAttribute("HasBall", false)
		if p.Character then
			onChar(p.Character)
		end
		p.CharacterAdded:Connect(onChar)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		lockout[p], touchReady[p], parryCd[p] = nil, nil, nil
		if lastToucher == p then
			lastToucher = nil
		end
		if prevToucher == p then
			prevToucher = nil
		end
		if holder == p then
			holder = nil
			if Ball then
				ghostUntil = os.clock() + 0.15
			end
		end
		if driven.player == p then
			driven.player = nil
		end
		if controller == p then
			controller = nil
			if Ball then
				Ball:SetAttribute("OwnerUserId", 0)
			end
		end
	end)
	ensureBall()
	assignNetworkOwner()
end

return BallService
