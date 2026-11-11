--[[
	SoccerShared/FeintDefs (ModuleScript)

	Data-driven feints (28 total: the 21 requested moves plus 7 bonus). To ADD a feint: append one entry to the `raw` list (nothing else to change; buttons, hotkeys,
	server validation and animation slots are built from this list - add a slot with the same name to AnimationIds.Feints).

	NO COOLDOWNS. A feint needs the ball within Config.FEINT_REACH, costs Stamina, and that is all.

	How a feint moves the ball. The ball is a normal physics ball; during a feint the server steers it (it is never
	attached) along the feint's own motion, described in the player's local frame locked at the moment the feint starts:
	  f = studs forward, r = studs to the right (multiplied by the chosen side, -1 or +1), u = extra height.
	Phases (played in order):
	  { kind = "path",   dur = s, keys = { {t=0..1, f=, r=, u=}, ... } }   ball is steered along the path
	  { kind = "launch", dur = s, vf=, vr=, vu=, carry=, ghost= }          ball is kicked free ONCE (physics takes over)
	        carry = share of the player's own running speed added to the launch, ghost = seconds the ball passes
	        through players (a nutmeg goes through legs, a rainbow flick over the head)
	Body (local player only, client side): small movement / spin of the player's own character.
	  { t = startSeconds, f = , r = , dur = s }     adds velocity (studs/s) over dur
	  { t = startSeconds, spin = degrees, dur = s }  turns the character (sign follows side)
	Evade = { from, to }: seconds after the start during which tackles / touches by opponents cannot take the ball.
	Fool  = { radius, factor, seconds }: defenders within radius in front of you "bite" and are slowed to `factor` speed.
	MinSpeed / MaxSpeed: horizontal speed gate. AimOpponent: aim the ball at the nearest opponent ahead.
	NoMirror = true: ignore the side toggle.
]]
local FeintDefs = {}

local function K(t, f, r, u)
	return { t = t, f = f, r = r or 0, u = u or 0 }
end

-- Keys along a circle: starts at the front of the player and goes round (angle sign follows side).
local function circle(radius, centerF, n)
	local keys = {}
	for i = 0, n do
		local a = (i / n) * math.pi * 2
		table.insert(keys, K(i / n, centerF + radius * math.cos(a), radius * math.sin(a), 0))
	end
	return keys
end

local function sumDur(phases)
	local d = 0
	for _, p in ipairs(phases) do
		d = d + p.dur
	end
	return d
end

