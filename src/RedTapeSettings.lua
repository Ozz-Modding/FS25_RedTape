RedTape.SETTINGS = {}
RedTape.CONTROLS = {}

RedTape.menuItems = {
    'taxEnabled',
    'policiesAndSchemesEnabled',
    'grantsEnabled',
    'baseTaxRate',
    'productivityRecovery',
    'manureStorageLimit'
}

RedTape.multiplayerPermissions = {
    'redTapeSettings'
}

Farm.PERMISSION['RED_TAPE_SETTINGS'] = "redTapeSettings"
table.insert(Farm.PERMISSIONS, Farm.PERMISSION.RED_TAPE_SETTINGS)

--SERVER SETTINGS
RedTape.SETTINGS.taxEnabled = {
    ['default'] = 1,
    ['serverOnly'] = true,
    ['permission'] = 'redTapeSettings',
    ['values'] = { true, false },
    ['strings'] = {
        g_i18n:getText("ui_on"),
        g_i18n:getText("ui_off")
    }
}

RedTape.SETTINGS.policiesAndSchemesEnabled = {
    ['default'] = 1,
    ['serverOnly'] = true,
    ['permission'] = 'redTapeSettings',
    ['values'] = { true, false },
    ['strings'] = {
        g_i18n:getText("ui_on"),
        g_i18n:getText("ui_off")
    }
}

RedTape.SETTINGS.grantsEnabled = {
    ['default'] = 1,
    ['serverOnly'] = true,
    ['permission'] = 'redTapeSettings',
    ['values'] = { true, false },
    ['strings'] = {
        g_i18n:getText("ui_on"),
        g_i18n:getText("ui_off")
    }
}

RedTape.SETTINGS.baseTaxRate = {
    ['default'] = 2,
    ['serverOnly'] = true,
    ['permission'] = 'redTapeSettings',
    ['values'] = { 10, 20, 30, 40 },
    ['strings'] = {
        "10%",
        "20%",
        "30%",
        "40%"
    }
}

RedTape.SETTINGS.productivityRecovery = {
    ['default'] = 1,
    ['serverOnly'] = true,
    ['permission'] = 'redTapeSettings',
    ['values'] = { 1, 2, 4, 6, 8, 0 },
    ['strings'] = {
        "1x",
        "2x",
        "4x",
        "6x",
        "8x",
        g_i18n:getText("rt_setting_instant")
    }
}

RedTape.SETTINGS.manureStorageLimit = {
    ['default'] = 1,
    ['serverOnly'] = true,
    ['permission'] = 'redTapeSettings',
    ['values'] = { 5000, 10000, 20000, 50000, 100000 },
    ['strings'] = {
        "5,000",
        "10,000",
        "20,000",
        "50,000",
        "100,000"
    }
}



function RedTape.getStateIndex(id, value)
    local value = value or g_currentMission.RedTape.settings[id]
    local values = RedTape.SETTINGS[id].values
    if type(value) == 'number' then
        local index = RedTape.SETTINGS[id].default
        local initialdiff = math.huge
        for i, v in pairs(values) do
            local currentdiff = math.abs(v - value)
            if currentdiff < initialdiff then
                initialdiff = currentdiff
                index = i
            end
        end
        return index
    else
        for i, v in pairs(values) do
            if value == v then
                return i
            end
        end
    end
    return RedTape.SETTINGS[id].default
end

RedTapeControls = {}
function RedTapeControls.onMenuOptionChanged(self, state, menuOption)
    local id = menuOption.id
    local setting = RedTape.SETTINGS
    local value = setting[id].values[state]

    if value ~= nil then
        g_currentMission.RedTape.settings[id] = value
    end

    g_client:getServerConnection():sendEvent(RTSettingsEvent.new())
end

local function updateFocusIds(element)
    if not element then
        return
    end
    element.focusId = FocusManager:serveAutoFocusId()
    for _, child in pairs(element.elements) do
        updateFocusIds(child)
    end
end

