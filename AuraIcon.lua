-- Get the GLOBAL addon table correctly
local addonNameString, privateTable = ...
_G.BoxxyAuras = _G.BoxxyAuras or {}
local BoxxyAuras = _G.BoxxyAuras -- Use the global table

-- Remove redundant AllAuras creation if it's already done in BoxxyAuras.lua
-- BoxxyAuras.AllAuras = {}

-- PixelUtil Compatibility Layer
local PixelUtilCompat = {}

-- Fix IDE errors with LibWindow
LibWindow = LibWindow or {}

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

-- =============================================================== --
-- Helper Functions (to eliminate duplications)
-- =============================================================== --

-- Helper: Find frame type for a given frame
local function GetFrameType(parentFrame)
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if frame == parentFrame then
            return frameType
        end
    end
    return nil
end

-- Helper: Get frame settings (iconSize, textSize, borderSize)
local function GetFrameSettings(parentFrame)
    local frameType = GetFrameType(parentFrame)
    local frameSettings = frameType and BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)

    return {
        iconSize = (frameSettings and frameSettings.iconSize) or BoxxyAuras.Config.IconSize,
        textSize = (frameSettings and frameSettings.textSize) or 8,
        borderSize = (frameSettings and frameSettings.borderSize) or 1,
        frameType = frameType
    }
end

-- Helper: Apply font sizes to text elements
local function ApplyFontSizes(durationText, countText, textSize)
    -- Get user's font preference and text color if available
    local fontPath = nil
    local textColor = nil
    if BoxxyAuras and BoxxyAuras.GetCurrentProfileSettings then
        local settings = BoxxyAuras:GetCurrentProfileSettings()
        if settings then
            -- Get font
            if settings.textFont then
                -- Try to get the font from LibSharedMedia
                local Media = LibStub and LibStub("LibSharedMedia-3.0", true)
                if Media then
                    fontPath = Media:Fetch("font", settings.textFont, true) -- true = silent mode, won't error if not found
                end
            end
            
            -- Get text color
            if settings.textColor then
                textColor = settings.textColor
            end
        end
    end
    
    -- Duration text
    local currentFontPath, _, fontFlags = durationText:GetFont()
    local finalFontPath = fontPath or currentFontPath
    if finalFontPath then
        durationText:SetFont(finalFontPath, textSize, fontFlags)
    end
    
    -- Apply text color if available
    if textColor then
        durationText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a)
    end

    -- Count text (2 points larger for better visibility)
    local countFontPath, _, countFontFlags = countText:GetFont()
    local finalCountFontPath = fontPath or countFontPath
    if finalCountFontPath then
        countText:SetFont(finalCountFontPath, textSize + 2, countFontFlags)
    end
    
    -- Apply text color to count text if available
    if textColor then
        countText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a)
    end
end

-- Helper: Create and setup all animations for an icon
local function CreateAnimations(frame, iconSize, wipeOverlay, shakeOverlay)
    -- Main animation group (new aura pop + fade)
    local animGroup = frame:CreateAnimationGroup()

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

    -- Wipe overlay animations (target overlay directly)
    local wipeAlpha = animGroup:CreateAnimation("Alpha")
    wipeAlpha:SetTarget(wipeOverlay)
    wipeAlpha:SetFromAlpha(0)
    wipeAlpha:SetToAlpha(0.75)
    wipeAlpha:SetDuration(0.1)
    wipeAlpha:SetOrder(1)
    wipeAlpha:SetSmoothing("IN")

    local wipeAlpha2 = animGroup:CreateAnimation("Alpha")
    wipeAlpha2:SetTarget(wipeOverlay)
    wipeAlpha2:SetFromAlpha(0.75)
    wipeAlpha2:SetToAlpha(0)
    wipeAlpha2:SetDuration(0.25)
    wipeAlpha2:SetOrder(2)
    wipeAlpha2:SetSmoothing("OUT")

    local wipeSlide = animGroup:CreateAnimation("Translation")
    wipeSlide:SetTarget(wipeOverlay)
    wipeSlide:SetOffset(0, -iconSize)
    wipeSlide:SetDuration(0.25)
    wipeSlide:SetOrder(2)
    wipeSlide:SetSmoothing("OUT")

    -- Shake animation group
    local shakeGroup = frame:CreateAnimationGroup("ShakeGroup")
    local shakeDur, shakeOffset = 0.05, 4

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
    shakeOverlayFadeIn:SetTarget(shakeOverlay)
    shakeOverlayFadeIn:SetFromAlpha(0)
    shakeOverlayFadeIn:SetToAlpha(0.6)
    shakeOverlayFadeIn:SetDuration(shakeDur)
    shakeOverlayFadeIn:SetOrder(1)

    local shakeOverlayFadeOut = shakeGroup:CreateAnimation("Alpha")
    shakeOverlayFadeOut:SetTarget(shakeOverlay)
    shakeOverlayFadeOut:SetFromAlpha(0.6)
    shakeOverlayFadeOut:SetToAlpha(0)
    shakeOverlayFadeOut:SetDuration(shakeDur * 3)
    shakeOverlayFadeOut:SetOrder(2)

    return animGroup, shakeGroup, shake1, shake2, shake3
