RTSchemeSystem = {}
RTSchemeSystem_mt = Class(RTSchemeSystem)

RTSchemeSystem.OPEN_SCHEMES_PER_TIER = 10

table.insert(FinanceStats.statNames, "schemePayout")
FinanceStats.statNameToIndex["schemePayout"] = #FinanceStats.statNames

function RTSchemeSystem.new()
    local self = {}
    setmetatable(self, RTSchemeSystem_mt)
    self.availableSchemes = {
        [RTPolicySystem.TIER.A] = {},
        [RTPolicySystem.TIER.B] = {},
        [RTPolicySystem.TIER.C] = {},
        [RTPolicySystem.TIER.D] = {}
    }
    self.activeSchemesByFarm = {}

    MoneyType.SCHEME_PAYOUT = MoneyType.register("schemePayout", "rt_ui_schemePayout")
    MoneyType.LAST_ID = MoneyType.LAST_ID + 1

    return self
end

function RTSchemeSystem:loadFromXMLFile(xmlFile)
    if (not g_currentMission:getIsServer()) then return end

    local key = RedTape.SaveKey .. ".schemeSystem"

    local i = 0
    while true do
        local schemeKey = string.format(key .. ".schemes.scheme(%d)", i)
        if not hasXMLProperty(xmlFile, schemeKey) then
            break
        end

        local scheme = RTScheme.new()
        scheme:loadFromXMLFile(xmlFile, schemeKey)
        local tier = getXMLInt(xmlFile, schemeKey .. "#tier")
        if self.availableSchemes[tier] == nil then
            self.availableSchemes[tier] = {}
        end
        table.insert(self.availableSchemes[tier], scheme)
        i = i + 1
    end

    local j = 0
    while true do
        local schemeKey = string.format(key .. ".activeSchemes.scheme(%d)", j)
        if not hasXMLProperty(xmlFile, schemeKey) then
            break
        end

        local scheme = RTScheme.new()
        scheme:loadFromXMLFile(xmlFile, schemeKey)
        local farmId = scheme.farmId
        if self.activeSchemesByFarm[farmId] == nil then
            self.activeSchemesByFarm[farmId] = {}
        end
        table.insert(self.activeSchemesByFarm[farmId], scheme)
        j = j + 1
    end
end

function RTSchemeSystem:saveToXmlFile(xmlFile)
    if (not g_currentMission:getIsServer()) then return end
    if (not self:isEnabled()) then return end

    local key = RedTape.SaveKey .. ".schemeSystem"

    local i = 0
    for tier, schemes in pairs(self.availableSchemes) do
        for _, scheme in pairs(schemes) do
            local schemeKey = string.format("%s.schemes.scheme(%d)", key, i)
            scheme:saveToXmlFile(xmlFile, schemeKey)
            setXMLInt(xmlFile, schemeKey .. "#tier", tier)
            i = i + 1
        end
    end

    local j = 0
    for _, schemes in pairs(self.activeSchemesByFarm) do
        for _, scheme in pairs(schemes) do
            local schemeKey = string.format("%s.activeSchemes.scheme(%d)", key, j)
            scheme:saveToXmlFile(xmlFile, schemeKey)
            j = j + 1
        end
    end
end

function RTSchemeSystem:isEnabled()
    return g_currentMission.RedTape.settings.policiesAndSchemesEnabled
end

function RTSchemeSystem:writeInitialClientState(streamId, connection)
    streamWriteInt32(streamId, RedTape.tableCount(self.availableSchemes))
    for tier, schemes in pairs(self.availableSchemes) do
        streamWriteInt32(streamId, tier)
        streamWriteInt32(streamId, RedTape.tableCount(schemes))
        for _, scheme in pairs(schemes) do
            scheme:writeStream(streamId, connection)
        end
    end

    streamWriteInt32(streamId, RedTape.tableCount(self.activeSchemesByFarm))
    for farmId, schemes in pairs(self.activeSchemesByFarm) do
        streamWriteInt32(streamId, farmId)
        streamWriteInt32(streamId, RedTape.tableCount(schemes))
        for _, scheme in pairs(schemes) do
            scheme:writeStream(streamId, connection)
        end
    end
end

