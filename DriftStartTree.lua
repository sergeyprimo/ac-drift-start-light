-- ====================================================================
-- DRIFT START TREE HUD (СИНХРОНИЗИРОВАННЫЙ СВЕТОФОР СТАРТА ДРИФТА)
-- Профессиональный модуль соревнований ГАЗДЕРЖИМ.РФ (twitch.tv/sergeyprimo)
-- Assetto Corsa Custom Shaders Patch
-- Версия: 3.1 (Drift Edition: Управление доступом судей и пилотов)
-- ====================================================================

local GREEN_DURATION  = 2.5 -- Секунды горения зелёного света

local STORAGE_KEY_POS_X          = "drift_tree_pos_x"
local STORAGE_KEY_POS_Y          = "drift_tree_pos_y"
local STORAGE_KEY_ENABLED        = "drift_tree_enabled"
local STORAGE_KEY_MINIMIZED      = "drift_tree_minimized"
local STORAGE_KEY_HOTKEY         = "drift_tree_hotkey"
local STORAGE_KEY_INTERVAL       = "drift_tree_interval"
local STORAGE_KEY_ALLOWED_JUDGES = "drift_tree_allowed_judges"

local frameCount = 0
local lastUpdateFrame = -1
local autoOpened = false
local prevHotkeyDown = false
local previewPilotMode = false
local showPermsPanel = false
local manualPilotInput = ""
local serverDisabled = false

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

local allowedJudges = {}

-- Загрузка сохранённого списка назначенных судей
pcall(function()
    local savedStr = ac.storage[STORAGE_KEY_ALLOWED_JUDGES]
    if savedStr and savedStr ~= "" then
        local parsed = JSON.parse(savedStr)
        if type(parsed) == "table" then
            for _, name in ipairs(parsed) do
                if type(name) == "string" and name ~= "" then
                    allowedJudges[string.lower(name)] = true
                end
            end
        end
    end
end)

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

-- Проверка: является ли имя именем Главного Администратора (Sergey Primo)
local function isMasterAdminName(name)
    local n = string.lower(name or "")
    return string.find(n, "sergey") ~= nil or string.find(n, "primo") ~= nil or string.find(n, "сергей") ~= nil
end

-- Проверка прав Главного Администратора
local function isMasterAdmin()
    local sim = ac.getSim()
    if not sim then return true end

    -- Одиночный режим / тренировка — полный доступ
    local okOnline, isOnline = pcall(function() return sim.isOnlineRace end)
    if okOnline and not isOnline then return true end

    -- Администратор сервера
    local okAdmin, isAdmin = pcall(function() return sim.isAdmin end)
    if okAdmin and isAdmin then return true end

    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    return isMasterAdminName(state.myDriverName)
end

-- Проверка: разрешено ли пилоту судейство
local function isPilotAllowed(name)
    if not name or name == "" then return false end
    if isMasterAdminName(name) then return true end
    local n = string.lower(name)
    return allowedJudges[n] == true
end

-- Общая проверка прав судьи (Главный админ ИЛИ назначенный пилот)
local function isJudge()
    if isMasterAdmin() then return true end
    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end
    return isPilotAllowed(state.myDriverName)
end