end

-- Helper: Apply border styling (consolidated from Display and ApplyStyle)
local function ApplyBorderStyling(frame, auraType, borderSize, dispelName)
    local effectiveBorderSize = borderSize
    if auraType == "HARMFUL" and borderSize == 0 then
        effectiveBorderSize = 1
    end

    if BoxxyAuras.DEBUG then
        print(string.format("ApplyBorderStyling: auraType=%s, borderSize=%d, effectiveSize=%d, dispelName=%s",
            tostring(auraType), borderSize or 0, effectiveBorderSize, tostring(dispelName)))
    end

    -- Draw borders based on size
    if effectiveBorderSize == 0 then
        if frame.borderTextures then
            for _, tex in pairs(frame.borderTextures) do
                if tex and tex.Hide then tex:Hide() end
            end
        end
    elseif effectiveBorderSize == 1 then
        BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ItemEntryBorder", "border", 0)
    else
        local shrinkAmount = -math.min((effectiveBorderSize - 1) * 2, 12)
        BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ThickBorder", "border", shrinkAmount)
    end

    -- Apply border and text colors
    -- Get user's text color preference if available
    local userTextColor = nil
    if BoxxyAuras and BoxxyAuras.GetCurrentProfileSettings then
        local settings = BoxxyAuras:GetCurrentProfileSettings()
        if settings and settings.textColor then
            userTextColor = settings.textColor
        end
    end
    
    if effectiveBorderSize > 0 then
        if auraType == "HARMFUL" then
            local upperDispelType = string.upper(dispelName or "NONE")
            local colorTable = DebuffTypeColor[upperDispelType]
            if upperDispelType == "NONE" or not colorTable then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", 1.0, 0.1, 0.1, 0.9)
                -- Use user text color if available, otherwise white
                if userTextColor then
                    frame.durationText:SetTextColor(userTextColor.r, userTextColor.g, userTextColor.b, userTextColor.a)
                else
                    frame.durationText:SetTextColor(1, 1, 1, 1.0)
                end
            else
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", colorTable[1], colorTable[2], colorTable[3], 0.9)
                -- Use user text color if available, otherwise use dispel color for visibility
                if userTextColor then
                    frame.durationText:SetTextColor(userTextColor.r, userTextColor.g, userTextColor.b, userTextColor.a)
                else
                    frame.durationText:SetTextColor(colorTable[1], colorTable[2], colorTable[3], 1.0)
                end
            end
        else -- Helpful
            local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
            local cfgBorder = (currentSettings and currentSettings.normalBorderColor) or
                BoxxyAuras:GetDefaultProfileSettings().normalBorderColor
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)
            -- Use user text color if available, otherwise white
            if userTextColor then
                frame.durationText:SetTextColor(userTextColor.r, userTextColor.g, userTextColor.b, userTextColor.a)
            else
                frame.durationText:SetTextColor(1, 1, 1, 1)
            end
        end
    else
        -- No border, but still color text for debuffs
        if auraType == "HARMFUL" then
            local upperDispelType = string.upper(dispelName or "NONE")
            local colorTable = DebuffTypeColor[upperDispelType]
            if colorTable and upperDispelType ~= "NONE" then
                -- Use user text color if available, otherwise use dispel color for visibility
                if userTextColor then
                    frame.durationText:SetTextColor(userTextColor.r, userTextColor.g, userTextColor.b, userTextColor.a)
                else
                    frame.durationText:SetTextColor(colorTable[1], colorTable[2], colorTable[3], 1.0)
                end
            else
                -- Use user text color if available, otherwise white
                if userTextColor then
                    frame.durationText:SetTextColor(userTextColor.r, userTextColor.g, userTextColor.b, userTextColor.a)
                else
                    frame.durationText:SetTextColor(1, 1, 1, 1.0)
                end
            end
        else
            -- Use user text color if available, otherwise white
            if userTextColor then
                frame.durationText:SetTextColor(userTextColor.r, userTextColor.g, userTextColor.b, userTextColor.a)
            else
                frame.durationText:SetTextColor(1, 1, 1, 1)
            end
        end
    end
    
    -- Also apply text color to count text if it exists
    if frame.countText and userTextColor then
        frame.countText:SetTextColor(userTextColor.r, userTextColor.g, userTextColor.b, userTextColor.a)
    end
