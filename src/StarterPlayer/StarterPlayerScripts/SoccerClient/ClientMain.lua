--[[
	StarterPlayerScripts/SoccerClient/ClientMain (LocalScript)
	NX26 client entry point. Orchestrates:
	  menu (MainMenu / KickOffFlow / SettingsMenu)  <->  match (HUD + ActionBar + input).
	The menu is shown in the lobby with a cinematic camera; when a match starts the menu
	hides and the gameplay HUD / controls take over. Settings load from the server and
	apply to sound, input, camera and graphics.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local player = Players.LocalPlayer
ReplicatedStorage:WaitForChild("SoccerShared")
ReplicatedStorage:WaitForChild("SoccerRemotes", 15)
local stateFolder = ReplicatedStorage:WaitForChild("SoccerState", 15)

local C = script.Parent
local function load(name)
	local ok, m = pcall(function()
		return require(C:WaitForChild(name))
	end)
	if not ok then
		warn("[NX client] cannot load " .. name .. ": " .. tostring(m))
		return nil
	end
	return m
end
local function run(name, fn, ...)
	local ok, r = pcall(fn, ...)
	if not ok then
		warn("[NX client] " .. name .. " failed: " .. tostring(r))
		return nil
	end
	return r
end

local A = load("ActionClient")
local Remotes = load("Remotes")
local Hud = load("HudController")
local ActionBar = load("ActionBar")
local Input = load("InputController")
local AnimationController = load("AnimationController")
local FeintAnimator = load("FeintAnimator")
local ShiftLock = load("ShiftLock")
local MainMenu = load("MainMenu")
local KickOffFlow = load("KickOffFlow")
local SettingsMenu = load("SettingsMenu")
local MenuCamera = load("MenuCamera")
local SoundController = load("SoundController")
local ClientSettings = load("ClientSettings")

if A then run("ActionClient.Init", A.Init) end
if SoundController then run("SoundController.Init", SoundController.Init) end
if ShiftLock then run("ShiftLock.Init", ShiftLock.Init) end

-- Gameplay HUD + controls
local hudGui = Hud and run("HudController.Build", Hud.Build)
if ActionBar and hudGui then run("ActionBar.Build", ActionBar.Build, hudGui) end
if Input then run("InputController.Init", Input.Init) end
if AnimationController then run("AnimationController.Init", AnimationController.Init) end
if FeintAnimator then run("FeintAnimator.Init", FeintAnimator.Init) end

-- Menu
local menuGui = Instance.new("ScreenGui")
menuGui.Name = "NXMenu"
menuGui.ResetOnSpawn = false
menuGui.IgnoreGuiInset = true
menuGui.DisplayOrder = 10
menuGui.Enabled = false
menuGui.Parent = player:WaitForChild("PlayerGui")

local function toast(kind, text)
	if A then A.Toast:Fire(kind, text) end
end

if MainMenu then
	run("MainMenu.Build", MainMenu.Build, menuGui, {
		KickOff = function()
			MainMenu.Hide()
			if KickOffFlow then KickOffFlow.Show() end
		end,
		Settings = function()
			MainMenu.Hide()
			if SettingsMenu then SettingsMenu.Show() end
		end,
		Toast = toast,
	})
end
if KickOffFlow then
	run("KickOffFlow.Build", KickOffFlow.Build, menuGui, {
		Back = function()
			KickOffFlow.Hide()
			if MainMenu then MainMenu.Show() end
		end,
		Toast = toast,
	})
end
if SettingsMenu then
	run("SettingsMenu.Build", SettingsMenu.Build, menuGui, {
		Back = function()
			SettingsMenu.Hide()
			if MainMenu then MainMenu.Show() end
		end,
	})
end

-- Settings: load from server, apply everywhere
local function applySettings(s)
	if SoundController then SoundController.SetVolumes(s.Volume) end
	if Input and Input.SetBindings then Input.SetBindings(s.Controls) end
	if ShiftLock then ShiftLock.Set(s.Camera.ShiftLock) end
	pcall(function()
		UserGameSettings.MouseSensitivity = s.Camera.Sensitivity
	end)
	pcall(function()
		local q = s.Graphics.Quality
		if q == "Low" then
			UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
		elseif q == "Medium" then
			UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel5
		elseif q == "High" then
			UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel10
		else
			UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.Automatic
		end
	end)
end
if ClientSettings then
	ClientSettings.Changed:Connect(applySettings)
	applySettings(ClientSettings.Get())
end
if Remotes then
	Remotes.get("SettingsSync").OnClientEvent:Connect(function(msg)
		if type(msg) == "table" and msg.action == "Load" and ClientSettings then
			ClientSettings.Apply(msg.settings)
		end
	end)
end

-- State-driven switching between menu and match
local function isLobby(st)
	return st == "Lobby" or st == "Waiting" or st == nil
end
local function isMatch(st)
	return st == "Kickoff" or st == "Live" or st == "HalfTime" or st == "GoalPause" or st == "Intermission"
end
local function onState()
	local st = stateFolder:GetAttribute("State")
	if isLobby(st) then
		menuGui.Enabled = true
		if hudGui then hudGui.Enabled = false end
		if ActionBar and ActionBar.SetActive then ActionBar.SetActive(false) end
		if Input and Input.SetEnabled then Input.SetEnabled(false) end
		if MenuCamera then MenuCamera.Start() end
		local kickVisible = KickOffFlow and KickOffFlow.IsVisible and KickOffFlow.IsVisible()
		local setVisible = SettingsMenu and SettingsMenu.IsVisible and SettingsMenu.IsVisible()
		if not kickVisible and not setVisible and MainMenu then
			MainMenu.Show()
		end
	else
		if MainMenu then MainMenu.Hide() end
		if KickOffFlow then KickOffFlow.Hide() end
		if SettingsMenu then SettingsMenu.Hide() end
		menuGui.Enabled = false
		if hudGui then hudGui.Enabled = true end
		if MenuCamera then MenuCamera.Stop() end
		if ActionBar and ActionBar.SetActive then ActionBar.SetActive(isMatch(st)) end
		if Input and Input.SetEnabled then Input.SetEnabled(isMatch(st)) end
	end
end
stateFolder:GetAttributeChangedSignal("State"):Connect(onState)
onState()

print("[NX: Next Football] client started (menu + match)")
