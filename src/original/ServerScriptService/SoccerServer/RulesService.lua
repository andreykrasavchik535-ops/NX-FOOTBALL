--[[
	ServerScriptService/SoccerServer/RulesService (ModuleScript)
	Goals and out-of-play, computed ONLY from the ball position in pitch-local coordinates
	(FieldService), so it works for any stadium once PitchArea is placed.

	Goal: ball centre fully beyond the goal line (by one radius), between the posts, below the bar,
	      having been in play on the previous frame. Counted by the server only.
	Out : over a touchline -> throw-in; over a goal line -> corner or goal kick (decided by last touch).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local Config = require(Shared:WaitForChild("Config"))

local Field = require(script.Parent:WaitForChild("FieldService"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))
local BallService = require(script.Parent:WaitForChild("BallService"))

local Rules = {}
local active = false
local wasInside = true
local R = Config.BALL_DIAMETER / 2

Rules.OnGoal = nil -- function(scoringTeam, scorer, assister, ownGoal)
Rules.OnOut = nil  -- function(kind, restartTeam, worldSpot)

function Rules.SetActive(value)
	active = value
	wasInside = true
end

local function defenderOfEnd(sign)
	if TeamService.GetDefendSign("RED") == sign then
		return "RED"
	end
	return "BLUE"
end

local function spot(x, z)
	return Field.ToWorld(Vector3.new(x, R + 0.15, z))
end

function Rules.Step()
	if not active then
		return
	end
	local ball = BallService.GetBall()
	if not ball then
		return
	end
	local f = Field.Get()
	local lp = Field.ToLocal(ball.Position)
	local overLine = math.abs(lp.Z) - f.halfL
	local overSide = math.abs(lp.X) - f.halfW

	-- goal
	if overLine > R and wasInside and math.abs(lp.X) <= f.goalHalfW and (lp.Y) <= f.goalH then
		active = false
		local sign = lp.Z > 0 and 1 or -1
		local defender = defenderOfEnd(sign)
		local attacker = TeamService.Other(defender)
		local toucher, toucherTeam, prevT, prevTeam, prevTime = BallService.GetLastTouch()
		local own = toucherTeam == defender
		local scorer, assister = nil, nil
		if not own then
			scorer = toucher
			if prevT and prevTeam == attacker and prevT ~= toucher and os.clock() - prevTime <= 6 then
				assister = prevT
			end
		else
			scorer = toucher
		end
		if Rules.OnGoal then
			Rules.OnGoal(attacker, scorer, assister, own)
		end
		return
	end

	-- out of play
	if overSide > R or overLine > R then
		active = false
		local _, toucherTeam = BallService.GetLastTouch()
		if overSide > R and overSide >= overLine then
			-- throw-in for the team that did not touch last
			local team = toucherTeam and TeamService.Other(toucherTeam) or "RED"
			local sx = lp.X > 0 and 1 or -1
			local z = math.clamp(lp.Z, -f.halfL + 8, f.halfL - 8)
			if Rules.OnOut then
				Rules.OnOut("Throw-in", team, spot(sx * (f.halfW - 0.5), z))
			end
		else
			local sign = lp.Z > 0 and 1 or -1
			local defender = defenderOfEnd(sign)
			if toucherTeam == defender then
				local sx = lp.X > 0 and 1 or -1
				if Rules.OnOut then
					Rules.OnOut("Corner", TeamService.Other(defender), spot(sx * (f.halfW - 1.5), sign * (f.halfL - 1.5)))
				end
			else
				if Rules.OnOut then
					Rules.OnOut("Goal kick", defender, spot(0, sign * (f.halfL - f.goalAreaDepth)))
				end
			end
		end
		return
	end
	wasInside = overLine <= R
end

return Rules