end

local AuraIcon = {}
AuraIcon.__index = AuraIcon
-- =============================================================== --
-- AuraIcon.New
-- Creates a new AuraIcon frame instance and sets up all child widgets.
-- =============================================================== --
function AuraIcon.New(parentFrame, index, baseName)
    -- Get frame settings using helper
    local settings = GetFrameSettings(parentFrame)
    local iconSize, textSize = settings.iconSize, settings.textSize

    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local textAreaHeight = textSize + 4
    local totalHeight = iconSize + textAreaHeight + (padding * 2)
    local totalWidth = iconSize + (padding * 2)

    -- Create instance and frame
    local instance = setmetatable({}, AuraIcon)
    instance.currentSize = iconSize
    instance.currentTextSize = textSize

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

    -- Apply font sizes using helper
    ApplyFontSizes(durationText, countText, textSize)

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

    -- Create healing absorb progress bar using texture layers (not StatusBar)
    -- This ensures proper layering behind text but above backdrop
    local flatTexture = "Interface\\Buttons\\WHITE8x8"
    
    -- Get color from current profile settings, not from Config
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local absorbColor = (currentSettings and currentSettings.healingAbsorbBarColor) or { r = 0.86, g = 0.28, b = 0.13, a = 0.8 }
    local absorbBGColor = { r = 0, g = 0, b = 0, a = 0.4 } -- Keep background black/transparent
    
    -- Create background texture in BACKGROUND layer (behind text but above backdrop)
    local absorbProgressBg = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    absorbProgressBg:SetTexture(flatTexture)
    absorbProgressBg:SetColorTexture(absorbBGColor.r, absorbBGColor.g, absorbBGColor.b, absorbBGColor.a)
    
    -- Create foreground texture in BACKGROUND layer (slightly higher sublevel)
    local absorbProgressBar = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
    absorbProgressBar:SetTexture(flatTexture)
    absorbProgressBar:SetColorTexture(absorbColor.r, absorbColor.g, absorbColor.b, absorbColor.a)
    
    -- Position both textures to cover the entire text area
    PixelUtilCompat.SetPoint(absorbProgressBg, "TOPLEFT", texture, "BOTTOMLEFT", 0, -padding)
    PixelUtilCompat.SetPoint(absorbProgressBg, "TOPRIGHT", texture, "BOTTOMRIGHT", 0, -padding)
    PixelUtilCompat.SetPoint(absorbProgressBg, "BOTTOM", frame, "BOTTOM", 0, padding)
    
    PixelUtilCompat.SetPoint(absorbProgressBar, "TOPLEFT", texture, "BOTTOMLEFT", 0, -padding)
    PixelUtilCompat.SetPoint(absorbProgressBar, "TOPRIGHT", texture, "BOTTOMRIGHT", 0, -padding)
    PixelUtilCompat.SetPoint(absorbProgressBar, "BOTTOM", frame, "BOTTOM", 0, padding)
    
    -- Store initial width for progress calculations
    local function updateAbsorbProgress(percentage)
        percentage = math.max(0, math.min(1, percentage))
        local fullWidth = absorbProgressBg:GetWidth() or 0
        local progressWidth = fullWidth * percentage
        
        absorbProgressBar:ClearAllPoints()
        PixelUtilCompat.SetPoint(absorbProgressBar, "TOPLEFT", texture, "BOTTOMLEFT", 0, -padding)
        absorbProgressBar:SetWidth(progressWidth)
        PixelUtilCompat.SetPoint(absorbProgressBar, "BOTTOM", frame, "BOTTOM", 0, padding)
    end
    
    -- Create helper functions to mimic StatusBar interface
    local absorbProgressHelper = {
        SetValue = function(self, value)
            updateAbsorbProgress(value)
        end,
        SetStatusBarColor = function(self, r, g, b, a)
            absorbProgressBar:SetColorTexture(r, g, b, a)
        end,
        Show = function(self)
            absorbProgressBg:Show()
            absorbProgressBar:Show()
        end,
        Hide = function(self)
            absorbProgressBg:Hide()
            absorbProgressBar:Hide()
        end
    }

    -- Hide by default
    absorbProgressHelper:Hide()

    -- Create backdrop texture object
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ItemEntryBG", "backdrop", 0)

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
    local animGroup, shakeGroup, shake1, shake2, shake3 = CreateAnimations(frame, iconSize, wipeOverlay, shakeOverlay)

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
    frame.absorbProgressBar = absorbProgressHelper
    frame.absorbProgressBg = absorbProgressBg

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

