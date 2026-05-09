RTSettingsEvent = {}
RTSettingsEvent_mt = Class(RTSettingsEvent, Event)

InitEventClass(RTSettingsEvent, "RTSettingsEvent")

function RTSettingsEvent.emptyNew()
    local self = Event.new(RTSettingsEvent_mt)
    return self
end

function RTSettingsEvent.new()
    local self = RTSettingsEvent.emptyNew()
    self.taxEnabled = g_currentMission.RedTape.settings.taxEnabled
    self.policiesAndSchemesEnabled = g_currentMission.RedTape.settings.policiesAndSchemesEnabled
    self.grantsEnabled = g_currentMission.RedTape.settings.grantsEnabled
    self.baseTaxRate = g_currentMission.RedTape.settings.baseTaxRate
    self.productivityRecovery = g_currentMission.RedTape.settings.productivityRecovery
    self.manureStorageLimit = g_currentMission.RedTape.settings.manureStorageLimit
    return self
end

function RTSettingsEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.taxEnabled)
    streamWriteBool(streamId, self.policiesAndSchemesEnabled)
    streamWriteBool(streamId, self.grantsEnabled)
    streamWriteFloat32(streamId, self.baseTaxRate)
    streamWriteInt32(streamId, self.productivityRecovery)
    streamWriteInt32(streamId, self.manureStorageLimit)
end

function RTSettingsEvent:readStream(streamId, connection)
    self.taxEnabled = streamReadBool(streamId)
    self.policiesAndSchemesEnabled = streamReadBool(streamId)
    self.grantsEnabled = streamReadBool(streamId)
    self.baseTaxRate = streamReadFloat32(streamId)
    self.productivityRecovery = streamReadInt32(streamId)
    self.manureStorageLimit = streamReadInt32(streamId)
    self:run(connection)
end

function RTSettingsEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(RTSettingsEvent.new())
    end

    g_currentMission.RedTape.settings.taxEnabled = self.taxEnabled
    g_currentMission.RedTape.settings.policiesAndSchemesEnabled = self.policiesAndSchemesEnabled
    g_currentMission.RedTape.settings.grantsEnabled = self.grantsEnabled
    g_currentMission.RedTape.settings.baseTaxRate = self.baseTaxRate
    g_currentMission.RedTape.settings.productivityRecovery = self.productivityRecovery
    g_currentMission.RedTape.settings.manureStorageLimit = self.manureStorageLimit

    if not connection:getIsServer() then
        if (not g_currentMission.RedTape.settings.policiesAndSchemesEnabled) then
            g_currentMission.RedTape.PolicySystem:onDisabled()
            g_currentMission.RedTape.SchemeSystem:onDisabled()
        end
        if (not g_currentMission.RedTape.settings.grantsEnabled) then
            g_currentMission.RedTape.GrantSystem:onDisabled()
        end
    else
        -- Update UI controls if they exist
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
