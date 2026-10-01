MenuRedTape = {}
MenuRedTape.currentTasks = {}
MenuRedTape._mt = Class(MenuRedTape, TabbedMenuFrameElement)

MenuRedTape.SUB_CATEGORY = {
    POLICIES = 1,
    SCHEMES = 2,
    TAX = 3,
    EVENTLOG = 4,
    CROP_ROTATION = 5,
    GRANTS = 6
}

MenuRedTape.SCHEME_LIST_TYPE = {
    AVAILABLE = 1,
    ACTIVE = 2
}
MenuRedTape.SCHEME_STATE_TEXTS = { "ui_contractsNew", "ui_contractsActive" }

MenuRedTape.HEADER_SLICES = {
    [MenuRedTape.SUB_CATEGORY.POLICIES] = "gui.icon_ingameMenu_contracts",
    [MenuRedTape.SUB_CATEGORY.SCHEMES] = "gui.icon_ingameMenu_finances",
    [MenuRedTape.SUB_CATEGORY.TAX] = "gui.icon_ingameMenu_prices",
    [MenuRedTape.SUB_CATEGORY.EVENTLOG] = "gui.icon_ingameMenu_contracts",
    [MenuRedTape.SUB_CATEGORY.CROP_ROTATION] = "gui.icon_ingameMenu_calendar",
    [MenuRedTape.SUB_CATEGORY.GRANTS] = "gui.icon_ingameMenu_finances",
}
MenuRedTape.HEADER_TITLES = {
    [MenuRedTape.SUB_CATEGORY.POLICIES] = "rt_header_policies",
    [MenuRedTape.SUB_CATEGORY.SCHEMES] = "rt_header_schemes",
    [MenuRedTape.SUB_CATEGORY.TAX] = "rt_header_tax",
    [MenuRedTape.SUB_CATEGORY.EVENTLOG] = "rt_header_eventlog",
    [MenuRedTape.SUB_CATEGORY.CROP_ROTATION] = "rt_header_croprotation",
    [MenuRedTape.SUB_CATEGORY.GRANTS] = "rt_header_grants",
}

function MenuRedTape.new(i18n, messageCenter)
    local self = MenuRedTape:superClass().new(nil, MenuRedTape._mt)
    self.name = "MenuRedTape"
    self.i18n = i18n
    self.messageCenter = messageCenter
    self.menuButtonInfo = {}

    self.eventLogRenderer = RTEventLogRenderer.new()
    self.activePoliciesRenderer = RTActivePoliciesRenderer.new()
    self.schemesRenderer = RTSchemesRenderer.new()
    self.schemeReportRenderer = RTReportRenderer.new()
    self.policyReportRenderer = RTReportRenderer.new()
    self.taxNotesRenderer = RTTaxNotesRenderer.new()
    self.currentYearTaxNotesRenderer = RTTaxNotesRenderer.new()
    self.cropRotationRenderer = RTCropRotationRenderer.new()
    self.pendingGrantsRenderer = RTGrantsRenderer.new("pending")
    self.approvedGrantsRenderer = RTGrantsRenderer.new("approved")
    self.historicalGrantsRenderer = RTGrantsRenderer.new("historical")

    self.vehicleElements = {}

    return self
end

function MenuRedTape:displaySelectedPolicy()
    local index = self.activePoliciesTable.selectedIndex
    local rt = g_currentMission.RedTape

    if index ~= -1 then
        local policy = self.activePoliciesRenderer.data[index]

        if policy ~= nil then
            self.policyInfoContainer:setVisible(true)
            self.noSelectedPolicyText:setVisible(false)
            self.selectedPolicyName:setText(policy:getName())
            self.selectedPolicyDescription:setText(policy:getDescription())

            local nextEval = policy.nextEvaluationMonth % 12
            if nextEval == 0 then
                nextEval = 12
            end

            self.selectedPolicyReportNextDate:setText(string.format(g_i18n:getText("rt_header_next_evaluation_date"),
                RedTape.monthToString(nextEval)))
            local report = policy.evaluationReports[g_currentMission:getFarmId()] or {}

            if rt.tableCount(report) == 0 then
                self.policyReportContainer:setVisible(false)
                self.noPolicyReportContainer:setVisible(true)
                self.selectedPolicyReportDescription:setVisible(false)
            else
                self.policyReportContainer:setVisible(true)
                self.noPolicyReportContainer:setVisible(false)
                self.policyReportRenderer:setData(report)
                self.selectedPolicyReportDescription:setVisible(true)
                self.selectedPolicyReportDescription:setText(policy:getReportDescription())
                self.policyReportTable:reloadData()
            end
        else
            self.policyInfoContainer:setVisible(false)
            self.noSelectedPolicyText:setVisible(true)
        end
    end
