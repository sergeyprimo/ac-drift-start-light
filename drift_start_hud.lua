-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР СТАРТА)
-- Официальный трековый модуль для соревнований ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch
-- Версия: 2.3 (Track Extension Auto-HUD)
-- ====================================================================

local COUNTDOWN_TOTAL = 3.0 -- 3 секунды отсчета
local GREEN_DURATION  = 2.5 -- 2.5 секунды горит зеленый

local STORAGE_KEY_POS_X   = "drift_tree_pos_x"
local STORAGE_KEY_POS_Y   = "drift_tree_pos_y"
local STORAGE_KEY_ENABLED = "drift_tree_enabled"

local frameCount = 0
local posInitialized = false
local prevHotkeyDown = false

local state = {
    targetGreenTime = 0,
    isActive = false,
    myCarIndex = 0,
    myDriverName = "",
    pulse = 0
}

-- Инициализация данных локального игрока
local function initPlayer()
    local sim = ac.getSim()
    state.myCarIndex = (sim and sim.focusedCar) or 0
    if ac.getDriverName then
        state.myDriverName = ac.getDriverName(state.myCarIndex) or ""
    end
end

-- Проверка прав судьи
local function isJudge()
    local sim = ac.getSim()
    if not sim or not sim.isOnlineRace then return true end -- Одиночный заезд / практика / тренировка
    if sim.isServerAdmin then return true end

    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    local nameLower = string.lower(state.myDriverName or "")
    if string.find(nameLower, "sergey") or string.find(nameLower, "primo") or string.find(nameLower, "сергей") then
        return true
    end
    return false
end

-- Запуск отсчета (Судья)
local function triggerStart()
    local sim = ac.getSim()
    local simTime = (sim and sim.time) or 0
    local greenTimestamp = simTime + COUNTDOWN_TOTAL

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = greenTimestamp
    })

    state.targetGreenTime = greenTimestamp
    state.isActive = true
    ac.log("[DriftStartTree] Countdown STARTED! Green at: " .. string.format("%.2f", greenTimestamp))
end

-- Сброс отсчета (Судья)
local function cancelStart()
    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = 0
    })

    state.targetGreenTime = 0
    state.isActive = false
    ac.log("[DriftStartTree] Countdown CANCELLED")
end

-- Прием сетевого события от сервера / судьи (0 ms задержка)
ac.onSharedEvent("DRIFT_START_SYNC", function(data)
    if data and data.greenTime then
        local gTime = tonumber(data.greenTime) or 0
        if gTime <= 0 then
            state.isActive = false
            state.targetGreenTime = 0
            ac.log("[DriftStartTree] Received SYNC: STOP")
        else
            state.targetGreenTime = gTime
            state.isActive = true
            ac.log("[DriftStartTree] Received SYNC: START at " .. tostring(gTime))
        end
    end
end)

-- Прием чат-команд судьи (!start, !stop, !cancel, !go)
if ac.onChatMessage then
    ac.onChatMessage(function(message, senderCarIndex)
        if not message then return false end
        local msg = string.lower(message)
        local senderName = string.lower((senderCarIndex and ac.getDriverName and ac.getDriverName(senderCarIndex)) or "")

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

-- Проверка горячей клавиши F8 для судьи
local function checkJudgeHotkey()
    if not isJudge() then return false end

    local isDown = false
    if ui.keyboardButtonPressed and ui.KeyIndex and ui.KeyIndex.F8 then
        local ok, pressed = pcall(ui.keyboardButtonPressed, ui.KeyIndex.F8)
        if ok and pressed then isDown = true end
    end

    if not isDown and ac.isKeyPressed then
        if ac.KeyIndex and ac.KeyIndex.F8 then
            local ok, pressed = pcall(ac.isKeyPressed, ac.KeyIndex.F8)
            if ok and pressed then isDown = true end
        end
        if not isDown then
            local ok, pressed = pcall(ac.isKeyPressed, 119) -- 119 = VK_F8
            if ok and pressed then isDown = true end
        end
    end

    local justPressed = isDown and not prevHotkeyDown
    prevHotkeyDown = isDown
    return justPressed
end

-- ====================================================================
-- ОСНОВНОЙ РЕНДЕР СОДЕРЖИМОГО СВЕТОФОРА
-- ====================================================================
local function renderTreeContent()
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

    -- 2. Расчет времени отсчета
    local sim = ac.getSim()
    local simTime = (sim and sim.time) or 0
    local timeLeft = state.targetGreenTime - simTime

    if not state.isActive or timeLeft < -GREEN_DURATION then
        state.isActive = false
    end

    local isStage = state.isActive and (timeLeft <= 3.0 and timeLeft > 2.0)
    local red1    = state.isActive and (timeLeft <= 2.0 and timeLeft > 0)
    local red2    = state.isActive and (timeLeft <= 1.0 and timeLeft > 0)
    local green   = state.isActive and (timeLeft <= 0 and timeLeft > -GREEN_DURATION)

    -- 3. Блок ламп в темном боксе
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
        ui.drawCircleFilled(vec2(lamp1X, centerY), radius + 5, rgbm(1.0, 0.0, 0.0, 0.35), 24)
    end

    -- Лампа 2 (Красный 2)
    local colR2 = red2 and rgbm(1.0, 0.08, 0.08, 1.0) or rgbm(0.22, 0.04, 0.04, 0.6)
    ui.drawCircleFilled(vec2(lamp2X, centerY), radius, colR2, 24)
    ui.drawCircle(vec2(lamp2X, centerY), radius, rgbm(0.45, 0.48, 0.55, 0.85), 24, 2)
    if red2 then
        ui.drawCircleFilled(vec2(lamp2X, centerY), radius + 5, rgbm(1.0, 0.0, 0.0, 0.35), 24)
    end

    -- Лампа 3 (Зеленый)
    local colG = green and rgbm(0.08, 1.0, 0.25, 1.0) or rgbm(0.04, 0.22, 0.06, 0.6)
    ui.drawCircleFilled(vec2(lamp3X, centerY), radius, colG, 24)
    ui.drawCircle(vec2(lamp3X, centerY), radius, rgbm(0.45, 0.48, 0.55, 0.85), 24, 2)
    if green then
        ui.drawCircleFilled(vec2(lamp3X, centerY), radius + 6, rgbm(0.1, 1.0, 0.2, 0.45), 24)
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

    -- 5. Управление судьи (СТАРТ / СБРОС)
    if isJudge() then
        ui.separator()
        local spaceW = math.max(ui.availableSpaceX(), 180)
        local btnW = math.floor((spaceW - 12) * 0.5)

        -- Кнопка СТАРТ (зеленая)
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.55, 0.22, 0.95))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.18, 0.72, 0.28, 1.0))
        ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.22, 0.88, 0.35, 1.0))
        if ui.button("▶ СТАРТ (F8)", vec2(btnW, 34)) then
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
local function renderFloatingHUD()
    local isEnabled = (ac.storage[STORAGE_KEY_ENABLED] ~= "0")
    local savedX = tonumber(ac.storage[STORAGE_KEY_POS_X]) or 760
    local savedY = tonumber(ac.storage[STORAGE_KEY_POS_Y]) or 40
    local cardW = 340
    local cardH = isEnabled and (isJudge() and 220 or 165) or 60

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

        local ok, err = pcall(renderTreeContent)
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
        -- Приложение уже отрисовывает окно, не дублируем оверлей
        return
    end

    -- Рендерим плавающий оверлей для участников без отдельного приложения
    renderFloatingHUD()
end

ac.log("[DriftStartTree] Track Extension HUD loaded v2.3")
