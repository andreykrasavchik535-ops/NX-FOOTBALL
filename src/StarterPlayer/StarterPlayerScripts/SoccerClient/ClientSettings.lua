--[[
	StarterPlayerScripts/SoccerClient/ClientSettings (ModuleScript)
	Holds the local player's current settings and broadcasts changes so every client
	module (sound, input, camera) can react. The server loads/saves them (SettingsService).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local SettingsDefs = require(Shared:WaitForChild("SettingsDefs"))

local ClientSettings = {}
ClientSettings.Current = SettingsDefs.Copy()
ClientSettings.Changed = Instance.new("BindableEvent")

function ClientSettings.Get()
	return ClientSettings.Current
end

function ClientSettings.Apply(settings)
	ClientSettings.Current = SettingsDefs.Validate(settings)
	ClientSettings.Changed:Fire(ClientSettings.Current)
end

return ClientSettings
