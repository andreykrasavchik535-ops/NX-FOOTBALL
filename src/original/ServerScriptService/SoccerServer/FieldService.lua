--[[
	ServerScriptService/SoccerServer/FieldService (ModuleScript)

	Single source of truth for the pitch. NOTHING else in the game knows world coordinates.
	Everything is derived from one Part: Workspace.SoccerPitch.PitchArea
	  Size.X = pitch width, Size.Z = pitch length, top surface = ground. Only its yaw is used (pitch must be level).
	Move/rotate/resize that part and the whole game follows (goal lines, out-of-bounds, spawns, restarts).
	If it does not exist and Config.BUILD_PLACEHOLDER_PITCH is true, a simple test pitch is built far from the map.
]]
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local FieldService = {}
local field -- data table, see build()

local function makeField(centerGround, yawLook, width, length)
	local cf = CFrame.lookAt(centerGround, centerGround + yawLook)
	field = {
		cf = cf,
		ground = centerGround.Y,
		halfW = width / 2,
		halfL = length / 2,
		goalHalfW = Config.GOAL_WIDTH / 2,
		goalH = Config.GOAL_HEIGHT,
		goalDepth = Config.GOAL_DEPTH,
		penaltyDepth = Config.PENALTY_DEPTH,
		penaltyHalfW = Config.PENALTY_WIDTH / 2,
		goalAreaDepth = Config.GOAL_AREA_DEPTH,
		goalAreaHalfW = Config.GOAL_AREA_WIDTH / 2,
		centerRadius = Config.CENTER_CIRCLE_RADIUS,
	}
end

