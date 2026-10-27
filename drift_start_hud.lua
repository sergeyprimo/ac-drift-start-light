-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР СТАРТА ДРИФТА)
-- Официальный модуль для соревнований ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch
-- ====================================================================

local JUDGE_STEAM_ID = "76561198419276819" -- Sergey Primo
local COUNTDOWN_TOTAL = 3.0 -- 3 секунды отсчета
local GREEN_DURATION  = 2.5 -- 2.5 секунды горит зеленый

-- Настройки пользователя
local settings = ac.storage{
    hudEnabled = true,
    posX = 780,
    posY = 50
}

if settings.hudEnabled == nil then
    settings.hudEnabled = true
end

local state = {
    targetGreenTime = 0,
    isActive = false,
    myCarIndex = 0,
    mySteamID = "",
    myDriverName = "",
    pulse = 0
}

local frameCount = 0
local appWindowActiveFrame = -100
local overlayPosSet = false

-- Инициализация локального игрока
local function initPlayer()
    local sim = ac.getSim()
    state.myCarIndex = (sim and sim.focusedCar) or 0
    state.mySteamID = ac.getDriverSteamID(state.myCarIndex) or ""
    state.myDriverName = ac.getDriverName(state.myCarIndex) or ""
end

-- Проверка прав судьи
local function isJudge()
    if state.mySteamID == "" then initPlayer() end
    local sim = ac.getSim()
    if sim and not sim.isOnlineRace then return true end -- Одиночный режим / Тренировка
    if state.mySteamID == JUDGE_STEAM_ID then return true end
    local nameLower = string.lower(state.myDriverName or "")
    if string.find(nameLower, "sergey") or string.find(nameLower, "primo") then
        return true
    end
    if sim and sim.isServerAdmin then return true end
    return false
end

-- Запуск обратного отсчета
local function triggerStart()
    local sim = ac.getSim()
    local simTime = (sim and sim.time) or 0
    local greenTimestamp = simTime + COUNTDOWN_TOTAL

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = greenTimestamp
    })

    state.targetGreenTime = greenTimestamp
    state.isActive = true
    ac.log("[DriftStartTree] START triggered! Green at: " .. string.format("%.2f", greenTimestamp))
end

-- Сброс / отмена отсчета
local function cancelStart()
    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = 0
    })

    state.targetGreenTime = 0
    state.isActive = false
    ac.log("[DriftStartTree] START cancelled")
end

-- Прием события синхронизации
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

