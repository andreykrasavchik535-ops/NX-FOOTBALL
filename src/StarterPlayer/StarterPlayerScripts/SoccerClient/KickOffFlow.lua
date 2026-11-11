--[[
	StarterPlayerScripts/SoccerClient/KickOffFlow (ModuleScript)
	Menu -> Team Selection -> Match Setup -> (Start) -> Match.
	  * pick your side (HOME / AWAY) and a formation position (or goalkeeper);
	  * the host picks the clubs, kits, stadium, half length, team size and formation;
	  * every setup change is sent to the server (MatchControl) which validates and re-broadcasts it.
	Non-host players see the setup read-only. Nothing here is authoritative.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Clubs = require(Shared:WaitForChild("Clubs"))
local Formations = require(Shared:WaitForChild("Formations"))
local Stadiums = require(Shared:WaitForChild("Stadiums"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local T = UIKit.Theme
local player = Players.LocalPlayer
local KickOffFlow = {}

local gui, root, stateFolder
local visible = false
local onBack
local controls = {}   -- refreshed widgets
local localSide = nil

local function attr(name, default)
	local v = stateFolder:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

local function isHost()
	return player.UserId == attr("HostUserId", 0)
end

local function currentSetup()
	return {
		homeClub = attr("HomeClub", Clubs.DefaultHome),
		awayClub = attr("AwayClub", Clubs.DefaultAway),
		homeKit = attr("HomeKit", "Home"),
		awayKit = attr("AwayKit", "Away"),
		halfSeconds = attr("HalfSeconds", Config.DEFAULT_HALF_SECONDS),
		teamSize = attr("TeamSize", Config.TEAM_SIZE),
		formation = attr("Formation", "1-2-1"),
		stadium = attr("Stadium", Stadiums.Default),
	}
end

local function sendSetup(mutator)
	if not isHost() then
		return
	end
	local s = currentSetup()
	mutator(s)
	Remotes.get("MatchControl"):FireServer({ cmd = "UpdateSetup", setup = s })
	SoundController.Click()
end

-- small helpers ------------------------------------------------------------------------

local function section(parent, title, u)
	local head = UIKit.label(parent, {
		Text = title, Font = UIKit.FONT_TITLE, TextSize = math.floor(u * 0.3), TextColor3 = T.accent,
		Size = UDim2.new(1, 0, 0, u * 0.5), LayoutOrder = #parent:GetChildren(),
	})
	return head
end

local function chipRow(parent, u)
	local row = UIKit.frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, u * 0.62), AutomaticSize = Enum.AutomaticSize.Y })
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Wraps = true
	layout.Parent = row
	return row
end

local function chip(row, text, u, onClick, selected, disabled)
	local b = UIKit.button(row, {
		Text = text, Size = UDim2.fromOffset(math.max(64, #text * u * 0.16 + 20), u * 0.52),
		BackgroundColor3 = selected and T.panel2 or T.panel, BackgroundTransparency = selected and 0.05 or 0.4,
		TextSize = math.floor(u * 0.22), TextColor3 = disabled and T.dim or T.text,
	})
	UIKit.corner(b, UDim.new(0, 8))
	UIKit.stroke(b, selected and T.accent or T.line, 1.2, selected and 0.2 or 0.7)
	if onClick and not disabled then
		b.Activated:Connect(onClick)
	end
	return b
end

-- A tiny kit preview (shirt + shorts) drawn with the club colours. Templates are empty by
-- default, so this shows the club's colours; the avatar's own clothing is kept in-game.
local function kitPreview(parent, club, u)
	local f = UIKit.frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(u * 0.9, u * 1.1) })
	local shirt = UIKit.frame(f, { BackgroundColor3 = club.Primary, Size = UDim2.fromOffset(u * 0.7, u * 0.55), Position = UDim2.fromOffset(u * 0.1, 0) })
	UIKit.corner(shirt, UDim.new(0, 6))
	local shorts = UIKit.frame(f, { BackgroundColor3 = club.Secondary, Size = UDim2.fromOffset(u * 0.55, u * 0.4), Position = UDim2.fromOffset(u * 0.175, u * 0.6) })
	UIKit.corner(shorts, UDim.new(0, 6))
	return f
end

-- Build the whole panel ----------------------------------------------------------------

local function build()
	if root then
		root:Destroy()
	end
	controls = {}
	local u = UIKit.unit()
	root = Instance.new("CanvasGroup")
	root.Name = "KickOffFlow"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui

	local bg = UIKit.frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = 1 })

	local panelW = math.clamp(u * 9, 320, 760)
	local panel = UIKit.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(panelW, math.min(u * 8.4, 640)),
		BackgroundColor3 = T.bg, BackgroundTransparency = 0.06, ZIndex = 2,
	})
	UIKit.corner(panel, UDim.new(0, 16))
	UIKit.stroke(panel, T.accent, 1.5, 0.4)

	UIKit.label(panel, { Text = "KICK OFF", Font = UIKit.FONT_TITLE, TextSize = math.floor(u * 0.5), Size = UDim2.new(1, 0, 0, u * 0.7), Position = UDim2.fromOffset(0, u * 0.12), ZIndex = 3 })
	local back = UIKit.button(panel, { Text = "BACK", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(12, u * 0.16), Size = UDim2.fromOffset(u * 1.2, u * 0.45), BackgroundColor3 = T.panel2, TextSize = math.floor(u * 0.22), ZIndex = 3 })
	UIKit.corner(back, UDim.new(0, 8))
	back.Activated:Connect(function()
		SoundController.Click()
		if onBack then onBack() end
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, u * 0.95)
	scroll.Size = UDim2.new(1, -32, 1, -(u * 1.9))
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 4
	scroll.ZIndex = 3
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local order = 0
	local function nextOrder()
		order = order + 1
		return order
	end

	-- YOUR TEAM ------------------------------------------------------------------------
	local h = section(scroll, "YOUR TEAM", u); h.LayoutOrder = nextOrder()
	local sideRow = chipRow(scroll, u); sideRow.LayoutOrder = nextOrder()
	chip(sideRow, "HOME", u, function()
		Remotes.get("JoinTeam"):FireServer("BLUE"); SoundController.Click()
	end, false, false)
	chip(sideRow, "AWAY", u, function()
		Remotes.get("JoinTeam"):FireServer("RED"); SoundController.Click()
	end, false, false)
	local posRow = chipRow(scroll, u); posRow.LayoutOrder = nextOrder()
	controls.posRow = posRow
	local gkRow = chipRow(scroll, u); gkRow.LayoutOrder = nextOrder()
	chip(gkRow, "GOALKEEPER", u, function()
		local isGK = player:GetAttribute("SoccerRole") == "GK"
		Remotes.get("SetRole"):FireServer(isGK and "FIELD" or "GK"); SoundController.Click()
	end, false, false)

	-- CLUBS ----------------------------------------------------------------------------
	for _, side in ipairs({ "home", "away" }) do
		local hh = section(scroll, side == "home" and "HOME CLUB" or "AWAY CLUB", u); hh.LayoutOrder = nextOrder()
		local row = chipRow(scroll, u); row.LayoutOrder = nextOrder()
		controls[side .. "ClubRow"] = row
		local previewRow = chipRow(scroll, u); previewRow.LayoutOrder = nextOrder()
		controls[side .. "Preview"] = previewRow
	end

	-- MATCH ----------------------------------------------------------------------------
	local mh = section(scroll, "MATCH SETTINGS", u); mh.LayoutOrder = nextOrder()
	local stadRow = chipRow(scroll, u); stadRow.LayoutOrder = nextOrder(); controls.stadRow = stadRow
	local halfRow = chipRow(scroll, u); halfRow.LayoutOrder = nextOrder(); controls.halfRow = halfRow
	local sizeRow = chipRow(scroll, u); sizeRow.LayoutOrder = nextOrder(); controls.sizeRow = sizeRow
	local formRow = chipRow(scroll, u); formRow.LayoutOrder = nextOrder(); controls.formRow = formRow

	-- START ----------------------------------------------------------------------------
	local startBtn = UIKit.button(scroll, {
		Text = "START MATCH", Size = UDim2.new(1, 0, 0, u * 0.7), BackgroundColor3 = T.panel2,
		TextSize = math.floor(u * 0.32), Font = UIKit.FONT_TITLE, LayoutOrder = nextOrder(),
	})
	UIKit.corner(startBtn, UDim.new(0, 10))
	UIKit.stroke(startBtn, T.accent, 1.5, 0.3)
	startBtn.Activated:Connect(function()
		if not isHost() then
			if KickOffFlow.Toast then KickOffFlow.Toast("info", "Only the host can start") end
			return
		end
		SoundController.Click()
		Remotes.get("MatchControl"):FireServer({ cmd = "StartMatch", setup = currentSetup() })
	end)
	controls.startBtn = startBtn
