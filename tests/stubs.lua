-- Fake FS25 engine globals for the unit tests. stubs.install() replaces
-- them all with fresh ones, loads the mod's core files, and returns a
-- `world` for building the scene a test needs (farmlands, fields, crops,
-- weeds) and reading back what happened (events sent, log lines). Call it
-- at the start of every test.
--
-- These are our assumptions about the base game, checked against
-- ../Reference/FS25_Lua (and data/maps/maps_weed.xml for the weed states)
-- where it matters - not the game itself. A test that passes here can
-- still be wrong in-game.

local luau = dofile("tests/luau.lua")

local stubs = {}

-- Base game texts the mod reads without shipping its own
stubs.BASE_TEXTS = {
    ui_on = "On",
    ui_off = "Off",
}
for month, name in ipairs({ "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December" }) do
    stubs.BASE_TEXTS["ui_month" .. month] = name
end

-- Crops, with the growth states the tests use. Numbers are made up but
-- keep vanilla's shape: growing states, then harvest ready, withered, cut.
stubs.FRUITS = {
    { name = "WHEAT", minHarvestingGrowthState = 7, maxHarvestingGrowthState = 7, witheredState = 8, cutState = 9 },
    { name = "BARLEY", minHarvestingGrowthState = 7, maxHarvestingGrowthState = 7, witheredState = 8, cutState = 9 },
    { name = "GRASS", minHarvestingGrowthState = 3, maxHarvestingGrowthState = 4, cutState = 5 },
    { name = "MEADOW", minHarvestingGrowthState = 3, maxHarvestingGrowthState = 4, cutState = 5 },
    { name = "GRAPE", minHarvestingGrowthState = 7, maxHarvestingGrowthState = 7, cutState = 10 },
    { name = "OLIVE", minHarvestingGrowthState = 7, maxHarvestingGrowthState = 7, cutState = 10 },
    { name = "OILSEEDRADISH", minHarvestingGrowthState = 2, maxHarvestingGrowthState = 2, cutState = 3, isCatchCrop = true },
}

-- Vanilla's data/maps/maps_weed.xml: 1-2 seeds (invisible), 3 small,
-- 4 medium, 5 large, 6 partly weeded, 7-9 killed by herbicide.
stubs.WEED = {
    SMALL = 3,
    MEDIUM = 4,
    LARGE = 5,
    WEEDED = 6,
    SPRAYED_SMALL = 7,
    SPRAYED_MEDIUM = 8,
    SPRAYED_LARGE = 9,
}
stubs.WEED_FACTORS = { [3] = 0.5, [4] = 0.75, [5] = 1.0, [6] = 0.5, [8] = 0.5, [9] = 0.75 }
stubs.HERBICIDE_REPLACEMENTS = { [1] = 0, [2] = 0, [3] = 7, [4] = 8, [5] = 9, [6] = 7 }

