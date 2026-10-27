-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР)
-- Разработано для ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch Track Extension
-- ====================================================================

-- Ключи сохранения локальных настроек пилота
local STORAGE_KEY_ENABLED = "drift_tree_hud_enabled"
local STORAGE_KEY_POS_X   = "drift_tree_pos_x"
local STORAGE_KEY_POS_Y   = "drift_tree_pos_y"

-- Идентификаторы судьи (Steam64 ID)
local JUDGE_STEAM_ID = "76561198419276819" -- Sergey Primo
local JUDGE_HOTKEY   = ui.KeyIndex.F8       -- Клавиша быстрого старта F8

-- Тайминги (в секундах)
local COUNTDOWN_TOTAL = 3.0 -- Время подготовки (3 секунды)
local GREEN_DURATION  = 2.5 -- Время свечения зеленого

-- ====================================================================
-- СОСТОЯНИЕ
-- ====================================================================
local state = {
    hudEnabled = (ac.storage[STORAGE_KEY_ENABLED] ~= "0"), -- По умолчанию ВКЛ
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

-- Проверка, является ли текущий игрок судьей/организатором
local function isJudge()
    if state.mySteamID == "" then initPlayer() end
    if state.mySteamID == JUDGE_STEAM_ID then return true end
    if string.find(string.lower(state.myDriverName), "sergey") or string.find(string.lower(state.myDriverName), "primo") then
        return true
    end
    return false
end

-- ====================================================================
-- СЕТЕВАЯ СИНХРОНИЗАЦИЯ ЧЕРЕЗ CSP
-- ====================================================================

-- Запуск отсчета (вызывает судья)
local function triggerStart()
    local simTime = ac.getSim().time
    local greenTimestamp = simTime + COUNTDOWN_TOTAL

    -- Рассылаем синхронизированную метку времени всем участникам на сервере
    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = greenTimestamp
    })

    state.targetGreenTime = greenTimestamp
    state.isActive = true
end

-- Сброс/отмена старта (вызывает судья)
local function cancelStart()
    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        greenTime = 0
    })
    state.targetGreenTime = 0
    state.isActive = false
end

-- Прием сетевого события от судьи
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

-- Поддержка команд через игровой чат (!start / !cancel)
if ac.onChatMessage then
    ac.onChatMessage(function(message, senderCarIndex)
        if isJudge() then
            local msg = string.lower(string.trim(message or ""))
            if msg == "!start" or msg == "!старт" then
                triggerStart()
            elseif msg == "!cancel" or msg == "!stop" or msg == "!стоп" or msg == "!сброс" then
                cancelStart()
            end
        end
    end)
end

