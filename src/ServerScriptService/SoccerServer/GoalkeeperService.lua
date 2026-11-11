--[[
	ServerScriptService/SoccerServer/GoalkeeperService (ModuleScript)
	Goalkeeper role for REAL players (hands in the own box: catch / parry, dive, hold-and-release)
	PLUS the only AI in the game: one AI goalkeeper per team.

	AI keepers:
	  * spawn only when a team has NO real goalkeeper, and despawn the moment a real player takes GK
	    (so a team never has two keepers);
	  * are server "pseudo-player" entities (IsAI=true) that BallService/TeamService understand, so the
	    EXISTING catch / hold / parry / punt logic is reused unchanged;
	  * move along the goal line and dive at shots. They NEVER teleport to the ball and never leave the
	    goal area to chase it. No AI outfield players exist anywhere in the game.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Clubs = require(Shared:WaitForChild("Clubs"))

local Field = require(script.Parent:WaitForChild("FieldService"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))
local StaminaService = require(script.Parent:WaitForChild("StaminaService"))
local BallService = require(script.Parent:WaitForChild("BallService"))
local MatchService = require(script.Parent:WaitForChild("MatchService"))

local GK = {}
local diveUntil, diveCd, buckets = {}, {}, {}
local aiKeepers = {}   -- [team] = pseudo-player entity
local aiFolder

-- Real-player goalkeeper helpers (unchanged behaviour) ----------------------------------------------------

function GK.IsGK(player)
	return TeamService.GetTeam(player) ~= nil and TeamService.GetRole(player) == "GK"
end

function GK.InOwnBox(player, worldPos)
	local team = TeamService.GetTeam(player)
	if not team then
		return false
	end
	local sign = TeamService.GetDefendSign(team)
	local f = Field.Get()
	local lp = Field.ToLocal(worldPos)
	local depthFromLine = f.halfL - sign * lp.Z
	return depthFromLine >= -f.goalDepth and depthFromLine <= f.penaltyDepth + 0.5 and math.abs(lp.X) <= f.penaltyHalfW
end

function GK.Params(player, ballPos, now)
	if not GK.IsGK(player) or not GK.InOwnBox(player, ballPos) then
		return nil
	end
	local diving = diveUntil[player] and now < diveUntil[player]
	return {
		radius = Config.GK_CATCH_RADIUS * (diving and Config.GK_DIVE_RADIUS_MULT or 1),
		maxHeight = Config.GK_CATCH_HEIGHT,
		maxSpeed = Config.GK_CATCH_MAX_SPEED * (diving and 1.25 or 1),
		canParry = true,
	}
end

local function countSave(player, now)
	local shooter, untilT = BallService.GetShot()
	if shooter and now < untilT and TeamService.GetTeam(shooter) ~= TeamService.GetTeam(player) then
		MatchService.AddStat(player, "Saves", 1)
		if not player.IsAI then
			Remotes.get("Notify"):FireClient(player, "good", "Save!")
		end
	end
end

function GK.OnCatch(player, now)
	countSave(player, now)
	Remotes.get("CatchPlayed"):FireAllClients(player.UserId)
	if not player.IsAI then
		Remotes.get("Notify"):FireClient(player, "info", "Ball caught - PASS / LONG / SHOOT to release (" .. Config.GK_HOLD_TIME .. "s)")
	end
end

function GK.OnParry(player, now)
	countSave(player, now)
end

local function onDive(player, side)
	local b = buckets[player]
	if not b or not b:take() then
		return
	end
	if not Util.isNum(side, -1, 1) then
		return
	end
	side = side < -0.3 and -1 or (side > 0.3 and 1 or 0)
	local now = os.clock()
	if not GK.IsGK(player) or not MatchService.CanPlay() then
		return
	end
	local _, _, hrp = Util.getCharParts(player)
	if not hrp or now < (diveCd[player] or 0) then
		return
	end
	if not StaminaService.Spend(player, Config.GK_DIVE_STAMINA) then
		Remotes.get("ActionResult"):FireClient(player, "GKDIVE", false, "stamina", 0)
		return
	end
	diveCd[player] = now + Config.GK_DIVE_COOLDOWN
	diveUntil[player] = now + Config.GK_DIVE_DURATION
	Remotes.get("DiveApproved"):FireAllClients(player.UserId, side)
	Remotes.get("ActionResult"):FireClient(player, "GKDIVE", true, "", Config.GK_DIVE_COOLDOWN)
end

-- AI goalkeeper rig ----------------------------------------------------------------------------------------

local function part(name, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = true
	p.Parent = parent
	return p
end

local function joint(name, p0, p1, parent)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = p0.CFrame:ToObjectSpace(p1.CFrame)
	m.C1 = CFrame.new()
	m.Parent = parent
	return m
end

-- Builds a simple R6-style keeper rig. Motor6D C0 is computed from the parts' relative placement,
-- so the figure is assembled correctly regardless of exact sizes. Colours come from the club.
local function buildRig(team)
	local club = Clubs.Get(TeamService.GetClub(team))
	local primary = club and club.Primary or Color3.fromRGB(120, 120, 120)
	local secondary = club and club.Secondary or Color3.fromRGB(40, 40, 40)
	local skin = Color3.fromRGB(200, 160, 130)

	local model = Instance.new("Model")
	model.Name = "NXKeeper_" .. team

	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), primary, model)
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = CFrame.new(0, 10, 0)

	local torso = part("Torso", Vector3.new(2, 2, 1), primary, model)
	torso.CFrame = root.CFrame
	local head = part("Head", Vector3.new(1, 1, 1), skin, model)
	head.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
	local la = part("Left Arm", Vector3.new(1, 2, 1), primary, model)
	la.CFrame = root.CFrame * CFrame.new(-1.5, 0, 0)
	local ra = part("Right Arm", Vector3.new(1, 2, 1), primary, model)
	ra.CFrame = root.CFrame * CFrame.new(1.5, 0, 0)
	local ll = part("Left Leg", Vector3.new(1, 2, 1), secondary, model)
	ll.CFrame = root.CFrame * CFrame.new(-0.5, -2, 0)
	local rl = part("Right Leg", Vector3.new(1, 2, 1), secondary, model)
	rl.CFrame = root.CFrame * CFrame.new(0.5, -2, 0)

	joint("RootJoint", root, torso, root)
	joint("Neck", torso, head, torso)
	joint("Left Shoulder", torso, la, torso)
	joint("Right Shoulder", torso, ra, torso)
	joint("Left Hip", torso, ll, torso)
	joint("Right Hip", torso, rl, torso)

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.HipHeight = 2
	hum.WalkSpeed = Config.GK_AI_WALKSPEED
	hum.MaxHealth = 100
	hum.Health = 100
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = model

	model.PrimaryPart = root
	-- keep the keeper out of the way of the anti-teleport / stamina systems (it is not a real player)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "SoccerPlayers"
		end
	end
	return model, hum, root
end

local function spawnAI(team)
	if aiKeepers[team] then
		return
	end
	if not aiFolder then
		aiFolder = Instance.new("Folder")
		aiFolder.Name = "NXKeepers"
		aiFolder.Parent = Workspace
	end
	local model, hum, root = buildRig(team)
	model.Parent = aiFolder
	local entity = {
		IsAI = true,
		Team = team,
		UserId = -1,
		DisplayName = "NX Keeper",
		Name = "NXKeeper",
		Character = model,
		Parent = model,
		GetAttribute = function(self, k)
			return model:GetAttribute(k)
		end,
		SetAttribute = function(self, k, v)
			model:SetAttribute(k, v)
		end,
	}
	aiKeepers[team] = { entity = entity, model = model, hum = hum, root = root, diveCd = 0, shotSeen = 0 }
	GK.PlaceAI(team)
end

local function despawnAI(team)
	local k = aiKeepers[team]
	if not k then
		return
	end
	if BallService.GetHolder() == k.entity then
		-- release a held ball before removing the keeper
		BallService.SetLockout(k.entity, 0)
	end
	diveUntil[k.entity] = nil
	aiKeepers[team] = nil
	if k.model then
		k.model:Destroy()
	end
end

-- Put an AI keeper on its goal line.
function GK.PlaceAI(team)
	local k = aiKeepers[team]
	if not k or not k.root then
		return
	end
	local f = Field.Get()
	local sign = TeamService.GetDefendSign(team)
	local localPos = Vector3.new(0, 0, sign * (f.halfL - Config.GK_AI_LINE_OFFSET))
	local world = Field.ToWorld(localPos)
	local face = Field.DirToWorld(Vector3.new(0, 0, -sign))
	local pos = Vector3.new(world.X, f.ground + 3, world.Z)
	k.model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(face.X, 0, face.Z)))
	k.root.AssemblyLinearVelocity = Vector3.zero
