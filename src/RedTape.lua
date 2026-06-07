RedTape = {}
RedTape.dir = g_currentModDirectory
RedTape.SaveKey = "RedTape"

source(RedTape.dir .. "src/gui/MenuRedTape.lua")

function RedTape:loadMap()
    g_currentMission.RedTape = self

    MessageType.RT_DATA_UPDATED = nextMessageTypeId()

    self.monthStarted = 0
    self.leaseDeals = {}
    self.constantChecksUpdateIntervalMs = 2000    -- interval for constant checks
    self.constantChecksUpdateTime = 5000          -- initial interval post load
    self.infrequentChecksUpdateIntervalMs = 30000 -- interval for infrequent checks
    self.infrequentChecksUpdateTime = 30000       -- initial interval for infrequent checks
    self.sprayAreaCheckInterval = 500             -- interval for spray area checks
    self.sprayCheckTime = 0                       -- initial time for spray area checks
    self.fillTypeCache = nil

    g_gui:loadProfiles(RedTape.dir .. "src/gui/guiProfiles.xml")

    local guiRedTape = MenuRedTape.new(g_i18n)
    g_gui:loadGui(RedTape.dir .. "src/gui/MenuRedTape.xml", "menuRedTape", guiRedTape, true)

    RedTape.addIngameMenuPage(guiRedTape, "menuRedTape", { 0, 0, 1024, 1024 },
        RedTape:makeCheckEnabledPredicate(), "pageSettings")
    guiRedTape:initialize()

    self.TaxSystem = RTTaxSystem.new()
    self.SchemeSystem = RTSchemeSystem.new()
    self.PolicySystem = RTPolicySystem.new()
    self.GrantSystem = RTGrantSystem.new()
    self.InfoGatherer = RTInfoGatherer.new()
    self.EventLog = RTEventLog.new()
    self.RedTapeMenu = guiRedTape
    self.didLoadFromXML = false
    self.missionStarted = false
    self.settings = {}

    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, RedTape.hourChanged)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, RedTape.periodChanged)
    g_messageCenter:subscribe(MessageType.PLAYER_FARM_CHANGED, RedTape.playerFarmChanged)

    self:loadFromXMLFile()
    RedTape.injectMenu()

    if g_addCheatCommands and g_currentMission:getIsServer() then
        addConsoleCommand("rtAddPoints", "Add or remove policy points for current farm. Usage: rtAddPoints amount", "consoleCommandAddPoints", self)
        addConsoleCommand("rtTriggerDemo", "Make a demo scheme available for current farm. Usage: rtTriggerDemo [tractor|brand]", "consoleCommandTriggerDemo", self)
    end
end

function RedTape:delete()
    if g_addCheatCommands then
        removeConsoleCommand("rtAddPoints")
        removeConsoleCommand("rtTriggerDemo")
    end
end

function RedTape:consoleCommandAddPoints(amount)
    if not g_currentMission:getIsServer() then return "Server only" end
    local numAmount = tonumber(amount)
    if numAmount == nil then
        return "Usage: rtAddPoints amount (e.g. rtAddPoints 100 or rtAddPoints -50)"
    end
    
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if farm == nil or farm.farmId == 0 then
        return "Error: No farm found for current player"
    end

    g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farm.farmId, numAmount, g_i18n:getText("rt_policy_custom")))
    return string.format("Applied %d points to farm %d", numAmount, farm.farmId)
end

function RedTape:consoleCommandTriggerDemo(demoType)
    if not g_currentMission:getIsServer() then return "Server only" end

    demoType = (demoType or "tractor"):lower()
    local schemeIndex
    if demoType == "tractor" then
        schemeIndex = RTSchemeIds.TRACTOR_DEMO
    elseif demoType == "brand" then
        schemeIndex = RTSchemeIds.BRAND_DEMO
    else
        return "Usage: rtTriggerDemo [tractor|brand]"
    end

    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if farm == nil or farm.farmId == 0 then
        return "Error: No farm found for current player"
    end

    local policySystem = g_currentMission.RedTape.PolicySystem
    local farmTier = policySystem:getProgressForCurrentFarm().tier

    local scheme = RTScheme.new()
    scheme.tier = farmTier
    scheme.schemeIndex = schemeIndex
    scheme:initialise()

    g_client:getServerConnection():sendEvent(RTSchemeActivatedEvent.new(scheme))
    return string.format("Created %s demo scheme at tier %s", demoType, RTPolicySystem.TIER_NAMES[farmTier])
