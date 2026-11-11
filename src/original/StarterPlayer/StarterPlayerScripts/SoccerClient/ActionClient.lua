--[[
	StarterPlayerScripts/SoccerClient/ActionClient (ModuleScript)
	Client logic behind every button / key: sends INTENTS to the server, predicts cooldowns for the UI
	and corrects them from the server's ActionResult. The client never decides outcomes.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Defs = require(Shared:WaitForChild("FeintDefs"))

local player = Players.LocalPlayer

local A = {}
A.Changed = Instance.new("BindableEvent") -- (key)
A.Toast = Instance.new("BindableEvent")   -- (kind, text)
A.Side = 1                                  -- manual side toggle: 1 = right, -1 = left

local cd = {}       -- [key] = { readyAt, duration }
local charging = {} -- [action] = start time
local chargeStyle = {} -- [action] = style chosen when the charge began
local sprinting = false
local lastToastAt = {}

local REASONS = {
	["need the ball"] = "Need the ball",
	["need speed"] = "Need more speed",
	["stamina"] = "No stamina",
	["busy"] = "Wait...",
	["no ball"] = "Ball out of reach",
	["not live"] = "Ball not in play",
	["you have the ball"] = "Tackle without the ball",
	["holding"] = "Release the ball first",
	["too fast"] = "Too fast",
	["too low"] = "Ball too low for a header",
}

local function startCd(key, duration)
	if duration and duration > 0 then
		cd[key] = { readyAt = os.clock() + duration, duration = duration }
	else
		cd[key] = nil
	end
	A.Changed:Fire(key)
end

function A.GetCooldown(key)
	local c = cd[key]
	if not c then
		return 0, 0
	end
	local remaining = c.readyAt - os.clock()
	if remaining <= 0 then
		return 0, c.duration
	end
	return remaining, c.duration
end

local function ready(key)
	return (A.GetCooldown(key)) <= 0
end

function A.IsGK()
	return player:GetAttribute("SoccerRole") == "GK"
end

-- Aim = where the player is moving, otherwise where the body faces.
function A.Aim()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return Vector3.new(0, 0, -1)
	end
	local md = hum.MoveDirection
	if md.Magnitude > 0.1 then
		return Vector3.new(md.X, 0, md.Z).Unit
	end
	local look = hrp.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

-- Side for mirrored feints: stick direction relative to the body if clear, otherwise the manual toggle.
function A.PickSide()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.MoveDirection.Magnitude > 0.1 then
		local lateral = hum.MoveDirection:Dot(hrp.CFrame.RightVector)
		if math.abs(lateral) > 0.55 then
			return lateral > 0 and 1 or -1
		end
	end
	return A.Side
end

function A.ToggleSide()
	A.Side = -A.Side
	A.Changed:Fire("SIDE")
end

-- Hold-to-charge kicks ---------------------------------------------------------------------------------------
function A.Begin(action, style)
	if charging[action] or not ready(action) then
		return
	end
	charging[action] = os.clock()
	chargeStyle[action] = style
	Remotes.get("ActionStart"):FireServer(action)
	A.Changed:Fire(action)
end

function A.End(action)
	local t = charging[action]
	if not t then
		return
	end
	charging[action] = nil
	local style = chargeStyle[action]
	chargeStyle[action] = nil
	Remotes.get("ActionRelease"):FireServer(action, A.Aim(), style, A.PickSide())
	startCd(action, Config.COOLDOWNS[action]) -- predicted; server result corrects it
end

function A.ChargeFraction(action)
	local t = charging[action]
	if not t then
		return 0
	end
	return math.clamp((os.clock() - t) / Config.CHARGE_TIME, 0, 1)
end

-- Tackles / feints / goalkeeper ------------------------------------------------------------------------------------
function A.Tackle(kind)
	local key = "TACKLE:" .. kind
	if not ready(key) then
		return
	end
	Remotes.get("Tackle"):FireServer(kind, A.Aim())
	startCd(key, Config.TACKLES[kind].cooldown)
end

-- Feints have NO cooldown: every press is sent, the server decides (ball within reach, speed, stamina).
function A.Feint(idOrIndex)
	local def = type(idOrIndex) == "number" and Defs.List[idOrIndex] or Defs.ById[idOrIndex]
	if not def then
		return
	end
	Remotes.get("Feint"):FireServer(def.Id, A.PickSide(), A.Aim())
	A.Changed:Fire("FEINT:" .. def.Id)
end

function A.HasBall()
	return player:GetAttribute("HasBall") == true
end

function A.GKDive(side)
	if not A.IsGK() or not ready("GKDIVE") then
		return
	end
	Remotes.get("GKDive"):FireServer(side)
end

function A.SetSprint(value)
	if sprinting ~= value then
		sprinting = value
		Remotes.get("Sprint"):FireServer(value)
	end
end

function A.IsSprinting()
	return sprinting
end

-- Sprint is a toggle: one tap turns it on, the next tap turns it off.
function A.ToggleSprint()
	A.SetSprint(not sprinting)
	A.Changed:Fire("SPRINT")
end

function A.Init()
	Remotes.get("ActionResult").OnClientEvent:Connect(function(key, ok, reason, cooldown)
		if ok then
			if cooldown and cooldown > 0 then
				startCd(key, cooldown)
			end
		else
			if reason == "cooldown" and cooldown and cooldown > 0 then
				startCd(key, cooldown)
			else
				cd[key] = nil
				A.Changed:Fire(key)
				local text = REASONS[reason] or reason
				local now = os.clock()
				if now - (lastToastAt[text] or 0) > 0.9 then -- do not flood the screen when a button is mashed
					lastToastAt[text] = now
					A.Toast:Fire("bad", text)
				end
			end
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, text)
		A.Toast:Fire(kind, text)
	end)
	Remotes.get("ComboHit").OnClientEvent:Connect(function(name)
		A.Toast:Fire("combo", "COMBO  " .. name)
	end)
end

return A
