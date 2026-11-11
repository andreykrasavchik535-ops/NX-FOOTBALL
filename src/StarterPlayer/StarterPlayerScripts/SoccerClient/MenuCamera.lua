--[[
	StarterPlayerScripts/SoccerClient/MenuCamera (ModuleScript)
	A slow cinematic orbit around the stadium while the player is in the menu. It only
	runs in the lobby; when a match starts the normal character camera is restored.
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local MenuCamera = {}
local active = false
local conn
local angle = 0

function MenuCamera.Start()
	if active then
		return
	end
	active = true
	angle = 0
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	conn = RunService.RenderStepped:Connect(function(dt)
		angle = angle + dt * 0.08
		local target = Vector3.new(0, 40, 0)
		local radius = 1500
		local pos = target + Vector3.new(math.cos(angle) * radius, 520, math.sin(angle) * radius)
		cam.CFrame = CFrame.lookAt(pos, target)
	end)
end

function MenuCamera.Stop()
	if not active then
		return
	end
	active = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local p = Players.LocalPlayer
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
end

function MenuCamera.IsActive()
	return active
end

return MenuCamera