end

function RedTape:update(dt)
    if self.constantChecksUpdateTime > 0 then
        self.constantChecksUpdateTime = self.constantChecksUpdateTime - dt
    else
        self.InfoGatherer:runConstantChecks()
        self.constantChecksUpdateTime = self.constantChecksUpdateIntervalMs
    end

    if self.infrequentChecksUpdateTime > 0 then
        self.infrequentChecksUpdateTime = self.infrequentChecksUpdateTime - dt
    else
        self.InfoGatherer:runInfrequentChecks()
        self.infrequentChecksUpdateTime = self.infrequentChecksUpdateIntervalMs
    end

    self.SchemeSystem:checkPendingVehicles()
end

function RedTape:makeCheckEnabledPredicate()
    return function() return true end
end

function RedTape:hourChanged()
    if (not g_currentMission:getIsServer()) then return end
    local rt = g_currentMission.RedTape

    rt.InfoGatherer:hourChanged()
end

function RedTape:periodChanged()
    local rt = g_currentMission.RedTape
    rt.EventLog:pruneOld()

    if (not g_currentMission:getIsServer()) then return end
    rt.InfoGatherer:periodChanged()
    rt.PolicySystem:periodChanged()
    rt.SchemeSystem:periodChanged()
    rt.TaxSystem:periodChanged()
    rt.GrantSystem:periodChanged()
    rt.InfoGatherer:resetMonthlyData()

    local month = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
    if month == 6 or month == 12 then
        rt.InfoGatherer:resetBiAnnualData()
    end
end

function RedTape:populateFillTypeCache()
    self.fillTypeCache = {}
    for k, v in pairs(g_fillTypeManager.indexToTitle) do
        self.fillTypeCache[v] = k
    end
end

function RedTape:getFillTypeCache()
    if self.fillTypeCache == nil then
        self:populateFillTypeCache()
    end
    return self.fillTypeCache
end

function RedTape:loadFromXMLFile()
    if (not g_currentMission:getIsServer()) then return end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory;
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    savegameFolderPath = savegameFolderPath .. "/"

    if fileExists(savegameFolderPath .. RedTape.SaveKey .. ".xml") then
        local xmlFile = loadXMLFile(RedTape.SaveKey, savegameFolderPath .. RedTape.SaveKey .. ".xml");
        self.monthStarted = getXMLInt(xmlFile, RedTape.SaveKey .. "#monthStarted") or 8
        g_currentMission.RedTape.PolicySystem:loadFromXMLFile(xmlFile)
        g_currentMission.RedTape.SchemeSystem:loadFromXMLFile(xmlFile)
        g_currentMission.RedTape.TaxSystem:loadFromXMLFile(xmlFile)
        g_currentMission.RedTape.GrantSystem:loadFromXMLFile(xmlFile)
        g_currentMission.RedTape.EventLog:loadFromXMLFile(xmlFile)
        g_currentMission.RedTape.InfoGatherer:loadFromXMLFile(xmlFile)

        -- Load settings
        for _, id in pairs(RedTape.menuItems) do
            local setting = RedTape.SETTINGS[id]
            if setting then
                local xmlValueKey = RedTape.SaveKey .. ".settings." .. id .. "#value"
                local defaultValue = setting.values[setting.default]
                local value = defaultValue
                local value_string = tostring(value)

                if hasXMLProperty(xmlFile, xmlValueKey) then
                    if type(defaultValue) == 'number' then
                        value = getXMLFloat(xmlFile, xmlValueKey) or defaultValue

                        if value == math.floor(value) then
                            value_string = tostring(value)
                        else
                            value_string = string.format("%.3f", value)
                        end
                    elseif type(defaultValue) == 'boolean' then
                        local xmlBool = getXMLBool(xmlFile, xmlValueKey)
                        value = xmlBool ~= nil and xmlBool or defaultValue
                        value_string = tostring(value)
                    end
                end
                g_currentMission.RedTape.settings[id] = value
            end
        end

        self.didLoadFromXML = true

        delete(xmlFile)
    end