-- The mod's real English texts, so a missing key fails the test.
local function loadTexts(path)
    local file = io.open(path, "rb")
    assert(file ~= nil, "can't open " .. path)
    local content = file:read("*a")
    file:close()

    local entities = { amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'" }
    local texts = {}
    for name, text in content:gmatch("<text%s+name=\"([^\"]+)\"%s+text=\"([^\"]*)\"") do
        texts[name] = text:gsub("&(%a+);", entities)
    end
    for name, text in pairs(stubs.BASE_TEXTS) do
        texts[name] = texts[name] or text
    end
    return texts
end

local function installXML()
    -- An xmlFile is a plain table, key -> value.
    local function set(xmlFile, key, value)
        xmlFile[key] = value
    end
    local function get(xmlFile, key)
        return xmlFile[key]
    end
    setXMLInt, setXMLFloat, setXMLString, setXMLBool = set, set, set, set
    getXMLInt, getXMLFloat, getXMLString, getXMLBool = get, get, get, get
    hasXMLProperty = function(xmlFile, key)
        for existing in pairs(xmlFile) do
            if existing == key or existing:sub(1, #key + 1) == key .. "#" or existing:sub(1, #key + 1) == key .. "." then
                return true
            end
        end
        return false
    end
end

local function installFruits(world)
    FruitType = { UNKNOWN = 0 }
    local fruitByIndex = {}
    local fruitTypes = {}
    for index, def in ipairs(stubs.FRUITS) do
        local fruit = {
            index = index,
            name = def.name,
            minHarvestingGrowthState = def.minHarvestingGrowthState,
            maxHarvestingGrowthState = def.maxHarvestingGrowthState,
            witheredState = def.witheredState,
            cutState = def.cutState,
            isCatchCrop = def.isCatchCrop == true,
        }
        -- Same rules as vanilla's FruitTypeDesc
        function fruit:getIsCut(growthState) return growthState == self.cutState end
        function fruit:getIsWithered(growthState) return self.witheredState ~= nil and growthState == self.witheredState end
        function fruit:getIsCatchCrop() return self.isCatchCrop end
        FruitType[def.name] = index
        fruitByIndex[index] = fruit
        table.insert(fruitTypes, fruit)
    end

    g_fruitTypeManager = {
        fruitTypes = fruitTypes,
        nameToFruitType = {},
        getFruitTypeByIndex = function(_, index)
            return fruitByIndex[index]
        end,
        getFillTypeByFruitTypeIndex = function()
            return nil
        end,
    }
    for _, fruit in ipairs(fruitTypes) do
        g_fruitTypeManager.nameToFruitType[fruit.name] = fruit
    end
end

-- The density maps: what is growing, and what weeds, at a world position.
-- Each field covers the square its vertices span; anywhere else is bare.
local function installDensityMaps(world)
    local function fieldAt(x, z)
        for _, field in ipairs(world.fields) do
            if x >= field.minX and x <= field.maxX and z >= field.minZ and z <= field.maxZ then
                return field
            end
        end
        return nil
    end
    world.fieldAt = fieldAt

    FSDensityMapUtil = {
        -- Vanilla returns nothing at all when there is no fruit
        getFruitTypeIndexAtWorldPos = function(x, z)
            local field = fieldAt(x, z)
            local fruit = field ~= nil and field.fruit or nil
            if field ~= nil and field.fruitAt ~= nil then
                fruit = field.fruitAt(x, z)
            end
            if fruit == nil then
                return nil
            end
            local growthState = field.growthState
            if field.growthStateAt ~= nil then
                growthState = field.growthStateAt(x, z)
            end
            return FruitType[fruit], growthState
        end,
    }

    g_currentMission.weedSystem = {
        getMapHasWeed = function()
            return world.mapHasWeed
        end,
        getFactors = function()
            return stubs.WEED_FACTORS
        end,
        getHerbicideReplacements = function()
            return { weed = { replacements = stubs.HERBICIDE_REPLACEMENTS } }
        end,
        -- Vanilla returns 0 for no weeds (or no weed map)
        getWeedStateAtWorldPos = function(_, x, z)
            local field = fieldAt(x, z)
            if field == nil then
                return 0
            end
            if field.weedStateAt ~= nil then
                return field.weedStateAt(x, z)
            end
            return field.weedState or 0
        end,
    }
end

-- A sent event, as recorded in world.events
local function eventClass(kind, fields)
    return {
        new = function(...)
            local event = { kind = kind }
            local args = { ... }
            for i, field in ipairs(fields) do
                event[field] = args[i]
            end
            return event
        end,
    }
end

function stubs.install()
    local world = {
        fields = {},
        events = {},
        logs = {},
        mapHasWeed = true,
        texts = loadTexts("languages/l10n_en.xml"),
    }

    Class = function(classTable, baseClass)
        return { __index = classTable }
    end
    table.unpack = table.unpack or unpack

    Utils = {
        getNoNil = function(value, default)
            if value == nil then
                return default
            end
            return value
        end,
        overwrittenFunction = function(oldFunc, newFunc)
            return function(self, ...)
                return newFunc(self, oldFunc, ...)
            end
        end,
        appendedFunction = function(oldFunc, newFunc)
            return function(...)
                if oldFunc ~= nil then
                    oldFunc(...)
                end
                return newFunc(...)
            end
        end,
        prependedFunction = function(oldFunc, newFunc)
            return function(...)
                newFunc(...)
                if oldFunc ~= nil then
                    return oldFunc(...)
                end
            end
        end,
    }

    g_i18n = {
        getText = function(_, key)
            local text = world.texts[key]
            assert(text ~= nil, "missing l10n key " .. tostring(key))
            return text
        end,
        hasText = function(_, key)
            return world.texts[key] ~= nil
        end,
        formatArea = function(_, area, precision)
            return string.format("%." .. (precision or 0) .. "f ha", area)
        end,
        formatVolume = function(_, liters)
            return string.format("%d l", math.floor(liters))
        end,
        formatMoney = function(_, amount)
            return string.format("%.0f", amount)
        end,
    }

    installXML()

    -- Loaded by RedTape.lua / RedTapeSettings.lua / PolicySystem.lua as they load
    g_currentModDirectory = ""
    source = function() end
    addModEventListener = function() end
    FSBaseMission = {}
    Mission00 = nil
    FocusManager = {}
    Farm = { PERMISSION = {}, PERMISSIONS = {} }
    FinanceStats = { statNames = {}, statNameToIndex = {} }
    g_fillTypeManager = {
        getConverterDataByName = function()
            return nil
        end,
    }

    -- Everything a sendEvent carries ends up in world.events
    local connection = {
        sendEvent = function(_, event)
            table.insert(world.events, event)
        end,
    }
    g_client = {
        getServerConnection = function()
            return connection
        end,
    }
    RTPolicyPointsEvent = eventClass("points", { "farmId", "points", "reason" })
    RTPolicyClearWarningsEvent = eventClass("clearWarnings", { "farmId", "policyIndex" })
    RTPolicyWarningEvent = eventClass("warning", { "farmId", "policyIndex" })
    RTPolicyFineEvent = eventClass("fine", { "farmId", "policyIndex", "amount" })

    g_currentMission = {
        -- period 1 is March; month 3 of year 1
        environment = { currentPeriod = 1, currentYear = 1 },
        missionInfo = { weedsEnabled = true },
        getIsServer = function()
            return true
        end,
    }

    installFruits(world)
    installDensityMaps(world)

    g_farmlandManager = { farmlands = {} }

    getWorldTranslation = function(node)
        return node.x, 0, node.z
    end

    function world:load(path)
        luau.dofile(path)
    end

    world:load("src/RedTape.lua")
    -- Recorded rather than printed, so a test can check for them
    RedTape.logWarning = function(message)
        table.insert(world.logs, tostring(message))
    end
    world:load("src/system/PolicyList.lua")
    world:load("src/RedTapeSettings.lua")
    world:load("src/system/PolicySystem.lua")
    world:load("src/instances/Policy.lua")
    world:load("src/system/InfoGatherer.lua")
    world:load("src/gatherers/FarmlandGatherer.lua")

    -- The parts of the running mod the code under test reaches for
    local policySystem = setmetatable({ policies = {}, points = {}, warnings = {} }, RTPolicySystem_mt)
    world.farmlandGatherer = FarmlandGatherer.new()
    g_currentMission.RedTape = {
        settings = {},
        monthStarted = 0,
        PolicySystem = policySystem,
        InfoGatherer = { gatherers = { [INFO_KEYS.FARMLANDS] = world.farmlandGatherer } },
    }
    world.policySystem = policySystem

    return world
end

-- Builders ------------------------------------------------------------------

-- def: { id, farmId, centerX, centerZ, size (square side, m), areaHa,
--        fruit (name), growthState, weedState,
--        fruitAt(x, z) / growthStateAt(x, z) / weedStateAt(x, z) for uneven
--        fields,
--        vertexCount (corners of the square, default 4) }
-- Returns the field's world data, so a test can change its crop or weeds.
function stubs.addField(world, def)
    local id = def.id or (#world.fields + 1)
    local cx = def.centerX or id * 1000
    local cz = def.centerZ or 0
    local half = (def.size or 100) / 2

    -- Vertices go round the square; with more than 4 they are spread
    -- along its edges.
    local corners = { { -half, -half }, { half, -half }, { half, half }, { -half, half } }
    local vertexCount = def.vertexCount or 4
    local nodes = {}
    for i = 1, vertexCount do
        local t = (i - 1) / vertexCount * 4
        local edge = math.floor(t) + 1
        local fraction = t - math.floor(t)
        local a = corners[edge]
        local b = corners[edge % 4 + 1]
        table.insert(nodes, { x = cx + a[1] + (b[1] - a[1]) * fraction, z = cz + a[2] + (b[2] - a[2]) * fraction })
    end

    local fieldData = {
        id = id,
        minX = cx - half, maxX = cx + half, minZ = cz - half, maxZ = cz + half,
        centerX = cx, centerZ = cz,
        fruit = def.fruit,
        growthState = def.growthState or 3,
        weedState = def.weedState or 0,
        fruitAt = def.fruitAt,
        growthStateAt = def.growthStateAt,
        weedStateAt = def.weedStateAt,
    }
    table.insert(world.fields, fieldData)

    local field = {
        nodes = nodes,
        areaHa = def.areaHa or 1,
    }
    function field:getCenterOfFieldWorldPosition() return cx, cz end
    function field:getPolygonPoints() return self.nodes end
    function field:getAreaHa() return self.areaHa end

    local farmland = {
        id = id,
        farmId = def.farmId or 1,
        field = field,
        showOnFarmlandsScreen = true,
    }
    g_farmlandManager.farmlands[id] = farmland
    fieldData.farmland = farmland
    return fieldData
end

-- Moves the calendar on one month, as the period change does
function stubs.nextMonth()
    local environment = g_currentMission.environment
    environment.currentPeriod = environment.currentPeriod + 1
    if environment.currentPeriod > 12 then
        environment.currentPeriod = 1
        environment.currentYear = environment.currentYear + 1
    end
end

-- Events of one kind, from world.events
function stubs.eventsOfKind(world, kind)
    local result = {}
    for _, event in ipairs(world.events) do
        if event.kind == kind then
            table.insert(result, event)
        end
    end
    return result
end

return stubs