end

function MenuRedTape:displaySelectedScheme()
    local index = self.schemesTable.selectedIndex
    local rt = g_currentMission.RedTape

    if index ~= -1 then
        local selection = self.schemeDisplaySwitcher:getState()
        local scheme = self.schemesRenderer.data[selection][index]

        if scheme ~= nil then
            self.schemeInfoContainer:setVisible(true)
            self.noSelectedSchemeText:setVisible(false)
            self.selectedSchemeName:setText(scheme:getName())
            self.selectedSchemeDescription:setText(scheme:getDescription())

            if selection == MenuRedTape.SCHEME_LIST_TYPE.AVAILABLE then
                self.activeSchemeInfo:setVisible(false)
                self:updateSchemeEquipmentBox(scheme)
            elseif selection == MenuRedTape.SCHEME_LIST_TYPE.ACTIVE then
                self.activeSchemeInfo:setVisible(true)
                self.schemeEquipmentBox:setVisible(false)

                local nextEval = scheme:getNextEvaluationMonth()
                -- nil when the scheme lacks the saved data to work it out (it ends at the next month end)
                self.selectedSchemeReportNextDate:setText(string.format(g_i18n:getText("rt_header_next_evaluation_date"),
                    tostring(RedTape.monthToString(nextEval) or "-")))

                if rt.tableCount(scheme.lastEvaluationReport) == 0 then
                    self.schemeReportContainer:setVisible(false)
                    self.noSchemeReportContainer:setVisible(true)
                    self.selectedSchemeReportDescription:setVisible(false)
                else
                    self.schemeReportContainer:setVisible(true)
                    self.noSchemeReportContainer:setVisible(false)
                    self.schemeReportRenderer:setData(scheme.lastEvaluationReport)
                    self.selectedSchemeReportDescription:setVisible(true)
                    self.selectedSchemeReportDescription:setText(scheme:getReportDescription())
                    self.schemeReportTable:reloadData()
                end
            end
        else
            self.schemeInfoContainer:setVisible(false)
            self.noSelectedSchemeText:setVisible(true)
        end
    end
    self:updateSchemeActionButton()
end

function MenuRedTape:updateSchemeEquipmentBox(scheme)
    for _, v in pairs(self.vehicleElements) do
        v:delete()
    end
    self.vehicleElements = {}
    self.schemeVehiclesBox:invalidateLayout()
    local schemeInfo = RTSchemes[scheme.schemeIndex]

    local vehicles = scheme:getVehiclesToSpawn()

    if vehicles == nil or #vehicles == 0 then
        self.schemeEquipmentBox:setVisible(false)
        return
    end

    local totalWidth = 0
    for _, storeItem in ipairs(vehicles) do
        local vehicleImage = storeItem.imageFilename
        if storeItem.configurations ~= nil then
            for k, _ in pairs(storeItem.configurations) do
                local configId = storeItem.configurations[k]
                local config = storeItem.configurations[k][configId]
                if config ~= nil and (config.vehicleIcon ~= nil and config.vehicleIcon ~= "") then
                    vehicleImage = config.vehicleIcon
                    break
                end
            end
        end
        local newElement = self.vehicleTemplate:clone(self.schemeVehiclesBox)
        newElement:setImageFilename(vehicleImage)
        newElement:setImageColor(nil, nil, nil, nil, 1)
        totalWidth = totalWidth + newElement.absSize[1] + newElement.margin[1] + newElement.margin[3]
        table.insert(self.vehicleElements, newElement)
    end
    self.schemeVehiclesBox:setSize(totalWidth)
    self.schemeVehiclesBox:invalidateLayout()
    if self.schemeVehiclesBox.maxFlowSize > self.schemeVehiclesBox.parent.absSize[1] and self.schemeVehiclesBox.pivot[1] ~= 0 then
        self.schemeVehiclesBox:setPivot(0, 0.5)
    elseif self.schemeVehiclesBox.maxFlowSize <= self.schemeVehiclesBox.parent.absSize[1] and self.schemeVehiclesBox.pivot[1] ~= 0.5 then
        self.schemeVehiclesBox:setPivot(0.5, 0.5)
    end
    self.schemeVehiclesBox:setPosition(0)

    self.schemeEquipmentBox:setVisible(true)
