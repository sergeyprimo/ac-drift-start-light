-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР СТАРТА)
-- Официальный трековый модуль для соревнований ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch
-- Версия: 2.5 (Track Extension Auto-HUD)
-- ====================================================================

local COUNTDOWN_TOTAL = 3.0 -- 3 секунды отсчета
local GREEN_DURATION  = 2.5 -- 2.5 секунды горит зеленый

local STORAGE_KEY_POS_X   = "drift_tree_pos_x"
local STORAGE_KEY_POS_Y   = "drift_tree_pos_y"
local STORAGE_KEY_ENABLED = "drift_tree_enabled"
local STORAGE_KEY_HOTKEY  = "drift_tree_hotkey"

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

local state = {
    timeLeft = 0,
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
    state.timeLeft = COUNTDOWN_TOTAL
    state.isActive = true

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        action = "start",
        duration = COUNTDOWN_TOTAL
    })

    ac.log("[DriftStartTree] Countdown STARTED! Duration: 3.0s")
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
        state.timeLeft = tonumber(data.duration) or COUNTDOWN_TOTAL
        state.isActive = true
        ac.log("[DriftStartTree] Received SYNC: START (" .. tostring(state.timeLeft) .. "s)")
    end
end)

-- Прием чат-команд судьи (!start, !stop, !cancel, !go)
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
-- ОСНОВНОЙ РЕНДЕР СОДЕРЖИМОГО СВЕТОФОРА
-- ====================================================================
local function renderTreeContent(dt)
    advanceTimer(dt)

    local isHudOn = (ac.storage[STORAGE_KEY_ENABLED] ~= "0")

    -- 1. Верхняя панель: Статус и кнопка Вкл/Выкл
    if isHudOn then
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.2, 1.0, 0.4, 1.0))
        ui.text("Светофор: ВКЛ")
        ui.popStyleColor()

        local availW = ui.availableSpaceX()
        local btnW = 90
        if availW > (btnW + 20) then
            ui.sameLine(availW - btnW)
            if ui.button("Выключить##treeToggleOff", vec2(btnW, 20)) then
                ac.storage[STORAGE_KEY_ENABLED] = "0"
            end
        end
    else
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.8, 0.3, 0.3, 1.0))
        ui.text("Светофор: ВЫКЛ")
        ui.popStyleColor()

        local availW = ui.availableSpaceX()
        local btnW = 90
        if availW > (btnW + 20) then
            ui.sameLine(availW - btnW)
            if ui.button("Включить##treeToggleOn", vec2(btnW, 20)) then
                ac.storage[STORAGE_KEY_ENABLED] = "1"
            end
        end
        ui.separator()
        ui.text("Светофор скрыт. Нажмите кнопку выше.")
        return
    end

    ui.separator()

    -- 2. Определение текущей фазы отсчета
    local timeLeft = state.timeLeft
    local isStage = state.isActive and (timeLeft <= 3.0 and timeLeft > 2.0)
    local red1    = state.isActive and (timeLeft <= 2.0 and timeLeft > 0)
    local red2    = state.isActive and (timeLeft <= 1.0 and timeLeft > 0)
    local green   = state.isActive and (timeLeft <= 0 and timeLeft > -GREEN_DURATION)

    -- 3. Блок 3 ламп в темном боксе
    local cur = ui.getCursor()
    local availW = math.max(ui.availableSpaceX(), 260)
    local boxW = math.min(availW - 10, 280)
    local boxH = 64
    local boxX = cur.x + (availW - boxW) * 0.5
    local boxY = cur.y + 2

    ui.drawRectFilled(vec2(boxX, boxY), vec2(boxX + boxW, boxY + boxH), rgbm(0.04, 0.05, 0.08, 0.95), 8)

    local centerY = boxY + boxH * 0.5
    local lamp1X = boxX + boxW * 0.20
    local lamp2X = boxX + boxW * 0.50
    local lamp3X = boxX + boxW * 0.80
    local radius = 18

    -- Лампа 1 (Красный 1)
    local colR1 = red1 and rgbm(1.0, 0.08, 0.08, 1.0) or rgbm(0.22, 0.04, 0.04, 0.6)
    ui.drawCircleFilled(vec2(lamp1X, centerY), radius, colR1, 24)
    ui.drawCircle(vec2(lamp1X, centerY), radius, rgbm(0.45, 0.48, 0.55, 0.85), 24, 2)
    if red1 then
        ui.drawCircleFilled(vec2(lamp1X, centerY), radius + 6, rgbm(1.0, 0.0, 0.0, 0.38), 24)
    end

    -- Лампа 2 (Красный 2)
    local colR2 = red2 and rgbm(1.0, 0.08, 0.08, 1.0) or rgbm(0.22, 0.04, 0.04, 0.6)
    ui.drawCircleFilled(vec2(lamp2X, centerY), radius, colR2, 24)
    ui.drawCircle(vec2(lamp2X, centerY), radius, rgbm(0.45, 0.48, 0.55, 0.85), 24, 2)
    if red2 then
        ui.drawCircleFilled(vec2(lamp2X, centerY), radius + 6, rgbm(1.0, 0.0, 0.0, 0.38), 24)
    end

    -- Лампа 3 (Зеленый)
    local colG = green and rgbm(0.08, 1.0, 0.25, 1.0) or rgbm(0.04, 0.22, 0.06, 0.6)
    ui.drawCircleFilled(vec2(lamp3X, centerY), radius, colG, 24)
    ui.drawCircle(vec2(lamp3X, centerY), radius, rgbm(0.45, 0.48, 0.55, 0.85), 24, 2)
    if green then
        ui.drawCircleFilled(vec2(lamp3X, centerY), radius + 7, rgbm(0.1, 1.0, 0.2, 0.50), 24)
    end

    ui.dummy(vec2(0, boxH + 8))

    -- 4. Текстовый статус стадии старта
    local statusText = "● ОЖИДАНИЕ СТАРТА"
    local statusCol  = rgbm(0.70, 0.72, 0.78, 1.0)

    if green then
        statusText = "★ СТАРТ!  GO!  GO!"
        statusCol  = rgbm(0.1, 1.0, 0.3, 1.0)
    elseif red2 then
        statusText = "● ВНИМАНИЕ (1 СЕК)"
        statusCol  = rgbm(1.0, 0.3, 0.2, 1.0)
    elseif red1 then
        statusText = "● ГОТОВНОСТЬ (2 СЕК)"
        statusCol  = rgbm(1.0, 0.55, 0.1, 1.0)
    elseif isStage then
        statusText = "● ПРИГОТОВИТЬСЯ (3 СЕК)"
        statusCol  = rgbm(1.0, 0.9, 0.15, 1.0)
    end

    ui.pushStyleColor(ui.StyleColor.Text, statusCol)
    ui.text(statusText)
    ui.popStyleColor()

    -- 5. Управление судьи / Режим пилота
    if isJudge() and not previewPilotMode then
        ui.separator()
        local spaceW = math.max(ui.availableSpaceX(), 180)
        local btnW = math.floor((spaceW - 12) * 0.5)
        local hotkey = getActiveHotkey()

        -- Кнопка СТАРТ (зеленая)
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.55, 0.22, 0.95))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.18, 0.72, 0.28, 1.0))
        ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.22, 0.88, 0.35, 1.0))
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

        -- Строка настроек горячей клавиши и переключения вида
        ui.dummy(vec2(0, 4))
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.7, 0.75, 0.85, 1.0))
        ui.text("Клавиша:")
        ui.popStyleColor()
        ui.sameLine()

        local curIndex = 1
        for idx, item in ipairs(HOTKEY_LIST) do
            if item.id == hotkey.id then curIndex = idx; break end
        end

        ui.setNextItemWidth(140)
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
        ui.text("ℹ Режим предварительного просмотра (вид пилота)")
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
    local cardW = 360
    local cardH = isEnabled and ((isJudge() and not previewPilotMode) and 260 or 165) or 60

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
    ui.pushStyleColor(ui.StyleColor.WindowBg, rgbm(0.06, 0.08, 0.12, 0.94))
    ui.pushStyleColor(ui.StyleColor.Border, rgbm(0.20, 0.55, 0.95, 0.75))

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

ac.log("[DriftStartTree] Track Extension HUD loaded v2.5")