-- ====================================================================
-- ОТРИСОВКА ИНТЕРФЕЙСА
-- ====================================================================
local function renderTreeUI(dt)
    state.pulse = (state.pulse + (dt or 0.016) * 6.0) % (math.pi * 2)
    local screenSize = ui.windowSize()

    -- ----------------------------------------------------------------
    -- 1. КНОПКА ВКЛЮЧЕНИЯ/ВЫКЛЮЧЕНИЯ ДЛЯ ВСЕХ ПИЛОТОВ (Правый верхний угол)
    -- ----------------------------------------------------------------
    ui.pushStyleVar(ui.StyleVar.WindowRounding, 8)
    ui.pushStyleVar(ui.StyleVar.FrameRounding, 6)

    local btnPos = vec2(screenSize.x - 200, 20)
    ui.beginTransparentWindow("drift_tree_toggle_btn", btnPos, vec2(185, 42))

    local statusText = state.hudEnabled and "🚦 Светофор: ВКЛ" or "🚫 Светофор: ВЫКЛ"
    local btnCol = state.hudEnabled and rgbm(0.15, 0.4, 0.15, 0.8) or rgbm(0.4, 0.15, 0.15, 0.8)
    local btnHover = state.hudEnabled and rgbm(0.2, 0.6, 0.2, 0.95) or rgbm(0.6, 0.2, 0.2, 0.95)

    ui.pushStyleColor(ui.Col.Button, btnCol)
    ui.pushStyleColor(ui.Col.ButtonHovered, btnHover)
    ui.pushStyleColor(ui.Col.Text, rgbm(1, 1, 1, 1))

    if ui.button(statusText, vec2(175, 34)) then
        state.hudEnabled = not state.hudEnabled
        ac.storage[STORAGE_KEY_ENABLED] = state.hudEnabled and "1" or "0"
    end

    ui.popStyleColor(3)
    ui.endTransparentWindow()

    -- ----------------------------------------------------------------
    -- 2. СУДЕЙСКАЯ ПАНЕЛЬ УПРАВЛЕНИЯ (Только для Сергея Primo)
    -- ----------------------------------------------------------------
    if isJudge() then
        -- Быстрый старт по клавише F8
        if ui.isKeyPressed(JUDGE_HOTKEY) then
            triggerStart()
        end

        local judgePos = vec2(screenSize.x - 200, 68)
        ui.beginTransparentWindow("drift_judge_panel", judgePos, vec2(185, state.isActive and 95 or 55))

        ui.pushStyleColor(ui.Col.Button, rgbm(0.1, 0.35, 0.7, 0.85))
        ui.pushStyleColor(ui.Col.ButtonHovered, rgbm(0.2, 0.5, 0.9, 1))

        if ui.button("▶ СТАРТ (F8)", vec2(175, 32)) then
            triggerStart()
        end
        ui.popStyleColor(2)

        if state.isActive then
            ui.pushStyleColor(ui.Col.Button, rgbm(0.6, 0.1, 0.1, 0.85))
            ui.pushStyleColor(ui.Col.ButtonHovered, rgbm(0.8, 0.15, 0.15, 1))
            if ui.button("✖ СБРОС", vec2(175, 26)) then
                cancelStart()
            end
            ui.popStyleColor(2)
        end

        ui.endTransparentWindow()
    end

    -- ----------------------------------------------------------------
    -- 3. САМ СВЕТОФОР (По центру экрана, если включен)
    -- ----------------------------------------------------------------
    if not state.hudEnabled then
        ui.popStyleVar(2)
        return
    end

    local simTime = ac.getSim().time
    local timeLeft = state.targetGreenTime - simTime

    -- Проверяем фазу активности
    if not state.isActive or timeLeft < -GREEN_DURATION then
        state.isActive = false
        ui.popStyleVar(2)
        return
    end

    -- Координаты светофора
    local center = vec2(screenSize.x * 0.5, screenSize.y * 0.22)
    local width = 360
    local height = 115

    ui.beginTransparentWindow("drift_tree_display", center - vec2(width * 0.5, height * 0.5), vec2(width, height))

    local drawPos = ui.getCursorScreenPos() + vec2(width * 0.5, height * 0.5)

    -- Фазы ламп
    local red1  = (timeLeft <= 2.0 and timeLeft > 0)
    local red2  = (timeLeft <= 1.0 and timeLeft > 0)
    local green = (timeLeft <= 0 and timeLeft > -GREEN_DURATION)

    -- Фон плашки светофора (стиль ГАЗДЕРЖИМ.РФ)
    local bgMin = drawPos - vec2(width * 0.5, height * 0.5)
    local bgMax = drawPos + vec2(width * 0.5, height * 0.5)
    ui.drawRectFilled(bgMin, bgMax, rgbm(0.04, 0.04, 0.05, 0.92), 14)
    ui.drawRect(bgMin, bgMax, rgbm(0.25, 0.25, 0.3, 0.95), 14, 2)

    -- Расположение 3 ламп (Красный 1, Красный 2, Зеленый)
    local r1Pos = drawPos + vec2(-100, -8)
    local r2Pos = drawPos + vec2(0, -8)
    local gPos  = drawPos + vec2(100, -8)
    local radius = 32

    -- Лампа 1 (Красный)
    local cR1 = red1 and rgbm(1.0, 0.05, 0.05, 1.0) or rgbm(0.18, 0.02, 0.02, 0.35)
    ui.drawCircleFilled(r1Pos, radius, cR1)
    ui.drawCircle(r1Pos, radius, rgbm(0.3, 0.3, 0.3, 0.8), 2)
    if red1 then
        local glow = 4 + math.sin(state.pulse) * 2
        ui.drawCircleFilled(r1Pos, radius + glow, rgbm(1.0, 0.0, 0.0, 0.3))
    end

    -- Лампа 2 (Красный)
    local cR2 = red2 and rgbm(1.0, 0.05, 0.05, 1.0) or rgbm(0.18, 0.02, 0.02, 0.35)
    ui.drawCircleFilled(r2Pos, radius, cR2)
    ui.drawCircle(r2Pos, radius, rgbm(0.3, 0.3, 0.3, 0.8), 2)
    if red2 then
        local glow = 4 + math.sin(state.pulse) * 2
        ui.drawCircleFilled(r2Pos, radius + glow, rgbm(1.0, 0.0, 0.0, 0.3))
    end

    -- Лампа 3 (Зеленый - GO!)
    local cG = green and rgbm(0.05, 1.0, 0.25, 1.0) or rgbm(0.02, 0.18, 0.04, 0.35)
    ui.drawCircleFilled(gPos, radius, cG)
    ui.drawCircle(gPos, radius, rgbm(0.3, 0.3, 0.3, 0.8), 2)
    if green then
        local glow = 6 + math.sin(state.pulse) * 3
        ui.drawCircleFilled(gPos, radius + glow, rgbm(0.1, 1.0, 0.2, 0.45))
    end

    -- Текстовый статус под лампами
    local statusStr = ""
    local textCol = rgbm(1, 1, 1, 1)

    if green then
        statusStr = "СТАРТ!  GO!  GO!"
        textCol = rgbm(0.15, 1.0, 0.35, 1)
    elseif red2 then
        statusStr = "ВНИМАНИЕ..."
        textCol = rgbm(1.0, 0.6, 0.1, 1)
    elseif red1 then
        statusStr = "ГОТОВНОСТЬ..."
        textCol = rgbm(1.0, 0.3, 0.2, 1)
    else
        statusStr = "ОЖИДАНИЕ СТАРТА"
        textCol = rgbm(0.7, 0.7, 0.7, 1)
    end

    local textWidth = ui.measureText(statusStr).x
    ui.setCursorScreenPos(drawPos + vec2(-textWidth * 0.5, 34))
    ui.textColored(statusStr, textCol)

    ui.endTransparentWindow()
    ui.popStyleVar(2)
end

-- ====================================================================
-- ОСНОВНОЙ ЦИКЛ CSP
-- ====================================================================
function script.update(dt)
    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end
    renderTreeUI(dt)
end

function script.drawUI()
    -- Для версий CSP, поддерживающих прямой хук drawUI
    renderTreeUI(0.016)
end
