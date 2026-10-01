RTPolicy = {}
RTPolicy_mt = Class(RTPolicy)

function RTPolicy.new()
    local self = {}
    setmetatable(self, RTPolicy_mt)

    self.id = RedTape.generateId()
    self.policyIndex = -1
    self.nextEvaluationMonth = -1
    self.evaluationCount = 0
    self.evaluationReports = {}
    self.watchingFarms = {}

    return self
end

function RTPolicy:writeStream(streamId, connection)
    streamWriteString(streamId, self.id)
    streamWriteInt32(streamId, self.policyIndex)
    streamWriteInt32(streamId, self.nextEvaluationMonth)
    streamWriteInt32(streamId, self.evaluationCount)

    streamWriteInt32(streamId, RedTape.tableCount(self.evaluationReports))
    for farmId, reportLines in pairs(self.evaluationReports) do
        streamWriteInt32(streamId, farmId)
        streamWriteInt32(streamId, RedTape.tableCount(reportLines))
        for _, line in pairs(reportLines) do
            streamWriteString(streamId, line.cell1 or "")
            streamWriteString(streamId, line.cell2 or "")
            streamWriteString(streamId, line.cell3 or "")
        end
    end

    streamWriteInt32(streamId, RedTape.tableCount(self.watchingFarms))
    for farmId, _ in pairs(self.watchingFarms) do
        streamWriteInt32(streamId, farmId)
    end
end

function RTPolicy:readStream(streamId, connection)
    self.id = streamReadString(streamId)
    self.policyIndex = streamReadInt32(streamId)
    self.nextEvaluationMonth = streamReadInt32(streamId)
    self.evaluationCount = streamReadInt32(streamId)

    local reportCount = streamReadInt32(streamId)
    self.evaluationReports = {}
    for i = 1, reportCount do
        local farmId = streamReadInt32(streamId)
        local lineCount = streamReadInt32(streamId)
        local reportLines = {}
        for j = 1, lineCount do
            local line = {
                cell1 = streamReadString(streamId),
                cell2 = streamReadString(streamId),
                cell3 = streamReadString(streamId)
            }
            table.insert(reportLines, line)
        end
        self.evaluationReports[farmId] = reportLines
    end

    local watchingCount = streamReadInt32(streamId)
    self.watchingFarms = {}
    for i = 1, watchingCount do
        local farmId = streamReadInt32(streamId)
        self.watchingFarms[farmId] = true
    end
end

function RTPolicy:saveToXmlFile(xmlFile, key)
    setXMLString(xmlFile, key .. "#id", self.id)
    setXMLInt(xmlFile, key .. "#policyIndex", self.policyIndex)
    setXMLInt(xmlFile, key .. "#nextEvaluationMonth", self.nextEvaluationMonth)
    setXMLInt(xmlFile, key .. "#evaluationCount", self.evaluationCount)

    local i = 0
    for farmId, reportLines in pairs(self.evaluationReports) do
        local reportKey = string.format("%s.evaluationReports.item(%d)", key, i)
        setXMLInt(xmlFile, reportKey .. "#farmId", farmId)
        local j = 0
        for _, line in pairs(reportLines) do
            local lineKey = string.format("%s.line(%d)", reportKey, j)
            setXMLString(xmlFile, lineKey .. "#cell1", line.cell1)
            setXMLString(xmlFile, lineKey .. "#cell2", line.cell2)
            setXMLString(xmlFile, lineKey .. "#cell3", line.cell3)
            j = j + 1
        end
        i = i + 1
    end

    local k = 0
    for farmId, _ in pairs(self.watchingFarms) do
        local watchKey = string.format("%s.watchingFarms.item(%d)", key, k)
        setXMLInt(xmlFile, watchKey .. "#farmId", farmId)
        k = k + 1
    end
end

function RTPolicy:loadFromXMLFile(xmlFile, key)
    self.id = getXMLString(xmlFile, key .. "#id") or RedTape.generateId()
    self.policyIndex = getXMLInt(xmlFile, key .. "#policyIndex") or -1
    self.nextEvaluationMonth = getXMLInt(xmlFile, key .. "#nextEvaluationMonth") or 0

    self.evaluationCount = getXMLInt(xmlFile, key .. "#evaluationCount") or 0

    local i = 0
    self.evaluationReports = {}
    while true do
        local reportKey = string.format("%s.evaluationReports.item(%d)", key, i)
        if not hasXMLProperty(xmlFile, reportKey) then
            break
        end

        local farmId = getXMLInt(xmlFile, reportKey .. "#farmId")
        local report = {}
        local j = 0
        while true do
            local lineKey = string.format("%s.line(%d)", reportKey, j)
            if not hasXMLProperty(xmlFile, lineKey) then
                break
            end

            table.insert(report, {
                cell1 = getXMLString(xmlFile, lineKey .. "#cell1") or "",
                cell2 = getXMLString(xmlFile, lineKey .. "#cell2") or "",
                cell3 = getXMLString(xmlFile, lineKey .. "#cell3") or ""
            })

            j = j + 1
        end

        if farmId ~= nil then
            self.evaluationReports[farmId] = report
        end

        i = i + 1
    end

    local k = 0
    self.watchingFarms = {}
    while true do
        local watchKey = string.format("%s.watchingFarms.item(%d)", key, k)
        if not hasXMLProperty(xmlFile, watchKey) then
            break
        end

        local farmId = getXMLInt(xmlFile, watchKey .. "#farmId")
        if farmId ~= nil then
            self.watchingFarms[farmId] = true
        end

        k = k + 1
    end