end

function MenuRedTape:onGuiSetupFinished()
    MenuRedTape:superClass().onGuiSetupFinished(self)

    self.farmEventsTable:setDataSource(self.eventLogRenderer)
    self.farmEventsTable:setDelegate(self.eventLogRenderer)

    self.activePoliciesTable:setDataSource(self.activePoliciesRenderer)
    self.activePoliciesTable:setDelegate(self.activePoliciesRenderer)

    self.activePoliciesRenderer.indexChangedCallback = function(index)
        self:displaySelectedPolicy()
    end

    self.schemesTable:setDataSource(self.schemesRenderer)
    self.schemesTable:setDelegate(self.schemesRenderer)

    self.schemesRenderer.indexChangedCallback = function(index)
        self:displaySelectedScheme()
    end

    self.schemeReportTable:setDataSource(self.schemeReportRenderer)
    self.schemeReportTable:setDelegate(self.schemeReportRenderer)

    self.policyReportTable:setDataSource(self.policyReportRenderer)
    self.policyReportTable:setDelegate(self.policyReportRenderer)

    self.taxNotesTable:setDataSource(self.taxNotesRenderer)
    self.taxNotesTable:setDelegate(self.taxNotesRenderer)

    self.currentYearTaxNotesTable:setDataSource(self.currentYearTaxNotesRenderer)
    self.currentYearTaxNotesTable:setDelegate(self.currentYearTaxNotesRenderer)

    self.cropHistoryTable:setDataSource(self.cropRotationRenderer)
    self.cropHistoryTable:setDelegate(self.cropRotationRenderer)

    self.pendingGrantsTable:setDataSource(self.pendingGrantsRenderer)
    self.pendingGrantsTable:setDelegate(self.pendingGrantsRenderer)

    self.approvedGrantsTable:setDataSource(self.approvedGrantsRenderer)
    self.approvedGrantsTable:setDelegate(self.approvedGrantsRenderer)

    self.historicalGrantsTable:setDataSource(self.historicalGrantsRenderer)
    self.historicalGrantsTable:setDelegate(self.historicalGrantsRenderer)
end

function MenuRedTape:initialize()
    MenuRedTape:superClass().initialize(self)
    for i, tab in pairs(self.subCategoryTabs) do
        tab:getDescendantByName("background").getIsSelected = function()
            return i == self.subCategoryPaging:getState()
        end
        function tab.getIsSelected()
            return i == self.subCategoryPaging:getState()
        end
    end

    -- Set the available/active scheme switcher texts
    local schemeSwitcherTexts = {}
    for k, v in pairs(MenuRedTape.SCHEME_STATE_TEXTS) do
        table.insert(schemeSwitcherTexts, g_i18n:getText(v))
    end
    self.schemeDisplaySwitcher:setTexts(schemeSwitcherTexts)

    self.btnBack = {
        inputAction = InputAction.MENU_BACK
    }
    self.btnNextPage = {
        inputAction = InputAction.MENU_PAGE_NEXT,
        text = g_i18n:getText("ui_ingameMenuNext"),
        callback = self.onPageNext
    }
    self.btnPrevPage = {
        inputAction = InputAction.MENU_PAGE_PREV,
        text = g_i18n:getText("ui_ingameMenuPrev"),
        callback = self.onPagePrevious
    }

    self.menuButtonInfoDefault = { self.btnBack, self.btnNextPage, self.btnPrevPage }
    self.menuButtonInfo[MenuRedTape.SUB_CATEGORY.EVENTLOG] = self.menuButtonInfoDefault
    self.menuButtonInfo[MenuRedTape.SUB_CATEGORY.CROP_ROTATION] = self.menuButtonInfoDefault
    self.menuButtonInfo[MenuRedTape.SUB_CATEGORY.TAX] = self.menuButtonInfoDefault
    self.menuButtonInfo[MenuRedTape.SUB_CATEGORY.GRANTS] = self.menuButtonInfoDefault

    self.btnSelectSchemeForFarm = {
        inputAction = InputAction.MENU_ACTIVATE,
        text = g_i18n:getText("rt_btn_select_scheme"),
        callback = function()
            self:onSelectOrEndScheme()
        end
    }

    self.btnWatchSchemeOrPolicy = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("rt_btn_watch_scheme_policy"),
        callback = function()
            self:onToggleWatch()
        end
    }

    self.btnSchemeAction = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = g_i18n:getText("rt_btn_scheme_action"),
        callback = function()
            self:onSchemeAction()
        end,
        disabled = true
    }

    self.menuButtonInfo[MenuRedTape.SUB_CATEGORY.SCHEMES] = {
        self.btnBack,
        self.btnNextPage,
        self.btnPrevPage,
        self.btnSchemeAction,
        self.btnWatchSchemeOrPolicy,
        self.btnSelectSchemeForFarm,
    }

    self.menuButtonInfo[MenuRedTape.SUB_CATEGORY.POLICIES] = {
        self.btnWatchSchemeOrPolicy,
        self.btnBack,
        self.btnNextPage,
        self.btnPrevPage
    }

    self.vehicleTemplate:unlinkElement()
    self.tableHeaderBox:invalidateLayout()