-- =============================================================== --
-- AuraIcon:Display
-- Updates this icon to represent the provided aura data (visuals & state).
-- =============================================================== --
function AuraIcon:Display(auraData, index, auraType, isNewAura)
    if not auraData then
        self:Reset()
        return
    end

    -- Section 1: Update internal state from auraData
    self.isExpired = auraData.forceExpired or false
    isNewAura = isNewAura or false

    if auraData.forceExpired then
        self.lastIsExpiredState = true
        self.frame.durationText:SetText("0s")
    else
        self.lastIsExpiredState = false
        self.expiredAt = nil
    end

    self.duration = auraData.duration
    self.expirationTime = auraData.expirationTime
    self.auraIndex = index
    self.auraType = auraType
    self.name = auraData.name
    self.spellId = auraData.spellId
    self.originalAuraType = auraData.originalAuraType
    self.auraInstanceID = auraData.auraInstanceID
    self.slot = auraData.slot
    self.auraKey = auraData.spellId
    self.dispelName = auraData.dispelName

    -- Section 2: Get frame settings and apply visuals
    local settings = GetFrameSettings(self.parentDisplayFrame)

    self:Resize(settings.iconSize, settings.textSize)
    self.textureWidget:SetTexture(auraData.icon)

    -- Handle stack count display
    if auraData.applications and auraData.applications > 1 then
        self.frame.countText:SetText(auraData.applications)
        self.frame.countText:Show()
        self.frame.countTextBg:Show()
    else
        self.frame.countText:Hide()
        self.frame.countTextBg:Hide()
    end

    -- Apply border styling using helper
    if BoxxyAuras.DEBUG then
        print(string.format("Display: Applying border styling for '%s' (auraType=%s, borderSize=%d, reused=%s)",
            self.name or "Unknown", tostring(auraType), settings.borderSize or 0, tostring(not isNewAura)))
    end
    ApplyBorderStyling(self.frame, auraType, settings.borderSize, self.dispelName)

    -- Handle healing absorb progress bar
    self:UpdateHealingAbsorbDisplay(auraData)

    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local cfgBG = (currentSettings and currentSettings.normalBackgroundColor) or
        BoxxyAuras:GetDefaultProfileSettings().normalBackgroundColor
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "backdrop", cfgBG.r, cfgBG.g, cfgBG.b, cfgBG.a)

    if self.isExpired then
        self.textureWidget:SetVertexColor(1, 0.5, 0.5)
    else
        self.textureWidget:SetVertexColor(1, 1, 1)
    end

    -- Section 4: Handle Animation and Visibility
    local frameWasHidden = not self.frame:IsShown() -- Check if frame is currently hidden
    local shouldShowAnimation = (frameWasHidden or isNewAura) and not self.isExpired

    local playAnimation = false
    if shouldShowAnimation then
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        local enableFlashOnShow = currentSettings.enableFlashAnimationOnShow
        if enableFlashOnShow == nil then enableFlashOnShow = true end

        if enableFlashOnShow and self.newAuraAnimGroup and not self.newAuraAnimGroup:IsPlaying() then
            playAnimation = true
        end
    end

    -- Debug animation trigger
    if BoxxyAuras.DEBUG then
        print(string.format(
            "ANIMATION DEBUG: frameWasHidden=%s, isNewAura=%s, shouldShow=%s, isExpired=%s, enableFlash=%s, hasAnimGroup=%s, isPlaying=%s, willPlay=%s",
            tostring(frameWasHidden), tostring(isNewAura), tostring(shouldShowAnimation), tostring(self.isExpired),
            tostring(enableFlashOnShow), tostring(self.newAuraAnimGroup ~= nil),
            tostring(self.newAuraAnimGroup and self.newAuraAnimGroup:IsPlaying()), tostring(playAnimation)))

        if playAnimation then
            print(string.format("ANIMATION: Playing show animation for aura '%s', wipeOverlay exists: %s",
                self.name or "Unknown", tostring(self.frame.wipeOverlay ~= nil)))
        end
    end

    if playAnimation then
        self.frame:Show()
        self.newAuraAnimGroup:Play()
    else
        self.frame:SetAlpha(1)
        self.frame:Show()
    end

    -- CRITICAL FIX: Ensure border textures are shown when frame is shown
    -- This fixes the issue where reused icons lose their borders
    if self.frame.borderTextures then
        for _, tex in pairs(self.frame.borderTextures) do
            if tex then
                tex:Show()
            end
        end
        if BoxxyAuras.DEBUG then
            print(string.format("BORDER FIX: Showing border textures for '%s'", self.name or "Unknown"))
        end
    end

    -- Section 5: Register for Duration Updates
    if self.isMouseOver then
        self.tooltipUpdateTimer = self.tooltipUpdateTimer or 0
        self.needsTooltipUpdate = true
    end

    if not self.isExpired and self.duration and self.duration > 0 then
        if BoxxyAuras.UpdateManager then BoxxyAuras.UpdateManager:RegisterAura(self) end
    else
        if BoxxyAuras.UpdateManager then BoxxyAuras.UpdateManager:UnregisterAura(self) end
        if self.duration == 0 or self.duration <= 0 then
            if self.frame.durationText then self.frame.durationText:Hide() end
        end
    end

    if not self.isExpired then
        AuraIcon.UpdateDurationDisplay(self, GetTime())
    end
