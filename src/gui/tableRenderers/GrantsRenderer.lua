RTGrantsRenderer = {}
RTGrantsRenderer_mt = Class(RTGrantsRenderer)

function RTGrantsRenderer.new(section)
    local self = {}
    setmetatable(self, RTGrantsRenderer_mt)
    self.data = {
        pending = {},
        approved = {},
        historical = {}
    }
    self.selectedRow = -1
    self.indexChangedCallback = nil
    self.currentSection = section or "pending" -- pending, approved, historical
    return self
end

function RTGrantsRenderer:setData(data)
    self.data = data or {
        pending = {},
        approved = {},
        historical = {}
    }
end

function RTGrantsRenderer:setCurrentSection(section)
    self.currentSection = section
    self.selectedRow = -1
end

function RTGrantsRenderer:getNumberOfSections()
    return 1
end

function RTGrantsRenderer:getNumberOfItemsInSection(list, section)
    local sectionData = self.data[self.currentSection]
    if sectionData == nil then
        return 0
    end
    return #sectionData
end

function RTGrantsRenderer:getBuildingName(grant)
    local xmlFile = type(grant.xmlFile) == "string" and grant.xmlFile or nil
    local storeItem = nil
    if xmlFile ~= nil and xmlFile ~= "" then
        storeItem = g_storeManager:getItemByXMLFilename(xmlFile)
    end

    if storeItem ~= nil and storeItem.name ~= nil then
        return storeItem.name
    end

    -- The store item is gone (mod removed or updated, map placeable, ...). Fall back to the
    -- file name so the row still tells the player which building the grant was for.
    local fileName = xmlFile ~= nil and xmlFile:match("([^/\\]+)%.xml$") or nil
    if fileName ~= nil then
        return fileName
    end

    return g_i18n:getText("rt_grant_unknown_building")
end

-- Numbers are coerced so a malformed saved or streamed value can never break the list
local function toNumber(value)
    return tonumber(value) or 0
end

local function toMonth(cumulativeMonth)
    local month = math.floor(toNumber(cumulativeMonth)) % 12
    if month == 0 then month = 12 end
    return month
end

local function setCellText(cell, name, text)
    local element = cell:getAttribute(name)
    if element ~= nil then
        element:setText(text or "")
    end
end

function RTGrantsRenderer:populateCellForItemInSection(list, section, index, cell)
    local sectionData = self.data[self.currentSection]
    local grant = sectionData ~= nil and sectionData[index] or nil
    if not grant then
        return
    end

    setCellText(cell, "building", self:getBuildingName(grant))

    setCellText(cell, "price", g_i18n:formatMoney(toNumber(grant.price), 0, true, true))

    if self.currentSection == "pending" then
        setCellText(cell, "applied", RedTape.monthToString(toMonth(grant.applicationMonth)))
        setCellText(cell, "assessment", RedTape.monthToString(toMonth(grant.assessmentMonth)))
    elseif self.currentSection == "approved" then
        setCellText(cell, "amount", g_i18n:formatMoney(toNumber(grant.amount), 0, true, true))
        setCellText(cell, "approved", RedTape.monthToString(toMonth(grant.assessmentMonth)))
    elseif self.currentSection == "historical" then
        setCellText(cell, "amount", g_i18n:formatMoney(toNumber(grant.amount), 0, true, true))

        local statusText = ""
        if grant.status == RTGrantSystem.STATUS.COMPLETE then
            statusText = g_i18n:getText("rt_grant_status_completed")
        elseif grant.status == RTGrantSystem.STATUS.REJECTED then
            statusText = g_i18n:getText("rt_grant_status_rejected")
        end
        setCellText(cell, "status", statusText)
    end
end

function RTGrantsRenderer:onListSelectionChanged(list, section, index)
    self.selectedRow = index
    if self.indexChangedCallback ~= nil then
        self.indexChangedCallback(index)
    end
end
