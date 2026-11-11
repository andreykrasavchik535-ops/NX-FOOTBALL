--[[
	SoccerShared/Config (ModuleScript)
	ALL tunable numbers live here. Distances are studs, speeds studs/second, times seconds.
	Set TEST_MODE = false before publishing.
]]
local Config = {}

-- Test mode ----------------------------------------------------------------
Config.TEST_MODE = true          -- true: 1 player can start a match, short halves, fast timers

-- Match ----------------------------------------------------------------------
Config.TEAM_SIZE = 5             -- players per team (5 = 5v5, set 11 for 11v11). Formations adapt automatically.
Config.MIN_PLAYERS_TO_START = 2  -- total players needed to start a match
Config.HALF_SECONDS = 180        -- length of one half
Config.HALFTIME_SECONDS = 12
Config.INTERMISSION_SECONDS = 10 -- wait after enough players joined
Config.KICKOFF_SECONDS = 4       -- freeze + countdown before every kickoff
Config.GOAL_PAUSE_SECONDS = 4
Config.FINISHED_SECONDS = 12
Config.ABANDON_AFTER_SECONDS = 20 -- match is abandoned if a team stays empty this long
Config.KICKOFF_EXCLUSIVE = 6     -- only the kickoff team may touch the ball for this long
Config.RESTART_FREEZE = 1.2      -- ball is held still at a throw-in / corner / goal kick spot
Config.RESTART_EXCLUSIVE = 6     -- only the restart team may touch the ball for this long
Config.AUTO_BALANCE = true      -- a team that has TEAM_MAX_LEAD more players than the other one is closed for new players
Config.TEAM_MAX_LEAD = 2

-- Teams -----------------------------------------------------------------------
Config.RED_COLOR = BrickColor.new("Bright red")
Config.BLUE_COLOR = BrickColor.new("Bright blue")

-- Pitch (used by FieldService; real stadium: place Workspace.SoccerPitch.PitchArea) --
Config.PITCH_FOLDER_NAME = "SoccerPitch"
Config.PITCH_PART_NAME = "PitchArea"   -- Size.X = width, Size.Z = length, top surface = ground
Config.BUILD_PLACEHOLDER_PITCH = true  -- build a simple test pitch when no PitchArea exists
Config.PLACEHOLDER_ORIGIN = Vector3.new(2000, 0, 0) -- far from any stadium on purpose
-- Stadium mode: no PitchArea part needed. The pitch is centred at STADIUM_PITCH_CENTER (X,Z) with its long side
-- along world Z; ground height is auto-detected by a raycast onto the stadium model (fallback height below).
Config.USE_STADIUM_PITCH = true
Config.STADIUM_MODEL_NAME = "Tottenham"
Config.STADIUM_PITCH_CENTER = Vector3.new(0, 0, 0)
Config.STADIUM_FALLBACK_GROUND_Y = 4.5
Config.STADIUM_GROUND_Y = nil          -- set a number to skip auto-detection and force the ground height
Config.STADIUM_RAY_START_Y = 200       -- the ground raycast starts this high (roof/trusses above it are ignored)
Config.PITCH_WIDTH = 243
Config.PITCH_LENGTH = 375
Config.GOAL_WIDTH = 26
Config.GOAL_HEIGHT = 9
Config.GOAL_DEPTH = 8
Config.PENALTY_DEPTH = 59
Config.PENALTY_WIDTH = 144
Config.GOAL_AREA_DEPTH = 20
Config.GOAL_AREA_WIDTH = 65
Config.CENTER_CIRCLE_RADIUS = 33

-- Ball physics ----------------------------------------------------------------------
Config.BALL_DIAMETER = 2.2
Config.BALL_DENSITY = 0.7
Config.BALL_FRICTION = 0.5
Config.BALL_ELASTICITY = 0.62
Config.BALL_GRAVITY_SCALE = 0.75   -- 1 = normal Roblox gravity; lower = floatier ball
Config.BALL_GROUND_DRAG = 0.55     -- exp decay per second while rolling
Config.BALL_AIR_DRAG = 0.06
Config.BALL_DEAD_DRAG = 3.2        -- extra damping while the ball is dead (goal scored / match paused)
Config.BALL_MAX_SPEED = 150
Config.BALL_STOP_SPEED = 0.4       -- below this the rolling ball is stopped

