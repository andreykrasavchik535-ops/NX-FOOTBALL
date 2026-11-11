--[[
	SoccerShared/Util (ModuleScript)
	Small helpers used by both server and client.
]]
local Util = {}

function Util.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Horizontal unit vector, or fallback when v is (almost) vertical / zero.
function Util.flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

function Util.isFiniteVec(v)
	if typeof(v) ~= "Vector3" then
		return false
	end
	local lim = 1e6
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < lim and math.abs(v.Y) < lim and math.abs(v.Z) < lim
end

function Util.isNum(n, lo, hi)
	return type(n) == "number" and n == n and n >= lo and n <= hi
end

-- Rotate vector around the Y axis (radians).
function Util.rotateY(v, ang)
	local c, s = math.cos(ang), math.sin(ang)
	return Vector3.new(v.X * c + v.Z * s, v.Y, -v.X * s + v.Z * c)
end

-- Signed horizontal angle from a to b (radians, positive = counter-clockwise seen from above).
function Util.signedAngle(a, b)
	local cross = a.X * b.Z - a.Z * b.X
	local dot = a.X * b.X + a.Z * b.Z
	return math.atan2(-cross, dot)
end

-- Token bucket (rate limiter).
local Bucket = {}
Bucket.__index = Bucket

function Util.newBucket(ratePerSecond, burst)
	return setmetatable({ rate = ratePerSecond, burst = burst, tokens = burst, last = os.clock() }, Bucket)
end

function Bucket:take()
	local now = os.clock()
	self.tokens = math.min(self.burst, self.tokens + (now - self.last) * self.rate)
	self.last = now
	if self.tokens >= 1 then
		self.tokens = self.tokens - 1
		return true
	end
	return false
end

-- Character helpers -------------------------------------------------------

-- Returns character, humanoid, rootPart for a living character, or nil.
function Util.getCharParts(player)
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return nil
	end
	return char, hum, hrp
end

-- Distance from HumanoidRootPart centre down to the ground when standing.
function Util.hipOffset(hum, hrp)
	if hum.RigType == Enum.HumanoidRigType.R6 then
		return 3
	end
	return hum.HipHeight + hrp.Size.Y / 2
end

function Util.groundY(hum, hrp)
	return hrp.Position.Y - Util.hipOffset(hum, hrp)
end

return Util
