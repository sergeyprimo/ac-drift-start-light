-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР СТАРТА ДРИФТА)
-- Профессиональный трековый модуль соревнований ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch
-- Версия: 3.0 (Drift Edition: Настраиваемый интервал + Реалистичные 3D-линзы)
-- ====================================================================

local GREEN_DURATION  = 2.5 -- Секунды горения зелёного света

local STORAGE_KEY_POS_X    = "drift_tree_pos_x"
local STORAGE_KEY_POS_Y    = "drift_tree_pos_y"
local STORAGE_KEY_ENABLED  = "drift_tree_enabled"
local STORAGE_KEY_HOTKEY   = "drift_tree_hotkey"
local STORAGE_KEY_INTERVAL = "drift_tree_interval"

local frameCount = 0
local lastUpdateFrame = -1
local posInitialized = false
local prevHotkeyDown = false
local previewPilotMode = false

-- Доступные горячие клавиши для назначения
local HOTKEY_LIST = {
    { id = "F8",        name = "F8 (по умолчанию)", short = "F8",    vk = 119, uiKey = "F8" },
    { id = "F7",        name = "F7",                 short = "F7",    vk = 118, uiKey = "F7" },
    { id = "F6",        name = "F6",                 short = "F6",    vk = 117, uiKey = "F6" },
    { id = "F5",        name = "F5",                 short = "F5",    vk = 116, uiKey = "F5" },
    { id = "F9",        name = "F9",                 short = "F9",    vk = 120, uiKey = "F9" },
    { id = "SPACE",     name = "ПРОБЕЛ (Space)",     short = "Space", vk = 32,  uiKey = "Space" },
    { id = "ENTER",     name = "ENTER",              short = "Enter", vk = 13,  uiKey = "Enter" },
    { id = "NUM0",      name = "NumPad 0",           short = "Num 0", vk = 96,  uiKey = nil },
    { id = "KEY_1",     name = "Клавиша 1",          short = "1",     vk = 49,  uiKey = nil },
    { id = "KEY_2",     name = "Клавиша 2",          short = "2",     vk = 50,  uiKey = nil },
    { id = "KEY_G",     name = "Клавиша G",          short = "G",     vk = 71,  uiKey = nil },
    { id = "KEY_H",     name = "Клавиша H",          short = "H",     vk = 72,  uiKey = nil },
}

-- Быстрые пресеты задержки
local PRESETS = {
    { label = "0.5с (PRO)",  val = 0.50 },
    { label = "0.75с (RDS)", val = 0.75 },
    { label = "1.0с (STD)",  val = 1.00 },
    { label = "1.5с",        val = 1.50 },
}

local state = {
    timeLeft = 0,
    totalDuration = 3.0,
    stageInterval = 1.0,
    isActive = false,
    myCarIndex = 0,
    myDriverName = "",
    pulse = 0
}

-- Получение текущей выбранной горячей клавиши
local function getActiveHotkey()
    local curId = ac.storage[STORAGE_KEY_HOTKEY] or "F8"
    for _, item in ipairs(HOTKEY_LIST) do
        if item.id == curId then return item end
    end
    return HOTKEY_LIST[1]
end

-- Инициализация данных локального игрока
local function initPlayer()
    local sim = ac.getSim()
    local carIndex = 0
    pcall(function()
        if sim and sim.focusedCar then carIndex = sim.focusedCar end
    end)
    state.myCarIndex = carIndex

    if ac.getDriverName then
        local okName, dName = pcall(ac.getDriverName, state.myCarIndex)
        if okName and dName then
            state.myDriverName = dName
        end
    end
end

-- Проверка прав судьи
local function isJudge()
    local sim = ac.getSim()
    if not sim then return true end

    -- Одиночный режим / практика
    local okOnline, isOnline = pcall(function() return sim.isOnlineRace end)
    if okOnline and not isOnline then return true end

    -- Администратор сервера
    local okAdmin, isAdmin = pcall(function() return sim.isAdmin end)
    if okAdmin and isAdmin then return true end

    -- Проверка имени судьи (Sergey Primo)
    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    local nameLower = string.lower(state.myDriverName or "")
    if string.find(nameLower, "sergey") or string.find(nameLower, "primo") or string.find(nameLower, "сергей") then
        return true
    end

    return false
