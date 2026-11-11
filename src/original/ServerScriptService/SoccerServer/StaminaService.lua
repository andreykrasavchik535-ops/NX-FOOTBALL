--[[
	ServerScriptService/SoccerServer/StaminaService (ModuleScript)
	Server-authoritative stamina and walk speed, plus a basic movement sanity check (anti-teleport).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Stamina = {}
local states = {}
local frozen = false

local function newState()
	return {
		st = Config.STAMINA_MAX, want = false, regenAt = 0, exhausted = false,
		slowUntil = 0, slowFactor = 1, lastSpeed = -1, bucket = Util.newBucket(Config.RATE_MISC.rate * 3, Config.RATE_MISC.burst * 2),
		lastPos = nil, lastCheck = 0, strikes = 0, skip = false, lastGoodCF = nil, sent = -1,
	}
end

local function get(player)
	local s = states[player]
	if not s then
		s = newState()
		states[player] = s
	end
	return s
end

function Stamina.Get(player)
	return get(player).st
end

function Stamina.Reset(player)
	local s = get(player)
	s.st = Config.STAMINA_MAX
	s.exhausted = false
	s.want = false
end

function Stamina.ResetAll()
	for p in pairs(states) do
		Stamina.Reset(p)
	end
end

-- Returns true and deducts if enough stamina.
function Stamina.Spend(player, amount)
	local s = get(player)
	if amount <= 0 then
		return true
	end
	if s.st < amount then
		return false
	end
	s.st = s.st - amount
	s.regenAt = os.clock() + Config.STAMINA_REGEN_DELAY
	return true
end

function Stamina.Add(player, amount)
	local s = get(player)
	s.st = math.clamp(s.st + amount, 0, Config.STAMINA_MAX)
end

-- Temporary slowdown (factor 0..1 of normal speed) after tackles.
function Stamina.Slow(player, factor, seconds)
	local s = get(player)
	local now = os.clock()
	local untilT = now + seconds
	if now < s.slowUntil and s.slowFactor < factor then
		-- a stronger slow is already running: only extend it, never weaken it
		s.slowUntil = math.max(s.slowUntil, untilT)
		return
	end
	s.slowFactor = factor
	s.slowUntil = math.max(untilT, now < s.slowUntil and s.slowUntil or 0)
end

function Stamina.SetFrozen(value)
	frozen = value
end

-- Call after the SERVER moves a character, so the movement check does not flag it.
function Stamina.NoteTeleport(player)
	get(player).skip = true
end

local function tick(dt)
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local s = get(player)
		local char, hum, hrp = Util.getCharParts(player)
		if hrp then
			local vel = hrp.AssemblyLinearVelocity
			local moving = Vector3.new(vel.X, 0, vel.Z).Magnitude > 3
			local sprinting = s.want and moving and not s.exhausted and s.st > 0 and not frozen
			if sprinting then
				s.st = math.max(0, s.st - Config.STAMINA_DRAIN * dt)
				s.regenAt = now + Config.STAMINA_REGEN_DELAY
				if s.st <= 0 then
					s.exhausted = true
				end
			elseif now >= s.regenAt then
				local rate = Config.STAMINA_REGEN * (moving and 1 or 1.6)
				s.st = math.min(Config.STAMINA_MAX, s.st + rate * dt)
				if s.exhausted and s.st >= Config.STAMINA_EXHAUSTED_UNTIL then
					s.exhausted = false
				end
			end
			-- speed
			local speed
			if frozen then
				speed = 0
			elseif s.exhausted then
				speed = Config.EXHAUSTED_SPEED
			elseif sprinting then
				speed = Config.SPRINT_SPEED
			else
				speed = Config.WALK_SPEED
			end
			if now < s.slowUntil then
				speed = speed * s.slowFactor
			end
			if math.abs(speed - s.lastSpeed) > 0.01 then
				hum.WalkSpeed = speed
				hum.UseJumpPower = true
				hum.JumpPower = frozen and 0 or Config.JUMP_POWER
				s.lastSpeed = speed
			end
			local shown = math.floor(s.st + 0.5)
			if shown ~= s.sent then
				player:SetAttribute("Stamina", shown)
				player:SetAttribute("Exhausted", s.exhausted)
				s.sent = shown
			end

			-- movement sanity (anti speed-hack / teleport)
			if now - s.lastCheck >= Config.MOVE_CHECK_INTERVAL then
				local pos = hrp.Position
				if s.skip or not s.lastPos then
					s.skip = false
					s.strikes = 0
					s.lastGoodCF = hrp.CFrame
				else
					local d = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude
					if d > Config.MOVE_MAX_DISTANCE then
						s.strikes = s.strikes + 1
						if s.strikes >= Config.MOVE_STRIKES_TO_RESET and s.lastGoodCF then
							hrp.CFrame = s.lastGoodCF
							hrp.AssemblyLinearVelocity = Vector3.zero
							s.strikes = 0
							pos = s.lastGoodCF.Position
						end
					else
						s.strikes = math.max(0, s.strikes - 1)
						s.lastGoodCF = hrp.CFrame
					end
				end
				s.lastPos = pos
				s.lastCheck = now
			end
		else
			s.lastPos = nil
			s.lastSpeed = -1
		end
	end
end

function Stamina.Init()
	Remotes.get("Sprint").OnServerEvent:Connect(function(player, want)
		local s = get(player)
		if type(want) == "boolean" and s.bucket:take() then
			s.want = want
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 0.1 then
			tick(acc)
			acc = 0
		end
	end)
end

return Stamina
