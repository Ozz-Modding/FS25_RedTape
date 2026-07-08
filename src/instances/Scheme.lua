RTScheme = {}
RTScheme_mt = Class(RTScheme)


function RTScheme.new()
    local self = {}
    setmetatable(self, RTScheme_mt)

    self.id = RedTape.generateId()
    self.schemeIndex = -1

    -- if -1, the scheme is open for selection by farms
    self.farmId = -1
    self.tier = -1
    self.watched = false
    self.lastEvaluationReport = {}
    self.props = {}
    self.spawnedVehicles = false
    self.vehicles = {}

    self.pendingVehicleLoadingData = {} -- temp, not to be saved
    self.failedToLoadVehicles = false   -- temp, not to be saved

    return self
end

function RTScheme:checkPendingVehicles()
    if self.pendingVehicleUniqueIds ~= nil then
        for i = #self.pendingVehicleUniqueIds, 1, -1 do
            local uniqueId = self.pendingVehicleUniqueIds[i]
            local vehicle = g_currentMission.vehicleSystem:getVehicleByUniqueId(uniqueId)
            if vehicle ~= nil then
                table.remove(self.pendingVehicleUniqueIds, i)
                table.insert(self.vehicles, vehicle)
            end
        end
        if #self.pendingVehicleUniqueIds == 0 then
            self.pendingVehicleUniqueIds = nil
        end
    end
end

function RTScheme:writeStream(streamId, connection)
    streamWriteString(streamId, self.id)
    streamWriteInt32(streamId, self.schemeIndex)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.tier)
    streamWriteBool(streamId, self.watched)
    streamWriteBool(streamId, self.spawnedVehicles)

    streamWriteInt32(streamId, RedTape.tableCount(self.lastEvaluationReport))
    for _, report in pairs(self.lastEvaluationReport) do
        streamWriteString(streamId, report.cell1 or "")
        streamWriteString(streamId, report.cell2 or "")
        streamWriteString(streamId, report.cell3 or "")
    end

    streamWriteInt32(streamId, RedTape.tableCount(self.props))
    for key, value in pairs(self.props) do
        streamWriteString(streamId, key)
        if string.startsWith(key, "vehicleToSpawn") then
            streamWriteString(streamId, NetworkUtil.convertToNetworkFilename(value))
        else
            streamWriteString(streamId, value)
        end
    end
end

function RTScheme:readStream(streamId, connection)
    self.id = streamReadString(streamId)
    self.schemeIndex = streamReadInt32(streamId)
    self.farmId = streamReadInt32(streamId)
    self.tier = streamReadInt32(streamId)
    self.watched = streamReadBool(streamId)
    self.spawnedVehicles = streamReadBool(streamId)

    local reportCount = streamReadInt32(streamId)
    for i = 1, reportCount do
        local report = {
            cell1 = streamReadString(streamId),
            cell2 = streamReadString(streamId),
            cell3 = streamReadString(streamId)
        }
        table.insert(self.lastEvaluationReport, report)
    end

    local propCount = streamReadInt32(streamId)
    for i = 1, propCount do
        local key = streamReadString(streamId)
        local value = streamReadString(streamId)
        if string.startsWith(key, "vehicleToSpawn") then
            value = NetworkUtil.convertFromNetworkFilename(value)
        end
        self.props[key] = value
    end
end

function RTScheme:saveToXmlFile(xmlFile, key)
    setXMLString(xmlFile, key .. "#id", self.id)
    setXMLInt(xmlFile, key .. "#schemeIndex", self.schemeIndex)
    setXMLInt(xmlFile, key .. "#farmId", self.farmId)
    setXMLInt(xmlFile, key .. "#tier", self.tier)
    setXMLBool(xmlFile, key .. "#watched", self.watched)
    setXMLBool(xmlFile, key .. "#spawnedVehicles", self.spawnedVehicles)

    local i = 0
    for _, report in pairs(self.lastEvaluationReport) do
        local reportKey = string.format("%s.reportItems.item(%d)", key, i)
        setXMLString(xmlFile, reportKey .. "#cell1", report.cell1)
        setXMLString(xmlFile, reportKey .. "#cell2", report.cell2)
        setXMLString(xmlFile, reportKey .. "#cell3", report.cell3)
        i = i + 1
    end

    local j = 0
    for propertyKey, propertyValue in pairs(self.props) do
        local propKey = string.format("%s.propItems.item(%d)", key, j)
        setXMLString(xmlFile, propKey .. "#key", propertyKey)
        setXMLString(xmlFile, propKey .. "#value", propertyValue)
        j = j + 1
    end

    local k = 0
    for _, vehicle in pairs(self.vehicles) do
        local vehicleKey = string.format("%s.vehicles.vehicle(%d)", key, k)
        setXMLString(xmlFile, vehicleKey .. "#uniqueId", vehicle.uniqueId)
        k = k + 1
    end
