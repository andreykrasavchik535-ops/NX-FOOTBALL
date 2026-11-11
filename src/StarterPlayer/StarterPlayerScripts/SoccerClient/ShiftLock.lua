--[[
	StarterPlayerScripts/SoccerClient/ShiftLock (ModuleScript)
	Own shift lock that also works on phones: while it is on, the character always faces where the camera looks
	and the camera sits slightly over the shoulder. Toggle: LOCK button, key L, or ShiftLock.Toggle().
	(Roblox's built-in shift lock is switched off by the server, Main.server.lua, so the two never fight.)
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ShiftLock = {}
ShiftLock.Changed = Instance.new("BindableEvent")

local enabled = false
local started = false
local SHOULDER = Vector3.new(1.7, 0.2, 0)

function ShiftLock.IsEnabled()
	return enabled
end

local function release()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.CameraOffset = Vector3.new(0, 0, 0)
		if not hum:GetAttribute("NXSpin") then
			hum.AutoRotate = true
		end
	end
	if UserInputService.MouseEnabled then
		pcall(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end)
	end
end

local function step()
	if not enabled then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local cam = Workspace.CurrentCamera
	if not hum or not hrp or not cam or hum.Health <= 0 or hum.Sit then
		return
	end
	hum.CameraOffset = SHOULDER
	if UserInputService.MouseEnabled then
		pcall(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end)
	end
	if hum:GetAttribute("NXSpin") then
		return -- a feint spin is running, let it turn the body
	end
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	hum.AutoRotate = false
	hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
end

function ShiftLock.Set(value)
	value = value and true or false
	if value == enabled then
		return
	end
	enabled = value
	if not enabled then
		release()
	end
	ShiftLock.Changed:Fire(enabled)
end

function ShiftLock.Toggle()
	ShiftLock.Set(not enabled)
end

function ShiftLock.Init()
	if started then
		return
	end
	started = true
	RunService:BindToRenderStep("NXShiftLock", (Enum.RenderPriority.Camera.Value or 200) + 1, step)
end

return ShiftLock