end

function MenuRedTape:getMenuButtonInfo()
    return self.menuButtonInfo[self.subCategoryPaging:getState()]
end

function MenuRedTape:onFrameOpen()
    -- local xmlFile = loadXMLFile("Temp", "dataS/gui/InGameMenuCalendarFrame.xml")
    -- saveXMLFileTo(xmlFile, g_currentMission.missionInfo.savegameDirectory .. "/InGameMenuCalendarFrame.xml")
    -- delete(xmlFile);

    local texts = {}
    for k, tab in pairs(self.subCategoryTabs) do
        tab:setVisible(true)
        table.insert(texts, tostring(k))
    end
    self.subCategoryBox:invalidateLayout()
    self.subCategoryPaging:setTexts(texts)
    self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)

    self:onMoneyChange()
    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.onMoneyChange, self)
    g_messageCenter:subscribe(MessageType.RT_DATA_UPDATED, self.updateContent, self)
    self:updateContent()
    self:setMenuButtonInfoDirty()
    -- FocusManager:setFocus(self.subCategoryPaging)
end

function MenuRedTape:onFrameClose()
    MenuRedTape:superClass().onFrameClose(self)
    g_messageCenter:unsubscribeAll(self)
end

function MenuRedTape:onClickPolicies()
    self.subCategoryPaging:setState(MenuRedTape.SUB_CATEGORY.POLICIES, true)

    self:setMenuButtonInfoDirty()
end

function MenuRedTape:onClickSchemes()
    self.subCategoryPaging:setState(MenuRedTape.SUB_CATEGORY.SCHEMES, true)

    self:setMenuButtonInfoDirty()
end

function MenuRedTape:onClickTax()
    self.subCategoryPaging:setState(MenuRedTape.SUB_CATEGORY.TAX, true)

    self:setMenuButtonInfoDirty()
end

function MenuRedTape:onClickEventLog()
    self.subCategoryPaging:setState(MenuRedTape.SUB_CATEGORY.EVENTLOG, true)

    self:setMenuButtonInfoDirty()
end

function MenuRedTape:onClickCropRotation()
    self.subCategoryPaging:setState(MenuRedTape.SUB_CATEGORY.CROP_ROTATION, true)

    self:setMenuButtonInfoDirty()
end

function MenuRedTape:onClickGrants()
    self.subCategoryPaging:setState(MenuRedTape.SUB_CATEGORY.GRANTS, true)

    self:setMenuButtonInfoDirty()
end

function MenuRedTape:updateSubCategoryPages(subCategoryIndex)
    self:updateContent()
    self:setMenuButtonInfoDirty()
    -- FocusManager:setFocus(self.subCategoryPaging)
end

function MenuRedTape:onSwitchSchemeDisplay()
    self.schemesTable:reloadData()
    local hasItem = self.schemesTable:getItemCount() > 0
    self.schemesContainer:setVisible(hasItem)
    self.noSchemesContainer:setVisible(not hasItem)
    if hasItem then
        self.schemesTable:setSelectedIndex(1)
    end
    self:displaySelectedScheme()
    if self.schemeDisplaySwitcher:getState() ~= MenuRedTape.SCHEME_LIST_TYPE.AVAILABLE then
        self.btnSelectSchemeForFarm.text = g_i18n:getText("rt_btn_end_scheme")
    else
        self.btnSelectSchemeForFarm.text = g_i18n:getText("rt_btn_select_scheme")
    end


    self.btnWatchSchemeOrPolicy.disabled = self.schemeDisplaySwitcher:getState() ~=
        MenuRedTape.SCHEME_LIST_TYPE.ACTIVE
    self:updateSchemeActionButton()
    self:setMenuButtonInfoDirty()
