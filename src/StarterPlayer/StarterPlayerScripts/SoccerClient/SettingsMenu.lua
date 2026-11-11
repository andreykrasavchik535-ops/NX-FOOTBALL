--[[
	StarterPlayerScripts/SoccerClient/SettingsMenu (ModuleScript)
	Volume, camera, sensitivity, graphics and key rebinds. Changes apply immediately and
	are sent to the server to persist (SettingsSync). Works with touch, mouse and gamepad.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local SettingsDefs = require(Shared:WaitForChild("SettingsDefs"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local T = UIKit.Theme
local SettingsMenu = {}
local gui, root, visible = false, nil, false
local onBack
local rows = {}
local rebinding = nil

local function settings()
	return ClientSettings.Get()
end

local function commit()
	local s = settings()
	ClientSettings.Apply(s)
	Remotes.get("SettingsSync"):FireServer({ action = "Save", settings = s })
end

local function mutate(fn)
	fn(settings())
	commit()
	SoundController.Click()
end

local function stepper(parent, label, u, get, set, min, max, step)
	local row = UIKit.frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, u * 0.6), LayoutOrder = #parent:GetChildren() + 1 })
	UIKit.label(row, { Text = label, TextSize = math.floor(u * 0.24), Size = UDim2.new(0.45, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left })
	local minus = UIKit.button(row, { Text = "-", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.45, 0, 0.5, 0), Size = UDim2.fromOffset(u * 0.5, u * 0.5), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.3) })
	UIKit.corner(minus, UDim.new(0, 8))
	local val = UIKit.label(row, { Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.62, 0, 0.5, 0), Size = UDim2.fromOffset(u * 0.9, u * 0.5), TextSize = math.floor(u * 0.24) })
	local plus = UIKit.button(row, { Text = "+", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.95, 0, 0.5, 0), Size = UDim2.fromOffset(u * 0.5, u * 0.5), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.3) })
	UIKit.corner(plus, UDim.new(0, 8))
	local function refresh()
		val.Text = string.format("%.1f", get())
	end
	minus.Activated:Connect(function()
		mutate(function(s) set(s, math.max(min, get() - step)) end)
		refresh()
	end)
	plus.Activated:Connect(function()
		mutate(function(s) set(s, math.min(max, get() + step)) end)
		refresh()
	end)
	refresh()
	table.insert(rows, refresh)
	return row
end

