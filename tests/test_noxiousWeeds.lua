-- Noxious Weed Control (P07): FarmlandGatherer samples each field at month
-- end and counts the months in a row it has been overrun with live weeds;
-- the policy warns at 2 months and fines per ha from 3. Weed states are
-- vanilla's (see stubs.WEED).

local WEED = stubs.WEED

local function setup()
    local world = stubs.install()
    world.policy = RTPolicy.new()
    world.policy.policyIndex = RTPolicyIds.NOXIOUS_WEEDS
    return world
end

local function policyInfo()
    return RTPolicies[RTPolicyIds.NOXIOUS_WEEDS]
end

-- Runs the policy's evaluation on its own, with a fresh event list
local function evaluate(world, farmId, tier)
    world.events = {}
    local info = policyInfo()
    return info.evaluate(info, world.policy, farmId or 1, tier or RTPolicySystem.TIER.C)
end

-- A month end: the gatherer samples, then the policy evaluates
local function monthEnd(world, farmId, tier)
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    return evaluate(world, farmId, tier)
end

local function runOf(world, field)
    return world.farmlandGatherer:getFarmlandData(field.id).highWeedMonths
end

local function sample(field)
    return FarmlandGatherer.sampleFieldWeeds(field.farmland.field, FarmlandGatherer.getWeedSkipFruits())
end

local function reportRow(report, cell1)
    for _, row in ipairs(report) do
        if row.cell1 == cell1 then
            return row
        end
    end
    return nil
end

local function farmlandName(id)
    return string.format(g_i18n:getText("rt_report_name_farmland"), id)
end

local function pointsSent(world)
    local total = 0
    for _, event in ipairs(stubs.eventsOfKind(world, "points")) do
        total = total + event.points
    end
    return total
end

-- Sampling --------------------------------------------------------------

test("large and medium weeds under a growing crop are overrun", function()
    local world = setup()
    local large = stubs.addField(world, { fruit = "WHEAT", weedState = WEED.LARGE })
    local medium = stubs.addField(world, { fruit = "WHEAT", weedState = WEED.MEDIUM })

    local judged, overrun = sample(large)
    assertTrue(judged, "large judged")
    assertTrue(overrun, "large overrun")
    judged, overrun = sample(medium)
    assertTrue(judged and overrun, "medium overrun")
end)

test("small weeds, partly weeded and no weeds are not overrun", function()
    local world = setup()
    for _, state in ipairs({ 0, 1, 2, WEED.SMALL, WEED.WEEDED }) do
        local field = stubs.addField(world, { fruit = "WHEAT", weedState = state })
        local judged, overrun = sample(field)
        assertTrue(judged, "judged at state " .. state)
        assertEquals(overrun, false, "overrun at state " .. state)
    end
end)

test("weeds killed by herbicide don't count, even though they still dent the yield", function()
    local world = setup()
    for _, state in ipairs({ WEED.SPRAYED_SMALL, WEED.SPRAYED_MEDIUM, WEED.SPRAYED_LARGE }) do
        local field = stubs.addField(world, { fruit = "WHEAT", weedState = state })
        local _, overrun = sample(field)
        assertEquals(overrun, false, "overrun at sprayed state " .. state)
    end
end)

test("a field is overrun when at least half of its sampled crop is weedy", function()
    local world = setup()
    -- Square field: centre (x = cx) plus 4 points, two left and two right of it
    local cx = 1000
    local threeOfFive = stubs.addField(world, { id = 1, centerX = cx, fruit = "WHEAT",
        weedStateAt = function(x) return x >= cx and WEED.LARGE or 0 end })
    local twoOfFive = stubs.addField(world, { id = 2, centerX = 3000, fruit = "WHEAT",
        weedStateAt = function(x) return x > 3000 and WEED.LARGE or 0 end })

    local _, overrun = sample(threeOfFive)
    assertTrue(overrun, "3 of 5 points weedy")
    _, overrun = sample(twoOfFive)
    assertEquals(overrun, false, "2 of 5 points weedy")
end)

