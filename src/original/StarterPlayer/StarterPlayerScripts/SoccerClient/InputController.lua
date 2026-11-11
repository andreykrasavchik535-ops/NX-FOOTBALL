--[[
	StarterPlayerScripts/SoccerClient/InputController (ModuleScript)
	Keyboard / mouse / gamepad bindings (touch buttons live in ActionBar).

	KEYBOARD  F or Left Mouse = SHOOT (hold to charge)   E = PASS (hold)   R = LONG (hold)
	          Q = fast TACKLE   X = SLIDE tackle   LeftShift = sprint ON/OFF (tap)   L = shift lock ON/OFF
	          1-9, 0 = feints 1-10      LeftCtrl + 1-5 = feints 11-15      G = swap feint side   Tab or V = show/hide the feint panel
	          Z / C = goalkeeper dive left / right
	GAMEPAD   X = SHOOT   A = PASS   Y = LONG   B = fast TACKLE   R1 = SLIDE   R2 = sprint ON/OFF   R3 = swap side   L3 = shift lock
	          hold L1 + A/B/X/Y = feints 1-4, L1 + D-pad up/down/left/right = 5-8
	          hold L2 + A/B/X/Y = feints 9-12, L2 + D-pad up/down/left = 13-15
	          D-pad left/right (no modifier) = goalkeeper dive
]]
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local A = require(script.Parent:WaitForChild("ActionClient"))

local Input = {}
Input.PanelToggle = Instance.new("BindableEvent")
Input.LockToggle = Instance.new("BindableEvent")

local KC = Enum.KeyCode
local NUMBER_KEYS = { KC.One, KC.Two, KC.Three, KC.Four, KC.Five, KC.Six, KC.Seven, KC.Eight, KC.Nine, KC.Zero }
local numberIndex = {}
for i, k in ipairs(NUMBER_KEYS) do
	numberIndex[k] = i
end

local PAD_FACE = { [KC.ButtonA] = 1, [KC.ButtonB] = 2, [KC.ButtonX] = 3, [KC.ButtonY] = 4 }
local PAD_DPAD = { [KC.DPadUp] = 5, [KC.DPadDown] = 6, [KC.DPadLeft] = 7, [KC.DPadRight] = 8 }

local active = {} -- [keyId] = charge action to end on release
local l1, l2 = false, false

-- Exposed so the feint panel can show the right hint.
function Input.HotkeyFor(index)
	if index <= 10 then
		return tostring(index % 10)
	end
	if index <= 15 then
		return "Ctrl+" .. tostring(index - 10)
	end
	return "" -- feints above 15 have no hotkey, use the on-screen button
end

local function keyId(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return "Mouse1"
	end
	return input.KeyCode
end

local function beginCharge(id, action)
	active[id] = action
	A.Begin(action)
end

local function padFeint(code)
	local page = l1 and 0 or (l2 and 8 or nil)
	if page == nil then
		return nil
	end
	local base = PAD_FACE[code] or PAD_DPAD[code]
	if not base then
		return nil
	end
	local index = base + page
	if index > 15 then
		return nil
	end
	return index
end

local function onBegan(input, processed)
	if processed then
		return
	end
	local id = keyId(input)
	local code = input.KeyCode

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		beginCharge(id, "SHOOT")
		return
	end

	-- keyboard
	if code == KC.F then
		beginCharge(id, "SHOOT")
	elseif code == KC.E then
		beginCharge(id, "PASS")
	elseif code == KC.R then
		beginCharge(id, "LONG")
	elseif code == KC.Q then
		A.Tackle("Fast")
	elseif code == KC.X then
		A.Tackle("Slide")
	elseif code == KC.LeftShift then
		A.ToggleSprint()
	elseif code == KC.L then
		Input.LockToggle:Fire()
	elseif code == KC.G then
		A.ToggleSide()
	elseif code == KC.Tab or code == KC.V then
		Input.PanelToggle:Fire()
	elseif code == KC.Z then
		A.GKDive(-1)
	elseif code == KC.C then
		A.GKDive(1)
	elseif numberIndex[code] then
		local index = numberIndex[code]
		if UserInputService:IsKeyDown(KC.LeftControl) then
			index = index + 10
		end
		if index <= 15 then
			A.Feint(index)
		end
	end
end

local function onEnded(input)
	local id = keyId(input)
	local action = active[id]
	if action then
		active[id] = nil
		A.End(action)
	end
end

-- Gamepad: bound through ContextActionService with HIGH priority, because the default Roblox controls already use
-- ButtonA (jump) and would swallow it before UserInputService could deliver it to us.
local PAD_KEYS = {
	KC.ButtonA, KC.ButtonB, KC.ButtonX, KC.ButtonY, KC.ButtonL1, KC.ButtonL2, KC.ButtonR1, KC.ButtonR2, KC.ButtonR3, KC.ButtonL3,
	KC.DPadUp, KC.DPadDown, KC.DPadLeft, KC.DPadRight,
}

local function padAction(_, state, input)
	local code = input.KeyCode
	if state ~= Enum.UserInputState.Begin and state ~= Enum.UserInputState.End then
		return Enum.ContextActionResult.Pass
	end
	local down = state == Enum.UserInputState.Begin

	if code == KC.ButtonL1 then
		l1 = down
		return Enum.ContextActionResult.Pass
	elseif code == KC.ButtonL2 then
		l2 = down
		return Enum.ContextActionResult.Pass
	end

	if not down then
		local action = active[code]
		if action then
			active[code] = nil
			A.End(action)
		end
		return Enum.ContextActionResult.Sink
	end

	local fi = padFeint(code)
	if fi then
		A.Feint(fi)
		return Enum.ContextActionResult.Sink
	end
	if code == KC.ButtonX then
		beginCharge(code, "SHOOT")
	elseif code == KC.ButtonA then
		beginCharge(code, "PASS")
	elseif code == KC.ButtonY then
		beginCharge(code, "LONG")
	elseif code == KC.ButtonB then
		A.Tackle("Fast")
	elseif code == KC.ButtonR1 then
		A.Tackle("Slide")
	elseif code == KC.ButtonR2 then
		A.ToggleSprint()
	elseif code == KC.ButtonL3 then
		Input.LockToggle:Fire()
	elseif code == KC.ButtonR3 then
		A.ToggleSide()
	elseif code == KC.DPadLeft then
		A.GKDive(-1)
	elseif code == KC.DPadRight then
		A.GKDive(1)
	else
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

function Input.Init()
	UserInputService.InputBegan:Connect(onBegan)
	UserInputService.InputEnded:Connect(onEnded)
	ContextActionService:BindActionAtPriority("NXGamepad", padAction, false, Enum.ContextActionPriority.High.Value, unpack(PAD_KEYS))
end

return Input