end

-- Шаг таймера отсчета
local function advanceTimer(dt)
    if lastUpdateFrame == frameCount then return end
    lastUpdateFrame = frameCount

    local step = math.clamp(dt or 0.016, 0.001, 0.1)
    state.pulse = state.pulse + step

    if state.isActive then
        state.timeLeft = state.timeLeft - step
        if state.timeLeft < -GREEN_DURATION then
            state.isActive = false
            state.timeLeft = 0
        end
    end
end

-- Запуск отсчета (Судья)
local function triggerStart()
    local interval = tonumber(ac.storage[STORAGE_KEY_INTERVAL]) or 1.0
    interval = math.clamp(interval, 0.3, 3.0)
    local totalCountdown = interval * 3.0

    state.stageInterval = interval
    state.totalDuration = totalCountdown
    state.timeLeft = totalCountdown
    state.isActive = true

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        action = "start",
        duration = totalCountdown,
        interval = interval
    })

    ac.log(string.format("[DriftStartTree] Countdown STARTED! Total: %.2fs (interval: %.2fs)", totalCountdown, interval))
end

-- Сброс отсчета (Судья)
local function cancelStart()
    state.timeLeft = 0
    state.isActive = false

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        action = "cancel"
    })

    ac.log("[DriftStartTree] Countdown CANCELLED")
end

-- Прием сетевого события от сервера / судьи (0 ms задержка)
ac.onSharedEvent("DRIFT_START_SYNC", function(data)
    if not data then return end
    if data.action == "cancel" or (data.duration and tonumber(data.duration) <= 0) then
        state.isActive = false
        state.timeLeft = 0
        ac.log("[DriftStartTree] Received SYNC: STOP")
    elseif data.action == "start" or (data.duration and tonumber(data.duration) > 0) then
        state.stageInterval = tonumber(data.interval) or 1.0
        state.totalDuration = tonumber(data.duration) or (state.stageInterval * 3.0)
        state.timeLeft = state.totalDuration
        state.isActive = true
        ac.log(string.format("[DriftStartTree] Received SYNC: START (total: %.2fs, step: %.2fs)", state.totalDuration, state.stageInterval))
    end
end)

-- Прием чат-команд судьи (!start [интервал], !stop, !cancel, !go)
if ac.onChatMessage then
    ac.onChatMessage(function(message, senderCarIndex)
        if not message then return false end
        local msg = string.lower(message)
        local senderName = ""
        if senderCarIndex and ac.getDriverName then
            local ok, nm = pcall(ac.getDriverName, senderCarIndex)
            if ok and nm then senderName = string.lower(nm) end
        end

        local allowed = string.find(senderName, "sergey")
            or string.find(senderName, "primo")
            or string.find(senderName, "сергей")
            or isJudge()

        if allowed then
            if string.find(msg, "!start") or string.find(msg, "!старт") or string.find(msg, "!go") then
                local customInterval = tonumber(string.match(msg, "!start%s+([%d%.]+)") or string.match(msg, "!старт%s+([%d%.]+)"))
                if customInterval and customInterval >= 0.3 and customInterval <= 3.0 then
                    ac.storage[STORAGE_KEY_INTERVAL] = string.format("%.2f", customInterval)
                end
                triggerStart()
                return false
            elseif string.find(msg, "!cancel") or string.find(msg, "!сброс") or string.find(msg, "!stop") then
                cancelStart()
                return false
            end
        end
        return false
    end)
end

-- Проверка назначенной горячей клавиши для судьи
local function checkJudgeHotkey()
    if not isJudge() or previewPilotMode then return false end

    local hotkey = getActiveHotkey()
    local isDown = false

    if hotkey.uiKey and ui.keyboardButtonPressed and ui.KeyIndex and ui.KeyIndex[hotkey.uiKey] then
        local ok, pressed = pcall(ui.keyboardButtonPressed, ui.KeyIndex[hotkey.uiKey])
        if ok and pressed then isDown = true end
    end

    if not isDown and ac.isKeyPressed and hotkey.vk then
        local ok, pressed = pcall(ac.isKeyPressed, hotkey.vk)
        if ok and pressed then isDown = true end
    end

    local justPressed = isDown and not prevHotkeyDown
    prevHotkeyDown = isDown
    return justPressed
