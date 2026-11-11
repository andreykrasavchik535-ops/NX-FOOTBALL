--[[
	StarterPlayerScripts/SoccerClient/FeintAnimator (ModuleScript)
	Connects server events (feint, tackle, dive, kick, catch) to AnimationController.

	* The animation is played ONLY on the local player's own character; Roblox replicates it to everyone.
	* When the slot in SoccerShared/AnimationIds is empty, a text popup with the move name is shown over the
	  player instead (every client shows it; switch off with Config.ANIM_PLACEHOLDER_POPUPS = false).
	* The small body movement / spin of a feint and the lunge of a tackle are applied to the LOCAL character only
	  (the server never moves characters), so they work with or without animations.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Defs = require(Shared:WaitForChild("FeintDefs"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local AC = require(script.Parent:WaitForChild("AnimationController"))

local localPlayer = Players.LocalPlayer
local Animator = {}
local spinLocks = setmetatable({}, { __mode = "k" }) -- [humanoid] = number of running spins

local function charOf(userId)
	local p = Players:GetPlayerByUserId(userId)
	return p and p.Character, p
end

local function popup(char, text, color)
	if not Config.ANIM_PLACEHOLDER_POPUPS then
		return
	end
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("SkillPopup")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SkillPopup"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(190, 36)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head
	local l = UIKit.label(gui, {
		Size = UDim2.fromScale(1, 1), Text = text, TextSize = 20, TextColor3 = UIKit.Theme.text,
		TextStrokeTransparency = 0.4,
	})
	task.delay(0.7, function()
		if l.Parent then
			for i = 1, 8 do
				l.TextTransparency = i / 8
				l.TextStrokeTransparency = 0.4 + i / 8 * 0.6
				task.wait(0.04)
			end
		end
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

-- Adds `vec` studs/s of velocity to the local character, spread over `dur` seconds.
local function burst(hrp, vec, dur)
	task.spawn(function()
		local t0 = os.clock()
		local last = t0
		while hrp.Parent do
			RunService.Heartbeat:Wait()
			local now = os.clock()
			local dt = now - last
			last = now
			if now - t0 > dur then
				break
			end
			hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + vec * (dt / dur)
		end
	end)
end

local function spin(char, degrees, dur)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return
	end
	task.spawn(function()
		-- overlapping spins share one "AutoRotate off" period, so it is always restored
		local n = spinLocks[hum] or 0
		if n == 0 then
			hum:SetAttribute("NXAutoRotate", hum.AutoRotate)
		end
		spinLocks[hum] = n + 1
		hum.AutoRotate = false
		hum:SetAttribute("NXSpin", true) -- tells ShiftLock not to fight the spin
		local t0 = os.clock()
		local last = t0
		while hrp.Parent do
			RunService.RenderStepped:Wait()
			local now = os.clock()
			local dt = now - last
			last = now
			if now - t0 > dur then
				break
			end
			hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(degrees) * (dt / dur), 0)
		end
		spinLocks[hum] = math.max((spinLocks[hum] or 1) - 1, 0)
		if spinLocks[hum] == 0 then
			hum:SetAttribute("NXSpin", false)
			local prev = hum:GetAttribute("NXAutoRotate")
			hum.AutoRotate = prev == nil and true or prev
		end
	end)
end

local function onFeint(userId, id, side, fwd, duration)
	local def = Defs.ById[id]
	local char, p = charOf(userId)
	if not def or not char then
		return
	end
	local played = false
	if p == localPlayer then
		played = AC.Play("Feints", id, side) ~= nil
	else
		played = AC.Has("Feints", id, side) -- another player's own client plays it; we only decide about the popup
	end
	if not played then
		popup(char, string.upper(def.Name), UIKit.Theme.categories[def.Category])
	end
	if p == localPlayer then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local sgn = def.NoMirror and 1 or side
		local right = fwd:Cross(Vector3.new(0, 1, 0))
		for _, b in ipairs(def.Body) do
			task.delay(b.t, function()
				if not hrp.Parent then
					return
				end
				if b.spin then
					spin(char, -b.spin * sgn, b.dur)
				else
					burst(hrp, fwd * (b.f or 0) + right * ((b.r or 0) * sgn), b.dur)
				end
			end)
		end
	end
end

local function onTackle(userId, kind, dir)
	local char, p = charOf(userId)
	if not char then
		return
	end
	local key = kind == "Slide" and "TackleSlide" or "TackleFast"
	local played = false
	if p == localPlayer then
		played = AC.Play("Actions", key) ~= nil
	else
		played = AC.Has("Actions", key)
	end
	if not played then
		popup(char, kind == "Slide" and "SLIDE TACKLE" or "TACKLE")
	end
	if p == localPlayer then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local def = Config.TACKLES[kind]
		if hrp and def then
			burst(hrp, dir * def.lunge, 0.25)
		end
	end
end

local function onDive(userId, side)
	local char, p = charOf(userId)
	if not char then
		return
	end
	local played = false
	if p == localPlayer then
		local key = side < 0 and "GKDiveLeft" or (side > 0 and "GKDiveRight" or "GKDive")
		if AC.Has("Actions", key) then
			played = AC.Play("Actions", key) ~= nil
		else
			played = AC.Play("Actions", "GKDive") ~= nil
		end
	else
		played = AC.Has("Actions", "GKDive") or AC.Has("Actions", "GKDiveLeft") or AC.Has("Actions", "GKDiveRight")
	end
	if not played then
		popup(char, "DIVE")
	end
	if p == localPlayer then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local right = hrp.CFrame.RightVector
			burst(hrp, right * (side * Config.GK_DIVE_IMPULSE) + Vector3.new(0, 14, 0), 0.3)
		end
	end
end

local KICK_KEYS = { SHOOT = "Shoot", PASS = "Pass", LONG = "Long" }
-- A style may have its own animation slot; when it is empty the normal Shoot / Pass animation is used.
local STYLE_KEYS = {
	SHOOT = { Finesse = "ShotFinesse", Trivela = "ShotTrivela", Knuckle = "ShotKnuckle", Header = "Header" },
	PASS = { Through = "PassThrough", Lob = "PassLob" },
}

local function onKick(userId, action, charge, style)
	local _, p = charOf(userId)
	local key = KICK_KEYS[action]
	if p == localPlayer and key then
		local styled = STYLE_KEYS[action] and STYLE_KEYS[action][style]
		if styled and AC.Has("Actions", styled) then
			AC.Play("Actions", styled)
		else
			AC.Play("Actions", key)
		end
	end
end

local function onCatch(userId)
	local _, p = charOf(userId)
	if p == localPlayer then
		AC.Play("Actions", "GKCatch")
	end
end

function Animator.Init()
	Remotes.get("FeintApproved").OnClientEvent:Connect(onFeint)
	Remotes.get("TackleApproved").OnClientEvent:Connect(onTackle)
	Remotes.get("DiveApproved").OnClientEvent:Connect(onDive)
	Remotes.get("KickPlayed").OnClientEvent:Connect(onKick)
	Remotes.get("CatchPlayed").OnClientEvent:Connect(onCatch)
end

return Animator