function RTSchemeSystem:readInitialClientState(streamId, connection)
    local tierCount = streamReadInt32(streamId)
    for i = 1, tierCount do
        local readTier = streamReadInt32(streamId)
        local schemeCount = streamReadInt32(streamId)
        self.availableSchemes[readTier] = self.availableSchemes[readTier] or {}
        for i = 1, schemeCount do
            local scheme = RTScheme.new()
            scheme:readStream(streamId, connection)
            table.insert(self.availableSchemes[readTier], scheme)
        end
    end

    local farmCount = streamReadInt32(streamId)
    for i = 1, farmCount do
        local farmId = streamReadInt32(streamId)
        local schemeCount = streamReadInt32(streamId)
        local activeSchemes = self:getActiveSchemesForFarm(farmId)
        for j = 1, schemeCount do
            local scheme = RTScheme.new()
            scheme:readStream(streamId, connection)
            table.insert(activeSchemes, scheme)
        end
    end
end

function RTSchemeSystem:hourChanged()
end

function RTSchemeSystem:periodChanged()
    if (not self:isEnabled()) then return end
    local schemeSystem = g_currentMission.RedTape.SchemeSystem

    for farm, schemes in pairs(schemeSystem.activeSchemesByFarm) do
        for _, scheme in pairs(schemes) do
            local ok, err = pcall(scheme.evaluate, scheme)
            if not ok then
                local schemeInfo = RTSchemes[scheme.schemeIndex]
                local schemeName = schemeInfo and schemeInfo.name or ("index=" .. tostring(scheme.schemeIndex))
                print("RedTape Error: scheme evaluate failed for '" .. schemeName .. "' (id=" .. tostring(scheme.id) .. ", farm=" .. tostring(farm) .. "): " .. tostring(err))
            end
        end
    end

    local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
    local cumulativeMonth = RedTape.getCumulativeMonth()
    local expired = {}
    for tier, schemes in pairs(self.availableSchemes) do
        for _, scheme in pairs(schemes) do
            local schemeInfo = RTSchemes[scheme.schemeIndex]
            if schemeInfo.offerMonths ~= nil and not RedTape.tableHasValue(schemeInfo.offerMonths, currentMonth) then
                table.insert(expired, scheme)
            elseif schemeInfo.getExpiryMonth ~= nil then
                local expiryMonth = schemeInfo.getExpiryMonth(schemeInfo, scheme)
                if expiryMonth ~= nil and expiryMonth <= cumulativeMonth then
                    table.insert(expired, scheme)
                end
            end
        end
    end

    for _, scheme in pairs(expired) do
        g_client:getServerConnection():sendEvent(RTSchemeNoLongerAvailableEvent.new(scheme.id))
    end

    schemeSystem:generateSchemes()
end

function RTSchemeSystem:checkPendingVehicles()
    for farm, schemes in pairs(self.activeSchemesByFarm) do
        for _, scheme in pairs(schemes) do
            scheme:checkPendingVehicles()
        end
    end
end

function RTSchemeSystem:generateSchemes()
    if (not self:isEnabled()) then return end
    for tier, schemes in pairs(self.availableSchemes) do
        local existingCount = RedTape.tableCount(schemes)
        if existingCount < RTSchemeSystem.OPEN_SCHEMES_PER_TIER then
            local toCreate = RTSchemeSystem.OPEN_SCHEMES_PER_TIER - existingCount
            for i = 1, toCreate do
                local scheme = RTScheme.new()
                scheme.tier = tier
                local nextIndex = self:getNextSchemeIndex(tier)

                if nextIndex == nil then
                    break
                end

                scheme.schemeIndex = nextIndex
                scheme:initialise()
                g_client:getServerConnection():sendEvent(RTSchemeActivatedEvent.new(scheme))
            end
        end
    end
end