end

-- Assign to the global table
BoxxyAuras.AuraIcon = AuraIcon

-- Debug command for testing animations
SLASH_BOXXYAURASDEBUG1 = "/badebug"
SlashCmdList["BOXXYAURASDEBUG"] = function(msg)
    BoxxyAuras.DEBUG = not BoxxyAuras.DEBUG
    print("BoxxyAuras DEBUG mode: " .. (BoxxyAuras.DEBUG and "ON" or "OFF"))
end

-- Debug command for testing healing absorb progress bars
SLASH_BOXXYAURASABSORB1 = "/baabsorb"
SlashCmdList["BOXXYAURASABSORB"] = function(msg)
    if not BoxxyAuras.DEBUG then
        print("BoxxyAuras: Enable DEBUG mode first (/badebug)")
        return
    end
    
    local command, value = string.match(msg, "^(%S+)%s*(.*)$")
    command = command or msg
    
    if command == "list" then
        -- List all current debuffs to help identify healing absorbs
        print("BoxxyAuras: Current debuffs:")
        
        if C_UnitAuras and C_UnitAuras.GetAuraSlots then
            local auraSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }
            local foundAny = false
            
            for i = 2, #auraSlots do
                local slot = auraSlots[i]
                local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
                if auraData then
                    foundAny = true
                    print(string.format("  '%s' - ID: %s, Type: %s, Dispel: %s", 
                        auraData.name or "Unknown",
                        tostring(auraData.spellId),
                        tostring(auraData.dispelName),
                        tostring(auraData.auraType)))
                end
            end
            
            if not foundAny then
                print("  No debuffs found")
            end
        end
        
    elseif command == "test" then
        -- Create a fake healing absorb for testing
        print("BoxxyAuras: Creating test healing absorb...")
        
        if not BoxxyAuras.healingAbsorbTracking then
            BoxxyAuras.healingAbsorbTracking = {}
        end
        
        -- Find any active debuff to apply the test absorb to
        for frameType, iconArray in pairs(BoxxyAuras.iconArrays or {}) do
            if iconArray and #iconArray > 0 then
                for _, icon in ipairs(iconArray) do
                    if icon and icon.auraType == "HARMFUL" and icon.frame and icon.frame.absorbProgressBar then
                        local testKey = icon.auraInstanceID or ("test_" .. (icon.spellId or 0))
                        BoxxyAuras.healingAbsorbTracking[testKey] = {
                            initialAmount = 500000,
                            currentAmount = 500000,
                            spellId = icon.spellId,
                            auraInstanceID = icon.auraInstanceID,
                            lastUpdate = GetTime()
                        }
                        
                        icon.frame.absorbProgressBar:SetValue(1.0)
                        icon.frame.absorbProgressBar:Show()
                        
                        print(string.format("BoxxyAuras: Applied test absorb to '%s' (500k healing)", icon.name or "Unknown"))
                        return
                    end
                end
            end
        end
        print("BoxxyAuras: No suitable debuff found for testing")
        
    elseif command == "damage" then
        local amount = tonumber(value) or 100000
        print(string.format("BoxxyAuras: Simulating %d absorbed healing...", amount))
        
        -- Reduce all active absorbs
        local updated = false
        for trackingKey, trackingData in pairs(BoxxyAuras.healingAbsorbTracking or {}) do
            if trackingData.currentAmount > 0 then
                trackingData.currentAmount = math.max(0, trackingData.currentAmount - amount)
                trackingData.lastUpdate = GetTime()
                BoxxyAuras:UpdateHealingAbsorbVisuals(trackingKey, trackingData)
                updated = true
                
                print(string.format("BoxxyAuras: Absorb reduced to %d/%d", 
                    trackingData.currentAmount, trackingData.initialAmount))
            end
        end
        
        if not updated then
            print("BoxxyAuras: No active absorbs to damage")
        end
        
    elseif command == "clear" then
        BoxxyAuras.healingAbsorbTracking = {}
        
        -- Hide all absorb bars
        for frameType, iconArray in pairs(BoxxyAuras.iconArrays or {}) do
            if iconArray then
                for _, icon in ipairs(iconArray) do
                    if icon and icon.frame and icon.frame.absorbProgressBar then
                        icon.frame.absorbProgressBar:Hide()
                    end
                end
            end
        end
        
        print("BoxxyAuras: Cleared all healing absorb tracking")
        
    else
        print("BoxxyAuras Healing Absorb Test Commands:")
        print("  /baabsorb list - List all current debuffs with spell IDs")
        print("  /baabsorb test - Create a test healing absorb")
        print("  /baabsorb damage [amount] - Simulate absorbed healing (default: 100k)")
        print("  /baabsorb clear - Clear all absorb tracking")
    end
