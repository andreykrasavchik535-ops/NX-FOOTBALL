--[[
	StarterPlayerScripts/SoccerClient/InputController (ModuleScript)
	Keyboard / mouse / gamepad bindings (touch buttons live in ActionBar).
	NX26: bindings are rebindable from Settings, input is gated to live match only, and the
	feint hotkeys cover all 28 feints:
	  1-0 = feints 1-10,  Ctrl+1-0 = 11-20,  Alt+1-8 = 21-28.
	KEYBOARD (defaults)  F / Left Mouse = SHOOT (hold)  E = PASS (hold)  R = LONG (hold)
	  Q = fast TACKLE  X = SLIDE  LeftShift = sprint toggle  L = shift lock  G = feint side
	  V / Tab = feint panel  Z / C = goalkeeper dive left / right
	GAMEPAD  X = SHOOT  A = PASS  Y = LONG  B = TACKLE  R1 = SLIDE  R2 = sprint  R3 = side  L3 = lock
	  L1 + face/dpad = feints 1-8,  L2 + face/dpad = feints 9-16,  L1+L2 + face/dpad = 17-24
]]
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SoccerShared")
local SettingsDefs = require(Shared:WaitForChild("SettingsDefs"))
local A = require(script.Parent:WaitForChild("ActionClient"))

local Input = {}
Input.PanelToggle = Instance.new("BindableEvent")
Input.LockToggle = Instance.new("BindableEvent")

local KC = Enum.KeyCode
local enabled = false
local bindings = {}
for action, key in pairs(SettingsDefs.Defaults.Controls) do
	bindings[action] = KC[key]
end

local NUMBER_KEYS = { KC.One, KC.Two, KC.Three, KC.Four, KC.Five, KC.Six, KC.Seven, KC.Eight, KC.Nine, KC.Zero }
local numberIndex = {}
for i, k in ipairs(NUMBER_KEYS) do
	numberIndex[k] = i
end

local PAD_FACE = { [KC.ButtonA] = 1, [KC.ButtonB] = 2, [KC.ButtonX] = 3, [KC.ButtonY] = 4 }
local PAD_DPAD = { [KC.DPadUp] = 5, [KC.DPadDown] = 6, [KC.DPadLeft] = 7, [KC.DPadRight] = 8 }

local active = {}
local l1, l2 = false, false

function Input.SetEnabled(value)
	enabled = value and true or false
	if not enabled then
		active = {}
	end
end

function Input.SetBindings(controls)
	if type(controls) ~= "table" then
		return
	end
	for action, keyName in pairs(controls) do
		if type(keyName) == "string" and KC[keyName] then
			bindings[action] = KC[keyName]
		end
	end
end

function Input.HotkeyFor(index)
	if index <= 10 then
		return tostring(index % 10)
	end
	if index <= 20 then
		return "Ctrl+" .. tostring((index - 10) % 10)
	end
	if index <= 28 then
		return "Alt+" .. tostring((index - 20) % 10)
	end
	return ""
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

local function feintIndex(code)
	local base = numberIndex[code]
	if not base then
		return nil
	end
	if UserInputService:IsKeyDown(KC.LeftControl) or UserInputService:IsKeyDown(KC.RightControl) then
		return base + 10
	end
	if UserInputService:IsKeyDown(KC.LeftAlt) or UserInputService:IsKeyDown(KC.RightAlt) then
		return base + 20
	end
	return base
end

local function onBegan(input, processed)
	if not enabled or processed then
		return
	end
	local id = keyId(input)
	local code = input.KeyCode

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		beginCharge(id, "SHOOT")
		return
	end

	if code == bindings.Shoot then
		beginCharge(id, "SHOOT")
	elseif code == bindings.Pass then
		beginCharge(id, "PASS")
	elseif code == bindings.Long then
		beginCharge(id, "LONG")
	elseif code == bindings.Tackle then
		A.Tackle("Fast")
	elseif code == bindings.Slide then
		A.Tackle("Slide")
	elseif code == bindings.Sprint then
		A.ToggleSprint()
	elseif code == bindings.Lock then
		Input.LockToggle:Fire()
	elseif code == bindings.Side then
		A.ToggleSide()
	elseif code == bindings.FeintPanel or code == KC.Tab then
		Input.PanelToggle:Fire()
	elseif code == bindings.DiveLeft then
		A.GKDive(-1)
	elseif code == bindings.DiveRight then
		A.GKDive(1)
	elseif numberIndex[code] then
		local index = feintIndex(code)
		if index and index <= 28 then
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

local PAD_KEYS = {
	KC.ButtonA, KC.ButtonB, KC.ButtonX, KC.ButtonY, KC.ButtonL1, KC.ButtonL2, KC.ButtonR1, KC.ButtonR2, KC.ButtonR3, KC.ButtonL3,
	KC.DPadUp, KC.DPadDown, KC.DPadLeft, KC.DPadRight,
}

local function padFeint(code)
	local page
	if l1 and l2 then
		page = 16
	elseif l1 then
		page = 0
	elseif l2 then
		page = 8
	else
		return nil
	end
	local base = PAD_FACE[code] or PAD_DPAD[code]
	if not base then
		return nil
	end
	local index = base + page
	if index > 28 then
		return nil
	end
	return index
end

local function padAction(_, state, input)
	if not enabled then
		return Enum.ContextActionResult.Pass
	end
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
