RTTaxSystem = {}
RTTaxSystem_mt = Class(RTTaxSystem)

RTTaxSystem.TAX_CALCULATION_MONTH = 4
RTTaxSystem.TAX_PAYMENT_MONTH = 9

table.insert(FinanceStats.statNames, "taxCost")
FinanceStats.statNameToIndex["taxCost"] = #FinanceStats.statNames

function RTTaxSystem.new()
    local self = {}
    setmetatable(self, RTTaxSystem_mt)
    self.lineItems = {}
    self.taxStatements = {}
    self.farms = {}
    self.customRates = {}
    self.lossRollover = {} -- farmId -> rollover amount

    MoneyType.TAX_PAID = MoneyType.register("taxCost", "rt_ui_taxCost")
    MoneyType.LAST_ID = MoneyType.LAST_ID + 1

    return self
end

function RTTaxSystem:loadFromXMLFile(xmlFile)
    if (not g_currentMission:getIsServer()) then return end

    local key = RedTape.SaveKey .. ".taxSystem"

    self.lineItems = {}

    local i = 0
    while true do
        local lineItemKey = string.format("%s.lineItems.lineItem(%d)", key, i)
        if not hasXMLProperty(xmlFile, lineItemKey) then
            break
        end

        local farmId = getXMLInt(xmlFile, lineItemKey .. "#farmId")
        local month = getXMLInt(xmlFile, lineItemKey .. "#month")

        if self.lineItems[farmId] == nil then
            self.lineItems[farmId] = {}
        end
        if self.lineItems[farmId][month] == nil then
            self.lineItems[farmId][month] = {}
        end

        local lineItem = RTTaxLineItem.new()
        lineItem:loadFromXMLFile(xmlFile, lineItemKey)

        table.insert(self.lineItems[farmId][month], lineItem)

        if not RedTape.tableHasValue(self.farms, farmId) then
            table.insert(self.farms, farmId)
        end

        i = i + 1
    end

    self.lossRollover = {}
    local l = 0
    while true do
        local rolloverKey = string.format("%s.lossRollover.rollover(%d)", key, l)
        if not hasXMLProperty(xmlFile, rolloverKey) then
            break
        end

        local farmId = getXMLInt(xmlFile, rolloverKey .. "#farmId")
        local amount = getXMLInt(xmlFile, rolloverKey .. "#amount")
        self.lossRollover[farmId] = amount

        l = l + 1
    end

    self.taxStatements = {}
    local j = 0
    while true do
        local taxStatementKey = string.format("%s.taxStatements.taxStatement(%d)", key, j)
        if not hasXMLProperty(xmlFile, taxStatementKey) then
            break
        end

        local taxStatement = RTTaxStatement.new()
        taxStatement:loadFromXMLFile(xmlFile, taxStatementKey)

        table.insert(self.taxStatements, taxStatement)

        j = j + 1
    end

    self.customRates = {}
    local k = 0
    while true do
        local rateKey = string.format("%s.customRates.customRate(%d)", key, k)
        if not hasXMLProperty(xmlFile, rateKey) then
            break
        end

        local farmId = getXMLInt(xmlFile, rateKey .. "#farmId")
        if self.customRates[farmId] == nil then
            self.customRates[farmId] = {}
        end

        local rateInfo = {
            startMonth = getXMLInt(xmlFile, rateKey .. "#startMonth"),
            endMonth = getXMLInt(xmlFile, rateKey .. "#endMonth"),
            statistic = getXMLString(xmlFile, rateKey .. "#statistic"),
            taxedAmountModifier = getXMLFloat(xmlFile, rateKey .. "#taxedAmountModifier")
        }

        table.insert(self.customRates[farmId], rateInfo)

        k = k + 1
    end
end

