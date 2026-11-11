--[[
	SoccerShared/AnimationIds (ModuleScript)      <<<  СЮДА ВСТАВЛЯЕШЬ СВОИ ANIMATION ID  >>>

	Здесь НЕТ выдуманных ID: каждый слот пустой ("") и ждёт твою анимацию.
	Пустой слот ничего не ломает: механика (удар, финт, подкат...) работает полностью, игра просто
	оставляет стандартную анимацию Roblox и (если Config.ANIM_PLACEHOLDER_POPUPS = true) показывает
	над игроком название приёма.

	КАК ДОБАВИТЬ АНИМАЦИЮ
	  1. Сделай анимацию (Animation Editor, R15) и опубликуй её (Publish to Roblox).
	     Анимация должна принадлежать ТЕБЕ или ТВОЕЙ ГРУППЕ, иначе в игре она не загрузится.
	  2. Скопируй ID (число) со страницы анимации в Creator Hub.
	  3. Вставь его между кавычками. Подойдёт любой вариант:
	         StepOver = "rbxassetid://123456789",
	         StepOver = "123456789",
	     (число без rbxassetid:// тоже принимается - скрипт добавит префикс сам)

	ПРИОРИТЕТЫ (задаются ниже, в Settings; в самом Animation Editor приоритет можно не менять)
	  Бег (Locomotion)  -> Movement, зацикленный (Looped).
	  Всё остальное     -> Action, играется один раз и перекрывает бег.

	ЛЕВЫЕ ВАРИАНТЫ (_Left)
	  Roblox не умеет зеркалить анимации на лету. Если финт можно сделать в обе стороны, сделай вторую
	  анимацию зеркально и вставь её в слот с суффиксом _Left. Если слот _Left пустой, для левой стороны
	  используется обычная (правая) анимация.

	ТАЙМИНГ УДАРА
	  Сервер запускает мяч сразу в момент нажатия/отпускания кнопки. Поэтому момент касания мяча в анимации
	  удара/паса делай примерно на 0.05-0.12 с от начала.

	Ключи в Feints совпадают с Id в FeintDefs (Step Over = StepOver и т.д.).
]]
local AnimationIds = {}

----------------------------------------------------------------------------------------------------
-- БЕГ  (проигрывается автоматически на твоём персонаже, скорость анимации подстраивается под скорость бега)
----------------------------------------------------------------------------------------------------
AnimationIds.Locomotion = {
	RunNoBall = "",  -- обычный бег БЕЗ мяча
	RunBall = "",    -- бег С мячом (мяч рядом: ты его только что тронул)
	IdleBall = "",   -- (необязательно) стойка с мячом на месте
}

----------------------------------------------------------------------------------------------------
-- ДЕЙСТВИЯ
----------------------------------------------------------------------------------------------------
AnimationIds.Actions = {
	Shoot = "",        -- удар по мячу (кнопка SHOOT)
	Pass = "",         -- пас (кнопка PASS)
	Long = "",         -- длинный пас / навес (кнопка LONG)
	-- Необязательно: свои анимации для видов ударов и пасов. Если пусто, играется обычный Shoot / Pass.
	ShotFinesse = "",  -- Finesse
	ShotTrivela = "",  -- Trivela
	ShotKnuckle = "",  -- Knuckle Shot
	Header = "",       -- удар головой
	PassThrough = "",  -- пас вразрез (Through)
	PassLob = "",      -- навесной пас (Lob)
	TackleFast = "",   -- обычный подкат-выпад (кнопка TACKLE)
	TackleSlide = "",  -- подкат в скольжении (кнопка SLIDE)
	GKDive = "",       -- прыжок вратаря (общий, если нет левого/правого)
	GKDiveLeft = "",   -- (необязательно) прыжок вратаря влево
	GKDiveRight = "",  -- (необязательно) прыжок вратаря вправо
	GKCatch = "",      -- вратарь поймал мяч
}

----------------------------------------------------------------------------------------------------
-- ФИНТЫ  (15 штук, по одному слоту на каждый)
----------------------------------------------------------------------------------------------------
AnimationIds.Feints = {
	StepOver = "",
	StepOver_Left = "",
	DoubleStepOver = "",
	DoubleStepOver_Left = "",
	Roulette = "",
	Roulette_Left = "",
	RainbowFlick = "",
	HeelFlick = "",
	Elastico = "",
	Elastico_Left = "",
	ReverseElastico = "",
	ReverseElastico_Left = "",
	BodyFeint = "",
	BallRoll = "",
	BallRoll_Left = "",
	FakeShot = "",
	Nutmeg = "",
	DragBack = "",
	DragBack_Left = "",
	LaCroqueta = "",
	LaCroqueta_Left = "",
	McGeadySpin = "",
	McGeadySpin_Left = "",
	HeelToHeel = "",
	HeelToHeel_Left = "",
	BodyFeintCut = "",
	BodyFeintCut_Left = "",
	TwoTouchQuick = "",
	Chop = "",
	Chop_Left = "",
	RouletteBurst = "",
	RouletteBurst_Left = "",
	DoubleTouch = "",
	DoubleTouch_Left = "",
	StepoverExit = "",
	StepoverExit_Left = "",
}

----------------------------------------------------------------------------------------------------
-- НАСТРОЙКИ ВОСПРОИЗВЕДЕНИЯ (менять не обязательно)
--   Priority: Core / Idle / Movement / Action / Action2 / Action3 / Action4
--   Speed: множитель скорости, Weight: вес, FadeIn/FadeOut: плавность, Looped: зациклить
--   ReferenceSpeed (только бег): при какой скорости персонажа анимация идёт со скоростью 1.0
-- Любой параметр можно переопределить для одной анимации в Overrides, ключ "Группа.Имя".
----------------------------------------------------------------------------------------------------
AnimationIds.Settings = {
	Defaults = {
		Locomotion = { Priority = "Movement", Looped = true, FadeIn = 0.2, FadeOut = 0.2, Speed = 1, Weight = 1, ReferenceSpeed = 20 },
		Actions = { Priority = "Action", Looped = false, FadeIn = 0.06, FadeOut = 0.15, Speed = 1, Weight = 1 },
		Feints = { Priority = "Action", Looped = false, FadeIn = 0.08, FadeOut = 0.15, Speed = 1, Weight = 1 },
	},
	Overrides = {
		["Locomotion.IdleBall"] = { ReferenceSpeed = 1 },
		["Actions.GKCatch"] = { Priority = "Action2", Speed = 1.4 },
		-- анимации из Mixamo-пака длинные (с вставанием): ускоряем, чтобы не мешали игре
		["Actions.TackleFast"] = { Speed = 1.7 },
		["Actions.TackleSlide"] = { Priority = "Action2", Speed = 1.5 },
		["Actions.GKDive"] = { Speed = 1.5 },
		-- пример: ["Feints.Roulette"] = { Speed = 1.15 },
	},
}

----------------------------------------------------------------------------------------------------
-- Служебные функции (ниже ничего менять не нужно)
----------------------------------------------------------------------------------------------------

-- "123" / 123 / "rbxassetid://123" -> "rbxassetid://123"; всё остальное -> nil (слот считается пустым)
function AnimationIds.Normalize(id)
	if type(id) == "number" and id > 0 and id == math.floor(id) then
		return "rbxassetid://" .. string.format("%d", id)
	end
	if type(id) ~= "string" then
		return nil
	end
	local digits = string.match(id, "^%s*rbxassetid://(%d+)%s*$") or string.match(id, "^%s*(%d+)%s*$")
	if digits and tonumber(digits) and tonumber(digits) > 0 then
		return "rbxassetid://" .. digits
	end
	return nil
end

-- Возвращает готовый ID для (группа, ключ, сторона) или nil. side: 1 = правая, -1 = левая.
function AnimationIds.Get(group, key, side)
	local g = AnimationIds[group]
	if type(g) ~= "table" then
		return nil
	end
	if side == -1 then
		local left = AnimationIds.Normalize(g[key .. "_Left"])
		if left then
			return left
		end
	end
	return AnimationIds.Normalize(g[key])
end

function AnimationIds.GetSettings(group, key)
	local d = AnimationIds.Settings.Defaults[group] or AnimationIds.Settings.Defaults.Actions
	local o = AnimationIds.Settings.Overrides[group .. "." .. key]
	local out = {}
	for k, v in pairs(d) do
		out[k] = v
	end
	if o then
		for k, v in pairs(o) do
			out[k] = v
		end
	end
	return out
end

-- Список пустых слотов (для отладки): { "Feints.StepOver", ... }. Слоты _Left не считаются обязательными.
function AnimationIds.ListMissing()
	local missing = {}
	local total = 0
	for _, group in ipairs({ "Locomotion", "Actions", "Feints" }) do
		local names = {}
		for key in pairs(AnimationIds[group]) do
			if not string.find(key, "_Left$") then
				table.insert(names, key)
			end
		end
		table.sort(names)
		for _, key in ipairs(names) do
			total = total + 1
			if not AnimationIds.Normalize(AnimationIds[group][key]) then
				table.insert(missing, group .. "." .. key)
			end
		end
	end
	return missing, total
end

return AnimationIds