-- Рассылка списка прав судей по сети
local function broadcastPermissions()
    local list = {}
    for name, isAllowed in pairs(allowedJudges) do
        if isAllowed then table.insert(list, name) end
    end

    ac.broadcastSharedEvent("DRIFT_START_JUDGE_PERMS", {
        judges = list
    })

    pcall(function()
        ac.storage[STORAGE_KEY_ALLOWED_JUDGES] = JSON.stringify(list)
    end)

    ac.log("[DriftStartTree] Permissions updated (" .. tostring(#list) .. " judges allowed)")
end

-- Назначить пилота судьей
local function grantJudge(name)
    if not name or name == "" then return end
    allowedJudges[string.lower(name)] = true
    broadcastPermissions()
end

-- Отозвать права судьи у пилота
local function revokeJudge(name)
    if not name or name == "" then return end
    allowedJudges[string.lower(name)] = nil
    broadcastPermissions()
end

-- Шаг таймера отсчета
local lastTimerClock = -1

-- Шаг таймера отсчета (высокоточный таймер на базе os.clock, не зависящий от frameCount)
local function advanceTimer(dt)
    local now = os.clock()
    if lastTimerClock < 0 then
        lastTimerClock = now
        return
    end

    local delta = now - lastTimerClock
    if delta < 0.0005 then
        return
    end
    lastTimerClock = now

    if delta > 0.25 then
        delta = 0.016
    end

    state.pulse = state.pulse + delta

    if state.isActive then
        state.timeLeft = state.timeLeft - delta
        if state.timeLeft < -GREEN_DURATION then
            state.isActive = false
            state.timeLeft = 0
        end
    end
end

-- Запуск отсчета (Судья)
local function triggerStart()
    -- Запуск старта судьёй гарантированно активирует светофор
    serverDisabled = false

    local interval = tonumber(ac.storage[STORAGE_KEY_INTERVAL]) or 1.0
    interval = math.clamp(interval, 0.3, 3.0)
    local totalCountdown = interval * 3.0

    state.stageInterval = interval
    state.totalDuration = totalCountdown
    state.timeLeft = totalCountdown
    state.isActive = true
    lastTimerClock = os.clock()

    -- Формируем список судей для попутной синхронизации
    local jList = {}
    for name, isAllowed in pairs(allowedJudges) do
        if isAllowed then table.insert(jList, name) end
    end

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        action = "start",
        duration = totalCountdown,
        interval = interval,
        judges = jList,
        serverDisabled = false
    })

    ac.log(string.format("[DriftStartTree] Countdown STARTED! Total: %.2fs (interval: %.2fs)", totalCountdown, interval))
end

-- Сброс отсчета (Судья)
local function cancelStart()
    state.timeLeft = 0
    state.isActive = false

    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        action = "cancel",
        serverDisabled = serverDisabled
    })

    ac.log("[DriftStartTree] Countdown CANCELLED")
end

-- Переключение глобального состояния светофора на сервере (Судья)
local function toggleServerDisabled()
    if not isJudge() then return end
    serverDisabled = not serverDisabled
    if serverDisabled then
        state.isActive = false
        state.timeLeft = 0
    end
    ac.broadcastSharedEvent("DRIFT_START_SYNC", {
        action = serverDisabled and "server_disable" or "server_enable",
        serverDisabled = serverDisabled
    })
    ac.log("[DriftStartTree] Broadcasted server " .. (serverDisabled and "DISABLE" or "ENABLE"))
end

-- Прием сетевого события от сервера / судьи (0 ms задержка)
ac.onSharedEvent("DRIFT_START_SYNC", function(data)
    if not data then return end

    -- Попутно обновляем список судей, если передан
    if data.judges and type(data.judges) == "table" then
        for _, name in ipairs(data.judges) do
            allowedJudges[string.lower(name)] = true
        end
    end

    if data.action == "server_disable" then
        serverDisabled = true
        state.isActive = false
        state.timeLeft = 0
        ac.log("[DriftStartTree] Received SYNC: SERVER DISABLED BY JUDGE")
        return
    elseif data.action == "server_enable" then
        serverDisabled = false
        state.isActive = false
        state.timeLeft = 0
        ac.log("[DriftStartTree] Received SYNC: SERVER ENABLED BY JUDGE")
        return
    elseif data.action == "cancel" or (data.duration and tonumber(data.duration) <= 0) then
        state.isActive = false
        state.timeLeft = 0
        ac.log("[DriftStartTree] Received SYNC: STOP")
        return
    elseif data.action == "start" or (data.duration and tonumber(data.duration) > 0) then
        serverDisabled = false
        state.stageInterval = tonumber(data.interval) or 1.0
        state.totalDuration = tonumber(data.duration) or (state.stageInterval * 3.0)
        state.timeLeft = state.totalDuration
        state.isActive = true
        lastTimerClock = os.clock()
        ac.log(string.format("[DriftStartTree] Received SYNC: START (total: %.2fs, step: %.2fs)", state.totalDuration, state.stageInterval))
        return
    end
end)