end

-- =============================================================== --
-- AuraIcon.UpdateDurationDisplay
-- Per-frame update driving countdown text, tint and manager registration.
-- =============================================================== --
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
    end

    if self.frame.durationText then
        self.frame.durationText:SetJustifyH("CENTER")
    end
end

-- =============================================================== --
-- AuraIcon.OnEnter
-- Mouse-over handler: shows tooltip and flags for tooltip refresh.
-- =============================================================== --
function AuraIcon.OnEnter(self)
    self.isMouseOver = true
    self.needsTooltipUpdate = true
    self.tooltipUpdateTimer = 0
    GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    AuraIcon.RefreshTooltipContent(self)
    GameTooltip:Show()
end

-- =============================================================== --
-- AuraIcon.HasCasterLineInTooltip
-- Utility: Detects if another addon already inserted caster info lines.
-- =============================================================== --
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

-- =============================================================== --
-- AuraIcon.AddWrappedTooltipLine
-- Adds a line (or double-line) to the tooltip with automatic wrapping.
-- =============================================================== --
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

-- =============================================================== --
-- AuraIcon.RefreshTooltipContent
-- Completely rebuilds the tooltip content for this aura icon.
-- =============================================================== --
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

-- =============================================================== --
-- AuraIcon.OnLeave
-- Mouse-leave handler: hides tooltip and clears hover tracking.
-- =============================================================== --
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

function AuraIcon:UpdateBorderSize(auraData)
    if not self.frame then
        return
    end

    -- If auraData is not provided, try to get it from the instance itself
    if not auraData then
        auraData = {
            auraType = self.auraType,
            dispelName = self.dispelName,
        }
    end

    if not auraData or not auraData.auraType then
        return
    end

    -- Get current styling parameters
    local frameType = nil
    if self.parentDisplayFrame then
        for fType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame == self.parentDisplayFrame then
                frameType = fType
                break
            end
        end
    end

    local frameSettings = frameType and BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    local borderSize = (frameSettings and frameSettings.borderSize) or 1
    local iconSize = (frameSettings and frameSettings.iconSize) or BoxxyAuras.Config.IconSize
    local textSize = (frameSettings and frameSettings.textSize) or 8

    -- Reapply border styling with updated border size
    ApplyBorderStyling(self.frame, auraData.auraType, borderSize, auraData.dispelName)
end

function AuraIcon:Resize(newIconSize, newTextSize)
    if not self.frame or not self.textureWidget then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras ERROR: Invalid icon instance in Resize - missing frame or texture")
        end
        return
    end

    -- Get text size from parameter or settings using helper
    local textSize = newTextSize or GetFrameSettings(self.parentDisplayFrame).textSize

    -- Prevent unnecessary resizing
    if self.currentSize == newIconSize and self.currentTextSize == textSize then
        return
    end

    if BoxxyAuras.DEBUG then
        local frameType = GetFrameType(self.parentDisplayFrame) or "unknown"
        print("BoxxyAuras: Resizing " ..
            frameType .. " icon from " .. (self.currentSize or "unset") .. " to " .. newIconSize)
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
    end

    -- Apply font sizes using helper
    ApplyFontSizes(self.frame.durationText, self.frame.countText, textSize)

    -- Re-anchor overlay textures
    if self.frame.wipeOverlay then
        self.frame.wipeOverlay:ClearAllPoints()
        PixelUtilCompat.SetPoint(self.frame.wipeOverlay, "TOPLEFT", self.textureWidget, "TOPLEFT")
    end

    if self.frame.shakeOverlay then
        self.frame.shakeOverlay:ClearAllPoints()
        PixelUtilCompat.SetPoint(self.frame.shakeOverlay, "TOPLEFT", self.textureWidget, "TOPLEFT")
    end

    -- Re-anchor absorb progress bar background texture to fill the text area
    if self.frame.absorbProgressBg then
        self.frame.absorbProgressBg:ClearAllPoints()
        PixelUtilCompat.SetPoint(self.frame.absorbProgressBg, "TOPLEFT", self.textureWidget, "BOTTOMLEFT", 0, -padding)
        PixelUtilCompat.SetPoint(self.frame.absorbProgressBg, "TOPRIGHT", self.textureWidget, "BOTTOMRIGHT", 0, -padding)
        PixelUtilCompat.SetPoint(self.frame.absorbProgressBg, "BOTTOM", self.frame, "BOTTOM", 0, padding)
    end
    
    -- Note: The absorb progress bar foreground texture will be repositioned automatically when SetValue is called
