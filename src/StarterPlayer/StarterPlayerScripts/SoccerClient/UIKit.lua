--[[
	StarterPlayerScripts/SoccerClient/UIKit (ModuleScript)
	Small UI helpers and the visual theme (NX: Next Football).
]]
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("SoccerShared"):WaitForChild("Config"))

local UIKit = {}

UIKit.Theme = {
	-- RFX-style round buttons: near black, see-through, thin white outline, plain white text (no neon colours)
	btn = Color3.fromRGB(8, 10, 12),
	btnAlpha = 0.5,
	btnDown = Color3.fromRGB(70, 74, 78),
	line = Color3.fromRGB(255, 255, 255),
	lineAlpha = 0.72,
	bg = Color3.fromRGB(10, 14, 24),
	panel = Color3.fromRGB(18, 24, 38),
	panel2 = Color3.fromRGB(28, 36, 56),
	accent = Color3.fromRGB(232, 236, 240),
	gold = Color3.fromRGB(232, 236, 240),
	text = Color3.fromRGB(240, 245, 255),
	dim = Color3.fromRGB(150, 165, 190),
	red = Color3.fromRGB(235, 64, 64),
	blue = Color3.fromRGB(64, 128, 255),
	good = Color3.fromRGB(70, 220, 130),
	bad = Color3.fromRGB(255, 90, 90),
	info = Color3.fromRGB(120, 190, 255),
	categories = {
		Move = Color3.fromRGB(240, 242, 245),
		Spin = Color3.fromRGB(240, 242, 245),
		Flick = Color3.fromRGB(240, 242, 245),
		Fake = Color3.fromRGB(240, 242, 245),
		Push = Color3.fromRGB(240, 242, 245),
	},
}

-- thin, clean font (Gotham regular); UIKit.FONT_TITLE is a little heavier for big titles
UIKit.FONT = Enum.Font.Gotham
UIKit.FONT_TITLE = Enum.Font.GothamMedium

function UIKit.isTouch()
	return UserInputService.TouchEnabled
end

function UIKit.hasKeyboard()
	return UserInputService.KeyboardEnabled
end

-- Phone / tablet layout: touch screen and no physical keyboard.
function UIKit.isMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Base size unit scaled to the screen (phone friendly).
function UIKit.unit()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min(vp.X, vp.Y) * 0.11, 42, 84) * (Config.UI_SCALE or 1)
end

function UIKit.corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 10)
	c.Parent = inst
	return c
end

function UIKit.stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or UIKit.Theme.accent
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

function UIKit.frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = UIKit.Theme.panel
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

function UIKit.label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UIKit.FONT
	l.TextColor3 = UIKit.Theme.text
	l.TextScaled = false
	l.TextSize = 18
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function UIKit.button(parent, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Font = UIKit.FONT
	b.TextColor3 = UIKit.Theme.text
	b.BackgroundColor3 = UIKit.Theme.panel2
	b.TextSize = 16
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	b.Parent = parent
	return b
end

-- Press/hold handling that works for mouse and touch (including finger sliding off the button).
function UIKit.hold(btn, onDown, onUp)
	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			onDown(input)
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					conn:Disconnect()
					if onUp then
						onUp(input)
					end
				end
			end)
		end
	end)
end

-- Small player silhouette (head + shoulders) for the team cards. Returns the frame.
function UIKit.personIcon(parent, size, color, transparency)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(size, size)
	f.Parent = parent
	local head = Instance.new("Frame")
	head.BorderSizePixel = 0
	head.BackgroundColor3 = color
	head.BackgroundTransparency = transparency or 0
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0.02)
	head.Size = UDim2.fromScale(0.36, 0.36)
	head.Parent = f
	UIKit.corner(head, UDim.new(1, 0))
	local body = Instance.new("Frame")
	body.BorderSizePixel = 0
	body.BackgroundColor3 = color
	body.BackgroundTransparency = transparency or 0
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 0.98)
	body.Size = UDim2.fromScale(0.74, 0.46)
	body.Parent = f
	UIKit.corner(body, UDim.new(0.5, 0))
	return f
end

function UIKit.textLimit(label, minSize, maxSize)
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize
	c.MaxTextSize = maxSize
	c.Parent = label
	return c
end

return UIKit
