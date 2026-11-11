--[[
	StarterPlayerScripts/SoccerClient/ActionBar (ModuleScript)
	On-screen controls in an RFX-like style: dark see-through round buttons, thin white outline, plain white text.
	Everything is sized from UIKit.unit() and rebuilt when the screen size changes.

	  bottom centre   MODE TABS:  Shoot | Dribbling | Pass | Defend   (+ a small Side chip)
	  right side      round buttons of the ACTIVE mode:
	                    Shoot      Normal Shot, Finesse, Trivela, Knuckle Shot, Header   (hold = charge, release = shoot)
	                    Dribbling  every feint / skill (no cooldowns, they also work without the ball)
	                    Pass       Pass, Through, Lob, Long Pass                         (hold = charge, release = pass)
	                    Defend     Tackle, Slide tackle
	  left column     Sprint (tap = on, tap = off) | Lock (shift lock) | Skills (hide / show the round buttons)
	  keeper only     Dive L / Dive R above the tabs
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("FeintDefs"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local A = require(script.Parent:WaitForChild("ActionClient"))
local Input = require(script.Parent:WaitForChild("InputController"))
local ShiftLock = require(script.Parent:WaitForChild("ShiftLock"))

local T = UIKit.Theme
local player = Players.LocalPlayer
local ActionBar = {}

local gui, root
local panelOpen = Config.UI_FEINT_DOCK_OPEN ~= false
local mode = Config.UI_DEFAULT_MODE or "Dribble"
local sideChip
local panels = {}       -- [modeId] = frame with the round buttons
local modeTabs = {}     -- [modeId] = tab button
local mainButtons = {}  -- [name] = { btn, overlay, bar, action, key }
local feintButtons = {} -- [id] = { btn, label }
local toggles = {}      -- sprint / lock buttons
local diveRow
local heartbeatConn, connected = nil, false

local MODES = {
	{ id = "Shoot", text = "Shoot" },
	{ id = "Dribble", text = "Dribbling" },
	{ id = "Pass", text = "Pass" },
	{ id = "Defend", text = "Defend" },
}

-- Buttons of the modes that are not feints. kind: "charge" (hold / release) or "tackle".
local ITEMS = {
	Shoot = {
		{ id = "Shot_Normal", text = "Normal Shot", kind = "charge", action = "SHOOT", style = "Normal", hint = "F" },
		{ id = "Shot_Finesse", text = "Finesse", kind = "charge", action = "SHOOT", style = "Finesse" },
		{ id = "Shot_Trivela", text = "Trivela", kind = "charge", action = "SHOOT", style = "Trivela" },
		{ id = "Shot_Knuckle", text = "Knuckle Shot", kind = "charge", action = "SHOOT", style = "Knuckle" },
		{ id = "Shot_Header", text = "Header", kind = "charge", action = "SHOOT", style = "Header" },
	},
	Pass = {
		{ id = "Pass_Normal", text = "Pass", kind = "charge", action = "PASS", style = "Normal", hint = "E" },
		{ id = "Pass_Through", text = "Through", kind = "charge", action = "PASS", style = "Through" },
		{ id = "Pass_Lob", text = "Lob", kind = "charge", action = "PASS", style = "Lob" },
		{ id = "Pass_Long", text = "Long Pass", kind = "charge", action = "LONG", style = "Normal", hint = "R" },
	},
	Defend = {
		{ id = "Tackle_Fast", text = "Tackle", kind = "tackle", tackle = "Fast", hint = "Q" },
		{ id = "Tackle_Slide", text = "Slide", kind = "tackle", tackle = "Slide", hint = "X" },
	},
}

local function addOverlay(btn, round)
	local o = UIKit.frame(btn, { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), ZIndex = btn.ZIndex + 2, Visible = false })
	UIKit.corner(o, round and UDim.new(1, 0) or UDim.new(0, 12))
	return o
end

-- One look for every button: near-black, see-through, thin white outline, white text.
local function skin(b, round, textSize)
	b.BackgroundColor3 = T.btn
	b.BackgroundTransparency = T.btnAlpha
	b.TextColor3 = T.text
	b.TextSize = textSize
	b.TextStrokeTransparency = 1
	UIKit.corner(b, round and UDim.new(1, 0) or UDim.new(0, 14))
	UIKit.stroke(b, T.line, 1.3, T.lineAlpha)
end

local function roundButton(parent, text, size, name)
	local b = UIKit.button(parent, { Text = text, Size = UDim2.fromOffset(size, size), ZIndex = 5 })
	skin(b, true, math.max(10, math.floor(size * 0.27)))
	b.TextWrapped = true
	if name then
		b.Name = name
	end
	return b
end

local function pillButton(parent, text, w, h, name)
	local b = UIKit.button(parent, { Text = text, Size = UDim2.fromOffset(w, h), ZIndex = 5 })
	skin(b, false, math.max(11, math.floor(h * 0.46)))
	b.Name = name
	return b
end

local function press(btn, down)
	btn.BackgroundColor3 = down and T.btnDown or T.btn
	btn.BackgroundTransparency = down and 0.2 or T.btnAlpha
end

local function applyPanelVisibility()
	for id, f in pairs(panels) do
		f.Visible = panelOpen and id == mode
	end
end

function ActionBar.TogglePanel()
	panelOpen = not panelOpen
	applyPanelVisibility()
end

function ActionBar.SetMode(id)
	if panels[id] then
		mode = id
		panelOpen = true
		applyPanelVisibility()
	end
end

local function refreshSideChip()
	if sideChip then
		sideChip.Text = A.Side == 1 and "Side: R" or "Side: L"
	end
end

local function updateGKVisibility()
	if diveRow then
		diveRow.Visible = A.IsGK()
	end
end

-- A grid of round buttons (no panel behind them). `count` decides columns and cell size, so every mode uses the
-- same cell size. Returns the frame and the cell size.
local function gridFrame(name, cell, cols, rows, pad, topInset)
	local w = cols * cell + (cols - 1) * pad
	local h = rows * cell + (rows - 1) * pad
	local f = UIKit.frame(root, {
		Name = name, BackgroundTransparency = 1, ZIndex = 6, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, topInset), Size = UDim2.fromOffset(w, h), Visible = false,
	})
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(cell, cell)
	gl.CellPadding = UDim2.fromOffset(pad, pad)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	gl.Parent = f
	return f
end

local function circleLabel(b, text, cell)
	local txt = UIKit.label(b, { Text = text, Size = UDim2.new(0.84, 0, 0.56, 0), Position = UDim2.fromScale(0.08, 0.22), TextScaled = true, TextWrapped = true, ZIndex = 9 })
	UIKit.textLimit(txt, 8, math.max(10, math.floor(cell * 0.23)))
	return txt
end

local function hintLabel(b, text, cell)
	UIKit.label(b, { Text = text, TextSize = math.max(8, math.floor(cell * 0.16)), Size = UDim2.fromScale(0.5, 0.2), Position = UDim2.fromScale(0.25, 0.03), TextTransparency = 0.45, ZIndex = 9 })
end

local function addItemButton(f, item, index, cell, kb)
	local b = UIKit.button(f, { Text = "", LayoutOrder = index, ZIndex = 8 })
	b.Name = item.id
	skin(b, true, 10)
	circleLabel(b, item.text, cell)
	if kb and item.hint then
		hintLabel(b, item.hint, cell)
	end
	local key = item.kind == "tackle" and ("TACKLE:" .. item.tackle) or item.action
	local barH = math.max(3, math.floor(cell * 0.08))
	local bar = UIKit.frame(b, { BackgroundColor3 = T.text, Size = UDim2.new(0, 0, 0, barH), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.92), ZIndex = 10, Visible = false })
	UIKit.corner(bar, UDim.new(0, 4))
	mainButtons[item.id] = { btn = b, overlay = addOverlay(b, true), bar = item.kind == "charge" and bar or nil, action = item.action, key = key, width = cell * 0.6, barH = barH }
	if item.kind == "charge" then
		UIKit.hold(b, function() press(b, true) A.Begin(item.action, item.style) end, function() press(b, false) A.End(item.action) end)
	else
		UIKit.hold(b, function() press(b, true) A.Tackle(item.tackle) end, function() press(b, false) end)
	end
