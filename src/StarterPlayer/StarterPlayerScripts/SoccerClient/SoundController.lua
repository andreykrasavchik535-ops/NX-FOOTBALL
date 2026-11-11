--[[
	StarterPlayerScripts/SoccerClient/SoundController (ModuleScript)
	UI sounds (click / hover) using SoccerShared/SoundIds, scaled by the player's volume
	settings. Empty sound slots are skipped safely. World sounds are played by the server
	(SoundRunner); this module only handles the interface.
]]
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local SoundIds = require(Shared:WaitForChild("SoundIds"))

local SoundController = {}
local master = 0.8
local sfx = 0.8

local uiGroup
local function ensureGroup()
	if not uiGroup then
		uiGroup = Instance.new("SoundGroup")
		uiGroup.Name = "NXUI"
		uiGroup.Parent = SoundService
	end
	return uiGroup
end

local function playUI(key)
	local id = SoundIds.Get(key)
	if not id then
		return
	end
	local st = SoundIds.GetSettings(key)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = st.Volume
	s.SoundGroup = ensureGroup()
	s.Parent = SoundService
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end

function SoundController.Click()
	playUI("UIClick")
end

function SoundController.Hover()
	playUI("UIHover")
end

function SoundController.SetVolumes(volume)
	if type(volume) ~= "table" then
		return
	end
	master = volume.Master or master
	sfx = volume.SFX or sfx
	ensureGroup().Volume = master * sfx
end

function SoundController.Init()
	ensureGroup().Volume = master * sfx
end

return SoundController