function RTSchemeSystem:getNextSchemeIndex(tier)
    local rt = g_currentMission.RedTape
    local currentMonth = rt.periodToMonth(g_currentMission.environment.currentPeriod)
    local currentSchemeDupeKeys = {}
    for _, scheme in pairs(self.availableSchemes[tier]) do
        table.insert(currentSchemeDupeKeys, RTSchemes[scheme.schemeIndex].duplicationKey)
    end

    local availableSchemes = {}
    for _, schemeInfo in pairs(RTSchemes) do
        if rt.tableHasKey(schemeInfo.tiers, tier) and not rt.tableHasValue(currentSchemeDupeKeys, schemeInfo.duplicationKey) then
            if schemeInfo.offerMonths == nil or rt.tableHasValue(schemeInfo.offerMonths, currentMonth) then
                local availabilityProbability = schemeInfo.availabilityProbability or 1
                if math.random() <= availabilityProbability then
                    table.insert(availableSchemes, schemeInfo)
                end
            end
        end
    end

    local totalProbability = 0
    for _, scheme in pairs(availableSchemes) do
        totalProbability = totalProbability + scheme.selectionProbability
    end

    if totalProbability == 0 then
        return nil -- No available schemes to choose from
    end

    local randomValue = math.random() * totalProbability
    local cumulativeProbability = 0
    for _, scheme in pairs(availableSchemes) do
        cumulativeProbability = cumulativeProbability + scheme.selectionProbability
        if randomValue <= cumulativeProbability then
            return scheme.id
        end
    end

    return nil
end

-- Called by PolicyActivatedEvent, runs on Client and Server
function RTSchemeSystem:registerActivatedScheme(scheme)
    table.insert(self.availableSchemes[scheme.tier], scheme)
    local available = scheme:availableForCurrentFarm()

    local tierName = RTPolicySystem.TIER_NAMES[scheme.tier]
    g_currentMission.RedTape.EventLog:addEvent(nil, RTEventLogItem.EVENT_TYPE.SCHEME_ACTIVATED,
        string.format(g_i18n:getText("rt_notify_active_scheme"), scheme:getName(), tierName), available)
    g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
end

-- Called by SchemeSelectedEvent, runs on Server only
function RTSchemeSystem:registerSelectedScheme(scheme, farmId)
    if (not g_currentMission:getIsServer()) then return end
    if farmId == nil or farmId == 0 then
        return nil
    end

    local activeSchemes = self:getActiveSchemesForFarm(farmId)
    local schemeForFarm = scheme:createFarmScheme(farmId)
    table.insert(activeSchemes, schemeForFarm)
    schemeForFarm:selected()
    g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
end

function RTSchemeSystem:storeSelectedSchemeOnClient(scheme)
    if (g_currentMission:getIsServer()) then return end
    local activeSchemes = self:getActiveSchemesForFarm(scheme.farmId)
    table.insert(activeSchemes, scheme)
    g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
end

-- Called by SchemeNoLongerAvailableEvent, runs on Client and Server
function RTSchemeSystem:removeAvailableScheme(id)
    for tier, schemes in pairs(self.availableSchemes) do
        for i, scheme in pairs(schemes) do
            if scheme.id == id then
                table.remove(schemes, i)
                g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
                local tierName = RTPolicySystem.TIER_NAMES[scheme.tier]
                g_currentMission.RedTape.EventLog:addEvent(nil, RTEventLogItem.EVENT_TYPE.SCHEME_EXPIRED,
                    string.format(g_i18n:getText("rt_notify_expired_scheme"), scheme:getName(), tierName),
                    scheme:availableForCurrentFarm())
                return
            end
        end
    end
end

-- Called by RTSchemeEndedEvent, runs on Client and Server
function RTSchemeSystem:endActiveScheme(id, farmId)
    local currentFarmId = g_currentMission:getFarmId()
    for i, scheme in pairs(self.activeSchemesByFarm[farmId]) do
        if scheme.id == id then
            scheme:endScheme()
            table.remove(self.activeSchemesByFarm[farmId], i)
            g_currentMission.RedTape.EventLog:addEvent(nil, RTEventLogItem.EVENT_TYPE.SCHEME_ACTIVATED,
                string.format(g_i18n:getText("rt_notify_ended_scheme"), scheme:getName()), farmId == currentFarmId)
            return
        end
    end
end

function RTSchemeSystem:isSchemeActiveForFarm(farmId, schemeIndex)
    local activeSchemes = self:getActiveSchemesForFarm(farmId)
    for _, scheme in pairs(activeSchemes) do
        if scheme.schemeIndex == schemeIndex then
            return true
        end
    end
    return false
end