end

local function buildPanels(u, mobile, kb, vp, topInset, bottomReserve)
	local feintCount = #Defs.List
	local cols = feintCount > 15 and 4 or 3
	local rows = math.ceil(feintCount / cols)
	local pad = mobile and 4 or math.max(5, math.floor(u * 0.08))
	local availH = vp.Y - topInset - bottomReserve
	local cell = math.clamp(math.floor(math.min(u * 1.0, (availH - (rows - 1) * pad) / rows)), 30, 66)

	-- Dribbling: every feint
	local dock = gridFrame("FeintDock", cell, cols, rows, pad, topInset)
	for index, def in ipairs(Defs.List) do
		local b = UIKit.button(dock, { Text = "", LayoutOrder = index, ZIndex = 8 })
		b.Name = def.Id
		skin(b, true, 10)
		local txt = circleLabel(b, def.Name, cell)
		if kb then
			hintLabel(b, Input.HotkeyFor(index), cell)
		end
		feintButtons[def.Id] = { btn = b, label = txt }
		UIKit.hold(b, function() press(b, true) A.Feint(index) end, function() press(b, false) end)
	end
	panels.Dribble = dock

	-- the other modes
	for modeId, items in pairs(ITEMS) do
		local f = gridFrame(modeId .. "Panel", cell, math.min(3, #items), math.ceil(#items / 3), pad, topInset)
		for index, item in ipairs(items) do
			addItemButton(f, item, index, cell, kb)
		end
		panels[modeId] = f
	end
end

local function build()
	if root then
		root:Destroy()
	end
	mainButtons, feintButtons, toggles, panels, modeTabs = {}, {}, {}, {}, {}
	local u = UIKit.unit()
	local mobile = UIKit.isMobile()
	local kb = UIKit.hasKeyboard()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local gap = math.max(4, math.floor(u * 0.1))
	local topInset = mobile and 52 or 60

	root = UIKit.frame(gui, { Name = "ActionBar", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 })

	-- bottom row: mode tabs -------------------------------------------------------------------------------------
	local bw = mobile and math.clamp(math.floor(u * 1.6), 62, 92) or math.clamp(math.floor(u * 1.5), 80, 130)
	local bh = mobile and math.clamp(math.floor(u * 0.7), 28, 44) or math.clamp(math.floor(u * 0.6), 38, 56)
	local small = math.floor(bw * 0.78)
	local rowW = gap * #MODES + small
	for _ = 1, #MODES do
		rowW = rowW + bw
	end
	local row = UIKit.frame(root, { Name = "Row", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(rowW, bh) })
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local side = pillButton(row, "Side: R", small, bh, "SIDE")
	side.LayoutOrder = 0
	sideChip = side
	side.Activated:Connect(function() A.ToggleSide() end)
	refreshSideChip()
	for i, m in ipairs(MODES) do
		local b = pillButton(row, m.text, bw, bh, "MODE_" .. m.id)
		b.LayoutOrder = i
		modeTabs[m.id] = b
		b.Activated:Connect(function() ActionBar.SetMode(m.id) end)
	end

	-- keeper dive buttons (shown only for the keeper) above the tabs
	local sd = math.clamp(math.floor(u * 0.8), 34, 56)
	diveRow = UIKit.frame(root, { Name = "DiveRow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -(bh + 16)), Size = UDim2.fromOffset(sd * 2 + gap, sd), Visible = false })
	for i, sideValue in ipairs({ -1, 1 }) do
		local b = UIKit.button(diveRow, { Text = sideValue < 0 and "Dive L" or "Dive R", Size = UDim2.fromOffset(sd, sd), Position = UDim2.fromOffset((i - 1) * (sd + gap), 0), ZIndex = 5 })
		skin(b, true, math.max(9, math.floor(sd * 0.24)))
		b.Activated:Connect(function() A.GKDive(sideValue) end)
	end
	updateGKVisibility()

	-- left column: Sprint / Lock / Skills -------------------------------------------------------------------------
	local ls = mobile and math.clamp(math.floor(u * 0.95), 34, 52) or math.clamp(math.floor(u * 0.75), 44, 60)
	local leftBottom = mobile and math.floor(math.min(vp.Y * 0.38, u * 3.5)) or 24
	local function leftButton(index, text, name)
		local b = roundButton(root, text, ls, name)
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.new(0, 14, 1, -(leftBottom + (index - 1) * (ls + gap)))
		return b
	end
	local sprint = leftButton(1, "Sprint", "SPRINT")
	sprint.Activated:Connect(function() A.ToggleSprint() end)
	toggles.sprint = sprint
	local lock = leftButton(2, "Lock", "LOCK")
	lock.Activated:Connect(function() ShiftLock.Toggle() end)
	toggles.lock = lock
	local skills = leftButton(3, "Skills", "SKILLS")
	skills.Activated:Connect(function() ActionBar.TogglePanel() end)

	-- round buttons on the right (one panel per mode) ---------------------------------------------------------------
	local bottomReserve = mobile and 120 or (bh + 24)
	buildPanels(u, mobile, kb, vp, topInset, bottomReserve)
	applyPanelVisibility()
end

local function setToggleLook(b, on)
	if not b then
		return
	end
	b.BackgroundColor3 = on and T.text or T.btn
	b.BackgroundTransparency = on and 0.15 or T.btnAlpha
	b.TextColor3 = on and Color3.fromRGB(10, 12, 14) or T.text
end

local function updateCooldowns()
	for _, e in pairs(mainButtons) do
		if e.key and e.overlay then
			local remaining, dur = A.GetCooldown(e.key)
			if remaining > 0 and dur > 0 then
				e.overlay.Visible = true
				e.overlay.Size = UDim2.fromScale(1, remaining / dur)
			else
				e.overlay.Visible = false
			end
		end
		if e.bar and e.action then
			local frac = A.ChargeFraction(e.action)
			e.bar.Visible = frac > 0
			e.bar.Size = UDim2.new(0, math.floor(e.width * frac), 0, e.barH)
		end
	end
	for id, tab in pairs(modeTabs) do
		setToggleLook(tab, id == mode and panelOpen)
	end
	setToggleLook(toggles.sprint, A.IsSprinting())
	setToggleLook(toggles.lock, ShiftLock.IsEnabled())
end

function ActionBar.Build(screenGui)
	gui = screenGui
	build()
	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	local acc = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 0.05 then
			acc = 0
			updateCooldowns()
		end
	end)
	if connected then
		return
	end
	connected = true
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(build)
		end)
	end
	A.Changed.Event:Connect(function(key)
		if key == "SIDE" then
			refreshSideChip()
		end
	end)
	player:GetAttributeChangedSignal("SoccerRole"):Connect(updateGKVisibility)
	Input.PanelToggle.Event:Connect(ActionBar.TogglePanel)
	Input.LockToggle.Event:Connect(ShiftLock.Toggle)
end

return ActionBar