end

function MenuRedTape:updateContent()
    local state = self.subCategoryPaging:getState()

    self.categoryHeaderIcon:setImageSlice(nil, MenuRedTape.HEADER_SLICES[state])
    self.categoryHeaderText:setText(g_i18n:getText(MenuRedTape.HEADER_TITLES[state]))

    for k, v in pairs(self.subCategoryPages) do
        v:setVisible(k == state)
    end

    if state == MenuRedTape.SUB_CATEGORY.POLICIES then
        if (not g_currentMission.RedTape.settings.policiesAndSchemesEnabled) then
            self.policySystemDisabledMessage:setVisible(true)
            self.policySystemEnabledInfo:setVisible(false)
            return
        end

        self.policySystemDisabledMessage:setVisible(false)
        self.policySystemEnabledInfo:setVisible(true)

        local policySystem = g_currentMission.RedTape.PolicySystem
        local activePolicies = policySystem:getEnforcedPolicies()
        local progress = policySystem:getProgressForCurrentFarm()

        if progress == nil then
            self.complianceTier:setText(string.format(g_i18n:getText("rt_header_current_tier"), "-"))
            self.progressText:setVisible(false)
            self.progressBar:setVisible(false)
            return
        end

        self.progressText:setVisible(true)
        self.progressBar:setVisible(true)

        self.complianceTier:setText(string.format(g_i18n:getText("rt_header_current_tier"),
            RTPolicySystem.TIER_NAMES[progress.tier]))
        self.progressText:setText(string.format("%d/%d", progress.points, progress.nextTierPoints))
        local fullWidth = self.progressBarBg.size[1] - self.progressBar.margin[1] * 2
        local minProgressBarWidthRatio = self.progressBar.startSize[1] * 2 / fullWidth
        local progressBarRatio = math.max(progress.progressPercentage, minProgressBarWidthRatio)
        self.progressBar:setSize(fullWidth * math.min(progressBarRatio, 1), nil)

        self.activePoliciesRenderer:setData(activePolicies)
        self.activePoliciesTable:reloadData()

        self.btnWatchSchemeOrPolicy.disabled = false
        self:displaySelectedPolicy()

        self.activePoliciesContainer:setVisible(self.activePoliciesTable:getItemCount() > 0)
        self.noActivePoliciesContainer:setVisible(self.activePoliciesTable:getItemCount() == 0)
    elseif state == MenuRedTape.SUB_CATEGORY.SCHEMES then
        if (not g_currentMission.RedTape.settings.policiesAndSchemesEnabled) then
            self.schemeSystemDisabledMessage:setVisible(true)
            self.schemeSystemEnabledInfo:setVisible(false)
            return
        end

        self.schemeSystemDisabledMessage:setVisible(false)
        self.schemeSystemEnabledInfo:setVisible(true)

        local schemeSystem = g_currentMission.RedTape.SchemeSystem
        local availableSchemes = schemeSystem:getAvailableSchemesForCurrentFarm()
        local activeSchemes = schemeSystem:getActiveSchemesForFarm(g_currentMission:getFarmId())

        local renderData = {
            [MenuRedTape.SCHEME_LIST_TYPE.AVAILABLE] = availableSchemes,
            [MenuRedTape.SCHEME_LIST_TYPE.ACTIVE] = activeSchemes
        }

        self.schemesRenderer:setData(renderData)
        self.schemesTable:reloadData()

        self.btnWatchSchemeOrPolicy.disabled = self.schemeDisplaySwitcher:getState() ~=
            MenuRedTape.SCHEME_LIST_TYPE.ACTIVE
        self:displaySelectedScheme()

        self.schemesContainer:setVisible(self.schemesTable:getItemCount() > 0)
        self.noSchemesContainer:setVisible(self.schemesTable:getItemCount() == 0)
    elseif state == MenuRedTape.SUB_CATEGORY.EVENTLOG then
        local farmEvents = g_currentMission.RedTape.EventLog:getEventsForCurrentFarm()

        if #farmEvents == 0 then
            self.farmEventsContainer:setVisible(false)
            self.noFarmEventsContainer:setVisible(true)
            return
        end

        self.farmEventsContainer:setVisible(true)
        self.noFarmEventsContainer:setVisible(false)

        self.eventLogRenderer:setData(farmEvents)
        self.farmEventsTable:reloadData()
    elseif state == MenuRedTape.SUB_CATEGORY.TAX then
        if (not g_currentMission.RedTape.settings.taxEnabled) then
            self.taxSystemDisabledMessage:setVisible(true)
            self.taxSystemEnabledInfo:setVisible(false)
            return
        end

        self.taxSystemDisabledMessage:setVisible(false)
        self.taxSystemEnabledInfo:setVisible(true)

        local taxSystem = g_currentMission.RedTape.TaxSystem
        local farmId = g_currentMission:getFarmId()
        local statement = taxSystem.taxStatements[farmId]

        local currentYearStatement = taxSystem:getCurrentYearTaxToDate(farmId)
        self.currentYearTaxTotalExpenses:setText(g_i18n:formatMoney(currentYearStatement.totalExpenses, 0, true, true))
        self.currentYearTaxTotalTaxable:setText(g_i18n:formatMoney(currentYearStatement.totalTaxableIncome, 0, true, true))
        self.currentYearTaxTotalTaxDue:setText(g_i18n:formatMoney(currentYearStatement.totalTax, 0, true, true))

        if #currentYearStatement.notes == 0 then
            self.currentYearTaxNotesContainer:setVisible(false)
            self.currentYearNoTaxNotesContainer:setVisible(true)
        else
            self.currentYearTaxNotesContainer:setVisible(true)
            self.currentYearNoTaxNotesContainer:setVisible(false)
            self.currentYearTaxNotesRenderer:setData(currentYearStatement.notes)
            self.currentYearTaxNotesTable:reloadData()
        end

        if statement == nil then
            self.taxStatementContainer:setVisible(false)
            self.noTaxStatementContainer:setVisible(true)
            return
        end

        self.taxStatementContainer:setVisible(true)
        self.noTaxStatementContainer:setVisible(false)

        self.taxTotalExpenses:setText(g_i18n:formatMoney(statement.totalExpenses, 0, true, true))
        self.taxTotalTaxable:setText(g_i18n:formatMoney(statement.totalTaxableIncome, 0, true, true))
        self.taxTotalTaxed:setText(g_i18n:formatMoney(statement.totalTaxedIncome, 0, true, true))
        self.taxTaxRate:setText(string.format("%.2f%%", statement.taxRate * 100))
        self.taxTotalTaxDue:setText(g_i18n:formatMoney(statement.totalTax, 0, true, true))
        self.taxStatementStatus:setText(statement.paid and
            g_i18n:getText("rt_tax_statement_status_paid") or g_i18n:getText("rt_tax_statement_status_unpaid"))

        if #statement.notes == 0 then
            self.taxNotesContainer:setVisible(false)
            self.noTaxNotesContainer:setVisible(true)
        else
            self.taxNotesContainer:setVisible(true)
            self.noTaxNotesContainer:setVisible(false)
            self.taxNotesRenderer:setData(statement.notes)
            self.taxNotesTable:reloadData()
        end
    elseif state == MenuRedTape.SUB_CATEGORY.CROP_ROTATION then
        local cropHistoryData = {}
        local currentFarmId = g_currentMission:getFarmId()
        local ig = g_currentMission.RedTape.InfoGatherer
        local gatherer = ig.gatherers[INFO_KEYS.FARMLANDS]

        for _, farmland in pairs(g_farmlandManager.farmlands) do
            if farmland.showOnFarmlandsScreen and farmland.field ~= nil and farmland.farmId == currentFarmId then
                local farmlandData = gatherer:getFarmlandData(farmland.id)

                local cropEntry = {
                    farmland = string.format(g_i18n:getText("rt_report_name_farmland"), farmland.id),
                    fruitName1 = "-",
                    fruitName2 = "-",
                    fruitName3 = "-",
                    fruitName4 = "-",
                    fruitName5 = "-",
                    fruitIcon1 = "",
                    fruitIcon2 = "",
                    fruitIcon3 = "",
                    fruitIcon4 = "",
                    fruitIcon5 = ""
                }

                for i = 1, math.min(5, #farmlandData.harvestedCropsHistory) do
                    local harvestEntry = farmlandData.harvestedCropsHistory[i]
                    local fruit = g_fruitTypeManager.nameToFruitType[harvestEntry.name]

                    if fruit ~= nil then
                        local fillType = g_fruitTypeManager:getFillTypeByFruitTypeIndex(fruit.index)
                        cropEntry["fruitName" .. i] = fruit.title or harvestEntry.name
                        cropEntry["fruitIcon" .. i] = fillType.hudOverlayFilename or ""
                    end
                end

                table.insert(cropHistoryData, cropEntry)
            end
        end

        self.cropRotationRenderer:setData(cropHistoryData)
        self.cropHistoryTable:reloadData()
    elseif state == MenuRedTape.SUB_CATEGORY.GRANTS then
        if (not g_currentMission.RedTape.settings.grantsEnabled) then
            self.grantSystemDisabledMessage:setVisible(true)
            self.grantSystemEnabledInfo:setVisible(false)
            return
        end

        self.grantSystemDisabledMessage:setVisible(false)
        self.grantSystemEnabledInfo:setVisible(true)

        local grantSystem = g_currentMission.RedTape.GrantSystem
        local currentFarmId = g_currentMission:getFarmId()
        local canApply = grantSystem:canFarmApplyForGrant(currentFarmId)
        local farmGrants = grantSystem:getGrantsForFarm(currentFarmId)

        if canApply then
            self.grantEligibilityStatus:setText(g_i18n:getText("rt_grant_eligible"))
        else
            self.grantEligibilityStatus:setText(g_i18n:getText("rt_grant_not_eligible"))
        end

        local grantsData = {
            pending = farmGrants.pending or {},
            approved = farmGrants.approved or {},
            historical = {}
        }

        for _, grant in pairs(grantSystem.grants) do
            if grant.farmId == currentFarmId and
                (grant.status == RTGrantSystem.STATUS.REJECTED or grant.status == RTGrantSystem.STATUS.COMPLETE) then
                table.insert(grantsData.historical, grant)
            end
        end

        -- Visibility is applied before the lists are rebuilt, and RTGrantsRenderer tolerates
        -- malformed grants, so a single bad grant can never leave the page half updated.
        local hasPendingGrants = #grantsData.pending > 0
        self.pendingGrantsContainer:setVisible(hasPendingGrants)
        self.noPendingGrantsContainer:setVisible(not hasPendingGrants)

        local hasApprovedGrants = #grantsData.approved > 0
        self.approvedGrantsContainer:setVisible(hasApprovedGrants)
        self.noApprovedGrantsContainer:setVisible(not hasApprovedGrants)

        local hasHistoricalGrants = #grantsData.historical > 0
        self.historicalGrantsContainer:setVisible(hasHistoricalGrants)
        self.noHistoricalGrantsContainer:setVisible(not hasHistoricalGrants)

        self.pendingGrantsRenderer:setData(grantsData)
        self.approvedGrantsRenderer:setData(grantsData)
        self.historicalGrantsRenderer:setData(grantsData)

        for _, grantsTable in pairs({ self.pendingGrantsTable, self.approvedGrantsTable, self.historicalGrantsTable }) do
            grantsTable:reloadData()
        end
    end

    self:updateMenuButtons()
end

function MenuRedTape:updateMenuButtons()
    local state = self.subCategoryPaging:getState()
end

function MenuRedTape:onMoneyChange()
    if g_localPlayer ~= nil then
        local farm = g_farmManager:getFarmById(g_localPlayer.farmId)
        if farm.money <= -1 then
            self.currentBalanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY_NEGATIVE, nil, true)
        else
            self.currentBalanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY, nil, true)
        end
        local moneyText = g_i18n:formatMoney(farm.money, 0, true, false)
        self.currentBalanceText:setText(moneyText)
        if self.shopMoneyBox ~= nil then
            self.shopMoneyBox:invalidateLayout()
            self.shopMoneyBoxBg:setSize(self.shopMoneyBox.flowSizes[1] + 60 * g_pixelSizeScaledX)
        end
    end