function RTSchemeSystem:isSchemeAvailableForTier(tier, schemeIndex)
    for _, scheme in pairs(self.availableSchemes[tier]) do
        if scheme.schemeIndex == schemeIndex then
            return true
        end
    end
    return false
end

function RTSchemeSystem:getActiveSchemesForFarm(farmId)
    if farmId == nil or farmId == 0 then
        return {}
    end

    if self.activeSchemesByFarm[farmId] == nil then
        self.activeSchemesByFarm[farmId] = {}
    end

    return self.activeSchemesByFarm[farmId]
end

function RTSchemeSystem:getAvailableSchemesForCurrentFarm()
    local availableForFarm = {}

    local farmId = g_currentMission:getFarmId()
    if farmId == nil or farmId == 0 then
        return availableForFarm
    end

    local policySystem = g_currentMission.RedTape.PolicySystem
    local farmTier = policySystem:getProgressForCurrentFarm().tier
    for _, scheme in pairs(self.availableSchemes[farmTier]) do
        if scheme:availableForCurrentFarm() then
            table.insert(availableForFarm, scheme)
        end
    end

    return availableForFarm
end

function RTSchemeSystem:getIsSchemeVehicle(farmId, vehicle)
    local activeSchemes = self:getActiveSchemesForFarm(farmId)
    for _, scheme in pairs(activeSchemes) do
        if scheme:isSchemeVehicle(vehicle) then
            return true
        end
    end
    return false
end

function RTSchemeSystem.isSpawnSpaceAvailable(storeItems)
    local usedStorePlaces = g_currentMission.usedStorePlaces
    local placesFilled = {}
    local result = true
    for _, storeItem in ipairs(storeItems) do
        local size = StoreItemUtil.getSizeValues(storeItem.xmlFilename, "vehicle", storeItem.rotation,
            storeItem.configurations)
        local x = size.width
        size.width = math.max(x, VehicleLoadingData.MIN_SPAWN_PLACE_WIDTH)
        size.length = math.max(size.length, VehicleLoadingData.MIN_SPAWN_PLACE_LENGTH)
        size.height = math.max(size.height, VehicleLoadingData.MIN_SPAWN_PLACE_HEIGHT)
        size.width = size.width + VehicleLoadingData.SPAWN_WIDTH_OFFSET
        local adjustedX, _, _, place, width, _ = PlacementUtil.getPlace(g_currentMission.storeSpawnPlaces, size,
            usedStorePlaces)
        if adjustedX == nil then
            result = false
            break
        end
        PlacementUtil.markPlaceUsed(usedStorePlaces, place, width)
        table.insert(placesFilled, place)
    end
    for _, place in ipairs(placesFilled) do
        PlacementUtil.unmarkPlaceUsed(usedStorePlaces, place)
    end
    return result
end

function RTSchemeSystem:onSnowApplied()
    if (not self:isEnabled()) then return end
    for tier, _ in pairs(self.availableSchemes) do
        if not self:isSchemeAvailableForTier(tier, RTSchemeIds.ROAD_SNOW_CLEARING) then
            local scheme = RTScheme.new()
            scheme.tier = tier
            scheme.schemeIndex = RTSchemeIds.ROAD_SNOW_CLEARING
            scheme:initialise()
            g_client:getServerConnection():sendEvent(RTSchemeActivatedEvent.new(scheme))
        end
    end
end

function RTSchemeSystem:onSnowEnded()
    if (not self:isEnabled()) then return end
    for _, schemes in pairs(self.availableSchemes) do
        for _, scheme in pairs(schemes) do
            if scheme.schemeIndex == RTSchemeIds.ROAD_SNOW_CLEARING then
                g_client:getServerConnection():sendEvent(RTSchemeNoLongerAvailableEvent.new(scheme.id))
            end
        end
    end
    for _, schemes in pairs(self.activeSchemesByFarm) do
        for _, scheme in pairs(schemes) do
            if scheme.schemeIndex == RTSchemeIds.ROAD_SNOW_CLEARING then
                scheme:snowSchemeEnded()
            end
        end
    end
end

function RTSchemeSystem:onDisabled()
    for _, schemes in pairs(self.activeSchemesByFarm) do
        for _, scheme in pairs(schemes) do
            g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
        end
    end
end
