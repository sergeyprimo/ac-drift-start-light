-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР)
-- Разработано для ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch Track Extension & Lua App
-- ====================================================================

local JUDGE_STEAM_ID = "76561198419276819" -- Sergey Primo
local JUDGE_HOTKEY   = ui.KeyIndex.F8       -- F8 для мгновенного запуска

local COUNTDOWN_TOTAL = 3.0 -- Секунд до зеленого
local GREEN_DURATION  = 2.5 -- Сколько секунд горит зеленый

local settings = ac.storage{
    hudEnabled = true,
    posX = 760,
    posY = 40
}

local isRunningAsApp = false

local state = {
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
    local sim = ac.getSim()
    if sim and sim.isServerAdmin then return true end
    return true -- Разрешаем управление в локальном окне
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
        if message then
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
-- ОСНОВНОЙ РЕНДЕР СОДЕРЖИМОГО СВЕТОФОРА
-- ====================================================================
local function renderTreeContent()
    state.pulse = (state.pulse + 0.05) % (math.pi * 2)

    -- 1. Верхняя панель: статус и кнопка
    local toggleText = settings.hudEnabled and "🚦 Светофор: ВКЛ" or "🚫 Светофор: ВЫКЛ"
    local toggleCol = settings.hudEnabled and rgbm(0.2, 1.0, 0.4, 1) or rgbm(0.8, 0.2, 0.2, 1)
    ui.textColored(toggleText, toggleCol)
    
    local availW = ui.availableSpaceX()
    if availW > 120 then
        ui.sameLine(availW - 105)
        if ui.button(settings.hudEnabled and "Выключить" or "Включить", vec2(105, 24)) then
            settings.hudEnabled = not settings.hudEnabled
        end
    end

    ui.separator()

    -- Если выключен пользователем — показываем только компактную плашку
    if not settings.hudEnabled then
        ui.textColored("Светофор выключен. Нажмите кнопку выше.", rgbm(0.5, 0.5, 0.5, 1))
        return
    end

    -- 2. Расчет времени
    local simTime = ac.getSim().time
    local timeLeft = state.targetGreenTime - simTime

    if not state.isActive or timeLeft < -GREEN_DURATION then
        state.isActive = false
    end

    local red1  = state.isActive and (timeLeft <= 2.0 and timeLeft > 0)
    local red2  = state.isActive and (timeLeft <= 1.0 and timeLeft > 0)
    local green = state.isActive and (timeLeft <= 0 and timeLeft > -GREEN_DURATION)

    -- 3. Отрисовка 3 ламп по центру окна
    local cursor = ui.getCursor()
    local winW = math.max(ui.availableSpaceX(), 300)
    local lampY = cursor.y + 40
    local centerX = cursor.x + winW * 0.5

    local r1Pos = vec2(centerX - 85, lampY)
    local r2Pos = vec2(centerX, lampY)
    local gPos  = vec2(centerX + 85, lampY)
    local radius = 26

    -- Лампа 1 (Красный)
    local colR1 = red1 and rgbm(1.0, 0.05, 0.05, 1.0) or rgbm(0.25, 0.03, 0.03, 0.45)
    ui.drawCircleFilled(r1Pos, radius, colR1, 24)
    ui.drawCircle(r1Pos, radius, rgbm(0.5, 0.5, 0.5, 0.8), 24, 2)
    if red1 then ui.drawCircleFilled(r1Pos, radius + 5, rgbm(1.0, 0.0, 0.0, 0.35), 24) end

    -- Лампа 2 (Красный)
    local colR2 = red2 and rgbm(1.0, 0.05, 0.05, 1.0) or rgbm(0.25, 0.03, 0.03, 0.45)
    ui.drawCircleFilled(r2Pos, radius, colR2, 24)
    ui.drawCircle(r2Pos, radius, rgbm(0.5, 0.5, 0.5, 0.8), 24, 2)
    if red2 then ui.drawCircleFilled(r2Pos, radius + 5, rgbm(1.0, 0.0, 0.0, 0.35), 24) end

    -- Лампа 3 (Зеленый)
    local colG = green and rgbm(0.05, 1.0, 0.25, 1.0) or rgbm(0.03, 0.25, 0.05, 0.45)
    ui.drawCircleFilled(gPos, radius, colG, 24)
    ui.drawCircle(gPos, radius, rgbm(0.5, 0.5, 0.5, 0.8), 24, 2)
    if green then ui.drawCircleFilled(gPos, radius + 7, rgbm(0.1, 1.0, 0.2, 0.45), 24) end

    -- Отступ под лампы
    ui.dummy(vec2(0, 80))

    -- 4. Текстовый статус под лампами
    local statusStr = "ОЖИДАНИЕ СТАРТА"
    local statusCol = rgbm(0.65, 0.65, 0.65, 1)

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
    ui.separator()

    -- 5. Кнопки управления (СТАРТ / СБРОС)
    local spaceW = ui.availableSpaceX()
    local btnW = math.max((spaceW - 12) * 0.5, 80)

    if ui.button("▶ СТАРТ (F8)", vec2(btnW, 36)) then
        triggerStart()
    end
    ui.sameLine()
    if ui.button("✖ СБРОС", vec2(btnW, 36)) then
        cancelStart()
    end
end

-- ====================================================================
-- ДЛЯ РЕЖИМА ПРИЛОЖЕНИЯ (APP SHELF)
-- ====================================================================
function script.windowMain(dt)
    isRunningAsApp = true
    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end
    if ui.isKeyPressed(JUDGE_HOTKEY) then
        triggerStart()
    end
    renderTreeContent()
end

windowMain = script.windowMain

-- ====================================================================
-- ДЛЯ РЕЖИМА РАСШИРЕНИЯ ТРАССЫ (АВТОМАТИЧЕСКИЙ ОВЕРЛЕЙ У ВСЕХ НА СЕРВЕРЕ)
-- ====================================================================
function script.update(dt)
    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end
    if ui.isKeyPressed(JUDGE_HOTKEY) then
        triggerStart()
    end

    -- Если окно уже открыто в виде приложения из правого меню, не дублируем
    if isRunningAsApp then
        return
    end

    -- Отрисовка плавающего оверлея на трассе
    local savedX = settings.posX or 760
    local savedY = settings.posY or 40
    local winW = 360
    local winH = 200

    ui.setNextWindowPosition(vec2(savedX, savedY))
    ui.setNextWindowSize(vec2(winW, winH))

    local winFlags = bit.bor(ui.WindowFlags.NoCollapse, ui.WindowFlags.NoScrollbar)
    ui.begin("🚦 СВЕТОФОР | ГАЗДЕРЖИМ.РФ##DRIFT_START_OVERLAY", winFlags, function()
        local curPos = ui.windowPos()
        if curPos and (curPos.x ~= savedX or curPos.y ~= savedY) then
            settings.posX = math.floor(curPos.x)
            settings.posY = math.floor(curPos.y)
            savedX = curPos.x
            savedY = curPos.y
        end
        renderTreeContent()
    end)
end