-- Прием события обновления судейских прав
ac.onSharedEvent("DRIFT_START_JUDGE_PERMS", function(data)
    if not data or not data.judges then return end
    allowedJudges = {}
    for _, name in ipairs(data.judges) do
        allowedJudges[string.lower(name)] = true
    end
    ac.log("[DriftStartTree] SYNC: updated judge permissions (" .. tostring(#data.judges) .. " judges)")
end)

-- Прием чат-команд (!start, !stop, !cancel, !go, !judge <ник>, !unjudge <ник>)
if ac.onChatMessage then
    ac.onChatMessage(function(message, senderCarIndex)
        if not message then return false end
        local msg = string.lower(message)

        -- Команда переключения HUD для любого игрока
        if string.find(msg, "!hud") or string.find(msg, "!tree") or string.find(msg, "!светофор") then
            local cur = ac.storage[STORAGE_KEY_ENABLED]
            ac.storage[STORAGE_KEY_ENABLED] = (cur == "0") and "1" or "0"
            return false
        end
        local senderName = ""
        if senderCarIndex and ac.getDriverName then
            local ok, nm = pcall(ac.getDriverName, senderCarIndex)
            if ok and nm then senderName = string.lower(nm) end
        end

        local isMaster = isMasterAdminName(senderName) or (senderCarIndex == state.myCarIndex and isMasterAdmin())
        local isAllowed = isMaster or isPilotAllowed(senderName)

        -- Команды назначения/снятия судей (только для Главного Админа)
        if isMaster then
            local grantTarget = string.match(msg, "!judge%s+(.+)") or string.match(msg, "!судья%s+(.+)")
            if grantTarget then
                grantJudge(grantTarget)
                return false
            end
            local revokeTarget = string.match(msg, "!unjudge%s+(.+)") or string.match(msg, "!снять%s+(.+)")
            if revokeTarget then
                revokeJudge(revokeTarget)
                return false
            end
        end

        -- Команды отключения/включения светофора на сервере (Судья)
        if isAllowed then
            if string.find(msg, "!disable") or string.find(msg, "!выкл") or string.find(msg, "!отключить") then
                if not serverDisabled then toggleServerDisabled() end
                return false
            elseif string.find(msg, "!enable") or string.find(msg, "!вкл") or string.find(msg, "!включить") then
                if serverDisabled then toggleServerDisabled() end
                return false
            end
        end

        -- Команды запуска и сброса светофора
        if isAllowed then
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
    if not isJudge() or previewPilotMode or serverDisabled then return false end

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

    -- 1. Если светофор полностью выключен (отключен на экране)
    if not isHudOn then
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.85, 0.35, 0.35, 1.0))
        ui.text("⚡ СВЕТОФОР (ОТКЛЮЧЕН)")
        ui.popStyleColor()

        local availW = ui.availableSpaceX()
        local btnW = 96
        if availW > (btnW + 10) then
            ui.sameLine(ui.getCursorX() + availW - btnW)
            ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.55, 0.22, 0.90))
            if ui.button("Включить##treeToggleOn", vec2(btnW, 20)) then
                ac.storage[STORAGE_KEY_ENABLED] = "1"
            end
            ui.popStyleColor()
        end
        ui.separator()
        ui.text("Светофор отключен на вашем экране.")
        return
    end

    -- Определение фаз отсчета
    local interval = state.stageInterval or tonumber(ac.storage[STORAGE_KEY_INTERVAL]) or 1.0
    interval = math.clamp(interval, 0.3, 3.0)
    local totalDur = interval * 3.0

    local timeLeft = state.timeLeft
    local isStage = not serverDisabled and state.isActive and (timeLeft <= (interval * 3.0) and timeLeft > (interval * 2.0))
    local red1    = not serverDisabled and state.isActive and (timeLeft <= (interval * 2.0) and timeLeft > 0)
    local red2    = not serverDisabled and state.isActive and (timeLeft <= interval and timeLeft > 0)
    local green   = not serverDisabled and state.isActive and (timeLeft <= 0 and timeLeft > -GREEN_DURATION)

    local isMinimized = (ac.storage[STORAGE_KEY_MINIMIZED] == "1")

    -- ============================================================
    -- КОМПАКТНЫЙ СВЁРНУТЫЙ РЕЖИМ (МИНИ-ПАНЕЛЬ)
    -- ============================================================
    if isMinimized then
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.25, 0.90, 1.0, 1.0))
        ui.text("🚦 СВЕТОФОР")
        ui.popStyleColor()

        ui.sameLine(86)

        -- Миниатюрный статус светофора в одну строку
        if serverDisabled then
            ui.pushStyleColor(ui.StyleColor.Text, rgbm(1.0, 0.45, 0.15, 1.0))
            ui.text("⚠️ ОТКЛЮЧЕН СУДЬЁЙ")
            ui.popStyleColor()
        elseif state.isActive then
            if green then
                ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.05, 1.0, 0.28, 1.0))
                ui.text("🟢 СТАРТ! ГАЗ В ПОЛ!")
                ui.popStyleColor()
            elseif red2 then
                ui.pushStyleColor(ui.StyleColor.Text, rgbm(1.0, 0.15, 0.15, 1.0))
                ui.text("🔴 🔴 ВНИМАНИЕ...")
                ui.popStyleColor()
            elseif red1 then
                ui.pushStyleColor(ui.StyleColor.Text, rgbm(1.0, 0.20, 0.20, 1.0))
                ui.text("🔴 ГОТОВНОСТЬ...")
                ui.popStyleColor()
            elseif isStage then
                ui.pushStyleColor(ui.StyleColor.Text, rgbm(1.0, 0.80, 0.10, 1.0))
                ui.text("🟡 ПРЕ-СТАЙДЖ")
                ui.popStyleColor()
            end
        else
            ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.55, 0.60, 0.70, 1.0))
            ui.text("● ОЖИДАНИЕ")
            ui.popStyleColor()
        end

        local availW = ui.availableSpaceX()
        local expandBtnW = 95
        local offBtnW = 60
        local startBtnW = 62

        -- Кнопка быстрого старта прямо из свёрнутого режима (для судьи)
        if isJudge() and not previewPilotMode and not serverDisabled then
            if availW > (expandBtnW + startBtnW + offBtnW + 12) then
                ui.sameLine(ui.getCursorX() + availW - (expandBtnW + startBtnW + offBtnW + 8))
                ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.10, 0.62, 0.24, 0.95))
                if ui.button("▶ СТАРТ##miniStart", vec2(startBtnW, 20)) then
                    triggerStart()
                end
                ui.popStyleColor()
                ui.sameLine()
            end
        end

        -- Кнопка «Развернуть»
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.18, 0.45, 0.85, 0.90))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.25, 0.55, 0.95, 1.0))
        if ui.button("⤢ Развернуть##treeExpand", vec2(expandBtnW, 20)) then
            ac.storage[STORAGE_KEY_MINIMIZED] = "0"
        end
        ui.popStyleColor(2)

        ui.sameLine()

        -- Кнопка «Отключить»
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.50, 0.18, 0.18, 0.85))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.70, 0.22, 0.22, 1.0))
        if ui.button("⏻ Выкл##miniOffBtn", vec2(offBtnW, 20)) then
            ac.storage[STORAGE_KEY_ENABLED] = "0"
        end
        ui.popStyleColor(2)

        return
    end

    -- ============================================================
    -- ПОЛНЫЙ РАЗВЁРНУТЫЙ РЕЖИМ (ЗАГОЛОВОК С КНОПКОЙ СВЕРНУТЬ И ОТКЛЮЧИТЬ)
    -- ============================================================
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.20, 1.0, 0.45, 1.0))
    ui.text("⚡ СВЕТОФОР СТАРТА")
    ui.popStyleColor()

    local availW = ui.availableSpaceX()
    local minBtnW = 86
    local hideBtnW = 86

    if availW > (minBtnW + hideBtnW + 12) then
        ui.sameLine(ui.getCursorX() + availW - (minBtnW + hideBtnW + 6))

        -- Кнопка СВЕРНУТЬ
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.20, 0.35, 0.55, 0.85))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.25, 0.45, 0.75, 1.0))
        if ui.button("─ Свернуть##treeMinBtn", vec2(minBtnW, 20)) then
            ac.storage[STORAGE_KEY_MINIMIZED] = "1"
        end
        ui.popStyleColor(2)

        ui.sameLine()

        -- Кнопка ОТКЛЮЧИТЬ
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.50, 0.18, 0.18, 0.85))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.70, 0.22, 0.22, 1.0))
        if ui.button("⏻ Отключить##treeHideBtn", vec2(hideBtnW, 20)) then
            ac.storage[STORAGE_KEY_ENABLED] = "0"
        end
        ui.popStyleColor(2)
    end

    ui.separator()

    -- 3. Карбоновый корпус светофора с металлическими винтами
    local cur = ui.getCursor()
    local availW = math.max(ui.availableSpaceX(), 280)
    local boxW = math.min(availW - 6, 350)
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
    if state.isActive and not serverDisabled then
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

    if serverDisabled then
        statusText = "⚠️ СВЕТОФОР ОТКЛЮЧЕН СУДЬЁЙ НА СЕРВЕРЕ"
        statusCol  = rgbm(1.0, 0.45, 0.15, 1.0)
    elseif green then
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
        if serverDisabled then
            ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.25, 0.28, 0.32, 0.60))
            ui.button("▶ СТАРТ (ОТКЛЮЧЕН)", vec2(btnW, 34))
            ui.popStyleColor()
        else
            ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.10, 0.58, 0.24, 0.95))
            ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.15, 0.75, 0.30, 1.0))
            ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.20, 0.90, 0.38, 1.0))
            if ui.button("▶ СТАРТ (" .. hotkey.short .. ")", vec2(btnW, 34)) then
                triggerStart()
            end
            ui.popStyleColor(3)
        end

        ui.sameLine(btnW + 14)

        -- Кнопка СБРОС (красная)
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.65, 0.15, 0.15, 0.95))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.80, 0.20, 0.20, 1.0))
        ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.95, 0.25, 0.25, 1.0))
        if ui.button("✖ СБРОС", vec2(btnW, 34)) then
            cancelStart()
        end
        ui.popStyleColor(3)

        -- Кнопка ГЛОБАЛЬНОГО отключения/включения светофора на сервере
        ui.dummy(vec2(0, 2))
        local fullW = math.max(ui.availableSpaceX(), 200)
        if serverDisabled then
            ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.58, 0.24, 0.95))
            ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.18, 0.75, 0.32, 1.0))
            if ui.button("🟢 ВКЛЮЧИТЬ СВЕТОФОР НА СЕРВЕРЕ##srvToggle", vec2(fullW, 26)) then
                toggleServerDisabled()
            end
            ui.popStyleColor(2)
        else
            ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.55, 0.16, 0.16, 0.90))
            ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.72, 0.20, 0.20, 1.0))
            if ui.button("🔴 ОТКЛЮЧИТЬ СВЕТОФОР НА СЕРВЕРЕ##srvToggle", vec2(fullW, 26)) then
                toggleServerDisabled()
            end
            ui.popStyleColor(2)
        end

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

        -- Строка горячей клавиши и сервисных кнопок
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.70, 0.76, 0.85, 1.0))
        ui.text("Клавиша:")
        ui.popStyleColor()
        ui.sameLine()

        local curIndex = 1
        for idx, item in ipairs(HOTKEY_LIST) do
            if item.id == hotkey.id then curIndex = idx; break end
        end

        ui.setNextItemWidth(110)
        if ui.combo("##hotkeySelect", HOTKEY_LIST[curIndex].short, ui.ComboFlags.HeightRegular, function()
            for idx, item in ipairs(HOTKEY_LIST) do
                if ui.selectable(item.name, idx == curIndex) then
                    ac.storage[STORAGE_KEY_HOTKEY] = item.id
                end
            end
        end) then
        end

        ui.sameLine()
        if ui.button("👁 Вид пилота##previewPilot", vec2(90, 20)) then
            previewPilotMode = true
        end

        -- Кнопка «Доступ пилотов» (только для Главного Админа)
        if isMasterAdmin() then
            ui.sameLine()
            local btnText = showPermsPanel and "👥 Доступ ▲" or "👥 Доступ ▼"
            local wasOpen = showPermsPanel
            if wasOpen then
                ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.20, 0.55, 0.85, 0.95))
            end
            if ui.button(btnText .. "##togglePermsBtn", vec2(85, 20)) then
                showPermsPanel = not showPermsPanel
            end
            if wasOpen then
                ui.popStyleColor()
            end
        end

        -- ============================================================
        -- ПАНЕЛЬ УПРАВЛЕНИЯ ПРАВАМИ СУДЕЙ (ТОЛЬКО ДЛЯ ГЛАВНОГО АДМИНА)
        -- ============================================================
        if isMasterAdmin() and showPermsPanel then
            ui.separator()
            ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.25, 0.85, 1.0, 1.0))
            ui.text("👥 УПРАВЛЕНИЕ СУДЕЙСКИМИ ПРАВАМИ:")
            ui.popStyleColor()

            local sim = ac.getSim()
            local carCount = 0
            pcall(function() if sim and sim.carsCount then carCount = sim.carsCount end end)

            local foundPilots = {}
            for i = 0, carCount - 1 do
                local car = ac.getCar(i)
                if car and car.isConnected then
                    local dName = ac.getDriverName(i) or ("Машина #" .. i)
                    table.insert(foundPilots, { index = i, name = dName })
                end
            end

            if #foundPilots == 0 then
                ui.text("• Нет подключенных пилотов на сервере")
            else
                for _, p in ipairs(foundPilots) do
                    local pName = p.name
                    local isMaster = isMasterAdminName(pName)
                    local isDelegated = isPilotAllowed(pName)

                    if isMaster then
                        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1.0, 0.85, 0.25, 1.0))
                        ui.text(string.format("★ %s (Владелец)", pName))
                        ui.popStyleColor()
                    else
                        local statusCol = isDelegated and rgbm(0.2, 1.0, 0.4, 1.0) or rgbm(0.70, 0.72, 0.78, 1.0)
                        local statusTag = isDelegated and "[СУДЬЯ]" or "[ПИЛОТ]"

                        ui.pushStyleColor(ui.StyleColor.Text, statusCol)
                        ui.text(string.format("%s %s", statusTag, pName))
                        ui.popStyleColor()

                        ui.sameLine(ui.availableSpaceX() - 86)
                        if isDelegated then
                            ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.65, 0.15, 0.15, 0.90))
                            if ui.button("Забрать##rev" .. p.index, vec2(80, 20)) then
                                revokeJudge(pName)
                            end
                            ui.popStyleColor()
                        else
                            ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.55, 0.22, 0.90))
                            if ui.button("+ Судья##gnt" .. p.index, vec2(80, 20)) then
                                grantJudge(pName)
                            end
                            ui.popStyleColor()
                        end
                    end
                end
            end

            -- Ручной ввод ника пилота (если пилот ещё подключается)
            ui.dummy(vec2(0, 2))
            ui.setNextItemWidth(170)
            manualPilotInput = ui.inputText("Ник пилота##manInput", manualPilotInput or "", ui.InputTextFlags.Placeholder)
            ui.sameLine()
            if ui.button("+ Назначить##manAdd", vec2(86, 20)) then
                if manualPilotInput and string.len(manualPilotInput) > 1 then
                    grantJudge(manualPilotInput)
                    manualPilotInput = ""
                end
            end
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
-- ТОЧКА ВХОДА ДЛЯ ОКНА ПРИЛОЖЕНИЯ (APP SHELF)
-- ====================================================================
function script.windowMain(dt)
    frameCount = frameCount + 1
    ac.storage["drift_tree_app_active"] = tostring(os.clock())

    local isEnabled = (ac.storage[STORAGE_KEY_ENABLED] ~= "0")
    if not isEnabled then
        if ui.setNextWindowSize then
            ui.setNextWindowSize(vec2(270, 72))
        end
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.70, 0.75, 0.85, 1.0))
        ui.text("⚡ Светофор отключен на экране")
        ui.popStyleColor()
        ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.12, 0.55, 0.24, 0.95))
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.18, 0.72, 0.32, 1.0))
        if ui.button("🚦 Включить светофор##turnOnApp", vec2(220, 24)) then
            ac.storage[STORAGE_KEY_ENABLED] = "1"
        end
        ui.popStyleColor(2)
        return
    end

    local isMinimized = (ac.storage[STORAGE_KEY_MINIMIZED] == "1")
    local cardW = isMinimized and (isJudge() and not previewPilotMode and 410 or 300) or 390
    local cardH = isMinimized and 56 or ((isJudge() and not previewPilotMode) and (showPermsPanel and 535 or 345) or 175)

    if ui.setNextWindowSize then
        ui.setNextWindowSize(vec2(cardW, cardH))
    end

    local ok, err = pcall(renderTreeContent, dt)
    if not ok and err then
        ac.log("[DriftStartTree] Error in windowMain: " .. tostring(err))
        ui.text("Ошибка: " .. tostring(err))
    end
end

windowMain = script.windowMain

-- ====================================================================
-- ТОЧКА ВХОДА 60 FPS ОБНОВЛЕНИЯ
-- ====================================================================
function script.update(dt)
    frameCount = frameCount + 1
    advanceTimer(dt)

    if not state.myDriverName or state.myDriverName == "" then
        initPlayer()
    end

    if checkJudgeHotkey() then
        triggerStart()
    end

    -- Автоматическое открытие окна при старте заезда
    if not autoOpened and frameCount > 5 then
        pcall(function()
            if ac.setWindowOpen and not ac.isWindowOpen("main") then
                ac.log("[DriftStartTree] Auto-opening app window 'main'")
                ac.setWindowOpen("main", true)
            end
        end)
        autoOpened = true
    end
end

ac.log("[DriftStartTree] Standalone App loaded v3.1 (Permissions Edition)")
