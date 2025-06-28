-- Get the GLOBAL addon table correctly
local addonNameString, privateTable = ...
_G.BoxxyAuras = _G.BoxxyAuras or {}
local BoxxyAuras = _G.BoxxyAuras -- Use the global table

-- Remove redundant AllAuras creation if it's already done in BoxxyAuras.lua
-- BoxxyAuras.AllAuras = {}

-- PixelUtil Compatibility Layer
local PixelUtilCompat = {}

-- Standard WoW API fallback functions
local function FallbackSetPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
    frame:SetPoint(point, relativeTo, relativePoint, xOffset or 0, yOffset or 0)
end

local function FallbackSetSize(frame, width, height)
    frame:SetSize(width, height)
end

local function FallbackSetWidth(frame, width)
    frame:SetWidth(width)
end

local function FallbackSetHeight(frame, height)
    frame:SetHeight(height)
end

if PixelUtil then
    -- Use native PixelUtil with error handling - fall back to standard methods if they fail
    function PixelUtilCompat.SetPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
        local success, err = pcall(PixelUtil.SetPoint, frame, point, relativeTo, relativePoint, xOffset, yOffset)
        if not success then
            FallbackSetPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
        end
    end

    function PixelUtilCompat.SetSize(frame, width, height)
        local success, err = pcall(PixelUtil.SetSize, frame, width, height)
        if not success then
            FallbackSetSize(frame, width, height)
        end
    end

    function PixelUtilCompat.SetWidth(frame, width)
        local success, err = pcall(PixelUtil.SetWidth, frame, width)
        if not success then
            FallbackSetWidth(frame, width)
        end
    end

    function PixelUtilCompat.SetHeight(frame, height)
        local success, err = pcall(PixelUtil.SetHeight, frame, height)
        if not success then
            FallbackSetHeight(frame, height)
        end
    end
else
    -- Fallback implementations using standard WoW API
    PixelUtilCompat.SetPoint = FallbackSetPoint
    PixelUtilCompat.SetSize = FallbackSetSize
    PixelUtilCompat.SetWidth = FallbackSetWidth
    PixelUtilCompat.SetHeight = FallbackSetHeight
end

-- SetAllPoints is not part of PixelUtil - it's a standard frame method
function PixelUtilCompat.SetAllPoints(frame, relativeTo)
    frame:SetAllPoints(relativeTo)
end

-- Add this near the top of AuraIcon.lua if it's missing
local DebuffTypeColor = {
    ["MAGIC"] = { 0.2, 0.6, 1.0 }, -- Blue
    ["CURSE"] = { 0.6, 0.0, 1.0 }, -- Purple
    ["DISEASE"] = { 0.6, 0.4, 0 }, -- Brown/Yellow
    ["POISON"] = { 0.0, 0.6, 0 },  -- Green
    ["NONE"] = { 0.8, 0.0, 0.0 }   -- Grey for non-dispellable (placeholder, we handle NONE explicitly now)
    -- Add other potential types if needed, though these are the main player-dispellable ones
}

local AuraIcon = {}
AuraIcon.__index = AuraIcon