end

function RedTape:saveToXmlFile()
    if (not g_currentMission:getIsServer()) then return end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory .. "/"
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(),
            g_currentMission.missionInfo.savegameIndex .. "/")
    end

    local xmlFile = createXMLFile(RedTape.SaveKey, savegameFolderPath .. RedTape.SaveKey .. ".xml", RedTape.SaveKey);

    setXMLInt(xmlFile, RedTape.SaveKey .. "#monthStarted", g_currentMission.RedTape.monthStarted)

    g_currentMission.RedTape.PolicySystem:saveToXmlFile(xmlFile)
    g_currentMission.RedTape.SchemeSystem:saveToXmlFile(xmlFile)
    g_currentMission.RedTape.TaxSystem:saveToXmlFile(xmlFile)
    g_currentMission.RedTape.GrantSystem:saveToXmlFile(xmlFile)
    g_currentMission.RedTape.EventLog:saveToXmlFile(xmlFile)
    g_currentMission.RedTape.InfoGatherer:saveToXmlFile(xmlFile)

    -- Save settings
    for _, id in pairs(RedTape.menuItems) do
        if RedTape.SETTINGS[id] then
            local xmlValueKey = RedTape.SaveKey .. ".settings." .. id .. "#value"
            local value = g_currentMission.RedTape.settings[id]
            if type(value) == 'number' then
                setXMLFloat(xmlFile, xmlValueKey, value)
            elseif type(value) == 'boolean' then
                setXMLBool(xmlFile, xmlValueKey, value)
            end
        end
    end

    saveXMLFile(xmlFile);
    delete(xmlFile);
end

function RedTape:sendInitialClientState(connection, user, farm)
    connection:sendEvent(RTInitialClientStateEvent.new())
end

-- from Courseplay
function RedTape.addIngameMenuPage(frame, pageName, uvs, predicateFunc, insertAfter)
    local targetPosition = 0

    -- remove all to avoid warnings
    for k, v in pairs({ pageName }) do
        g_inGameMenu.controlIDs[v] = nil
    end

    for i = 1, #g_inGameMenu.pagingElement.elements do
        local child = g_inGameMenu.pagingElement.elements[i]
        if child == g_inGameMenu[insertAfter] then
            targetPosition = i + 1;
            break
        end
    end

    g_inGameMenu[pageName] = frame
    g_inGameMenu.pagingElement:addElement(g_inGameMenu[pageName])

    g_inGameMenu:exposeControlsAsFields(pageName)

    for i = 1, #g_inGameMenu.pagingElement.elements do
        local child = g_inGameMenu.pagingElement.elements[i]
        if child == g_inGameMenu[pageName] then
            table.remove(g_inGameMenu.pagingElement.elements, i)
            table.insert(g_inGameMenu.pagingElement.elements, targetPosition, child)
            break
        end
    end

    for i = 1, #g_inGameMenu.pagingElement.pages do
        local child = g_inGameMenu.pagingElement.pages[i]
        if child.element == g_inGameMenu[pageName] then
            table.remove(g_inGameMenu.pagingElement.pages, i)
            table.insert(g_inGameMenu.pagingElement.pages, targetPosition, child)
            break
        end
    end

    g_inGameMenu.pagingElement:updateAbsolutePosition()
    g_inGameMenu.pagingElement:updatePageMapping()

    g_inGameMenu:registerPage(g_inGameMenu[pageName], nil, predicateFunc)

    local iconFileName = Utils.getFilename('images/menuIcon.dds', RedTape.dir)
    g_inGameMenu:addPageTab(g_inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))

    for i = 1, #g_inGameMenu.pageFrames do
        local child = g_inGameMenu.pageFrames[i]
        if child == g_inGameMenu[pageName] then
            table.remove(g_inGameMenu.pageFrames, i)
            table.insert(g_inGameMenu.pageFrames, targetPosition, child)
            break
        end
    end

    g_inGameMenu:rebuildTabList()
end