end

function RTScheme:loadFromXMLFile(xmlFile, key)
    self.id = getXMLString(xmlFile, key .. "#id") or RedTape.generateId()
    self.schemeIndex = getXMLInt(xmlFile, key .. "#schemeIndex")
    self.farmId = getXMLInt(xmlFile, key .. "#farmId")
    self.tier = getXMLInt(xmlFile, key .. "#tier")
    self.watched = getXMLBool(xmlFile, key .. "#watched") or false
    self.spawnedVehicles = getXMLBool(xmlFile, key .. "#spawnedVehicles") or false

    if self.spawnedVehicles then
        g_messageCenter:subscribe(MessageType.VEHICLE_RESET, self.onVehicleReset, self)
    end

    local i = 0
    while true do
        local reportKey = string.format("%s.reportItems.item(%d)", key, i)
        if not hasXMLProperty(xmlFile, reportKey) then
            break
        end
        local report = {
            cell1 = getXMLString(xmlFile, reportKey .. "#cell1"),
            cell2 = getXMLString(xmlFile, reportKey .. "#cell2"),
            cell3 = getXMLString(xmlFile, reportKey .. "#cell3")
        }
        table.insert(self.lastEvaluationReport, report)
        i = i + 1
    end

    local j = 0
    while true do
        local propKey = string.format("%s.propItems.item(%d)", key, j)
        if not hasXMLProperty(xmlFile, propKey) then
            break
        end
        local propKeyName = getXMLString(xmlFile, propKey .. "#key")
        local propValue = getXMLString(xmlFile, propKey .. "#value")

        if propKeyName == "fruitType" and tonumber(propValue) ~= nil then
            local fruit = g_fruitTypeManager:getFruitTypeByIndex(tonumber(propValue))
            if fruit ~= nil then
                propValue = fruit.name
            end
        end

        self.props[propKeyName] = propValue
        j = j + 1
    end

    self.pendingVehicleUniqueIds = {}
    local k = 0
    while true do
        local vehicleKey = string.format("%s.vehicles.vehicle(%d)", key, k)
        if not hasXMLProperty(xmlFile, vehicleKey) then
            break
        end
        local vehicleUniqueId = getXMLString(xmlFile, vehicleKey .. "#uniqueId")
        table.insert(self.pendingVehicleUniqueIds, vehicleUniqueId)
        k = k + 1
    end
end

-- Called by the SchemeSystem when generating schemes
function RTScheme:initialise()
    local schemeInfo = RTSchemes[self.schemeIndex]
    schemeInfo.initialise(schemeInfo, self)
end

function RTScheme:setProp(key, value)
    self.props[key] = tostring(value)
end

function RTScheme:getName()
    if self.schemeIndex == -1 then
        return nil
    end

    local schemeInfo = RTSchemes[self.schemeIndex]

    return g_i18n:getText(schemeInfo.name)
end

function RTScheme:getDescription()
    if self.schemeIndex == -1 then
        return nil
    end

    local schemeInfo = RTSchemes[self.schemeIndex]

    if schemeInfo.descriptionFunction ~= nil then
        return schemeInfo.descriptionFunction(schemeInfo, self)
    end

    return g_i18n:getText(schemeInfo.description)
end

function RTScheme:getReportDescription()
    if self.schemeIndex == -1 then
        return nil
    end

    local schemeInfo = RTSchemes[self.schemeIndex]

    return g_i18n:getText(schemeInfo.report_description)