function RTTaxSystem:saveToXmlFile(xmlFile)
    if (not g_currentMission:getIsServer()) then return end
    if (not self:isEnabled()) then return end

    local key = RedTape.SaveKey .. ".taxSystem"

    local i = 0
    for farmId, months in pairs(self.lineItems) do
        for month, lineItems in pairs(months) do
            for _, lineItem in ipairs(lineItems) do
                local lineItemKey = string.format("%s.lineItems.lineItem(%d)", key, i)
                setXMLInt(xmlFile, lineItemKey .. "#farmId", farmId)
                setXMLInt(xmlFile, lineItemKey .. "#month", month)
                lineItem:saveToXmlFile(xmlFile, lineItemKey)
                i = i + 1
            end
        end
    end

    local j = 0
    for _, taxStatement in ipairs(self.taxStatements) do
        local taxStatementKey = string.format("%s.taxStatements.taxStatement(%d)", key, j)
        taxStatement:saveToXmlFile(xmlFile, taxStatementKey)
        j = j + 1
    end

    local k = 0
    for farmId, customRates in pairs(self.customRates) do
        for _, rateInfo in ipairs(customRates) do
            local rateKey = string.format("%s.customRates.customRate(%d)", key, k)
            setXMLInt(xmlFile, rateKey .. "#farmId", farmId)
            setXMLInt(xmlFile, rateKey .. "#startMonth", rateInfo.startMonth)
            setXMLInt(xmlFile, rateKey .. "#endMonth", rateInfo.endMonth)
            setXMLString(xmlFile, rateKey .. "#statistic", rateInfo.statistic)
            setXMLFloat(xmlFile, rateKey .. "#taxedAmountModifier", rateInfo.taxedAmountModifier)
            k = k + 1
        end
    end

    local l = 0
    for farmId, rolloverAmount in pairs(self.lossRollover) do
        if rolloverAmount > 0 then
            local rolloverKey = string.format("%s.lossRollover.rollover(%d)", key, l)
            setXMLInt(xmlFile, rolloverKey .. "#farmId", farmId)
            setXMLInt(xmlFile, rolloverKey .. "#amount", rolloverAmount)
            l = l + 1
        end
    end
end

function RTTaxSystem:isEnabled()
    return g_currentMission.RedTape.settings.taxEnabled
end

function RTTaxSystem:writeInitialClientState(streamId, connection)
    streamWriteInt32(streamId, RedTape.tableCount(self.taxStatements))
    for _, taxStatement in ipairs(self.taxStatements) do
        taxStatement:writeStream(streamId, connection)
    end

    local farmMonthCount = 0
    for farmId, months in pairs(self.lineItems) do
        for month, lineItems in pairs(months) do
            farmMonthCount = farmMonthCount + 1
        end
    end

    streamWriteInt32(streamId, farmMonthCount)
    for farmId, months in pairs(self.lineItems) do
        for month, lineItems in pairs(months) do
            streamWriteInt32(streamId, farmId)
            streamWriteInt32(streamId, month)
            streamWriteInt32(streamId, RedTape.tableCount(lineItems))
            for _, lineItem in ipairs(lineItems) do
                lineItem:writeStream(streamId, connection)
            end
        end
    end

    streamWriteInt32(streamId, RedTape.tableCount(self.customRates))
    for farmId, customRates in pairs(self.customRates) do
        streamWriteInt32(streamId, farmId)
        streamWriteInt32(streamId, RedTape.tableCount(customRates))
        for _, rateInfo in ipairs(customRates) do
            streamWriteInt32(streamId, rateInfo.startMonth)
            streamWriteInt32(streamId, rateInfo.endMonth)
            streamWriteString(streamId, rateInfo.statistic)
            streamWriteFloat32(streamId, rateInfo.taxedAmountModifier)
        end
    end

    streamWriteInt32(streamId, RedTape.tableCount(self.lossRollover))
    for farmId, rolloverAmount in pairs(self.lossRollover) do
        streamWriteInt32(streamId, farmId)
        streamWriteInt32(streamId, rolloverAmount)
    end
end