test("only points with a growing crop make up the share", function()
    local world = setup()
    -- Wheat on the right-hand side only; weeds everywhere
    local field = stubs.addField(world, { centerX = 1000, weedState = WEED.LARGE,
        fruitAt = function(x) return x > 1000 and "WHEAT" or nil end })

    local judged, overrun = sample(field)
    assertTrue(judged, "judged on its cropped part")
    assertTrue(overrun, "all cropped points weedy")
end)

test("weeds on bare ground are not judged", function()
    local world = setup()
    local field = stubs.addField(world, { fruit = nil, weedState = WEED.LARGE })
    local judged, overrun = sample(field)
    assertEquals(judged, false, "judged")
    assertEquals(overrun, false, "overrun")
end)

test("grass, meadow, vines, olives and catch crops are not judged", function()
    local world = setup()
    for _, fruit in ipairs({ "GRASS", "MEADOW", "GRAPE", "OLIVE", "OILSEEDRADISH" }) do
        local field = stubs.addField(world, { fruit = fruit, growthState = 1, weedState = WEED.LARGE })
        local judged = sample(field)
        assertEquals(judged, false, fruit .. " judged")
    end
end)

test("stubble and withered crops are not judged, a harvest-ready crop is", function()
    local world = setup()
    local wheat = stubs.FRUITS[FruitType.WHEAT]
    local cut = stubs.addField(world, { fruit = "WHEAT", growthState = wheat.cutState, weedState = WEED.LARGE })
    local withered = stubs.addField(world, { fruit = "WHEAT", growthState = wheat.witheredState, weedState = WEED.LARGE })
    local ready = stubs.addField(world, { fruit = "WHEAT", growthState = wheat.minHarvestingGrowthState, weedState = WEED.LARGE })

    assertEquals((sample(cut)), false, "stubble judged")
    assertEquals((sample(withered)), false, "withered judged")
    assertEquals((sample(ready)), true, "harvest-ready judged")
end)