-- Ball touches (NOTHING is ever glued to the player) ---------------------------------------------------
-- The ball is a free physics object. A player influences it only by
--   * physically bumping it (body collision),
--   * a short "foot touch" impulse while running into it (below),
--   * a first-touch cushion when a pass arrives (below),
--   * kicking / tackling / feinting on purpose.
Config.TOUCH_RADIUS = 3.1          -- horizontal distance (player centre -> ball centre) for a foot touch
Config.TOUCH_MAX_HEIGHT = 3.2      -- ball centre height above ground for a foot touch
Config.TOUCH_CONE_DEG = 70         -- the ball must be within this angle of the running direction (feet are in front)
Config.TOUCH_MIN_SPEED = 3         -- the player must be running at least this fast to push the ball
Config.TOUCH_INTERVAL = 0.2        -- seconds between two touches by the same player
Config.TOUCH_CARRY = 1.0           -- ball speed after a touch = player speed * this + push
Config.TOUCH_PUSH_MIN = 2.0        -- extra studs/s given on top of the player's speed (walking)
Config.TOUCH_PUSH_MAX = 5.5        -- ... (full sprint): the ball always runs a little ahead, then slows by drag
Config.TOUCH_SIDE_KEEP = 0.35      -- share of the ball's old sideways speed that survives a touch
Config.TOUCH_MAX_REL_SPEED = 34    -- balls arriving faster than this (relative to the player) are not "touched"
Config.TRAP_ENABLED = true         -- first-touch cushion for arriving passes
Config.TRAP_RADIUS = 2.9
Config.TRAP_MIN_BALL_SPEED = 5
Config.TRAP_MAX_BALL_SPEED = 62    -- faster balls are not controlled (first-touch limit)
Config.TRAP_STRENGTH = 0.72        -- 0 = ball ignores the player, 1 = ball takes the player's speed
Config.TRAP_INTERVAL = 0.4
Config.CONTROL_RADIUS = 5.0        -- "in control" (HasBall) = last toucher within this distance...
Config.CONTROL_HEIGHT = 4.5
Config.CONTROL_MEMORY = 1.1        -- ...and touched the ball less than this many seconds ago. Display/animation only.
Config.POSSESSION_LOCKOUT = 0.35   -- after your own kick you cannot touch the ball again for this long
Config.TACKLED_LOCKOUT = 0.7       -- dispossessed player lockout
Config.KICK_GHOST_TIME = 0.14      -- ball ignores character collisions right after a kick
Config.KICK_CARRY = 0.35           -- share of player's velocity added to a kick
Config.KICK_REACH = 4.8            -- strike distance (horizontal, player centre -> ball centre)
Config.KICK_MAX_HEIGHT = 6.5       -- ball centre height above ground that can still be struck
Config.HEADING_SMOOTH = 12

-- Kicks ----------------------------------------------------------------------------------------
Config.CHARGE_TIME = 1.0            -- seconds to full charge (server-timed)
Config.MAX_AIM_ANGLE = 110          -- degrees: aim may differ from body facing by at most this
Config.COOLDOWNS = { SHOOT = 0.55, PASS = 0.3, LONG = 0.8 }
Config.KICK_STAMINA = { SHOOT = 6, PASS = 2, LONG = 7 }
Config.SHOOT_SPEED = { min = 62, max = 138 }
Config.SHOOT_LIFT = { min = 0.04, max = 0.2 }   -- vertical/horizontal speed ratio
Config.SHOOT_SPREAD_DEG = 2.5                    -- random error at zero stamina/full charge
Config.PASS_SPEED = { min = 40, max = 82 }
Config.PASS_RANGE = 130
Config.PASS_ASSIST_ANGLE = 22       -- degrees
Config.PASS_ASSIST_STRENGTH = 0.45  -- 0 = none, 1 = snaps to the teammate
Config.PASS_DIST_FACTOR = 1.55      -- pass speed per stud to the assisted target
Config.LONG_SPEED = { min = 72, max = 128 }
Config.LONG_ANGLE_DEG = 40

-- Shot / pass styles (the style is chosen with the on-screen buttons; keyboard keys use "Normal").
-- speed / lift / spread are multipliers of the Normal shot. curve = a SMALL bend of the flight path: the ball turns by
-- `deg` degrees in total (scaled by charge) at `rate` degrees per second, and only while it is flying fast. Keep these
-- numbers small: big values look like a bug. Set curve = nil (or deg = 0) to switch the bend off.
Config.SHOT_STYLES = {
	Normal  = { speed = 1.0,  lift = 1.0,  spread = 1.0, stamina = 1.0 },
	Finesse = { speed = 0.84, lift = 1.2,  spread = 0.4, stamina = 0.9, curve = { deg = 13, rate = 26, dur = 1.1, dir = 1 } },
	Trivela = { speed = 0.92, lift = 0.9,  spread = 0.6, stamina = 1.0, curve = { deg = 15, rate = 30, dur = 1.1, dir = -1 } },
	Knuckle = { speed = 1.08, lift = 0.5,  spread = 1.7, stamina = 1.1 },
	Header  = { speed = 0.5,  lift = 0.0,  spread = 1.0, stamina = 0.5, minHeight = 0.5 }, -- only when the ball is above the body centre (chest height or higher)
}
Config.PASS_STYLES = { Normal = true, Through = true, Lob = true }
Config.LOB_ANGLE_DEG = 38


-- Tackles ---------------------------------------------------------------------------------------
Config.TACKLE_CONE_DEG = 75
Config.TACKLE_BEHIND_BONUS = 0.15
Config.TACKLE_CHALLENGE_RADIUS = 4.5 -- an opponent this close to the ball counts as "challenged" even if he is not in control
Config.TACKLES = {
	Fast  = { cooldown = 2.0, reach = 6.5, window = 0.35, lunge = 30, stamina = 9,  winChance = 0.6,  recovery = 0.35, clean = true },
	Slide = { cooldown = 4.0, reach = 10,  window = 0.55, lunge = 52, stamina = 17, winChance = 0.72, recovery = 0.95, clean = false },
}
Config.TACKLE_POP_SPEED = 30
Config.TACKLE_WIN_SPEED = 16        -- clean tackle: ball rolls toward the tackler's feet at about this speed