function RedTape.injectMenu()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    local settingsPage = inGameMenu.pageSettings
    -- The name is required as otherwise the focus manager would ignore any control which has RedTape as a callback target, believing it belonged to a different UI
    RedTapeControls.name = settingsPage.name

    function RedTape.addBinaryMenuOption(id)
        local callback = "onMenuOptionChanged"
        local i18n_title = "rt_setting_" .. id
        local i18n_tooltip = "rt_toolTip_" .. id
        local options = RedTape.SETTINGS[id].strings

        local originalBox = settingsPage.checkWoodHarvesterAutoCutBox

        local menuOptionBox = originalBox:clone(settingsPage.gameSettingsLayout)
        menuOptionBox.id = id .. "box"

        local menuBinaryOption = menuOptionBox.elements[1]
        menuBinaryOption.id = id
        menuBinaryOption.target = RedTapeControls


        menuBinaryOption:setCallback("onClickCallback", callback)
        menuBinaryOption:setDisabled(false)


        local toolTip = menuBinaryOption.elements[1]
        toolTip:setText(g_i18n:getText(i18n_tooltip))

        local setting = menuOptionBox.elements[2]
        setting:setText(g_i18n:getText(i18n_title))

        menuBinaryOption:setTexts({ table.unpack(options) })
        menuBinaryOption:setState(RedTape.getStateIndex(id))

        RedTape.CONTROLS[id] = menuBinaryOption

        -- Assign new focus IDs to the controls as clone() copies the existing ones which are supposed to be unique
        updateFocusIds(menuOptionBox)
        table.insert(settingsPage.controlsList, menuOptionBox)
        return menuOptionBox
    end

    function RedTape.addMultiMenuOption(id)
        local callback = "onMenuOptionChanged"
        local i18n_title = "rt_setting_" .. id
        local i18n_tooltip = "rt_toolTip_" .. id
        local options = RedTape.SETTINGS[id].strings

        local originalBox = settingsPage.multiVolumeVoiceBox

        local menuOptionBox = originalBox:clone(settingsPage.gameSettingsLayout)
        menuOptionBox.id = id .. "box"

        local menuMultiOption = menuOptionBox.elements[1]
        menuMultiOption.id = id
        menuMultiOption.target = RedTapeControls


        menuMultiOption:setCallback("onClickCallback", callback)
        menuMultiOption:setDisabled(false)


        local toolTip = menuMultiOption.elements[1]
        toolTip:setText(g_i18n:getText(i18n_tooltip))

        local setting = menuOptionBox.elements[2]
        setting:setText(g_i18n:getText(i18n_title))

        menuMultiOption:setTexts({ table.unpack(options) })
        menuMultiOption:setState(RedTape.getStateIndex(id))

        RedTape.CONTROLS[id] = menuMultiOption

        -- Assign new focus IDs to the controls as clone() copies the existing ones which are supposed to be unique
        updateFocusIds(menuOptionBox)
        table.insert(settingsPage.controlsList, menuMultiOption)
        return menuOptionBox
    end

    -- Add section
    local sectionTitle = nil
    for idx, elem in ipairs(settingsPage.gameSettingsLayout.elements) do
        if elem.name == "sectionHeader" then
            sectionTitle = elem:clone(settingsPage.gameSettingsLayout)
            break
        end
    end

    if sectionTitle then
        sectionTitle:setText(g_i18n:getText("rt_help_title_red_tape"))
    else
        sectionTitle = TextElement.new()
        sectionTitle:applyProfile("fs25_settingsSectionHeader", true)
        sectionTitle:setText(g_i18n:getText("rt_help_title_red_tape"))
        sectionTitle.name = "sectionHeader"
        settingsPage.gameSettingsLayout:addElement(sectionTitle)
    end
    -- Apply a new focus ID in either case - either the element doesn't have one right now, or it has an already used one
    -- This is required for proper keyboard/controller navigation in the menu
    sectionTitle.focusId = FocusManager:serveAutoFocusId()
    table.insert(settingsPage.controlsList, sectionTitle)
    -- The title needs to be passed to the focus manager later on, otherwise skipping over the section title with up/down keys will fail
    RedTape.CONTROLS[sectionTitle.name] = sectionTitle

    for _, id in pairs(RedTape.menuItems) do
        if #RedTape.SETTINGS[id].values == 2 then
            RedTape.addBinaryMenuOption(id)
        else
            RedTape.addMultiMenuOption(id)
        end
    end

    settingsPage.gameSettingsLayout:invalidateLayout()

    -- MULTIPLAYER PERMISSIONS
    local multiplayerPage = inGameMenu.pageMultiplayer

    function RedTape.addMultiplayerPermission(id)
        local newPermissionName = id .. 'PermissionCheckbox'
        local i18n_title = "permission_redTape_" .. id

        local original = multiplayerPage.cutTreesPermissionCheckbox.parent
        local newPermissionRow = original:clone(multiplayerPage.permissionsBox)

        local newPermissionCheckbox = newPermissionRow.elements[1]
        newPermissionCheckbox.id = newPermissionName

        local newPermissionLabel = newPermissionRow.elements[2]
        newPermissionLabel:setText(g_i18n:getText(i18n_title))

        table.insert(multiplayerPage.permissionRow, newPermissionRow)

        multiplayerPage.controlIDs[newPermissionName] = true
        multiplayerPage.permissionCheckboxes[id] = newPermissionCheckbox
        multiplayerPage.checkboxPermissions[newPermissionCheckbox] = id
    end

    for _, id in pairs(RedTape.multiplayerPermissions) do
        RedTape.addMultiplayerPermission(id)
    end

    -- ENABLE/DISABLE OPTIONS FOR CLIENTS
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
        local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser

        for _, id in pairs(RedTape.menuItems) do
            local menuOption = RedTape.CONTROLS[id]
            menuOption:setState(RedTape.getStateIndex(id))

            if RedTape.SETTINGS[id].disabled then
                menuOption:setDisabled(true)
            elseif RedTape.SETTINGS[id].serverOnly and g_server == nil then
                menuOption:setDisabled(not isAdmin)
            else
                local permission = RedTape.SETTINGS[id].permission
                local hasPermission = g_currentMission:getHasPlayerPermission(permission)

                local canChange = isAdmin or hasPermission or false
                menuOption:setDisabled(not canChange)
            end
        end
    end)
end

-- Allow keyboard navigation of menu options
FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
    if gui == "ingameMenuSettings" then
        -- Let the focus manager know about our custom controls now (earlier than this point seems to fail)
        for _, control in pairs(RedTape.CONTROLS) do
            if not control.focusId or not FocusManager.currentFocusData.idToElementMapping[control.focusId] then
                if not FocusManager:loadElementFromCustomValues(control, nil, nil, false, false) then
                    print(
                        "Could not register control %s with the focus manager. Selecting the control might be bugged",
                        control.id or control.name or control.focusId)
                end
            end
        end
        -- Invalidate the layout so the up/down connections are analyzed again by the focus manager
        local settingsPage = g_gui.screenControllers[InGameMenu].pageSettings
        settingsPage.gameSettingsLayout:invalidateLayout()
    end
end)


--SEND SETTINGS TO CLIENT:
FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState,
    function(self, connection, user, farm)
        -- Send all RedTape settings to the new client
        g_client:getServerConnection():sendEvent(RTSettingsEvent.new())
    end)
