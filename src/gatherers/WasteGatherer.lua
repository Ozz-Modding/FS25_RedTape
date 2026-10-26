-- Waste disposals reported by other mods through RedTapeAPI.recordWasteDisposal (server only).
-- Litres per farm, waste type and disposal method for the current month, judged by the Waste
-- Disposal policy at month end and then cleared.
WasteGatherer = {}
WasteGatherer_mt = Class(WasteGatherer)

function WasteGatherer.new()
    local self = {}
    setmetatable(self, WasteGatherer_mt)

    -- farmId -> wasteType -> method -> litres this month
    self.data = {}

    return self
end

function WasteGatherer:hourChanged()
end

function WasteGatherer:periodChanged()
end

function WasteGatherer:resetMonthlyData()
    self.data = {}
end

function WasteGatherer:addDisposal(farmId, wasteType, liters, method)
    local farmData = self:getFarmData(farmId)
    farmData[wasteType][method] = farmData[wasteType][method] + liters
end

--- This month's litres for a farm, every waste type and method present (0 when none)
function WasteGatherer:getFarmData(farmId)
    if self.data[farmId] == nil then
        local farmData = {}
        for _, wasteType in ipairs(RedTapeAPI.WASTE_TYPES) do
            farmData[wasteType] = {}
            for _, method in ipairs(RedTapeAPI.DISPOSAL_METHODS) do
                farmData[wasteType][method] = 0
            end
        end
        self.data[farmId] = farmData
    end
    return self.data[farmId]
end

--- Litres this month by one method, all waste types together
function WasteGatherer:getMethodTotal(farmId, method)
    local total = 0
    for _, wasteType in ipairs(RedTapeAPI.WASTE_TYPES) do
        total = total + self:getFarmData(farmId)[wasteType][method]
    end
    return total
end

function WasteGatherer:saveToXmlFile(xmlFile, key)
    local wasteKey = string.format("%s.wasteGatherer", key)

    local i = 0
    for farmId, farmData in pairs(self.data) do
        for wasteType, methods in pairs(farmData) do
            for method, liters in pairs(methods) do
                if liters > 0 then
                    local entryKey = string.format("%s.disposal(%d)", wasteKey, i)
                    setXMLInt(xmlFile, entryKey .. "#farmId", farmId)
                    setXMLString(xmlFile, entryKey .. "#wasteType", wasteType)
                    setXMLString(xmlFile, entryKey .. "#method", method)
                    setXMLFloat(xmlFile, entryKey .. "#liters", liters)
                    i = i + 1
                end
            end
        end
    end
end

function WasteGatherer:loadFromXMLFile(xmlFile, key)
    local wasteKey = string.format("%s.wasteGatherer", key)
    self.data = {}

    local i = 0
    while true do
        local entryKey = string.format("%s.disposal(%d)", wasteKey, i)
        if not hasXMLProperty(xmlFile, entryKey) then
            break
        end

        local farmId = getXMLInt(xmlFile, entryKey .. "#farmId")
        local wasteType = getXMLString(xmlFile, entryKey .. "#wasteType")
        local method = getXMLString(xmlFile, entryKey .. "#method")
        local liters = getXMLFloat(xmlFile, entryKey .. "#liters")

        -- An entry from an edited savegame, or for a type or method this version doesn't know, is dropped
        if RedTapeAPI.checkWasteArguments(farmId, wasteType, liters, method) == nil then
            self:addDisposal(farmId, wasteType, liters, method)
        else
            RedTape.logWarning(string.format("WasteGatherer: dropping saved disposal %d (%s, %s, %s, %s)", i,
                tostring(farmId), tostring(wasteType), tostring(method), tostring(liters)))
        end

        i = i + 1
    end
end