function AuraIcon.New(parentFrame, index, baseName)
    -- Find frame type and get config values
    local frameType
    for fType, f in pairs(BoxxyAuras.Frames or {}) do
        if f == parentFrame then
            frameType = fType;
            break
        end
    end

    local settingsKey = frameType and BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = settingsKey and BoxxyAuras:GetCurrentProfileSettings()

    -- Get icon dimensions and text size
    local iconSize = (currentSettings and currentSettings[settingsKey] and currentSettings[settingsKey].iconSize) or
        BoxxyAuras.Config.IconSize
    local textSize = (currentSettings and currentSettings[settingsKey] and currentSettings[settingsKey].textSize) or 8
    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    -- Calculate text area height with some padding (text size + small buffer)
    local textAreaHeight = textSize + 4
    local totalHeight = iconSize + textAreaHeight + (padding * 2)
    local totalWidth = iconSize + (padding * 2)

    -- Create instance and frame
    local instance = setmetatable({}, AuraIcon)
    instance.currentSize = iconSize     -- Store initial size
    instance.currentTextSize = textSize -- Track current text size

    local frame = CreateFrame("Frame", baseName .. index, parentFrame, "BackdropTemplate")
    frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
    PixelUtilCompat.SetSize(frame, totalWidth, totalHeight)

    -- Create core UI elements
    local texture = frame:CreateTexture(nil, "ARTWORK")
    PixelUtilCompat.SetSize(texture, iconSize, iconSize)
    PixelUtilCompat.SetPoint(texture, "TOPLEFT", frame, "TOPLEFT", padding, -padding)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local countText = frame:CreateFontString(nil, "OVERLAY", "BoxxyAuras_StackTxt")
    PixelUtilCompat.SetPoint(countText, "BOTTOMRIGHT", texture, "BOTTOMRIGHT", 2, -2)
    countText:SetJustifyH("RIGHT")

    local countTextBg = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    countTextBg:SetColorTexture(0, 0, 0, 0.85)
    PixelUtilCompat.SetPoint(countTextBg, "TOPLEFT", countText, "TOPLEFT", -2, 2)
    PixelUtilCompat.SetPoint(countTextBg, "BOTTOMRIGHT", countText, "BOTTOMRIGHT", -2, -2)

    local durationText = frame:CreateFontString(nil, "OVERLAY", "BoxxyAuras_DurationTxt")
    PixelUtilCompat.SetPoint(durationText, "TOPLEFT", texture, "BOTTOMLEFT", 0, -padding)
    PixelUtilCompat.SetPoint(durationText, "TOPRIGHT", texture, "BOTTOMRIGHT", 0, -padding)
    PixelUtilCompat.SetPoint(durationText, "BOTTOM", frame, "BOTTOM", 0, padding)
    durationText:SetJustifyH("CENTER")

    -- Apply text size from settings
    local fontPath, _, fontFlags = durationText:GetFont()
    if fontPath then
        durationText:SetFont(fontPath, textSize, fontFlags)
    end

    -- Also apply text size to count text (2 points larger for better visibility)
    local countFontPath, _, countFontFlags = countText:GetFont()
    if countFontPath then
        countText:SetFont(countFontPath, textSize + 2, countFontFlags)
    end

    -- Create overlay textures
    local wipeOverlay = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    wipeOverlay:SetColorTexture(1, 1, 1, 1.0)
    PixelUtilCompat.SetSize(wipeOverlay, iconSize, iconSize)
    PixelUtilCompat.SetPoint(wipeOverlay, "TOPLEFT", texture, "TOPLEFT")
    wipeOverlay:SetAlpha(0)

    local shakeOverlay = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    shakeOverlay:SetColorTexture(1, 0, 0, 0.75)
    PixelUtilCompat.SetSize(shakeOverlay, iconSize, iconSize)
    PixelUtilCompat.SetPoint(shakeOverlay, "TOPLEFT", texture, "TOPLEFT")
    shakeOverlay:SetAlpha(0)

    -- Get border size from settings
    local borderSize = 0                                          -- Default border size
    if currentSettings and settingsKey and currentSettings[settingsKey] then
        borderSize = currentSettings[settingsKey].borderSize or 0 -- Use 0 if borderSize is nil
    end

    -- Apply backdrop
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ItemEntryBG", "backdrop", 0)

    -- Create border based on border size setting
    if borderSize == 0 then
        -- No border at all
    elseif borderSize == 1 then
        -- Standard border (what was previously 0)
        BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ItemEntryBorder", "border", 0)
    else
        -- Thick border for borderSize >= 2 (what was previously >= 1)
        local shrinkAmount = -math.min((borderSize - 1) * 2, 12) -- Scale shrink with border size, max 12
        BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ThickBorder", "border", shrinkAmount)
    end

    local cfgBG = (currentSettings and currentSettings.normalBackgroundColor) or
        BoxxyAuras:GetDefaultProfileSettings().normalBackgroundColor
    local cfgBorder = (currentSettings and currentSettings.normalBorderColor) or
        BoxxyAuras:GetDefaultProfileSettings().normalBorderColor
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", cfgBG.r, cfgBG.g, cfgBG.b, cfgBG.a)
    if borderSize > 0 then
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)
    end

    -- Set up event handlers
    frame:SetScript("OnEnter", function()
        AuraIcon.OnEnter(instance)

        -- << NEW: When entering a child icon, explicitly cancel the parent's leave timer
        local parentFrame = instance.parentDisplayFrame
        if parentFrame and BoxxyAuras.FrameLeaveTimers[parentFrame] then
            C_Timer.Cancel(BoxxyAuras.FrameLeaveTimers[parentFrame])
            BoxxyAuras.FrameLeaveTimers[parentFrame] = nil
        end
        -- Also, ensure the global hover state is set to the parent
        BoxxyAuras.HoveredFrame = parentFrame
    end)
    frame:SetScript("OnLeave", function()
        -- OnLeave is now handled by the parent frame's OnUpdate logic,
        -- but we still need to call the instance's OnLeave for the tooltip.
        AuraIcon.OnLeave(instance)
    end)
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            -- Check if frames are unlocked and enable dragging the parent frame
            local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
            if not currentSettings.lockFrames and instance.parentDisplayFrame then
                instance.parentDisplayFrame:StartMoving()
            end
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            -- Stop dragging the parent frame if it was being moved
            local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
            if not currentSettings.lockFrames and instance.parentDisplayFrame then
                instance.parentDisplayFrame:StopMovingOrSizing()
                -- Save the new position with LibWindow
                if LibWindow and LibWindow.SavePosition then
                    LibWindow.SavePosition(instance.parentDisplayFrame)
                end
            end
        elseif button == "RightButton" and instance.auraType == "HELPFUL" and not InCombatLockdown() then
            if instance.auraInstanceID then
                local buffIndex
                for i = 1, 40 do
                    local auraData = C_UnitAuras.GetAuraDataByIndex and
                        C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                    if auraData and auraData.auraInstanceID == instance.auraInstanceID then
                        buffIndex = i
                        break
                    end
                    if not auraData then
                        break
                    end
                end
                if buffIndex then
                    CancelUnitBuff("player", buffIndex)
                end
            end
        end
    end)

    -- Create animations
    local animGroup = frame:CreateAnimationGroup()

    -- New aura animation (pop + fade in)
    local scaleAnim = animGroup:CreateAnimation("Scale")
    scaleAnim:SetScale(1.2, 1.2)
    scaleAnim:SetDuration(0.15)
    scaleAnim:SetOrder(1)
    scaleAnim:SetSmoothing("OUT")

    local scaleAnim2 = animGroup:CreateAnimation("Scale")
    scaleAnim2:SetScale(1.0, 1.0)
    scaleAnim2:SetDuration(0.15)
    scaleAnim2:SetOrder(2)
    scaleAnim2:SetSmoothing("IN")

    local alphaAnim = animGroup:CreateAnimation("Alpha")
    alphaAnim:SetFromAlpha(0)
    alphaAnim:SetToAlpha(1)
    alphaAnim:SetDuration(0.2)
    alphaAnim:SetOrder(1)

    -- Wipe overlay animations
    local wipeAlpha = animGroup:CreateAnimation("Alpha")
    wipeAlpha:SetChildKey("wipeOverlay")
    wipeAlpha:SetFromAlpha(0)
    wipeAlpha:SetToAlpha(0.75)
    wipeAlpha:SetDuration(0.1)
    wipeAlpha:SetOrder(1)
    wipeAlpha:SetSmoothing("IN")

    local wipeAlpha2 = animGroup:CreateAnimation("Alpha")
    wipeAlpha2:SetChildKey("wipeOverlay")
    wipeAlpha2:SetFromAlpha(0.75)
    wipeAlpha2:SetToAlpha(0)
    wipeAlpha2:SetDuration(0.25)
    wipeAlpha2:SetOrder(2)
    wipeAlpha2:SetSmoothing("OUT")

    local wipeSlide = animGroup:CreateAnimation("Translation")
    wipeSlide:SetChildKey("wipeOverlay")
    wipeSlide:SetOffset(0, -iconSize)
    wipeSlide:SetDuration(0.25)
    wipeSlide:SetOrder(2)
    wipeSlide:SetSmoothing("OUT")

    -- Shake animation group
    local shakeGroup = frame:CreateAnimationGroup("ShakeGroup")
    local shakeDur = 0.05
    local shakeOffset = 4

    local shake1 = shakeGroup:CreateAnimation("Translation")
    shake1:SetOffset(shakeOffset, 0)
    shake1:SetDuration(shakeDur)
    shake1:SetOrder(1)

    local shake2 = shakeGroup:CreateAnimation("Translation")
    shake2:SetOffset(-shakeOffset * 2, 0)
    shake2:SetDuration(shakeDur * 2)
    shake2:SetOrder(2)

    local shake3 = shakeGroup:CreateAnimation("Translation")
    shake3:SetOffset(shakeOffset, 0)
    shake3:SetDuration(shakeDur)
    shake3:SetOrder(3)

    local shakeOverlayFadeIn = shakeGroup:CreateAnimation("Alpha")
    shakeOverlayFadeIn:SetChildKey("shakeOverlay")
    shakeOverlayFadeIn:SetFromAlpha(0)
    shakeOverlayFadeIn:SetToAlpha(0.6)
    shakeOverlayFadeIn:SetDuration(shakeDur)
    shakeOverlayFadeIn:SetOrder(1)

    local shakeOverlayFadeOut = shakeGroup:CreateAnimation("Alpha")
    shakeOverlayFadeOut:SetChildKey("shakeOverlay")
    shakeOverlayFadeOut:SetFromAlpha(0.6)
    shakeOverlayFadeOut:SetToAlpha(0)
    shakeOverlayFadeOut:SetDuration(shakeDur * 3)
    shakeOverlayFadeOut:SetOrder(2)

    -- Store references
    instance.frame = frame
    instance.parentDisplayFrame = parentFrame
    instance.textureWidget = texture
    instance.newAuraAnimGroup = animGroup
    instance.shakeAnimGroup = shakeGroup
    instance.shakeAnim1 = shake1
    instance.shakeAnim2 = shake2
    instance.shakeAnim3 = shake3

    frame.auraTexture = texture
    frame.countText = countText
    frame.countTextBg = countTextBg
    frame.durationText = durationText
    frame.wipeOverlay = wipeOverlay
    frame.shakeOverlay = shakeOverlay

    -- Initialize state
    instance.duration = 0
    instance.expirationTime = 0
    instance.auraIndex = 0
    instance.tooltipUpdateTimer = 0
    frame:Hide()

    return instance