function RTTaxSystem:readInitialClientState(streamId, connection)
    local taxStatementCount = streamReadInt32(streamId)
    self.taxStatements = {}
    for i = 1, taxStatementCount do
        local taxStatement = RTTaxStatement.new()
        taxStatement:readStream(streamId, connection)
        table.insert(self.taxStatements, taxStatement)
    end

    local lineItemCount = streamReadInt32(streamId)
    self.lineItems = {}
    for i = 1, lineItemCount do
        local farmId = streamReadInt32(streamId)
        local month = streamReadInt32(streamId)
        local itemsCount = streamReadInt32(streamId)

        if self.lineItems[farmId] == nil then
            self.lineItems[farmId] = {}
        end
        if self.lineItems[farmId][month] == nil then
            self.lineItems[farmId][month] = {}
        end

        for j = 1, itemsCount do
            local lineItem = RTTaxLineItem.new()
            lineItem:readStream(streamId, connection)
            table.insert(self.lineItems[farmId][month], lineItem)
        end
    end

    local customRateFarmCount = streamReadInt32(streamId)
    self.customRates = {}
    for i = 1, customRateFarmCount do
        local farmId = streamReadInt32(streamId)
        local rateCount = streamReadInt32(streamId)

        self.customRates[farmId] = {}
        for j = 1, rateCount do
            local rateInfo = {
                startMonth = streamReadInt32(streamId),
                endMonth = streamReadInt32(streamId),
                statistic = streamReadString(streamId),
                taxedAmountModifier = streamReadFloat32(streamId)
            }
            table.insert(self.customRates[farmId], rateInfo)
        end
    end

    local rolloverCount = streamReadInt32(streamId)
    self.lossRollover = {}
    for i = 1, rolloverCount do
        local farmId = streamReadInt32(streamId)
        local rolloverAmount = streamReadInt32(streamId)
        self.lossRollover[farmId] = rolloverAmount
    end
end

function RTTaxSystem:hourChanged()
end

function RTTaxSystem:periodChanged()
    if (not self:isEnabled()) then return end
    local month = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
    if month == RTTaxSystem.TAX_CALCULATION_MONTH then
        self:createAnnualTaxStatements()
    end

    if month == RTTaxSystem.TAX_PAYMENT_MONTH then
        self:processTaxStatements()
    end

    local cumulativeMonth = RedTape.getCumulativeMonth()
    local oldestHistoryMonth = cumulativeMonth - 24

    -- Clean up old tax line items
    for farmId, months in pairs(self.lineItems) do
        for month, _ in pairs(months) do
            if month < oldestHistoryMonth then
                self.lineItems[farmId][month] = nil
            end
        end
    end
end

-- Called via NewTaxLineItemEvent to store on server and client
function RTTaxSystem:recordLineItem(farmId, lineItem)
    if (not self:isEnabled()) then return end
    local cumulativeMonth = RedTape.getCumulativeMonth()
    self.lineItems[farmId] = self.lineItems[farmId] or {}

    if self.lineItems[farmId][cumulativeMonth] == nil then
        self.lineItems[farmId][cumulativeMonth] = {}
    end

    if not RedTape.tableHasValue(self.farms, farmId) then
        table.insert(self.farms, farmId)
    end

    -- try merge into an existing lineItem of the same statistic for this month
    for _, existingLineItem in ipairs(self.lineItems[farmId][cumulativeMonth]) do
        if existingLineItem.statistic == lineItem.statistic then
            existingLineItem.amount = existingLineItem.amount + lineItem.amount
            return
        end
    end

    table.insert(self.lineItems[farmId][cumulativeMonth], lineItem)
end

function RTTaxSystem:getTaxRate(farmId)
    -- Example usage is to look up the farm and find tax rate modifiers
    -- return 0.2
    return g_currentMission.RedTape.settings.baseTaxRate / 100
end

function RTTaxSystem:getTaxedAmount(lineItem, taxStatement)
    -- Apply any modifiers to the amount taxed
    local taxedAmountModifier = 1
    if self.customRates[lineItem.farmId] ~= nil then
        local cumulativeMonth = RedTape.getCumulativeMonth()
        for _, rateInfo in ipairs(self.customRates[lineItem.farmId]) do
            if lineItem.statistic == rateInfo.statistic and
                cumulativeMonth >= rateInfo.startMonth and
                cumulativeMonth <= rateInfo.endMonth then
                taxedAmountModifier = rateInfo.taxedAmountModifier
            end
        end
    end

    return lineItem.amount * taxedAmountModifier
end