local function build()
	if root then root:Destroy() end
	rows = {}
	local u = UIKit.unit()
	root = Instance.new("CanvasGroup")
	root.Name = "SettingsMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui
	UIKit.frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, ZIndex = 1 })

	local panelW = math.clamp(u * 8, 320, 680)
	local panel = UIKit.frame(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(panelW, math.min(u * 8, 620)), BackgroundColor3 = T.bg, BackgroundTransparency = 0.05, ZIndex = 2 })
	UIKit.corner(panel, UDim.new(0, 16))
	UIKit.stroke(panel, T.accent, 1.5, 0.4)
	UIKit.label(panel, { Text = "SETTINGS", Font = UIKit.FONT_TITLE, TextSize = math.floor(u * 0.5), Size = UDim2.new(1, 0, 0, u * 0.7), Position = UDim2.fromOffset(0, u * 0.12), ZIndex = 3 })
	local back = UIKit.button(panel, { Text = "BACK", Position = UDim2.fromOffset(12, u * 0.16), Size = UDim2.fromOffset(u * 1.2, u * 0.45), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.22), ZIndex = 3 })
	UIKit.corner(back, UDim.new(0, 8))
	back.Activated:Connect(function()
		SoundController.Click()
		if onBack then onBack() end
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, u * 0.95)
	scroll.Size = UDim2.new(1, -32, 1, -(u * 1.2))
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ScrollBarThickness = 4
	scroll.ZIndex = 3
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local function head(text)
		local l = UIKit.label(scroll, { Text = text, Font = UIKit.FONT_TITLE, TextSize = math.floor(u * 0.28), TextColor3 = T.accent, Size = UDim2.new(1, 0, 0, u * 0.45), LayoutOrder = #scroll:GetChildren() + 1 })
		return l
	end

	head("VOLUME")
	stepper(scroll, "Master", u, function() return settings().Volume.Master end, function(s, v) s.Volume.Master = v end, 0, 1, 0.1)
	stepper(scroll, "Music", u, function() return settings().Volume.Music end, function(s, v) s.Volume.Music = v end, 0, 1, 0.1)
	stepper(scroll, "SFX", u, function() return settings().Volume.SFX end, function(s, v) s.Volume.SFX = v end, 0, 1, 0.1)
	stepper(scroll, "Crowd", u, function() return settings().Volume.Crowd end, function(s, v) s.Volume.Crowd = v end, 0, 1, 0.1)

	head("CAMERA")
	stepper(scroll, "Sensitivity", u, function() return settings().Camera.Sensitivity end, function(s, v) s.Camera.Sensitivity = v end, 0.2, 3.0, 0.1)
	local lockRow = UIKit.frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, u * 0.6), LayoutOrder = #scroll:GetChildren() + 1 })
	UIKit.label(lockRow, { Text = "Shift Lock", TextSize = math.floor(u * 0.24), Size = UDim2.new(0.45, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left })
	local lockBtn = UIKit.button(lockRow, { Text = "OFF", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.95, 0, 0.5, 0), Size = UDim2.fromOffset(u * 1.2, u * 0.5), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.24) })
	UIKit.corner(lockBtn, UDim.new(0, 8))
	local function refreshLock()
		lockBtn.Text = settings().Camera.ShiftLock and "ON" or "OFF"
	end
	lockBtn.Activated:Connect(function()
		mutate(function(s) s.Camera.ShiftLock = not s.Camera.ShiftLock end)
		refreshLock()
	end)
	refreshLock()
	table.insert(rows, refreshLock)

	head("GRAPHICS")
	local qRow = UIKit.frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, u * 0.6), LayoutOrder = #scroll:GetChildren() + 1 })
	local qButtons = {}
	for i, q in ipairs({ "Auto", "Low", "Medium", "High" }) do
		local b = UIKit.button(qRow, { Text = q, Size = UDim2.fromOffset(u * 1.3, u * 0.5), Position = UDim2.fromOffset((i - 1) * (u * 1.4), 0), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.22) })
		UIKit.corner(b, UDim.new(0, 8))
		b.Activated:Connect(function()
			mutate(function(s) s.Graphics.Quality = q end)
			for _, bb in ipairs(qButtons) do bb.BackgroundColor3 = T.panel2 end
			b.BackgroundColor3 = T.panel
		end)
		table.insert(qButtons, b)
	end

	head("CONTROLS (click, then press a key)")
	local actions = { "Shoot", "Pass", "Long", "Tackle", "Slide", "Sprint", "Lock", "Side", "FeintPanel", "DiveLeft", "DiveRight" }
	for _, action in ipairs(actions) do
		local row = UIKit.frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, u * 0.55), LayoutOrder = #scroll:GetChildren() + 1 })
		UIKit.label(row, { Text = action, TextSize = math.floor(u * 0.22), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left })
		local b = UIKit.button(row, { Text = settings().Controls[action] or "?", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.95, 0, 0.5, 0), Size = UDim2.fromOffset(u * 1.8, u * 0.48), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.22) })
		UIKit.corner(b, UDim.new(0, 8))
		b.Activated:Connect(function()
			rebinding = action
			b.Text = "press a key..."
			b.BackgroundColor3 = T.panel
		end)
		table.insert(rows, function()
			if rebinding ~= action then
				b.Text = settings().Controls[action] or "?"
				b.BackgroundColor3 = T.panel2
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not rebinding or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local keyName = input.KeyCode.Name
			local action = rebinding
			rebinding = nil
			mutate(function(s) s.Controls[action] = keyName end)
			for _, r in ipairs(rows) do r() end
		end
	end)
end

function SettingsMenu.Build(parent, callbacks)
	gui = parent
	onBack = callbacks.Back
	build()
	ClientSettings.Changed:Connect(function()
		for _, r in ipairs(rows) do r() end
	end)
	return root
end

function SettingsMenu.Show()
	if not root then return end
	visible = true
	root.Visible = true
	root.GroupTransparency = 1
	TweenService:Create(root, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	for _, r in ipairs(rows) do r() end
end

function SettingsMenu.Hide()
	visible = false
	rebinding = nil
	if root then root.Visible = false end
end

return SettingsMenu
