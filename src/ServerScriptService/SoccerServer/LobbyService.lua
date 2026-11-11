--[[
	ServerScriptService/SoccerServer/LobbyService (ModuleScript)
	Builds a small spawn platform above the pitch (Config.LOBBY_SPAWN) and a neutral SpawnLocation on it,
	so players in the menu / lobby stand somewhere safe instead of falling into the stadium.
	This is ADDITIVE geometry: it never touches the imported stadium. When a match starts, MatchService
	teleports players into their formation; when the match ends and the state returns to Lobby, players
	are brought back up here.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local LobbyService = {}
local spawnPart
local stateFolder

local function buildPlatform()
	local pos = Config.LOBBY_SPAWN
	local folder = Workspace:FindFirstChild("NXLobby")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "NXLobby"
		folder.Parent = Workspace
	end
	local platform = folder:FindFirstChild("LobbyPlatform")
	if not platform then
		platform = Instance.new("Part")
		platform.Name = "LobbyPlatform"
		platform.Anchored = true
		platform.Size = Vector3.new(46, 1, 46)
		platform.CFrame = CFrame.new(pos)
		platform.Material = Enum.Material.SmoothPlastic
		platform.Color = Color3.fromRGB(24, 28, 36)
		platform.TopSurface = Enum.SurfaceType.Smooth
		platform.BottomSurface = Enum.SurfaceType.Smooth
		platform.Parent = folder
	end
	local spawn = folder:FindFirstChild("LobbySpawn")
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Neutral = true
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0
		spawn.Parent = folder
	end
	spawnPart = spawn
end

local function sendToLobby(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and spawnPart then
		local target = spawnPart.CFrame.Position + Vector3.new(math.random(-8, 8), 3, math.random(-8, 8))
		char:PivotTo(CFrame.new(target))
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

function LobbyService.BringAll()
	for _, p in ipairs(Players:GetPlayers()) do
		sendToLobby(p)
	end
end

function LobbyService.Init()
	buildPlatform()
	stateFolder = ReplicatedStorage:WaitForChild("SoccerState")
	stateFolder:GetAttributeChangedSignal("State"):Connect(function()
		local s = stateFolder:GetAttribute("State")
		if s == "Lobby" or s == "Waiting" then
			task.delay(0.3, LobbyService.BringAll)
		end
	end)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			task.delay(0.4, function()
				local s = stateFolder:GetAttribute("State") or "Lobby"
				if s == "Lobby" or s == "Waiting" or s == "Results" then
					sendToLobby(p)
				end
			end)
		end)
	end)
end

return LobbyService