end

function MenuRedTape:onSelectOrEndScheme()
    if self.schemesRenderer.selectedRow == -1 then
        return
    end
    local schemeSystem = g_currentMission.RedTape.SchemeSystem

    if self.schemeDisplaySwitcher:getState() ~= MenuRedTape.SCHEME_LIST_TYPE.AVAILABLE then
        local scheme = self.schemesRenderer.data[MenuRedTape.SCHEME_LIST_TYPE.ACTIVE][self.schemesRenderer.selectedRow]
        YesNoDialog.show(
            function(self, clickOk)
                if clickOk then
                    local farmId = g_currentMission:getFarmId()
                    g_client:getServerConnection():sendEvent(RTSchemeEndedEvent.new(scheme.id, farmId))
                end
            end, self,
            g_i18n:getText("rt_misc_confirm_scheme_end"))
    else
        local scheme = self.schemesRenderer.data[MenuRedTape.SCHEME_LIST_TYPE.AVAILABLE]
            [self.schemesRenderer.selectedRow]
        local vehicles = scheme:getVehiclesToSpawn()

        if not schemeSystem.isSpawnSpaceAvailable(vehicles) then
            InfoDialog.show(g_i18n:getText("rt_no_vehicle_room"))
            return
        end

        YesNoDialog.show(
            function(self, clickOk)
                if clickOk then
                    local farmId = g_currentMission:getFarmId()
                    g_client:getServerConnection():sendEvent(RTSchemeSelectedEvent.new(scheme, farmId))
                    InfoDialog.show(g_i18n:getText("rt_info_scheme_selected"))
                end
            end, self,
            g_i18n:getText("rt_misc_confirm_scheme_selection"))
    end