local raw = {
	-- 1. Step Over: the ball barely moves, the BODY goes the other way; defenders in front bite.
	{
		Id = "StepOver", Name = "Step Over", Category = "Move",
		Stamina = 5, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.55, keys = { K(0, 3, 0), K(0.35, 3.1, -0.9), K(0.7, 3.3, 0.6), K(1, 3.4, 0.2) } } },
		Body = { { t = 0.2, r = 14, dur = 0.2 } },
		Evade = { 0.15, 0.5 },
		Fool = { radius = 9, factor = 0.65, seconds = 0.35 },
	},
	-- 2. Double Step Over: two wobbles, two body shifts, longer evade.
	{
		Id = "DoubleStepOver", Name = "Double Step Over", Category = "Move",
		Stamina = 8, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.85, keys = { K(0, 3, 0), K(0.2, 3.1, -0.8), K(0.4, 3.1, 0.8), K(0.6, 3.2, -0.6), K(0.8, 3.3, 0.7), K(1, 3.5, 0.2) } } },
		Body = { { t = 0.2, r = 12, dur = 0.15 }, { t = 0.5, r = -18, dur = 0.2 } },
		Evade = { 0.15, 0.8 },
		Fool = { radius = 10, factor = 0.55, seconds = 0.5 },
	},
	-- 3. Roulette: the ball circles the body while the player spins 360, then runs on.
	{
		Id = "Roulette", Name = "Roulette", Category = "Spin",
		Stamina = 12, MinSpeed = 4,
		Phases = { { kind = "path", dur = 0.7, keys = circle(2.6, 0.5, 10) } },
		Body = { { t = 0.0, spin = 360, dur = 0.65 }, { t = 0.0, f = 6, dur = 0.6 } },
		Evade = { 0.1, 0.65 },
	},
	-- 4. Rainbow Flick: ball is pulled to the feet, then flicked high OVER the head, far ahead.
	{
		Id = "RainbowFlick", Name = "Rainbow Flick", Category = "Flick",
		Stamina = 14, MinSpeed = 0,
		Phases = {
			{ kind = "path", dur = 0.22, keys = { K(0, 3, 0), K(1, 2.0, 0) } },
			{ kind = "launch", dur = 0.9, vf = 16, vr = 0, vu = 44, carry = 0.6, ghost = 0.5 },
		},
		Body = { { t = 0.25, f = 16, dur = 0.5 } },
		Evade = { 0.2, 0.6 },
	},
	-- 5. Heel Flick: low pop-up with the heel, short distance, quick to collect.
	{
		Id = "HeelFlick", Name = "Heel Flick", Category = "Flick",
		Stamina = 8, MinSpeed = 0,
		Phases = {
			{ kind = "path", dur = 0.22, keys = { K(0, 3, 0), K(1, 1.5, 0.4) } },
			{ kind = "launch", dur = 0.55, vf = 12, vr = 0, vu = 30, carry = 0.5, ghost = 0.35 },
		},
		Body = { { t = 0.2, f = 8, dur = 0.4 } },
		Evade = { 0.15, 0.5 },
	},
	-- 6. Elastico: ball pushed out with the outside of the boot, snapped back across with the inside.
	{
		Id = "Elastico", Name = "Elastico", Category = "Move",
		Stamina = 10, MinSpeed = 3,
		Phases = { { kind = "path", dur = 0.6, keys = { K(0, 3, 0), K(0.25, 3, 2.2), K(0.5, 3, -2.4), K(1, 3.6, -3.2) } } },
		Body = { { t = 0.45, r = -18, dur = 0.2 } },
		Evade = { 0.2, 0.6 },
		Fool = { radius = 8, factor = 0.7, seconds = 0.3 },
	},
	-- 7. Reverse Elastico: the mirror order (inside first, outside second).
	{
		Id = "ReverseElastico", Name = "Reverse Elastico", Category = "Move",
		Stamina = 10, MinSpeed = 3,
		Phases = { { kind = "path", dur = 0.7, keys = { K(0, 3, 0), K(0.28, 2.4, -2.0), K(0.55, 2.2, 2.5), K(1, 3.4, 3.4) } } },
		Body = { { t = 0.5, r = 18, dur = 0.2 } },
		Evade = { 0.2, 0.65 },
		Fool = { radius = 8, factor = 0.7, seconds = 0.3 },
	},
	-- 8. Body Feint: tiny shoulder drop, cheapest feint, still makes defenders in front hesitate.
	{
		Id = "BodyFeint", Name = "Body Feint", Category = "Fake",
		Stamina = 3, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.35, keys = { K(0, 3, 0), K(0.5, 2.7, 0.3), K(1, 3, 0) } } },
		Body = { { t = 0.05, r = 10, dur = 0.12 }, { t = 0.2, r = -6, dur = 0.1 } },
		Evade = { 0.05, 0.35 },
		Fool = { radius = 11, factor = 0.55, seconds = 0.45 },
	},
	-- 9. Ball Roll: sole drags the ball 5 studs sideways, the player follows it.
	{
		Id = "BallRoll", Name = "Ball Roll", Category = "Move",
		Stamina = 5, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.5, keys = { K(0, 3, 0), K(0.4, 2.2, -2.5), K(1, 2.8, -5) } } },
		Body = { { t = 0.25, r = -14, dur = 0.25 } },
		Evade = { 0.1, 0.5 },
	},
	-- 10. Fake Shot: leg goes back, ball is poked forward and pulled back; the biggest "bite" radius.
	{
		Id = "FakeShot", Name = "Fake Shot", Category = "Fake",
		Stamina = 5, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.55, keys = { K(0, 3, 0), K(0.25, 4.8, 0), K(0.55, 1.9, 0), K(1, 3, 0) } } },
		Body = {},
		Evade = { 0.1, 0.5 },
		Fool = { radius = 12, factor = 0.45, seconds = 0.55 },
	},
	-- 11. Nutmeg: ball is rolled through the legs of the nearest opponent ahead (passes through players).
	{
		Id = "Nutmeg", Name = "Nutmeg", Category = "Push", AimOpponent = true, NoMirror = true,
		Stamina = 11, MinSpeed = 0,
		Phases = {
			{ kind = "path", dur = 0.12, keys = { K(0, 3, 0), K(1, 3.4, 0) } },
			{ kind = "launch", dur = 0.6, vf = 34, vr = 0, vu = 2, carry = 0.3, ghost = 0.7 },
		},
		Body = { { t = 0.12, f = 22, dur = 0.45 } },
		Evade = { 0.05, 0.3 },
	},
	-- 12. Drag Back: sole drags the ball BEHIND the player and the player turns 180 to follow it.
	{
		Id = "DragBack", Name = "Drag Back", Category = "Spin",
		Stamina = 8, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.65, keys = { K(0, 3, 0), K(0.35, 0.4, 0), K(1, -3.4, 0.8) } } },
		Body = { { t = 0.2, spin = 180, dur = 0.4 }, { t = 0.2, f = -8, dur = 0.3 } },
		Evade = { 0.1, 0.7 },
	},
	-- 13. La Croqueta: two quick inside-foot touches from one foot to the other, small and fast.
	{
		Id = "LaCroqueta", Name = "La Croqueta", Category = "Move",
		Stamina = 6, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.4, keys = { K(0, 3, 0), K(0.35, 2.6, 1.4), K(0.7, 2.6, -1.4), K(1, 3.2, -0.3) } } },
		Body = { { t = 0.1, r = -8, dur = 0.15 } },
		Evade = { 0.05, 0.4 },
		Fool = { radius = 7, factor = 0.75, seconds = 0.25 },
	},
	-- 14. McGeady Spin: wide spin with the ball orbiting the body, then it is released diagonally forward.
	{
		Id = "McGeadySpin", Name = "McGeady Spin", Category = "Spin",
		Stamina = 13, MinSpeed = 6,
		Phases = {
			{ kind = "path", dur = 0.75, keys = circle(3.2, 0.8, 12) },
			{ kind = "launch", dur = 0.25, vf = 12, vr = 8, vu = 0, carry = 0.7, ghost = 0.1 },
		},
		Body = { { t = 0.05, spin = 360, dur = 0.6 }, { t = 0.0, f = 6, dur = 0.6 } },
		Evade = { 0.12, 0.7 },
	},
	-- 15. Heel to Heel: S-shaped roll with both soles, ball ends up straight ahead.
	{
		Id = "HeelToHeel", Name = "Heel to Heel", Category = "Move",
		Stamina = 9, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.65, keys = { K(0, 3, 0), K(0.25, 1.6, 1.8), K(0.55, 1.2, -1.8), K(1, 3.4, 0) } } },
		Body = { { t = 0.3, f = 6, dur = 0.3 } },
		Evade = { 0.15, 0.7 },
	},
	-- 16. Body Feint Cut: shoulder drop one way, then the ball is cut hard the other way and forward.
	{
		Id = "BodyFeintCut", Name = "Body Feint Cut", Category = "Fake",
		Stamina = 5, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.5, keys = { K(0, 3, 0), K(0.4, 2.8, 1.0), K(0.75, 3.2, -1.6), K(1, 3.7, -2.5) } } },
		Body = { { t = 0.05, r = 9, dur = 0.12 }, { t = 0.22, r = -16, dur = 0.2 } },
		Evade = { 0.1, 0.5 },
		Fool = { radius = 10, factor = 0.55, seconds = 0.4 },
	},
	-- 17. Two Touch Quick: two short taps forward, the ball ends up a little ahead.
	{
		Id = "TwoTouchQuick", Name = "Two Touch Quick", Category = "Move",
		Stamina = 4, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.38, keys = { K(0, 3, 0), K(0.3, 3.7, 0.2), K(0.5, 2.9, 0), K(0.8, 4.3, 0), K(1, 5, 0) } } },
		Body = { { t = 0.1, f = 8, dur = 0.25 } },
		Evade = { 0.05, 0.35 },
	},
	-- 18. Chop: the ball is cut behind the standing leg and the player turns about a quarter.
	{
		Id = "Chop", Name = "Chop", Category = "Move",
		Stamina = 6, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.5, keys = { K(0, 3, 0), K(0.3, 2.2, 0.6), K(0.65, 1.5, -1.6), K(1, 2.6, -3.6) } } },
		Body = { { t = 0.1, spin = 90, dur = 0.3 }, { t = 0.15, r = -8, dur = 0.2 } },
		Evade = { 0.1, 0.5 },
		Fool = { radius = 8, factor = 0.7, seconds = 0.3 },
	},
	-- 19. Roulette Burst: a short roulette (one spin), then the ball is pushed ahead and the player bursts after it.
	{
		Id = "RouletteBurst", Name = "Roulette Burst", Category = "Spin",
		Stamina = 13, MinSpeed = 3,
		Phases = {
			{ kind = "path", dur = 0.5, keys = circle(2.3, 0.5, 8) },
			{ kind = "launch", dur = 0.3, vf = 22, vr = 0, vu = 0, carry = 0.5, ghost = 0.1 },
		},
		Body = { { t = 0.0, spin = 360, dur = 0.45 }, { t = 0.5, f = 14, dur = 0.35 } },
		Evade = { 0.1, 0.7 },
	},
	-- 20. Double Touch: one touch to the side, a second one across and forward.
	{
		Id = "DoubleTouch", Name = "Double Touch", Category = "Move",
		Stamina = 5, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.4, keys = { K(0, 3, 0), K(0.3, 3.4, 1.0), K(0.6, 3.8, -0.4), K(1, 4.4, 0) } } },
		Body = { { t = 0.12, r = -8, dur = 0.15 } },
		Evade = { 0.05, 0.4 },
		Fool = { radius = 7, factor = 0.75, seconds = 0.25 },
	},
	-- 21. Stepover Exit: a step over, then the ball is taken diagonally forward out of the move.
	{
		Id = "StepoverExit", Name = "Stepover Exit", Category = "Move",
		Stamina = 7, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.45, keys = { K(0, 3, 0), K(0.4, 3.2, -0.8), K(0.75, 3.4, 0.5), K(1, 3.7, 1.5) } } },
		Body = { { t = 0.15, r = 12, dur = 0.18 }, { t = 0.35, f = 10, dur = 0.25 } },
		Evade = { 0.1, 0.5 },
		Fool = { radius = 9, factor = 0.6, seconds = 0.35 },
	},
	-- 22. Lateral Heel-to-Heel: quick heel touches push the ball sideways across the body.
	{
		Id = "LateralHeelToHeel", Name = "Lateral Heel-to-Heel", Category = "Move",
		Stamina = 8, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.5, keys = { K(0, 3, 0), K(0.3, 2.6, 1.6), K(0.6, 2.8, 3.2), K(1, 3, 4.2) } } },
		Body = { { t = 0.15, r = 12, dur = 0.2 } },
		Evade = { 0.1, 0.5 },
	},
	-- 23. Sombrero Flick: the ball is lobbed up and over the nearest opponent ahead.
	{
		Id = "SombreroFlick", Name = "Sombrero Flick", Category = "Flick", AimOpponent = true,
		Stamina = 13, MinSpeed = 0,
		Phases = {
			{ kind = "path", dur = 0.2, keys = { K(0, 3, 0), K(1, 2.2, 0) } },
			{ kind = "launch", dur = 0.8, vf = 20, vr = 0, vu = 40, carry = 0.5, ghost = 0.5 },
		},
		Body = { { t = 0.2, f = 14, dur = 0.5 } },
		Evade = { 0.2, 0.6 },
	},
	-- 24. Stop and Go: the ball is stopped dead at the feet, then exploded forward.
	{
		Id = "StopAndGo", Name = "Stop and Go", Category = "Move",
		Stamina = 7, MinSpeed = 0,
		Phases = {
			{ kind = "path", dur = 0.3, keys = { K(0, 3, 0), K(0.5, 1.6, 0), K(1, 1.4, 0) } },
			{ kind = "launch", dur = 0.35, vf = 30, vr = 0, vu = 2, carry = 0.8, ghost = 0.1 },
		},
		Body = { { t = 0.3, f = 18, dur = 0.3 } },
		Evade = { 0.05, 0.5 },
		Fool = { radius = 8, factor = 0.7, seconds = 0.3 },
	},
	-- 25. Scoop Turn: the ball is scooped up and dragged around a 180 turn.
	{
		Id = "ScoopTurn", Name = "Scoop Turn", Category = "Spin",
		Stamina = 10, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.6, keys = { K(0, 3, 0), K(0.3, 1.5, 0.8, 1.2), K(0.6, -1, 1.2, 1.5), K(1, -2.5, 0.5, 0.5) } } },
		Body = { { t = 0.15, spin = 180, dur = 0.45 }, { t = 0.2, f = -6, dur = 0.3 } },
		Evade = { 0.1, 0.65 },
	},
	-- 26. V-Cut: the ball is pulled back then cut out diagonally, tracing a V.
	{
		Id = "VCut", Name = "V-Cut", Category = "Move",
		Stamina = 6, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.5, keys = { K(0, 3, 0), K(0.35, 0.8, 0), K(0.6, 1.5, -1.2), K(1, 3.2, -2.8) } } },
		Body = { { t = 0.3, r = -12, dur = 0.2 } },
		Evade = { 0.1, 0.5 },
		Fool = { radius = 8, factor = 0.7, seconds = 0.3 },
	},
	-- 27. Berba Spin: the ball is lifted slightly while the body spins 90 and bursts out.
	{
		Id = "BerbaSpin", Name = "Berba Spin", Category = "Spin",
		Stamina = 12, MinSpeed = 3,
		Phases = {
			{ kind = "path", dur = 0.55, keys = { K(0, 3, 0), K(0.3, 2, 0.5, 1.0), K(0.6, 1, 1.5, 0.8), K(1, 2.5, 2, 0) } },
			{ kind = "launch", dur = 0.25, vf = 18, vr = 6, vu = 0, carry = 0.7, ghost = 0.1 },
		},
		Body = { { t = 0.05, spin = 90, dur = 0.4 }, { t = 0.5, f = 14, dur = 0.3 } },
		Evade = { 0.1, 0.6 },
	},
	-- 28. Advanced Body Feint: a big shoulder drop that strongly freezes defenders, then a push.
	{
		Id = "AdvancedBodyFeint", Name = "Advanced Body Feint", Category = "Fake",
		Stamina = 4, MinSpeed = 0,
		Phases = { { kind = "path", dur = 0.5, keys = { K(0, 3, 0), K(0.3, 2.6, 0.6), K(0.6, 2.8, -0.4), K(1, 3.4, 0.3) } } },
		Body = { { t = 0.05, r = 14, dur = 0.15 }, { t = 0.25, r = -10, dur = 0.12 } },
		Evade = { 0.05, 0.55 },
		Fool = { radius = 13, factor = 0.4, seconds = 0.6 },
	},
}