end

-- ====================================================================
-- ОТРИСОВКА ДРИФТ-ЛАМПЫ С РЕАЛИСТИЧНОЙ ОПТИКОЙ И НЕОНОВЫМ BLOOM
-- ====================================================================
local function drawDriftLamp(centerX, centerY, radius, isLit, litCol, offCol, glowCol, haloRadius, isGreen, pulsePhase)
    -- 1. Внешний корпус / металлический козырёк линзы (Titanium Rim)
    ui.drawCircleFilled(vec2(centerX, centerY), radius + 3, rgbm(0.06, 0.07, 0.10, 0.98), 32)
    ui.drawCircle(vec2(centerX, centerY), radius + 3, rgbm(0.25, 0.30, 0.38, 0.85), 32, 1.5)

    -- 2. Тень козырька (Sun visor cowl)
    ui.drawCircle(vec2(centerX, centerY + 1), radius + 2, rgbm(0.02, 0.02, 0.04, 0.95), 32, 2.0)

    -- 3. Атмосферный неоновый Halo Bloom (при свечении)
    if isLit then
        local pulseExtra = isGreen and (math.sin(pulsePhase * 9.0) * 3.5) or 0
        ui.drawCircleFilled(vec2(centerX, centerY), radius + haloRadius + pulseExtra, glowCol, 32)
        ui.drawCircleFilled(vec2(centerX, centerY), radius + 5 + (pulseExtra * 0.5), litCol * 0.45, 32)
    end

    -- 4. Главная колба / рефлектор
    local baseCol = isLit and litCol or offCol
    ui.drawCircleFilled(vec2(centerX, centerY), radius, baseCol, 32)
    ui.drawCircle(vec2(centerX, centerY), radius, rgbm(0.12, 0.15, 0.20, 0.9), 32, 1.2)

    -- 5. Внутренняя оптика
    if isLit then
        local coreRadius = radius * 0.40
        local coreCol = isGreen and rgbm(0.88, 1.0, 0.90, 0.98) or rgbm(1.0, 0.85, 0.85, 0.98)
        ui.drawCircleFilled(vec2(centerX, centerY), coreRadius, coreCol, 24)
    else
        ui.drawCircleFilled(vec2(centerX - radius * 0.35, centerY - radius * 0.35), radius * 0.25, rgbm(1.0, 1.0, 1.0, 0.18), 16)
    end
end

