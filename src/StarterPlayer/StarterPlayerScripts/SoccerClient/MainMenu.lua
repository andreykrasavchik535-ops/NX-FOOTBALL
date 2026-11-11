--[[
	StarterPlayerScripts/SoccerClient/MainMenu (ModuleScript)
	The NX26 main menu: KICK OFF, ULTIMATE TEAM, CAREER, CLUBS, SETTINGS.
	ULTIMATE TEAM / CAREER / CLUBS are marked COMING SOON and are genuinely disabled.
	Modern look, animated transitions, PC hover, touch and gamepad navigation, adaptive layout.
]]
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local T = UIKit.Theme
local MainMenu = {}

local gui, root
local buttons = {}
local selection = 1
local visible = false
local onKickOff, onSettings

local ITEMS = {
	{ id = "kickoff", text = "KICK OFF", soon = false },
	{ id = "ultimate", text = "ULTIMATE TEAM", soon = true },
	{ id = "career", text = "CAREER", soon = true },
	{ id = "clubs", text = "CLUBS", soon = true },
	{ id = "settings", text = "SETTINGS", soon = false },
}

local function tween(inst, props, t)
	TweenService:Create(inst, TweenInfo.new(t or 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function refreshSelection()
	for i, b in ipairs(buttons) do
		local sel = (i == selection)
		local soon = ITEMS[i].soon
		tween(b.btn, {
			BackgroundColor3 = sel and T.panel2 or T.panel,
			BackgroundTransparency = sel and 0.05 or 0.35,
		})
		tween(b.bar, { BackgroundTransparency = sel and 0 or 1 })
		b.btn.TextColor3 = soon and T.dim or T.text
	end
end

local function activate(i)
	local item = ITEMS[i]
	if not item then
		return
	end
	if item.soon then
		SoundController.Click()
		if MainMenu.Toast then
			MainMenu.Toast("info", item.text .. " - COMING SOON")
		end
		return
	end
	SoundController.Click()
	if item.id == "kickoff" and onKickOff then
		onKickOff()
	elseif item.id == "settings" and onSettings then
		onSettings()
	end
end

local function moveSelection(d)
	local n = #ITEMS
	selection = ((selection - 1 + d) % n) + 1
	refreshSelection()
	SoundController.Hover()
end

function MainMenu.Build(parent, callbacks)
	gui = parent
	onKickOff = callbacks.KickOff
	onSettings = callbacks.Settings
	MainMenu.Toast = callbacks.Toast

	root = Instance.new("CanvasGroup")
	root.Name = "MainMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui
	local u = UIKit.unit()

	-- subtle dark gradient backdrop so text reads over the stadium
	local bg = UIKit.frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, ZIndex = 1 })
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 0.45),
	})
	grad.Parent = bg

	UIKit.label(root, {
		Text = "NX26", Font = UIKit.FONT_TITLE, TextSize = math.floor(u * 1.4), TextColor3 = T.text,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08, 0),
		Size = UDim2.fromOffset(u * 8, u * 1.5), ZIndex = 2, TextStrokeTransparency = 0.6,
	})
	UIKit.label(root, {
		Text = "N E X T   F O O T B A L L", Font = UIKit.FONT, TextSize = math.floor(u * 0.3),
		TextColor3 = T.dim, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08 + 0.001, u * 1.5),
		Size = UDim2.fromOffset(u * 8, u * 0.5), ZIndex = 2,
	})

	local bw = math.clamp(u * 5.2, 260, 460)
	local bh = math.clamp(u * 0.72, 44, 64)
	local gap = math.floor(u * 0.16)
	local list = UIKit.frame(root, {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.56, 0), Size = UDim2.fromOffset(bw, #ITEMS * bh + (#ITEMS - 1) * gap), ZIndex = 2,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list

	for i, item in ipairs(ITEMS) do
		local b = UIKit.button(list, {
			Text = item.text .. (item.soon and "   (COMING SOON)" or ""),
			Size = UDim2.fromOffset(bw, bh), LayoutOrder = i,
			BackgroundColor3 = T.panel, BackgroundTransparency = 0.35,
			TextSize = math.floor(bh * 0.36), Font = UIKit.FONT_TITLE, ZIndex = 3,
		})
		UIKit.corner(b, UDim.new(0, 12))
		UIKit.stroke(b, T.line, 1.2, 0.75)
		local bar = UIKit.frame(b, {
			Name = "SelBar", BackgroundColor3 = T.accent, BackgroundTransparency = 1,
			Size = UDim2.new(0, 4, 0.6, 0), Position = UDim2.new(0, 8, 0.2, 0), ZIndex = 4,
		})
		UIKit.corner(bar, UDim.new(1, 0))
		buttons[i] = { btn = b, bar = bar }
		b.Activated:Connect(function()
			selection = i
			refreshSelection()
			activate(i)
		end)
		b.MouseEnter:Connect(function()
			if not UIKit.isMobile() then
				selection = i
				refreshSelection()
				SoundController.Hover()
			end
		end)
	end

	UIKit.label(root, {
		Text = "Arrow keys / D-pad to navigate, Enter / A to select", TextSize = math.floor(u * 0.2),
		TextColor3 = T.dim, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.98, 0),
		Size = UDim2.fromOffset(u * 8, u * 0.4), ZIndex = 2,
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if not visible or processed then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Up or k == Enum.KeyCode.DPadUp then
			moveSelection(-1)
		elseif k == Enum.KeyCode.Down or k == Enum.KeyCode.DPadDown then
			moveSelection(1)
		elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA then
			activate(selection)
		end
	end)

	refreshSelection()
	return root
end

function MainMenu.Show()
	if not root then
		return
	end
	visible = true
	root.Visible = true
	root.GroupTransparency = 1
	tween(root, { GroupTransparency = 0 }, 0.3)
	refreshSelection()
end

function MainMenu.Hide()
	visible = false
	if root then
		root.Visible = false
	end
end

function MainMenu.IsVisible()
	return visible
end

return MainMenu
