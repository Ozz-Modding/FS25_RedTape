RTInfoGatherer = {}
RTInfoGatherer_mt = Class(RTInfoGatherer)

RTInfoGatherer.RETENTION_YEARS = 5

INFO_KEYS = {
    FARMLANDS = "farmlands",
    FARMS = "farms",
    WASTE = "waste",
}

function RTInfoGatherer.new()
    local self = {}
    setmetatable(self, RTInfoGatherer_mt)

    self.gatherers = {
        [INFO_KEYS.FARMLANDS] = FarmlandGatherer.new(),
        [INFO_KEYS.FARMS] = FarmGatherer.new(),
        [INFO_KEYS.WASTE] = WasteGatherer.new(),
    }

    return self
end

function RTInfoGatherer:loadFromXMLFile(xmlFile)
    if not g_currentMission:getIsServer() then return end

    local key = RedTape.SaveKey .. ".infoGatherer"

    for infoKey, gatherer in pairs(self.gatherers) do
        local gathererKey = key .. ".gatherers"
        if gatherer.loadFromXMLFile ~= nil then
            gatherer:loadFromXMLFile(xmlFile, gathererKey)
        end
    end
end

function RTInfoGatherer:saveToXmlFile(xmlFile)
    if (not g_currentMission:getIsServer()) then return end

    local key = RedTape.SaveKey .. ".infoGatherer"

    for _, gatherer in self.gatherers do
        gatherer:saveToXmlFile(xmlFile, key .. ".gatherers")
    end
end

function RTInfoGatherer:runConstantChecks()
    self.gatherers[INFO_KEYS.FARMS]:checkSprayers()
end

function RTInfoGatherer:runInfrequentChecks()
    -- Server only. Harvest history is authoritative on the server and reaches clients via
    -- the initial client state and RTHarvestHistoryUpdateEvent. Letting clients run this
    -- made every joining player re-report any field still sitting in stubble as a fresh
    -- harvest, which showed up as a bogus monoculture in the crop rotation policy.
    if not g_currentMission:getIsServer() then return end

    self.gatherers[INFO_KEYS.FARMLANDS]:checkHarvestedState()
end

function RTInfoGatherer:hourChanged()
    for _, gatherer in pairs(self.gatherers) do
        gatherer:hourChanged()
    end
end

function RTInfoGatherer:periodChanged()
    for _, gatherer in pairs(self.gatherers) do
        gatherer:periodChanged()
    end
end

function RTInfoGatherer:resetMonthlyData()
    for _, gatherer in pairs(self.gatherers) do
        gatherer:resetMonthlyData()
    end
end

-- Reset bi annual stats for all gatherers in june and december, after an evalautions
function RTInfoGatherer:resetBiAnnualData()
    for _, gatherer in pairs(self.gatherers) do
        if gatherer.resetBiAnnualData ~= nil then
            gatherer:resetBiAnnualData()
        end
    end
end

function RTInfoGatherer:writeInitialClientState(streamId, connection)
    for _, gatherer in pairs(self.gatherers) do
        if gatherer.writeInitialClientState ~= nil then
            gatherer:writeInitialClientState(streamId, connection)
        end
    end
end

function RTInfoGatherer:readInitialClientState(streamId, connection)
    for _, gatherer in pairs(self.gatherers) do
        if gatherer.readInitialClientState ~= nil then
            gatherer:readInitialClientState(streamId, connection)
        end
    end
end