-- Прием команд из чата (!start / !stop / !cancel)
if ac.onChatMessage then
    ac.onChatMessage(function(message, senderCarIndex)
        if not message then return false end
        local msg = string.lower(message)
        local senderSteamID = (senderCarIndex and ac.getDriverSteamID(senderCarIndex)) or ""
        local senderName = string.lower((senderCarIndex and ac.getDriverName(senderCarIndex)) or "")

        local allowed = (senderSteamID == JUDGE_STEAM_ID)
            or string.find(senderName, "sergey")
            or string.find(senderName, "primo")
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

-- Проверка горячей клавиши F8
local function checkJudgeHotkey()
    if not isJudge() then return false end

    -- Проверка через ImGui (когда окно активно)
    if ui.keyboardButtonPressed then
        if ui.KeyIndex and ui.KeyIndex.F8 and ui.keyboardButtonPressed(ui.KeyIndex.F8) then
            return true
        end
    end

    -- Глобальная проверка через ac.isKeyPressed / ac.isKeyDown
    if ac.isKeyPressed then
        if ac.KeyIndex and ac.KeyIndex.F8 and ac.isKeyPressed(ac.KeyIndex.F8) then
            return true
        end
        local ok, pressed = pcall(ac.isKeyPressed, 119) -- 119 = VK_F8
        if ok and pressed then return true end
    end

    return false
end

-- Безопасный вывод цветного текста
local function drawColoredText(col, text)
    ui.pushStyleColor(ui.StyleColor.Text, col)
    ui.text(tostring(text))
    ui.popStyleColor()
end

-- ====================================================================
-- ОСНОВНОЙ РЕНДЕР ИНТЕРФЕЙСА СВЕТОФОРА
-- ====================================================================
local function renderTreeContent()
    state.pulse = (state.pulse + 0.08) % (math.pi * 2)

    local isHudOn = (settings.hudEnabled ~= false)

    -- 1. Верхняя панель: Индикатор состояния и кнопка Вкл/Выкл
    local statusTitle = isHudOn and "🚦 Светофор: ВКЛ" or "🚫 Светофор: ВЫКЛ"
    local statusTitleCol = isHudOn and rgbm(0.2, 1.0, 0.4, 1.0) or rgbm(0.8, 0.3, 0.3, 1.0)
    drawColoredText(statusTitleCol, statusTitle)

    local availW = math.max(ui.availableSpaceX(), 180)
    local btnToggleW = 100
    if availW > (btnToggleW + 20) then
        ui.sameLine(availW - btnToggleW)
        local btnLabel = isHudOn and "Выключить" or "Включить"
        if ui.button(btnLabel, vec2(btnToggleW, 22)) then
            settings.hudEnabled = not isHudOn
        end
    end

    ui.separator()

    -- Если светофор отключен пользователем
    if not isHudOn then
        drawColoredText(rgbm(0.6, 0.6, 0.6, 1.0), "Светофор скрыт. Нажмите кнопку выше для включения.")
        return
    end

    -- 2. Расчет таймингов
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

    -- 3. Графический блок светофора (3 лампы)
    local cur = ui.getCursor()
    local contentW = math.max(ui.availableSpaceX(), 260)
    local boxW = 270
    local boxH = 68
    local boxX = cur.x + math.max((contentW - boxW) * 0.5, 0)
    local boxY = cur.y + 4

    -- Фоновый корпус светофора
    ui.drawRectFilled(vec2(boxX, boxY), vec2(boxX + boxW, boxY + boxH), rgbm(0.08, 0.09, 0.12, 0.95), 8)
    ui.drawRect(vec2(boxX, boxY), vec2(boxX + boxW, boxY + boxH), rgbm(0.25, 0.28, 0.35, 0.8), 8, nil, 1.5)

    -- Координаты 3 ламп
    local centerY = boxY + boxH * 0.5
    local r1Pos = vec2(boxX + 50, centerY)
    local r2Pos = vec2(boxX + 135, centerY)
    local gPos  = vec2(boxX + 220, centerY)
    local radius = 22

    -- Лампа 1 (Красный 1)
    local colR1 = red1 and rgbm(1.0, 0.08, 0.08, 1.0) or rgbm(0.22, 0.04, 0.04, 0.7)
    ui.drawCircleFilled(r1Pos, radius, colR1, 24)
    ui.drawCircle(r1Pos, radius, rgbm(0.4, 0.45, 0.55, 0.9), 24, 2)
    if red1 then
        ui.drawCircleFilled(r1Pos, radius + 6, rgbm(1.0, 0.0, 0.0, 0.38), 24)
    end

    -- Лампа 2 (Красный 2)
    local colR2 = red2 and rgbm(1.0, 0.08, 0.08, 1.0) or rgbm(0.22, 0.04, 0.04, 0.7)
    ui.drawCircleFilled(r2Pos, radius, colR2, 24)
    ui.drawCircle(r2Pos, radius, rgbm(0.4, 0.45, 0.55, 0.9), 24, 2)
    if red2 then
        ui.drawCircleFilled(r2Pos, radius + 6, rgbm(1.0, 0.0, 0.0, 0.38), 24)
    end

    -- Лампа 3 (Зеленый)
    local colG = green and rgbm(0.08, 1.0, 0.25, 1.0) or rgbm(0.04, 0.22, 0.06, 0.7)
    ui.drawCircleFilled(gPos, radius, colG, 24)
    ui.drawCircle(gPos, radius, rgbm(0.4, 0.45, 0.55, 0.9), 24, 2)
    if green then
        ui.drawCircleFilled(gPos, radius + 8, rgbm(0.1, 1.0, 0.2, 0.45), 24)
    end

    -- Смещение курсора под блок ламп
    ui.dummy(vec2(0, boxH + 8))

    -- 4. Текстовый статус стадии старта
    local statusText = "⚪ ОЖИДАНИЕ СТАРТА"
    local statusCol  = rgbm(0.7, 0.72, 0.78, 1.0)

    if green then
        statusText = "🟢 СТАРТ!  GO!  GO!"
        statusCol  = rgbm(0.1, 1.0, 0.3, 1.0)
    elseif red2 then
        statusText = "🔴 ВНИМАНИЕ (1 СЕК)"
        statusCol  = rgbm(1.0, 0.3, 0.2, 1.0)
    elseif red1 then
        statusText = "🔴 ГОТОВНОСТЬ (2 СЕК)"
        statusCol  = rgbm(1.0, 0.55, 0.1, 1.0)
    elseif isStage then
        statusText = "🟡 ПРИГОТОВИТЬСЯ (3 СЕК)"
        statusCol  = rgbm(1.0, 0.9, 0.15, 1.0)
    end

    drawColoredText(statusCol, statusText)

    -- 5. Панель управления судьи (СТАРТ / СБРОС)
    if isJudge() then
        ui.separator()
        local spaceW = math.max(ui.availableSpaceX(), 200)
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
        drawColoredText(rgbm(0.55, 0.58, 0.65, 1.0), "Управление светофором: Судья (Sergey Primo)")
    end
end

-- ====================================================================
-- ТОЧКА ВХОДА ДЛЯ ПРИЛОЖЕНИЯ (LUA APP / APP SHELF)
-- ====================================================================
function script.windowMain(dt)
    frameCount = frameCount + 1
    appWindowActiveFrame = frameCount

    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    if checkJudgeHotkey() then
        triggerStart()
    end

    local ok, err = pcall(renderTreeContent)
    if not ok and err then
        ac.log("[DriftStartTree] Error in windowMain: " .. tostring(err))
        drawColoredText(rgbm(1, 0.2, 0.2, 1), "Ошибка рендера: " .. tostring(err))
    end
end

windowMain = script.windowMain

-- ====================================================================
-- ТОЧКА ВХОДА ДЛЯ РАСШИРЕНИЯ ТРАССЫ (АВТОМАТИЧЕСКИЙ ОВЕРЛЕЙ У ВСЕХ НА СЕРВЕРЕ)
-- ====================================================================
function script.update(dt)
    frameCount = frameCount + 1

    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    -- Глобальная проверка F8 для судьи
    if checkJudgeHotkey() then
        triggerStart()
    end

    -- Если открыто отдельное окно приложения, не дублируем оверлей на экране
    if (frameCount - appWindowActiveFrame) < 5 then
        return
    end

    -- Если светофор выключен в настройках
    if settings.hudEnabled == false then
        return
    end

    local savedX = settings.posX or 780
    local savedY = settings.posY or 50
    local winW = 340
    local winH = isJudge() and 225 or 175

    if not overlayPosSet then
        ui.setNextWindowPosition(vec2(savedX, savedY))
        ui.setNextWindowSize(vec2(winW, winH))
        overlayPosSet = true
    end

    local winFlags = bit.bor(ui.WindowFlags.NoCollapse, ui.WindowFlags.NoScrollbar)
    ui.begin("🚦 СВЕТОФОР | ГАЗДЕРЖИМ.РФ##DRIFT_START_OVERLAY", winFlags, function()
        local curPos = ui.windowPos()
        if curPos and (math.abs(curPos.x - savedX) > 2 or math.abs(curPos.y - savedY) > 2) then
            settings.posX = math.floor(curPos.x)
            settings.posY = math.floor(curPos.y)
            savedX = curPos.x
            savedY = curPos.y
        end

        local ok, err = pcall(renderTreeContent)
        if not ok and err then
            ac.log("[DriftStartTree] Error in overlay: " .. tostring(err))
            drawColoredText(rgbm(1, 0.2, 0.2, 1), "Ошибка: " .. tostring(err))
        end
    end)
end

ac.log("[DriftStartTree] Module loaded successfully v1.1")