end

function MenuRedTape:updateSchemeActionButton()
    local enabled = false
    if self.schemeDisplaySwitcher:getState() == MenuRedTape.SCHEME_LIST_TYPE.ACTIVE then
        local index = self.schemesTable.selectedIndex
        if index ~= nil and index ~= -1 then
            local scheme = self.schemesRenderer.data[MenuRedTape.SCHEME_LIST_TYPE.ACTIVE][index]
            if scheme ~= nil then
                local schemeInfo = RTSchemes[scheme.schemeIndex]
                if schemeInfo ~= nil and schemeInfo.action ~= nil then
                    enabled = true
                end
            end
        end
    end
    self.btnSchemeAction.disabled = not enabled
    self:setMenuButtonInfoDirty()
end

function MenuRedTape:onSchemeAction()
    if self.schemesRenderer.selectedRow == -1 then return end
    if self.schemeDisplaySwitcher:getState() ~= MenuRedTape.SCHEME_LIST_TYPE.ACTIVE then return end

    local scheme = self.schemesRenderer.data[MenuRedTape.SCHEME_LIST_TYPE.ACTIVE][self.schemesRenderer.selectedRow]
    if scheme == nil then return end

    local schemeInfo = RTSchemes[scheme.schemeIndex]
    if schemeInfo == nil or schemeInfo.action == nil then return end

    local text = schemeInfo.action.description(schemeInfo, scheme)
    if text == nil then return end

    local price = tonumber(scheme.props['buyPrice']) or 0
    YesNoDialog.show(
        function(self, clickOk)
            if clickOk then
                local farmId = g_currentMission:getFarmId()
                g_client:getServerConnection():sendEvent(RTSchemeBuyVehiclesEvent.new(scheme.id, farmId, price))
            end
        end, self,
        text)
end

function MenuRedTape:onToggleWatch()
    local state = self.subCategoryPaging:getState()

    if state == MenuRedTape.SUB_CATEGORY.POLICIES then
        if self.activePoliciesRenderer.selectedRow == -1 then
            return
        end

        local policy = self.activePoliciesRenderer.data[self.activePoliciesRenderer.selectedRow]
        local farmId = g_currentMission:getFarmId()

        g_client:getServerConnection():sendEvent(RTPolicyWatchToggleEvent.new(policy.id, farmId))
    elseif state == MenuRedTape.SUB_CATEGORY.SCHEMES then
        if self.schemesRenderer.selectedRow == -1 then
            return
        end

        if self.schemeDisplaySwitcher:getState() ~= MenuRedTape.SCHEME_LIST_TYPE.ACTIVE then
            return
        end

        local selection = self.schemeDisplaySwitcher:getState()
        if selection ~= MenuRedTape.SCHEME_LIST_TYPE.ACTIVE then
            return
        end

        local scheme = self.schemesRenderer.data[selection][self.schemesRenderer.selectedRow]
        local farmId = g_currentMission:getFarmId()

        g_client:getServerConnection():sendEvent(RTSchemeWatchToggleEvent.new(scheme.id))
    end
end