end

-- =============================================================== --
-- AuraIcon.GetCasterNameFromCurrentData
-- Looks up the cached combat-log tracking table for the aura's caster.
-- =============================================================== --
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

-- =============================================================== --
-- AuraIcon:UpdateHealingAbsorbDisplay
-- Shows/hides and updates the healing absorb progress bar
-- =============================================================== --
function AuraIcon:UpdateHealingAbsorbDisplay(auraData)
    if not self.frame or not self.frame.absorbProgressBar then
        return
    end

    -- Check if this is a healing absorb debuff
    local isHealingAbsorb = self:IsHealingAbsorbDebuff(auraData)

    if isHealingAbsorb then
        -- Initialize healing absorb tracking if needed
        if not BoxxyAuras.healingAbsorbTracking then
            BoxxyAuras.healingAbsorbTracking = {}
        end

        local trackingKey = auraData.auraInstanceID or auraData.spellId
        if trackingKey then
            -- Initialize tracking data if this is a new absorb
            if not BoxxyAuras.healingAbsorbTracking[trackingKey] then
                local initialAmount = self:GetInitialAbsorbAmount(auraData)
                if initialAmount and initialAmount > 0 then
                    BoxxyAuras.healingAbsorbTracking[trackingKey] = {
                        initialAmount = initialAmount,
                        currentAmount = initialAmount,
                        spellId = auraData.spellId,
                        auraInstanceID = auraData.auraInstanceID,
                        lastUpdate = GetTime()
                    }
                end
            end

            -- Update progress bar if we have tracking data
            local tracking = BoxxyAuras.healingAbsorbTracking[trackingKey]
            if tracking and tracking.initialAmount > 0 then
                local percentage = math.max(0, tracking.currentAmount / tracking.initialAmount)
                self.frame.absorbProgressBar:SetValue(percentage)
                self.frame.absorbProgressBar:Show()
            else
                self.frame.absorbProgressBar:Hide()
                print("BoxxyAuras: No tracking data, hiding absorb bar")
            end
        else
            self.frame.absorbProgressBar:Hide()
            print("BoxxyAuras: No tracking key, hiding absorb bar")
        end
    else
        -- Not a healing absorb, hide the progress bar
        self.frame.absorbProgressBar:Hide()
    end
end

-- =============================================================== --
-- AuraIcon:IsHealingAbsorbDebuff
-- Determines if the aura is a healing absorb effect by checking the API data
-- =============================================================== --
function AuraIcon:IsHealingAbsorbDebuff(auraData)
    if not auraData or auraData.auraType ~= "HARMFUL" then
        return false
    end

    -- The WoW API provides healing absorb information directly in the points field
    -- If points exist and contain meaningful values, this is a healing absorb
    local points = auraData.points
    if points and type(points) == "table" and #points > 0 then
        -- Look for any meaningful absorb value in the points array
        for i, point in ipairs(points) do
            if point and point > 0 then
                if BoxxyAuras.DEBUG then
                    print(string.format("BoxxyAuras: Detected healing absorb by API data: %s (%d) - absorb amount: %d", 
                        auraData.name or "Unknown", auraData.spellId or 0, point))
                end
                return true
            end
        end
    end

    -- Special case: Demo mode healing absorb (for testing)
    if auraData.spellId == 22351 then -- Demo Healing Absorb
        if BoxxyAuras.DEBUG then
            print(string.format("BoxxyAuras: Detected demo mode healing absorb: %s", auraData.name or "Unknown"))
        end
        return true
    end

    return false
end