local function buildPlaceholder(folder, origin, withFloor)
	local W, L = Config.PITCH_WIDTH, Config.PITCH_LENGTH
	local F = CFrame.new(origin)

	local function mk(name, size, localPos, color, transparency, collide, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = F * CFrame.new(localPos)
		p.Color = color
		p.Transparency = transparency or 0
		p.CanCollide = collide
		p.CanQuery = collide
		p.CanTouch = false
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end

	local grass
	if withFloor then
		grass = mk("PitchArea", Vector3.new(W, 2, L), Vector3.new(0, -1, 0), Color3.fromRGB(58, 125, 52), 0, true, Enum.Material.Grass)
		grass.CanTouch = false
		-- surrounding apron so the ball does not fall into void right after leaving the pitch
		mk("Apron", Vector3.new(W + 160, 2, L + 160), Vector3.new(0, -1.05, 0), Color3.fromRGB(46, 100, 42), 0, true, Enum.Material.Grass)
	end

	local white = Color3.fromRGB(255, 255, 255)
	local lineT = 0.8
	local function line(name, sx, sz, x, z)
		mk(name, Vector3.new(sx, 0.12, sz), Vector3.new(x, 0.06, z), white, 0, false)
	end
	local halfW, halfL = W / 2, L / 2
	line("LineLeft", lineT, L, -halfW, 0)
	line("LineRight", lineT, L, halfW, 0)
	line("LineGoalA", W, lineT, 0, -halfL)
	line("LineGoalB", W, lineT, 0, halfL)
	line("LineHalf", W, lineT, 0, 0)
	for _, s in ipairs({ -1, 1 }) do
		local pd, pw = Config.PENALTY_DEPTH, Config.PENALTY_WIDTH
		line("PenFront" .. s, pw, lineT, 0, s * (halfL - pd))
		line("PenL" .. s, lineT, pd, -pw / 2, s * (halfL - pd / 2))
		line("PenR" .. s, lineT, pd, pw / 2, s * (halfL - pd / 2))
		local gd, gw = Config.GOAL_AREA_DEPTH, Config.GOAL_AREA_WIDTH
		line("GAFront" .. s, gw, lineT, 0, s * (halfL - gd))
		line("GAL" .. s, lineT, gd, -gw / 2, s * (halfL - gd / 2))
		line("GAR" .. s, lineT, gd, gw / 2, s * (halfL - gd / 2))
	end
	local r, segs = Config.CENTER_CIRCLE_RADIUS, 28
	for i = 0, segs - 1 do
		local a = (i + 0.5) / segs * math.pi * 2
		local seg = mk("Circle" .. i, Vector3.new(lineT, 0.12, (2 * math.pi * r / segs) * 1.05),
			Vector3.new(math.cos(a) * r, 0.06, math.sin(a) * r), white, 0, false)
		seg.CFrame = F * CFrame.new(Vector3.new(math.cos(a) * r, 0.06, math.sin(a) * r)) * CFrame.Angles(0, -a, 0)
	end

	-- goals (frame collides with the ball, net is soft-looking but solid)
	local gw, gh, gd = Config.GOAL_WIDTH, Config.GOAL_HEIGHT, Config.GOAL_DEPTH
	for _, s in ipairs({ -1, 1 }) do
		local zLine = s * halfL
		mk("PostL" .. s, Vector3.new(0.7, gh, 0.7), Vector3.new(-gw / 2, gh / 2, zLine), white, 0, true)
		mk("PostR" .. s, Vector3.new(0.7, gh, 0.7), Vector3.new(gw / 2, gh / 2, zLine), white, 0, true)
		mk("Bar" .. s, Vector3.new(gw + 0.7, 0.7, 0.7), Vector3.new(0, gh, zLine), white, 0, true)
		local net = Color3.fromRGB(235, 235, 235)
		-- the net swallows the ball: no bounce (elasticity 0, heavy weight so it wins against the ball's own value)
		local netParts = {
			mk("NetBack" .. s, Vector3.new(gw, gh, 0.3), Vector3.new(0, gh / 2, zLine + s * gd), net, 0.55, true),
			mk("NetTop" .. s, Vector3.new(gw, 0.3, gd), Vector3.new(0, gh, zLine + s * gd / 2), net, 0.55, true),
			mk("NetSideL" .. s, Vector3.new(0.3, gh, gd), Vector3.new(-gw / 2, gh / 2, zLine + s * gd / 2), net, 0.55, true),
			mk("NetSideR" .. s, Vector3.new(0.3, gh, gd), Vector3.new(gw / 2, gh / 2, zLine + s * gd / 2), net, 0.55, true),
		}
		for _, np in ipairs(netParts) do
			np.CustomPhysicalProperties = PhysicalProperties.new(1, 1, 0, 1, 100)
		end
	end

	folder:SetAttribute("Placeholder", true)
	return grass
end

-- Finds or builds the pitch and computes the field table.
function FieldService.Init()
	local folder = Workspace:FindFirstChild(Config.PITCH_FOLDER_NAME)
	local area = folder and folder:FindFirstChild(Config.PITCH_PART_NAME)
	local stadium = Workspace:FindFirstChild(Config.STADIUM_MODEL_NAME)
	if not area and Config.USE_STADIUM_PITCH and stadium then
		-- stadium mode: find the grass surface under the pitch centre, build only lines + goals on it
		local c = Config.STADIUM_PITCH_CENTER
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { stadium }
		local rayY = Config.STADIUM_RAY_START_Y or 200
		local hit = Workspace:Raycast(Vector3.new(c.X, rayY, c.Z), Vector3.new(0, -(rayY + 200), 0), params)
		local groundY = hit and hit.Position.Y or Config.STADIUM_FALLBACK_GROUND_Y
		if type(Config.STADIUM_GROUND_Y) == "number" then
			groundY, hit = Config.STADIUM_GROUND_Y, nil
		end
		folder = folder or Instance.new("Folder")
		folder.Name = Config.PITCH_FOLDER_NAME
		folder.Parent = Workspace
		buildPlaceholder(folder, Vector3.new(c.X, groundY, c.Z), hit == nil)
		folder:SetAttribute("StadiumGroundY", groundY)
		warn(string.format("[Soccer] Stadium mode: ground Y = %.2f (%s)", groundY, hit and ("raycast hit " .. hit.Instance.Name) or "NO surface found, built a floor at fallback height"))
		makeField(Vector3.new(c.X, groundY, c.Z), Vector3.new(0, 0, -1), Config.PITCH_WIDTH, Config.PITCH_LENGTH)
		return field
	end
	if not area then
		if not Config.BUILD_PLACEHOLDER_PITCH then
			error("[Soccer] Workspace." .. Config.PITCH_FOLDER_NAME .. "." .. Config.PITCH_PART_NAME .. " not found")
		end
		folder = folder or Instance.new("Folder")
		folder.Name = Config.PITCH_FOLDER_NAME
		folder.Parent = Workspace
		area = buildPlaceholder(folder, Config.PLACEHOLDER_ORIGIN, true)
		warn("[Soccer] No PitchArea found - built a placeholder test pitch at " .. tostring(Config.PLACEHOLDER_ORIGIN))
	end
	local size = area.Size
	local top = area.Position + Vector3.new(0, size.Y / 2, 0)
	local look = Util.flatUnit(area.CFrame.LookVector, Vector3.new(0, 0, -1))
	-- the part's local Z axis is the pitch length
	if size.Z < size.X then
		warn("[Soccer] PitchArea.Size.Z should be the long side; using Z as length anyway")
	end
	makeField(top, look, size.X, size.Z)
	return field
end

function FieldService.Get()
	return field
end

function FieldService.ToLocal(worldPos)
	return field.cf:PointToObjectSpace(worldPos)
end

function FieldService.ToWorld(localPos)
	return field.cf:PointToWorldSpace(localPos)
end

function FieldService.DirToWorld(localDir)
	return field.cf:VectorToWorldSpace(localDir)
end

return FieldService
