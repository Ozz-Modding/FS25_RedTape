-- Sent from server to all clients to sync salt scheme running earnings for a farm.
-- Throttled to at most once per 5 seconds from FarmGatherer.
RTSaltSchemeHUDUpdateEvent = {}
local RTSaltSchemeHUDUpdateEvent_mt = Class(RTSaltSchemeHUDUpdateEvent, Event)

InitEventClass(RTSaltSchemeHUDUpdateEvent, "RTSaltSchemeHUDUpdateEvent")

function RTSaltSchemeHUDUpdateEvent.emptyNew()
    return Event.new(RTSaltSchemeHUDUpdateEvent_mt)
end

function RTSaltSchemeHUDUpdateEvent.new(farmId, earnings)
    local self = RTSaltSchemeHUDUpdateEvent.emptyNew()
    self.farmId = farmId
    self.earnings = earnings
    return self
end

function RTSaltSchemeHUDUpdateEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.earnings)
end

function RTSaltSchemeHUDUpdateEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.earnings = streamReadFloat32(streamId)
    self:run(connection)
end

function RTSaltSchemeHUDUpdateEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(RTSaltSchemeHUDUpdateEvent.new(self.farmId, self.earnings))
    end

    local myFarmId = g_currentMission:getFarmId()
    if self.farmId == myFarmId then
        g_currentMission.RedTape.SaltSchemeHUD:refreshEarnings(self.earnings)
    end
end
