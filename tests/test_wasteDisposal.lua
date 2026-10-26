-- Waste Disposal: other mods report waste oil and coolant disposals through RedTapeAPI
-- (src/RedTapeAPI.lua, docs/RedTapeAPI.md), WasteGatherer keeps this month's litres, and the
-- policy rewards delivery, ignores collection and warns then fines for discarding.

local function setup()
    local world = stubs.install()
    world.policy = RTPolicy.new()
    world.policy.policyIndex = RTPolicyIds.WASTE_DISPOSAL
    RedTapeAPI.registerWasteSource("TestMod")
    return world
end

local function policyInfo()
    return RTPolicies[RTPolicyIds.WASTE_DISPOSAL]
end

local function evaluate(world, farmId, tier)
    world.events = {}
    local info = policyInfo()
    return info.evaluate(info, world.policy, farmId or 1, tier or RTPolicySystem.TIER.C)
end

local function record(farmId, wasteType, liters, method)
    return RedTapeAPI.recordWasteDisposal(farmId, wasteType, liters, method)
end

local function pointsSent(world)
    local total = 0
    for _, event in ipairs(stubs.eventsOfKind(world, "points")) do
        total = total + event.points
    end
    return total
end

local function fineSent(world)
    local total = 0
    for _, event in ipairs(stubs.eventsOfKind(world, "fine")) do
        total = total + event.amount
    end
    return total
end

local function reportRow(report, cell1)
    for _, row in ipairs(report) do
        if row.cell1 == cell1 then
            return row
        end
    end
    return nil
end

local function activate(world)
    table.insert(world.policySystem.policies, world.policy)
end

-- getInfo -------------------------------------------------------------------

test("getInfo announces version 1 with waste disposal, its waste types and methods", function()
    setup()
    local info = RedTapeAPI.getInfo()
    assertEquals(info.version, 1, "version")
    assertEquals(info.features.wasteDisposal, true, "feature")
    assertEquals(table.concat(info.wasteTypes, ","), "oil,coolant", "waste types")
    assertEquals(table.concat(info.disposalMethods, ","), "delivered,collected,discarded", "methods")
end)