test("sample points are the centre plus halfway towards up to 8 vertices", function()
    local world = setup()
    local square = stubs.addField(world, { id = 1, centerX = 1000, size = 100 })
    local many = stubs.addField(world, { id = 2, centerX = 3000, size = 100, vertexCount = 20 })

    local points = FarmlandGatherer.getWeedSamplePoints(square.farmland.field)
    assertEquals(#points, 5, "square point count")
    assertEquals(points[1].x, 1000, "centre x")
    assertEquals(points[1].z, 0, "centre z")
    -- First corner is (-50, -50) from the centre
    assertEquals(points[2].x, 975, "halfway x")
    assertEquals(points[2].z, -25, "halfway z")

    points = FarmlandGatherer.getWeedSamplePoints(many.farmland.field)
    assertEquals(#points, 9, "capped at centre + 8")
    for i, point in ipairs(points) do
        assertTrue(world.fieldAt(point.x, point.z) == many, "point " .. i .. " inside the field")
    end
end)

test("a field without a centre gives no points and is not judged", function()
    local world = setup()
    local field = stubs.addField(world, { fruit = "WHEAT", weedState = WEED.LARGE })
    function field.farmland.field:getCenterOfFieldWorldPosition() return nil, nil end

    assertEquals(#FarmlandGatherer.getWeedSamplePoints(field.farmland.field), 0, "points")
    assertEquals((sample(field)), false, "judged")
end)

-- The run of overrun months ------------------------------------------------

test("each overrun month adds to the run and a clean month resets it", function()
    local world = setup()
    local field = stubs.addField(world, { fruit = "WHEAT", weedState = WEED.LARGE })

    for month = 1, 3 do
        stubs.nextMonth()
        world.farmlandGatherer:periodChanged()
        assertEquals(runOf(world, field), month, "run after month " .. month)
    end

    field.weedState = WEED.SPRAYED_LARGE
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    assertEquals(runOf(world, field), 0, "run after spraying")
end)

test("a month with no growing crop breaks the run", function()
    local world = setup()
    local field = stubs.addField(world, { fruit = "WHEAT", weedState = WEED.LARGE })
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    assertEquals(runOf(world, field), 2, "run before harvest")

    field.growthState = stubs.FRUITS[FruitType.WHEAT].cutState
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    assertEquals(runOf(world, field), 0, "run after harvest")
    assertEquals(world.farmlandGatherer:getFarmlandData(field.id).weedJudged, false, "judged after harvest")
end)

test("a field that changes hands starts with a clean record", function()
    local world = setup()
    local field = stubs.addField(world, { farmId = 1, fruit = "WHEAT", weedState = WEED.LARGE })
    for _ = 1, 3 do
        stubs.nextMonth()
        world.farmlandGatherer:periodChanged()
    end
    assertEquals(runOf(world, field), 3, "run under the first owner")

    field.farmland.farmId = 2
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    assertEquals(runOf(world, field), 1, "run under the new owner counts only their month")
end)

test("with weeds switched off or no weed map nothing is judged and runs reset", function()
    local world = setup()
    local field = stubs.addField(world, { fruit = "WHEAT", weedState = WEED.LARGE })
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    assertEquals(runOf(world, field), 1, "run with weeds on")

    g_currentMission.missionInfo.weedsEnabled = false
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    assertEquals(runOf(world, field), 0, "run with weeds switched off")

    g_currentMission.missionInfo.weedsEnabled = true
    world.mapHasWeed = false
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    assertEquals(runOf(world, field), 0, "run on a map without weeds")
    assertEquals(world.farmlandGatherer:getFarmlandData(field.id).weedJudged, false, "judged")
end)

test("the run and its owner survive a save and load; older saves start clean", function()
    local world = setup()
    local field = stubs.addField(world, { id = 7, farmId = 1, fruit = "WHEAT", weedState = WEED.LARGE })
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()
    stubs.nextMonth()
    world.farmlandGatherer:periodChanged()

    local xmlFile = {}
    world.farmlandGatherer:saveToXmlFile(xmlFile, "RedTape")
    local loaded = FarmlandGatherer.new()
    loaded:loadFromXMLFile(xmlFile, "RedTape")
    local data = loaded:getFarmlandData(7)
    assertEquals(data.highWeedMonths, 2, "loaded run")
    assertEquals(data.weedOwnerFarmId, 1, "loaded owner")
    assertEquals(data.weedJudged, false, "judged is not saved")

    -- A save from before this policy has neither attribute
    for key in pairs(xmlFile) do
        if key:find("#highWeedMonths", 1, true) or key:find("#weedOwnerFarmId", 1, true) then
            xmlFile[key] = nil
        end
    end
    local old = FarmlandGatherer.new()
    old:loadFromXMLFile(xmlFile, "RedTape")
    assertEquals(old:getFarmlandData(7).highWeedMonths, 0, "old save run")
    assertEquals(old:getFarmlandData(7).weedOwnerFarmId, 0, "old save owner")
end)

-- The policy ----------------------------------------------------------------

test("one overrun month is only watched: no warning, fine or reward", function()
    local world = setup()
    stubs.addField(world, { id = 3, fruit = "WHEAT", weedState = WEED.LARGE })

    local report = monthEnd(world)
    assertEquals(#stubs.eventsOfKind(world, "warning"), 0, "warnings")
    assertEquals(#stubs.eventsOfKind(world, "fine"), 0, "fines")
    assertEquals(pointsSent(world), 0, "points")
    local row = reportRow(report, farmlandName(3))
    assertTrue(row ~= nil, "field listed")
    assertEquals(row.cell2, "1 " .. g_i18n:getText("rt_misc_month"), "months")
    assertEquals(row.cell3, g_i18n:getText("rt_report_value_weeds_monitoring"), "status")
end)

test("two months in a row earns a warning but no fine", function()
    local world = setup()
    stubs.addField(world, { id = 3, fruit = "WHEAT", weedState = WEED.LARGE })

    monthEnd(world)
    local report = monthEnd(world)
    local warnings = stubs.eventsOfKind(world, "warning")
    assertEquals(#warnings, 1, "warnings")
    assertEquals(warnings[1].farmId, 1, "warned farm")
    assertEquals(warnings[1].policyIndex, RTPolicyIds.NOXIOUS_WEEDS, "warned policy")
    assertEquals(#stubs.eventsOfKind(world, "fine"), 0, "fines")
    assertEquals(pointsSent(world), 0, "points")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 0, "warnings cleared")
    local row = reportRow(report, farmlandName(3))
    assertEquals(row.cell2, "2 " .. g_i18n:getText("rt_misc_month") .. g_i18n:getText("rt_misc_month_plural_suffix"), "months")
    assertEquals(row.cell3, g_i18n:getText("rt_report_value_weeds_warning"), "status")
end)

test("three months fines per ha straight away and costs points per ha", function()
    local world = setup()
    stubs.addField(world, { id = 3, areaHa = 2.5, fruit = "WHEAT", weedState = WEED.LARGE })

    monthEnd(world)
    monthEnd(world)
    local report = monthEnd(world)
    local fines = stubs.eventsOfKind(world, "fine")
    assertEquals(#fines, 1, "fines")
    assertNear(fines[1].amount, 2.5 * policyInfo().finePerHa, 0.001, "fine")
    assertEquals(#stubs.eventsOfKind(world, "warning"), 0, "no warning with the fine")
    assertEquals(pointsSent(world), math.floor(2.5 * policyInfo().pointsPenaltyPerHa), "points")
    assertEquals(reportRow(report, farmlandName(3)).cell3, g_i18n:getText("rt_report_value_weeds_fined"), "status")
end)

test("the fine repeats every month the field stays overrun", function()
    local world = setup()
    stubs.addField(world, { areaHa = 1, fruit = "WHEAT", weedState = WEED.LARGE })

    for _ = 1, 3 do
        monthEnd(world)
    end
    monthEnd(world)
    assertEquals(#stubs.eventsOfKind(world, "fine"), 1, "fined again in month 4")
end)

test("only fields at 3 months are fined; a warned field alongside adds nothing", function()
    local world = setup()
    local early = stubs.addField(world, { id = 1, areaHa = 2, fruit = "WHEAT", weedState = WEED.LARGE })
    local late = stubs.addField(world, { id = 2, areaHa = 5, fruit = "WHEAT", weedState = 0 })

    monthEnd(world)
    late.weedState = WEED.LARGE
    monthEnd(world)
    monthEnd(world)
    -- early is at 3 months, late at 2
    assertEquals(runOf(world, early), 3, "early run")
    assertEquals(runOf(world, late), 2, "late run")
    local fines = stubs.eventsOfKind(world, "fine")
    assertEquals(#fines, 1, "fines")
    assertNear(fines[1].amount, 2 * policyInfo().finePerHa, 0.001, "fine covers only the early field")
    assertEquals(#stubs.eventsOfKind(world, "warning"), 0, "warnings")
end)

test("a clean month with a crop checked earns the reward and clears warnings", function()
    local world = setup()
    local field = stubs.addField(world, { fruit = "WHEAT", weedState = WEED.LARGE })
    monthEnd(world)
    monthEnd(world)

    field.weedState = WEED.SPRAYED_LARGE
    local report = monthEnd(world)
    assertEquals(pointsSent(world), policyInfo().periodicReward, "points")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 1, "warnings cleared")
    assertEquals(reportRow(report, g_i18n:getText("rt_report_name_fields_checked")).cell2, 1, "fields checked")
end)

test("with nothing to check there is no reward, except in tier D", function()
    local world = setup()
    stubs.addField(world, { fruit = "GRASS", growthState = 1 })

    monthEnd(world, 1, RTPolicySystem.TIER.C)
    assertEquals(pointsSent(world), 0, "points in tier C")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 1, "warnings cleared")

    monthEnd(world, 1, RTPolicySystem.TIER.D)
    assertEquals(pointsSent(world), policyInfo().periodicReward, "points in tier D")
end)

test("another farm's weedy fields don't affect this farm", function()
    local world = setup()
    stubs.addField(world, { id = 1, farmId = 2, fruit = "WHEAT", weedState = WEED.LARGE })
    stubs.addField(world, { id = 2, farmId = 1, fruit = "WHEAT", weedState = 0 })

    local report
    for _ = 1, 3 do
        report = monthEnd(world, 1)
    end
    assertEquals(#stubs.eventsOfKind(world, "fine"), 0, "fines")
    assertEquals(reportRow(report, farmlandName(1)), nil, "other farm's field listed")
    assertEquals(pointsSent(world), policyInfo().periodicReward, "clean month for farm 1")

    evaluate(world, 2)
    assertEquals(#stubs.eventsOfKind(world, "fine"), 1, "farm 2 fined")
    assertEquals(stubs.eventsOfKind(world, "fine")[1].farmId, 2, "fined farm")
end)

test("the report lists overrun fields in farmland order between the totals", function()
    local world = setup()
    stubs.addField(world, { id = 1, fruit = "WHEAT", weedState = 0 })
    stubs.addField(world, { id = 4, fruit = "WHEAT", weedState = WEED.LARGE })
    stubs.addField(world, { id = 2, fruit = "BARLEY", weedState = WEED.MEDIUM })

    local report = monthEnd(world)
    assertEquals(#report, 4, "rows")
    assertEquals(report[1].cell1, g_i18n:getText("rt_report_name_fields_checked"), "first row")
    assertEquals(report[1].cell2, 3, "fields checked")
    assertEquals(report[2].cell1, farmlandName(2), "second row")
    assertEquals(report[3].cell1, farmlandName(4), "third row")
    assertEquals(report[4].cell1, g_i18n:getText("rt_report_name_points"), "last row")
end)

test("with weeds switched off the report says so and nothing is judged", function()
    local world = setup()
    stubs.addField(world, { fruit = "WHEAT", weedState = WEED.LARGE })
    g_currentMission.missionInfo.weedsEnabled = false

    local report = monthEnd(world)
    assertEquals(#report, 1, "rows")
    assertEquals(report[1].cell2, g_i18n:getText("rt_report_value_weeds_disabled"), "note")
    assertEquals(pointsSent(world), 0, "points")
    assertEquals(#stubs.eventsOfKind(world, "warning") + #stubs.eventsOfKind(world, "fine"), 0, "warnings and fines")
    assertEquals(#stubs.eventsOfKind(world, "clearWarnings"), 1, "warnings cleared")
end)

-- Issuing -------------------------------------------------------------------

-- Every other policy already active, so the only candidate is this one
local function onlyNoxiousWeedsFree(world)
    for id in pairs(RTPolicies) do
        if id ~= RTPolicyIds.NOXIOUS_WEEDS then
            table.insert(world.policySystem.policies, { policyIndex = id })
        end
    end
end

test("the policy is only issued in a savegame that has weeds", function()
    local world = setup()
    onlyNoxiousWeedsFree(world)
    assertEquals(world.policySystem:getNextPolicyIndex(), RTPolicyIds.NOXIOUS_WEEDS, "weeds on")

    g_currentMission.missionInfo.weedsEnabled = false
    assertEquals(world.policySystem:getNextPolicyIndex(), nil, "weeds switched off")

    g_currentMission.missionInfo.weedsEnabled = true
    world.mapHasWeed = false
    assertEquals(world.policySystem:getNextPolicyIndex(), nil, "map without weeds")
end)

test("it gets its own enforcement toggle, and switching it off stops it being issued", function()
    local world = setup()
    local settingId = RedTape.policySettingIdByPolicyId[RTPolicyIds.NOXIOUS_WEEDS]
    assertEquals(settingId, "policyEnabled_NOXIOUS_WEEDS", "setting id")
    assertEquals(RedTape.SETTINGS[settingId].title, g_i18n:getText("rt_policy_noxious_weeds"), "setting title")

    onlyNoxiousWeedsFree(world)
    g_currentMission.RedTape.settings[settingId] = false
    assertEquals(world.policySystem:getNextPolicyIndex(), nil, "issued while switched off")
end)