end

function RTScheme:getNextEvaluationMonth()
    local schemeInfo = RTSchemes[self.schemeIndex]
    if schemeInfo.getNextEvaluationMonth ~= nil then
        return schemeInfo.getNextEvaluationMonth(schemeInfo, self)
    end
    local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
    local nextMonth = currentMonth + 1
    if nextMonth > 12 then
        nextMonth = 1
    end
    return nextMonth
end

function RTScheme:availableForCurrentFarm()
    local schemeSystem = g_currentMission.RedTape.SchemeSystem
    local policySystem = g_currentMission.RedTape.PolicySystem
    local farmId = g_currentMission:getFarmId()

    if farmId == nil or farmId == 0 then
        return false
    end

    local farmTier = policySystem:getProgressForCurrentFarm().tier
    local schemeInfo = RTSchemes[self.schemeIndex]

    if self.tier ~= farmTier then
        return false
    end

    -- Check if the scheme conflicts with another active scheme
    local activeSchemes = schemeSystem:getActiveSchemesForFarm(farmId)
    for _, scheme in pairs(activeSchemes) do
        local activeSchemeInfo = RTSchemes[scheme.schemeIndex]
        if activeSchemeInfo.duplicationKey == schemeInfo.duplicationKey then
            return false
        end
    end

    return true
end

function RTScheme:evaluate()
    local schemeInfo = RTSchemes[self.schemeIndex]
    local report = schemeInfo.evaluate(schemeInfo, self, self.tier)

    if report ~= nil then
        report = report or {}

        -- Ensure all report values are strings
        for _, reportLine in pairs(report) do
            reportLine.cell1 = tostring(reportLine.cell1 or "")
            reportLine.cell2 = tostring(reportLine.cell2 or "")
            reportLine.cell3 = tostring(reportLine.cell3 or "")
        end

        g_client:getServerConnection():sendEvent(RTSchemeReportEvent.new(self.id, self.farmId, report))
    end
end

function  RTScheme:snowSchemeEnded()
    if self.schemeIndex ~= RTSchemeIds.ROAD_SNOW_CLEARING then
        return
    end

    local schemeInfo = RTSchemes[self.schemeIndex]
    schemeInfo.onSnowEnded(schemeInfo, self, self.tier)
end

-- Called by SchemeSelectedEvent, runs on client and server
-- Creates a new farm specific scheme from
function RTScheme:createFarmScheme(farmId)
    local policySystem = g_currentMission.RedTape.PolicySystem
    local farmScheme = RTScheme.new()
    farmScheme.schemeIndex = self.schemeIndex
    farmScheme.farmId = farmId
    farmScheme.tier = policySystem:getProgressForFarm(farmId).tier

    for key, value in pairs(self.props) do
        farmScheme.props[key] = value
    end
    return farmScheme
end

-- Called by SchemeSelectedEvent, runs on server only
function RTScheme:selected()
    if not g_currentMission:getIsServer() then
        return
    end

    local schemeInfo = RTSchemes[self.schemeIndex]
    schemeInfo.selected(schemeInfo, self, self.tier)
    g_client:getServerConnection():sendEvent(RTSchemePostSelectionEvent.new(self))
end

-- Get a list of vehicles to spawn.
function RTScheme:getVehiclesToSpawn()
    local vehicles = {}

    local vehicleSpawnIndex = 1
    while true do
        local vehicleKey = 'vehicleToSpawn' .. vehicleSpawnIndex
        if self.props[vehicleKey] == nil then
            break
        end
        local storeItem = g_storeManager:getItemByXMLFilename(self.props[vehicleKey])
        table.insert(vehicles, storeItem)
        vehicleSpawnIndex = vehicleSpawnIndex + 1
    end

    return vehicles
end