function RTTaxSystem:categoriseLineItem(lineItem, taxStatement)
    local otherExpense = lineItem.statistic == "other" and lineItem.amount < 0
    local otherIncome = lineItem.statistic == "other" and lineItem.amount > 0

    local expenseStats = {
        "newVehiclesCost",
        "constructionCost",
        "newHandtoolsCost",
        "wagePayment",
        "newAnimalsCost",
        "animalUpkeep",
        "purchaseSeeds",
        "purchaseFertilizer",
        "purchaseFuel",
        "purchaseSaplings",
        "purchaseWater",
        "purchaseBales",
        "purchasePallets",
        "purchaseConsumable",
        "fieldPurchase",
        "vehicleLeasingCost",
        "loanInterest",
        "vehicleRunningCost",
        "propertyMaintenance",
        "productionCosts",
        "grantApplicationCost",
        "invoiceExpense",
        "bankLoanInterest"
    }

    local incomeStats = {
        "soldVehicles",
        "soldBuildings",
        "soldHandtools",
        "soldMilk",
        "soldAnimals",
        "harvestIncome",
        "missionIncome",
        "fieldSelling",
        "propertyIncome",
        "soldProducts",
        "incomeBga",
        "soldWood",
        "soldBales",
        "expenses",
        "invoiceIncome"
    }

    local ignoreStats = {
        "policyFine",
        "schemePayout",
        "grantReceived",
        "taxCost"
    }

    if g_modIsLoaded["FS25_RealisticLivestock"] or g_modIsLoaded["FS25_RealisticLivestockRM"] then
        table.insert(expenseStats, "herdsmanWages")
        table.insert(expenseStats, "semenPurchase")
        table.insert(expenseStats, "medicine")
        table.insert(expenseStats, "monitorSubscriptions")
    end

    if otherExpense or RedTape.tableHasValue(expenseStats, lineItem.statistic) then
        taxStatement.totalExpenses = taxStatement.totalExpenses + math.abs(lineItem.amount)
    elseif otherIncome or RedTape.tableHasValue(incomeStats, lineItem.statistic) then
        taxStatement.totalTaxableIncome = taxStatement.totalTaxableIncome + math.abs(lineItem.amount)
        taxStatement.totalTaxedIncome = taxStatement.totalTaxedIncome + self:getTaxedAmount(lineItem, taxStatement)
    else
        if not RedTape.tableHasValue(ignoreStats, lineItem.statistic) then
            print("Warning: Uncategorised tax line item statistic '" .. tostring(lineItem.statistic) .. "'")
        end
    end
end

function RTTaxSystem:generateTaxStatement(farmId, startMonth, endMonth, finalizeRollover)
    finalizeRollover = finalizeRollover or false -- Default to false for estimates

    local taxStatement = RTTaxStatement.new()
    taxStatement.farmId = farmId
    taxStatement.taxRate = self:getTaxRate(farmId)

    local allLineItems = self.lineItems[farmId] or {}

    for month, lineItems in pairs(allLineItems) do
        if month < startMonth or month > endMonth then
            continue
        end

        for _, lineItem in ipairs(lineItems) do
            self:categoriseLineItem(lineItem, taxStatement)
        end
    end

    local baseTaxableAmount = taxStatement.totalTaxedIncome - taxStatement.totalExpenses
    local existingRollover = self.lossRollover[farmId] or 0

    if baseTaxableAmount < 0 then
        -- We have a loss this year
        local currentYearLoss = math.abs(baseTaxableAmount)
        local totalRollover = math.min(existingRollover + currentYearLoss, 5000000)

        if finalizeRollover then
            self.lossRollover[farmId] = totalRollover
        end

        taxStatement.lossRolloverGenerated = currentYearLoss
        taxStatement.lossRolloverUsed = 0
        taxStatement.totalTax = 0

        if currentYearLoss > 0 then
            table.insert(taxStatement.notes, string.format(
                g_i18n:getText("rt_notes_loss_generated"),
                g_i18n:formatMoney(currentYearLoss, 0, true, true),
                g_i18n:formatMoney(totalRollover, 0, true, true)
            ))
        end
    else
        -- We have profit this year, apply rollover losses
        local rolloverToUse = math.min(existingRollover, baseTaxableAmount)
        local finalTaxableAmount = baseTaxableAmount - rolloverToUse

        local remainingRollover = existingRollover - rolloverToUse
        if finalizeRollover then
            self.lossRollover[farmId] = remainingRollover
        end

        taxStatement.lossRolloverUsed = rolloverToUse
        taxStatement.lossRolloverGenerated = 0
        taxStatement.totalTax = math.floor(finalTaxableAmount * taxStatement.taxRate)

        if rolloverToUse > 0 then
            table.insert(taxStatement.notes, string.format(
                g_i18n:getText("rt_notes_loss_applied"),
                g_i18n:formatMoney(rolloverToUse, 0, true, true),
                g_i18n:formatMoney(remainingRollover, 0, true, true)
            ))
        end
    end

    if self.customRates[farmId] ~= nil then
        for _, rateInfo in ipairs(self.customRates[farmId]) do
            if self:monthsIntersect(startMonth, endMonth, rateInfo.startMonth, rateInfo.endMonth) then
                local statName = g_i18n:getText("finance_" .. rateInfo.statistic)
                local rate = taxStatement.taxRate * rateInfo.taxedAmountModifier * 100
                table.insert(taxStatement.notes, string.format(
                    g_i18n:getText("rt_notes_additional_tax_benefit") .. " - %s: %.2f%%",
                    statName,
                    rate
                ))
            end
        end
    end
    return taxStatement
