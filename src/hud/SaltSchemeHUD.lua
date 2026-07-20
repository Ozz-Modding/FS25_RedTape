RTSaltSchemeHUD = {}
RTSaltSchemeHUD_mt = Class(RTSaltSchemeHUD)

-- Fixed normalised screen position (0-1). Bottom-left area.
RTSaltSchemeHUD.POS_X     = 0.01
RTSaltSchemeHUD.POS_Y     = 0.01
RTSaltSchemeHUD.FONT_SIZE = 0.015

function RTSaltSchemeHUD.new()
    local self = {}
    setmetatable(self, RTSaltSchemeHUD_mt)

    self.isVisible    = false
    self.earningsText = ""

    return self
end

-- Polled every 2 seconds from RedTape:update. Sets visibility based on whether
-- the local farm has an active salt scheme right now.
function RTSaltSchemeHUD:syncVisibility()
    local myFarmId = g_currentMission:getFarmId()
    if not myFarmId or myFarmId == 0 then
        self.isVisible = false
        return
    end

    local rt = g_currentMission.RedTape
    local farmGatherer = rt.InfoGatherer.gatherers[INFO_KEYS.FARMS]
    local scheme = farmGatherer:_getActiveSaltScheme(rt.SchemeSystem, myFarmId)

    if scheme == nil then
        self.isVisible = false
        return
    end

    self.isVisible = true

    -- On the server, always recalculate from the authoritative saltCount so a
    -- loaded save shows the correct value immediately rather than waiting for a sync.
    if g_currentMission:getIsServer() then
        local tierInfo = RTSchemes[RTSchemeIds.ROAD_SNOW_CLEARING].tiers[scheme.tier]
        local farmData = rt.InfoGatherer.gatherers[INFO_KEYS.FARMS]:getFarmData(myFarmId)
        local earnings = (farmData.saltCount or 0) * tierInfo.bonusPerBlock * EconomyManager.getPriceMultiplier()
        self.earningsText = self:_format(earnings)
    end
end

-- Called when a synced earnings value arrives (from the 5s broadcast or initial state).
function RTSaltSchemeHUD:refreshEarnings(earnings)
    self.earningsText = self:_format(earnings)
end

function RTSaltSchemeHUD:draw()
    if not self.isVisible then return end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.9)
    renderText(RTSaltSchemeHUD.POS_X, RTSaltSchemeHUD.POS_Y, RTSaltSchemeHUD.FONT_SIZE, self.earningsText)

    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
    setTextBold(false)
end

function RTSaltSchemeHUD:_format(earnings)
    return string.format(g_i18n:getText("rt_salt_scheme_hud_earnings"),
        g_i18n:formatMoney(earnings, 0, true, true))
end
