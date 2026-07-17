RTSettingsEvent = {}
RTSettingsEvent_mt = Class(RTSettingsEvent, Event)

InitEventClass(RTSettingsEvent, "RTSettingsEvent")

function RTSettingsEvent.emptyNew()
    local self = Event.new(RTSettingsEvent_mt)
    return self
end

function RTSettingsEvent.new()
    return RTSettingsEvent.emptyNew()
end

function RTSettingsEvent:writeStream(streamId, connection)
    RedTape.SETTINGS.writeToStream(streamId)
end

function RTSettingsEvent:readStream(streamId, connection)
    RedTape.SETTINGS.readFromStream(streamId)
    self:run(connection)
end

function RTSettingsEvent:run(connection)
    local rt = g_currentMission.RedTape

    if not connection:getIsServer() then
        g_server:broadcastEvent(RTSettingsEvent.new())
        if not rt.settings.taxEnabled then
            rt.TaxSystem:onDisabled()
        end
        if not rt.settings.policiesAndSchemesEnabled then
            rt.PolicySystem:onDisabled()
            rt.SchemeSystem:onDisabled()
        end
        if not rt.settings.grantsEnabled then
            rt.GrantSystem:onDisabled()
        end
    else
        for _, id in pairs(RedTape.menuItems) do
            local menuOption = RedTape.CONTROLS[id]
            if menuOption then
                local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser
                menuOption:setState(RedTape.getStateIndex(id))
                menuOption:setDisabled(not isAdmin)
            end
        end
    end
end
