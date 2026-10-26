-- Public API for other mods. Reach it through Red Tape's mod environment:
--
--   local env = g_modIsLoaded["FS25_RedTape"] and getfenv(0)["FS25_RedTape"] or nil
--   local api = env ~= nil and env.RedTapeAPI or nil
--   if api ~= nil and api.getInfo().version >= 1 and api.getInfo().features.wasteDisposal then ... end
--
-- The version only goes up when something here changes in a way a caller would notice; a new
-- feature is announced in getInfo().features. See docs/RedTapeAPI.md for the full contract.
--
-- Waste disposal (version 1): a mod that produces regulated farm waste reports each disposal with
-- recordWasteDisposal, and Red Tape's Waste Disposal policy judges the farm on it each month.
-- Nothing here throws: a bad call is logged and returns false with a reason.

RedTapeAPI = {}

RedTapeAPI.VERSION = 1

RedTapeAPI.WASTE_TYPES = { "oil", "coolant" }

-- How the waste left the farm.
--   delivered: the farm took it to an approved site (dealer, collection point). Rewarded.
--   collected: an approved collector fetched it from the farm. Legal, but not rewarded.
--   discarded: dumped or otherwise got rid of illegally. Penalised.
RedTapeAPI.DISPOSAL_METHODS = { "delivered", "collected", "discarded" }

-- sourceId -> true. Mods that report waste disposals. Kept for the whole game session, since a
-- caller may register before Red Tape's own loadMap has run.
RedTapeAPI.wasteSources = {}

--- What this version of Red Tape offers.
function RedTapeAPI.getInfo()
    return {
        version = RedTapeAPI.VERSION,
        features = {
            wasteDisposal = true,
        },
        wasteTypes = RedTapeAPI.copyList(RedTapeAPI.WASTE_TYPES),
        disposalMethods = RedTapeAPI.copyList(RedTapeAPI.DISPOSAL_METHODS),
    }
end

function RedTapeAPI.copyList(list)
    local copy = {}
    for i, value in ipairs(list) do
        copy[i] = value
    end
    return copy
end

--- Tells Red Tape that sourceId (e.g. the caller's mod name) reports waste disposals. The Waste
--- Disposal policy is only issued while at least one source is registered. Call on every machine
--- from loadMap or later. Registering twice is harmless.
function RedTapeAPI.registerWasteSource(sourceId)
    if type(sourceId) ~= "string" or sourceId == "" then
        RedTape.logWarning("RedTapeAPI.registerWasteSource: invalid sourceId '" .. tostring(sourceId) .. "'")
        return false, "invalidSourceId"
    end

    RedTapeAPI.wasteSources[sourceId] = true
    return true
end

--- Withdraws a source, e.g. when the caller's own waste handling is switched off. A policy that is
--- already active stays active, but finds nothing to judge until a source is registered again.
function RedTapeAPI.unregisterWasteSource(sourceId)
    if RedTapeAPI.wasteSources[sourceId] == nil then
        return false
    end

    RedTapeAPI.wasteSources[sourceId] = nil
    return true
end

function RedTapeAPI.hasWasteSource()
    return next(RedTapeAPI.wasteSources) ~= nil
end

--- Whether waste disposal is regulated right now: the Waste Disposal policy is active and
--- enforced. Works on the server and on clients. farmId is accepted for future use; policies
--- currently apply to every farm alike.
function RedTapeAPI.isWasteDisposalRegulated(farmId)
    local rt = g_currentMission ~= nil and g_currentMission.RedTape or nil
    local policySystem = rt ~= nil and rt.PolicySystem or nil
    if policySystem == nil or rt.settings == nil or not policySystem:isEnabled() then
        return false
    end

    local policyId = RTPolicyIds.WASTE_DISPOSAL
    if not RedTape.isPolicyEnforced(policyId) then
        return false
    end

    for _, policy in ipairs(policySystem.policies or {}) do
        if policy.policyIndex == policyId then
            return true
        end
    end

    return false
end

--- Server only. Records that farmId got rid of liters of wasteType ("oil" or "coolant") by
--- method ("delivered", "collected" or "discarded"). Call it for every disposal, whether or not
--- the policy is active: Red Tape decides what counts. Returns true, or false and a reason:
--- notServer, notReady, invalidFarm, invalidWasteType, invalidLiters, invalidMethod.
function RedTapeAPI.recordWasteDisposal(farmId, wasteType, liters, method)
    local reason = RedTapeAPI.checkWasteDisposal(farmId, wasteType, liters, method)
    if reason ~= nil then
        RedTape.logWarning(string.format("RedTapeAPI.recordWasteDisposal(%s, %s, %s, %s) refused: %s",
            tostring(farmId), tostring(wasteType), tostring(liters), tostring(method), reason))
        return false, reason
    end

    local gatherer = g_currentMission.RedTape.InfoGatherer.gatherers[INFO_KEYS.WASTE]
    gatherer:addDisposal(farmId, wasteType, liters, method)
    return true
end

-- The reason a recordWasteDisposal call can't be taken, or nil
function RedTapeAPI.checkWasteDisposal(farmId, wasteType, liters, method)
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then
        return "notServer"
    end

    local rt = mission.RedTape
    local infoGatherer = rt ~= nil and rt.InfoGatherer or nil
    if infoGatherer == nil or infoGatherer.gatherers == nil or infoGatherer.gatherers[INFO_KEYS.WASTE] == nil then
        return "notReady"
    end

    return RedTapeAPI.checkWasteArguments(farmId, wasteType, liters, method)
end

-- The reason a disposal's values can't be recorded, or nil. Also checks entries loaded from a savegame.
function RedTapeAPI.checkWasteArguments(farmId, wasteType, liters, method)
    -- Spectator (0) and invalid farms can't be judged
    if type(farmId) ~= "number" or farmId < 1 or farmId ~= math.floor(farmId) then
        return "invalidFarm"
    end

    if not RedTape.tableHasValue(RedTapeAPI.WASTE_TYPES, wasteType) then
        return "invalidWasteType"
    end

    -- liters ~= liters catches NaN; inf is refused too
    if type(liters) ~= "number" or liters ~= liters or liters <= 0 or liters == math.huge then
        return "invalidLiters"
    end

    if not RedTape.tableHasValue(RedTapeAPI.DISPOSAL_METHODS, method) then
        return "invalidMethod"
    end

    return nil
end
