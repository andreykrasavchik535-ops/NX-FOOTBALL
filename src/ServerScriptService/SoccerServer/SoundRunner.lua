--[[
	ServerScriptService/SoccerServer/SoundRunner (ModuleScript)
	World sounds for match events using SoccerShared/SoundIds. Every slot is optional:
	an empty id is skipped, so the game never errors when no sounds are set. UI sounds
	are handled on the client (SoundController); this module only does world sounds.
]]
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local SoundIds = require(Shared:WaitForChild("SoundIds"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BallService = require(script.Parent:WaitForChild("BallService"))

local SoundRunner = {}

local function makeSound(key, parent)
	local id = SoundIds.Get(key)
	if not id then
		return nil
	end
	local st = SoundIds.GetSettings(key)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = st.Volume
	s.Looped = st.Loop
	s.Parent = parent
	return s
end

local function playGlobal(key)
	local s = makeSound(key, SoundService)
	if not s then
		return
	end
	s:Play()
	if not s.Looped then
		task.delay(5, function()
			s:Destroy()
		end)
	end
	return s
end

local function playAtBall(key)
	local ball = BallService.GetBall()
	if not ball then
		return
	end
	local s = makeSound(key, ball)
	if not s then
		return
	end
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 220
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

local function isPostPart(part)
	local n = part.Name
	return string.find(n, "Post") == 1 or string.find(n, "Bar") == 1
end

function SoundRunner.Init()
	Remotes.get("KickPlayed").OnServerEvent:Connect(function(_, action)
		if action == "PASS" then
			playAtBall("Pass")
		else
			playAtBall("Kick")
		end
	end)
	Remotes.get("CatchPlayed").OnServerEvent:Connect(function()
		playAtBall("Save")
	end)
	Remotes.get("GoalScored").OnServerEvent:Connect(function()
		playGlobal("Goal")
		task.delay(0.4, function()
			playGlobal("Whistle")
		end)
	end)
	task.spawn(function()
		local ball = BallService.GetBall()
		while not ball do
			task.wait(0.5)
			ball = BallService.GetBall()
		end
		ball.Touched:Connect(function(part)
			if isPostPart(part) then
				playAtBall("Post")
			end
		end)
	end)
	local stateFolder = ReplicatedStorage:WaitForChild("SoccerState")
	stateFolder:GetAttributeChangedSignal("State"):Connect(function()
		local st = stateFolder:GetAttribute("State")
		if st == "Kickoff" or st == "HalfTime" or st == "Results" then
			playGlobal("Whistle")
		end
	end)
	playGlobal("Crowd")
end

return SoundRunner
