-- A payout when a scheme is evaluated
RTSchemePayoutEvent = {}
local RTSchemePayoutEvent_mt = Class(RTSchemePayoutEvent, Event)

InitEventClass(RTSchemePayoutEvent, "RTSchemePayoutEvent")

function RTSchemePayoutEvent.emptyNew()
    local self = Event.new(RTSchemePayoutEvent_mt)

    return self
end

function RTSchemePayoutEvent.new(scheme, farmId, amount)
    local self = RTSchemePayoutEvent.emptyNew()
    self.scheme = scheme
    self.farmId = farmId
    self.amount = amount
    return self
end

function RTSchemePayoutEvent:writeStream(streamId, connection)
    self.scheme:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.amount)
end

function RTSchemePayoutEvent:readStream(streamId, connection)
    self.scheme = RTScheme.new()
    self.scheme:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.amount = streamReadFloat32(streamId)
    self:run(connection)
end

function RTSchemePayoutEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(RTSchemePayoutEvent.new(self.scheme, self.farmId, self.amount))
    end

    -- On the server this runs synchronously inside scheme evaluation, so a farm deleted in
    -- multiplayer must not throw here
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        RedTape.logWarning("skipping scheme payout for missing farm " .. tostring(self.farmId))
        return
    end

    if g_currentMission:getIsServer() then
        g_currentMission:addMoneyChange(self.amount, self.farmId,
            MoneyType.SCHEME_PAYOUT, true)
    end
    farm:changeBalance(self.amount, MoneyType.SCHEME_PAYOUT)

    local eventLog = g_currentMission.RedTape.EventLog
    local detail = string.format(g_i18n:getText("rt_notify_scheme_payout"), tostring(self.scheme:getName() or ""),
        g_i18n:formatMoney(self.amount))
    eventLog:addEvent(self.farmId, RTEventLogItem.EVENT_TYPE.SCHEME_PAYOUT, detail, true)
end
