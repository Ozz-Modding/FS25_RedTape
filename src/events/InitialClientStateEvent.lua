RTInitialClientStateEvent = {}
local RTInitialClientStateEvent_mt = Class(RTInitialClientStateEvent, Event)

InitEventClass(RTInitialClientStateEvent, "RTInitialClientStateEvent")

function RTInitialClientStateEvent.emptyNew()
    return Event.new(RTInitialClientStateEvent_mt)
end

function RTInitialClientStateEvent.new()
    return RTInitialClientStateEvent.emptyNew()
end

function RTInitialClientStateEvent:writeStream(streamId, connection)
    local rt = g_currentMission.RedTape

    rt.EventLog:writeInitialClientState(streamId, connection)
    rt.PolicySystem:writeInitialClientState(streamId, connection)
    rt.SchemeSystem:writeInitialClientState(streamId, connection)
    rt.TaxSystem:writeInitialClientState(streamId, connection)
    rt.GrantSystem:writeInitialClientState(streamId, connection)
    rt.InfoGatherer:writeInitialClientState(streamId, connection)

    RedTape.SETTINGS.writeToStream(streamId)
end

function RTInitialClientStateEvent:readStream(streamId, connection)
    local rt = g_currentMission.RedTape

    rt.EventLog:readInitialClientState(streamId, connection)
    rt.PolicySystem:readInitialClientState(streamId, connection)
    rt.SchemeSystem:readInitialClientState(streamId, connection)
    rt.TaxSystem:readInitialClientState(streamId, connection)
    rt.GrantSystem:readInitialClientState(streamId, connection)
    rt.InfoGatherer:readInitialClientState(streamId, connection)

    RedTape.SETTINGS.readFromStream(streamId)

    self:run(connection)
end

function RTInitialClientStateEvent:run(connection)
    g_messageCenter:publish(MessageType.RT_DATA_UPDATED)
end
