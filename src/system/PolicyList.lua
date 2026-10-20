RTPolicyIds = {
    CROP_ROTATION = 1,
    SPRAY_VIOLATION = 2,
    EMPTY_STRAW = 3,
    FULL_SLURRY = 4,
    EMPTY_FOOD = 5,
    ANIMAL_SPACE = 6,
    ANIMAL_PRODUCTIVITY = 7,
    MANURE_SPREADING = 8,
    RESTRICTED_SLURRY = 9,
    SUSTAINABLE_FORESTRY = 10,
    SPREADING_CONDITIONS = 11,
    NOXIOUS_WEEDS = 12,
}

RTPolicies = {

    [RTPolicyIds.CROP_ROTATION] = {
        id = RTPolicyIds.CROP_ROTATION,
        name = "rt_policy_croprotation",
        description = "rt_policy_description_croprotation",
        report_description = "rt_policy_report_description_croprotation",
        probability = 0.8,
        periodicReward = 100,
        periodicPenalty = -200,
        evaluationInterval = 12,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]
            local fruitsToSkip = {}

            -- Every one of these can be nil on a map that removes the fruit, so never index
            -- the result without checking.
            local skipIndices = { FruitType.GRAPE, FruitType.OLIVE }
            for _, f in pairs(RedTape.getGrassTypes()) do
                table.insert(skipIndices, f)
            end

            for _, fruitTypeIndex in pairs(skipIndices) do
                local fruit = fruitTypeIndex ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex) or nil
                if fruit ~= nil then
                    table.insert(fruitsToSkip, fruit.name)
                end
            end

            -- Harvests recorded in the month the mod started tracking come from whatever the
            -- map itself put on the fields, not from anything the player grew.
            local firstTrackedMonth = g_currentMission.RedTape.monthStarted or 0

            local totalHa = 0
            local nonCompliantHa = 0

            for _, farmland in pairs(g_farmlandManager.farmlands) do
                if farmland.farmId == farmId and farmland.field ~= nil then
                    local farmLandData = gatherer:getFarmlandData(farmland.id)

                    if farmLandData.rotationExceptions > 0 then
                        farmLandData.rotationExceptions = farmLandData.rotationExceptions - 1
                        continue
                    end

                    if farmLandData.fallowMonths > 10 then
                        continue
                    end

                    local history = {}
                    for _, harvestEntry in ipairs(farmLandData.harvestedCropsHistory) do
                        if harvestEntry.month ~= nil and harvestEntry.month > firstTrackedMonth then
                            table.insert(history, harvestEntry)
                        end
                    end

                    if #history == 0 then
                        continue
                    end

                    local mostRecentHarvest = history[1]

                    if RedTape.tableHasValue(fruitsToSkip, mostRecentHarvest.name) then
                        continue
                    end

                    if #history < 2 then
                        continue
                    end

                    local previousHarvest = history[2]

                    totalHa = totalHa + farmLandData.areaHa

                    if mostRecentHarvest.name == previousHarvest.name then
                        nonCompliantHa = nonCompliantHa + farmLandData.areaHa
                    end
                end
            end

            local reward = 0
            if totalHa == 0 then
                reward = 0
            elseif nonCompliantHa == 0 then
                reward = policyInfo.periodicReward
            else
                local nonCompliantProportion = nonCompliantHa / totalHa
                reward = policyInfo.periodicPenalty * nonCompliantProportion
            end

            if reward < 0 then
                reward = math.floor(reward)
            else
                reward = math.ceil(reward)
            end

            local report = {}
            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_total_area"), cell2 = g_i18n:formatArea(totalHa, 2) })
            table.insert(report,
                {
                    cell1 = g_i18n:getText("rt_report_name_non_compliant_area"),
                    cell2 = g_i18n:formatArea(nonCompliantHa, 2)
                })
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end
            return report
        end,
    },

    [RTPolicyIds.SPRAY_VIOLATION] = {
        id = RTPolicyIds.SPRAY_VIOLATION,
        name = "rt_policy_sprayviolation",
        description = "rt_policy_description_sprayviolation",
        report_description = "rt_policy_report_description_sprayviolation",
        probability = 0.5,
        periodicReward = 5,
        pointsPenaltyPerViolation = -1,
        evaluationInterval = 1,
        finePerViolation = 100,
        warningThreshold = 10,
        maxWarnings = 1,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local monthlySprayViolations = farmData.monthlySprayViolations or 0

            local reward = 0
            if monthlySprayViolations > 0 then
                reward = policyInfo.pointsPenaltyPerViolation * monthlySprayViolations

                local fineAmount = monthlySprayViolations * policyInfo.finePerViolation
                local skipWarning = monthlySprayViolations > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                reward = policyInfo.periodicReward
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            reward = math.ceil(reward)

            local report = {}
            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_spray_violations"), cell2 = monthlySprayViolations })
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end,
    },

    [RTPolicyIds.EMPTY_STRAW] = {
        id = RTPolicyIds.EMPTY_STRAW,
        name = "rt_policy_empty_straw",
        description = "rt_policy_description_empty_straw",
        report_description = "rt_policy_report_description_empty_straw",
        probability = 0.6,
        periodicReward = 5,
        pointsPenaltyPerViolation = -2,
        finePerViolation = 50,
        warningThreshold = 24,
        maxWarnings = 1,
        evaluationInterval = 1,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local monthlyEmptyStrawCount = farmData.monthlyEmptyStrawCount or 0
            local reward = 0
            if monthlyEmptyStrawCount > 0 then
                reward = (policyInfo.pointsPenaltyPerViolation / RedTape.getDaysPerPeriod()) *
                    monthlyEmptyStrawCount

                local normalisedCount = monthlyEmptyStrawCount / RedTape.getDaysPerPeriod()
                local fineAmount = normalisedCount * policyInfo.finePerViolation
                local skipWarning = normalisedCount > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                if farmData.monthlyAnimalHours > 0 or currentTier == RTPolicySystem.TIER.D then
                    reward = policyInfo.periodicReward
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            if reward < 0 then
                reward = math.floor(reward)
            else
                reward = math.ceil(reward)
            end

            local report = {}
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_empty_straw"), cell2 = monthlyEmptyStrawCount })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })
            return report
        end,
    },

    [RTPolicyIds.FULL_SLURRY] = {
        id = RTPolicyIds.FULL_SLURRY,
        name = "rt_policy_full_slurry",
        description = "rt_policy_description_full_slurry",
        report_description = "rt_policy_report_description_full_slurry",
        probability = 0.5,
        periodicReward = 5,
        periodicPenaltyPerViolation = -3,
        evaluationInterval = 1,
        finePerViolation = 80,
        warningThreshold = 12,
        maxWarnings = 1,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local monthlyFullSlurryCount = farmData.monthlyFullSlurryCount or 0
            local reward = 0
            if monthlyFullSlurryCount > 0 then
                reward = (policyInfo.periodicPenaltyPerViolation / RedTape.getDaysPerPeriod()) *
                    monthlyFullSlurryCount

                local normalisedViolations = monthlyFullSlurryCount / RedTape.getDaysPerPeriod()
                local fineAmount = policyInfo.finePerViolation * normalisedViolations
                local skipWarning = normalisedViolations > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                if farmData.monthlyAnimalHours > 0 or currentTier == RTPolicySystem.TIER.D then
                    reward = policyInfo.periodicReward
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            if reward < 0 then
                reward = math.floor(reward)
            else
                reward = math.ceil(reward)
            end

            local report = {}
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_full_slurry"), cell2 = monthlyFullSlurryCount })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })
            return report
        end
    },

    [RTPolicyIds.EMPTY_FOOD] = {
        id = RTPolicyIds.EMPTY_FOOD,
        name = "rt_policy_empty_food",
        description = "rt_policy_description_empty_food",
        report_description = "rt_policy_report_description_empty_food",
        probability = 0.7,
        periodicReward = 5,
        periodicPenaltyPerViolation = -3,
        evaluationInterval = 1,
        finePerViolation = 100,
        warningThreshold = 6,
        maxWarnings = 1,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local monthlyEmptyFoodCount = farmData.monthlyEmptyFoodCount or 0
            local reward = 0
            if monthlyEmptyFoodCount > 0 then
                reward = (policyInfo.periodicPenaltyPerViolation / RedTape.getDaysPerPeriod()) *
                    monthlyEmptyFoodCount

                local normalisedViolations = monthlyEmptyFoodCount / RedTape.getDaysPerPeriod()
                local fineAmount = normalisedViolations * policyInfo.finePerViolation
                local skipWarning = normalisedViolations > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                if farmData.monthlyAnimalHours > 0 or currentTier == RTPolicySystem.TIER.D then
                    reward = policyInfo.periodicReward
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            if reward < 0 then
                reward = math.floor(reward)
            else
                reward = math.ceil(reward)
            end

            local report = {}
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_empty_food"), cell2 = monthlyEmptyFoodCount })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })
            return report
        end,
    },

    [RTPolicyIds.ANIMAL_SPACE] = {
        id = RTPolicyIds.ANIMAL_SPACE,
        name = "rt_policy_animal_space",
        description = "rt_policy_description_animal_space",
        report_description = "rt_policy_report_description_animal_space",
        probability = 0.6,
        periodicReward = 10,
        periodicPenaltyPerViolation = -1,
        evaluationInterval = 1,
        finePerViolation = 50,
        warningThreshold = 24,
        maxWarnings = 1,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local animalSpaceDetail = farmData.monthlyDetail["animalSpace"] or {}
            local pendingViolations = farmData.monthlyAnimalSpaceViolations or 0
            local cumulativeMonth = RedTape.getCumulativeMonth()
            local reward = 0
            if pendingViolations > 0 then
                if policy:getWarningCount(farmId) > 0 then
                    reward = (policyInfo.periodicPenaltyPerViolation / RedTape.getDaysPerPeriod()) *
                        pendingViolations
                end

                local normalisedViolations = pendingViolations / RedTape.getDaysPerPeriod()
                local fineAmount = normalisedViolations * policyInfo.finePerViolation
                local skipWarning = normalisedViolations > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                if farmData.monthlyAnimalHours > 0 or currentTier == RTPolicySystem.TIER.D then
                    reward = policyInfo.periodicReward
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            if reward < 0 then
                reward = math.floor(reward)
            else
                reward = math.ceil(reward)
            end

            local report = {}
            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_animal_space_violations"), cell2 = pendingViolations })

            for _, entry in pairs(animalSpaceDetail) do
                if entry.updated >= cumulativeMonth - 1 then
                    table.insert(report, {
                        cell1 = entry.key,
                        cell2 = string.format("%s%s", tostring(entry.value1 or ""), g_i18n:getText("rt_unit_meter_square")),
                        cell3 = string.format("%s%s", tostring(entry.value2 or ""), g_i18n:getText("rt_unit_meter_square"))
                    })
                end
            end
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end,
    },

    [RTPolicyIds.ANIMAL_PRODUCTIVITY] = {
        id = RTPolicyIds.ANIMAL_PRODUCTIVITY,
        name = "rt_policy_animal_productivity",
        description = "rt_policy_description_animal_productivity",
        report_description = "rt_policy_report_description_animal_productivity",
        probability = 0.3,
        periodicReward = 5,
        periodicPenaltyPerViolation = -1,
        evaluationInterval = 1,
        finePerViolation = 100,
        warningThreshold = 24,
        maxWarnings = 1,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local pendingViolations = farmData.monthlyLowProductivityHusbandry or 0
            local reward = 0
            if pendingViolations > 0 then
                reward = (policyInfo.periodicPenaltyPerViolation / RedTape.getDaysPerPeriod()) *
                    pendingViolations

                local normalisedViolations = pendingViolations / RedTape.getDaysPerPeriod()
                local fineAmount = normalisedViolations * policyInfo.finePerViolation
                local skipWarning = normalisedViolations > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                if farmData.monthlyAnimalHours > 0 or currentTier == RTPolicySystem.TIER.D then
                    reward = policyInfo.periodicReward
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            if reward < 0 then
                reward = math.floor(reward)
            else
                reward = math.ceil(reward)
            end

            local report = {}
            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_low_productivity_hours"), cell2 = pendingViolations })
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end,
    },

    [RTPolicyIds.MANURE_SPREADING] = {
        id = RTPolicyIds.MANURE_SPREADING,
        name = "rt_policy_manure_spreading",
        description = "rt_policy_description_manure_spreading",
        report_description = "rt_policy_report_description_manure_spreading",
        probability = 0.4,
        periodicReward = 50,
        periodicPenalty = -100,
        evaluationInterval = 1,
        finePerViolation = 5000,
        warningThreshold = 0,
        maxWarnings = 0,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local manureName = g_fillTypeManager:getFillTypeNameByIndex(FillType.MANURE)
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
            local elapsedMonths = RedTape.getElapsedMonths()

            -- local actualSpread = 0
            local totalProduced = 0
            local monthsToSearch = 6
            local cumulativeMonth = RedTape.getCumulativeMonth()

            local report = {}
            local perMonthValues = {}
            for month = cumulativeMonth - monthsToSearch, cumulativeMonth - 1 do
                local producedHistory = farmData.produceHistory[month]

                table.insert(perMonthValues, producedHistory ~= nil and producedHistory[manureName] or 0)

                if producedHistory ~= nil and producedHistory[manureName] ~= nil then
                    totalProduced = totalProduced + producedHistory[manureName]
                end
            end

            for i = 1, #perMonthValues do
                local monthsBack = i
                table.insert(report,
                    {
                        cell1 = string.format("%s %d", g_i18n:getText("rt_misc_month"), monthsBack),
                        cell2 = g_i18n:formatVolume(perMonthValues[i], 0)
                    })
            end

            local reward = 0
            local manureStorageLimit = g_currentMission.RedTape.settings.manureStorageLimit or 5000
            local maxStoredAmount = math.max(totalProduced * 0.5, manureStorageLimit)
            -- expectedSpread = farmData.rollingAverageManureLevel * 0.5

            if currentMonth == 5 or currentMonth == 11 then
                if elapsedMonths < 3 then
                    table.insert(report,
                        {
                            cell1 = g_i18n:getText("rt_report_name_note"),
                            cell2 = g_i18n:getText("rt_report_value_not_enough_months_elapsed")
                        })
                else
                    if farmData.currentManureLevel > maxStoredAmount then
                        reward = policyInfo.periodicPenalty

                        local fineAmount = policyInfo.finePerViolation
                        local skipWarning = true
                        g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount,
                            skipWarning)
                    else
                        reward = policyInfo.periodicReward
                    end
                end
            end

            reward = math.ceil(reward)

            table.insert(report,
                {
                    cell1 = g_i18n:getText("rt_report_name_manure_total_produced"),
                    cell2 = g_i18n:formatVolume(totalProduced, 0)
                })
            table.insert(report,
                {
                    cell1 = g_i18n:getText("rt_report_name_manure_max_stored_amount"),
                    cell2 = g_i18n:formatVolume(maxStoredAmount, 0)
                })
            table.insert(report,
                {
                    cell1 = g_i18n:getText("rt_report_name_manure_stored_amount"),
                    cell2 = g_i18n:formatVolume(farmData.currentManureLevel, 0)
                })
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end
    },

    [RTPolicyIds.RESTRICTED_SLURRY] = {
        id = RTPolicyIds.RESTRICTED_SLURRY,
        name = "rt_policy_restricted_slurry",
        description = "rt_policy_description_restricted_slurry",
        report_description = "rt_policy_report_description_restricted_slurry",
        probability = 0.4,
        periodicReward = 20,
        periodicPenaltyPerViolation = -0.5,
        evaluationInterval = 1,
        finePerViolation = 5,
        warningThreshold = 50,
        maxWarnings = 1,
        restrictedMonthCount = 4,
        defaultStartMonth = 9,
        -- The closed period is UK based by default, but the start month is a setting so it can
        -- be shifted to match other countries' rules. The window length never changes.
        getStartMonth = function(policyInfo)
            local settings = g_currentMission.RedTape.settings
            return (settings ~= nil and settings.slurryRestrictionStart) or policyInfo.defaultStartMonth
        end,
        -- The months slurry may not be applied in.
        getRestrictedMonths = function(policyInfo)
            local startMonth = policyInfo.getStartMonth(policyInfo)
            local months = {}
            for i = 0, policyInfo.restrictedMonthCount - 1 do
                table.insert(months, (startMonth - 1 + i) % 12 + 1)
            end
            return months
        end,
        -- Each restricted month is evaluated in the month that follows it, so the months a clean
        -- record earns points in are the restricted months shifted forward by one.
        getRewardMonths = function(policyInfo)
            local months = {}
            for _, month in pairs(policyInfo.getRestrictedMonths(policyInfo)) do
                table.insert(months, month % 12 + 1)
            end
            return months
        end,
        getDescription = function(policyInfo)
            local restrictedMonths = policyInfo.getRestrictedMonths(policyInfo)
            return string.format(g_i18n:getText(policyInfo.description),
                RedTape.monthToString(restrictedMonths[1]),
                RedTape.monthToString(restrictedMonths[#restrictedMonths]))
        end,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local pendingViolations = farmData.monthlyRestrictedSlurryViolations or 0
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)

            local reward = 0
            if pendingViolations > 0 then
                reward = policyInfo.periodicPenaltyPerViolation * pendingViolations

                local fineAmount = pendingViolations * policyInfo.finePerViolation
                local skipWarning = pendingViolations > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                if RedTape.tableHasValue(policyInfo.getRewardMonths(policyInfo), currentMonth) then
                    if farmData.monthlyAnimalHours > 0 or currentTier == RTPolicySystem.TIER.D then
                        reward = policyInfo.periodicReward
                    end
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            reward = math.ceil(reward)

            local report = {}
            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_restricted_slurry_violations"), cell2 = pendingViolations })
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end,
    },

    [RTPolicyIds.SUSTAINABLE_FORESTRY] = {
        id = RTPolicyIds.SUSTAINABLE_FORESTRY,
        name = "rt_policy_sustainable_forestry",
        description = "rt_policy_description_sustainable_forestry",
        report_description = "rt_policy_report_description_sustainable_forestry",
        probability = 0.5,
        excessCutFinePerTree = 250,
        pointsPerNetTree = 1,
        penaltyPointsPerTree = -5,
        evaluationInterval = 1,
        maxWarnings = 0,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
            local elapsedMonths = RedTape.getElapsedMonths()

            local cutTrees = farmData.biAnnualCutTrees or 0
            local plantedTrees = farmData.biAnnualPlantedTrees or 0
            local netTrees = plantedTrees - cutTrees

            local report = {}

            local reward = 0
            if currentMonth == 6 or currentMonth == 12 then
                if elapsedMonths < 3 then
                    table.insert(report,
                        {
                            cell1 = g_i18n:getText("rt_report_name_note"),
                            cell2 = g_i18n:getText(
                                "rt_report_value_not_enough_months_elapsed")
                        })
                else
                    if netTrees < 0 then
                        reward = policyInfo.penaltyPointsPerTree * math.abs(netTrees)
                        local fine = policyInfo.excessCutFinePerTree * math.abs(netTrees)
                        local skipWarning = true
                        g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fine, skipWarning)
                    elseif netTrees > 0 then
                        reward = policyInfo.pointsPerNetTree * netTrees
                    end
                end
            end

            reward = math.ceil(reward)

            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_trees_planted"), cell2 = plantedTrees })
            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_trees_cut"), cell2 = cutTrees })
            table.insert(report,
                { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end,
    },

    [RTPolicyIds.SPREADING_CONDITIONS] = {
        id = RTPolicyIds.SPREADING_CONDITIONS,
        name = "rt_policy_spreading_conditions",
        description = "rt_policy_description_spreading_conditions",
        report_description = "rt_policy_report_description_spreading_conditions",
        probability = 0.5,
        periodicReward = 10,
        periodicPenaltyPerViolation = -0.25,
        evaluationInterval = 1,
        finePerViolation = 5,
        warningThreshold = 90,
        maxWarnings = 1,
        -- Report label for each FarmGatherer.BAD_SPREAD_REASONS entry
        reasonNames = {
            snow = "rt_report_name_spread_snow",
            frozen = "rt_report_name_spread_frozen",
            rain = "rt_report_name_spread_rain",
            waterlogged = "rt_report_name_spread_waterlogged",
        },
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(farmId)
            local counts = farmData.monthlyBadConditionsSpread or {}
            local pendingViolations = FarmGatherer.getBadConditionsSpreadTotal(farmData)

            local reward = 0
            if pendingViolations > 0 then
                reward = policyInfo.periodicPenaltyPerViolation * pendingViolations

                local fineAmount = pendingViolations * policyInfo.finePerViolation
                local skipWarning = pendingViolations > policyInfo.warningThreshold
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, skipWarning)
            else
                -- Only reward a clean month if the farm actually spread something in it
                local spreadLastMonth = false
                local regulatedNames = {}
                for _, fillTypeIndex in pairs({ FillType.FERTILIZER, FillType.LIQUIDFERTILIZER, FillType.LIQUIDMANURE,
                    FillType.DIGESTATE, FillType.MANURE }) do
                    local name = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
                    if name ~= nil then
                        table.insert(regulatedNames, name)
                    end
                end
                local lastMonthHistory = (farmData.sprayHistory or {})[RedTape.getCumulativeMonth() - 1] or {}
                for fillTypeName, amount in pairs(lastMonthHistory) do
                    if RedTape.tableHasValue(regulatedNames, fillTypeName) and (tonumber(amount) or 0) > 0 then
                        spreadLastMonth = true
                        break
                    end
                end

                if spreadLastMonth or currentTier == RTPolicySystem.TIER.D then
                    reward = policyInfo.periodicReward
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            if reward < 0 then
                reward = math.floor(reward)
            else
                reward = math.ceil(reward)
            end

            local report = {}
            for _, reason in ipairs(FarmGatherer.BAD_SPREAD_REASONS) do
                table.insert(report,
                    { cell1 = g_i18n:getText(policyInfo.reasonNames[reason]), cell2 = counts[reason] or 0 })
            end
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end,
    },

    [RTPolicyIds.NOXIOUS_WEEDS] = {
        id = RTPolicyIds.NOXIOUS_WEEDS,
        name = "rt_policy_noxious_weeds",
        description = "rt_policy_description_noxious_weeds",
        report_description = "rt_policy_report_description_noxious_weeds",
        probability = 0.5,
        periodicReward = 10,
        pointsPenaltyPerHa = -2,
        finePerHa = 400,
        evaluationInterval = 1,
        maxWarnings = 1,
        -- Consecutive overrun months before a field draws a warning, and then a fine. A single
        -- weedy month is never acted on, so there is always time to spray after weeds appear.
        warningMonths = 2,
        fineMonths = 3,
        -- Nothing to enforce in a savegame without weeds
        isAvailable = function(policyInfo)
            return FarmlandGatherer.getWeedsActive()
        end,
        activate = function(policyInfo, policy, farmId)
        end,
        evaluate = function(policyInfo, policy, farmId, currentTier)
            local report = {}

            if not FarmlandGatherer.getWeedsActive() then
                table.insert(report, {
                    cell1 = g_i18n:getText("rt_report_name_note"),
                    cell2 = g_i18n:getText("rt_report_value_weeds_disabled")
                })
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
                return report
            end

            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]

            local fieldsChecked = 0
            local anyOverrun = false
            local warnedFields = 0
            local finedHa = 0
            local fieldRows = {}

            -- The gatherer has just sampled every field this period change, so its streaks
            -- already include last month.
            for _, farmland in pairs(g_farmlandManager.farmlands) do
                if farmland.farmId == farmId and farmland.field ~= nil then
                    local farmlandData = gatherer:getFarmlandData(farmland.id)
                    local months = farmlandData.highWeedMonths or 0

                    if farmlandData.weedJudged then
                        fieldsChecked = fieldsChecked + 1
                    end

                    if months > 0 then
                        anyOverrun = true

                        local status
                        if months >= policyInfo.fineMonths then
                            finedHa = finedHa + (farmlandData.areaHa or 0)
                            status = "rt_report_value_weeds_fined"
                        elseif months >= policyInfo.warningMonths then
                            warnedFields = warnedFields + 1
                            status = "rt_report_value_weeds_warning"
                        else
                            status = "rt_report_value_weeds_monitoring"
                        end

                        local suffix = months > 1 and g_i18n:getText("rt_misc_month_plural_suffix") or ""
                        table.insert(fieldRows, {
                            id = farmland.id,
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = string.format("%d %s%s", months, g_i18n:getText("rt_misc_month"), suffix),
                            cell3 = g_i18n:getText(status)
                        })
                    end
                end
            end

            local reward = 0
            if finedHa > 0 then
                reward = math.floor(policyInfo.pointsPenaltyPerHa * finedHa)
                local fineAmount = finedHa * policyInfo.finePerHa
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, fineAmount, true)
            elseif warnedFields > 0 then
                -- A warning only. The fine comes from the field reaching fineMonths, not from
                -- the warning count, so no fine is passed here.
                g_currentMission.RedTape.PolicySystem:WarnAndFine(policyInfo, policy, farmId, 0, false)
            else
                -- A field in its first weedy month is not penalised, but it does not earn a
                -- clean month either.
                if not anyOverrun and (fieldsChecked > 0 or currentTier == RTPolicySystem.TIER.D) then
                    reward = policyInfo.periodicReward
                end
                g_client:getServerConnection():sendEvent(RTPolicyClearWarningsEvent.new(farmId, policy.policyIndex))
            end

            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_fields_checked"), cell2 = fieldsChecked })
            table.sort(fieldRows, function(a, b) return a.id < b.id end)
            for _, row in ipairs(fieldRows) do
                table.insert(report, { cell1 = row.cell1, cell2 = row.cell2, cell3 = row.cell3 })
            end
            table.insert(report, { cell1 = g_i18n:getText("rt_report_name_points"), cell2 = reward })

            if reward ~= 0 then
                g_client:getServerConnection():sendEvent(RTPolicyPointsEvent.new(farmId, reward, policy:getName()))
            end

            return report
        end,
    },
}