function RTScheme:spawnVehicles()
    if not g_currentMission:getIsServer() then
        return
    end

    local storeItems = self:getVehiclesToSpawn()

    for _, storeItem in pairs(storeItems) do
        local data = VehicleLoadingData.new()
        data:setFilename(storeItem.xmlFilename)
        if data.isValid then
            local vehicleConfig = self:getVehicleConfiguration(storeItem)
            data:setConfigurations(vehicleConfig)
            data:setLoadingPlace(g_currentMission.storeSpawnPlaces, g_currentMission.usedStorePlaces)
            data:setPropertyState(VehiclePropertyState.MISSION)
            data:setOwnerFarmId(self.farmId)
            table.insert(self.pendingVehicleLoadingData, data)
            data:load(self.onSpawnedVehicle, self, {
                ["loadingData"] = data,
                ["vehicleInfo"] = storeItem
            })
        end
    end

    self.spawnedVehicles = #storeItems > 0
    g_messageCenter:subscribe(MessageType.VEHICLE_RESET, self.onVehicleReset, self)
end

function RTScheme:getVehicleConfiguration(storeItem)
    local result = {}
    StoreItemUtil.loadSpecsFromXML(storeItem)

    if storeItem.defaultConfigurationIds ~= nil then
        for k, v in pairs(storeItem.defaultConfigurationIds) do
            result[k] = v
        end
    end

    if storeItem.configurations ~= nil and storeItem.configurationSets ~= nil then
        if RedTape.tableCount(storeItem.configurationSets) > 0 then
            local chosenSet = math.random(1, #storeItem.configurationSets)
            for k, v in pairs(storeItem.configurationSets[chosenSet]) do
                result[k] = v
            end
        end
    end

    return result
end

function RTScheme:onSpawnedVehicle(vehicles, vehicleLoadState, loadingInfo)
    table.removeElement(self.pendingVehicleLoadingData, loadingInfo.loadingData)
    if self.failedToLoadVehicles then
        for _, vehicle in pairs(vehicles) do
            vehicle:delete()
        end
        return
    elseif vehicleLoadState == VehicleLoadingState.OK then
        for _, vehicle in pairs(vehicles) do
            vehicle:addWearAmount(math.random() * 0.10 + 0.05)
            vehicle:setOperatingTime(3600000 * (math.random() * 7 + 5))
            table.insert(self.vehicles, vehicle)
        end
    else
        self.failedToLoadVehicles = true
        for _, vehicle in pairs(vehicles) do
            vehicle:delete()
        end
        for _, loadingData in pairs(self.pendingVehicleLoadingData) do
            loadingData:cancelLoading()
        end
        table.clear(self.pendingVehicleLoadingData)
        table.clear(self.vehiclesToLoad)
        self.spawnedVehicles = false
        for _, vehicle in pairs(self.vehicles) do
            vehicle:delete()
        end
        table.clear(self.vehicles)
    end
end

function RTScheme:onVehicleReset(oldVehicle, newVehicle)
    if g_currentMission:getIsServer() and table.removeElement(self.vehicles, oldVehicle) then
        table.addElement(self.vehicles, newVehicle)
    end
end

function RTScheme:removeVehicles()
    if g_currentMission:getIsServer() then
        for _, vehicle in pairs(self.vehicles) do
            if not vehicle:getIsBeingDeleted() then
                pcall(function()
                    if vehicle.spec_fillUnit ~= nil then
                        vehicle.spec_fillUnit:unloadFillUnits(true)
                    end
                end)
                vehicle:delete()
            end
        end
        self.vehicles = {}
    end
end

-- Must be called when the scheme ends
function RTScheme:endScheme()
    if g_currentMission:getIsServer() then
        self:removeVehicles()
        g_messageCenter:unsubscribeAll(self)
    end
end

function RTScheme:isSchemeVehicle(vehicle)
    for _, v in pairs(self.vehicles) do
        if v == vehicle then
            return true
        end
    end
    return false
end

function RTScheme.expireMatchingAvailableScheme(activeScheme)
    local schemeSystem = g_currentMission.RedTape.SchemeSystem
    local toRemove = {}
    for _, schemes in pairs(schemeSystem.availableSchemes) do
        for _, available in pairs(schemes) do
            if available.schemeIndex == activeScheme.schemeIndex then
                table.insert(toRemove, available.id)
            end
        end
    end
    for _, id in ipairs(toRemove) do
        schemeSystem:removeAvailableScheme(id)
    end
end
