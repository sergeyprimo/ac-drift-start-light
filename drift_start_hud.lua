-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР)
-- Разработано для ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch Track Extension & Lua App
-- ====================================================================

local STORAGE_KEY_POS_X   = "drift_tree_pos_x"
local STORAGE_KEY_POS_Y   = "drift_tree_pos_y"
local STORAGE_KEY_ENABLED = "drift_tree_enabled"

local JUDGE_STEAM_ID = "76561198419276819" -- Sergey Primo
local JUDGE_HOTKEY   = ui.KeyIndex.F8       -- F8 для мгновенного запуска

local COUNTDOWN_TOTAL = 3.0 -- Секунд до зеленого
local GREEN_DURATION  = 2.5 -- Сколько секунд горит зеленый

local isRunningAsStandaloneApp = false

local state = {
    hudEnabled = (ac.storage[STORAGE_KEY_ENABLED] ~= "0"),
    targetGreenTime = 0,
    isActive = false,
    myCarIndex = 0,
    mySteamID = "",
    myDriverName = "",
    pulse = 0
}

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
    if state.mySteamID == JUDGE_STEAM_ID then return true end
    local nameLower = string.lower(state.myDriverName or "")
    if string.find(nameLower, "sergey") or string.find(nameLower, "primo") then
        return true
    end
    return false
end

-- Запуск отсчета
local function triggerStart()
    local simTime = ac.getSim().time
    local greenTimestamp = simTime + COUNTDOWN_TOTAL

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = greenTimestamp
    })

    state.targetGreenTime = greenTimestamp
    state.isActive = true
end

-- Сброс отсчета
local function cancelStart()
    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = 0
    })
    state.targetGreenTime = 0
    state.isActive = false
end

-- Прием события от судьи
ac.onSharedEvent("DRIFT_START_SYNC", function(data)
    if data and data.greenTime then
        if data.greenTime == 0 then
            state.isActive = false
            state.targetGreenTime = 0
        else
            state.targetGreenTime = data.greenTime
            state.isActive = true
        end
    end
end)

-- Команды в чате (!start / !cancel)
if ac.onChatMessage then
    ac.onChatMessage(function(message, senderCarIndex)
        if isJudge() and message then
            local msg = string.lower(message)
            if string.find(msg, "!start") or string.find(msg, "!старт") then
                triggerStart()
            elseif string.find(msg, "!cancel") or string.find(msg, "!сброс") or string.find(msg, "!stop") then
                cancelStart()
            end
        end
    end)
end