end

-- Helper to format duration
local function FormatDuration(seconds)
    if seconds >= 3600 then
        return string.format("%.0fh", seconds / 3600)
    elseif seconds >= 60 then
        return string.format("%.0fm", seconds / 60)
    else
        return string.format("%.0fs", seconds)
    end
end

function AuraIcon.Update(self, auraData, index, auraType)
    if not auraData then
        -- Instead of just hiding, properly reset the icon for pooling
        self:Reset()
        return
    end

    -- Update state
    self.isExpired = auraData.forceExpired or false
    local wasHidden = not self.frame:IsShown()

    -- Initialize expired state based on aura data
    if auraData.forceExpired then
        -- This aura is already expired (from hover persistence)
        self.lastIsExpiredState = true
        self.textureWidget:SetVertexColor(1, 0.5, 0.5)
        self.frame.durationText:SetText("0s")
        self.frame:SetScript("OnUpdate", nil)
        if BoxxyAuras.DEBUG then
            print(string.format("UPDATE: Icon updated with FORCE-EXPIRED aura '%s'", auraData.name or "Unknown"))
        end
    else
        -- This is a fresh/active aura - ensure expired state is reset
        self.lastIsExpiredState = false
        self.expiredAt = nil
        self.textureWidget:SetVertexColor(1, 1, 1) -- Ensure normal color
        if BoxxyAuras.DEBUG then
            print(string.format("UPDATE: Icon updated with FRESH aura '%s' (duration=%.1f)", auraData.name or "Unknown",
                auraData.duration or 0))
        end
    end

    -- Update icon appearance
    self.textureWidget:SetTexture(auraData.icon)

    -- Stack count
    if auraData.applications and auraData.applications > 1 then
        self.frame.countText:SetText(auraData.applications)
        self.frame.countText:Show()
        self.frame.countTextBg:Show()
    else
        self.frame.countText:Hide()
        self.frame.countTextBg:Hide()
    end

    -- Store data
    self.duration = auraData.duration
    self.expirationTime = auraData.expirationTime
    self.auraIndex = index
    self.auraType = auraType
    self.name = auraData.name
    if auraData.spellId then
        self.spellId = auraData.spellId
    end
    if auraData.originalAuraType then
        self.originalAuraType = auraData.originalAuraType
    end
    self.auraInstanceID = auraData.auraInstanceID
    self.slot = auraData.slot
    self.auraKey = auraData.spellId
    self.dispelName = auraData.dispelName -- Store dispel type for border color

    -- Find frame type and get border size from settings
    local frameType = nil
    if self.parentDisplayFrame then
        for fType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame == self.parentDisplayFrame then
                frameType = fType
                break
            end
        end
    end

    local settingsKey = frameType and BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = settingsKey and BoxxyAuras:GetCurrentProfileSettings()

    -- Get border size from settings
    local borderSize = 0                                          -- Default border size
    if currentSettings and settingsKey and currentSettings[settingsKey] then
        borderSize = currentSettings[settingsKey].borderSize or 0 -- Use 0 if borderSize is nil
    end

    -- Set border color based on aura type (only if border exists)
    if borderSize > 0 then
        if auraType == "HARMFUL" then
            local dispelType = string.upper(auraData.dispelName or "NONE")

            if dispelType == "NONE" then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", 1.0, 0.1, 0.1, 0.9)
                self.frame.durationText:SetTextColor(1, 1, 1, 1.0)
            else
                local colorTable = DebuffTypeColor[dispelType]
                if colorTable then
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", colorTable[1], colorTable[2],
                        colorTable[3],
                        0.9)
                    self.frame.durationText:SetTextColor(colorTable[1], colorTable[2], colorTable[3], 1.0)
                else
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", 1.0, 0.1, 0.1, 0.9)
                    self.frame.durationText:SetTextColor(1, 1, 1, 1.0)
                end
            end
        else
            local cfgBorder = (currentSettings and currentSettings.normalBorderColor) or {
                r = 0.3,
                g = 0.3,
                b = 0.3,
                a = 0.8
            }
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b,
                cfgBorder.a)
            self.frame.durationText:SetTextColor(1, 1, 1, 1)
        end
    else
        -- No border, but still set text color for consistency
        if auraType == "HARMFUL" then
            local dispelType = string.upper(auraData.dispelName or "NONE")
            if dispelType ~= "NONE" then
                local colorTable = DebuffTypeColor[dispelType]
                if colorTable then
                    self.frame.durationText:SetTextColor(colorTable[1], colorTable[2], colorTable[3], 1.0)
                else
                    self.frame.durationText:SetTextColor(1, 1, 1, 1.0)
                end
            else
                self.frame.durationText:SetTextColor(1, 1, 1, 1.0)
            end
        else
            self.frame.durationText:SetTextColor(1, 1, 1, 1)
        end
    end

    -- Ensure duration text is always centered regardless of frame alignment
    if self.frame.durationText then
        self.frame.durationText:SetJustifyH("CENTER")
    end

    -- Set up duration tracking using central update manager
    -- Always clear any existing OnUpdate script first to prevent accumulation
    self.frame:SetScript("OnUpdate", nil)

    -- Also handle tooltip updates in the central manager
    if self.isMouseOver then
        self.tooltipUpdateTimer = self.tooltipUpdateTimer or 0
        self.needsTooltipUpdate = true
    end

    if not auraData.forceExpired and self.duration and self.duration > 0 then
        -- Register with central update manager instead of individual OnUpdate
        if BoxxyAuras.UpdateManager then
            BoxxyAuras.UpdateManager:RegisterAura(self)
        end
        if BoxxyAuras.DEBUG then
            print(string.format("MANAGER: Registered '%s' with central update manager (duration=%.1f)",
                auraData.name or "Unknown", self.duration))
        end
    else
        -- Unregister from update manager for permanent auras or force-expired ones
        if BoxxyAuras.UpdateManager then
            BoxxyAuras.UpdateManager:UnregisterAura(self)
        end

        if self.duration == 0 or self.duration <= 0 then
            if self.frame.durationText then
                self.frame.durationText:Hide()
            end
        end
        if BoxxyAuras.DEBUG then
            print(string.format("MANAGER: No updates needed for '%s' (forceExpired=%s, duration=%.1f)",
                auraData.name or "Unknown", tostring(auraData.forceExpired), self.duration or 0))
        end
    end

    -- Ensure correct size (we already have frameType, settingsKey, and currentSettings from above)
    if frameType and currentSettings and settingsKey and currentSettings[settingsKey] then
        local iconSize = currentSettings[settingsKey].iconSize or BoxxyAuras.Config.IconSize
        self:Resize(iconSize)
    end

    -- Show frame
    if not self.frame:IsShown() then
        self.frame:Show()
    end

    -- Initial duration display (but skip for forceExpired auras as they're already set up)
    if not auraData.forceExpired then
        AuraIcon.UpdateDurationDisplay(self, GetTime())
    end
end

function AuraIcon.UpdateDurationDisplay(self, currentTime)
    if not self.frame or not self.frame:IsShown() then
        return
    end

    if self.duration and self.duration > 0 then
        local remaining = self.expirationTime - currentTime
        local isParentHovered = (self.parentDisplayFrame == BoxxyAuras.HoveredFrame) -- Check if the parent frame is THE hovered frame
        local currentIsExpired = (remaining <= 0)

        -- Debug only when approaching expiration or state changes
        if BoxxyAuras.DEBUG and (remaining <= 5 or currentIsExpired ~= self.lastIsExpiredState) then
            print(string.format("DEBUG: Aura '%s' - remaining=%.3f, currentIsExpired=%s, lastExpired=%s",
                self.name or "Unknown", remaining, tostring(currentIsExpired), tostring(self.lastIsExpiredState)))
        end
        local currentFormattedText
        local showText = false
        local applyTint = false

        if not currentIsExpired then -- Active aura
            currentFormattedText = FormatDuration(remaining)
            showText = true
            applyTint = false    -- No tint for active auras
            self.expiredAt = nil -- Reset expired timestamp
            if BoxxyAuras.DEBUG and remaining <= 5 then
                print(string.format("BRANCH: Taking ACTIVE branch for '%s' (remaining=%.3f)", self.name or "Unknown",
                    remaining))
            end
        else                 -- Expired aura (remaining <= 0)
            applyTint = true -- Expired tint (red)
            if BoxxyAuras.DEBUG then
                print(string.format("BRANCH: Taking EXPIRED branch for '%s' (remaining=%.3f)", self.name or "Unknown",
                    remaining))
            end

            -- Mark when this aura first expired for grace period tracking
            if not self.expiredAt then
                self.expiredAt = currentTime
                if BoxxyAuras.DEBUG then
                    print(string.format("EXPIRE: Aura '%s' first detected as expired at %.1f", self.name or "Unknown",
                        currentTime))
                end
            end

            local expiredDuration = currentTime - self.expiredAt
            local graceExpired = expiredDuration > 1.0 -- 1 second grace period

            if isParentHovered or not graceExpired then
                -- Show "0s" if hovered OR still within grace period
                currentFormattedText = "0s"
                showText = true
            else
                -- Grace period expired and not hovered - stop updating
                showText = false
                if BoxxyAuras.UpdateManager then
                    BoxxyAuras.UpdateManager:UnregisterAura(self)
                end
                if BoxxyAuras.DEBUG then
                    print(string.format("MANAGER: Unregistered expired aura '%s' (grace period over)",
                        self.name or "Unknown"))
                end
            end
        end

        -- Update text if changed or visibility changed
        if currentFormattedText ~= self.lastFormattedDurationText or showText ~= self.frame.durationText:IsShown() then
            if showText then
                self.frame.durationText:SetText(currentFormattedText)
                self.frame.durationText:Show()
            else
                self.frame.durationText:Hide()
            end
            self.lastFormattedDurationText = currentFormattedText
        end

        -- Update tint if expired state changed (hover state no longer affects tint)
        if currentIsExpired ~= self.lastIsExpiredState then
            if BoxxyAuras.DEBUG then
                print(string.format("TINT CHECK: '%s' - currentIsExpired=%s, lastIsExpiredState=%s, applyTint=%s",
                    self.name or "Unknown", tostring(currentIsExpired), tostring(self.lastIsExpiredState),
                    tostring(applyTint)))
            end
            if self.textureWidget then
                -- Apply red tint if expired, regardless of hover state
                if applyTint then
                    self.textureWidget:SetVertexColor(1, 0.5, 0.5)
                    if BoxxyAuras.DEBUG then
                        print(string.format("TINT: Applied RED to aura '%s' (remaining=%.1f)", self.name or "Unknown",
                            remaining))
                    end
                else
                    -- Normal white tint for active auras
                    self.textureWidget:SetVertexColor(1, 1, 1)
                    if BoxxyAuras.DEBUG then
                        print(string.format("TINT: Applied WHITE to aura '%s' (remaining=%.1f)", self.name or "Unknown",
                            remaining))
                    end
                end
            end
            self.lastIsExpiredState = currentIsExpired
        end

        -- Still track hover state for other purposes, but don't affect tint
        self.lastIsParentHoveredState = isParentHovered

        -- Handle tooltip updates (centralized from individual OnUpdate scripts)
        if self.isMouseOver and self.needsTooltipUpdate then
            self.tooltipUpdateTimer = (self.tooltipUpdateTimer or 0) + 0.1 -- Assume 0.1s since last update
            if self.tooltipUpdateTimer >= 1.0 then
                if GameTooltip:IsOwned(self.frame) then
                    AuraIcon.RefreshTooltipContent(self)
                end
                self.tooltipUpdateTimer = 0
            end
        end
    else
        -- Handle permanent auras (ensure text hidden, tint reset, OnUpdate nil)
        if self.frame.durationText:IsShown() or self.lastFormattedDurationText then
            self.frame.durationText:Hide()
            self.lastFormattedDurationText = nil
        end

        if self.lastIsExpiredState or self.lastIsParentHoveredState then
            if self.textureWidget then
                self.textureWidget:SetVertexColor(1, 1, 1)
            end
            self.lastIsExpiredState = false
            self.lastIsParentHoveredState = false -- Reset hover state tracking too
        end

        if self.frame:GetScript("OnUpdate") then
            self.frame:SetScript("OnUpdate", nil)
        end
    end
end

function AuraIcon.OnEnter(self)
    self.isMouseOver = true
    self.needsTooltipUpdate = true
    self.tooltipUpdateTimer = 0
    GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    AuraIcon.RefreshTooltipContent(self)
    GameTooltip:Show()
end

-- Helper function to check if TipTac (or other addons) already added caster information
function AuraIcon.HasCasterLineInTooltip()
    if not GameTooltip:IsShown() or GameTooltip:NumLines() == 0 then
        return false
    end

    for i = 1, GameTooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i]
        if line then
            local text = line:GetText() or ""
            -- Check for various patterns that indicate caster information
            -- TipTac uses "Caster:", some other addons might use different patterns
            if string.find(text, "Caster:", 1, true) or
                string.find(text, "From:", 1, true) or
                string.find(text, "Cast by:", 1, true) or
                string.find(text, "Source:", 1, true) then
                if BoxxyAuras.DEBUG then
                    print(string.format("HasCasterLineInTooltip: Found caster line at position %d: '%s'", i, text))
                end
                return true
            end
        end
    end

    if BoxxyAuras.DEBUG then
        print("HasCasterLineInTooltip: No caster lines found")
    end
    return false