-- Combos: feints used in this order, each starting within Config.COMBO_WINDOW of the previous one ending.
-- Rewards: staminaRefund = share of the last feint's stamina cost given back, evadeBonus = extra seconds of evade.
FeintDefs.Combos = {
	{ Name = "Quick Cut", Sequence = { "StepOver", "Elastico" }, Reward = { evadeBonus = 0.15, staminaRefund = 0.25 } },
	{ Name = "Street Pro", Sequence = { "Roulette", "FakeShot", "Nutmeg" }, Reward = { evadeBonus = 0.1, staminaRefund = 0.3 } },
	{ Name = "Silky Mix", Sequence = { "LaCroqueta", "BodyFeint", "McGeadySpin" }, Reward = { evadeBonus = 0.2, staminaRefund = 0.3 } },
	{ Name = "Double Flick", Sequence = { "HeelFlick", "RainbowFlick" }, Reward = { evadeBonus = 0.1, staminaRefund = 0.25 } },
	{ Name = "Roll & Turn", Sequence = { "BallRoll", "DragBack" }, Reward = { evadeBonus = 0.15, staminaRefund = 0.25 } },
	{ Name = "Heel Magic", Sequence = { "HeelToHeel", "Elastico" }, Reward = { evadeBonus = 0.15, staminaRefund = 0.25 } },
	{ Name = "V Master", Sequence = { "VCut", "ScoopTurn" }, Reward = { evadeBonus = 0.15, staminaRefund = 0.25 } },
	{ Name = "Sombrero Magic", Sequence = { "StopAndGo", "SombreroFlick" }, Reward = { evadeBonus = 0.1, staminaRefund = 0.3 } },
}

FeintDefs.List = {}
FeintDefs.ById = {}
for index, def in ipairs(raw) do
	def.Duration = sumDur(def.Phases)
	def.Index = index
	def.Body = def.Body or {}
	FeintDefs.List[index] = def
	FeintDefs.ById[def.Id] = def
end

return FeintDefs