end

function RTPolicy:getName()
    if self.policyIndex == -1 then
        return nil
    end

    local policyInfo = RTPolicies[self.policyIndex]
    if policyInfo == nil then
        return nil
    end

    return g_i18n:getText(policyInfo.name)
end

function RTPolicy:getDescription()
    if self.policyIndex == -1 then
        return nil
    end

    local policyInfo = RTPolicies[self.policyIndex]
    if policyInfo == nil then
        return nil
    end

    -- Policies whose text depends on a setting build their own description
    if policyInfo.getDescription ~= nil then
        return policyInfo.getDescription(policyInfo)
    end

    return g_i18n:getText(policyInfo.description)
end

function RTPolicy:getWarningCount(farmId)
    return g_currentMission.RedTape.PolicySystem:getWarningCountForFarmPolicy(farmId, self.policyIndex)
end

function RTPolicy:isBeingWatchedByFarm(farmId)
    return self.watchingFarms[farmId] == true
end

function RTPolicy:setBeingWatchedByFarm(farmId, isWatching)
    if isWatching then
        self.watchingFarms[farmId] = true
    else
        self.watchingFarms[farmId] = nil
    end
end

function RTPolicy:getReportDescription()
    if self.policyIndex == -1 then
        return nil
    end

    local policyInfo = RTPolicies[self.policyIndex]
    if policyInfo == nil then
        return nil
    end

    return g_i18n:getText(policyInfo.report_description)
end

function RTPolicy:activate()
    local policyInfo = RTPolicies[self.policyIndex]

    if policyInfo == nil then
        return
    end

    if policyInfo.evaluationInterval > 0 then
        self.nextEvaluationMonth = RedTape.getCumulativeMonth() + policyInfo.evaluationInterval
    end

    for _, farm in pairs(g_farmManager.farmIdToFarm) do
        policyInfo.activate(policyInfo, self, farm.farmId)
    end
end

function RTPolicy:evaluate()
    local rt = g_currentMission.RedTape

    -- Month end runs every system in sequence, so evaluate must never throw: anything it cannot
    -- make sense of is logged and skipped rather than allowed to abort the rest of month end.
    local policyInfo = RTPolicies[self.policyIndex]
    if policyInfo == nil or policyInfo.evaluate == nil then
        RedTape.logWarning("skipping evaluation of unknown policy index " .. tostring(self.policyIndex)
            .. " (id=" .. tostring(self.id) .. ")")
        return
    end

    local cumulativeMonth = RedTape.getCumulativeMonth()
    -- Accounts for possible skipping of time
    if cumulativeMonth < (self.nextEvaluationMonth or 0) then
        return
    end

    -- Not enforced: no report, no points, no warnings and no fines. The window still rolls
    -- forward so that switching the policy back on starts a fresh evaluation period rather than
    -- immediately judging the months it spent switched off.
    if not RedTape.isPolicyEnforced(self.policyIndex) then
        self.nextEvaluationMonth = cumulativeMonth + policyInfo.evaluationInterval
        return
    end

    for _, farm in pairs(g_farmManager.farmIdToFarm) do
        local progress = rt.PolicySystem:getProgressForFarm(farm.farmId)

        if progress == nil then
            continue
        end

        local farmTier = progress.tier
        local report = policyInfo.evaluate(policyInfo, self, farm.farmId, farmTier) or {}

        -- Ensure all report values are strings
        for _, reportLine in pairs(report) do
            reportLine.cell1 = tostring(reportLine.cell1 or "")
            reportLine.cell2 = tostring(reportLine.cell2 or "")
            reportLine.cell3 = tostring(reportLine.cell3 or "")
        end

        g_client:getServerConnection():sendEvent(RTPolicyReportEvent.new(self.policyIndex, farm.farmId, report))
    end

    self.evaluationCount = (self.evaluationCount or 0) + 1
    self.nextEvaluationMonth = cumulativeMonth + policyInfo.evaluationInterval
end
