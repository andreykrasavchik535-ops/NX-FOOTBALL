--[[
	StarterPlayerScripts/SoccerClient/ClientMain (LocalScript)
	Starts the client: HUD, on-screen controls, keyboard/gamepad input, animations.
	Each stage is protected, so a failing stage is reported in Output but the buttons still appear.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("SoccerShared")
ReplicatedStorage:WaitForChild("SoccerRemotes", 15)
ReplicatedStorage:WaitForChild("SoccerState", 15)

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
local Hud = load("HudController")
local ActionBar = load("ActionBar")
local Input = load("InputController")
local AnimationController = load("AnimationController")
local FeintAnimator = load("FeintAnimator")
local ShiftLock = load("ShiftLock")

if A then run("ActionClient.Init", A.Init) end
local gui = Hud and run("HudController.Build", Hud.Build)
if ActionBar and gui then run("ActionBar.Build", ActionBar.Build, gui) end
if ShiftLock then run("ShiftLock.Init", ShiftLock.Init) end
if Input then run("InputController.Init", Input.Init) end
if AnimationController then run("AnimationController.Init", AnimationController.Init) end
if FeintAnimator then run("FeintAnimator.Init", FeintAnimator.Init) end