end

local function teamHasRealGK(team)
	for _, p in ipairs(TeamService.GetMembers(team)) do
		if TeamService.GetRole(p) == "GK" then
			return true
		end
	end
	return false
end

local function matchActive()
	local s = MatchService.GetState()
	return s == "Kickoff" or s == "Live" or s == "HalfTime" or s == "GoalPause"
end

-- List of AI pseudo-players for BallService's catch check.
function GK.AIKeepers()
	local list = {}
	for _, k in pairs(aiKeepers) do
		table.insert(list, k.entity)
	end
	return list
end

-- Per-frame AI: spawn/despawn to match the real-GK situation, then position / dive.
function GK.Step(dt)
	local active = matchActive()
	for _, team in ipairs({ "RED", "BLUE" }) do
		local want = Config.GK_AI_ENABLED and active and not teamHasRealGK(team)
		if want and not aiKeepers[team] then
			spawnAI(team)
		elseif not want and aiKeepers[team] then
			despawnAI(team)
		end
	end
	if not active then
		return
	end
	local ball = BallService.GetBall()
	if not ball then
		return
	end
	local f = Field.Get()
	local now = os.clock()
	local lp = Field.ToLocal(ball.Position)
	local lv = f.cf:VectorToObjectSpace(ball.AssemblyLinearVelocity)
	local live = MatchService.CanPlay()

	for team, k in pairs(aiKeepers) do
		local hum, root = k.hum, k.root
		if hum and root and hum.Health > 0 then
			local sign = TeamService.GetDefendSign(team)
			local goalZ = sign * f.halfL
			local lineZ = sign * (f.halfL - Config.GK_AI_LINE_OFFSET)
			local maxX = f.goalHalfW - 1.2

			-- default: track the ball's X along the line
			local targetX = math.clamp(lp.X * 0.6, -maxX, maxX)

			-- shot reaction: ball heading toward this goal, close and fast
			local towardGoal = lv.Z * sign > 1
			local distToLine = math.abs(goalZ - lp.Z)
			if live and towardGoal and distToLine < Config.GK_AI_MAX_RANGE then
				local speed = math.abs(lv.Z)
				local t = speed > 1 and (distToLine / speed) or 99
				if t > 0 and t < 1.1 then
					local interceptX = math.clamp(lp.X + lv.X * t, -maxX, maxX)
					targetX = interceptX
					if now >= k.diveCd and math.abs(interceptX - (Field.ToLocal(root.Position).X)) > 2 then
						k.diveCd = now + Config.GK_DIVE_COOLDOWN
						diveUntil[k.entity] = now + Config.GK_DIVE_DURATION
					end
				end
			end

			local diving = diveUntil[k.entity] and now < diveUntil[k.entity]
			hum.WalkSpeed = diving and Config.GK_AI_DIVE_SPEED or Config.GK_AI_WALKSPEED
			local world = Field.ToWorld(Vector3.new(targetX, 0, lineZ))
			hum:MoveTo(Vector3.new(world.X, f.ground, world.Z))
		end
	end
end

function GK.Init()
	Remotes.get("GKDive").OnServerEvent:Connect(onDive)
	local function add(p)
		buckets[p] = Util.newBucket(Config.RATE_ACTION.rate, Config.RATE_ACTION.burst)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		add(p)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p], diveUntil[p], diveCd[p] = nil, nil, nil
	end)
	-- When a real player takes / leaves the GK role, re-evaluate the AI keepers.
	TeamService.Changed:Connect(function()
		-- Step() handles spawn/despawn on the next frame; nothing to do here.
	end)
end

return GK