-- ====================================================================
-- ОСНОВНОЙ РЕНДЕР СОДЕРЖИМОГО СВЕТОФОРА
-- ====================================================================
local function renderTreeContent(dt)
    advanceTimer(dt)

    local isHudOn = (ac.storage[STORAGE_KEY_ENABLED] ~= "0")

    -- 1. Верхняя панель в стиле дрифт-телеметрии
    if isHudOn then
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.20, 1.0, 0.45, 1.0))
        ui.text("⚡ СВЕТОФОР СТАРТА")
        ui.popStyleColor()

        local availW = ui.availableSpaceX()
        local btnW = 86
        if availW > (btnW + 20) then
            ui.sameLine(availW - btnW)
            if ui.button("Выключить##treeToggleOff", vec2(btnW, 20)) then
                ac.storage[STORAGE_KEY_ENABLED] = "0"
            end
        end
    else
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.85, 0.3, 0.3, 1.0))
        ui.text("⚡ СВЕТОФОР СТАРТА (ВЫКЛ)")
        ui.popStyleColor()

        local availW = ui.availableSpaceX()
        local btnW = 86
        if availW > (btnW + 20) then
            ui.sameLine(availW - btnW)
            if ui.button("Включить##treeToggleOn", vec2(btnW, 20)) then
                ac.storage[STORAGE_KEY_ENABLED] = "1"
            end
        end
        ui.separator()
        ui.text("Светофор скрыт. Нажмите «Включить» выше.")
        return
    end

    ui.separator()

    -- 2. Определение текущей фазы отсчета с учетом настраиваемого интервала
    local interval = state.stageInterval or tonumber(ac.storage[STORAGE_KEY_INTERVAL]) or 1.0
    interval = math.clamp(interval, 0.3, 3.0)
    local totalDur = interval * 3.0

    local timeLeft = state.timeLeft
    local isStage = state.isActive and (timeLeft <= (interval * 3.0) and timeLeft > (interval * 2.0))
    local red1    = state.isActive and (timeLeft <= (interval * 2.0) and timeLeft > 0)
    local red2    = state.isActive and (timeLeft <= interval and timeLeft > 0)
    local green   = state.isActive and (timeLeft <= 0 and timeLeft > -GREEN_DURATION)

    -- 3. Карбоновый корпус светофора с металлическими винтами
    local cur = ui.getCursor()
    local availW = math.max(ui.availableSpaceX(), 280)
    local boxW = math.min(availW - 6, 340)
    local boxH = 74
    local boxX = cur.x + (availW - boxW) * 0.5
    local boxY = cur.y + 2

    ui.drawRectFilled(vec2(boxX, boxY), vec2(boxX + boxW, boxY + boxH), rgbm(0.03, 0.04, 0.06, 0.98), 10)
    ui.drawRect(vec2(boxX, boxY), vec2(boxX + boxW, boxY + boxH), rgbm(0.22, 0.28, 0.36, 0.85), 10, nil, 1.5)
    ui.drawRect(vec2(boxX + 2, boxY + 2), vec2(boxX + boxW - 2, boxY + boxH - 2), rgbm(0.08, 0.10, 0.14, 0.9), 8, nil, 1.0)

    -- 4 винта по углам
    local rOff = 6
    local rR = 2.5
    local rCol = rgbm(0.40, 0.45, 0.52, 0.85)
    ui.drawCircleFilled(vec2(boxX + rOff, boxY + rOff), rR, rCol, 8)
    ui.drawCircleFilled(vec2(boxX + boxW - rOff, boxY + rOff), rR, rCol, 8)
    ui.drawCircleFilled(vec2(boxX + rOff, boxY + boxH - rOff), rR, rCol, 8)
    ui.drawCircleFilled(vec2(boxX + boxW - rOff, boxY + boxH - rOff), rR, rCol, 8)

    local centerY = boxY + boxH * 0.5
    local lamp1X = boxX + boxW * 0.20
    local lamp2X = boxX + boxW * 0.50
    local lamp3X = boxX + boxW * 0.80
    local radius = 21

    -- Лампа 1 (Красный 1 / Готовность)
    local colR1 = rgbm(1.0, 0.06, 0.06, 1.0)
    local offR  = rgbm(0.18, 0.03, 0.03, 0.85)
    local glowR = rgbm(1.0, 0.0, 0.0, 0.35)
    drawDriftLamp(lamp1X, centerY, radius, red1, colR1, offR, glowR, 7, false, state.pulse)

    -- Лампа 2 (Красный 2 / Внимание)
    drawDriftLamp(lamp2X, centerY, radius, red2, colR1, offR, glowR, 7, false, state.pulse)

    -- Лампа 3 (Неоновый зеленый / Дрифт-Старт)
    local colG  = rgbm(0.04, 1.0, 0.28, 1.0)
    local offG  = rgbm(0.02, 0.16, 0.05, 0.85)
    local glowG = rgbm(0.08, 1.0, 0.30, 0.48)
    drawDriftLamp(lamp3X, centerY, radius, green, colG, offG, glowG, 9, true, state.pulse)

    ui.dummy(vec2(0, boxH + 8))

    -- 4. Линейный индикатор прогресса отсчета
    local barCur = ui.getCursor()
    local barW = boxW
    local barX = boxX
    local barH = 4
    ui.drawRectFilled(vec2(barX, barCur.y), vec2(barX + barW, barCur.y + barH), rgbm(0.08, 0.10, 0.14, 0.8), 2)
    if state.isActive then
        local progress = 1.0 - math.clamp(state.timeLeft / (state.totalDuration > 0 and state.totalDuration or 1.0), 0, 1)
        local fillW = (green and 1.0 or progress) * barW
        local barCol = green and rgbm(0.08, 1.0, 0.32, 1.0) or
                       (red2 and rgbm(1.0, 0.2, 0.2, 1.0) or
                       (red1 and rgbm(1.0, 0.55, 0.15, 1.0) or rgbm(1.0, 0.85, 0.1, 1.0)))
        if fillW > 0 then
            ui.drawRectFilled(vec2(barX, barCur.y), vec2(barX + fillW, barCur.y + barH), barCol, 2)
        end
    end
    ui.dummy(vec2(0, barH + 4))

    -- 5. Текстовый статус стадии старта с миллисекундами
    local statusText = "● ОЖИДАНИЕ СТАРТА"
    local statusCol  = rgbm(0.70, 0.74, 0.80, 1.0)

    if green then
        statusText = "🟢 ⚡ ★ СТАРТ!  GO!  GO! ★ ⚡"
        statusCol  = rgbm(0.12, 1.0, 0.35, 1.0)
    elseif red2 then
        statusText = string.format("🔴 [ ВНИМАНИЕ ] 1 СЕК  (%.1fс)", math.max(0, timeLeft))
        statusCol  = rgbm(1.0, 0.25, 0.20, 1.0)
    elseif red1 then
        statusText = string.format("🔴 [ ГОТОВНОСТЬ ] 2 СЕК  (%.1fс)", math.max(0, timeLeft))
        statusCol  = rgbm(1.0, 0.55, 0.12, 1.0)
    elseif isStage then
        statusText = string.format("🟡 [ ПРИГОТОВИТЬСЯ ] 3 СЕК  (%.1fс)", math.max(0, timeLeft))
        statusCol  = rgbm(1.0, 0.88, 0.15, 1.0)
    end

    ui.pushStyleColor(ui.StyleColor.Text, statusCol)
    ui.text(statusText)
    ui.popStyleColor()

    -- 6. Управление судьи / Режим пилота
    if isJudge() and not previewPilotMode then
        ui.separator()
        local spaceW = math.max(ui.availableSpaceX(), 180)
        local btnW = math.floor((spaceW - 12) * 0.5)
        local hotkey = getActiveHotkey()

        -- Кнопка СТАРТ (зеленая)
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.10, 0.58, 0.24, 0.95))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.15, 0.75, 0.30, 1.0))
        ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.20, 0.90, 0.38, 1.0))
        if ui.button("▶ СТАРТ (" .. hotkey.short .. ")", vec2(btnW, 34)) then
            triggerStart()
        end
        ui.popStyleColor(3)

        ui.sameLine(btnW + 14)

        -- Кнопка СБРОС (красная)
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.65, 0.15, 0.15, 0.95))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.80, 0.20, 0.20, 1.0))
        ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.95, 0.25, 0.25, 1.0))
        if ui.button("✖ СБРОС", vec2(btnW, 34)) then
            cancelStart()
        end
        ui.popStyleColor(3)

        -- Панель настройки задержки светофора
        ui.dummy(vec2(0, 2))
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.70, 0.76, 0.85, 1.0))
        ui.text("Задержка ламп:")
        ui.popStyleColor()

        local currentInterval = tonumber(ac.storage[STORAGE_KEY_INTERVAL]) or 1.0

        for i, p in ipairs(PRESETS) do
            ui.sameLine()
            local isSel = math.abs(currentInterval - p.val) < 0.03
            if isSel then
                ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.18, 0.55, 0.92, 0.95))
            else
                ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.18, 0.20, 0.25, 0.85))
            end
            if ui.button(p.label .. "##pBtn" .. i, vec2(58, 20)) then
                ac.storage[STORAGE_KEY_INTERVAL] = string.format("%.2f", p.val)
            end
            ui.popStyleColor()
        end

        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.60, 0.65, 0.75, 1.0))
        ui.text(string.format("Интервал: %.2fс (Всего: %.2fс)", currentInterval, currentInterval * 3.0))
        ui.popStyleColor()
        ui.sameLine(190)

        ui.setNextItemWidth(ui.availableSpaceX() - 4)
        local newInt, changed = ui.slider("##intervalSlider", currentInterval, 0.30, 2.00, "%.2f сек")
        if changed or (newInt and math.abs(newInt - currentInterval) > 0.01) then
            ac.storage[STORAGE_KEY_INTERVAL] = string.format("%.2f", newInt)
        end

        -- Строка горячей клавиши и переключения вида
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.70, 0.76, 0.85, 1.0))
        ui.text("Клавиша:")
        ui.popStyleColor()
        ui.sameLine()

        local curIndex = 1
        for idx, item in ipairs(HOTKEY_LIST) do
            if item.id == hotkey.id then curIndex = idx; break end
        end

        ui.setNextItemWidth(130)
        if ui.combo("##hotkeySelect", HOTKEY_LIST[curIndex].short, ui.ComboFlags.HeightRegular, function()
            for idx, item in ipairs(HOTKEY_LIST) do
                if ui.selectable(item.name, idx == curIndex) then
                    ac.storage[STORAGE_KEY_HOTKEY] = item.id
                end
            end
        end) then
        end

        ui.sameLine()
        if ui.button("👁 Вид пилота##previewPilot", vec2(95, 20)) then
            previewPilotMode = true
        end
    elseif previewPilotMode then
        ui.separator()
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.3, 0.85, 1.0, 1.0))
        ui.text("ℹ Режим пилота (без судейских кнопок)")
        ui.popStyleColor()
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.55, 0.58, 0.65, 1.0))
        ui.text("Управление: Судья (Sergey Primo)")
        ui.popStyleColor()

        if ui.button("↩ Вернуться к виду судьи##exitPreview", vec2(195, 24)) then
            previewPilotMode = false
        end
    else
        ui.separator()
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.55, 0.58, 0.65, 1.0))
        ui.text("Управление: Судья (Sergey Primo)")
        ui.popStyleColor()
    end