-- Stamina ----------------------------------------------------------------------------------------
Config.STAMINA_MAX = 100
Config.WALK_SPEED = 16
Config.SPRINT_SPEED = 24
Config.EXHAUSTED_SPEED = 12
Config.JUMP_POWER = 40
Config.STAMINA_DRAIN = 16           -- per second of sprinting
Config.STAMINA_REGEN = 11
Config.STAMINA_REGEN_DELAY = 1.0
Config.STAMINA_MIN_TO_SPRINT = 12
Config.STAMINA_EXHAUSTED_UNTIL = 22 -- after hitting 0 you stay slow until this value

-- Feints ------------------------------------------------------------------------------------------
-- NO COOLDOWNS: a feint costs stamina and needs the ball within reach. That is all.
Config.FEINT_REACH = 4.8            -- ball must be this close (horizontal) to start a feint
Config.FEINT_MAX_HEIGHT = 4.5       -- ... and no higher than this
Config.FEINT_INTERRUPT_AT = 0       -- 0 = a new feint may replace the running one at once; 0.5 = only after half of it
Config.FEINT_GAIN = 26              -- how hard a feint pulls the ball toward its path
Config.FEINT_SMOOTH = 26            -- velocity smoothing rate while a feint moves the ball
Config.FEINT_MAX_EXTRA_SPEED = 44   -- ball may move this much faster than the player during a feint
Config.FEINT_BREAK_DISTANCE = 8     -- the ball farther than this from the player ends the feint
Config.FEINT_LAUNCH_LOCKOUT = 0.18  -- the feinter cannot re-touch the ball for this long after a launch
Config.FEINT_FOOL_ENABLED = true    -- fake feints (step over, body feint, fake shot...) briefly slow the defenders in front
Config.COMBO_WINDOW = 1.1           -- max gap between chained feints

-- Steal during a feint is gone: opponents simply touch/tackle the ball; the feint ends if they get it (unless evading).

-- Goalkeeper -----------------------------------------------------------------------------------------
Config.GK_AUTO_CATCH = true         -- keeper hands catch the ball inside his own box (the ONLY place a ball is held)
Config.GK_HOLD_IN_BOX_ONLY = true   -- a held ball is released if the keeper walks out of his box
Config.GK_CATCH_RADIUS = 5.2
Config.GK_CATCH_HEIGHT = 9.5
Config.GK_CATCH_MAX_SPEED = 78
Config.GK_HOLD_TIME = 5
Config.GK_DIVE_COOLDOWN = 2.5
Config.GK_DIVE_DURATION = 0.7
Config.GK_DIVE_RADIUS_MULT = 1.8
Config.GK_DIVE_STAMINA = 14
Config.GK_DIVE_IMPULSE = 38
Config.GK_PARRY_COOLDOWN = 0.6
Config.GK_PUNT_SPEED = 62

-- Animations -------------------------------------------------------------------------------------------
-- Real animation ids go into SoccerShared/AnimationIds. While a slot there is empty the game simply keeps its
-- default Roblox animation and (optionally) shows the move name above the player.
Config.ANIM_PLACEHOLDER_POPUPS = true  -- text popup ("STEP OVER", "SLIDE TACKLE"...) for every move without an animation
Config.ANIM_RUN_START_SPEED = 3.5      -- speed at which the run animation starts
Config.ANIM_RUN_STOP_SPEED = 1.5       -- ...and stops (hysteresis)

-- UI -------------------------------------------------------------------------------------------------------
Config.UI_SCALE = 1                    -- multiplies the size of every on-screen control
Config.UI_DEFAULT_MODE = "Dribble"   -- round buttons shown at start: "Shoot", "Dribble", "Pass" or "Defend"
Config.UI_FEINT_DOCK_OPEN = true       -- the feint buttons are visible from the start

-- Anti-exploit ------------------------------------------------------------------------------------------
Config.RATE_ACTION = { rate = 8, burst = 6 }
Config.RATE_FEINT = { rate = 8, burst = 5 }
Config.RATE_MISC = { rate = 3, burst = 4 }
Config.MOVE_CHECK_INTERVAL = 0.5
Config.MOVE_MAX_DISTANCE = 32       -- studs per check interval (0.5s); sprint=12, tackle lunge/dive bursts stay below
Config.MOVE_STRIKES_TO_RESET = 3

-- Debug -------------------------------------------------------------------------------------------------
Config.DEBUG = false

if Config.TEST_MODE then
	Config.MIN_PLAYERS_TO_START = 1
	Config.HALF_SECONDS = 60
	Config.HALFTIME_SECONDS = 6
	Config.INTERMISSION_SECONDS = 4
	Config.FINISHED_SECONDS = 8
end

return Config
