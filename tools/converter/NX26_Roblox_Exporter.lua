--[[
	NX26_Roblox_Exporter.lua  —  Studio PLUGIN
	Exports NX26 procedural KeyframeSequence animations to JSON (Roblox -> JSON step).

	SETUP (one-time, additive, does NOT change gameplay):
	  Add this function to the END of SoccerClient/ProceduralAnimations (before return ProceduralAnimations):

		function ProceduralAnimations.BuildSeq(group, key, side)
			side = (side == -1) and -1 or 1
			local gen = GENERATORS[group .. "." .. key]
			if not gen then return nil end
			return gen(side)   -- returns the KeyframeSequence WITHOUT registering a temp id
		end

	  Then save THIS file as a Studio plugin (e.g. %LOCALAPPDATA%/Roblox/Plugins/NX26_Exporter.lua)
	  and restart Studio. A NX26 Export dock appears. Pick an animation, click Export, copy the JSON.

	NOTES:
	  * Reads the ACTUAL KeyframeSequence (Pose.CFrame:GetComponents()), NOT the temporary AnimationId.
	  * Roblox cannot write files from a script; the plugin shows the JSON in a copyable TextBox.
	    (Optional: set HTTP_ENDPOINT to POST the JSON to a local server you run.)
	  * UNTESTED in Studio here (no Studio in this environment). Traversal uses standard API.
]]
local HttpService = game:GetService("HttpService")
local StarterPlayer = game:GetService("StarterPlayer")
local HTTP_ENDPOINT = ""  -- optional local listener, requires HttpEnabled

local function getPA()
	local sp = StarterPlayer:WaitForChild("StarterPlayerScripts", 10)
	local sc = sp and sp:WaitForChild("SoccerClient", 10)
	local pa = sc and sc:WaitForChild("ProceduralAnimations", 10)
	if not pa then return nil end
	local ok, mod = pcall(require, pa)
	if ok then return mod end
	return nil
end

local function poseToTable(pose)
	local t = { name = pose.Name, cf = { pose.CFrame:GetComponents() }, weight = pose.Weight, children = {} }
	for _, sub in ipairs(pose:GetSubPoses()) do table.insert(t.children, poseToTable(sub)) end
	return t
end

local function seqToTable(seq)
	local kfs = {}
	for _, kf in ipairs(seq:GetKeyframes()) do
		local poses = {}
		for _, p in ipairs(kf:GetPoses()) do table.insert(poses, poseToTable(p)) end
		table.insert(kfs, { time = kf.Time, poses = poses })
	end
	return { name = seq.Name, loop = seq.Loop, priority = tostring(seq.Priority), keyframes = kfs }
end

local ANIMS = {
	{"Locomotion","Idle"},{"Locomotion","RunNoBall"},{"Locomotion","RunBall"},{"Locomotion","Sprint"},
	{"Actions","Shoot"},{"Actions","Pass"},{"Actions","Long"},{"Actions","TackleFast"},{"Actions","TackleSlide"},
	{"Feints","StepOver"},{"Feints","DoubleStepOver"},{"Feints","Roulette"},{"Feints","RainbowFlick"},
	{"Feints","HeelFlick"},{"Feints","Elastico"},{"Feints","ReverseElastico"},{"Feints","BodyFeint"},
	{"Feints","BallRoll"},{"Feints","FakeShot"},{"Feints","Nutmeg"},{"Feints","DragBack"},{"Feints","LaCroqueta"},
	{"Feints","McGeadySpin"},{"Feints","HeelToHeel"},{"Feints","BodyFeintCut"},{"Feints","TwoTouchQuick"},
	{"Feints","Chop"},{"Feints","RouletteBurst"},{"Feints","DoubleTouch"},{"Feints","StepoverExit"},
	{"Feints","LateralHeelToHeel"},{"Feints","SombreroFlick"},{"Feints","StopAndGo"},{"Feints","ScoopTurn"},
	{"Feints","VCut"},{"Feints","BerbaSpin"},{"Feints","AdvancedBodyFeint"},
}

local function exportOne(pa, group, key, side)
	if not pa.BuildSeq then return nil, "Add BuildSeq to ProceduralAnimations (see header)" end
	local seq = pa.BuildSeq(group, key, side)
	if not seq then return nil, "no generator for " .. group .. "." .. key end
	local tbl = seqToTable(seq)
	tbl.group = group; tbl.key = key; tbl.side = side; tbl.rig = "R15"
	return HttpService:JSONEncode(tbl), nil
end

local toolbar = plugin:CreateToolbar("NX26")
local btn = toolbar:CreateButton("NX26 Export", "Export procedural animations to JSON", "rbxassetid://0")
local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 520, 420, 420, 320)
local widget = plugin:CreateDockWidgetPluginGui("NX26Exporter", info)
widget.Title = "NX26 Animation Exporter"
local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1,1); frame.BackgroundColor3 = Color3.fromRGB(24,28,36); frame.Parent = widget
local list = Instance.new("ScrollingFrame"); list.Size = UDim2.new(0,170,1,-10); list.Position = UDim2.fromOffset(5,5); list.CanvasSize = UDim2.new(0,0,0,#ANIMS*24); list.BackgroundTransparency = 1; list.Parent = frame
local layout = Instance.new("UIListLayout"); layout.Parent = list
local box = Instance.new("TextBox"); box.Size = UDim2.new(1,-190,1,-40); box.Position = UDim2.fromOffset(180,5); box.MultiLine = true; box.TextEditable = false; box.ClearTextOnFocus = false; box.TextColor3 = Color3.fromRGB(220,230,240); box.BackgroundColor3 = Color3.fromRGB(15,18,24); box.Text = "Select an animation, then Export. Copy this JSON."; box.TextXAlignment = Enum.TextXAlignment.Left; box.TextYAlignment = Enum.TextYAlignment.Top; box.Parent = frame
local exportBtn = Instance.new("TextButton"); exportBtn.Size = UDim2.new(0,170,0,26); exportBtn.Position = UDim2.new(0,5,1,-32); exportBtn.Text = "Export selected"; exportBtn.Parent = frame
local sideBtn = Instance.new("TextButton"); sideBtn.Size = UDim2.new(0,80,0,26); sideBtn.Position = UDim2.new(0,180,1,-32); sideBtn.Text = "side: R"; sideBtn.Parent = frame
local current, side = nil, 1
for _, a in ipairs(ANIMS) do
	local b = Instance.new("TextButton"); b.Size = UDim2.new(1,-5,0,22); b.Text = a[1].."."..a[2]; b.TextColor3 = Color3.fromRGB(220,230,240); b.BackgroundColor3 = Color3.fromRGB(32,38,48); b.Parent = list
	b.Activated:Connect(function() current = a; box.Text = "Selected: "..a[1].."."..a[2]..". Click Export." end)
end
sideBtn.Activated:Connect(function() side = -side; sideBtn.Text = side==1 and "side: R" or "side: L" end)
exportBtn.Activated:Connect(function()
	if not current then box.Text = "Select an animation first." return end
	local pa = getPA()
	if not pa then box.Text = "Cannot require ProceduralAnimations." return end
	local json, err = exportOne(pa, current[1], current[2], side)
	if err then box.Text = "ERROR: "..err return end
	box.Text = json
	if HTTP_ENDPOINT ~= "" then pcall(function() HttpService:PostAsync(HTTP_ENDPOINT, json, Enum.HttpContentType.ApplicationJson) end) end
end)
btn.Click:Connect(function() widget.Enabled = not widget.Enabled end)