-- =============================================================== --
-- AuraIcon:GetInitialAbsorbAmount
-- Attempts to determine the initial healing absorb amount
-- =============================================================== --
function AuraIcon:GetInitialAbsorbAmount(auraData)
    if not auraData then
        return 0
    end

    -- First, try to get absorb amount from the aura data itself
    -- Some auras provide points/amount information that represents the absorb capacity
    local points = auraData.points
    if points and type(points) == "table" and #points > 0 then
        -- Look for the first meaningful value in the points array
        for i, point in ipairs(points) do
            if point and point > 0 then
                return point
            end
        end
    end

    -- Try the applications field as some absorbs use stacks to represent capacity
    local applications = auraData.applications
    if applications and applications > 1 then
        -- For stacking absorbs, estimate based on applications
        local baseAmount = 50000 -- Base amount per stack
        local totalAmount = baseAmount * applications
        return totalAmount
    end

    -- Try tooltip scanning as fallback
    local tooltipAmount = self:GetAbsorbAmountFromTooltip(auraData)
    if tooltipAmount and tooltipAmount > 0 then
        return tooltipAmount
    end

    -- Final fallback: Use a reasonable default amount based on level/content
    -- This ensures the progress bar still shows up even if we can't get exact amounts
    local playerLevel = UnitLevel("player") or 70
    local fallbackAmount = math.max(100000, playerLevel * 8000) -- Scale with player level, higher than before
    
    return fallbackAmount
end

-- AuraIcon:GetAbsorbAmountFromTooltip
-- Attempts to extract healing absorb amount from aura tooltip
-- =============================================================== --
function AuraIcon:GetAbsorbAmountFromTooltip(auraData)
    if not auraData or not auraData.spellId then
        return nil
    end

    -- Create a tooltip scanner
    local tooltip = CreateFrame("GameTooltip", "BoxxyAurasAbsorbScanner", nil, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    
    -- Set the tooltip to the spell
    tooltip:SetSpellByID(auraData.spellId)
    
    -- Scan tooltip lines for absorb amounts
    for i = 1, tooltip:NumLines() do
        local line = _G["BoxxyAurasAbsorbScannerTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                -- Look for patterns like "absorbs 123,456 healing" or "absorbs 123456 damage from healing"
                local amount = string.match(text, "absorbs? (%d[%d,]*) .-heal")
                if not amount then
                    amount = string.match(text, "absorbs? (%d[%d,]*)")
                end
                if amount then
                    -- Remove commas and convert to number
                    local numericAmount = tonumber(string.gsub(amount, ",", ""))
                    if numericAmount and numericAmount > 0 then
                        tooltip:Hide()
                        return numericAmount
                    end
                end
            end
        end
    end
    
    tooltip:Hide()
    return nil
end

-- =============================================================== --
-- AuraIcon:UpdateAbsorbProgressBarColor
-- Updates the color of the healing absorb progress bar from current settings
-- =============================================================== --
function AuraIcon:UpdateAbsorbProgressBarColor()
    if not self.frame or not self.frame.absorbProgressBar then
        return
    end

    -- Get color from current profile settings
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local absorbColor = (currentSettings and currentSettings.healingAbsorbBarColor) or { r = 0.86, g = 0.28, b = 0.13, a = 0.8 }
    
    -- Update the progress bar color using the helper's method
    self.frame.absorbProgressBar:SetStatusBarColor(absorbColor.r, absorbColor.g, absorbColor.b, absorbColor.a)
end

-- =============================================================== --
-- AuraIcon:Reset
-- Returns the icon instance to its initial, unused state for pooling.
-- =============================================================== --
function AuraIcon:Reset()
    if not self.frame then
        return
    end

    -- Unregister from central update manager
    if BoxxyAuras.UpdateManager then
        BoxxyAuras.UpdateManager:UnregisterAura(self)
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

    -- Clear any existing border styling to ensure clean state for reuse
    if self.frame and self.frame.borderTextures then
        for _, tex in pairs(self.frame.borderTextures) do
            if tex and tex.Hide then
                tex:Hide()
                if BoxxyAuras.DEBUG then
                    print("Reset: Hiding border texture")
                end
            end
        end
    end

    -- Hide and reset absorb progress bar
    if self.frame and self.frame.absorbProgressBar then
        self.frame.absorbProgressBar:Hide()
        self.frame.absorbProgressBar:SetValue(1) -- Reset to full
    end

    -- Hide tooltip if it's showing for this frame
    if GameTooltip:IsOwned(self.frame) then
        GameTooltip:Hide()
    end

    -- CRITICAL: Hide the frame when returning to pool
    self.frame:Hide()
end