-- ====================================================================
-- ОСНОВНОЙ РЕНДЕР ИНТЕРФЕЙСА
-- ====================================================================
local function renderTreeHUD()
    local defaultX = 760
    local defaultY = 40
    local savedX = tonumber(ac.storage[STORAGE_KEY_POS_X]) or defaultX
    local savedY = tonumber(ac.storage[STORAGE_KEY_POS_Y]) or defaultY

    ui.setNextWindowPos(vec2(savedX, savedY), ui.Cond.FirstUseEver)

    local winW = 380
    local winH = isJudge() and 180 or 140
    ui.setNextWindowSize(vec2(winW, winH), ui.Cond.FirstUseEver)

    local winFlags = bit.bor(ui.WindowFlags.NoCollapse, ui.WindowFlags.NoScrollbar)

    ui.pushStyleVar(ui.StyleVar.WindowRounding, 10)
    ui.pushStyleVar(ui.StyleVar.WindowBorderSize, 1.5)
    ui.pushStyleColor(ui.StyleColor.WindowBg, rgbm(0.05, 0.06, 0.08, 0.95))
    ui.pushStyleColor(ui.StyleColor.Border, rgbm(0.20, 0.55, 0.95, 0.8))

    local title = "🚦 СВЕТОФОР | ГАЗДЕРЖИМ.РФ##DRIFT_START_TREE"

    ui.begin(title, winFlags, function()
        -- Сохранение положения окна при перемещении пользователем
        local curPos = ui.windowPos()
        if curPos.x ~= savedX or curPos.y ~= savedY then
            ac.storage[STORAGE_KEY_POS_X] = tostring(math.floor(curPos.x))
            ac.storage[STORAGE_KEY_POS_Y] = tostring(math.floor(curPos.y))
            savedX = curPos.x
            savedY = curPos.y
        end

        -- Верхняя строка: переключатель ВКЛ/ВЫКЛ
        local toggleText = state.hudEnabled and "Светофор: ВКЛЮЧЕН" or "Светофор: ВЫКЛЮЧЕН"
        local toggleCol = state.hudEnabled and rgbm(0.2, 1.0, 0.4, 1) or rgbm(0.7, 0.2, 0.2, 1)
        ui.textColored(toggleText, toggleCol)
        ui.sameLine(winW - 130)
        if ui.button(state.hudEnabled and "Выключить" or "Включить", vec2(100, 22)) then
            state.hudEnabled = not state.hudEnabled
            ac.storage[STORAGE_KEY_ENABLED] = state.hudEnabled and "1" or "0"
        end

        ui.separator()

        local simTime = ac.getSim().time
        local timeLeft = state.targetGreenTime - simTime

        if not state.isActive or timeLeft < -GREEN_DURATION then
            state.isActive = false
        end

        -- Фазы ламп
        local red1  = state.isActive and (timeLeft <= 2.0 and timeLeft > 0)
        local red2  = state.isActive and (timeLeft <= 1.0 and timeLeft > 0)
        local green = state.isActive and (timeLeft <= 0 and timeLeft > -GREEN_DURATION)

        -- Отрисовка 3 ламп по центру окна
        local startPos = ui.getCursorScreenPos()
        local lampCenterY = startPos.y + 36
        local r1Pos = vec2(startPos.x + 70, lampCenterY)
        local r2Pos = vec2(startPos.x + 180, lampCenterY)
        local gPos  = vec2(startPos.x + 290, lampCenterY)
        local radius = 24

        -- Лампа 1 (Красный)
        local colR1 = red1 and rgbm(1.0, 0.05, 0.05, 1.0) or rgbm(0.2, 0.02, 0.02, 0.4)
        ui.drawCircleFilled(r1Pos, radius, colR1)
        ui.drawCircle(r1Pos, radius, rgbm(0.4, 0.4, 0.4, 0.8), 2)
        if red1 then ui.drawCircleFilled(r1Pos, radius + 4, rgbm(1.0, 0.0, 0.0, 0.3)) end

        -- Лампа 2 (Красный)
        local colR2 = red2 and rgbm(1.0, 0.05, 0.05, 1.0) or rgbm(0.2, 0.02, 0.02, 0.4)
        ui.drawCircleFilled(r2Pos, radius, colR2)
        ui.drawCircle(r2Pos, radius, rgbm(0.4, 0.4, 0.4, 0.8), 2)
        if red2 then ui.drawCircleFilled(r2Pos, radius + 4, rgbm(1.0, 0.0, 0.0, 0.3)) end

        -- Лампа 3 (Зеленый)
        local colG = green and rgbm(0.05, 1.0, 0.25, 1.0) or rgbm(0.02, 0.2, 0.04, 0.4)
        ui.drawCircleFilled(gPos, radius, colG)
        ui.drawCircle(gPos, radius, rgbm(0.4, 0.4, 0.4, 0.8), 2)
        if green then ui.drawCircleFilled(gPos, radius + 6, rgbm(0.1, 1.0, 0.2, 0.4)) end

        -- Текстовый статус под лампами
        ui.dummy(vec2(0, 68))
        local statusStr = "ОЖИДАНИЕ СТАРТА"
        local statusCol = rgbm(0.6, 0.6, 0.6, 1)

        if green then
            statusStr = "СТАРТ!  GO!  GO!"
            statusCol = rgbm(0.1, 1.0, 0.3, 1)
        elseif red2 then
            statusStr = "ВНИМАНИЕ (1 СЕК)"
            statusCol = rgbm(1.0, 0.6, 0.1, 1)
        elseif red1 then
            statusStr = "ГОТОВНОСТЬ (2 СЕК)"
            statusCol = rgbm(1.0, 0.3, 0.2, 1)
        elseif state.isActive then
            statusStr = "ПРИГОТОВИТЬСЯ (3 СЕК)"
            statusCol = rgbm(0.9, 0.9, 0.2, 1)
        end

        ui.textColored(statusStr, statusCol)

        -- Панель судьи (только для Сергея)
        if isJudge() then
            ui.sameLine(winW - 190)
            if ui.button("▶ СТАРТ (F8)", vec2(90, 24)) then
                triggerStart()
            end
            ui.sameLine()
            if ui.button("✖ СБРОС", vec2(70, 24)) then
                cancelStart()
            end
        end
    end)

    ui.popStyleColor(2)
    ui.popStyleVar(2)
end

-- ====================================================================
-- ЦИКЛ ОБНОВЛЕНИЯ
-- ====================================================================
function script.update(dt)
    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    -- Проверка горячей клавиши F8 для судьи
    if isJudge() and ui.isKeyPressed(JUDGE_HOTKEY) then
        triggerStart()
    end

    if not isRunningAsStandaloneApp then
        local ok, err = pcall(renderTreeHUD)
        if not ok and err then
            ac.log("DriftStartTree Error: " .. tostring(err))
        end
    end
end

function script.windowMain()
    isRunningAsStandaloneApp = true
    local ok, err = pcall(renderTreeHUD)
    if not ok and err then
        ac.log("DriftStartTree App Error: " .. tostring(err))
    end
end