end

-- Helper function to add tooltip lines with proper wrapping and coloring for expired auras
function AuraIcon.AddWrappedTooltipLine(leftText, rightText, isTitle)
    if not leftText or leftText == "" then return end

    -- Define proper tooltip colors
    local titleColor = { r = 1, g = 0.82, b = 0 }
    local normalColor = { r = 1, g = 1, b = 1 }
    local rightColor = { r = 1, g = 1, b = 1 }

    -- If it has right-side text, it's a double line.
    if rightText and rightText ~= "" then
        local r, g, b = isTitle and titleColor.r or normalColor.r, isTitle and titleColor.g or normalColor.g,
            isTitle and titleColor.b or normalColor.b
        GameTooltip:AddDoubleLine(leftText, rightText, r, g, b, rightColor.r, rightColor.g, rightColor.b)
    else
        -- It's a single line. This could be a title or a description paragraph. Let the game wrap.
        local r, g, b = isTitle and titleColor.r or normalColor.r, isTitle and titleColor.g or normalColor.g,
            isTitle and titleColor.b or normalColor.b
        GameTooltip:AddLine(leftText, r, g, b, true)
    end
end

function AuraIcon.RefreshTooltipContent(self)
    if not self.frame then
        return
    end

    local currentTime = GetTime()
    local remaining = (self.expirationTime or 0) - currentTime
    local isPermanent = (self.duration or 0) == 0

    GameTooltip:ClearLines()

    if BoxxyAuras.DEBUG then
        print(string.format("RefreshTooltipContent: aura=%s, remaining=%.1f, isPermanent=%s, expired=%s",
            tostring(self.name), remaining, tostring(isPermanent), tostring(remaining <= 0 and not isPermanent)))
    end

    if isPermanent or remaining > 0 then
        local tooltipSet = false

        -- Handle custom auras
        if self.auraType == "CUSTOM" then
            local cachedData = self.auraInstanceID and BoxxyAuras.AllAuras[self.auraInstanceID]
            if cachedData and cachedData.lines then
                if BoxxyAuras.DEBUG then
                    print(string.format("RefreshTooltipContent: Using cached data for custom aura, %d lines",
                        #cachedData.lines))
                end
                -- Use text wrapping to control tooltip width

                for i, lineInfo in ipairs(cachedData.lines) do
                    if lineInfo.left then
                        AuraIcon.AddWrappedTooltipLine(lineInfo.left, lineInfo.right, i == 1)
                    end
                end

                -- Add caster information if available (check if TipTac already added one)
                local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
                if casterName then
                    local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                    if BoxxyAuras.DEBUG then
                        print(string.format("Tooltip: Custom aura casterName='%s', tiptacExists=%s for instanceID=%s",
                            tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                    end
                    if not tiptacCasterExists then
                        GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true) -- Light blue color
                    end
                end

                tooltipSet = true
            else
                if BoxxyAuras.DEBUG then
                    print("RefreshTooltipContent: No cached data for custom aura")
                end
            end
        end

        -- Try SetUnitAura for regular auras
        if not tooltipSet and self.auraType ~= "CUSTOM" then
            if self.auraInstanceID and self.auraType then
                local currentIndex
                local filterToUse = self.originalAuraType or self.auraType
                for i = 1, 40 do
                    local currentAuraData = C_UnitAuras.GetAuraDataByIndex("player", i, filterToUse)
                    if currentAuraData and currentAuraData.auraInstanceID == self.auraInstanceID then
                        currentIndex = i
                        break
                    end
                end
                if currentIndex then
                    if BoxxyAuras.DEBUG then
                        print(string.format("RefreshTooltipContent: Using SetUnitAura with index %d", currentIndex))
                    end
                    GameTooltip:SetUnitAura("player", currentIndex, filterToUse)

                    -- Add caster information immediately - no timer delays to avoid flickering
                    local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
                    if casterName then
                        local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                        if BoxxyAuras.DEBUG then
                            print(string.format(
                                "Tooltip: Active aura casterName='%s', tiptacExists=%s for instanceID=%s",
                                tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                        end
                        if not tiptacCasterExists then
                            GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true) -- Light blue color
                        end
                    end

                    tooltipSet = true
                else
                    if BoxxyAuras.DEBUG then
                        print("RefreshTooltipContent: Aura not found by instance ID")
                    end
                end
            end
        end

        -- Fallback to spell ID
        if not tooltipSet and self.spellId then
            if BoxxyAuras.DEBUG then
                print(string.format("RefreshTooltipContent: Using SetSpellByID with spellId %s", tostring(self.spellId)))
            end
            GameTooltip:SetSpellByID(self.spellId)

            -- Add caster information if available (check if TipTac already added one)
            local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
            if casterName then
                local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                if BoxxyAuras.DEBUG then
                    print(string.format("Tooltip: Fallback spell casterName='%s', tiptacExists=%s for instanceID=%s",
                        tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                end
                if not tiptacCasterExists then
                    GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true) -- Light blue color
                end
            end

            tooltipSet = true
        end

        -- Last resort
        if not tooltipSet then
            if BoxxyAuras.DEBUG then
                print("RefreshTooltipContent: Using fallback tooltip text")
            end
            GameTooltip:AddLine(self.name or "Unknown Aura")
        end
    elseif not isPermanent and remaining <= 0 then
        -- Show cached data for expired auras
        local cachedData = self.auraInstanceID and BoxxyAuras.AllAuras[self.auraInstanceID]
        if cachedData and cachedData.lines then
            if BoxxyAuras.DEBUG then
                print(string.format(
                    "RefreshTooltipContent: Using cached data for expired aura, %d lines, scrapedVia=%s, instanceID=%s",
                    #cachedData.lines, tostring(cachedData.scrapedVia), tostring(self.auraInstanceID)))
            end

            -- Reconstruct description paragraphs and add lines
            local descriptionParagraph = ""
            local paragraphStarted = false

            for i, lineInfo in ipairs(cachedData.lines) do
                if lineInfo.left then
                    local isTitle = (i == 1)
                    -- A "normal" line is part of a description if it has no right-side text and is not the title.
                    local isNormalLine = (not lineInfo.right or lineInfo.right == "") and not isTitle

                    if isNormalLine then
                        -- Append to the current paragraph.
                        if descriptionParagraph == "" then
                            descriptionParagraph = lineInfo.left
                        else
                            descriptionParagraph = descriptionParagraph .. " " .. lineInfo.left
                        end
                        paragraphStarted = true
                    else
                        -- This is a special line (e.g., title, or a line with right-side text).
                        -- First, add any pending paragraph to the tooltip.
                        if paragraphStarted then
                            AuraIcon.AddWrappedTooltipLine(descriptionParagraph, nil, false)
                            descriptionParagraph = ""
                            paragraphStarted = false
                        end

                        -- Now, add the current special line.
                        AuraIcon.AddWrappedTooltipLine(lineInfo.left, lineInfo.right, isTitle)
                    end
                end
            end

            -- After the loop, add any final pending paragraph.
            if paragraphStarted then
                AuraIcon.AddWrappedTooltipLine(descriptionParagraph, nil, false)
            end

            -- Add caster and expired information
            local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
            local tiptacCasterExists = casterName and AuraIcon.HasCasterLineInTooltip()

            if casterName and not tiptacCasterExists then
                if BoxxyAuras.DEBUG then
                    print(string.format("Tooltip: Expired aura casterName='%s', tiptacExists=%s for instanceID=%s",
                        tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                end
                -- Add "From" and "Expired" on the same line using AddDoubleLine for better formatting
                GameTooltip:AddDoubleLine("From: " .. casterName, "(Expired)", 0.5, 0.8, 1.0, 1, 0.5, 0.5)
            else
                -- If no caster info, just show "(Expired)" on its own line
                GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5, true)
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("RefreshTooltipContent: No cached data for expired aura (instanceID=%s)",
                    tostring(self.auraInstanceID)))
                -- Let's also debug what IS in the cache
                print("Current cache contents:")
                for id, data in pairs(BoxxyAuras.AllAuras or {}) do
                    print(string.format("  - ID: %s, Name: %s, ScrapedVia: %s", tostring(id), tostring(data.name),
                        tostring(data.scrapedVia)))
                end
            end
            GameTooltip:AddLine(self.name or "Unknown Expired Aura", 1, 1, 1, true)
            GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5, true)
        end
    else
        if BoxxyAuras.DEBUG then
            print("RefreshTooltipContent: Unknown aura state")
        end
        GameTooltip:AddLine(self.name or "Unknown Aura State")
    end

    -- Show the tooltip once after all modifications are complete
    GameTooltip:Show()
end

function AuraIcon.OnLeave(self)
    if not self.frame then
        return
    end
    self.isMouseOver = false
    self.needsTooltipUpdate = false
    GameTooltip:Hide()
end

function AuraIcon:Shake(scale)
    if not self.frame or not self.shakeAnim1 or not self.shakeAnim2 or not self.shakeAnim3 then
        return
    end

    local scaledOffset = math.min(4 * (scale or 1.0), 12)
    scaledOffset = math.max(scaledOffset, 1)

    self.shakeAnim1:SetOffset(0, -scaledOffset)
    self.shakeAnim2:SetOffset(0, scaledOffset * 2)
    self.shakeAnim3:SetOffset(0, -scaledOffset)

    if self.shakeAnimGroup and not self.shakeAnimGroup:IsPlaying() then
        self.shakeAnimGroup:Play()
    end
end

function AuraIcon:UpdateBorderSize()
    if not self.frame then
        return
    end

    -- Find frame type and get border size setting
    local frameType = nil
    if self.parentDisplayFrame then
        for fType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame == self.parentDisplayFrame then
                frameType = fType
                break
            end
        end
    end

    local borderSize = 0 -- Default border size
    if frameType then
        local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if currentSettings and settingsKey and currentSettings[settingsKey] then
            borderSize = currentSettings[settingsKey].borderSize or 0 -- Use 0 if borderSize is nil
        end
    end

    -- Redraw the border with the new size using custom thick texture
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
        -- IMPORTANT: DO NOT destroy the texture group - DrawSlicedBG will reuse existing textures
        -- The accumulation issue was caused by setting borderTextures = nil, forcing recreation
        -- Instead, let DrawSlicedBG reuse the existing texture objects

        -- Create border with appropriate texture based on size
        if borderSize == 0 then
            -- No border at all - don't draw any border
        elseif borderSize == 1 then
            -- Standard border (what was previously 0)
            BoxxyAuras.UIUtils.DrawSlicedBG(self.frame, "ItemEntryBorder", "border", 0)
        else
            -- Thick border for borderSize >= 2 (what was previously >= 1)
            local shrinkAmount = -math.min((borderSize - 1) * 2, 12) -- Scale shrink with border size, max 12
            BoxxyAuras.UIUtils.DrawSlicedBG(self.frame, "ThickBorder", "border", shrinkAmount)
        end

        -- Apply color to the border (only if border exists)
        if borderSize > 0 then
            local r, g, b, a = 0.3, 0.3, 0.3, 0.8 -- Default colors

            if self.auraType == "HARMFUL" then
                local dispelType = string.upper(self.dispelName or "NONE")
                if dispelType == "NONE" then
                    r, g, b, a = 1.0, 0.1, 0.1, 0.9
                else
                    local colorTable = DebuffTypeColor[dispelType]
                    if colorTable then
                        r, g, b, a = colorTable[1], colorTable[2], colorTable[3], 0.9
                    else
                        r, g, b, a = 1.0, 0.1, 0.1, 0.9
                    end
                end
            else
                local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
                local cfgBorder = (currentSettings and currentSettings.normalBorderColor) or
                    BoxxyAuras:GetDefaultProfileSettings().normalBorderColor
                r, g, b, a = cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a
            end

            -- Apply color to the border
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", r, g, b, a)
        end

        -- Also update the background color when border size changes
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        local cfgBG = (currentSettings and currentSettings.normalBackgroundColor) or
            BoxxyAuras:GetDefaultProfileSettings().normalBackgroundColor
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "backdrop", cfgBG.r, cfgBG.g, cfgBG.b, cfgBG.a)
    end
end

function AuraIcon:Resize(newIconSize)
    if not self.frame or not self.textureWidget then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras ERROR: Invalid icon instance in Resize - missing frame or texture")
        end
        return
    end

    -- Prevent unnecessary resizing only when both icon and text sizes are unchanged
    if self.currentSize and self.currentSize == newIconSize and self.currentTextSize and self.currentTextSize == textSize then
        return
    end

    if BoxxyAuras.DEBUG then
        local frameType = "unknown"
        if self.parentDisplayFrame then
            for fType, frame in pairs(BoxxyAuras.Frames or {}) do
                if frame == self.parentDisplayFrame then
                    frameType = fType
                    break
                end
            end
        end
        print("BoxxyAuras: Resizing " .. frameType .. " icon from " .. (self.currentSize or "unset") .. " to " ..
            newIconSize)
    end

    -- Get current text size from settings
    local frameType = nil
    if self.parentDisplayFrame then
        for fType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame == self.parentDisplayFrame then
                frameType = fType
                break
            end
        end
    end

    local textSize = 8 -- default
    if frameType then
        local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if currentSettings and settingsKey and currentSettings[settingsKey] then
            textSize = currentSettings[settingsKey].textSize or 8
        end
    end

    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local textAreaHeight = textSize + 4
    local newHeight = newIconSize + textAreaHeight + (padding * 2)
    local newWidth = newIconSize + (padding * 2)

    -- Store the new size
    self.currentSize = newIconSize
    self.currentTextSize = textSize

    -- Resize frame and widgets
    PixelUtilCompat.SetSize(self.frame, newWidth, newHeight)
    PixelUtilCompat.SetSize(self.textureWidget, newIconSize, newIconSize)

    -- Resize overlays
    if self.frame.wipeOverlay then
        PixelUtilCompat.SetSize(self.frame.wipeOverlay, newIconSize, newIconSize)
    end
    if self.frame.shakeOverlay then
        PixelUtilCompat.SetSize(self.frame.shakeOverlay, newIconSize, newIconSize)
    end

    -- Reposition text elements
    if self.frame.countText then
        self.frame.countText:ClearAllPoints()
        PixelUtilCompat.SetPoint(self.frame.countText, "BOTTOMRIGHT", self.textureWidget, "BOTTOMRIGHT", 2, -2)
    end

    if self.frame.durationText then
        self.frame.durationText:ClearAllPoints()
        PixelUtilCompat.SetPoint(self.frame.durationText, "TOPLEFT", self.textureWidget, "BOTTOMLEFT", 0, -padding)
        PixelUtilCompat.SetPoint(self.frame.durationText, "TOPRIGHT", self.textureWidget, "BOTTOMRIGHT", 0, -padding)
        PixelUtilCompat.SetPoint(self.frame.durationText, "BOTTOM", self.frame, "BOTTOM", 0, padding)

        -- Update font size if it changed
        local fontPath, _, fontFlags = self.frame.durationText:GetFont()
        if fontPath then
            self.frame.durationText:SetFont(fontPath, textSize, fontFlags)
        end
    end

    -- Also update count text font size (2 points larger for better visibility)
    if self.frame.countText then
        local countFontPath, _, countFontFlags = self.frame.countText:GetFont()
        if countFontPath then
            self.frame.countText:SetFont(countFontPath, textSize + 2, countFontFlags)
        end
    end

    -- Re-anchor overlay textures
    if self.frame.wipeOverlay then
        self.frame.wipeOverlay:ClearAllPoints()
        PixelUtilCompat.SetPoint(self.frame.wipeOverlay, "TOPLEFT", self.textureWidget, "TOPLEFT")
    end

    if self.frame.shakeOverlay then
        self.frame.shakeOverlay:ClearAllPoints()
        PixelUtilCompat.SetPoint(self.frame.shakeOverlay, "TOPLEFT", self.textureWidget, "TOPLEFT")
    end
end

-- Helper function to get caster name from tracked aura data
function AuraIcon.GetCasterNameFromCurrentData(self)
    if not self or not self.auraInstanceID then
        return nil
    end

    -- Always try to get source info from our tracked data first
    -- This is where we store the sourceGUID from combat log events
    for frameType, auras in pairs(BoxxyAuras.auraTracking or {}) do
        for _, aura in ipairs(auras or {}) do
            if aura.auraInstanceID == self.auraInstanceID then
                if BoxxyAuras.DEBUG then
                    print(string.format("GetCasterNameFromCurrentData: Found tracked aura with sourceGUID='%s'",
                        tostring(aura.sourceGUID)))
                end
                return BoxxyAuras.UIUtils.GetCasterName(aura)
            end
        end
    end

    if BoxxyAuras.DEBUG then
        print(string.format("GetCasterNameFromCurrentData: No tracked data found for instanceID=%s",
            tostring(self.auraInstanceID)))
    end

    -- Fallback: if no tracked data, we can't reliably determine caster
    -- WoW's live APIs don't preserve original caster information
    return nil
end

-- Add comprehensive reset method for pooling
function AuraIcon:Reset()
    if not self.frame then
        return
    end

    -- Unregister from central update manager
    if BoxxyAuras.UpdateManager then
        BoxxyAuras.UpdateManager:UnregisterAura(self)
    end

    -- Clear all scripts to prevent memory leaks and performance issues
    self.frame:SetScript("OnUpdate", nil)
    if BoxxyAuras.DEBUG then
        print(string.format("RESET: Icon reset for aura '%s', unregistered from manager", self.name or "Unknown"))
    end

    -- Reset state variables that could cause issues
    self.isMouseOver = false
    self.tooltipUpdateTimer = 0
    self.needsTooltipUpdate = false -- Reset tooltip update flag
    self.updateTier = nil           -- Reset update tier tracking
    self.lastFormattedDurationText = nil
    self.lastIsExpiredState = nil
    self.lastIsParentHoveredState = nil
    self.isExpired = false
    self.expiredAt = nil -- Reset expired timestamp for grace period

    -- Reset aura data
    self.duration = 0
    self.expirationTime = 0
    self.auraIndex = 0
    self.auraType = nil
    self.name = nil
    self.spellId = nil
    self.originalAuraType = nil
    self.auraInstanceID = nil
    self.slot = nil
    self.auraKey = nil
    self.dispelName = nil

    -- Stop any running animations
    if self.newAuraAnimGroup and self.newAuraAnimGroup:IsPlaying() then
        self.newAuraAnimGroup:Stop()
    end
    if self.shakeAnimGroup and self.shakeAnimGroup:IsPlaying() then
        self.shakeAnimGroup:Stop()
    end

    -- Reset visual elements
    if self.textureWidget then
        self.textureWidget:SetVertexColor(1, 1, 1) -- Reset to normal color
    end

    -- Hide and reset text elements
    if self.frame.durationText then
        self.frame.durationText:Hide()
        self.frame.durationText:SetTextColor(1, 1, 1, 1) -- Reset to normal color
    end

    if self.frame.countText then
        self.frame.countText:Hide()
    end

    if self.frame.countTextBg then
        self.frame.countTextBg:Hide()
    end

    -- Reset overlay alphas
    if self.frame.wipeOverlay then
        self.frame.wipeOverlay:SetAlpha(0)
    end
    if self.frame.shakeOverlay then
        self.frame.shakeOverlay:SetAlpha(0)
    end

    -- Hide the frame
    self.frame:Hide()

    -- Hide tooltip if it's showing for this frame
    if GameTooltip:IsOwned(self.frame) then
        GameTooltip:Hide()
    end
end

-- Assign to the global table
BoxxyAuras.AuraIcon = AuraIcon