end

-- Refresh widgets from the replicated setup ---------------------------------------------

local function refresh()
	if not root or not visible then
		return
	end
	local u = UIKit.unit()
	local s = currentSetup()
	local host = isHost()

	-- positions for the local player's side
	local posRow = controls.posRow
	if posRow then
		for _, c in ipairs(posRow:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		local team = player:GetAttribute("SoccerTeam")
		local myPos = player:GetAttribute("SoccerPosition") or ""
		local slots = Formations.Get(s.teamSize, s.formation)
		if slots and team and team ~= "" then
			for _, slot in ipairs(slots.Slots) do
				if slot.Role == "FIELD" then
					chip(posRow, slot.Label, u, function()
						Remotes.get("AssignPosition"):FireServer(slot.Id)
						SoundController.Click()
					end, myPos == slot.Id, false)
				end
			end
		end
	end

	-- clubs
	for _, side in ipairs({ "home", "away" }) do
		local row = controls[side .. "ClubRow"]
		local preview = controls[side .. "Preview"]
		if row then
			for _, c in ipairs(row:GetChildren()) do
				if c:IsA("TextButton") then c:Destroy() end
			end
			local selected = side == "home" and s.homeClub or s.awayClub
			for _, club in ipairs(Clubs.List) do
				chip(row, club.Short, u, function()
					sendSetup(function(setup)
						if side == "home" then setup.homeClub = club.Id else setup.awayClub = club.Id end
					end)
				end, selected == club.Id, not host)
			end
		end
		if preview then
			for _, c in ipairs(preview:GetChildren()) do
				c:Destroy()
			end
			local clubId = side == "home" and s.homeClub or s.awayClub
			local club = Clubs.Get(clubId)
			if club then
				kitPreview(preview, club, u)
				chip(preview, (side == "home" and s.homeKit or s.awayKit) .. " KIT", u, function()
					sendSetup(function(setup)
						if side == "home" then
							setup.homeKit = setup.homeKit == "Home" and "Away" or "Home"
						else
							setup.awayKit = setup.awayKit == "Home" and "Away" or "Home"
						end
					end)
				end, false, not host)
			end
		end
	end

	-- stadium
	local stadRow = controls.stadRow
	if stadRow then
		for _, c in ipairs(stadRow:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for _, st in ipairs(Stadiums.List) do
			local label = st.Name .. (st.ComingSoon and " (SOON)" or "")
			chip(stadRow, label, u, function()
				sendSetup(function(setup) setup.stadium = st.Id end)
			end, s.stadium == st.Id, not host or not st.Enabled)
		end
	end

	-- half length
	local halfRow = controls.halfRow
	if halfRow then
		for _, c in ipairs(halfRow:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for _, opt in ipairs(Config.HALF_LENGTH_OPTIONS) do
			chip(halfRow, (opt / 60) .. " MIN", u, function()
				sendSetup(function(setup) setup.halfSeconds = opt end)
			end, s.halfSeconds == opt, not host)
		end
	end

	-- team size
	local sizeRow = controls.sizeRow
	if sizeRow then
		for _, c in ipairs(sizeRow:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for _, size in ipairs(Formations.Sizes) do
			chip(sizeRow, size .. "v" .. size, u, function()
				sendSetup(function(setup)
					setup.teamSize = size
					local f = Formations.DefaultFor(size)
					setup.formation = f and f.Id or setup.formation
				end)
			end, s.teamSize == size, not host)
		end
	end

	-- formation
	local formRow = controls.formRow
	if formRow then
		for _, c in ipairs(formRow:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for _, f in ipairs(Formations.List(s.teamSize)) do
			chip(formRow, f.Id, u, function()
				sendSetup(function(setup) setup.formation = f.Id end)
			end, s.formation == f.Id, not host)
		end
	end

	if controls.startBtn then
		controls.startBtn.Text = host and "START MATCH" or "WAITING FOR HOST"
		controls.startBtn.TextColor3 = host and T.text or T.dim
	end
end

function KickOffFlow.Build(parent, callbacks)
	gui = parent
	onBack = callbacks.Back
	KickOffFlow.Toast = callbacks.Toast
	stateFolder = ReplicatedStorage:WaitForChild("SoccerState")
	build()
	for _, name in ipairs({ "HomeClub", "AwayClub", "HomeKit", "AwayKit", "HalfSeconds", "TeamSize", "Formation", "Stadium", "HostUserId" }) do
		stateFolder:GetAttributeChangedSignal(name):Connect(refresh)
	end
	player:GetAttributeChangedSignal("SoccerTeam"):Connect(refresh)
	player:GetAttributeChangedSignal("SoccerPosition"):Connect(refresh)
	player:GetAttributeChangedSignal("SoccerRole"):Connect(refresh)
	return root
end

function KickOffFlow.Show()
	if not root then return end
	visible = true
	root.Visible = true
	root.GroupTransparency = 1
	TweenService:Create(root, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	refresh()
end

function KickOffFlow.Hide()
	visible = false
	if root then root.Visible = false end
end

return KickOffFlow
