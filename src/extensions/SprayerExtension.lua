RTSprayerExtension = {}

function RTSprayerExtension:onTurnedOn()
    g_currentMission.RedTape.InfoGatherer.gatherers[INFO_KEYS.FARMS].turnedOnSprayers[self.uniqueId] = self
end

function RTSprayerExtension:onTurnedOff()
    g_currentMission.RedTape.InfoGatherer.gatherers[INFO_KEYS.FARMS].turnedOnSprayers[self.uniqueId] = nil
    g_currentMission.RedTape.InfoGatherer.gatherers[INFO_KEYS.FARMS].sprayCoords[self.uniqueId] = nil
end

Sprayer.onTurnedOn = Utils.appendedFunction(Sprayer.onTurnedOn, RTSprayerExtension.onTurnedOn)
Sprayer.onTurnedOff = Utils.appendedFunction(Sprayer.onTurnedOff, RTSprayerExtension.onTurnedOff)

function RTSprayerExtension:processSprayerArea(superFunc, workArea, dt)
    if (not g_currentMission:getIsServer()) then
        return superFunc(self, workArea, dt)
    end
    local rt = g_currentMission.RedTape
    local delta = dt or g_currentDt

    -- Gate to perform spray area calculations much less frequently
    if rt.sprayCheckTime > 0 then
        rt.sprayCheckTime = rt.sprayCheckTime - delta
        return superFunc(self, workArea, dt)
    else
        rt.sprayCheckTime = rt.sprayAreaCheckInterval
    end

    local sx, sy, sz = getWorldTranslation(workArea.start)
    local wx, wy, wz = getWorldTranslation(workArea.width)
    local hx, hy, hz = getWorldTranslation(workArea.height)

    local widthVecX, widthVecY, widthVecZ = wx - sx, wy - sy, wz - sz
    local heightVecX, heightVecY, heightVecZ = hx - sx, hy - sy, hz - sz

    local widthLength = MathUtil.vector3Length(widthVecX, widthVecY, widthVecZ)
    local heightLength = MathUtil.vector3Length(heightVecX, heightVecY, heightVecZ)

    if widthLength == 0 or heightLength == 0 then
        return superFunc(self, workArea, dt)
    end

    local cellSize = 1
    local coords = {}

    -- Sample points in a grid over the work area
    for w = 0, widthLength, cellSize do
        for h = 0, heightLength, cellSize do
            local x = sx + (widthVecX / widthLength) * w + (heightVecX / heightLength) * h
            local y = sy + (widthVecY / widthLength) * w + (heightVecY / heightLength) * h
            local z = sz + (widthVecZ / widthLength) * w + (heightVecZ / heightLength) * h
            table.insert(coords, { x = x, y = y, z = z })
        end
    end

    rt.InfoGatherer.gatherers[INFO_KEYS.FARMS]:storeSprayAreaCoords(self.uniqueId, coords)

    return superFunc(self, workArea, dt)
end

Sprayer.processSprayerArea = Utils.overwrittenFunction(Sprayer.processSprayerArea, RTSprayerExtension.processSprayerArea)

function RTSprayerExtension:onEndWorkAreaProcessing(dt, hasProcessed)
    if (not g_currentMission:getIsServer()) then return end

    local rt = g_currentMission.RedTape
    local spec = self.spec_sprayer
    if spec.workAreaParameters.isActive then
        local sprayVehicle = spec.workAreaParameters.sprayVehicle
        local usage = spec.workAreaParameters.usage

        if sprayVehicle ~= nil then
            local sprayFillType = spec.workAreaParameters.sprayFillType
            local farmData = rt.InfoGatherer.gatherers[INFO_KEYS.FARMS]:getFarmData(sprayVehicle:getOwnerFarmId())
            if sprayFillType ~= nil then
                local cumulativeMonth = RedTape.getCumulativeMonth()
                local sprayHistory = farmData.sprayHistory

                if sprayHistory[cumulativeMonth] == nil then
                    sprayHistory[cumulativeMonth] = {}
                end
                local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(sprayFillType)
                if sprayHistory[cumulativeMonth][fillTypeName] == nil then
                    sprayHistory[cumulativeMonth][fillTypeName] = 0
                end

                sprayHistory[cumulativeMonth][fillTypeName] = sprayHistory[cumulativeMonth][fillTypeName] + usage
            end
        end
    end
end

Sprayer.onEndWorkAreaProcessing = Utils.appendedFunction(Sprayer.onEndWorkAreaProcessing,
    RTSprayerExtension.onEndWorkAreaProcessing)