end

function RTTaxSystem:createAnnualTaxStatements()
    if (not self:isEnabled()) then return end
    local minMonth = RedTape.getCumulativeMonth() - 12
    local maxMonth = RedTape.getCumulativeMonth() - 1
    for _, farmId in ipairs(self.farms) do
        local taxStatement = self:generateTaxStatement(farmId, minMonth, maxMonth, true)
        g_client:getServerConnection():sendEvent(RTNewTaxStatementEvent.new(taxStatement))
    end
end

function RTTaxSystem:monthsIntersect(windowStart, windowEnd, periodStart, periodEnd)
    return not (windowEnd < periodStart or windowStart > periodEnd)
end

-- Called via NewTaxStatementEvent to store on client and server
function RTTaxSystem:storeTaxStatement(taxStatement)
    local farmId = taxStatement.farmId

    -- Replace existing statement for farmId if exists
    for i, existingStatement in ipairs(self.taxStatements) do
        if existingStatement.farmId == farmId then
            self.taxStatements[i] = taxStatement
            return
        end
    end

    table.insert(self.taxStatements, taxStatement)
    g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
end

function RTTaxSystem:processTaxStatements()
    if g_currentMission:getIsServer() then
        for _, taxStatement in ipairs(self.taxStatements) do
            if not taxStatement.paid then
                if taxStatement.totalTax > 0 then
                    g_currentMission:addMoneyChange(-taxStatement.totalTax, taxStatement.farmId, MoneyType.TAX_PAID,
                        true)
                end
                g_client:getServerConnection():sendEvent(RTTaxStatementPaidEvent.new(taxStatement.farmId, taxStatement.totalTax))
            end
        end
    end
end

-- Called via RTTaxStatementPaidEvent to mark as paid on client and server
function RTTaxSystem:markTaxStatementAsPaid(farmId, amountPaid)
    for _, taxStatement in ipairs(self.taxStatements) do
        if taxStatement.farmId == farmId then
            taxStatement.paid = true
            taxStatement.amountPaid = amountPaid
            g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
            return
        end
    end
end

function RTTaxSystem:getCurrentYearTaxToDate(farmId)
    if (not self:isEnabled()) then return end
    local cumulativeMonth = RedTape.getCumulativeMonth()
    local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)

    local monthsBack = (currentMonth - RTTaxSystem.TAX_CALCULATION_MONTH + 12) % 12
    local minMonth = cumulativeMonth - monthsBack
    local maxMonth = cumulativeMonth

    local taxStatement = self:generateTaxStatement(farmId, minMonth, maxMonth, false)
    return taxStatement
end

-- Called by RTTaxRateBenefitEvent to record a custom tax rate benefit
function RTTaxSystem:recordCustomTaxRateBenefit(farmId, startMonth, endMonth, statistic, taxedAmountModifier)
    if self.customRates[farmId] == nil then
        self.customRates[farmId] = {}
    end

    table.insert(self.customRates[farmId], {
        startMonth = startMonth,
        endMonth = endMonth,
        statistic = statistic,
        taxedAmountModifier = taxedAmountModifier
    })
end