test("changing what getInfo returned doesn't change the API", function()
    setup()
    local info = RedTapeAPI.getInfo()
    table.insert(info.wasteTypes, "battery")
    info.disposalMethods[1] = "burnt"
    assertEquals(#RedTapeAPI.getInfo().wasteTypes, 2, "waste types")
    assertEquals(RedTapeAPI.getInfo().disposalMethods[1], "delivered", "methods")
    assertEquals(select(2, record(1, "battery", 10, "delivered")), "invalidWasteType", "battery")
end)

-- recordWasteDisposal -------------------------------------------------------

test("disposals add up per farm, waste type and method", function()
    local world = setup()
    assertEquals(record(1, "oil", 120, "delivered"), true, "first")
    record(1, "oil", 30.5, "delivered")
    record(1, "coolant", 40, "discarded")
    record(2, "oil", 400, "collected")

    local farm1 = world.wasteGatherer:getFarmData(1)
    assertNear(farm1.oil.delivered, 150.5, 0.001, "farm 1 oil delivered")
    assertEquals(farm1.coolant.discarded, 40, "farm 1 coolant discarded")
    assertEquals(farm1.oil.collected, 0, "farm 1 oil collected")
    assertEquals(world.wasteGatherer:getFarmData(2).oil.collected, 400, "farm 2")
    assertEquals(world.wasteGatherer:getMethodTotal(1, "delivered"), 150.5, "total")
end)

test("bad calls are refused with a reason, logged, and record nothing", function()
    local world = setup()
    local cases = {
        { { 0, "oil", 10, "delivered" }, "invalidFarm" },
        { { -1, "oil", 10, "delivered" }, "invalidFarm" },
        { { 1.5, "oil", 10, "delivered" }, "invalidFarm" },
        { { "1", "oil", 10, "delivered" }, "invalidFarm" },
        { { nil, "oil", 10, "delivered" }, "invalidFarm" },
        { { 1, "OIL", 10, "delivered" }, "invalidWasteType" },
        { { 1, nil, 10, "delivered" }, "invalidWasteType" },
        { { 1, "oil", 0, "delivered" }, "invalidLiters" },
        { { 1, "oil", -5, "delivered" }, "invalidLiters" },
        { { 1, "oil", 0 / 0, "delivered" }, "invalidLiters" },
        { { 1, "oil", math.huge, "delivered" }, "invalidLiters" },
        { { 1, "oil", "10", "delivered" }, "invalidLiters" },
        { { 1, "oil", 10, "dumped" }, "invalidMethod" },
        { { 1, "oil", 10, nil }, "invalidMethod" },
    }
    for i, case in ipairs(cases) do
        local args = case[1]
        local ok, reason = record(args[1], args[2], args[3], args[4])
        assertEquals(ok, false, "case " .. i)
        assertEquals(reason, case[2], "case " .. i .. " reason")
    end
    assertEquals(#world.logs, #cases, "one warning per refusal")
    assertEquals(world.wasteGatherer.data[1] == nil or world.wasteGatherer:getMethodTotal(1, "delivered") == 0, true,
        "nothing recorded")
end)

test("only the server records disposals", function()
    local world = setup()
    g_currentMission.getIsServer = function() return false end
    local ok, reason = record(1, "oil", 10, "delivered")
    assertEquals(ok, false, "ok")
    assertEquals(reason, "notServer", "reason")
    assertEquals(world.wasteGatherer.data[1], nil, "nothing recorded")
end)

test("a call before Red Tape has loaded is refused rather than throwing", function()
    setup()
    g_currentMission.RedTape = nil
    assertEquals(select(2, record(1, "oil", 10, "delivered")), "notReady", "no RedTape")
end)

-- Waste sources -------------------------------------------------------------

test("waste sources register once, and can be withdrawn", function()
    setup()
    assertEquals(RedTapeAPI.hasWasteSource(), true, "registered in setup")
    assertEquals(RedTapeAPI.registerWasteSource("TestMod"), true, "twice")
    assertEquals(RedTapeAPI.unregisterWasteSource("TestMod"), true, "withdrawn")
    assertEquals(RedTapeAPI.hasWasteSource(), false, "none left")
    assertEquals(RedTapeAPI.unregisterWasteSource("TestMod"), false, "withdrawn twice")
end)

test("a waste source needs a name", function()
    local world = stubs.install()
    local ok, reason = RedTapeAPI.registerWasteSource("")
    assertEquals(ok, false, "empty")
    assertEquals(reason, "invalidSourceId", "reason")
    assertEquals(RedTapeAPI.registerWasteSource(nil), false, "nil")
    assertEquals(RedTapeAPI.hasWasteSource(), false, "nothing registered")
    assertEquals(#world.logs, 2, "logged")
end)

-- isWasteDisposalRegulated --------------------------------------------------

test("waste disposal is regulated only while the policy is active and enforced", function()
    local world = setup()
    local settings = g_currentMission.RedTape.settings
    settings.policiesAndSchemesEnabled = true
    assertEquals(RedTapeAPI.isWasteDisposalRegulated(1), false, "not active")

    activate(world)
    assertEquals(RedTapeAPI.isWasteDisposalRegulated(1), true, "active")
    assertEquals(RedTapeAPI.isWasteDisposalRegulated(), true, "without a farm")

    settings[RedTape.policySettingIdByPolicyId[RTPolicyIds.WASTE_DISPOSAL]] = false
    assertEquals(RedTapeAPI.isWasteDisposalRegulated(1), false, "policy switched off")

    settings[RedTape.policySettingIdByPolicyId[RTPolicyIds.WASTE_DISPOSAL]] = true
    settings.policiesAndSchemesEnabled = false
    assertEquals(RedTapeAPI.isWasteDisposalRegulated(1), false, "policies switched off")
end)

test("isWasteDisposalRegulated is false before Red Tape has loaded", function()
    setup()
    g_currentMission.RedTape = nil
    assertEquals(RedTapeAPI.isWasteDisposalRegulated(1), false, "no RedTape")
end)

-- Issuing -------------------------------------------------------------------

local function onlyWasteDisposalFree(world)
    for id in pairs(RTPolicies) do
        if id ~= RTPolicyIds.WASTE_DISPOSAL then
            table.insert(world.policySystem.policies, { policyIndex = id })
        end
    end
end

test("the policy is only issued while a mod reports waste disposals", function()
    local world = setup()
    onlyWasteDisposalFree(world)
    assertEquals(world.policySystem:getNextPolicyIndex(), RTPolicyIds.WASTE_DISPOSAL, "with a source")

    RedTapeAPI.unregisterWasteSource("TestMod")
    assertEquals(world.policySystem:getNextPolicyIndex(), nil, "without a source")
end)

test("it gets its own enforcement toggle", function()
    local world = setup()
    local settingId = RedTape.policySettingIdByPolicyId[RTPolicyIds.WASTE_DISPOSAL]
    assertEquals(settingId, "policyEnabled_WASTE_DISPOSAL", "setting id")
    assertEquals(RedTape.SETTINGS[settingId].title, g_i18n:getText("rt_policy_waste_disposal"), "setting title")

    onlyWasteDisposalFree(world)
    g_currentMission.RedTape.settings[settingId] = false
    assertEquals(world.policySystem:getNextPolicyIndex(), nil, "issued while switched off")
end)

-- Evaluation ----------------------------------------------------------------

test("a month with deliveries and nothing discarded earns the reward", function()
    local world = setup()
    record(1, "oil", 200, "delivered")
    record(1, "coolant", 50, "collected")
    evaluate(world)
    assertEquals(pointsSent(world), policyInfo().periodicReward, "points")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 1, "warnings cleared")
    assertEquals(#stubs.eventsOfKind(world, "warning") + #stubs.eventsOfKind(world, "fine"), 0, "no warning or fine")
end)

test("collection alone is legal but earns nothing, unless the farm is in tier D", function()
    local world = setup()
    record(1, "oil", 200, "collected")
    evaluate(world)
    assertEquals(pointsSent(world), 0, "tier C")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 1, "warnings cleared")

    evaluate(world, 1, RTPolicySystem.TIER.D)
    assertEquals(pointsSent(world), policyInfo().periodicReward, "tier D")
end)

test("a month with no disposals at all earns nothing above tier D", function()
    local world = setup()
    evaluate(world)
    assertEquals(pointsSent(world), 0, "points")
end)

test("a first small discard is a warning only, and still loses points", function()
    local world = setup()
    record(1, "oil", 100, "delivered")
    record(1, "coolant", 150, "discarded")
    evaluate(world)
    assertEquals(#stubs.eventsOfKind(world, "warning"), 1, "warning")
    assertEquals(#stubs.eventsOfKind(world, "fine"), 0, "no fine yet")
    -- -5 per 100 l, rounded away from zero
    assertEquals(pointsSent(world), -8, "points")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 0, "warnings kept")
end)

test("discarding again after a warning is fined per litre", function()
    local world = setup()
    table.insert(world.policySystem.warnings,
        { farmId = 1, policyIndex = RTPolicyIds.WASTE_DISPOSAL, warningCount = 1 })
    record(1, "oil", 60, "discarded")
    record(1, "coolant", 40.2, "discarded")
    evaluate(world)
    assertEquals(fineSent(world), math.ceil(100.2 * policyInfo().finePerLiter), "fine")
end)

test("discarding more than the threshold in a month is fined straight away", function()
    local world = setup()
    record(1, "oil", 401, "discarded")
    evaluate(world)
    assertEquals(#stubs.eventsOfKind(world, "warning"), 0, "no warning first")
    assertEquals(fineSent(world), 802, "fine")
    assertEquals(pointsSent(world), -21, "points")
end)

test("discarding exactly the threshold is still warned first", function()
    local world = setup()
    record(1, "oil", 400, "discarded")
    evaluate(world)
    assertEquals(#stubs.eventsOfKind(world, "warning"), 1, "warning")
    assertEquals(fineSent(world), 0, "no fine")
end)

test("each farm is judged on its own disposals", function()
    local world = setup()
    record(2, "oil", 500, "discarded")
    record(1, "oil", 50, "delivered")
    evaluate(world, 1)
    assertEquals(pointsSent(world), policyInfo().periodicReward, "farm 1")
    assertEquals(fineSent(world), 0, "farm 1 not fined")
end)

test("the report lists litres per method for oil and coolant, then points", function()
    local world = setup()
    record(1, "oil", 120, "delivered")
    record(1, "coolant", 30, "collected")
    local report = evaluate(world)

    assertEquals(#report, 5, "rows")
    assertEquals(report[1].cell2, g_i18n:getText("rt_report_name_waste_oil"), "header oil")
    assertEquals(report[1].cell3, g_i18n:getText("rt_report_name_waste_coolant"), "header coolant")
    local delivered = reportRow(report, g_i18n:getText("rt_report_name_waste_delivered"))
    assertEquals(delivered.cell2, "120 l", "oil delivered")
    assertEquals(delivered.cell3, "0 l", "coolant delivered")
    assertEquals(reportRow(report, g_i18n:getText("rt_report_name_waste_collected")).cell3, "30 l", "coolant collected")
    assertEquals(reportRow(report, g_i18n:getText("rt_report_name_waste_discarded")).cell2, "0 l", "discarded")
    assertEquals(report[5].cell1, g_i18n:getText("rt_report_name_points"), "last row")
    assertEquals(report[5].cell2, policyInfo().periodicReward, "points row")
end)

test("an active policy with no waste source left says so and judges nothing", function()
    local world = setup()
    record(1, "oil", 900, "discarded")
    RedTapeAPI.unregisterWasteSource("TestMod")
    local report = evaluate(world)
    assertEquals(#report, 1, "rows")
    assertEquals(report[1].cell2, g_i18n:getText("rt_report_value_waste_no_source"), "note")
    assertEquals(pointsSent(world) + fineSent(world), 0, "points and fines")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 1, "warnings cleared")
end)

-- Month end and saving ------------------------------------------------------

test("month end clears the month's disposals", function()
    local world = setup()
    record(1, "oil", 900, "discarded")
    world.wasteGatherer:resetMonthlyData()
    evaluate(world)
    assertEquals(fineSent(world) + #stubs.eventsOfKind(world, "warning"), 0, "nothing carried over")
end)

test("this month's disposals survive a save and load", function()
    local world = setup()
    record(1, "oil", 120.25, "delivered")
    record(3, "coolant", 40, "discarded")
    local xmlFile = {}
    world.wasteGatherer:saveToXmlFile(xmlFile, "RedTape.infoGatherer.gatherers")

    local loaded = WasteGatherer.new()
    loaded:loadFromXMLFile(xmlFile, "RedTape.infoGatherer.gatherers")
    assertNear(loaded:getFarmData(1).oil.delivered, 120.25, 0.001, "farm 1")
    assertEquals(loaded:getFarmData(3).coolant.discarded, 40, "farm 3")
    assertEquals(loaded:getMethodTotal(1, "discarded"), 0, "nothing else")
    assertEquals(#world.logs, 0, "no warnings")
end)

test("a saved disposal Red Tape doesn't understand is dropped with a warning", function()
    local world = setup()
    local key = "RedTape.infoGatherer.gatherers.wasteGatherer"
    local xmlFile = {
        [key .. ".disposal(0)#farmId"] = 1,
        [key .. ".disposal(0)#wasteType"] = "battery",
        [key .. ".disposal(0)#method"] = "delivered",
        [key .. ".disposal(0)#liters"] = 10,
        [key .. ".disposal(1)#farmId"] = 1,
        [key .. ".disposal(1)#wasteType"] = "oil",
        [key .. ".disposal(1)#method"] = "delivered",
        [key .. ".disposal(2)#farmId"] = 1,
        [key .. ".disposal(2)#wasteType"] = "oil",
        [key .. ".disposal(2)#method"] = "discarded",
        [key .. ".disposal(2)#liters"] = 25,
    }
    local loaded = WasteGatherer.new()
    loaded:loadFromXMLFile(xmlFile, "RedTape.infoGatherer.gatherers")
    assertEquals(loaded:getMethodTotal(1, "delivered"), 0, "bad entries dropped")
    assertEquals(loaded:getFarmData(1).oil.discarded, 25, "good entry kept")
    assertEquals(#world.logs, 2, "one warning per dropped entry")
end)