function RedTape.periodToMonth(period)
    period = period + 2
    if period > 12 then
        period = period - 12
    end
    return period
end

function RedTape.monthToString(month)
    if month == 1 then
        return g_i18n:getText("ui_month1")
    elseif month == 2 then
        return g_i18n:getText("ui_month2")
    elseif month == 3 then
        return g_i18n:getText("ui_month3")
    elseif month == 4 then
        return g_i18n:getText("ui_month4")
    elseif month == 5 then
        return g_i18n:getText("ui_month5")
    elseif month == 6 then
        return g_i18n:getText("ui_month6")
    elseif month == 7 then
        return g_i18n:getText("ui_month7")
    elseif month == 8 then
        return g_i18n:getText("ui_month8")
    elseif month == 9 then
        return g_i18n:getText("ui_month9")
    elseif month == 10 then
        return g_i18n:getText("ui_month10")
    elseif month == 11 then
        return g_i18n:getText("ui_month11")
    elseif month == 12 then
        return g_i18n:getText("ui_month12")
    end
end

function RedTape.tableHasValue(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

function RedTape.tableHasKey(tab, key)
    return tab[key] ~= nil
end

function RedTape.tableCount(tab)
    local count = 0

    if type(tab) ~= "table" then
        return 0
    end

    for _, _ in pairs(tab) do
        count = count + 1
    end
    return count
end

function RedTape.generateId()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

function RedTape.getCumulativeMonth()
    local month = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
    local year = g_currentMission.environment.currentYear - 1

    if month < 3 then
        year = year + 1
    end

    return (year * 12) + month
end

function RedTape.getElapsedMonths()
    return RedTape.getCumulativeMonth() - g_currentMission.RedTape.monthStarted
end

function RedTape.getActualYear()
    local month = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
    local year = g_currentMission.environment.currentYear

    if month < 3 then
        year = year + 1
    end

    return year
end

function RedTape.getGridPosition(x, y, z, gridSize)
    gridSize = gridSize or 10

    local gridX = math.floor(x / gridSize) * gridSize + gridSize / 2
    local gridY = math.floor(y / gridSize) * gridSize + gridSize / 2
    local gridZ = math.floor(z / gridSize) * gridSize + gridSize / 2

    return gridX, gridY, gridZ
end

function RedTape.getGrassTypes()
    local result = { FruitType.GRASS, FruitType.MEADOW }

    if FruitType.ALFALFA ~= nil then
        table.insert(result, FruitType.ALFALFA)
    end
    if FruitType.CLOVER ~= nil then
        table.insert(result, FruitType.CLOVER)
    end
    return result
end

function RedTape:onStartMission()
    MissionManager.getIsMissionWorkAllowed = Utils.overwrittenFunction(MissionManager.getIsMissionWorkAllowed,
        RTMissionManagerExtension.getIsMissionWorkAllowed)
    Farm.changeBalance = Utils.appendedFunction(Farm.changeBalance, RTFarmExtension.changeBalance)
    local rt = g_currentMission.RedTape
    rt.missionStarted = true
    local ig = rt.InfoGatherer
    local farmGatherer = ig.gatherers[INFO_KEYS.FARMS]

    if g_currentMission:getIsServer() then
        -- Initialize RedTape on new game
        if not rt.didLoadFromXML then
            rt.monthStarted = RedTape.getCumulativeMonth()
            local husbandries = g_currentMission.husbandrySystem.placeables
            for _, husbandry in pairs(husbandries) do
                farmGatherer:addProductivityException(husbandry, 24)
            end

            -- Set all settings to their defaults
            for _, id in pairs(RedTape.menuItems) do
                if RedTape.SETTINGS[id] then
                    local defaultValue = RedTape.SETTINGS[id].values[RedTape.SETTINGS[id].default]
                    g_currentMission.RedTape.settings[id] = defaultValue
                end
            end

            rt:periodChanged()
        end
    end
end

function RedTape:playerFarmChanged()
    g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
end

FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState,
    RedTape.sendInitialClientState)
FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, RedTape.saveToXmlFile)
FSBaseMission.onStartMission = Utils.prependedFunction(FSBaseMission.onStartMission, RedTape.onStartMission)

addModEventListener(RedTape)
