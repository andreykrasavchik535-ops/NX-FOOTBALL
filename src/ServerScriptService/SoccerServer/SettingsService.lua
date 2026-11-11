--[[
	ServerScriptService/SoccerServer/SettingsService (ModuleScript)
	Persists player settings with DataStore, but ONLY when it is actually available.
	Every DataStore call is wrapped in pcall; if the store is unavailable (unpublished
	place, Studio without API access, throttling) the game keeps working with session
	settings and says so in Output. A failed load NEVER overwrites saved data with
	defaults. Saves are validated (SettingsDefs) and rate-limited.
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local SettingsDefs = require(Shared:WaitForChild("SettingsDefs"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SettingsService = {}
local store
local storeOk = false
local buckets = {}

local ok, err = pcall(function()
	store = DataStoreService:GetDataStore("NX26_Settings_v1")
end)
storeOk = ok and store ~= nil
if not storeOk then
	warn("[NX] Settings DataStore unavailable (" .. tostring(err) .. "). Settings are session-only until the game is published with API access.")
end

local function key(userId)
	return "u_" .. tostring(userId)
end

local function load(player)
	local saved = nil
	if storeOk then
		local okGet, res = pcall(function()
			return store:GetAsync(key(player.UserId))
		end)
		if okGet and type(res) == "table" then
			saved = res
		end
	end
	local settings = SettingsDefs.Validate(saved)
	Remotes.get("SettingsSync"):FireClient(player, { action = "Load", settings = settings })
end

local function save(player, raw)
	local settings = SettingsDefs.Validate(raw)
	if not storeOk then
		return
	end
	task.spawn(function()
		local okSet, e = pcall(function()
			store:UpdateAsync(key(player.UserId), function()
				return settings
			end)
		end)
		if not okSet then
			warn("[NX] settings save failed for " .. player.UserId .. ": " .. tostring(e))
		end
	end)
end

function SettingsService.Init()
	Remotes.get("SettingsSync").OnServerEvent:Connect(function(player, msg)
		local b = buckets[player]
		if not b or not b:take() or type(msg) ~= "table" then
			return
		end
		if msg.action == "Save" then
			save(player, msg.settings)
		end
	end)
	local function add(player)
		buckets[player] = Util.newBucket(1, 3)
		task.spawn(load, player)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		add(p)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

return SettingsService
