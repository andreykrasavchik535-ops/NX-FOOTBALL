--[[
	StarterPlayerScripts/SoccerClient/HudController (ModuleScript)
	Scoreboard, clock, state banner, stamina bar, toasts, goal banner, lobby (team / goalkeeper choice) and
	end-of-match result screen. Reads ReplicatedStorage.SoccerState attributes; nothing here is authoritative.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local A = require(script.Parent:WaitForChild("ActionClient"))

local T = UIKit.Theme
local player = Players.LocalPlayer
local Hud = {}
Hud.Gui = nil

local stateFolder
local ui = {}
local NAMES = { RED = "AWAY", BLUE = "HOME" } -- RED / BLUE are the internal names, players see AWAY / HOME

local function fmtClock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function teamCounts()
	local r, b = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		local t = p:GetAttribute("SoccerTeam")
		if t == "RED" then
			r = r + 1
		elseif t == "BLUE" then
			b = b + 1
		end
	end
	return r, b
end

local function toast(kind, text)
	local color = T.info
	local size = 20
	if kind == "good" then
		color = T.good
	elseif kind == "bad" then
		color = T.bad
	elseif kind == "combo" then
		color = T.gold
		size = 28
	end
	local l = UIKit.label(ui.toasts, { Text = text, TextSize = size, TextColor3 = color, Size = UDim2.new(1, 0, 0, size + 8), TextStrokeTransparency = 0.45, LayoutOrder = -math.floor(os.clock() * 100) })
	task.delay(1.8, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.45)
			l:Destroy()
		end
	end)
end

local function refreshScoreboard()
	ui.redScore.Text = tostring(stateFolder:GetAttribute("RedScore") or 0)
	ui.blueScore.Text = tostring(stateFolder:GetAttribute("BlueScore") or 0)
	local half = stateFolder:GetAttribute("Half") or 1
	ui.half.Text = half == 1 and "1ST HALF" or "2ND HALF"
	ui.clock.Text = fmtClock(stateFolder:GetAttribute("Clock") or 0)
end

local function refreshBanner()
	local state = stateFolder:GetAttribute("State") or "Waiting"
	local cd = stateFolder:GetAttribute("Countdown") or 0
	local msg = stateFolder:GetAttribute("Message") or ""
	local text = ""
	if state == "Waiting" then
		text = "WAITING FOR PLAYERS"
	elseif state == "Intermission" then
		text = "MATCH STARTS IN " .. cd
	elseif state == "Kickoff" then
		text = string.upper(msg) .. (cd > 0 and ("  " .. cd) or "")
	elseif state == "HalfTime" then
		text = "HALF TIME  " .. cd
	elseif state == "GoalPause" then
		text = ""
	elseif state == "Results" then
		text = string.upper(msg)
	end
	ui.banner.Text = text
	ui.banner.Visible = text ~= ""
	ui.result.Visible = ui.result.Visible and state == "Results"
end

-- CHOOSE A TEAM screen -------------------------------------------------------------------------------------------------
local function blockedReason(key, r, b, team)
	local size = stateFolder:GetAttribute("TeamSize") or Config.TEAM_SIZE
	if team == key then
		return nil
	end
	local counts = { RED = r, BLUE = b }
	if team == "RED" or team == "BLUE" then
		counts[team] = counts[team] - 1 -- he leaves his old team when he moves
	end
	local other = key == "RED" and "BLUE" or "RED"
	if counts[key] >= size then
		return "FULL"
	end
	if Config.AUTO_BALANCE and counts[key] - counts[other] >= (Config.TEAM_MAX_LEAD or 2) then
		return "CLOSED"
	end
	return nil
end

local function refreshTeamSelect()
	if not ui.teamSelect then
		return
	end
	local team = player:GetAttribute("SoccerTeam") or ""
	local show = team == "" or ui.selectOpen
	ui.teamSelect.Visible = show
	if not show then
		return
	end
	local r, b = teamCounts()
	for _, key in ipairs({ "RED", "BLUE" }) do
		local card = ui.cards[key]
		local count = key == "RED" and r or b
		local reason = blockedReason(key, r, b, team)
		card.btn.BackgroundTransparency = reason and 0.55 or 0
		card.status.Text = reason and (reason == "FULL" and "TEAM FULL" or "TEAM CLOSED") or (team == key and "YOUR TEAM" or "")
		card.reason = reason
		for i, icon in ipairs(card.icons) do
			local filled = i <= count
			for _, part in ipairs(icon:GetChildren()) do
				part.BackgroundTransparency = filled and 0 or 0.78
			end
		end
	end
	ui.selectClose.Visible = team ~= ""
end

local function buildTeamSelect(gui, u)
	local f = UIKit.frame(gui, { Name = "TeamSelect", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = 30, Visible = false, Active = true })
	ui.teamSelect = f
	ui.selectOpen = false
	UIKit.label(f, {
		Text = "CHOOSE A TEAM", Font = UIKit.FONT_TITLE, TextSize = math.max(22, math.floor(u * 0.62)), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.05, 0), Size = UDim2.fromOffset(u * 9, u * 0.9), TextStrokeTransparency = 0.7, ZIndex = 31,
	})
	local cw, ch = u * 3.5, u * 4.3
	local gap = u * 0.5
	local size = stateFolder:GetAttribute("TeamSize") or Config.TEAM_SIZE
	local per = 6
	local icon = u * 0.36
	local pad = math.max(3, math.floor(u * 0.06))
	ui.cards = {}
	local defs = {
		{ key = "RED", x = -(cw / 2 + gap / 2), light = Color3.fromRGB(235, 80, 80), dark = Color3.fromRGB(140, 24, 30), line = Color3.fromRGB(255, 110, 110) },
		{ key = "BLUE", x = (cw / 2 + gap / 2), light = Color3.fromRGB(70, 110, 230), dark = Color3.fromRGB(24, 48, 140), line = Color3.fromRGB(100, 170, 255) },
	}
	for _, d in ipairs(defs) do
		local btn = UIKit.button(f, { Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, d.x, 0.2, 0), Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = d.light, ZIndex = 31 })
		btn.Name = "Card_" .. d.key
		UIKit.corner(btn, UDim.new(0, 14))
		UIKit.stroke(btn, d.line, 3, 0)
		pcall(function()
			local g = Instance.new("UIGradient")
			g.Rotation = 90
			g.Color = ColorSequence.new(d.light, d.dark)
			g.Parent = btn
		end)
		UIKit.label(btn, { Text = NAMES[d.key], Font = UIKit.FONT_TITLE, TextSize = math.max(22, math.floor(u * 0.72)), Size = UDim2.new(1, 0, 0, u * 1.0), Position = UDim2.fromOffset(0, u * 0.12), ZIndex = 32 })
		local status = UIKit.label(btn, { Text = "", TextSize = math.max(12, math.floor(u * 0.26)), Size = UDim2.new(1, 0, 0, u * 0.4), Position = UDim2.fromOffset(0, u * 1.5), ZIndex = 32 })
		local rows = math.ceil(size / per)
		local gridW = math.min(size, per) * icon + (math.min(size, per) - 1) * pad
		local grid = UIKit.frame(btn, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -u * 0.3), Size = UDim2.fromOffset(gridW, rows * icon + (rows - 1) * pad), ZIndex = 32 })
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(icon, icon)
		gl.CellPadding = UDim2.fromOffset(pad, pad)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grid
		local icons = {}
		for i = 1, size do
			local ic = UIKit.personIcon(grid, icon, Color3.new(1, 1, 1), 0.78)
			ic.LayoutOrder = i
			ic.ZIndex = 33
			icons[i] = ic
		end
		local card = { btn = btn, status = status, icons = icons }
		ui.cards[d.key] = card
		btn.Activated:Connect(function()
			if card.reason then
				A.Toast:Fire("bad", card.reason == "FULL" and "Team is full" or "This team already has 2 more players")
				return
			end
			Remotes.get("JoinTeam"):FireServer(d.key)
		end)
	end
	ui.selectClose = UIKit.button(f, { Text = "CLOSE", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(u * 1.8, u * 0.5), BackgroundColor3 = T.btn, BackgroundTransparency = T.btnAlpha, TextSize = math.max(12, math.floor(u * 0.24)), ZIndex = 31, Visible = false })
	UIKit.corner(ui.selectClose, UDim.new(0, 10))
	UIKit.stroke(ui.selectClose, T.line, 1.3, T.lineAlpha)
	ui.selectClose.Activated:Connect(function()
		ui.selectOpen = false
		refreshTeamSelect()
	end)
