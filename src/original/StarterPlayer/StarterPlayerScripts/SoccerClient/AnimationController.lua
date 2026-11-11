--[[
	StarterPlayerScripts/SoccerClient/AnimationController (ModuleScript)

	Plays animations from SoccerShared/AnimationIds on the LOCAL player's character through its Animator.
	Roblox replicates animations played by the owner of a character to everybody, so every other player sees
	them without any extra work (and nobody plays a second copy, which would double-blend).

	* An empty / invalid slot is simply skipped: Play() returns false and the game keeps working
	  (default Roblox animation, optional text popup from FeintAnimator).
	* Locomotion: RunNoBall / RunBall (/ IdleBall) are chosen automatically from the player's speed and the
	  server attribute HasBall. They use Movement priority, so they override the default Roblox run animation
	  and are overridden by every Action animation (kick, feint, tackle).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local AnimationIds = require(Shared:WaitForChild("AnimationIds"))

local player = Players.LocalPlayer
local AC = {}

local trackCache = setmetatable({}, { __mode = "k" }) -- [character] = { [animId] = track }
local warned = {}
local loco = { key = nil, track = nil }

local function priorityOf(name)
	local ok, value = pcall(function()
		return Enum.AnimationPriority[name]
	end)
	return ok and value or Enum.AnimationPriority.Action
end

local function getAnimator(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = hum:WaitForChild("Animator", 2)
	end
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

local function loadTrack(char, animId, settings, label)
	local animator = getAnimator(char)
	if not animator then
		return nil
	end
	local cache = trackCache[char]
	if not cache then
		cache = {}
		trackCache[char] = cache
	end
	local track = cache[animId]
	if track then
		return track
	end
	local anim = Instance.new("Animation")
	anim.Name = label
	anim.AnimationId = animId
	local ok, loaded = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not loaded then
		if not warned[animId] then
			warned[animId] = true
			warn("[NX Animations] could not load " .. label .. " (" .. animId .. ")")
		end
		return nil
	end
	loaded.Priority = priorityOf(settings.Priority)
	loaded.Looped = settings.Looped and true or false
	cache[animId] = loaded
	-- an id that is wrong or not owned by the game creator loads with length 0: tell the developer once
	task.delay(4, function()
		if loaded.Length == 0 and not warned[animId] then
			warned[animId] = true
			warn("[NX Animations] " .. label .. " (" .. animId .. ") has length 0: wrong id, or the animation is not owned by the game's creator/group.")
		end
	end)
	return loaded
end

-- True if an animation id is set (and well formed) for this slot.
function AC.Has(group, key, side)
	return AnimationIds.Get(group, key, side) ~= nil
end

-- Plays group/key on the local character. Returns the track or nil (slot empty / not loadable). Never throws.
function AC.Play(group, key, side, speedMul)
	local ok, track = pcall(function()
		local id = AnimationIds.Get(group, key, side)
		if not id then
			return nil
		end
		local char = player.Character
		if not char then
			return nil
		end
		local settings = AnimationIds.GetSettings(group, key)
		local t = loadTrack(char, id, settings, group .. "." .. key)
		if not t then
			return nil
		end
		t:Play(settings.FadeIn, settings.Weight, (settings.Speed or 1) * (speedMul or 1))
		return t
	end)
	if ok then
		return track
	end
	return nil
end

function AC.Stop(group, key, side)
	local id = AnimationIds.Get(group, key, side)
	local char = player.Character
	local cache = char and trackCache[char]
	local track = id and cache and cache[id]
	if track then
		track:Stop(AnimationIds.GetSettings(group, key).FadeOut)
	end
end

-- Locomotion ---------------------------------------------------------------------------------------------------------

local function stopLoco()
	if loco.track then
		local settings = AnimationIds.GetSettings("Locomotion", loco.key or "RunNoBall")
		pcall(function() loco.track:Stop(settings.FadeOut) end)
	end
	loco.key, loco.track = nil, nil
end

local function chooseLocoKey(moving, hasBall)
	if moving then
		if hasBall and AC.Has("Locomotion", "RunBall") then
			return "RunBall"
		end
		if AC.Has("Locomotion", "RunNoBall") then
			return "RunNoBall"
		end
		return nil
	end
	if hasBall and AC.Has("Locomotion", "IdleBall") then
		return "IdleBall"
	end
	return nil
end

local function updateLocomotion()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		stopLoco()
		return
	end
	local state = hum:GetState()
	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Flying or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.Ragdoll
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local threshold = loco.key and Config.ANIM_RUN_STOP_SPEED or Config.ANIM_RUN_START_SPEED
	local moving = speed >= threshold and hum.MoveDirection.Magnitude > 0.05 and not airborne
	local hasBall = player:GetAttribute("HasBall") == true
	local want = (not airborne) and chooseLocoKey(moving, hasBall) or nil

	if want ~= loco.key or (loco.track and not loco.track.IsPlaying) then
		stopLoco()
		if want then
			local settings = AnimationIds.GetSettings("Locomotion", want)
			local id = AnimationIds.Get("Locomotion", want)
			local track = id and loadTrack(char, id, settings, "Locomotion." .. want)
			if track then
				track:Play(settings.FadeIn, settings.Weight, 1)
				loco.key, loco.track = want, track
			end
		end
	end
	if loco.track and loco.key ~= "IdleBall" then
		local settings = AnimationIds.GetSettings("Locomotion", loco.key)
		local ref = math.max(settings.ReferenceSpeed or 20, 1)
		loco.track:AdjustSpeed(math.clamp(speed / ref, 0.5, 1.8) * (settings.Speed or 1))
	end
end

function AC.Init()
	local missing, total = AnimationIds.ListMissing()
	if #missing == 0 then
		print("[NX Animations] all " .. total .. " animation slots are filled")
	else
		print(string.format("[NX Animations] %d of %d slots are empty (game works without them). Fill SoccerShared/AnimationIds.", #missing, total))
	end
	player.CharacterAdded:Connect(function()
		loco.key, loco.track = nil, nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.05 then
			return
		end
		acc = 0
		local ok, err = pcall(updateLocomotion)
		if not ok and not warned.loco then
			warned.loco = true
			warn("[NX Animations] locomotion error: " .. tostring(err))
		end
	end)
end

return AC
