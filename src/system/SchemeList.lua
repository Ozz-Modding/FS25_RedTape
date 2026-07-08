-- Maybe an incentive to use a natural fertiliser. Like sea weed fert, its a real  thing.

RTSchemeIds = {
    DELAYED_MOWING_WILDLIFE = 1,
    REDUCE_BALE_WRAPPING = 2,
    NATURAL_GRAZING = 3,
    NATURAL_FERTILISER = 4,
    CROP_PROMOTION = 5,
    TRACTOR_DEMO = 6,
    WINTER_COVER_CROPS = 7,
    ROAD_SNOW_CLEARING = 8,
    BRAND_DEMO = 9,
    SET_ASIDE = 10,
}


RTSchemes = {

    [RTSchemeIds.DELAYED_MOWING_WILDLIFE] = {
        id = RTSchemeIds.DELAYED_MOWING_WILDLIFE,
        name = "rt_scheme_delayed_mowing",
        description = "rt_scheme_desc_delayed_mowing",
        report_description = "rt_scheme_report_desc_delayed_mowing",
        duplicationKey = "DELAYED_HARVEST",
        offerMonths = { 1, 2, 3 },
        autoTierTransition = true,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                bonusPerHa = 12500,
            },
            [RTPolicySystem.TIER.B] = {
                bonusPerHa = 12300,
            },
            [RTPolicySystem.TIER.C] = {
                bonusPerHa = 12200,
            },
            [RTPolicySystem.TIER.D] = {
                bonusPerHa = 12000,
            },
        },
        selectionProbability = 1,
        availabilityProbability = 1,
        getNextEvaluationMonth = function(schemeInfo, scheme)
            return 7 -- July
        end,
        initialise = function(schemeInfo, scheme)
            -- Init of an available scheme, prior to selection by a farm
        end,
        selected = function(schemeInfo, scheme, tier)
            -- Any action when applying the scheme to a farm, e.g. initial payout or equipment
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)

            if currentMonth == 8 then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
                return
            end

            if currentMonth ~= 7 then return end -- Only evaluate in July
            local cumulativeMonth = RedTape.getCumulativeMonth()

            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]
            local farmId = scheme.farmId
            local invalidMonths = { cumulativeMonth - 1, cumulativeMonth - 2, cumulativeMonth - 3 }

            local grassTypes = RedTape.getGrassTypes()
            local grassTypeNames = {}
            for _, f in pairs(grassTypes) do
                table.insert(grassTypeNames, g_fruitTypeManager:getFruitTypeByIndex(f).name)
            end

            local report = {}
            local totalReward = 0
            for _, farmland in pairs(g_farmlandManager.farmlands) do
                if farmland.farmId == farmId then
                    local farmlandData = gatherer:getFarmlandData(farmland.id)

                    local juneFruit = farmlandData.fruitHistory[cumulativeMonth - 1]
                    local mayFruit = farmlandData.fruitHistory[cumulativeMonth - 2]
                    local aprilFruit = farmlandData.fruitHistory[cumulativeMonth - 3]

                    local retainedGrass = juneFruit ~= nil and RedTape.tableHasValue(grassTypeNames, juneFruit.name) and
                        mayFruit ~= nil and RedTape.tableHasValue(grassTypeNames, mayFruit.name) and
                        aprilFruit ~= nil and RedTape.tableHasValue(grassTypeNames, aprilFruit.name)

                    local didHarvest = RedTape.tableHasValue(invalidMonths, farmlandData.lastGrassHarvest)
                    if retainedGrass and not didHarvest then
                        local bonusPerHa = schemeInfo.tiers[tier].bonusPerHa
                        local payout = farmlandData.areaHa * bonusPerHa * EconomyManager.getPriceMultiplier()
                        totalReward = totalReward + payout
                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:formatMoney(payout, 0, true, true)
                        })
                    else
                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:formatMoney(0, 0, true, true),
                        })
                    end
                end
            end

            if totalReward > 0 then
                g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, farmId, totalReward))
            end

            return report
        end
    },

    [RTSchemeIds.REDUCE_BALE_WRAPPING] = {
        id = RTSchemeIds.REDUCE_BALE_WRAPPING,
        name = "rt_scheme_reduce_bale_wrapping",
        description = "rt_scheme_desc_reduce_bale_wrapping",
        report_description = "rt_scheme_report_desc_reduce_bale_wrapping",
        duplicationKey = "REDUCE_BALE_WRAPPING",
        autoTierTransition = true,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                deductionPerBaleRate = 0.068,
                maxPayoutPerHa = 1000,
            },
            [RTPolicySystem.TIER.B] = {
                deductionPerBaleRate = 0.068,
                maxPayoutPerHa = 850,
            },
            [RTPolicySystem.TIER.C] = {
                deductionPerBaleRate = 0.068,
                maxPayoutPerHa = 700,
            },
            [RTPolicySystem.TIER.D] = {
                deductionPerBaleRate = 0.068,
                maxPayoutPerHa = 600,
            },
        },
        selectionProbability = 1,
        availabilityProbability = 0.8,
        initialise = function(schemeInfo, scheme)
            -- Init of an available scheme, prior to selection by a farm
        end,
        selected = function(schemeInfo, scheme, tier)
            scheme:setProp('endMonth', RedTape.getCumulativeMonth() + 12)
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]
            local farmId = scheme.farmId
            local cumulativeMonth = RedTape.getCumulativeMonth()
            local endMonth = tonumber(scheme.props['endMonth'])

            local report = {}
            for _, farmland in pairs(g_farmlandManager.farmlands) do
                if farmland.farmId == farmId then
                    local farmlandData = gatherer:getFarmlandData(farmland.id)
                    local grassNames = {}
                    for _, fruitTypeIndex in ipairs(RedTape.getGrassTypes()) do
                        local fruitType = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
                        if fruitType ~= nil then
                            grassNames[fruitType.name] = true
                        end
                    end
                    local lastMonthFruit = farmlandData.fruitHistory[cumulativeMonth - 1]
                    local tierInfo = schemeInfo.tiers[tier]

                    local payout = 0

                    -- The goal of this calculation is an entirely baled field at 150cm bales reduces the payout to zero.
                    -- If the harvest and bale are split over months, we will see separate rewards/penalties
                    if farmlandData.monthlyWrappedBales > 0 then
                        local deductionPerBale = tierInfo.deductionPerBaleRate * tierInfo.maxPayoutPerHa
                        payout = payout - farmlandData.monthlyWrappedBales * deductionPerBale
                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:getText("rt_report_name_bale_penalty"),
                            cell3 = g_i18n:formatMoney(payout, 0, true, true)
                        })
                    end

                    if lastMonthFruit ~= nil and farmlandData.lastGrassHarvest == cumulativeMonth - 1 and grassNames[lastMonthFruit.name] then
                        local reward = farmlandData.areaHa * tierInfo.maxPayoutPerHa
                        payout = payout + reward

                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:getText("rt_report_name_harvest_reward"),
                            cell3 = g_i18n:formatMoney(payout, 0, true, true)
                        })
                    end

                    if payout ~= 0 then
                        g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, farmId,
                            payout * EconomyManager.getPriceMultiplier()))
                    end
                end
            end

            if cumulativeMonth >= endMonth then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
            end
            return report
        end
    },

    [RTSchemeIds.NATURAL_GRAZING] = {
        id = RTSchemeIds.NATURAL_GRAZING,
        name = "rt_scheme_natural_grazing",
        description = "rt_scheme_desc_natural_grazing",
        report_description = "rt_scheme_report_desc_natural_grazing",
        duplicationKey = "NATURAL_GRAZING",
        autoTierTransition = true,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                bonusPerAnimal = 30,
            },
            [RTPolicySystem.TIER.B] = {
                bonusPerAnimal = 26,
            },
            [RTPolicySystem.TIER.C] = {
                bonusPerAnimal = 23,
            },
            [RTPolicySystem.TIER.D] = {
                bonusPerAnimal = 21,
            },
        },
        selectionProbability = 1,
        availabilityProbability = 0.8,
        initialise = function(schemeInfo, scheme)
        end,
        selected = function(schemeInfo, scheme, tier)
            scheme:setProp('endMonth', RedTape.getCumulativeMonth() + 12)
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local daysPerPeriod = g_currentMission.environment.daysPerPeriod

            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]

            local report = {}
            local farmData = gatherer:getFarmData(scheme.farmId)
            local tierInfo = schemeInfo.tiers[tier]
            local eligibleAnimalCount = farmData.monthlyAnimalGrazingHours / 24 / daysPerPeriod
            local eligibleScaledAnimalCount = farmData.monthlyScaledAnimalGrazingHours / 24 / daysPerPeriod
            local payout = eligibleScaledAnimalCount * tierInfo.bonusPerAnimal * EconomyManager.getPriceMultiplier()
            local cumulativeMonth = RedTape.getCumulativeMonth()
            local endMonth = tonumber(scheme.props['endMonth'])

            table.insert(report, {
                cell1 = g_i18n:getText("rt_report_name_animal_count"),
                cell2 = tostring(eligibleAnimalCount)
            })
            table.insert(report, {
                cell1 = g_i18n:getText("rt_report_name_total_payout"),
                cell2 = g_i18n:formatMoney(payout, 0, true, true)
            })

            if payout ~= 0 then
                g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, scheme.farmId, payout))
            end

            if cumulativeMonth >= endMonth then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
            end
            return report
        end

    },

    [RTSchemeIds.NATURAL_FERTILISER] = {
        id = RTSchemeIds.NATURAL_FERTILISER,
        name = "rt_scheme_natural_fertiliser",
        description = "rt_scheme_desc_natural_fertiliser",
        report_description = "rt_scheme_report_desc_natural_fertiliser",
        duplicationKey = "NATURAL_FERTILISER",
        autoTierTransition = true,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                bonusPerUsageAmount = 0.025,
            },
            [RTPolicySystem.TIER.B] = {
                bonusPerUsageAmount = 0.022,
            },
            [RTPolicySystem.TIER.C] = {
                bonusPerUsageAmount = 0.018,
            },
            [RTPolicySystem.TIER.D] = {
                bonusPerUsageAmount = 0.015,
            },
        },
        selectionProbability = 1,
        availabilityProbability = 0.8,
        initialise = function(schemeInfo, scheme)
        end,
        selected = function(schemeInfo, scheme, tier)
            scheme:setProp('endMonth', RedTape.getCumulativeMonth() + 12)
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(scheme.farmId)
            local cumulativeMonth = RedTape.getCumulativeMonth()
            local endMonth = tonumber(scheme.props['endMonth'])

            local naturalFertilisers = {
                g_fillTypeManager:getFillTypeNameByIndex(FillType.MANURE),
                g_fillTypeManager:getFillTypeNameByIndex(FillType.LIQUIDMANURE),
                g_fillTypeManager:getFillTypeNameByIndex(FillType.DIGESTATE)
            }
            local otherFertilisers = {
                g_fillTypeManager:getFillTypeNameByIndex(FillType.FERTILIZER),
                g_fillTypeManager:getFillTypeNameByIndex(FillType.LIQUIDFERTILIZER)
            }
            local totalNaturalUsage = 0
            local totalOtherUsage = 0
            local sprayHistory = farmData.sprayHistory

            local previousMonth = cumulativeMonth - 1
            if sprayHistory[previousMonth] ~= nil then
                for fillType, amount in pairs(sprayHistory[previousMonth]) do
                    if RedTape.tableHasValue(naturalFertilisers, fillType) then
                        totalNaturalUsage = totalNaturalUsage + amount
                    elseif RedTape.tableHasValue(otherFertilisers, fillType) then
                        totalOtherUsage = totalOtherUsage + amount
                    end
                end
            end

            local totalUsage = totalNaturalUsage + totalOtherUsage
            local percentageNatural = totalUsage > 0 and (totalNaturalUsage / totalUsage) * 100 or 0
            local payout = 0

            if percentageNatural >= 75 then
                local tierInfo = schemeInfo.tiers[tier]
                payout = (totalNaturalUsage - totalOtherUsage) * tierInfo.bonusPerUsageAmount *
                    EconomyManager.getPriceMultiplier()
            end

            local report = {}
            table.insert(report, {
                cell1 = g_i18n:getText("rt_report_name_natural_usage"),
                cell2 = tostring(g_i18n:formatVolume(totalNaturalUsage, 0))
            })
            table.insert(report, {
                cell1 = g_i18n:getText("rt_report_name_other_usage"),
                cell2 = tostring(g_i18n:formatVolume(totalOtherUsage, 0))
            })

            if payout ~= 0 then
                g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, scheme.farmId, payout))
            end

            if cumulativeMonth >= endMonth then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
            end
            return report
        end
    },

    [RTSchemeIds.CROP_PROMOTION] = {
        id = RTSchemeIds.CROP_PROMOTION,
        name = "rt_scheme_crop_promotion",
        report_description = "rt_scheme_report_desc_crop_promotion",
        duplicationKey = "CROP_PROMOTION",
        offerMonths = { 1, 2, 3 },
        autoTierTransition = false,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                bonusPerHa = 2200,
            },
            [RTPolicySystem.TIER.B] = {
                bonusPerHa = 1800,
            },
            [RTPolicySystem.TIER.C] = {
                bonusPerHa = 1500,
            },
            [RTPolicySystem.TIER.D] = {
                bonusPerHa = 1200,
            },
        },
        selectionProbability = 1,
        availabilityProbability = 1,
        descriptionFunction = function(schemeInfo, scheme)
            local fruit = g_fruitTypeManager.nameToFruitType[scheme.props['fruitType']]
            local title = fruit.fillType.title
            return string.format(g_i18n:getText("rt_scheme_desc_crop_promotion"), title)
        end,
        getNextEvaluationMonth = function(schemeInfo, scheme)
            return 12
        end,
        initialise = function(schemeInfo, scheme)
            -- Init of an available scheme, prior to selection by a farm

            local fruitTypes = {
                [FruitType.SUGARBEET] = "BEETHARVESTERS",
                [FruitType.POTATO] = "POTATOHARVESTING",
                [FruitType.PARSNIP] = "VEGETABLEHARVESTERS",
                [FruitType.GREENBEAN] = "GREENBEANHARVESTERS",
                [FruitType.PEA] = "PEAHARVESTERS",
                [FruitType.SPINACH] = "SPINACHHARVESTERS",
                [FruitType.CARROT] = "VEGETABLEHARVESTERS",
            }
            local chosenIndex = math.random(1, RedTape.tableCount(fruitTypes))
            local chosenCategory = nil
            local i = 1
            for fruitType, category in pairs(fruitTypes) do
                if i == chosenIndex then
                    local fruit = g_fruitTypeManager:getFruitTypeByIndex(fruitType)
                    scheme:setProp('fruitType', fruit.name)
                    chosenCategory = category
                    break
                end
                i = i + 1
            end

            local options = {}
            for _, item in pairs(g_storeManager:getItems()) do
                for i = 1, #item.categoryNames do
                    if chosenCategory == item.categoryNames[i] then
                        if not string.find(item.xmlFilename, "/pdlc/") then
                            local success = pcall(StoreItemUtil.loadSpecsFromXML, item)
                            if success and item.brandIndex ~= nil then
                                table.insert(options, item)
                            end
                        end
                    end
                end
            end
            local harvester = options[math.random(1, #options)]
            scheme:setProp('vehicleToSpawn1', harvester.xmlFilename)

            local skipCategories = { "WEIGHTS" }
            local spawnIndex = 2
            if harvester.specs ~= nil and harvester.specs.combinations ~= nil then
                local items = g_shopController:getItemsFromCombinations(harvester.specs.combinations)
                for _, item in pairs(items) do
                    local storeItem = item.storeItem
                    if not RedTape.tableHasValue(skipCategories, storeItem.categoryName) then
                        scheme:setProp('vehicleToSpawn' .. spawnIndex, storeItem.xmlFilename)
                        spawnIndex = spawnIndex + 1
                    end
                end
            end
        end,
        selected = function(schemeInfo, scheme, tier)
            -- Any action when applying the scheme to a farm, e.g. initial payout or equipment
            scheme:setProp('evaluationYear', RedTape.getActualYear())
            scheme:spawnVehicles()
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local evaluationYear = tonumber(scheme.props['evaluationYear'])
            local currentYear = RedTape.getActualYear()
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
            local cumulativeMonth = RedTape.getCumulativeMonth()
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]
            local farmId = scheme.farmId

            -- As we eval in december, we can end if the year has advanced
            if currentYear > evaluationYear then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, farmId))
                return
            end

            if currentMonth ~= 12 then
                return
            end

            local fruit = g_fruitTypeManager.nameToFruitType[scheme.props['fruitType']]

            local report = {}
            for _, farmland in pairs(g_farmlandManager.farmlands) do
                if farmland.farmId == farmId and farmland.field ~= nil then
                    local farmlandData = gatherer:getFarmlandData(farmland.id)
                    local wasFruitPresent = gatherer:wasFruitPresent(farmland.id, cumulativeMonth - 12,
                        cumulativeMonth, fruit.index)
                    if wasFruitPresent then
                        local bonusPerHa = schemeInfo.tiers[tier].bonusPerHa
                        local payout = farmlandData.areaHa * bonusPerHa * EconomyManager.getPriceMultiplier()
                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:formatMoney(payout, 0, true, true)
                        })
                        g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, farmId, payout))
                    else
                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:formatMoney(0, 0, true, true),
                        })
                    end
                end
            end

            return report
        end
    },

    [RTSchemeIds.TRACTOR_DEMO] = {
        id = RTSchemeIds.TRACTOR_DEMO,
        name = "rt_scheme_tractor_demo",
        report_description = "rt_scheme_report_desc_tractor_demo",
        duplicationKey = "DEMO",
        autoTierTransition = false,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                categories = { "TRACTORSS", "TRACTORSM", "TRACTORSM", "TRACTORSL", "TRACTORSL" },
                durationMonths = { 2, 2, 3 },
            },
            [RTPolicySystem.TIER.B] = {
                categories = { "TRACTORSS", "TRACTORSM", "TRACTORSM", "TRACTORSL" },
                durationMonths = { 1, 2, 2 },
            },
            [RTPolicySystem.TIER.C] = {
                categories = { "TRACTORSS", "TRACTORSS", "TRACTORSM" },
                durationMonths = { 1, 1, 2 },
            },
            [RTPolicySystem.TIER.D] = {
                categories = { "TRACTORSS" },
                durationMonths = { 1 },
            },
        },
        selectionProbability = 1,
        availabilityProbability = 0.2,
        descriptionFunction = function(schemeInfo, scheme)
            local storeItem = g_storeManager:getItemByXMLFilename(scheme.props["vehicleToSpawn1"])
            pcall(StoreItemUtil.loadSpecsFromXML, storeItem)

            local brand = g_brandManager.indexToBrand[storeItem.brandIndex].title
            local vehicleName = storeItem.name
            local suffix = ""

            if (tonumber(scheme.props['durationMonths']) or 1) > 1 then
                suffix = g_i18n:getText("rt_misc_month_plural_suffix")
            end

            return string.format(g_i18n:getText("rt_scheme_desc_tractor_demo"),
                brand,
                vehicleName,
                scheme.props['durationMonths'],
                suffix)
        end,
        getNextEvaluationMonth = function(schemeInfo, scheme)
            local m = tonumber(scheme.props['endMonth']) % 12
            return m == 0 and 12 or m
        end,
        getExpiryMonth = function(schemeInfo, scheme)
            return tonumber(scheme.props['expiryMonth'])
        end,
        initialise = function(schemeInfo, scheme)
            local tierInfo = schemeInfo.tiers[scheme.tier]
            local chosenCategory = tierInfo.categories[math.random(1, #tierInfo.categories)]

            local options = {}
            for _, item in pairs(g_storeManager:getItems()) do
                for i = 1, #item.categoryNames do
                    if chosenCategory == item.categoryNames[i] then
                        if not string.find(item.xmlFilename, "/pdlc/") then
                            local success = pcall(StoreItemUtil.loadSpecsFromXML, item)
                            if success then
                                table.insert(options, item)
                            end
                        end
                    end
                end
            end
            local chosenItem = options[math.random(1, #options)]
            scheme:setProp('vehicleToSpawn1', chosenItem.xmlFilename)

            local chosenDuration = tierInfo.durationMonths[math.random(1, #tierInfo.durationMonths)]
            scheme:setProp('durationMonths', chosenDuration)
            scheme:setProp('expiryMonth', RedTape.getCumulativeMonth() + math.random(1, 2))
        end,
        selected = function(schemeInfo, scheme, tier)
            -- Any action when applying the scheme to a farm, e.g. initial payout or equipment
            local endMonth = RedTape.getCumulativeMonth() + tonumber(scheme.props['durationMonths'])
            scheme:setProp('endMonth', endMonth)
            scheme:spawnVehicles()
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local endMonth = tonumber(scheme.props['endMonth'])
            local cumulativeMonth = RedTape.getCumulativeMonth()

            if cumulativeMonth >= endMonth then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
            end
            return {}
        end,
        action = {
            description = function(schemeInfo, scheme)
                if #scheme.vehicles == 0 then return nil end
                local totalPrice = 0
                for _, vehicle in pairs(scheme.vehicles) do
                    totalPrice = totalPrice + vehicle:getPrice()
                end
                local discountedPrice = math.floor(totalPrice * (0.75 + math.random() * 0.10))
                scheme:setProp('buyPrice', discountedPrice)
                return string.format(g_i18n:getText("rt_action_buy_demo_vehicle"),
                    g_i18n:formatMoney(discountedPrice, 0, true, true))
            end,
            confirm = function(schemeInfo, scheme, price)
                if price <= 0 or #scheme.vehicles == 0 then return end

                if g_currentMission:getIsServer() then
                    g_currentMission:addMoneyChange(-price, scheme.farmId, MoneyType.SHOP_VEHICLE_BUY, true)
                end
                g_farmManager:getFarmById(scheme.farmId):changeBalance(-price, MoneyType.SHOP_VEHICLE_BUY)

                for _, vehicle in pairs(scheme.vehicles) do
                    vehicle.propertyState = VehiclePropertyState.OWNED
                    vehicle:setOwnerFarmId(scheme.farmId)
                end
                scheme.vehicles = {}
                scheme.spawnedVehicles = false

                RTScheme.expireMatchingAvailableScheme(scheme)
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
            end,
        },
    },

    [RTSchemeIds.WINTER_COVER_CROPS] = {
        id = RTSchemeIds.WINTER_COVER_CROPS,
        name = "rt_scheme_winter_cover_crops",
        description = "rt_scheme_desc_winter_cover_crops",
        report_description = "rt_scheme_report_desc_winter_cover_crops",
        duplicationKey = "WINTER_COVER_CROPS",
        offerMonths = { 3, 4, 5, 6 },
        autoTierTransition = true,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                bonusPerHa = 800,
            },
            [RTPolicySystem.TIER.B] = {
                bonusPerHa = 650,
            },
            [RTPolicySystem.TIER.C] = {
                bonusPerHa = 500,
            },
            [RTPolicySystem.TIER.D] = {
                bonusPerHa = 400,
            },
        },
        selectionProbability = 1,
        availabilityProbability = 1,
        getNextEvaluationMonth = function(schemeInfo, scheme)
            return 3 -- March
        end,
        initialise = function(schemeInfo, scheme)
        end,
        selected = function(schemeInfo, scheme, tier)
            local cumulativeMonth = RedTape.getCumulativeMonth()
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
            local nextApril = cumulativeMonth + (12 - currentMonth + 4)

            scheme:setProp('endMonth', nextApril)
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]
            local farmId = scheme.farmId
            local cumulativeMonth = RedTape.getCumulativeMonth()

            if cumulativeMonth >= tonumber(scheme.props['endMonth']) then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
                return
            end

            if currentMonth ~= 3 then return end -- Only evaluate in March

            local report = {}
            local totalReward = 0
            for _, farmland in pairs(g_farmlandManager.farmlands) do
                if farmland.farmId == farmId then
                    local farmlandData = gatherer:getFarmlandData(farmland.id)

                    local radishName = g_fruitTypeManager:getFruitTypeByIndex(FruitType.OILSEEDRADISH).name
                    local febFruit = farmlandData.fruitHistory[cumulativeMonth - 1]
                    local janFruit = farmlandData.fruitHistory[cumulativeMonth - 2]
                    local decFruit = farmlandData.fruitHistory[cumulativeMonth - 3]

                    local hadCoverCrop = febFruit ~= nil and febFruit.name == radishName and
                        janFruit ~= nil and janFruit.name == radishName and
                        decFruit ~= nil and decFruit.name == radishName

                    if hadCoverCrop then
                        local bonusPerHa = schemeInfo.tiers[tier].bonusPerHa
                        local payout = farmlandData.areaHa * bonusPerHa * EconomyManager.getPriceMultiplier()
                        totalReward = totalReward + payout
                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:formatMoney(payout, 0, true, true)
                        })
                    else
                        table.insert(report, {
                            cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                            cell2 = g_i18n:formatMoney(0, 0, true, true),
                        })
                    end
                end
            end

            if totalReward > 0 then
                g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, farmId, totalReward))
            end

            return report
        end

    },

    [RTSchemeIds.ROAD_SNOW_CLEARING] = {
        id = RTSchemeIds.ROAD_SNOW_CLEARING,
        name = "rt_scheme_road_snow_clearing",
        report_description = "rt_scheme_report_desc_road_snow_clearing",
        duplicationKey = "ROAD_SNOW_CLEARING",
        autoTierTransition = false,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                bonusPerBlock = 3.8,
            },
            [RTPolicySystem.TIER.B] = {
                bonusPerBlock = 3.5,
            },
            [RTPolicySystem.TIER.C] = {
                bonusPerBlock = 3.2,
            },
            [RTPolicySystem.TIER.D] = {
                bonusPerBlock = 2.9,
            },
        },
        selectionProbability = 1,
        availabilityProbability = 0,
        maxKMH = 21,
        descriptionFunction = function(schemeInfo, scheme)
            return string.format(g_i18n:getText("rt_scheme_desc_road_snow_clearing"),
                string.format("%1d", g_i18n:getSpeed(schemeInfo.maxKMH)), g_i18n:getSpeedMeasuringUnit())
        end,
        initialise = function(schemeInfo, scheme)
            local chosenCategory = "WINTEREQUIPMENT"
            local options = {}
            for _, item in pairs(g_storeManager:getItems()) do
                for i = 1, #item.categoryNames do
                    if chosenCategory == item.categoryNames[i] then
                        local success = pcall(StoreItemUtil.loadSpecsFromXML, item)
                        if success and item.specs and item.specs.fillTypes and item.specs.fillTypes.fillTypeNames == "roadsalt" then
                            if not string.find(item.xmlFilename, "/pdlc/") then
                                table.insert(options, item)
                            end
                        end
                    end
                end
            end
            local chosenItem = options[math.random(1, #options)]
            scheme:setProp('vehicleToSpawn1', chosenItem.xmlFilename)
        end,
        selected = function(schemeInfo, scheme, tier)
            scheme:spawnVehicles()
        end,
        evaluate = function(schemeInfo, scheme, tier)
        end,
        onSnowEnded = function(schemeInfo, scheme, tier)
            local tierInfo = schemeInfo.tiers[tier]
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMS]
            local farmData = gatherer:getFarmData(scheme.farmId)
            local clearedBlocks = farmData.saltCount or 0
            local payout = clearedBlocks * tierInfo.bonusPerBlock * EconomyManager.getPriceMultiplier()

            if payout ~= 0 then
                g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, scheme.farmId, payout))
            end
            g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
        end
    },

    [RTSchemeIds.BRAND_DEMO] = {
        id = RTSchemeIds.BRAND_DEMO,
        name = "rt_scheme_brand_demo",
        report_description = "rt_scheme_report_desc_brand_demo",
        duplicationKey = "DEMO",
        autoTierTransition = false,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                brands = { "ANDERSONGROUP", "BEDNAR", "DALBO", "EINBOECK", "FARESIN", "FARMTECH", "FLIEGL", "GOEWEIL",
                    "HAWE", "HORSCH", "KAWECO", "KINZE", "KNOCHE", "KRONE", "KUBOTA", "KUHN",
                    "KVERNELAND", "LEMKEN", "MANITOU", "PFANZELT", "POETTINGER", "SALEK", "SAMASZ", "SAMSONAGRO",
                    "VAEDERSTAD", "MASSEYFERGUSON", "NEWHOLLAND", "JOHNDEERE", "FENDT" },
                durationMonths = { 2, 2, 3 },
                itemCounts = { 2, 3, 3 }
            },
            [RTPolicySystem.TIER.B] = {
                brands = { "ANDERSONGROUP", "BEDNAR", "DALBO", "EINBOECK", "FARESIN", "FARMTECH", "FLIEGL", "GOEWEIL",
                    "HAWE", "HORSCH", "KAWECO", "KINZE", "KNOCHE", "KRONE", "KUBOTA", "KUHN",
                    "KVERNELAND", "LEMKEN", "MANITOU", "PFANZELT", "POETTINGER", "SALEK", "SAMASZ", "SAMSONAGRO",
                    "VAEDERSTAD", "NEWHOLLAND", "JOHNDEERE" },
                durationMonths = { 1, 2, 2, },
                itemCounts = { 2, 2, 3 }
            },
            [RTPolicySystem.TIER.C] = {
                brands = { "ANDERSONGROUP", "BEDNAR", "DALBO", "EINBOECK", "FARESIN", "FARMTECH", "FLIEGL", "GOEWEIL",
                    "HAWE", "HORSCH", "KAWECO", "KINZE", "KNOCHE", "KRONE", "KUBOTA", "KUHN",
                    "KVERNELAND", "LEMKEN", "MANITOU", "PFANZELT", "POETTINGER", "SALEK", "SAMASZ", "SAMSONAGRO",
                    "VAEDERSTAD" },
                durationMonths = { 1, 1, 2 },
                itemCounts = { 2 }
            },
            [RTPolicySystem.TIER.D] = {
                brands = { "BEDNAR", "DALBO", "EINBOECK", "FARESIN", "FARMTECH", "FLIEGL", "GOEWEIL",
                    "HAWE", "KAWECO", "KINZE", "KNOCHE", "KRONE", "KUBOTA", "LEMKEN", "MANITOU", "PFANZELT", "POETTINGER",
                    "SALEK", "SAMSONAGRO", "VAEDERSTAD" },
                durationMonths = { 1 },
                itemCounts = { 1, 2 },
            },
        },
        selectionProbability = 1,
        availabilityProbability = 0.1,
        descriptionFunction = function(schemeInfo, scheme)
            local storeItem = g_storeManager:getItemByXMLFilename(scheme.props["vehicleToSpawn1"])
            pcall(StoreItemUtil.loadSpecsFromXML, storeItem)

            local brand = g_brandManager.indexToBrand[storeItem.brandIndex].title
            local suffix = ""

            if (tonumber(scheme.props['durationMonths']) or 1) > 1 then
                suffix = g_i18n:getText("rt_misc_month_plural_suffix")
            end

            return string.format(g_i18n:getText("rt_scheme_desc_brand_demo"),
                brand,
                scheme.props['durationMonths'],
                suffix)
        end,
        getNextEvaluationMonth = function(schemeInfo, scheme)
            local m = tonumber(scheme.props['endMonth']) % 12
            return m == 0 and 12 or m
        end,
        getExpiryMonth = function(schemeInfo, scheme)
            return tonumber(scheme.props['expiryMonth'])
        end,
        initialise = function(schemeInfo, scheme)
            local tierInfo = schemeInfo.tiers[scheme.tier]
            local chosenBrand = tierInfo.brands[math.random(1, #tierInfo.brands)]
            local chosenBrandIndex = g_brandManager.nameToBrand[chosenBrand].index
            local chosenDuration = tierInfo.durationMonths[math.random(1, #tierInfo.durationMonths)]
            local maxItems = tierInfo.itemCounts[math.random(1, #tierInfo.itemCounts)]
            local skipCategories = { "FRONTLOADERS" }

            local options = {}
            for _, item in pairs(g_storeManager:getItems()) do
                local success = pcall(StoreItemUtil.loadSpecsFromXML, item)
                if success and item.brandIndex == chosenBrandIndex then
                    local skip = false
                    for _, name in pairs(item.categoryNames) do
                        if RedTape.tableHasValue(skipCategories, name) then
                            skip = true
                        end
                    end
                    if not skip and not string.find(item.xmlFilename, "/pdlc/") then
                        table.insert(options, item)
                    end
                end
            end

            local pickedItems = {}
            for i = 1, math.min(maxItems, #options) do
                local pickedItem
                while true do
                    pickedItem = options[math.random(1, #options)]
                    if not RedTape.tableHasValue(pickedItems, pickedItem) then
                        table.insert(pickedItems, pickedItem)
                        scheme:setProp('vehicleToSpawn' .. i, pickedItem.xmlFilename)
                        break
                    end
                end
            end

            scheme:setProp('durationMonths', chosenDuration)
            scheme:setProp('expiryMonth', RedTape.getCumulativeMonth() + math.random(1, 2))
        end,
        selected = function(schemeInfo, scheme, tier)
            -- Any action when applying the scheme to a farm, e.g. initial payout or equipment
            local endMonth = RedTape.getCumulativeMonth() + tonumber(scheme.props['durationMonths'])
            scheme:setProp('endMonth', endMonth)
            scheme:spawnVehicles()
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local endMonth = tonumber(scheme.props['endMonth'])
            local cumulativeMonth = RedTape.getCumulativeMonth()

            if cumulativeMonth >= endMonth then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
            end
            return {}
        end,
        action = {
            description = function(schemeInfo, scheme)
                if #scheme.vehicles == 0 then return nil end
                local totalPrice = 0
                for _, vehicle in pairs(scheme.vehicles) do
                    totalPrice = totalPrice + vehicle:getPrice()
                end
                local discountedPrice = math.floor(totalPrice * (0.75 + math.random() * 0.10))
                scheme:setProp('buyPrice', discountedPrice)
                local vehicleCount = #scheme.vehicles
                local key = vehicleCount == 1 and "rt_action_buy_demo_vehicle" or "rt_action_buy_demo_vehicles"
                return string.format(g_i18n:getText(key),
                    g_i18n:formatMoney(discountedPrice, 0, true, true))
            end,
            confirm = function(schemeInfo, scheme, price)
                if price <= 0 or #scheme.vehicles == 0 then return end

                if g_currentMission:getIsServer() then
                    g_currentMission:addMoneyChange(-price, scheme.farmId, MoneyType.SHOP_VEHICLE_BUY, true)
                end
                g_farmManager:getFarmById(scheme.farmId):changeBalance(-price, MoneyType.SHOP_VEHICLE_BUY)

                for _, vehicle in pairs(scheme.vehicles) do
                    vehicle.propertyState = VehiclePropertyState.OWNED
                    vehicle:setOwnerFarmId(scheme.farmId)
                end
                scheme.vehicles = {}
                scheme.spawnedVehicles = false

                RTScheme.expireMatchingAvailableScheme(scheme)
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, scheme.farmId))
            end,
        },
    },

    [RTSchemeIds.SET_ASIDE] = {
        id = RTSchemeIds.SET_ASIDE,
        name = "rt_scheme_set_aside",
        description = "rt_scheme_desc_set_aside",
        report_description = "rt_scheme_report_desc_set_aside",
        duplicationKey = "LEAVE_FALLOW",
        offerMonths = { 1, 2 },
        autoTierTransition = false,
        tiers = {
            [RTPolicySystem.TIER.A] = {
                bonusPerHa = 1800,
            },
            [RTPolicySystem.TIER.B] = {
                bonusPerHa = 1500,
            },
            [RTPolicySystem.TIER.C] = {
                bonusPerHa = 1200,
            },
            [RTPolicySystem.TIER.D] = {
                bonusPerHa = 1000,
            },
        },
        requiredFallowMonths = 9,
        requiredFallowHa = 3,
        selectionProbability = 1,
        availabilityProbability = 1,
        descriptionFunction = function(schemeInfo, scheme)
            return string.format(g_i18n:getText("rt_scheme_desc_set_aside"), schemeInfo.requiredFallowMonths,
                g_i18n:formatArea(schemeInfo.requiredFallowHa, 2))
        end,
        getNextEvaluationMonth = function(schemeInfo, scheme)
            return 12
        end,
        initialise = function(schemeInfo, scheme)
        end,
        selected = function(schemeInfo, scheme, tier)
            local cumulativeMonth = RedTape.getCumulativeMonth()
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
            local nextJan = cumulativeMonth + (12 - currentMonth + 1)
            scheme:setProp('endMonth', nextJan)
        end,
        evaluate = function(schemeInfo, scheme, tier)
            local ig = g_currentMission.RedTape.InfoGatherer
            local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]
            local farmId = scheme.farmId
            local currentMonth = RedTape.periodToMonth(g_currentMission.environment.currentPeriod)
            local cumulativeMonth = RedTape.getCumulativeMonth()

            -- End in January, allowing player to see report in December
            if cumulativeMonth >= tonumber(scheme.props['endMonth']) then
                g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, farmId))
                return
            end

            if currentMonth ~= 12 then
                return
            end

            local report = {}
            local payout = 0
            local eligibleHa = 0
            for _, farmland in pairs(g_farmlandManager.farmlands) do
                if farmland.farmId == farmId then
                    local farmlandData = gatherer:getFarmlandData(farmland.id)
                    local bonus = schemeInfo.tiers[tier].bonusPerHa
                    local reward = 0
                    if not gatherer:hasRecordedFruit(farmland.id, cumulativeMonth - 9, cumulativeMonth, true) then
                        reward = farmlandData.areaHa * bonus * EconomyManager.getPriceMultiplier()
                        eligibleHa = eligibleHa + farmlandData.areaHa
                    end
                    table.insert(report, {
                        cell1 = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                        cell2 = g_i18n:formatArea(farmlandData.areaHa, 2),
                        cell3 = g_i18n:formatMoney(reward, 0, true, true)
                    })
                    payout = payout + reward
                end
            end

            if eligibleHa > schemeInfo.requiredFallowHa then
                table.insert(report, {
                    cell1 = g_i18n:getText("rt_report_name_additional_tax_benefit"),
                    cell2 = g_i18n:getText("rt_report_value_true")
                })

                local cumulativeMonth = RedTape.getCumulativeMonth()
                local startMonth = cumulativeMonth + 4
                local endMonth = startMonth + 11
                g_client:getServerConnection():sendEvent(RTTaxRateBenefitEvent.new(scheme.farmId, startMonth, endMonth,
                    "harvestIncome", 0.25))
            else
                table.insert(report, {
                    cell1 = g_i18n:getText("rt_report_name_additional_tax_benefit"),
                    cell2 = g_i18n:getText("rt_report_value_false")
                })
            end

            if payout ~= 0 then
                g_client:getServerConnection():sendEvent(RTSchemePayoutEvent.new(scheme, scheme.farmId, payout))
            end

            return report
        end
    },

}