end

local lastTeam = nil
local function refreshLobby()
	if ui.lobby then ui.lobby.Visible = false end
	if ui.lobbyTab then ui.lobbyTab.Visible = false end
	if ui.teamSelect then ui.teamSelect.Visible = false end
	do return end
	local state = stateFolder:GetAttribute("State") or "Waiting"
	local team = player:GetAttribute("SoccerTeam") or ""
	if team ~= lastTeam then
		lastTeam = team
		ui.selectOpen = false -- joined (or left) a team: the choose screen closes by itself
	end
	-- the small panel (switch team / goalkeeper role) is only for players who already chose a team
	local show = team ~= "" and (state == "Waiting" or state == "Intermission")
	ui.lobby.Visible = show and not ui.lobbyHidden
	ui.lobbyTab.Visible = team ~= "" and not ui.lobby.Visible
	local r, b = teamCounts()
	local size = stateFolder:GetAttribute("TeamSize") or Config.TEAM_SIZE
	ui.joinRed.Text = string.format("%s  %d/%d", NAMES.RED, r, size)
	ui.joinBlue.Text = string.format("%s  %d/%d", NAMES.BLUE, b, size)
	ui.teamLabel.Text = team == "" and "Choose a team" or ("You are in team " .. (NAMES[team] or team))
	ui.teamLabel.TextColor3 = team == "RED" and T.red or (team == "BLUE" and T.blue or T.dim)
	local isGK = player:GetAttribute("SoccerRole") == "GK"
	ui.gkBtn.Text = isGK and "ROLE: GOALKEEPER" or "ROLE: FIELD PLAYER"
	ui.gkBtn.BackgroundColor3 = isGK and T.accent or T.panel2
	refreshTeamSelect()