end

-- ====================================================================
-- РЕНДЕР ПЛАВАЮЩЕГО HUD ДЛЯ УЧАСТНИКОВ НА СЕРВЕРЕ
-- ====================================================================
local function renderFloatingHUD(dt)
    local isEnabled = (ac.storage[STORAGE_KEY_ENABLED] ~= "0")
    local savedX = tonumber(ac.storage[STORAGE_KEY_POS_X]) or 760
    local savedY = tonumber(ac.storage[STORAGE_KEY_POS_Y]) or 40
    local cardW = 380
    local cardH = isEnabled and ((isJudge() and not previewPilotMode) and 290 or 175) or 60

    if not posInitialized then
        if ui.setNextWindowPosition then
            ui.setNextWindowPosition(vec2(savedX, savedY))
        end
        if ui.setNextWindowSize then
            ui.setNextWindowSize(vec2(cardW, cardH))
        end
        posInitialized = true
    end

    local winFlags = bit.bor(ui.WindowFlags.NoCollapse, ui.WindowFlags.NoScrollbar)

    ui.pushStyleVar(ui.StyleVar.WindowRounding, 8)
    ui.pushStyleVar(ui.StyleVar.WindowBorderSize, 1.5)
    ui.pushStyleColor(ui.StyleColor.WindowBg, rgbm(0.04, 0.05, 0.07, 0.96))
    ui.pushStyleColor(ui.StyleColor.Border, rgbm(0.20, 0.60, 0.95, 0.85))

    ui.begin("🚦 СВЕТОФОР | ГАЗДЕРЖИМ.РФ##DRIFT_START_HUD", winFlags, function()
        local curPos = ui.windowPos()
        if curPos and (math.abs(curPos.x - savedX) > 2 or math.abs(curPos.y - savedY) > 2) then
            ac.storage[STORAGE_KEY_POS_X] = tostring(math.floor(curPos.x))
            ac.storage[STORAGE_KEY_POS_Y] = tostring(math.floor(curPos.y))
            savedX = curPos.x
            savedY = curPos.y
        end

        local ok, err = pcall(renderTreeContent, dt)
        if not ok and err then
            ac.log("[DriftStartTree] Error in HUD: " .. tostring(err))
            ui.text("Ошибка: " .. tostring(err))
        end
    end)

    ui.popStyleColor(2)
    ui.popStyleVar(2)
end

-- ====================================================================
-- ТОЧКА ВХОДА ТРЕКОВОГО СКРИПТА
-- ====================================================================
function script.update(dt)
    frameCount = frameCount + 1

    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    if checkJudgeHotkey() then
        triggerStart()
    end

    -- Проверяем активность отдельного окна CSP App (DriftStartTree.lua)
    local lastAppTime = tonumber(ac.storage["drift_tree_app_active"] or 0) or 0
    if os.clock() - lastAppTime < 0.5 then
        return
    end

    renderFloatingHUD(dt)
end

ac.log("[DriftStartTree] Track Extension HUD loaded v3.0 (Drift Edition)")