end

local function refreshStamina()
	local st = player:GetAttribute("Stamina") or Config.STAMINA_MAX
	ui.stFill.Size = UDim2.fromScale(math.clamp(st / Config.STAMINA_MAX, 0, 1), 1)
	ui.stFill.BackgroundColor3 = player:GetAttribute("Exhausted") and T.bad or (st < 30 and T.gold or T.accent)
end

local function showGoal(scoring, scorer, assister, red, blue, own)
	ui.goalTitle.Text = own and "OWN GOAL" or "GOAL!"
	ui.goalTitle.TextColor3 = scoring == "RED" and T.red or T.blue
	ui.goalScore.Text = string.format("AWAY %d  -  %d HOME", red, blue)
	local who = scorer ~= "" and scorer or ""
	if assister ~= "" then
		who = who .. "   (assist: " .. assister .. ")"
	end
	ui.goalWho.Text = who
	ui.goal.Visible = true
	ui.goal.GroupTransparency = 1
	TweenService:Create(ui.goal, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	task.delay(Config.GOAL_PAUSE_SECONDS - 0.6, function()
		TweenService:Create(ui.goal, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
		task.wait(0.45)
		ui.goal.Visible = false
	end)
end

local function showResult(winner, red, blue, list, goalEvents, duration, homeClub, awayClub)
	for _, c in ipairs(ui.resultRows:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for _, c in ipairs(ui.goalLog:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	ui.resultTitle.Text = winner == "DRAW" and "DRAW" or ((NAMES[winner] or winner) .. " WINS")
	ui.resultTitle.TextColor3 = winner == "RED" and T.red or (winner == "BLUE" and T.blue or T.text)
	ui.resultScore.Text = string.format("%d  -  %d", red, blue)
	for i, e in ipairs(list) do
		if i > 5 then
			break
		end
		UIKit.label(ui.resultRows, {
			Text = string.format("%s   G %d   A %d   S %d   T %d", e.name, e.goals, e.assists, e.saves, e.tackles),
			TextSize = 15, TextColor3 = e.team == "RED" and T.red or T.blue, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 20),
		})
	end
	if goalEvents then
		for i, g in ipairs(goalEvents) do
			if i > 6 then
				break
			end
			local name = (g.scorer and g.scorer ~= "") and g.scorer or "Unknown"
			UIKit.label(ui.goalLog, {
				Text = string.format("%d'  %s%s", g.minute or 0, name, g.own and " (OG)" or ""),
				TextSize = 14, TextColor3 = g.team == "RED" and T.red or T.blue, LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end
	if duration then
		ui.durationLabel.Text = string.format("Match duration: %02d:%02d", math.floor(duration / 60), duration % 60)
	end
	ui.result.Visible = true
end

function Hud.Build()
	stateFolder = ReplicatedStorage:WaitForChild("SoccerState")
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "NXHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 5
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	gui.Parent = pg
	Hud.Gui = gui

	local u = UIKit.unit()

	-- scoreboard
	local sb = UIKit.frame(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(u * 5.2, u * 0.78), BackgroundColor3 = T.bg, BackgroundTransparency = 0.1 })
	UIKit.corner(sb, UDim.new(0, 12))
	UIKit.stroke(sb, T.accent, 1.5, 0.5)
	local redBox = UIKit.frame(sb, { BackgroundColor3 = T.red, Size = UDim2.new(0.3, 0, 1, 0) })
	UIKit.corner(redBox, UDim.new(0, 12))
	local blueBox = UIKit.frame(sb, { BackgroundColor3 = T.blue, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.3, 0, 1, 0) })
	UIKit.corner(blueBox, UDim.new(0, 12))
	UIKit.label(redBox, { Text = "AWAY", TextSize = math.floor(u * 0.2), Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0, 0) })
	ui.redScore = UIKit.label(redBox, { Text = "0", TextSize = math.floor(u * 0.44), Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0) })
	UIKit.label(blueBox, { Text = "HOME", TextSize = math.floor(u * 0.2), Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0) })
	ui.blueScore = UIKit.label(blueBox, { Text = "0", TextSize = math.floor(u * 0.44), Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0, 0) })
	ui.clock = UIKit.label(sb, { Text = "00:00", TextSize = math.floor(u * 0.36), Size = UDim2.fromScale(0.4, 0.62), Position = UDim2.fromScale(0.3, 0) })
	ui.half = UIKit.label(sb, { Text = "1ST HALF", TextSize = math.floor(u * 0.15), TextColor3 = T.dim, Size = UDim2.fromScale(0.4, 0.34), Position = UDim2.fromScale(0.3, 0.64) })

	-- banner
	ui.banner = UIKit.label(gui, { Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, u * 0.95), Size = UDim2.fromOffset(u * 7, u * 0.5), TextSize = math.floor(u * 0.3), TextStrokeTransparency = 0.5, Visible = false })

	-- toasts
	ui.toasts = UIKit.frame(gui, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -(u * 2.4)), Size = UDim2.fromOffset(u * 6, u * 2) })
	local tl = Instance.new("UIListLayout")
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tl.Parent = ui.toasts

	-- stamina
	local stBg = UIKit.frame(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -(u * 0.82 + 22)), Size = UDim2.fromOffset(u * 3.2, math.max(6, math.floor(u * 0.12))), BackgroundColor3 = T.bg, BackgroundTransparency = 0.25 })
	UIKit.corner(stBg, UDim.new(1, 0))
	ui.stFill = UIKit.frame(stBg, { BackgroundColor3 = T.accent, Size = UDim2.fromScale(1, 1) })
	UIKit.corner(ui.stFill, UDim.new(1, 0))

	-- goal banner
	ui.goal = Instance.new("CanvasGroup")
	ui.goal.BackgroundTransparency = 1
	ui.goal.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.goal.Position = UDim2.fromScale(0.5, 0.36)
	ui.goal.Size = UDim2.fromOffset(u * 7, u * 2.3)
	ui.goal.Visible = false
	ui.goal.Parent = gui
	ui.goalTitle = UIKit.label(ui.goal, { Text = "GOAL!", TextSize = math.floor(u * 1.1), Size = UDim2.fromScale(1, 0.5), TextStrokeTransparency = 0.3 })
	ui.goalScore = UIKit.label(ui.goal, { Text = "", TextSize = math.floor(u * 0.4), Size = UDim2.fromScale(1, 0.25), Position = UDim2.fromScale(0, 0.5), TextStrokeTransparency = 0.5 })
	ui.goalWho = UIKit.label(ui.goal, { Text = "", TextSize = math.floor(u * 0.28), TextColor3 = T.dim, Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.76) })

	-- result screen
	ui.result = UIKit.frame(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(u * 6.4, u * 5.6), BackgroundColor3 = T.bg, BackgroundTransparency = 0.05, Visible = false, ZIndex = 20 })
	UIKit.corner(ui.result, UDim.new(0, 16))
	UIKit.stroke(ui.result, T.accent, 2, 0.3)
	ui.resultTitle = UIKit.label(ui.result, { Text = "", TextSize = math.floor(u * 0.6), Size = UDim2.new(1, 0, 0, u * 0.8), Position = UDim2.fromOffset(0, 8), ZIndex = 21 })
	ui.resultScore = UIKit.label(ui.result, { Text = "", TextSize = math.floor(u * 0.5), Size = UDim2.new(1, 0, 0, u * 0.6), Position = UDim2.fromOffset(0, u * 0.85), ZIndex = 21 })
	ui.resultRows = UIKit.frame(ui.result, { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, u * 1.6), Size = UDim2.new(1, -24, 0, u * 1.3), ZIndex = 21 })
	local rl = Instance.new("UIListLayout")
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = ui.resultRows
	ui.goalLog = UIKit.frame(ui.result, { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, u * 3.0), Size = UDim2.new(1, -24, 0, u * 1.4), ZIndex = 21 })
	local gl = Instance.new("UIListLayout")
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = ui.goalLog
	ui.durationLabel = UIKit.label(ui.result, { Text = "", Position = UDim2.fromOffset(12, u * 4.5), Size = UDim2.new(1, -24, 0, u * 0.35), TextSize = math.floor(u * 0.22), TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 })
	ui.continueBtn = UIKit.button(ui.result, { Text = "CONTINUE", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(u * 2.6, u * 0.55), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.26), ZIndex = 22 })
	UIKit.corner(ui.continueBtn, UDim.new(0, 10))
	UIKit.stroke(ui.continueBtn, T.accent, 1.3, 0.4)
	ui.continueBtn.Activated:Connect(function()
		Remotes.get("MatchControl"):FireServer({ cmd = "Continue" })
	end)

	-- lobby
	ui.lobbyHidden = false
	ui.lobby = UIKit.frame(gui, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(u * 3.4, u * 3.75), BackgroundColor3 = T.bg, BackgroundTransparency = 0.08, ZIndex = 10 })
	UIKit.corner(ui.lobby, UDim.new(0, 14))
	UIKit.stroke(ui.lobby, T.accent, 1.5, 0.4)
	local lt = UIKit.label(ui.lobby, { Text = "NX: NEXT FOOTBALL", TextSize = math.floor(u * 0.24), TextColor3 = T.accent, Size = UDim2.new(1, 0, 0, u * 0.5), Position = UDim2.fromOffset(0, 6), ZIndex = 11 })
	ui.teamLabel = UIKit.label(ui.lobby, { Text = "", TextSize = math.floor(u * 0.19), Size = UDim2.new(1, 0, 0, u * 0.35), Position = UDim2.fromOffset(0, u * 0.55), ZIndex = 11 })
	local function lobbyBtn(y, color)
		local b = UIKit.button(ui.lobby, { Text = "", Size = UDim2.new(1, -24, 0, u * 0.62), Position = UDim2.fromOffset(12, y), BackgroundColor3 = color, TextSize = math.floor(u * 0.24), ZIndex = 11 })
		UIKit.corner(b, UDim.new(0, 10))
		return b
	end
	ui.joinRed = lobbyBtn(u * 1.0, T.red)
	ui.joinBlue = lobbyBtn(u * 1.75, T.blue)
	ui.gkBtn = lobbyBtn(u * 2.5, T.panel2)
	local hide = UIKit.button(ui.lobby, { Text = "HIDE", Size = UDim2.new(1, -24, 0, u * 0.4), Position = UDim2.fromOffset(12, u * 3.23), BackgroundColor3 = T.panel, TextSize = math.floor(u * 0.18), ZIndex = 11 })
	UIKit.corner(hide, UDim.new(0, 8))
	ui.joinRed.Activated:Connect(function() Remotes.get("JoinTeam"):FireServer("RED") end)
	ui.joinBlue.Activated:Connect(function() Remotes.get("JoinTeam"):FireServer("BLUE") end)
	ui.gkBtn.Activated:Connect(function()
		local isGK = player:GetAttribute("SoccerRole") == "GK"
		Remotes.get("SetRole"):FireServer(isGK and "FIELD" or "GK")
	end)
	ui.lobbyTab = UIKit.button(gui, { Text = "TEAM", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(u * 0.9, u * 0.5), BackgroundColor3 = T.panel, BackgroundTransparency = 0.1, TextSize = math.floor(u * 0.18), Visible = false, ZIndex = 10 })
	UIKit.corner(ui.lobbyTab, UDim.new(0, 8))
	buildTeamSelect(gui, u)
	hide.Activated:Connect(function() ui.lobbyHidden = true refreshLobby() end)
	ui.lobbyTab.Activated:Connect(function() ui.lobbyHidden = false refreshLobby() end)

	-- wiring
	for _, name in ipairs({ "RedScore", "BlueScore", "Half", "Clock" }) do
		stateFolder:GetAttributeChangedSignal(name):Connect(refreshScoreboard)
	end
	for _, name in ipairs({ "State", "Countdown", "Message" }) do
		stateFolder:GetAttributeChangedSignal(name):Connect(function()
			refreshBanner()
			refreshLobby()
		end)
	end
	player:GetAttributeChangedSignal("SoccerTeam"):Connect(refreshLobby)
	player:GetAttributeChangedSignal("SoccerRole"):Connect(refreshLobby)
	player:GetAttributeChangedSignal("Stamina"):Connect(refreshStamina)
	player:GetAttributeChangedSignal("Exhausted"):Connect(refreshStamina)
	Players.PlayerAdded:Connect(function(p) p:GetAttributeChangedSignal("SoccerTeam"):Connect(refreshLobby) end)
	for _, p in ipairs(Players:GetPlayers()) do
		p:GetAttributeChangedSignal("SoccerTeam"):Connect(refreshLobby)
	end
	Players.PlayerRemoving:Connect(function() task.defer(refreshLobby) end)

	A.Toast.Event:Connect(toast)
	Remotes.get("GoalScored").OnClientEvent:Connect(showGoal)
	Remotes.get("MatchEnded").OnClientEvent:Connect(showResult)

	refreshScoreboard()
	refreshBanner()
	refreshLobby()
	refreshStamina()
	return gui
end

return Hud
