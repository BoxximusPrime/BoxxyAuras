local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}       -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras          -- Create a convenient local alias to the global table
BoxxyAuras.Options = {}                   -- Table to hold options elements

-- LibSharedMedia for font selection
local Media = LibStub("LibSharedMedia-3.0")

-- Register our addon's fonts with LibSharedMedia so they appear in the dropdown
Media:Register("font", "OpenSans SemiBold", "Interface\\AddOns\\BoxxyAuras\\Fonts\\OpenSans-SemiBold.ttf")
Media:Register("font", "HK Grotesk Bold", "Interface\\AddOns\\BoxxyAuras\\Fonts\\hk-grotesk.bold.ttf")
Media:Register("font", "OpenSans Bold", "Interface\\AddOns\\BoxxyAuras\\Fonts\\OpenSans-Bold.ttf")
Media:Register("font", "OpenSans Bold Italic", "Interface\\AddOns\\BoxxyAuras\\Fonts\\OpenSans-BoldItalic.ttf")

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

-- <<< NEW: Local reference to the profile settings helper >>>
local function GetCurrentProfileSettings()
    -- Ensure the main addon table and function exist
    if BoxxyAuras and BoxxyAuras.GetCurrentProfileSettings then
        return BoxxyAuras:GetCurrentProfileSettings()
    else
        -- Fallback or error if the main function isn't loaded yet or missing
        -- print("|cffFF0000BoxxyAuras Options Error:|r Cannot get profile settings helper function!")
        -- Return a structure with defaults to avoid errors in options UI setup
        return {
            lockFrames = false,
            hideBlizzardAuras = true,
            auraBarScale = 1.0,
            optionsWindowScale = 1.0,
            buffFrameSettings = {
                buffTextAlign = "CENTER",
                iconSize = 24,
                textSize = 8,
                borderSize = 1
            },
            debuffFrameSettings = {
                debuffTextAlign = "CENTER",
                iconSize = 24,
                textSize = 8,
                borderSize = 1
            },
            customFrameSettings = {
                customTextAlign = "CENTER",
                iconSize = 24,
                textSize = 8,
                borderSize = 1
            }
        }
    end
end

-- Apply text alignment changes
function BoxxyAuras.Options:ApplyTextAlign(frameType)
    if BoxxyAuras.DEBUG then
        print(string.format("ApplyAlignment called for frameType: %s", tostring(frameType)))
    end

    if not frameType then
        -- Update all frame types (fallback)
        for _, fType in ipairs({ "Buff", "Debuff" }) do
            self:ApplyTextAlign(fType)
        end
        return
    end



    -- Trigger icon repositioning with the new alignment
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.UpdateAurasInFrame then
        BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
    end
end

-- Apply wrap direction changes
function BoxxyAuras.Options:ApplyWrapDirection(frameType)
    -- Check if required data structures exist
    if not BoxxyAuras.FrameHandler then
        return
    end

    if not BoxxyAuras.FrameHandler.UpdateAurasInFrame then
        return
    end

    if frameType then
        -- Update specific frame type
        BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
    else
        -- Update all frame types (fallback)
        for _, fType in ipairs({ "Buff", "Debuff" }) do
            BoxxyAuras.FrameHandler.UpdateAurasInFrame(fType)
        end
    end
end

-- Apply icon size changes
function BoxxyAuras.Options:ApplyIconSizeChange(frameType)
    if not frameType then return end

    local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not frameSettings then return end

    local iconSize = frameSettings.iconSize
    if not iconSize then return end

    -- Resize all icons for this frame type
    local icons = BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[frameType]
    if icons then
        for _, icon in ipairs(icons) do
            if icon and icon.Resize then
                icon:Resize(iconSize)
            end
        end
    end

    -- Update the main frame's layout (width, height, icon positions)
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.ApplySettings then
        BoxxyAuras.FrameHandler.ApplySettings(frameType)
    end
end

-- Apply text size changes
function BoxxyAuras.Options:ApplyTextSizeChange(frameType)
    if not frameType then return end

    local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not frameSettings then return end

    -- The AuraIcon:Resize function automatically picks up the new text size from settings.
    -- We just need to call it with the *current* icon size to trigger a refresh.
    local iconSize = frameSettings.iconSize
    if not iconSize then return end

    local icons = BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[frameType]
    if icons then
        for _, icon in ipairs(icons) do
            if icon and icon.Resize then
                icon:Resize(iconSize)
            end
        end
    end

    -- Update the main frame's layout
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.ApplySettings then
        BoxxyAuras.FrameHandler.ApplySettings(frameType)
    end
end

-- Apply border size changes
function BoxxyAuras.Options:ApplyBorderSizeChange(frameType)
    if not frameType then return end

    local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not frameSettings then return end

    local borderSize = frameSettings.borderSize
    if borderSize == nil then return end

    -- Apply border size to all aura icons of this frame type
    local iconArray = BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[frameType]
    local trackedAuras = BoxxyAuras.auraTracking and BoxxyAuras.auraTracking[frameType]

    if iconArray and trackedAuras then
        for i, icon in ipairs(iconArray) do
            local auraData = trackedAuras[i]
            if icon and icon.UpdateBorderSize and auraData then
                icon:UpdateBorderSize(auraData)
            end
        end
    end

    -- THROTTLED UPDATE: Cancel any pending update and schedule a new one
    -- This prevents rapid successive calls from accumulating
    if not BoxxyAuras.Options.updateTimers then
        BoxxyAuras.Options.updateTimers = {}
    end

    -- Cancel existing timer for this frame type
    if BoxxyAuras.Options.updateTimers[frameType] then
        BoxxyAuras.Options.updateTimers[frameType]:Cancel()
    end

    -- Schedule throttled update
    BoxxyAuras.Options.updateTimers[frameType] = C_Timer.NewTimer(0.1, function()
        if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.UpdateAurasInFrame then
            BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
        end
        BoxxyAuras.Options.updateTimers[frameType] = nil
    end)
end

-- Apply icon spacing changes
function BoxxyAuras.Options:ApplyIconSpacingChange(frameType)
    if not frameType then return end

    local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not frameSettings then return end

    -- THROTTLED UPDATE: Cancel any pending update and schedule a new one
    -- This prevents rapid successive calls from accumulating
    if not BoxxyAuras.Options.updateTimers then
        BoxxyAuras.Options.updateTimers = {}
    end

    -- Cancel existing timer for this frame type
    if BoxxyAuras.Options.updateTimers[frameType] then
        BoxxyAuras.Options.updateTimers[frameType]:Cancel()
    end

    -- Schedule throttled update - spacing changes require frame width recalculation
    BoxxyAuras.Options.updateTimers[frameType] = C_Timer.NewTimer(0.1, function()
        if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.ApplySettings then
            BoxxyAuras.FrameHandler.ApplySettings(frameType)
        end
        BoxxyAuras.Options.updateTimers[frameType] = nil
    end)
end

function BoxxyAuras.Options:ApplyNormalBorderColorChange()
    for frameType, icons in pairs(BoxxyAuras.iconArrays or {}) do
        local trackedAuras = BoxxyAuras.auraTracking and BoxxyAuras.auraTracking[frameType]
        if trackedAuras then
            for i, icon in ipairs(icons) do
                local auraData = trackedAuras[i]
                if icon and icon.UpdateBorderSize and auraData then
                    icon:UpdateBorderSize(auraData) -- This function re-evaluates and re-applies the border color
                end
            end
        end
    end

    -- THROTTLED UPDATE: Use the same throttling mechanism
    if not BoxxyAuras.Options.updateTimers then
        BoxxyAuras.Options.updateTimers = {}
    end

    -- Schedule a single update for all frame types after color changes
    if BoxxyAuras.Options.updateTimers.colorUpdate then
        BoxxyAuras.Options.updateTimers.colorUpdate:Cancel()
    end

    BoxxyAuras.Options.updateTimers.colorUpdate = C_Timer.NewTimer(0.1, function()
        -- Update all frame types once after color change
        for frameType in pairs(BoxxyAuras.iconArrays or {}) do
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.UpdateAurasInFrame then
                BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
            end
        end
        BoxxyAuras.Options.updateTimers.colorUpdate = nil
    end)
end

-- Helper function to update the normal border color swatch display
function BoxxyAuras.Options:UpdateNormalBorderColorSwatch()
    if not self.NormalBorderColorSwatch or not self.NormalBorderColorSwatch.background then
        return
    end

    local settings = BoxxyAuras:GetCurrentProfileSettings()
    if not settings then
        return
    end

    local color = settings.normalBorderColor or BoxxyAuras:GetDefaultProfileSettings().normalBorderColor
    self.NormalBorderColorSwatch.background:SetColorTexture(color.r, color.g, color.b, color.a)

    if BoxxyAuras.DEBUG then
        print(string.format("Updated normal border color swatch: r=%.2f, g=%.2f, b=%.2f, a=%.2f",
            color.r, color.g, color.b, color.a))
    end
end

-- Helper function to update the background color swatch display
function BoxxyAuras.Options:UpdateBackgroundColorSwatch()
    if not self.BackgroundColorSwatch or not self.BackgroundColorSwatch.background then
        return
    end

    local settings = BoxxyAuras:GetCurrentProfileSettings()
    if not settings then
        return
    end

    local color = settings.normalBackgroundColor or BoxxyAuras:GetDefaultProfileSettings().normalBackgroundColor
    self.BackgroundColorSwatch.background:SetColorTexture(color.r, color.g, color.b, color.a)

    if BoxxyAuras.DEBUG then
        print(string.format("Updated background color swatch: r=%.2f, g=%.2f, b=%.2f, a=%.2f",
            color.r, color.g, color.b, color.a))
    end
end

function BoxxyAuras.Options:ApplyBackgroundColorChange()
    for frameType, icons in pairs(BoxxyAuras.iconArrays or {}) do
        local trackedAuras = BoxxyAuras.auraTracking and BoxxyAuras.auraTracking[frameType]
        if trackedAuras then
            for i, icon in ipairs(icons) do
                local auraData = trackedAuras[i]
                if icon and icon.UpdateBorderSize and auraData then
                    icon:UpdateBorderSize(auraData) -- This function re-evaluates and re-applies the background color
                end
            end
        end
    end

    -- THROTTLED UPDATE: Use the same throttling mechanism as border color
    if not BoxxyAuras.Options.updateTimers then
        BoxxyAuras.Options.updateTimers = {}
    end

    -- Schedule a single update for all frame types after background color changes
    if BoxxyAuras.Options.updateTimers.backgroundColorUpdate then
        BoxxyAuras.Options.updateTimers.backgroundColorUpdate:Cancel()
    end

    BoxxyAuras.Options.updateTimers.backgroundColorUpdate = C_Timer.NewTimer(0.1, function()
        -- Update all frame types once after background color change
        for frameType in pairs(BoxxyAuras.iconArrays or {}) do
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.UpdateAurasInFrame then
                BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
            end
        end
        BoxxyAuras.Options.updateTimers.backgroundColorUpdate = nil
    end)
end

-- Helper function to update the healing absorb color swatch display
function BoxxyAuras.Options:UpdateHealingAbsorbColorSwatch()
    if not self.HealingAbsorbColorSwatch or not self.HealingAbsorbColorSwatch.background then
        return
    end

    local settings = BoxxyAuras:GetCurrentProfileSettings()
    if not settings then
        return
    end

    local color = settings.healingAbsorbBarColor or BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarColor
    self.HealingAbsorbColorSwatch.background:SetColorTexture(color.r, color.g, color.b, color.a)

    if BoxxyAuras.DEBUG then
        print(string.format("Updated healing absorb color swatch: r=%.2f, g=%.2f, b=%.2f, a=%.2f",
            color.r, color.g, color.b, color.a))
    end
end

-- Helper function to update the healing absorb background color swatch display
function BoxxyAuras.Options:UpdateHealingAbsorbBGColorSwatch()
    if not self.HealingAbsorbBGColorSwatch or not self.HealingAbsorbBGColorSwatch.background then
        return
    end

    local settings = BoxxyAuras:GetCurrentProfileSettings()
    if not settings then
        return
    end

    local color = settings.healingAbsorbBarBGColor or BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarBGColor
    self.HealingAbsorbBGColorSwatch.background:SetColorTexture(color.r, color.g, color.b, color.a)

    if BoxxyAuras.DEBUG then
        print(string.format("Updated healing absorb BG color swatch: r=%.2f, g=%.2f, b=%.2f, a=%.2f",
            color.r, color.g, color.b, color.a))
    end
end

-- Helper function to update the text color swatch display
function BoxxyAuras.Options:UpdateTextColorSwatch()
    if not self.TextColorSwatch or not self.TextColorSwatch.background then
        return
    end

    local settings = BoxxyAuras:GetCurrentProfileSettings()
    if not settings then
        return
    end

    local color = settings.textColor or BoxxyAuras:GetDefaultProfileSettings().textColor
    self.TextColorSwatch.background:SetColorTexture(color.r, color.g, color.b, color.a)

    if BoxxyAuras.DEBUG then
        print(string.format("Updated text color swatch: r=%.2f, g=%.2f, b=%.2f, a=%.2f",
            color.r, color.g, color.b, color.a))
    end
end

function BoxxyAuras.Options:ApplyHealingAbsorbColorChange()
    -- Update all existing healing absorb bars with new colors
    if BoxxyAuras.Frames then
        for _, frame in pairs(BoxxyAuras.Frames) do
            if frame and frame.HealingAbsorbFrame then
                local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
                local healingAbsorbColor = currentSettings.healingAbsorbBarColor or
                BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarColor
                local healingAbsorbBGColor = currentSettings.healingAbsorbBarBGColor or
                BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarBGColor

                if frame.HealingAbsorbFrame.bar then
                    frame.HealingAbsorbFrame.bar:SetColorTexture(healingAbsorbColor.r, healingAbsorbColor.g,
                        healingAbsorbColor.b, healingAbsorbColor.a)
                end
                if frame.HealingAbsorbFrame.background then
                    frame.HealingAbsorbFrame.background:SetColorTexture(healingAbsorbBGColor.r, healingAbsorbBGColor.g,
                        healingAbsorbBGColor.b, healingAbsorbBGColor.a)
                end
            end
        end
    end

    -- Update all actual aura icon progress bars
    if BoxxyAuras.iconArrays then
        for frameType, iconArray in pairs(BoxxyAuras.iconArrays) do
            if iconArray then
                for _, icon in ipairs(iconArray) do
                    if icon and icon.UpdateAbsorbProgressBarColor then
                        icon:UpdateAbsorbProgressBarColor()
                    end
                end
            end
        end
    end
end

-- Apply font changes to all aura text elements
function BoxxyAuras.Options:ApplyFontChange()
    local settings = BoxxyAuras:GetCurrentProfileSettings()
    if not settings or not settings.textFont then
        return
    end

    local fontPath = Media:Fetch("font", settings.textFont, true) -- silent mode
    if not fontPath then
        if BoxxyAuras.DEBUG then
            print("|cffFF0000BoxxyAuras Error:|r Font not found: " .. tostring(settings.textFont))
        end
        -- Try fallback to our default registered font
        fontPath = Media:Fetch("font", "OpenSans SemiBold", true)
        if not fontPath then
            if BoxxyAuras.DEBUG then
                print("|cffFF0000BoxxyAuras Error:|r Default font not found either!")
            end
            return
        end
    end

    -- Update all existing aura icons' font
    if BoxxyAuras.iconArrays then
        for frameType, iconArray in pairs(BoxxyAuras.iconArrays) do
            if iconArray then
                for _, icon in ipairs(iconArray) do
                    if icon and icon.frame and icon.frame:IsShown() then
                        -- Get the frame settings for this icon's frame type to get proper text size
                        local frameSettings = BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.GetFrameSettingsTable
                            and BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
                        local textSize = (frameSettings and frameSettings.textSize) or 8

                        -- Update duration text font
                        if icon.frame.durationText then
                            local _, currentSize, currentFlags = icon.frame.durationText:GetFont()
                            icon.frame.durationText:SetFont(fontPath, textSize, currentFlags or "OUTLINE")
                        end

                        -- Update count text font (slightly larger for visibility)
                        if icon.frame.countText then
                            local _, currentCountSize, currentCountFlags = icon.frame.countText:GetFont()
                            icon.frame.countText:SetFont(fontPath, textSize + 2, currentCountFlags or "OUTLINE")
                        end
                    end
                end
            end
        end
    end

    if BoxxyAuras.DEBUG then
        print("|cff4CAF50BoxxyAuras:|r Font updated to: " .. settings.textFont)
    end
end

-- Apply text color changes to all aura text elements
function BoxxyAuras.Options:ApplyTextColorChange()
    local settings = BoxxyAuras:GetCurrentProfileSettings()
    if not settings or not settings.textColor then
        return
    end

    local textColor = settings.textColor

    -- Update all existing aura icons' text color
    if BoxxyAuras.iconArrays then
        for frameType, iconArray in pairs(BoxxyAuras.iconArrays) do
            if iconArray then
                for _, icon in ipairs(iconArray) do
                    if icon and icon.frame and icon.frame:IsShown() then
                        -- Update duration text color
                        if icon.frame.durationText then
                            icon.frame.durationText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a)
                        end

                        -- Update count text color
                        if icon.frame.countText then
                            icon.frame.countText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a)
                        end
                    end
                end
            end
        end
    end

    if BoxxyAuras.DEBUG then
        print(string.format("|cff4CAF50BoxxyAuras:|r Text color updated to: r=%.2f, g=%.2f, b=%.2f, a=%.2f",
            textColor.r, textColor.g, textColor.b, textColor.a))
    end
end

-- Helper function to create reset buttons for container sections
function BoxxyAuras.Options:CreateResetButton(container, resetFunction)
    if not container or not container.GetFrame then
        return nil
    end

    local containerFrame = container:GetFrame()

    -- Create the reset button
    local resetButton = CreateFrame("Button", nil, containerFrame)
    PixelUtilCompat.SetSize(resetButton, 28, 28)

    -- Position in top-right corner of the container (accounting for padding and border)
    PixelUtilCompat.SetPoint(resetButton, "TOPRIGHT", containerFrame, "TOPRIGHT", -8, -8)

    -- Set the refresh icon texture
    local icon = resetButton:CreateTexture(nil, "ARTWORK")
    PixelUtilCompat.SetAllPoints(icon, resetButton)
    icon:SetTexture("Interface\\AddOns\\BoxxyAuras\\Art\\refresh.tga")
    icon:SetTexCoord(0, 1, 0, 1)

    -- Add hover effects
    resetButton:SetScript("OnEnter", function(self)
        icon:SetVertexColor(1.2, 1.2, 1.2, 1) -- Brighten on hover

        -- Show tooltip
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset to Default Values", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    resetButton:SetScript("OnLeave", function(self)
        icon:SetVertexColor(0.9, 0.9, 0.9, 1) -- Dim when not hovering
        GameTooltip:Hide()
    end)

    -- Set initial color (slightly dimmed)
    icon:SetVertexColor(0.9, 0.9, 0.9, 1)

    -- Set click handler
    resetButton:SetScript("OnClick", function(self)
        if resetFunction then
            resetFunction()
        end
        PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end)

    return resetButton
end

-- Reset functions for different sections
function BoxxyAuras.Options:ResetGeneralSettings()
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end

    local defaults = BoxxyAuras:GetDefaultProfileSettings()

    -- Reset general settings to defaults
    currentSettings.lockFrames = defaults.lockFrames
    currentSettings.hideBlizzardAuras = defaults.hideBlizzardAuras
    currentSettings.showHoverBorder = defaults.showHoverBorder
    currentSettings.enableFlashAnimationOnShow = true -- Default value for flash animation
    currentSettings.enableDotTickingAnimation = defaults.enableDotTickingAnimation
    currentSettings.showInfiniteDuration = defaults.showInfiniteDuration
    currentSettings.textFont = defaults.textFont
    currentSettings.textColor = CopyTable(defaults.textColor)
    currentSettings.normalBorderColor = CopyTable(defaults.normalBorderColor)
    currentSettings.normalBackgroundColor = CopyTable(defaults.normalBackgroundColor)
    currentSettings.healingAbsorbBarColor = CopyTable(defaults.healingAbsorbBarColor)
    currentSettings.healingAbsorbBarBGColor = CopyTable(defaults.healingAbsorbBarBGColor)
    currentSettings.auraBarScale = defaults.auraBarScale
    currentSettings.optionsWindowScale = defaults.optionsWindowScale

    -- Update UI elements to reflect the reset values
    if BoxxyAuras.Options.LockFramesCheck then
        BoxxyAuras.Options.LockFramesCheck:SetChecked(currentSettings.lockFrames)
    end
    if BoxxyAuras.Options.HideBlizzardCheck then
        BoxxyAuras.Options.HideBlizzardCheck:SetChecked(currentSettings.hideBlizzardAuras)
    end
    if BoxxyAuras.Options.ShowHoverBorderCheck then
        BoxxyAuras.Options.ShowHoverBorderCheck:SetChecked(currentSettings.showHoverBorder)
    end
    if BoxxyAuras.Options.EnableFlashOnShowCheck then
        BoxxyAuras.Options.EnableFlashOnShowCheck:SetChecked(currentSettings.enableFlashAnimationOnShow)
    end
    if BoxxyAuras.Options.EnableDotTickingCheck then
        BoxxyAuras.Options.EnableDotTickingCheck:SetChecked(currentSettings.enableDotTickingAnimation)
    end
    if BoxxyAuras.Options.ShowInfiniteDurationCheck then
        BoxxyAuras.Options.ShowInfiniteDurationCheck:SetChecked(currentSettings.showInfiniteDuration)
    end

    -- Update scale sliders if they exist
    if BoxxyAuras.Options.AuraBarScaleSlider then
        BoxxyAuras.Options.AuraBarScaleSlider:SetValue(currentSettings.auraBarScale)
    end
    if BoxxyAuras.Options.OptionsWindowScaleSlider then
        BoxxyAuras.Options.OptionsWindowScaleSlider:SetValue(currentSettings.optionsWindowScale)
    end

    -- Update color swatches
    BoxxyAuras.Options:UpdateNormalBorderColorSwatch()
    BoxxyAuras.Options:UpdateBackgroundColorSwatch()
    BoxxyAuras.Options:UpdateTextColorSwatch()
    BoxxyAuras.Options:UpdateHealingAbsorbColorSwatch()
    BoxxyAuras.Options:UpdateHealingAbsorbBGColorSwatch()

    -- Update font dropdown
    if BoxxyAuras.Options.FontDropdown then
        UIDropDownMenu_SetText(BoxxyAuras.Options.FontDropdown, currentSettings.textFont)
    end

    -- Apply the changes
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.ApplyLockState then
        BoxxyAuras.FrameHandler.ApplyLockState(currentSettings.lockFrames)
    end
    if BoxxyAuras.ApplyBlizzardAuraVisibility then
        BoxxyAuras.ApplyBlizzardAuraVisibility(currentSettings.hideBlizzardAuras)
    end
    BoxxyAuras.Options:ApplyNormalBorderColorChange()
    BoxxyAuras.Options:ApplyBackgroundColorChange()
    BoxxyAuras.Options:ApplyTextColorChange()
    BoxxyAuras.Options:ApplyHealingAbsorbColorChange()
    BoxxyAuras.Options:ApplyFontChange()
    -- Ensure aura bar scale is applied to all bars visually
    BoxxyAuras.Options:ApplyAuraBarScale(currentSettings.auraBarScale)
    BoxxyAuras.Options:ApplyOptionsWindowScale(currentSettings.optionsWindowScale)

    -- Force an aura update to refresh all duration displays (for showInfiniteDuration)
    if BoxxyAuras and BoxxyAuras.UpdateAuras then
        BoxxyAuras.UpdateAuras(false)
    end

    print("|cff4CAF50BoxxyAuras:|r General settings reset to defaults.")
end

function BoxxyAuras.Options:ResetBuffSettings()
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end

    local defaults = BoxxyAuras:GetDefaultProfileSettings()

    -- Reset buff frame settings to defaults
    if not currentSettings.buffFrameSettings then
        currentSettings.buffFrameSettings = {}
    end

    currentSettings.buffFrameSettings.buffTextAlign = defaults.buffFrameSettings.buffTextAlign
    currentSettings.buffFrameSettings.iconSize = defaults.buffFrameSettings.iconSize
    currentSettings.buffFrameSettings.textSize = defaults.buffFrameSettings.textSize
    currentSettings.buffFrameSettings.borderSize = defaults.buffFrameSettings.borderSize
    currentSettings.buffFrameSettings.iconSpacing = defaults.buffFrameSettings.iconSpacing or 0
    currentSettings.buffFrameSettings.wrapDirection = defaults.buffFrameSettings.wrapDirection or "DOWN"

    -- Update UI elements for buff settings
    if BoxxyAuras.Options.BuffAlignCheckboxes then
        for i, checkbox in ipairs(BoxxyAuras.Options.BuffAlignCheckboxes) do
            local alignValues = { "LEFT", "CENTER", "RIGHT" }
            checkbox:SetChecked(alignValues[i] == currentSettings.buffFrameSettings.buffTextAlign)
        end
    end

    if BoxxyAuras.Options.BuffWrapCheckboxes then
        for i, checkbox in ipairs(BoxxyAuras.Options.BuffWrapCheckboxes) do
            local wrapValues = { "DOWN", "UP" }
            checkbox:SetChecked(wrapValues[i] == currentSettings.buffFrameSettings.wrapDirection)
        end
    end

    if BoxxyAuras.Options.BuffSizeSlider then
        BoxxyAuras.Options.BuffSizeSlider:SetValue(currentSettings.buffFrameSettings.iconSize)
    end
    if BoxxyAuras.Options.BuffTextSizeSlider then
        BoxxyAuras.Options.BuffTextSizeSlider:SetValue(currentSettings.buffFrameSettings.textSize)
    end
    if BoxxyAuras.Options.BuffBorderSizeSlider then
        BoxxyAuras.Options.BuffBorderSizeSlider:SetValue(currentSettings.buffFrameSettings.borderSize)
    end
    if BoxxyAuras.Options.BuffSpacingSlider then
        BoxxyAuras.Options.BuffSpacingSlider:SetValue(currentSettings.buffFrameSettings.iconSpacing)
    end

    -- Apply the changes
    BoxxyAuras.Options:ApplyTextAlign("Buff")
    BoxxyAuras.Options:ApplyWrapDirection("Buff")
    BoxxyAuras.Options:ApplyIconSizeChange("Buff")
    BoxxyAuras.Options:ApplyTextSizeChange("Buff")
    BoxxyAuras.Options:ApplyBorderSizeChange("Buff")
    BoxxyAuras.Options:ApplyIconSpacingChange("Buff")

    print("|cff4CAF50BoxxyAuras:|r Buff settings reset to defaults.")
end

function BoxxyAuras.Options:ResetDebuffSettings()
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end

    local defaults = BoxxyAuras:GetDefaultProfileSettings()

    -- Reset debuff frame settings to defaults
    if not currentSettings.debuffFrameSettings then
        currentSettings.debuffFrameSettings = {}
    end

    currentSettings.debuffFrameSettings.debuffTextAlign = defaults.debuffFrameSettings.debuffTextAlign
    currentSettings.debuffFrameSettings.iconSize = defaults.debuffFrameSettings.iconSize
    currentSettings.debuffFrameSettings.textSize = defaults.debuffFrameSettings.textSize
    currentSettings.debuffFrameSettings.borderSize = defaults.debuffFrameSettings.borderSize
    currentSettings.debuffFrameSettings.iconSpacing = defaults.debuffFrameSettings.iconSpacing or 0
    currentSettings.debuffFrameSettings.wrapDirection = defaults.debuffFrameSettings.wrapDirection or "DOWN"

    -- Update UI elements for debuff settings
    if BoxxyAuras.Options.DebuffAlignCheckboxes then
        for i, checkbox in ipairs(BoxxyAuras.Options.DebuffAlignCheckboxes) do
            local alignValues = { "LEFT", "CENTER", "RIGHT" }
            checkbox:SetChecked(alignValues[i] == currentSettings.debuffFrameSettings.debuffTextAlign)
        end
    end

    if BoxxyAuras.Options.DebuffWrapCheckboxes then
        for i, checkbox in ipairs(BoxxyAuras.Options.DebuffWrapCheckboxes) do
            local wrapValues = { "DOWN", "UP" }
            checkbox:SetChecked(wrapValues[i] == currentSettings.debuffFrameSettings.wrapDirection)
        end
    end

    if BoxxyAuras.Options.DebuffSizeSlider then
        BoxxyAuras.Options.DebuffSizeSlider:SetValue(currentSettings.debuffFrameSettings.iconSize)
    end
    if BoxxyAuras.Options.DebuffTextSizeSlider then
        BoxxyAuras.Options.DebuffTextSizeSlider:SetValue(currentSettings.debuffFrameSettings.textSize)
    end
    if BoxxyAuras.Options.DebuffBorderSizeSlider then
        BoxxyAuras.Options.DebuffBorderSizeSlider:SetValue(currentSettings.debuffFrameSettings.borderSize)
    end
    if BoxxyAuras.Options.DebuffSpacingSlider then
        BoxxyAuras.Options.DebuffSpacingSlider:SetValue(currentSettings.debuffFrameSettings.iconSpacing)
    end

    -- Apply the changes
    BoxxyAuras.Options:ApplyTextAlign("Debuff")
    BoxxyAuras.Options:ApplyWrapDirection("Debuff")
    BoxxyAuras.Options:ApplyIconSizeChange("Debuff")
    BoxxyAuras.Options:ApplyTextSizeChange("Debuff")
    BoxxyAuras.Options:ApplyBorderSizeChange("Debuff")
    BoxxyAuras.Options:ApplyIconSpacingChange("Debuff")

    print("|cff4CAF50BoxxyAuras:|r Debuff settings reset to defaults.")
end

-- Apply global scale changes
function BoxxyAuras.Options:ApplyAuraBarScale(scale)
    if BoxxyAuras.DEBUG then
        local stack = debugstack(2, 1, 0) -- Get calling function
        print(string.format("ApplyAuraBarScale called with scale: %.2f from: %s", scale or -1, stack:match("([^\n]+)")))
    end

    -- Validate scale value - must be greater than 0
    if not scale or scale <= 0 then
        if BoxxyAuras.DEBUG then
            print("|cffFF0000BoxxyAuras Error:|r Invalid scale value: " ..
            tostring(scale) .. ". Using default scale of 1.0")
        end
        scale = 1.0
    end

    local settings = GetCurrentProfileSettings()
    if settings then
        -- Always set the scale and forcibly apply it to all frames
        settings.auraBarScale = scale

        if BoxxyAuras.DEBUG then
            print(string.format("Applying aura bar scale %.2f to %d frames (forced)", scale,
                (BoxxyAuras.Frames and #BoxxyAuras.Frames or 0)))
        end

        -- Apply the scale to all existing frames
        if BoxxyAuras.Frames then
            for frameType, frame in pairs(BoxxyAuras.Frames) do
                if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.SetFrameScale then
                    BoxxyAuras.FrameHandler.SetFrameScale(frame, scale)
                end
            end
        end
    end
end

function BoxxyAuras.Options:ApplyOptionsWindowScale(scale)
    -- Validate scale value - must be greater than 0
    if not scale or scale <= 0 then
        if BoxxyAuras.DEBUG then
            print("|cffFF0000BoxxyAuras Error:|r Invalid scale value: " ..
                tostring(scale) .. ". Using default scale of 1.0")
        end
        scale = 1.0
    end

    local settings = GetCurrentProfileSettings()
    if settings then
        settings.optionsWindowScale = scale

        -- Apply to the options frame itself
        if self.Frame then
            self.Frame:SetScale(scale)
        end

        -- Apply to the custom options frame if it exists
        if BoxxyAuras.CustomOptions and BoxxyAuras.CustomOptions.Frame then
            BoxxyAuras.CustomOptions.Frame:SetScale(scale)
        end
    end
end

--[[------------------------------------------------------------
-- Create Main Options Frame
--------------------------------------------------------------]]
local optionsFrame = CreateFrame("Frame", "BoxxyAurasOptionsFrame", UIParent, "BackdropTemplate")
PixelUtilCompat.SetSize(optionsFrame, 650, 600) -- << CHANGED: Increased width from 300 to 650, height from 500 to 600
PixelUtilCompat.SetPoint(optionsFrame, "CENTER", UIParent, "CENTER", 0, 0)
optionsFrame:SetFrameStrata("HIGH")             -- Changed from MEDIUM to HIGH to appear above aura bars
optionsFrame:SetClampedToScreen(true)
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
optionsFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    -- Snap position to whole pixel coordinates for crisp rendering
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    if point and relativeTo and relativePoint and xOfs and yOfs then
        local snappedX = math.floor(xOfs + 0.5)
        local snappedY = math.floor(yOfs + 0.5)

        if xOfs ~= snappedX or yOfs ~= snappedY then
            self:ClearAllPoints()
            PixelUtilCompat.SetPoint(self, point, relativeTo, relativePoint, snappedX, snappedY)

            if BoxxyAuras.DEBUG then
                print(string.format("Options window snapped from (%.2f, %.2f) to (%d, %d)",
                    xOfs, yOfs, snappedX, snappedY))
            end
        end
    end
end)
optionsFrame:Hide() -- Start hidden

-- <<< NEW: OnShow script for reliable initialization >>>
optionsFrame:SetScript("OnShow", function(self)
    -- Initialize profile dropdown when the main frame is shown
    if BoxxyAuras.Options.InitializeProfileDropdown then
        BoxxyAuras.Options:InitializeProfileDropdown()
    end
    -- Initialize font dropdown when the main frame is shown
    if BoxxyAuras.Options.InitializeFontDropdown then
        BoxxyAuras.Options:InitializeFontDropdown()
    end
    -- Update UI elements based on the loaded state (Load is called by Toggle before Show)
    if BoxxyAuras.Options.UpdateProfileUI then
        BoxxyAuras.Options:UpdateProfileUI()
    end

    -- NEW: Refresh dynamic layouts after the frame is fully shown and rendered
    C_Timer.After(0.1, function()
        if BoxxyAuras.Options.RefreshIgnoredAurasLayout then
            BoxxyAuras.Options:RefreshIgnoredAurasLayout()
        end
    end)
end)

BoxxyAuras.Options.Frame = optionsFrame

-- >> ADDED: Create and Style Separate Background and Border Frames <<
local bg = CreateFrame("Frame", nil, optionsFrame);
PixelUtilCompat.SetAllPoints(bg, optionsFrame);
bg:SetFrameLevel(optionsFrame:GetFrameLevel());
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(bg, "OptionsWindowBG", "backdrop", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(bg, "backdrop", 1, 1, 1, 0.95)
else
    -- print("|cffFF0000BoxxyAuras Options Error:|r Could not draw background.")
end

local border = CreateFrame("Frame", nil, optionsFrame);
PixelUtilCompat.SetAllPoints(border, optionsFrame);
border:SetFrameLevel(optionsFrame:GetFrameLevel() + 1);
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(border, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(border, "border", 0.4, 0.4, 0.4, 1)
else
    -- print("|cffFF0000BoxxyAuras Options Error:|r Could not draw border.")
end

-- Title
local title = optionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Title")
PixelUtilCompat.SetPoint(title, "TOPLEFT", optionsFrame, "TOPLEFT", 20, -23)
title:SetText("BoxxyAuras Options")

-- <<< ADDED: Version Text >>>
local versionText = optionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Vers") -- Use a smaller font
PixelUtilCompat.SetPoint(versionText, "TOPLEFT", title, "BOTTOMLEFT", 0, -2)         -- Position below title
local versionString = "v" .. (BoxxyAuras and BoxxyAuras.Version or "?.?.?")          -- Get version safely
versionText:SetText(versionString)
versionText:SetTextColor(0.7, 0.7, 0.7, 0.9)                                         -- Slightly greyed out
BoxxyAuras.Options.VersionText = versionText                                         -- Store reference if needed
-- <<< END Version Text >>>

-- Close Button
local closeBtn = CreateFrame("Button", "BoxxyAurasOptionsCloseButton", optionsFrame, "BAURASCloseBtn")
PixelUtilCompat.SetPoint(closeBtn, "TOPRIGHT", optionsFrame, "TOPRIGHT", -12, -12)
PixelUtilCompat.SetSize(closeBtn, 12, 12)
closeBtn:SetScript("OnClick", function(self)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

    -- Turn off demo mode when closing options
    if BoxxyAuras.Options.demoModeActive then
        BoxxyAuras.Options:SetDemoMode(false)
        if BoxxyAuras.Options.DemoModeCheck then
            BoxxyAuras.Options.DemoModeCheck:SetChecked(false)
        end
    end

    -- Cancel any pending save timers
    if BoxxyAuras.Options.CustomBars and BoxxyAuras.Options.CustomBars.saveTimers then
        for barId, timer in pairs(BoxxyAuras.Options.CustomBars.saveTimers) do
            if timer then
                timer:Cancel()
            end
        end
    end

    -- Cancel ignored auras save timer
    if BoxxyAuras.Options.ignoredAurasSaveTimer then
        BoxxyAuras.Options.ignoredAurasSaveTimer:Cancel()
        BoxxyAuras.Options.ignoredAurasSaveTimer = nil
    end

    self:GetParent():Hide() -- Hide the main options frame

    -- <<< ADDED: Also hide custom options if shown >>>
    if BoxxyAuras.CustomOptions and BoxxyAuras.CustomOptions.Frame and BoxxyAuras.CustomOptions.Frame:IsShown() then
        BoxxyAuras.CustomOptions.Frame:Hide()
    end
    -- <<< END ADDED SECTION >>>
end)

-- Info Button (positioned to the left of the close button)
local infoBtn = CreateFrame("Button", "BoxxyAurasOptionsInfoButton", optionsFrame, "BAURASInfoBtn")
PixelUtilCompat.SetPoint(infoBtn, "TOPRIGHT", closeBtn, "TOPLEFT", -6, 0) -- 6px spacing from close button
PixelUtilCompat.SetSize(infoBtn, 12, 12)

-- Create custom tooltip frame for info button
local customTooltip = CreateFrame("Frame", "BoxxyAurasInfoTooltip", UIParent, "BackdropTemplate")
customTooltip:SetFrameStrata("TOOLTIP")
customTooltip:SetFrameLevel(1000) -- Ensure it's on top
customTooltip:Hide()

-- Draw custom background and border using our textures
BoxxyAuras.UIUtils.DrawSlicedBG(customTooltip, "OptionsWindowBG", "backdrop", 0)
BoxxyAuras.UIUtils.ColorBGSlicedFrame(customTooltip, "backdrop", 1, 1, 1, 1) -- Dark background
BoxxyAuras.UIUtils.DrawSlicedBG(customTooltip, "EdgedBorder", "border", 0)
BoxxyAuras.UIUtils.ColorBGSlicedFrame(customTooltip, "border", 0.5, 0.5, 0.5, 1)

-- Create tooltip content
local tooltipText = customTooltip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tooltipText:SetPoint("TOPLEFT", customTooltip, "TOPLEFT", 20, -20)         -- Increased padding from 12 to 20
tooltipText:SetPoint("BOTTOMRIGHT", customTooltip, "BOTTOMRIGHT", -20, 20) -- Increased padding from 12 to 20
tooltipText:SetJustifyH("LEFT")
tooltipText:SetJustifyV("TOP")
tooltipText:SetTextColor(1, 1, 1, 1) -- White text

-- Set the tooltip content
local tooltipContent = "|cffFFD100BoxxyAuras Controls|r\n\n" ..
    "|cffCCCCFFGeneral Info:|r\n" ..
    "• Auras will wrap when overflowing the frame\n" ..
    "• Expired auras persist when hovering over frames\n\n" ..
    "|cffCCCCFFMoving Aura Bars:|r\n" ..
    "• Left-click and drag to move\n" ..
    "• Arrow keys to nudge frames when hovered\n\n" ..
    "|cffCCCCFFResizing Aura Bars:|r\n" ..
    "• Hover over left or right edges\n" ..
    "• Click and drag to resize\n\n" ..
    "|cffCCCCFFQuick Access:|r\n" ..
    "• Right-click aura bars to open options"


tooltipText:SetText(tooltipContent)

-- Function to show custom tooltip
local function ShowCustomTooltip(anchor)
    -- Size the tooltip based on text content with increased padding
    local textWidth = tooltipText:GetStringWidth()
    local textHeight = tooltipText:GetStringHeight()
    customTooltip:SetSize(textWidth + 40, textHeight + 40) -- Increased padding from 24 to 40

    -- Position tooltip to the left of the info button
    customTooltip:ClearAllPoints()
    customTooltip:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
    customTooltip:Show()
end

-- Function to hide custom tooltip
local function HideCustomTooltip()
    customTooltip:Hide()
end

infoBtn:SetScript("OnEnter", function(self)
    -- Call the template's OnEnter first for visual effects
    if self.Btn then
        self.Btn:SetVertexColor(1, 1, 1, 1)
    end

    -- Show our custom tooltip
    ShowCustomTooltip(self)
end)

infoBtn:SetScript("OnLeave", function(self)
    -- Call the template's OnLeave for visual effects
    if self.Btn then
        self.Btn:SetVertexColor(0.8, 0.8, 0.8, 1)
    end

    -- Hide our custom tooltip
    HideCustomTooltip()
end)

BoxxyAuras.Options.InfoButton = infoBtn

--[[------------------------------------------------------------
-- Helper Function for Group Styling
--------------------------------------------------------------]]
local function StyleGroupContainer(frame, backgroundKey, borderKey)
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
        -- Background (subtly darker than main options)
        BoxxyAuras.UIUtils.DrawSlicedBG(frame, backgroundKey or "OptionsWindowBG", "backdrop", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", 0.05, 0.05, 0.05, 0.6) -- Darker, semi-transparent
        -- Border
        BoxxyAuras.UIUtils.DrawSlicedBG(frame, borderKey or "EdgedBorder", "border", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", 0.2, 0.2, 0.2, 0.8) -- Subtle border
    else
        -- print(string.format("|cffFF0000BoxxyAuras Options Error:|r Could not style group container %s.", frame:GetName()))
    end
end

--[[------------------------------------------------------------
-- Scroll Frame & Content
--------------------------------------------------------------]]
local scrollFrame = CreateFrame("ScrollFrame", "BoxxyAurasOptionsScrollFrame", optionsFrame,
    "UIPanelScrollFrameTemplate")
PixelUtilCompat.SetPoint(scrollFrame, "TOPLEFT", optionsFrame, "TOPLEFT", 10, -50)
PixelUtilCompat.SetPoint(scrollFrame, "BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -40, 10)

-- <<< ADDED: Adjust Mouse Wheel Scroll Speed >>>
local SCROLL_STEP_REDUCTION_FACTOR = 0.9 -- Adjust this value (e.g., 0.5 for half speed)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local scrollBar = _G[self:GetName() .. "ScrollBar"];
    local currentStep = SCROLL_FRAME_SCROLL_STEP or
        16                                                                              -- Use default Blizzard step or fallback
    local newStep = math.max(1, math.floor(currentStep * SCROLL_STEP_REDUCTION_FACTOR)) -- Reduce step, ensure at least 1

    if (delta > 0) then
        scrollBar:SetValue(scrollBar:GetValue() - newStep);
    else
        scrollBar:SetValue(scrollBar:GetValue() + newStep);
    end
end);
-- <<< END Scroll Speed Adjustment >>>

local contentFrame = CreateFrame("Frame", "BoxxyAurasOptionsContentFrame", scrollFrame)
PixelUtilCompat.SetSize(contentFrame, scrollFrame:GetWidth(), 900) -- <<< CHANGED: Increased height from 700 to 900 for additional sections >>>
scrollFrame:SetScrollChild(contentFrame)

-- Layout Variables (for container positioning)
local lastContainer = nil -- Will track the last created container for positioning

--[[------------------------------------------------------------
-- Profile Management Container (Two Column Layout)
--------------------------------------------------------------]]
local profileContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Profile Management")

-- <<< NEW: Function to manually update height for columnar layout >>>
function profileContainer:UpdateHeightFromColumns()
    local leftColHeight = self.LeftColumn:GetFrame():GetHeight()
    local rightColHeight = self.RightColumn:GetFrame():GetHeight()
    local maxHeight = math.max(leftColHeight, rightColHeight)

    -- Set the main container's height.
    -- This includes the title height (approx. 30), column height, and bottom padding (12).
    local totalHeight = 30 + maxHeight + 12
    PixelUtilCompat.SetHeight(self:GetFrame(), totalHeight)
end

--[[------------------------
-- Left Column: Current Profile
--------------------------]]
local currentProfileContainer = BoxxyAuras.UIBuilder.CreateContainer(profileContainer:GetFrame(), "Current Profile")
currentProfileContainer:SetParentContainer(profileContainer) -- Set parent relationship
profileContainer.LeftColumn = currentProfileContainer        -- Store reference for height calculation

currentProfileContainer:SetPosition("TOPLEFT", profileContainer:GetFrame(), "TOPLEFT", 12, -30)
-- Resize to half width for side-by-side layout
local currentProfileFrame = currentProfileContainer:GetFrame()
local parentWidth = profileContainer:GetFrame():GetWidth()
local innerWidth = parentWidth - 24       -- Account for 12px padding on each side of the parent
local columnWidth = (innerWidth - 10) / 2 -- Account for 10px spacing between columns
PixelUtilCompat.SetWidth(currentProfileFrame, columnWidth)

-- Profile Selection Dropdown (manual creation for complex styling)
local profileDropdown = CreateFrame("Frame", "BoxxyAurasProfileDropdown", currentProfileContainer:GetFrame(),
    "UIDropDownMenuTemplate")
PixelUtilCompat.SetWidth(profileDropdown, currentProfileContainer:GetFrame():GetWidth() - 24) -- Full width of left column minus padding
currentProfileContainer:AddElement(profileDropdown, 30)

-- >> ADDED: Hide default button textures to allow custom styling <<
local dropdownButton = _G[profileDropdown:GetName() .. "Button"]
if dropdownButton then
    dropdownButton:Hide()
end

-- Hide the background textures
local dropdownLeft = _G[profileDropdown:GetName() .. "Left"]
local dropdownMiddle = _G[profileDropdown:GetName() .. "Middle"]
local dropdownRight = _G[profileDropdown:GetName() .. "Right"]

if dropdownLeft then dropdownLeft:Hide() end
if dropdownMiddle then dropdownMiddle:Hide() end
if dropdownRight then dropdownRight:Hide() end

-- Center Dropdown Text
local dropdownText = _G[profileDropdown:GetName() .. "Text"]
if dropdownText then
    dropdownText:SetJustifyH("CENTER")
    dropdownText:ClearAllPoints()
    PixelUtilCompat.SetPoint(dropdownText, "CENTER", profileDropdown, "CENTER", 0, 0)
end

-- Styling for Dropdown
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
    BoxxyAuras.UIUtils.DrawSlicedBG(profileDropdown, "BtnBG", "backdrop", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(profileDropdown, "backdrop", 0.1, 0.1, 0.1, 0.85)
    BoxxyAuras.UIUtils.DrawSlicedBG(profileDropdown, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(profileDropdown, "border", 0.4, 0.4, 0.4, 0.9)
end

-- Dropdown Arrow Texture
local arrow = profileDropdown:CreateTexture(nil, "OVERLAY")
PixelUtilCompat.SetSize(arrow, 16, 16)
PixelUtilCompat.SetPoint(arrow, "RIGHT", profileDropdown, "RIGHT", -8, 0)
arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown")
arrow:SetTexCoord(0, 1, 0, 1)

-- Dropdown Hover Effect
profileDropdown:SetScript("OnEnter", function(self)
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.8, 0.8, 0.8, 1.0)
    end
end)
profileDropdown:SetScript("OnLeave", function(self)
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.4, 0.4, 0.4, 0.9)
    end
end)

-- Click handler
profileDropdown:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        ToggleDropDownMenu(1, nil, self)
    end
end)

BoxxyAuras.Options.ProfileDropdown = profileDropdown

--[[--------------------------
-- Right Column: Profile Actions
----------------------------]]
local profileActionsContainer = BoxxyAuras.UIBuilder.CreateContainer(profileContainer:GetFrame(), "Profile Actions")
profileActionsContainer:SetParentContainer(profileContainer) -- Set parent relationship
profileContainer.RightColumn = profileActionsContainer       -- Store reference for height calculation

-- Position to the right of the current profile container at the same vertical level
profileActionsContainer:SetPosition("TOPLEFT", currentProfileContainer:GetFrame(), "TOPRIGHT", 10, 0)

-- Resize to half width for side-by-side layout
local profileActionsFrame = profileActionsContainer:GetFrame()
PixelUtilCompat.SetWidth(profileActionsFrame, columnWidth)

-- Calculate button row dimensions for edit box alignment
local buttonRowConfig = {
    { name = "BoxxyAurasCreateProfileButton", text = "New",    width = 60 },
    { name = "BoxxyAurasCopyProfileButton",   text = "Copy",   width = 60 },
    { name = "BoxxyAurasDeleteProfileButton", text = "Delete", width = 60 }
}
local buttonDimensions = profileActionsContainer:CalculateButtonRowDimensions(buttonRowConfig)

-- Profile Name EditBox (aligned with button row)
local editBoxOffset = buttonDimensions.startX + 6 -- Small adjustment to account for edit box visual padding
local profileNameEditBox = profileActionsContainer:AddEditBox("", 32, function(self)
    local name = self:GetText()
    if name and name ~= "" then
        self:SetText("")
        self:ClearFocus()
    end
end, nil, buttonDimensions.totalWidth - 6, editBoxOffset)
BoxxyAuras.Options.ProfileNameEditBox = profileNameEditBox

-- Profile Action Buttons (centered row)
local profileButtons = profileActionsContainer:AddButtonRow({
    {
        name = "BoxxyAurasCreateProfileButton",
        text = "New",
        width = 60,
        onClick = function()
            local name = BoxxyAuras.Options.ProfileNameEditBox:GetText()
            if name and name ~= "" then
                BoxxyAuras.Options:CreateProfile(name)
                BoxxyAuras.Options.ProfileNameEditBox:SetText("")
            end
            PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
        end
    },
    {
        name = "BoxxyAurasCopyProfileButton",
        text = "Copy",
        width = 60,
        onClick = function()
            local name = BoxxyAuras.Options.ProfileNameEditBox:GetText()
            if name and name ~= "" then
                BoxxyAuras.Options:CopyProfile(name)
                BoxxyAuras.Options.ProfileNameEditBox:SetText("")
            end
            PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
        end
    },
    {
        name = "BoxxyAurasDeleteProfileButton",
        text = "Delete",
        width = 60,
        onClick = function(self)
            if not self:IsEnabled() then
                return
            end
            local selectedProfile = BoxxyAurasDB and BoxxyAurasDB.activeProfile
            if selectedProfile then
                -- Pass profile name both for the text substitution (arg1) *and* as the data param so the OnAccept handler receives it
                StaticPopup_Show("BOXXYAURAS_DELETE_PROFILE_CONFIRM", selectedProfile, nil, selectedProfile)
            end
            PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
        end
    }
})

-- Store references to the buttons for later use
BoxxyAuras.Options.CreateProfileButton = profileButtons[1]
BoxxyAuras.Options.CopyProfileButton = profileButtons[2]
BoxxyAuras.Options.DeleteProfileButton = profileButtons[3]

-- <<< NEW: Match the height of the left column to the taller right column >>>
local leftColumnFrame = currentProfileContainer:GetFrame()
local rightColumnFrame = profileActionsContainer:GetFrame()
PixelUtilCompat.SetHeight(leftColumnFrame, rightColumnFrame:GetHeight())

-- <<< NEW: Manually trigger height update for the main container >>>
profileContainer:UpdateHeightFromColumns()

-- Store reference to the container for positioning next section
lastContainer = profileContainer

--[[------------------------------------------------------------
-- General Settings Container
--------------------------------------------------------------]]
local generalContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "General Settings")
generalContainer:SetPosition("TOPLEFT", lastContainer:GetFrame(), "BOTTOMLEFT", 0, -15)

-- Lock Frames Checkbox
local lockFramesCheck = generalContainer:AddCheckbox("Lock Frames", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then
        return
    end

    local currentSavedState = currentSettings.lockFrames
    local newState = not currentSavedState
    currentSettings.lockFrames = newState

    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.ApplyLockState then
        BoxxyAuras.FrameHandler.ApplyLockState(newState)
    end

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.LockFramesCheck = lockFramesCheck

-- Hide Blizzard Auras Checkbox
local hideBlizzardCheck = generalContainer:AddCheckbox("Hide Blizzard Auras", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then
        return
    end

    local currentSavedState = currentSettings.hideBlizzardAuras
    local newState = not currentSavedState
    currentSettings.hideBlizzardAuras = newState

    if BoxxyAuras.ApplyBlizzardAuraVisibility then
        BoxxyAuras.ApplyBlizzardAuraVisibility(newState)
    end

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.HideBlizzardCheck = hideBlizzardCheck

-- Force a wider width on this specific checkbox to prevent text truncation
if hideBlizzardCheck and hideBlizzardCheck.Label and hideBlizzardCheck.NormalBorder then
    -- Set a large visual width for the parent button to ensure no clipping
    hideBlizzardCheck:SetWidth(300)

    -- Set a large width for the label to ensure text draws fully
    -- (280 is known to be sufficient and fits within the 300px button)
    hideBlizzardCheck.Label:SetWidth(280)

    -- Now, calculate the *actual* width of the content to create a precise hitbox
    local textWidth = hideBlizzardCheck.Label:GetStringWidth()
    local checkboxGraphicWidth = hideBlizzardCheck.NormalBorder:GetWidth() or 12
    local padding = 4
    local contentWidth = checkboxGraphicWidth + padding + textWidth

    -- Shrink the hitbox to match the actual content
    local rightInset = hideBlizzardCheck:GetWidth() - contentWidth
    hideBlizzardCheck:SetHitRectInsets(0, rightInset, -4, -4)
end

-- Show Hover Border Checkbox
local showHoverBorderCheck = generalContainer:AddCheckbox("Show Hover Border", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then
        return
    end

    local currentState = currentSettings.showHoverBorder
    local newState = not currentState
    currentSettings.showHoverBorder = newState

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.ShowHoverBorderCheck = showHoverBorderCheck

-- Demo Mode Checkbox
local demoModeCheck = generalContainer:AddCheckbox("Demo Mode", function(self)
    local currentState = self:GetChecked()
    local newState = not currentState
    self:SetChecked(newState)

    print("Demo mode toggled to:", newState)

    if BoxxyAuras.Options and BoxxyAuras.Options.SetDemoMode then
        BoxxyAuras.Options:SetDemoMode(newState)
    else
        print("|cffFF0000BoxxyAuras Error:|r Demo mode function not found!")
    end

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.DemoModeCheck = demoModeCheck

-- Enable Flash Animation on Show Checkbox
local enableFlashOnShowCheck = generalContainer:AddCheckbox("Enable flash animation on show", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then
        return
    end

    local currentState = currentSettings.enableFlashAnimationOnShow
    if currentState == nil then
        currentState = true
    end
    local newState = not currentState
    currentSettings.enableFlashAnimationOnShow = newState

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.EnableFlashOnShowCheck = enableFlashOnShowCheck

-- Force a wider width on this specific checkbox to prevent text truncation
if enableFlashOnShowCheck and enableFlashOnShowCheck.Label and enableFlashOnShowCheck.NormalBorder then
    -- Set a large visual width for the parent button to ensure no clipping
    enableFlashOnShowCheck:SetWidth(300)

    -- Set a large width for the label to ensure text draws fully
    -- (280 is known to be sufficient and fits within the 300px button)
    enableFlashOnShowCheck.Label:SetWidth(280)

    -- Now, calculate the *actual* width of the content to create a precise hitbox
    local textWidth = enableFlashOnShowCheck.Label:GetStringWidth()
    local checkboxGraphicWidth = enableFlashOnShowCheck.NormalBorder:GetWidth() or 12
    local padding = 4
    local contentWidth = checkboxGraphicWidth + padding + textWidth

    -- Shrink the hitbox to match the actual content
    local rightInset = enableFlashOnShowCheck:GetWidth() - contentWidth
    enableFlashOnShowCheck:SetHitRectInsets(0, rightInset, -4, -4)
end

-- Enable Dot Ticking Animation Checkbox
local enableDotTickingCheck = generalContainer:AddCheckbox("Enable Dot Ticking Animation", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then
        return
    end

    local currentState = currentSettings.enableDotTickingAnimation
    local newState = not currentState
    currentSettings.enableDotTickingAnimation = newState

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.EnableDotTickingCheck = enableDotTickingCheck

-- Force a wider width on this specific checkbox to prevent text truncation
if enableDotTickingCheck and enableDotTickingCheck.Label and enableDotTickingCheck.NormalBorder then
    -- Set a large visual width for the parent button to ensure no clipping
    enableDotTickingCheck:SetWidth(300)

    -- Set a large width for the label to ensure text draws fully
    -- (280 is known to be sufficient and fits within the 300px button)
    enableDotTickingCheck.Label:SetWidth(280)

    -- Now, calculate the *actual* width of the content to create a precise hitbox
    local textWidth = enableDotTickingCheck.Label:GetStringWidth()
    local checkboxGraphicWidth = enableDotTickingCheck.NormalBorder:GetWidth() or 12
    local padding = 4
    local contentWidth = checkboxGraphicWidth + padding + textWidth

    -- Shrink the hitbox to match the actual content
    local rightInset = enableDotTickingCheck:GetWidth() - contentWidth
    enableDotTickingCheck:SetHitRectInsets(0, rightInset, -4, -4)
end

-- Show Infinite Duration Symbol Checkbox
local showInfiniteDurationCheck = generalContainer:AddCheckbox("Show ∞ for infinite duration auras", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then
        print("|cffFF0000BoxxyAuras Error:|r Failed to access profile settings.")
        return
    end

    local currentSavedState = currentSettings.showInfiniteDuration
    local newState = not currentSavedState
    currentSettings.showInfiniteDuration = newState

    -- Force an aura update to refresh all duration displays
    if BoxxyAuras and BoxxyAuras.UpdateAuras then
        BoxxyAuras.UpdateAuras(false)
    end

    self:SetChecked(newState)

    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Show Infinite Duration Symbol %s", newState and "enabled" or "disabled"))
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.ShowInfiniteDurationCheck = showInfiniteDurationCheck

-- Force proper width for the infinite duration checkbox
if showInfiniteDurationCheck and showInfiniteDurationCheck.Label and showInfiniteDurationCheck.NormalBorder then
    -- Set a large visual width for the parent button to ensure no clipping
    showInfiniteDurationCheck:SetWidth(300)

    -- Set a large width for the label to ensure text draws fully
    showInfiniteDurationCheck.Label:SetWidth(280)

    -- Calculate the actual width of the content to create a precise hitbox
    local textWidth = showInfiniteDurationCheck.Label:GetStringWidth()
    local checkboxGraphicWidth = showInfiniteDurationCheck.NormalBorder:GetWidth() or 12
    local padding = 4
    local contentWidth = checkboxGraphicWidth + padding + textWidth

    -- Shrink the hitbox to match the actual content
    local rightInset = showInfiniteDurationCheck:GetWidth() - contentWidth
    showInfiniteDurationCheck:SetHitRectInsets(0, rightInset, -4, -4)
end

-- Normal Border Color Picker
local colorPickerContainer = CreateFrame("Frame", nil, generalContainer:GetFrame())
PixelUtilCompat.SetSize(colorPickerContainer, generalContainer:GetFrame():GetWidth() - 24, 20)

local colorLabel = colorPickerContainer:CreateFontString(nil, "ARTWORK", "BAURASFont_Checkbox")
PixelUtilCompat.SetPoint(colorLabel, "LEFT", colorPickerContainer, "LEFT", 0, 0)
colorLabel:SetText("Normal Border Color:")

local colorSwatch = CreateFrame("Button", "BoxxyAurasNormalBorderColorSwatch", colorPickerContainer)
-- NEW: give the swatch a fixed size and create its background texture so it's always available
PixelUtilCompat.SetSize(colorSwatch, 16, 16)                             -- smaller, reasonable clickable size
PixelUtilCompat.SetPoint(colorSwatch, "LEFT", colorLabel, "RIGHT", 8, 0) -- place it next to the label

-- Create the color background first
local swatchBg = colorSwatch:CreateTexture(nil, "BACKGROUND")
PixelUtilCompat.SetAllPoints(swatchBg, colorSwatch)
-- Initialize with default border color instead of white
-- Initialize with default border color from centralized defaults
local defaultColor = BoxxyAuras:GetDefaultProfileSettings().normalBorderColor
swatchBg:SetColorTexture(defaultColor.r, defaultColor.g, defaultColor.b, defaultColor.a)
colorSwatch.background = swatchBg -- store for later access by loader / color picker

-- Create a simple clean border outline
local borderColor = { 0.6, 0.6, 0.6, 1 }
local borderThickness = 1

-- Top border
local borderTop = colorSwatch:CreateTexture(nil, "BORDER")
borderTop:SetColorTexture(unpack(borderColor))
PixelUtilCompat.SetPoint(borderTop, "TOPLEFT", colorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(borderTop, "TOPRIGHT", colorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetHeight(borderTop, borderThickness)

-- Bottom border
local borderBottom = colorSwatch:CreateTexture(nil, "BORDER")
borderBottom:SetColorTexture(unpack(borderColor))
PixelUtilCompat.SetPoint(borderBottom, "BOTTOMLEFT", colorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetPoint(borderBottom, "BOTTOMRIGHT", colorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetHeight(borderBottom, borderThickness)

-- Left border
local borderLeft = colorSwatch:CreateTexture(nil, "BORDER")
borderLeft:SetColorTexture(unpack(borderColor))
PixelUtilCompat.SetPoint(borderLeft, "TOPLEFT", colorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(borderLeft, "BOTTOMLEFT", colorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetWidth(borderLeft, borderThickness)

-- Right border
local borderRight = colorSwatch:CreateTexture(nil, "BORDER")
borderRight:SetColorTexture(unpack(borderColor))
PixelUtilCompat.SetPoint(borderRight, "TOPRIGHT", colorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetPoint(borderRight, "BOTTOMRIGHT", colorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetWidth(borderRight, borderThickness)

generalContainer:AddElement(colorPickerContainer, 26) -- height 20 + 6px padding

colorSwatch:SetScript("OnMouseUp", function(self)
    -- Show the color picker
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local currentColor = (currentSettings and currentSettings.normalBorderColor) or
        BoxxyAuras:GetDefaultProfileSettings().normalBorderColor

    local options = {
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = ColorPickerFrame:GetColorAlpha()
            if not currentSettings.normalBorderColor then
                currentSettings.normalBorderColor = {}
            end
            currentSettings.normalBorderColor.r = newR
            currentSettings.normalBorderColor.g = newG
            currentSettings.normalBorderColor.b = newB
            currentSettings.normalBorderColor.a = newA
            -- Update the swatch immediately
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateNormalBorderColorSwatch then
                BoxxyAuras.Options:UpdateNormalBorderColorSwatch()
            end
            -- Apply to all aura borders
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyNormalBorderColorChange then
                BoxxyAuras.Options:ApplyNormalBorderColorChange()
            end
        end,
        cancelFunc = function(previousValues)
            if not currentSettings.normalBorderColor then
                currentSettings.normalBorderColor = {}
            end
            currentSettings.normalBorderColor.r = previousValues.r
            currentSettings.normalBorderColor.g = previousValues.g
            currentSettings.normalBorderColor.b = previousValues.b
            currentSettings.normalBorderColor.a = previousValues.a
            -- Update the swatch to show canceled color
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateNormalBorderColorSwatch then
                BoxxyAuras.Options:UpdateNormalBorderColorSwatch()
            end
            -- Apply to all aura borders
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyNormalBorderColorChange then
                BoxxyAuras.Options:ApplyNormalBorderColorChange()
            end
        end,
        hasOpacity = true,
        opacity = currentColor.a,
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
        -- Pass the swatch itself so the color picker can update it live
        swatchBg = self.background
    }
    ColorPickerFrame:SetupColorPickerAndShow(options)
end)

BoxxyAuras.Options.NormalBorderColorSwatch = colorSwatch

-- Initialize the swatch with the current color immediately
C_Timer.After(0.1, function()
    if BoxxyAuras.Options and BoxxyAuras.Options.UpdateNormalBorderColorSwatch then
        BoxxyAuras.Options:UpdateNormalBorderColorSwatch()
    end
end)

-- Background Color Picker
local bgColorPickerContainer = CreateFrame("Frame", nil, generalContainer:GetFrame())
PixelUtilCompat.SetSize(bgColorPickerContainer, generalContainer:GetFrame():GetWidth() - 24, 20)

local bgColorLabel = bgColorPickerContainer:CreateFontString(nil, "ARTWORK", "BAURASFont_Checkbox")
PixelUtilCompat.SetPoint(bgColorLabel, "LEFT", bgColorPickerContainer, "LEFT", 0, 0)
bgColorLabel:SetText("Background Color:")

local bgColorSwatch = CreateFrame("Button", "BoxxyAurasBackgroundColorSwatch", bgColorPickerContainer)
PixelUtilCompat.SetSize(bgColorSwatch, 16, 16)
PixelUtilCompat.SetPoint(bgColorSwatch, "LEFT", bgColorLabel, "RIGHT", 8, 0)

-- Create the color background
local bgSwatchBg = bgColorSwatch:CreateTexture(nil, "BACKGROUND")
PixelUtilCompat.SetAllPoints(bgSwatchBg, bgColorSwatch)
-- Initialize with default background color from centralized defaults
local defaultBgColor = BoxxyAuras:GetDefaultProfileSettings().normalBackgroundColor
bgSwatchBg:SetColorTexture(defaultBgColor.r, defaultBgColor.g, defaultBgColor.b, defaultBgColor.a)
bgColorSwatch.background = bgSwatchBg

-- Create border for background color swatch (same as border color swatch)
local bgBorderColor = { 0.6, 0.6, 0.6, 1 }
local bgBorderThickness = 1

-- Top border
local bgBorderTop = bgColorSwatch:CreateTexture(nil, "BORDER")
bgBorderTop:SetColorTexture(unpack(bgBorderColor))
PixelUtilCompat.SetPoint(bgBorderTop, "TOPLEFT", bgColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(bgBorderTop, "TOPRIGHT", bgColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetHeight(bgBorderTop, bgBorderThickness)

-- Bottom border
local bgBorderBottom = bgColorSwatch:CreateTexture(nil, "BORDER")
bgBorderBottom:SetColorTexture(unpack(bgBorderColor))
PixelUtilCompat.SetPoint(bgBorderBottom, "BOTTOMLEFT", bgColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetPoint(bgBorderBottom, "BOTTOMRIGHT", bgColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetHeight(bgBorderBottom, bgBorderThickness)

-- Left border
local bgBorderLeft = bgColorSwatch:CreateTexture(nil, "BORDER")
bgBorderLeft:SetColorTexture(unpack(bgBorderColor))
PixelUtilCompat.SetPoint(bgBorderLeft, "TOPLEFT", bgColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(bgBorderLeft, "BOTTOMLEFT", bgColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetWidth(bgBorderLeft, bgBorderThickness)

-- Right border
local bgBorderRight = bgColorSwatch:CreateTexture(nil, "BORDER")
bgBorderRight:SetColorTexture(unpack(bgBorderColor))
PixelUtilCompat.SetPoint(bgBorderRight, "TOPRIGHT", bgColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetPoint(bgBorderRight, "BOTTOMRIGHT", bgColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetWidth(bgBorderRight, bgBorderThickness)

generalContainer:AddElement(bgColorPickerContainer, 26)

bgColorSwatch:SetScript("OnMouseUp", function(self)
    -- Show the color picker for background color
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local currentColor = (currentSettings and currentSettings.normalBackgroundColor) or
        BoxxyAuras:GetDefaultProfileSettings().normalBackgroundColor

    local options = {
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = ColorPickerFrame:GetColorAlpha()
            if not currentSettings.normalBackgroundColor then
                currentSettings.normalBackgroundColor = {}
            end
            currentSettings.normalBackgroundColor.r = newR
            currentSettings.normalBackgroundColor.g = newG
            currentSettings.normalBackgroundColor.b = newB
            currentSettings.normalBackgroundColor.a = newA
            -- Update the swatch immediately
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateBackgroundColorSwatch then
                BoxxyAuras.Options:UpdateBackgroundColorSwatch()
            end
            -- Apply to all aura backgrounds
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyBackgroundColorChange then
                BoxxyAuras.Options:ApplyBackgroundColorChange()
            end
        end,
        cancelFunc = function(previousValues)
            if not currentSettings.normalBackgroundColor then
                currentSettings.normalBackgroundColor = {}
            end
            currentSettings.normalBackgroundColor.r = previousValues.r
            currentSettings.normalBackgroundColor.g = previousValues.g
            currentSettings.normalBackgroundColor.b = previousValues.b
            currentSettings.normalBackgroundColor.a = previousValues.a
            -- Update the swatch to show canceled color
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateBackgroundColorSwatch then
                BoxxyAuras.Options:UpdateBackgroundColorSwatch()
            end
            -- Apply to all aura backgrounds
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyBackgroundColorChange then
                BoxxyAuras.Options:ApplyBackgroundColorChange()
            end
        end,
        hasOpacity = true,
        opacity = currentColor.a,
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
        -- Pass the swatch itself so the color picker can update it live
        swatchBg = self.background
    }
    ColorPickerFrame:SetupColorPickerAndShow(options)
end)

BoxxyAuras.Options.BackgroundColorSwatch = bgColorSwatch

-- Initialize the background color swatch with the current color immediately
C_Timer.After(0.1, function()
    if BoxxyAuras.Options and BoxxyAuras.Options.UpdateBackgroundColorSwatch then
        BoxxyAuras.Options:UpdateBackgroundColorSwatch()
    end
end)

-- Text Color Picker
local textColorPickerContainer = CreateFrame("Frame", nil, generalContainer:GetFrame())
PixelUtilCompat.SetSize(textColorPickerContainer, generalContainer:GetFrame():GetWidth() - 24, 20)

local textColorLabel = textColorPickerContainer:CreateFontString(nil, "ARTWORK", "BAURASFont_Checkbox")
PixelUtilCompat.SetPoint(textColorLabel, "LEFT", textColorPickerContainer, "LEFT", 0, 0)
textColorLabel:SetText("Text Color:")

local textColorSwatch = CreateFrame("Button", "BoxxyAurasTextColorSwatch", textColorPickerContainer)
PixelUtilCompat.SetSize(textColorSwatch, 16, 16)
PixelUtilCompat.SetPoint(textColorSwatch, "LEFT", textColorLabel, "RIGHT", 8, 0)

-- Create the color background
local textSwatchBg = textColorSwatch:CreateTexture(nil, "BACKGROUND")
PixelUtilCompat.SetAllPoints(textSwatchBg, textColorSwatch)
-- Initialize with default text color from centralized defaults
local defaultTextColor = BoxxyAuras:GetDefaultProfileSettings().textColor
textSwatchBg:SetColorTexture(defaultTextColor.r, defaultTextColor.g, defaultTextColor.b, defaultTextColor.a)
textColorSwatch.background = textSwatchBg

-- Create border for text color swatch (same as other color swatches)
local textBorderColor = { 0.6, 0.6, 0.6, 1 }
local textBorderThickness = 1

-- Top border
local textBorderTop = textColorSwatch:CreateTexture(nil, "BORDER")
textBorderTop:SetColorTexture(unpack(textBorderColor))
PixelUtilCompat.SetPoint(textBorderTop, "TOPLEFT", textColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(textBorderTop, "TOPRIGHT", textColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetHeight(textBorderTop, textBorderThickness)

-- Bottom border
local textBorderBottom = textColorSwatch:CreateTexture(nil, "BORDER")
textBorderBottom:SetColorTexture(unpack(textBorderColor))
PixelUtilCompat.SetPoint(textBorderBottom, "BOTTOMLEFT", textColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetPoint(textBorderBottom, "BOTTOMRIGHT", textColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetHeight(textBorderBottom, textBorderThickness)

-- Left border
local textBorderLeft = textColorSwatch:CreateTexture(nil, "BORDER")
textBorderLeft:SetColorTexture(unpack(textBorderColor))
PixelUtilCompat.SetPoint(textBorderLeft, "TOPLEFT", textColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(textBorderLeft, "BOTTOMLEFT", textColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetWidth(textBorderLeft, textBorderThickness)

-- Right border
local textBorderRight = textColorSwatch:CreateTexture(nil, "BORDER")
textBorderRight:SetColorTexture(unpack(textBorderColor))
PixelUtilCompat.SetPoint(textBorderRight, "TOPRIGHT", textColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetPoint(textBorderRight, "BOTTOMRIGHT", textColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetWidth(textBorderRight, textBorderThickness)

generalContainer:AddElement(textColorPickerContainer, 26)

textColorSwatch:SetScript("OnMouseUp", function(self)
    -- Show the color picker for text color
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local currentColor = (currentSettings and currentSettings.textColor) or
        BoxxyAuras:GetDefaultProfileSettings().textColor

    local options = {
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = ColorPickerFrame:GetColorAlpha()
            if not currentSettings.textColor then
                currentSettings.textColor = {}
            end
            currentSettings.textColor.r = newR
            currentSettings.textColor.g = newG
            currentSettings.textColor.b = newB
            currentSettings.textColor.a = newA
            -- Update the swatch immediately
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateTextColorSwatch then
                BoxxyAuras.Options:UpdateTextColorSwatch()
            end
            -- Apply to all aura text
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyTextColorChange then
                BoxxyAuras.Options:ApplyTextColorChange()
            end
        end,
        cancelFunc = function(previousValues)
            if not currentSettings.textColor then
                currentSettings.textColor = {}
            end
            currentSettings.textColor.r = previousValues.r
            currentSettings.textColor.g = previousValues.g
            currentSettings.textColor.b = previousValues.b
            currentSettings.textColor.a = previousValues.a
            -- Update the swatch to show canceled color
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateTextColorSwatch then
                BoxxyAuras.Options:UpdateTextColorSwatch()
            end
            -- Apply to all aura text
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyTextColorChange then
                BoxxyAuras.Options:ApplyTextColorChange()
            end
        end,
        hasOpacity = true,
        opacity = currentColor.a,
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
        -- Pass the swatch itself so the color picker can update it live
        swatchBg = self.background
    }
    ColorPickerFrame:SetupColorPickerAndShow(options)
end)

BoxxyAuras.Options.TextColorSwatch = textColorSwatch

-- Initialize the text color swatch with the current color immediately
C_Timer.After(0.1, function()
    if BoxxyAuras.Options and BoxxyAuras.Options.UpdateTextColorSwatch then
        BoxxyAuras.Options:UpdateTextColorSwatch()
    end
end)

-- Healing Absorb Bar Color Picker
local healingAbsorbColorPickerContainer = CreateFrame("Frame", nil, generalContainer:GetFrame())
PixelUtilCompat.SetSize(healingAbsorbColorPickerContainer, generalContainer:GetFrame():GetWidth() - 24, 20)

local healingAbsorbColorLabel = healingAbsorbColorPickerContainer:CreateFontString(nil, "ARTWORK", "BAURASFont_Checkbox")
PixelUtilCompat.SetPoint(healingAbsorbColorLabel, "LEFT", healingAbsorbColorPickerContainer, "LEFT", 0, 0)
healingAbsorbColorLabel:SetText("Healing Absorb Bar Color:")

local healingAbsorbColorSwatch = CreateFrame("Button", "BoxxyAurasHealingAbsorbColorSwatch",
    healingAbsorbColorPickerContainer)
PixelUtilCompat.SetSize(healingAbsorbColorSwatch, 16, 16)
PixelUtilCompat.SetPoint(healingAbsorbColorSwatch, "LEFT", healingAbsorbColorLabel, "RIGHT", 8, 0)

-- Create the color background
local healingAbsorbSwatchBg = healingAbsorbColorSwatch:CreateTexture(nil, "BACKGROUND")
PixelUtilCompat.SetAllPoints(healingAbsorbSwatchBg, healingAbsorbColorSwatch)
-- Initialize with default healing absorb color from centralized defaults
local defaultHealingAbsorbColor = BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarColor
healingAbsorbSwatchBg:SetColorTexture(defaultHealingAbsorbColor.r, defaultHealingAbsorbColor.g,
    defaultHealingAbsorbColor.b, defaultHealingAbsorbColor.a)
healingAbsorbColorSwatch.background = healingAbsorbSwatchBg

-- Create border for healing absorb color swatch (same as other color swatches)
local healingAbsorbBorderColor = { 0.6, 0.6, 0.6, 1 }
local healingAbsorbBorderThickness = 1

-- Top border
local healingAbsorbBorderTop = healingAbsorbColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBorderTop:SetColorTexture(unpack(healingAbsorbBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBorderTop, "TOPLEFT", healingAbsorbColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBorderTop, "TOPRIGHT", healingAbsorbColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetHeight(healingAbsorbBorderTop, healingAbsorbBorderThickness)

-- Bottom border
local healingAbsorbBorderBottom = healingAbsorbColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBorderBottom:SetColorTexture(unpack(healingAbsorbBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBorderBottom, "BOTTOMLEFT", healingAbsorbColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBorderBottom, "BOTTOMRIGHT", healingAbsorbColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetHeight(healingAbsorbBorderBottom, healingAbsorbBorderThickness)

-- Left border
local healingAbsorbBorderLeft = healingAbsorbColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBorderLeft:SetColorTexture(unpack(healingAbsorbBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBorderLeft, "TOPLEFT", healingAbsorbColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBorderLeft, "BOTTOMLEFT", healingAbsorbColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetWidth(healingAbsorbBorderLeft, healingAbsorbBorderThickness)

-- Right border
local healingAbsorbBorderRight = healingAbsorbColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBorderRight:SetColorTexture(unpack(healingAbsorbBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBorderRight, "TOPRIGHT", healingAbsorbColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBorderRight, "BOTTOMRIGHT", healingAbsorbColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetWidth(healingAbsorbBorderRight, healingAbsorbBorderThickness)

generalContainer:AddElement(healingAbsorbColorPickerContainer, 26)

healingAbsorbColorSwatch:SetScript("OnMouseUp", function(self)
    -- Show the color picker for healing absorb bar color
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local currentColor = (currentSettings and currentSettings.healingAbsorbBarColor) or
        BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarColor

    local options = {
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = ColorPickerFrame:GetColorAlpha()
            if not currentSettings.healingAbsorbBarColor then
                currentSettings.healingAbsorbBarColor = {}
            end
            currentSettings.healingAbsorbBarColor.r = newR
            currentSettings.healingAbsorbBarColor.g = newG
            currentSettings.healingAbsorbBarColor.b = newB
            currentSettings.healingAbsorbBarColor.a = newA
            -- Update the swatch immediately
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateHealingAbsorbColorSwatch then
                BoxxyAuras.Options:UpdateHealingAbsorbColorSwatch()
            end
            -- Apply to all healing absorb bars
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyHealingAbsorbColorChange then
                BoxxyAuras.Options:ApplyHealingAbsorbColorChange()
            end
        end,
        cancelFunc = function(previousValues)
            if not currentSettings.healingAbsorbBarColor then
                currentSettings.healingAbsorbBarColor = {}
            end
            currentSettings.healingAbsorbBarColor.r = previousValues.r
            currentSettings.healingAbsorbBarColor.g = previousValues.g
            currentSettings.healingAbsorbBarColor.b = previousValues.b
            currentSettings.healingAbsorbBarColor.a = previousValues.a
            -- Update the swatch to show canceled color
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateHealingAbsorbColorSwatch then
                BoxxyAuras.Options:UpdateHealingAbsorbColorSwatch()
            end
            -- Apply to all healing absorb bars
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyHealingAbsorbColorChange then
                BoxxyAuras.Options:ApplyHealingAbsorbColorChange()
            end
        end,
        hasOpacity = true,
        opacity = currentColor.a,
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
        -- Pass the swatch itself so the color picker can update it live
        swatchBg = self.background
    }
    ColorPickerFrame:SetupColorPickerAndShow(options)
end)

BoxxyAuras.Options.HealingAbsorbColorSwatch = healingAbsorbColorSwatch

-- Initialize the healing absorb color swatch with the current color immediately
C_Timer.After(0.1, function()
    if BoxxyAuras.Options and BoxxyAuras.Options.UpdateHealingAbsorbColorSwatch then
        BoxxyAuras.Options:UpdateHealingAbsorbColorSwatch()
    end
end)

-- Healing Absorb Bar Background Color Picker
local healingAbsorbBGColorPickerContainer = CreateFrame("Frame", nil, generalContainer:GetFrame())
PixelUtilCompat.SetSize(healingAbsorbBGColorPickerContainer, generalContainer:GetFrame():GetWidth() - 24, 20)

local healingAbsorbBGColorLabel = healingAbsorbBGColorPickerContainer:CreateFontString(nil, "ARTWORK",
    "BAURASFont_Checkbox")
PixelUtilCompat.SetPoint(healingAbsorbBGColorLabel, "LEFT", healingAbsorbBGColorPickerContainer, "LEFT", 0, 0)
healingAbsorbBGColorLabel:SetText("Healing Absorb BG Color:")

local healingAbsorbBGColorSwatch = CreateFrame("Button", "BoxxyAurasHealingAbsorbBGColorSwatch",
    healingAbsorbBGColorPickerContainer)
PixelUtilCompat.SetSize(healingAbsorbBGColorSwatch, 16, 16)
PixelUtilCompat.SetPoint(healingAbsorbBGColorSwatch, "LEFT", healingAbsorbBGColorLabel, "RIGHT", 8, 0)

-- Create the color background
local healingAbsorbBGSwatchBg = healingAbsorbBGColorSwatch:CreateTexture(nil, "BACKGROUND")
PixelUtilCompat.SetAllPoints(healingAbsorbBGSwatchBg, healingAbsorbBGColorSwatch)
-- Initialize with default healing absorb background color from centralized defaults
local defaultHealingAbsorbBGColor = BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarBGColor
healingAbsorbBGSwatchBg:SetColorTexture(defaultHealingAbsorbBGColor.r, defaultHealingAbsorbBGColor.g,
    defaultHealingAbsorbBGColor.b, defaultHealingAbsorbBGColor.a)
healingAbsorbBGColorSwatch.background = healingAbsorbBGSwatchBg

-- Create border for healing absorb background color swatch (same as other color swatches)
local healingAbsorbBGBorderColor = { 0.6, 0.6, 0.6, 1 }
local healingAbsorbBGBorderThickness = 1

-- Top border
local healingAbsorbBGBorderTop = healingAbsorbBGColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBGBorderTop:SetColorTexture(unpack(healingAbsorbBGBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBGBorderTop, "TOPLEFT", healingAbsorbBGColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBGBorderTop, "TOPRIGHT", healingAbsorbBGColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetHeight(healingAbsorbBGBorderTop, healingAbsorbBGBorderThickness)

-- Bottom border
local healingAbsorbBGBorderBottom = healingAbsorbBGColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBGBorderBottom:SetColorTexture(unpack(healingAbsorbBGBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBGBorderBottom, "BOTTOMLEFT", healingAbsorbBGColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBGBorderBottom, "BOTTOMRIGHT", healingAbsorbBGColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetHeight(healingAbsorbBGBorderBottom, healingAbsorbBGBorderThickness)

-- Left border
local healingAbsorbBGBorderLeft = healingAbsorbBGColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBGBorderLeft:SetColorTexture(unpack(healingAbsorbBGBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBGBorderLeft, "TOPLEFT", healingAbsorbBGColorSwatch, "TOPLEFT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBGBorderLeft, "BOTTOMLEFT", healingAbsorbBGColorSwatch, "BOTTOMLEFT", 0, 0)
PixelUtilCompat.SetWidth(healingAbsorbBGBorderLeft, healingAbsorbBGBorderThickness)

-- Right border
local healingAbsorbBGBorderRight = healingAbsorbBGColorSwatch:CreateTexture(nil, "BORDER")
healingAbsorbBGBorderRight:SetColorTexture(unpack(healingAbsorbBGBorderColor))
PixelUtilCompat.SetPoint(healingAbsorbBGBorderRight, "TOPRIGHT", healingAbsorbBGColorSwatch, "TOPRIGHT", 0, 0)
PixelUtilCompat.SetPoint(healingAbsorbBGBorderRight, "BOTTOMRIGHT", healingAbsorbBGColorSwatch, "BOTTOMRIGHT", 0, 0)
PixelUtilCompat.SetWidth(healingAbsorbBGBorderRight, healingAbsorbBGBorderThickness)

generalContainer:AddElement(healingAbsorbBGColorPickerContainer, 26)

healingAbsorbBGColorSwatch:SetScript("OnMouseUp", function(self)
    -- Show the color picker for healing absorb bar background color
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local currentColor = (currentSettings and currentSettings.healingAbsorbBarBGColor) or
        BoxxyAuras:GetDefaultProfileSettings().healingAbsorbBarBGColor

    local options = {
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = ColorPickerFrame:GetColorAlpha()
            if not currentSettings.healingAbsorbBarBGColor then
                currentSettings.healingAbsorbBarBGColor = {}
            end
            currentSettings.healingAbsorbBarBGColor.r = newR
            currentSettings.healingAbsorbBarBGColor.g = newG
            currentSettings.healingAbsorbBarBGColor.b = newB
            currentSettings.healingAbsorbBarBGColor.a = newA
            -- Update the swatch immediately
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateHealingAbsorbBGColorSwatch then
                BoxxyAuras.Options:UpdateHealingAbsorbBGColorSwatch()
            end
            -- Apply to all healing absorb bars
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyHealingAbsorbColorChange then
                BoxxyAuras.Options:ApplyHealingAbsorbColorChange()
            end
        end,
        cancelFunc = function(previousValues)
            if not currentSettings.healingAbsorbBarBGColor then
                currentSettings.healingAbsorbBarBGColor = {}
            end
            currentSettings.healingAbsorbBarBGColor.r = previousValues.r
            currentSettings.healingAbsorbBarBGColor.g = previousValues.g
            currentSettings.healingAbsorbBarBGColor.b = previousValues.b
            currentSettings.healingAbsorbBarBGColor.a = previousValues.a
            -- Update the swatch to show canceled color
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateHealingAbsorbBGColorSwatch then
                BoxxyAuras.Options:UpdateHealingAbsorbBGColorSwatch()
            end
            -- Apply to all healing absorb bars
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplyHealingAbsorbColorChange then
                BoxxyAuras.Options:ApplyHealingAbsorbColorChange()
            end
        end,
        hasOpacity = true,
        opacity = currentColor.a,
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
        -- Pass the swatch itself so the color picker can update it live
        swatchBg = self.background
    }
    ColorPickerFrame:SetupColorPickerAndShow(options)
end)

BoxxyAuras.Options.HealingAbsorbBGColorSwatch = healingAbsorbBGColorSwatch

-- Initialize the healing absorb background color swatch with the current color immediately
C_Timer.After(0.1, function()
    if BoxxyAuras.Options and BoxxyAuras.Options.UpdateHealingAbsorbBGColorSwatch then
        BoxxyAuras.Options:UpdateHealingAbsorbBGColorSwatch()
    end
end)

-- Font Selection Dropdown
local fontDropdownContainer = CreateFrame("Frame", nil, generalContainer:GetFrame())
PixelUtilCompat.SetSize(fontDropdownContainer, generalContainer:GetFrame():GetWidth() - 24, 32)

local fontLabel = fontDropdownContainer:CreateFontString(nil, "ARTWORK", "BAURASFont_Checkbox")
PixelUtilCompat.SetPoint(fontLabel, "LEFT", fontDropdownContainer, "LEFT", 0, 0)
fontLabel:SetText("Aura Text Font:")

-- Create the font dropdown
local fontDropdown = CreateFrame("Frame", "BoxxyAurasFontDropdown", fontDropdownContainer, "UIDropDownMenuTemplate")
PixelUtilCompat.SetWidth(fontDropdown, 200)
PixelUtilCompat.SetPoint(fontDropdown, "LEFT", fontLabel, "RIGHT", 8, 0)

-- Hide default button textures to allow custom styling
local fontDropdownButton = _G[fontDropdown:GetName() .. "Button"]
if fontDropdownButton then
    fontDropdownButton:Hide()
end

-- Hide the background textures
local fontDropdownLeft = _G[fontDropdown:GetName() .. "Left"]
local fontDropdownMiddle = _G[fontDropdown:GetName() .. "Middle"]
local fontDropdownRight = _G[fontDropdown:GetName() .. "Right"]

if fontDropdownLeft then fontDropdownLeft:Hide() end
if fontDropdownMiddle then fontDropdownMiddle:Hide() end
if fontDropdownRight then fontDropdownRight:Hide() end

-- Center Dropdown Text
local fontDropdownText = _G[fontDropdown:GetName() .. "Text"]
if fontDropdownText then
    fontDropdownText:SetJustifyH("LEFT")
    fontDropdownText:ClearAllPoints()
    PixelUtilCompat.SetPoint(fontDropdownText, "LEFT", fontDropdown, "LEFT", 8, 0)
end

-- Style the font dropdown
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
    BoxxyAuras.UIUtils.DrawSlicedBG(fontDropdown, "BtnBG", "backdrop", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(fontDropdown, "backdrop", 0.1, 0.1, 0.1, 0.85)
    BoxxyAuras.UIUtils.DrawSlicedBG(fontDropdown, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(fontDropdown, "border", 0.4, 0.4, 0.4, 0.9)
end

-- Dropdown Arrow Texture
local fontArrow = fontDropdown:CreateTexture(nil, "OVERLAY")
PixelUtilCompat.SetSize(fontArrow, 16, 16)
PixelUtilCompat.SetPoint(fontArrow, "RIGHT", fontDropdown, "RIGHT", -8, 0)
fontArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown")
fontArrow:SetTexCoord(0, 1, 0, 1)

-- Font Dropdown Hover Effect
fontDropdown:SetScript("OnEnter", function(self)
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.8, 0.8, 0.8, 1.0)
    end
end)
fontDropdown:SetScript("OnLeave", function(self)
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.4, 0.4, 0.4, 0.9)
    end
end)

-- Initialize font dropdown
local function InitializeFontDropdown()
    local fontList = Media:HashTable("font")
    local sortedFonts = {}

    -- Convert hash table to sorted array
    for fontName, fontPath in pairs(fontList) do
        table.insert(sortedFonts, fontName)
    end
    table.sort(sortedFonts)

    -- Clear existing items
    UIDropDownMenu_Initialize(fontDropdown, function()
        local settings = BoxxyAuras:GetCurrentProfileSettings()
        local currentFont = settings and settings.textFont or BoxxyAuras:GetDefaultProfileSettings().textFont

        -- Make sure our current font is in the list (fallback safety)
        if currentFont and not fontList[currentFont] then
            if BoxxyAuras.DEBUG then
                print("|cffFFCC00BoxxyAuras Warning:|r Current font '" ..
                currentFont .. "' not found in LibSharedMedia. Using default.")
            end
            currentFont = "OpenSans SemiBold" -- Fallback to our registered font
        end

        for _, fontName in ipairs(sortedFonts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = fontName
            info.value = fontName
            info.func = function(self)
                local settings = BoxxyAuras:GetCurrentProfileSettings()
                if settings then
                    settings.textFont = fontName
                    UIDropDownMenu_SetText(fontDropdown, fontName)

                    -- Apply font change to all auras
                    if BoxxyAuras.Options.ApplyFontChange then
                        BoxxyAuras.Options:ApplyFontChange()
                    end
                end
                PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
            end
            info.checked = (fontName == currentFont)

            -- Create a custom font object for this dropdown item to show font preview
            local fontPath = fontList[fontName]
            if fontPath then
                -- Create a unique font object name for this dropdown item
                local fontObjectName = "BoxxyAurasFontPreview_" .. fontName:gsub("[^%w]", "_")

                -- Only create the font object if it doesn't already exist
                if not _G[fontObjectName] then
                    local fontObject = CreateFont(fontObjectName)
                    fontObject:SetFont(fontPath, 12, "OUTLINE")
                    fontObject:SetTextColor(1, 1, 1, 1) -- White text
                    _G[fontObjectName] = fontObject
                end

                -- Apply the font object to this dropdown item
                info.fontObject = _G[fontObjectName]
            end

            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Set initial text
    local settings = BoxxyAuras:GetCurrentProfileSettings()
    local currentFont = settings and settings.textFont or BoxxyAuras:GetDefaultProfileSettings().textFont

    -- Ensure we display a valid font name
    if currentFont and not fontList[currentFont] then
        currentFont = "OpenSans SemiBold" -- Fallback to our registered font
    end

    UIDropDownMenu_SetText(fontDropdown, currentFont)
end

-- Click handler for font dropdown
fontDropdown:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        ToggleDropDownMenu(1, nil, self)
    end
end)

BoxxyAuras.Options.FontDropdown = fontDropdown
BoxxyAuras.Options.InitializeFontDropdown = InitializeFontDropdown
generalContainer:AddElement(fontDropdownContainer, 38) -- height 32 + 6px padding

-- Update reference for next container
lastContainer = generalContainer

-- Add reset button to general settings container
BoxxyAuras.Options.GeneralResetButton = BoxxyAuras.Options:CreateResetButton(generalContainer, function()
    BoxxyAuras.Options:ResetGeneralSettings()
end)

--[[------------------------------------------------------------
-- Display Frame Settings (Alignment & Size)
--------------------------------------------------------------]]

--[[------------------------------------------------------------
-- Side-by-Side Frame Settings (Buff and Debuff)
--------------------------------------------------------------]]

--[[------------------------
-- Buff Settings Container (Left Side)
--------------------------]]
local buffContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Buff Settings")
buffContainer:SetPosition("TOPLEFT", lastContainer:GetFrame(), "BOTTOMLEFT", 0, -15)
-- Resize to half width for side-by-side layout
local buffFrame = buffContainer:GetFrame()
PixelUtilCompat.SetWidth(buffFrame, (contentFrame:GetWidth() / 2) - 17) -- Half width minus margin

-- Buff Text Alignment
local buffAlignCheckboxes = buffContainer:AddCheckboxRow(
    { { text = "Left", value = "LEFT" }, { text = "Center", value = "CENTER" }, { text = "Right", value = "RIGHT" } },
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
        settings.buffFrameSettings.buffTextAlign = value
        BoxxyAuras.Options:ApplyTextAlign("Buff")
    end
)
BoxxyAuras.Options.BuffAlignCheckboxes = buffAlignCheckboxes

-- Add spacer before wrap direction
buffContainer:AddSpacer()

-- Buff Wrap Direction
local buffWrapCheckboxes = buffContainer:AddCheckboxRow(
    { { text = "Wrap Down", value = "DOWN" }, { text = "Wrap Up", value = "UP" } },
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
        settings.buffFrameSettings.wrapDirection = value
        BoxxyAuras.Options:ApplyWrapDirection("Buff")
    end
)
BoxxyAuras.Options.BuffWrapCheckboxes = buffWrapCheckboxes

-- Add spacer between alignment and sliders
buffContainer:AddSpacer()

-- Buff Icon Size Slider
local buffSizeSlider = buffContainer:AddSlider("Icon Size", 12, 64, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.iconSize = value
    BoxxyAuras.Options:ApplyIconSizeChange("Buff")
end)
BoxxyAuras.Options.BuffSizeSlider = buffSizeSlider

-- Buff Text Size Slider
local buffTextSizeSlider = buffContainer:AddSlider("Text Size", 6, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.textSize = value
    BoxxyAuras.Options:ApplyTextSizeChange("Buff")
end)
BoxxyAuras.Options.BuffTextSizeSlider = buffTextSizeSlider

-- Buff Border Size Slider
local buffBorderSizeSlider = buffContainer:AddSlider("Border Size", 0, 3, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.borderSize = value
    BoxxyAuras.Options:ApplyBorderSizeChange("Buff")
end)
BoxxyAuras.Options.BuffBorderSizeSlider = buffBorderSizeSlider

-- Buff Icon Spacing Slider
local buffSpacingSlider = buffContainer:AddSlider("Icon Spacing", -10, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.iconSpacing = value
    BoxxyAuras.Options:ApplyIconSpacingChange("Buff")
end)
BoxxyAuras.Options.BuffSpacingSlider = buffSpacingSlider

--[[--------------------------
-- Debuff Settings Container (Right Side)
----------------------------]]
local debuffContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Debuff Settings")
-- Position to the right of the buff container at the same vertical level
debuffContainer:SetPosition("TOPLEFT", buffContainer:GetFrame(), "TOPRIGHT", 10, 0)

-- Resize to half width for side-by-side layout
local debuffFrame = debuffContainer:GetFrame()
PixelUtilCompat.SetWidth(debuffFrame, (contentFrame:GetWidth() / 2) - 17) -- Half width minus margin

-- Debuff Text Alignment
local debuffAlignCheckboxes = debuffContainer:AddCheckboxRow(
    { { text = "Left", value = "LEFT" }, { text = "Center", value = "CENTER" }, { text = "Right", value = "RIGHT" } },
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
        settings.debuffFrameSettings.debuffTextAlign = value
        BoxxyAuras.Options:ApplyTextAlign("Debuff")
    end
)
BoxxyAuras.Options.DebuffAlignCheckboxes = debuffAlignCheckboxes

-- Add spacer before wrap direction
debuffContainer:AddSpacer()

-- Debuff Wrap Direction
local debuffWrapCheckboxes = debuffContainer:AddCheckboxRow(
    { { text = "Wrap Down", value = "DOWN" }, { text = "Wrap Up", value = "UP" } },
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
        settings.debuffFrameSettings.wrapDirection = value
        BoxxyAuras.Options:ApplyWrapDirection("Debuff")
    end
)
BoxxyAuras.Options.DebuffWrapCheckboxes = debuffWrapCheckboxes

-- Add spacer between alignment and sliders
debuffContainer:AddSpacer()

-- Debuff Icon Size Slider
local debuffSizeSlider = debuffContainer:AddSlider("Icon Size", 12, 64, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.iconSize = value
    BoxxyAuras.Options:ApplyIconSizeChange("Debuff")
end)
BoxxyAuras.Options.DebuffSizeSlider = debuffSizeSlider

-- Debuff Text Size Slider
local debuffTextSizeSlider = debuffContainer:AddSlider("Text Size", 6, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.textSize = value
    BoxxyAuras.Options:ApplyTextSizeChange("Debuff")
end)
BoxxyAuras.Options.DebuffTextSizeSlider = debuffTextSizeSlider

-- Debuff Border Size Slider
local debuffBorderSizeSlider = debuffContainer:AddSlider("Border Size", 0, 3, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.borderSize = value
    BoxxyAuras.Options:ApplyBorderSizeChange("Debuff")
end)
BoxxyAuras.Options.DebuffBorderSizeSlider = debuffBorderSizeSlider

-- Debuff Icon Spacing Slider
local debuffSpacingSlider = debuffContainer:AddSlider("Icon Spacing", -10, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.iconSpacing = value
    BoxxyAuras.Options:ApplyIconSpacingChange("Debuff")
end)
BoxxyAuras.Options.DebuffSpacingSlider = debuffSpacingSlider

-- Add reset buttons to buff and debuff containers
BoxxyAuras.Options.BuffResetButton = BoxxyAuras.Options:CreateResetButton(buffContainer, function()
    BoxxyAuras.Options:ResetBuffSettings()
end)

BoxxyAuras.Options.DebuffResetButton = BoxxyAuras.Options:CreateResetButton(debuffContainer, function()
    BoxxyAuras.Options:ResetDebuffSettings()
end)

-- Update reference for next container (use the buff container since both are at same level)
lastContainer = buffContainer

--[[------------------------------------------------------------
-- Custom Aura Bars Management Section
--------------------------------------------------------------]]

-- Main container for custom bars (spans full width like profile section)
local customBarsContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Custom Aura Bars")
customBarsContainer:SetPosition("TOPLEFT", lastContainer:GetFrame(), "BOTTOMLEFT", 0, -15)

-- Create New Bar Container
local createBarContainer = BoxxyAuras.UIBuilder.CreateContainer(customBarsContainer:GetFrame(), "Create New Bar")
createBarContainer:SetPosition("TOPLEFT", customBarsContainer:GetFrame(), "TOPLEFT", 12, -30)
createBarContainer:SetParentContainer(customBarsContainer) -- Set parent relationship

-- Add warning label for bar limit
local limitWarningLabel = createBarContainer:GetFrame():CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
limitWarningLabel:SetText("You can only create a maximum of 5 custom bars.")
limitWarningLabel:SetTextColor(1, 0.8, 0, 1) -- Warning yellow color
limitWarningLabel:SetPoint("TOPRIGHT", createBarContainer:GetFrame(), "TOPRIGHT", -12, -12)
limitWarningLabel:Hide()
BoxxyAuras.Options.CustomBarLimitWarning = limitWarningLabel

-- Add bar creation controls to the create container using the new AddRow method
local creationControls = createBarContainer:AddRow({
    {
        type = "EditBox",
        placeholder = "Enter bar name...",
        width = 400,
        height = 20,
        xOffset = 5, -- Add a little padding for the input box
        onEnterPressed = function(self)
            local barName = self:GetText()
            if barName and barName ~= "" then
                BoxxyAuras.Options:CreateCustomBar(barName)
                self:SetText("")
                self:ClearFocus()
            end
        end
    },
    {
        type = "Button",
        text = "Create Bar",
        width = 120,
        -- The onClick handler is now set *after* the row is created
        -- to correctly capture the edit box reference.
    }
}, 35) -- A bit more height for the row

-- Store references if needed
local addBarEditBox = creationControls[1]
local createBarButton = creationControls[2]

-- Now that we have references, set the button's OnClick script
if createBarButton and addBarEditBox then
    createBarButton:SetScript("OnClick", function()
        local barName = addBarEditBox:GetText()
        if barName and barName ~= "" then
            BoxxyAuras.Options:CreateCustomBar(barName)
            addBarEditBox:SetText("")
            addBarEditBox:ClearFocus()
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
end


-- Configure Bar Container (will hold the tabs and content)
local configureBarContainer = BoxxyAuras.UIBuilder.CreateContainer(customBarsContainer:GetFrame(), "Configure Bars")
configureBarContainer:SetPosition("TOPLEFT", createBarContainer:GetFrame(), "BOTTOMLEFT", 0, -15)
configureBarContainer:SetParentContainer(customBarsContainer) -- Set parent relationship

-- Tab system for custom bars (inside the configure container)
local tabFrameContainer = CreateFrame("Frame", nil, configureBarContainer:GetFrame())
-- The tab container only needs to be as tall as the tabs themselves (25px). Using a larger height left an undesired gap.
PixelUtilCompat.SetSize(tabFrameContainer, configureBarContainer:GetFrame():GetWidth() - 24, 20)
PixelUtilCompat.SetPoint(tabFrameContainer, "TOPLEFT", configureBarContainer:GetFrame(), "TOPLEFT", 12, -44)

-- Initialize custom bars management
BoxxyAuras.Options.CustomBars = {
    tabs = {},
    activeTab = nil,
    tabContainer = tabFrameContainer,
    contentFrames = {},
    createBarContainer = createBarContainer,
    configureBarContainer = configureBarContainer
}

-- Function to create a new custom bar
function BoxxyAuras.Options:CreateCustomBar(barName)
    if not barName or barName == "" then
        print("|cffFF0000BoxxyAuras:|r Please enter a valid bar name.")
        return
    end

    -- Sanitize name for use as frame ID
    local barId = barName:gsub("[^%w]", "")
    if barId == "" then
        print("|cffFF0000BoxxyAuras:|r Bar name must contain at least one letter or number.")
        return
    end

    -- Check if bar already exists
    local settings = GetCurrentProfileSettings()
    if settings.customFrameProfiles and settings.customFrameProfiles[barId] then
        print("|cffFF0000BoxxyAuras:|r A custom bar with that name already exists.")
        return
    end

    -- Check for bar limit
    local customBarCount = 0
    if settings.customFrameProfiles then
        for _ in pairs(settings.customFrameProfiles) do
            customBarCount = customBarCount + 1
        end
    end

    if customBarCount >= 5 then
        local warningLabel = self.CustomBarLimitWarning
        if warningLabel then
            warningLabel:Show()
            C_Timer.After(6, function()
                if warningLabel then
                    warningLabel:Hide()
                end
            end)
        end
        return
    end

    -- Create the bar using the core function
    if BoxxyAuras:CreateCustomBar(barName) then
        print("|cff00FF00BoxxyAuras:|r Created custom bar '" .. barName .. "'")

        local barId = barName:gsub("[^%w]", "") -- Same sanitization as in core function

        -- If demo mode is active, generate demo auras for the new bar
        if self.demoModeActive and BoxxyAuras.demoAuras then
            self:GenerateDemoAurasForBar(barId, barName)

            -- Trigger an update to show the new demo auras
            C_Timer.After(0.1, function()
                BoxxyAuras.UpdateAuras(false)
            end)
        end

        self:RefreshCustomBarTabs()

        -- Auto-select the newly created bar's tab
        C_Timer.After(0.1, function()
            if self.CustomBars and self.CustomBars.tabs and self.CustomBars.tabs[barId] then
                self:SelectCustomBarTab(barId)
            end
        end)
    else
        print("|cffFF0000BoxxyAuras:|r Failed to create custom bar.")
    end
end

-- Function to delete a custom bar
function BoxxyAuras.Options:DeleteCustomBar(barId)
    local success = BoxxyAuras:DeleteCustomBar(barId)

    if success then
        print("|cff00FF00BoxxyAuras:|r Deleted custom bar '" .. barId .. "'")

        -- If demo mode is active, clean up demo auras for the deleted bar
        if self.demoModeActive and BoxxyAuras.demoAuras and BoxxyAuras.demoAuras[barId] then
            BoxxyAuras.demoAuras[barId] = nil

            -- Trigger an update to remove the demo auras from display
            C_Timer.After(0.1, function()
                BoxxyAuras.UpdateAuras(false)
            end)
        end
    else
        print("|cffFF0000BoxxyAuras:|r Failed to delete custom bar '" .. barId .. "'.")
    end

    -- Always refresh the UI after a delete attempt. This ensures that even if a
    -- bar can't be deleted (like the default "Custom" bar), the UI will update
    -- to reflect its new (potentially empty) state.
    self:RefreshCustomBarTabs()
end

-- Function to refresh the tab display
function BoxxyAuras.Options:RefreshCustomBarTabs()
    -- Clear existing tabs
    for _, tab in pairs(self.CustomBars.tabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    wipe(self.CustomBars.tabs)

    -- Clear existing content frames
    for _, frame in pairs(self.CustomBars.contentFrames) do
        frame:Hide()
        frame:SetParent(nil)
    end
    wipe(self.CustomBars.contentFrames)

    -- Cancel and clear any pending save timers
    if self.CustomBars.saveTimers then
        for barId, timer in pairs(self.CustomBars.saveTimers) do
            if timer then
                timer:Cancel()
            end
        end
        wipe(self.CustomBars.saveTimers)
    end

    -- Get all custom bars from settings
    local settings = GetCurrentProfileSettings()
    local customBars = {}

    if settings.customFrameProfiles then
        for barId, barConfig in pairs(settings.customFrameProfiles) do
            table.insert(customBars, { id = barId, name = barConfig.name or barId })
        end
    end



    -- Sort bars alphabetically
    table.sort(customBars, function(a, b) return a.name < b.name end)

    if #customBars == 0 then
        -- Hide configure container when no bars exist
        if self.CustomBars.configureBarContainer then
            self.CustomBars.configureBarContainer:GetFrame():Hide()
        end

        -- Show placeholder text
        if not self.CustomBars.placeholderText then
            self.CustomBars.placeholderText = self.CustomBars.createBarContainer:GetFrame():CreateFontString(nil,
                "OVERLAY", "GameFontNormalSmall")
            self.CustomBars.placeholderText:SetPoint("TOP", self.CustomBars.createBarContainer:GetFrame(), "BOTTOM", 0,
                -20)
            self.CustomBars.placeholderText:SetTextColor(0.7, 0.7, 0.7, 1)
            self.CustomBars.placeholderText:SetText("Create your first custom bar above to get started!")
        end
        self.CustomBars.placeholderText:Show()

        -- Reposition subsequent sections
        if BoxxyAuras.Options.RepositionGlobalContainer then
            BoxxyAuras.Options:RepositionGlobalContainer()
        end
    else
        -- Show configure container when bars exist
        if self.CustomBars.configureBarContainer then
            self.CustomBars.configureBarContainer:GetFrame():Show()
        end

        -- Hide placeholder text
        if self.CustomBars.placeholderText then
            self.CustomBars.placeholderText:Hide()
        end

        -- Create tabs for each custom bar
        local tabSpacing = 2
        local lastTab = nil
        local horizontalOffset = 10 -- Initial indent from the left edge

        for i, barInfo in ipairs(customBars) do
            local tab = self:CreateCustomBarTab(barInfo.id, barInfo.name)
            self.CustomBars.tabs[barInfo.id] = tab

            -- Dynamically position the tab
            tab:ClearAllPoints()
            if lastTab then
                PixelUtilCompat.SetPoint(tab, "TOPLEFT", lastTab, "TOPRIGHT", tabSpacing, 0)
            else
                PixelUtilCompat.SetPoint(tab, "TOPLEFT", self.CustomBars.tabContainer, "TOPLEFT", horizontalOffset, 0)
            end
            lastTab = tab
        end

        -- Select the first tab if available
        if customBars[1] then
            self:SelectCustomBarTab(customBars[1].id)
        end

        -- Update parent container size after showing/hiding content
        C_Timer.After(0.2, function()
            if customBars[1] and self.CustomBars.activeTab then
                self:UpdateTabContentHeight(self.CustomBars.activeTab)
            end
        end)

        -- Reposition subsequent sections
        if BoxxyAuras.Options.RepositionGlobalContainer then
            BoxxyAuras.Options:RepositionGlobalContainer()
        end
    end

    -- Force update of main custom bars container size after all changes
    if customBarsContainer and customBarsContainer.UpdateHeightFromChildren then
        customBarsContainer:UpdateHeightFromChildren()
    end

    -- Ensure ignored auras section is positioned correctly after custom bars changes
    C_Timer.After(0.1, function()
        if BoxxyAuras.Options.RepositionGlobalContainer then
            BoxxyAuras.Options:RepositionGlobalContainer()
        end
    end)
end

-- Function to create a tab for a custom bar
function BoxxyAuras.Options:CreateCustomBarTab(barId, barName)
    local tab = CreateFrame("Button", nil, self.CustomBars.tabContainer, "BAURASTabTemplate")

    tab:SetText(barName)
    -- The sound is now played by the template's OnClick script.
    -- We hook our logic to run after the template's script.
    tab:HookScript("OnClick", function()
        BoxxyAuras.Options:SelectCustomBarTab(barId)
    end)

    -- Apply initial inactive tab styling
    tab:SetActive(false)

    -- Create content frame for this tab (positioned within the configure container, not constrained by tab container height)
    local contentFrame = CreateFrame("Frame", nil, self.CustomBars.configureBarContainer:GetFrame())
    PixelUtilCompat.SetSize(contentFrame, self.CustomBars.configureBarContainer:GetFrame():GetWidth() - 24, 50) -- Start small, will grow
    PixelUtilCompat.SetPoint(contentFrame, "TOPLEFT", self.CustomBars.tabContainer, "BOTTOMLEFT", 0, 0)

    -- No background styling needed - the mainBarContainer inside will provide its own styling

    contentFrame:Hide()

    self.CustomBars.contentFrames[barId] = contentFrame
    self:CreateCustomBarContent(barId, contentFrame)

    return tab
end

-- Function to select a tab
function BoxxyAuras.Options:SelectCustomBarTab(barId)
    -- Update tab appearances
    for id, tab in pairs(self.CustomBars.tabs) do
        if id == barId then
            -- Active tab styling
            tab:SetActive(true)
            self.CustomBars.activeTab = barId
        else
            -- Inactive tab styling
            tab:SetActive(false)
        end
    end

    -- Show/hide content frames
    for id, frame in pairs(self.CustomBars.contentFrames) do
        if id == barId then
            frame:Show()
        else
            frame:Hide()
        end
    end

    -- Force update of parent containers after showing/hiding content
    C_Timer.After(0.1, function()
        self:UpdateTabContentHeight(barId)
    end)
end

-- Function to update tab content height dynamically
function BoxxyAuras.Options:UpdateTabContentHeight(barId)
    if not self.CustomBars.contentFrames or not self.CustomBars.contentFrames[barId] then
        return
    end

    local contentFrame = self.CustomBars.contentFrames[barId]
    if not contentFrame:IsVisible() then
        return -- Don't update hidden content frames
    end

    -- Calculate required height based on deepest descendant using absolute coordinates
    local top = contentFrame:GetTop() or 0
    local lowestBottom = top

    local function Scan(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsShown() then
                local childBottom = child:GetBottom()
                if childBottom and childBottom < lowestBottom then
                    lowestBottom = childBottom
                end
                Scan(child)
            end
        end
    end

    Scan(contentFrame)

    local newHeight = math.max(50, (top - lowestBottom) + 20) -- Minimum 50, plus padding

    -- Update configure container to encompass tabs + content
    local tabHeight = 25        -- Tab area height (should match BAURASTabTemplate height)
    local spacing = 0           -- No space between tabs and content (connected directly)
    local containerPadding = 40 -- Container padding
    local totalConfigureHeight = tabHeight + spacing + newHeight + containerPadding

    -- Update the configure container height
    if self.CustomBars.configureBarContainer then
        PixelUtilCompat.SetHeight(self.CustomBars.configureBarContainer:GetFrame(), totalConfigureHeight)

        -- Update main custom bars container as well
        if self.CustomBars.configureBarContainer.parentContainer and
            self.CustomBars.configureBarContainer.parentContainer.UpdateHeightFromChildren then
            self.CustomBars.configureBarContainer.parentContainer:UpdateHeightFromChildren()
        end
    end
end

-- Function to create content for a custom bar tab
function BoxxyAuras.Options:CreateCustomBarContent(barId, contentFrame)
    -- Create main container for the entire bar with an empty title to remove the header
    local mainBarContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "")
    mainBarContainer:SetPosition("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)

    -- Create nested containers for organized sections

    -- Appearance Settings Container (now on the left side)
    local appearanceContainer = BoxxyAuras.UIBuilder.CreateContainer(mainBarContainer:GetFrame(), "Appearance Settings")
    appearanceContainer:SetPosition("TOPLEFT", mainBarContainer:GetFrame(), "TOPLEFT", 12, -12)
    local appearanceFrame = appearanceContainer:GetFrame()
    local parentWidth = mainBarContainer:GetFrame():GetWidth()
    PixelUtilCompat.SetWidth(appearanceFrame, (parentWidth / 2) - 17)

    -- Create alignment options as checkboxes
    local alignmentOptions = {
        { text = "Left",   value = "LEFT" },
        { text = "Center", value = "CENTER" },
        { text = "Right",  value = "RIGHT" }
    }

    local alignButtons = appearanceContainer:AddCheckboxRow(alignmentOptions, function(value)
        -- Update settings
        local settings = GetCurrentProfileSettings()

        -- Save to customFrameProfiles for all custom frames
        if not settings.customFrameProfiles then settings.customFrameProfiles = {} end
        if not settings.customFrameProfiles[barId] then settings.customFrameProfiles[barId] = {} end
        settings.customFrameProfiles[barId].customTextAlign = value

        -- Apply changes
        BoxxyAuras.Options:ApplyTextAlign(barId)
    end)

    -- Wrap Direction
    local wrapOptions = {
        { text = "Wrap Down", value = "DOWN" },
        { text = "Wrap Up",   value = "UP" }
    }

    local wrapButtons = appearanceContainer:AddCheckboxRow(wrapOptions, function(value)
        local settings = GetCurrentProfileSettings()

        -- Save to customFrameProfiles for all custom frames
        if not settings.customFrameProfiles then settings.customFrameProfiles = {} end
        if not settings.customFrameProfiles[barId] then settings.customFrameProfiles[barId] = {} end
        settings.customFrameProfiles[barId].wrapDirection = value

        BoxxyAuras.Options:ApplyWrapDirection(barId)
    end)

    -- Icon Size Slider
    local iconSizeSlider = appearanceContainer:AddSlider("Icon Size", 12, 64, 1, function(value)
        local settings = GetCurrentProfileSettings()

        -- Save to customFrameProfiles for all custom frames
        if not settings.customFrameProfiles then settings.customFrameProfiles = {} end
        if not settings.customFrameProfiles[barId] then settings.customFrameProfiles[barId] = {} end
        settings.customFrameProfiles[barId].iconSize = value

        BoxxyAuras.Options:ApplyIconSizeChange(barId)
    end)

    -- Text Size Slider
    local textSizeSlider = appearanceContainer:AddSlider("Text Size", 6, 20, 1, function(value)
        local settings = GetCurrentProfileSettings()

        -- Save to customFrameProfiles for all custom frames
        if not settings.customFrameProfiles then settings.customFrameProfiles = {} end
        if not settings.customFrameProfiles[barId] then settings.customFrameProfiles[barId] = {} end
        settings.customFrameProfiles[barId].textSize = value

        BoxxyAuras.Options:ApplyTextSizeChange(barId)
    end)

    -- Border Size Slider
    local borderSizeSlider = appearanceContainer:AddSlider("Border Size", 0, 3, 1, function(value)
        local settings = GetCurrentProfileSettings()

        -- Save to customFrameProfiles for all custom frames
        if not settings.customFrameProfiles then settings.customFrameProfiles = {} end
        if not settings.customFrameProfiles[barId] then settings.customFrameProfiles[barId] = {} end
        settings.customFrameProfiles[barId].borderSize = value

        BoxxyAuras.Options:ApplyBorderSizeChange(barId)
    end)

    -- Icon Spacing Slider
    local spacingSlider = appearanceContainer:AddSlider("Icon Spacing", -10, 20, 1, function(value)
        local settings = GetCurrentProfileSettings()

        -- Save to customFrameProfiles for all custom frames
        if not settings.customFrameProfiles then settings.customFrameProfiles = {} end
        if not settings.customFrameProfiles[barId] then settings.customFrameProfiles[barId] = {} end
        settings.customFrameProfiles[barId].iconSpacing = value

        BoxxyAuras.Options:ApplyIconSpacingChange(barId)
    end)

    appearanceContainer:AddSpacer(10)

    -- Delete button (now anchored inside the appearance container)
    local deleteButton = appearanceContainer:AddButton("Delete Bar", 120, function()
        self:DeleteCustomBar(barId)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end, "LEFT", { top = 6, right = 8, bottom = 6, left = 8 })

    -- Aura Assignment Container (now on the right side)
    local auraContainer = BoxxyAuras.UIBuilder.CreateContainer(mainBarContainer:GetFrame(), "Aura Assignments")
    auraContainer:SetPosition("TOPLEFT", appearanceContainer:GetFrame(), "TOPRIGHT", 10, 0)
    local auraFrame = auraContainer:GetFrame()
    PixelUtilCompat.SetWidth(auraFrame, (parentWidth / 2) - 17)

    -- Instructions text
    local instructLabel = auraContainer:GetFrame():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    PixelUtilCompat.SetPoint(instructLabel, "TOPLEFT", auraContainer:GetFrame(), "TOPLEFT", 12, -35)
    PixelUtilCompat.SetPoint(instructLabel, "TOPRIGHT", auraContainer:GetFrame(), "TOPRIGHT", -12, -35)
    instructLabel:SetText("Enter exact spell names, separated by commas. Case-insensitive.")
    instructLabel:SetJustifyH("LEFT")
    instructLabel:SetWordWrap(true)
    instructLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Adjust container height to account for instructions
    local currentHeight = auraContainer:GetFrame():GetHeight()
    PixelUtilCompat.SetHeight(auraContainer:GetFrame(), currentHeight + 25)

    -- Helper to clear and redraw the background and border for the edit box container
    local function RestyleEditBoxContainer(container)
        -- Remove old backdrop and border textures if present
        if container.backdropTextures then
            for _, tex in pairs(container.backdropTextures) do
                if tex and tex.Hide then tex:Hide() end
                if tex and tex.SetParent then tex:SetParent(nil) end
            end
            container.backdropTextures = nil
        end
        if container.borderTextures then
            for _, tex in pairs(container.borderTextures) do
                if tex and tex.Hide then tex:Hide() end
                if tex and tex.SetParent then tex:SetParent(nil) end
            end
            container.borderTextures = nil
        end
        -- Redraw
        if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            BoxxyAuras.UIUtils.DrawSlicedBG(container, "OptionsWindowBG", "backdrop", 0)
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(container, "backdrop", 0.05, 0.05, 0.05, 0.8)
            BoxxyAuras.UIUtils.DrawSlicedBG(container, "EdgedBorder", "border", 0)
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(container, "border", 0.4, 0.4, 0.4, 1)
        end
    end

    local padding = 12
    -- Create a hidden FontString for measuring text height (for robust auto-sizing)
    local editBoxFontString = auraContainer:GetFrame():CreateFontString(nil, "OVERLAY", "BAURASFont_General")
    editBoxFontString:SetWidth(auraContainer:GetFrame():GetWidth() - 34 - (padding * 2)) -- Match edit box width minus padding
    editBoxFontString:SetWordWrap(true)
    editBoxFontString:SetNonSpaceWrap(false)
    editBoxFontString:Hide()

    -- Create the actual EditBox, which will serve as its own container
    local editBox = CreateFrame("EditBox", nil, auraContainer:GetFrame())
    PixelUtilCompat.SetSize(editBox, auraContainer:GetFrame():GetWidth() - 34, 28)
    PixelUtilCompat.SetPoint(editBox, "TOPLEFT", instructLabel, "BOTTOMLEFT", 8, -8)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("BAURASFont_General")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetTextInsets(padding, padding, padding, padding) -- Increased padding
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Initial style applied directly to the edit box
    RestyleEditBoxContainer(editBox)

    -- OnTextChanged handler for auto-saving and resizing the container
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end -- Only respond to user input

        -- Debounced auto-save logic
        if BoxxyAuras.Options.CustomBars.saveTimers[barId] then
            BoxxyAuras.Options.CustomBars.saveTimers[barId]:Cancel()
        end
        BoxxyAuras.Options.CustomBars.saveTimers[barId] = C_Timer.NewTimer(1.0, function()
            BoxxyAuras.Options:SaveCustomBarAuras(barId, self:GetText())
            BoxxyAuras.Options.CustomBars.saveTimers[barId] = nil
        end)

        -- Robust auto-expand using FontString measurement
        editBoxFontString:SetWidth(self:GetWidth() - (padding * 2))
        editBoxFontString:SetText(self:GetText())
        editBoxFontString:Show()
        local measuredHeight = editBoxFontString:GetStringHeight() + (padding * 2)
        editBoxFontString:Hide()

        PixelUtilCompat.SetHeight(self, measuredHeight)

        -- Redraw background and border at new size
        RestyleEditBoxContainer(self)

        -- After resizing, we need to update the parent container's layout
        C_Timer.After(0.01, function()
            if BoxxyAuras.Options and BoxxyAuras.Options.UpdateTabContentHeight then
                BoxxyAuras.Options:UpdateTabContentHeight(barId)
            end
        end)
    end)

    -- Adjust final container height to include all elements (now handled by the expanding container)
    -- local finalHeight = auraContainer:GetFrame():GetHeight() + 75
    -- PixelUtilCompat.SetHeight(auraContainer:GetFrame(), finalHeight)

    -- Store references for loading/saving
    if not self.CustomBars.editBoxes then
        self.CustomBars.editBoxes = {}
    end
    if not self.CustomBars.alignButtons then
        self.CustomBars.alignButtons = {}
    end
    if not self.CustomBars.iconSizeSliders then
        self.CustomBars.iconSizeSliders = {}
    end
    if not self.CustomBars.textSizeSliders then
        self.CustomBars.textSizeSliders = {}
    end
    if not self.CustomBars.borderSizeSliders then
        self.CustomBars.borderSizeSliders = {}
    end
    if not self.CustomBars.spacingSliders then
        self.CustomBars.spacingSliders = {}
    end
    if not self.CustomBars.wrapButtons then
        self.CustomBars.wrapButtons = {}
    end
    if not self.CustomBars.saveTimers then
        self.CustomBars.saveTimers = {}
    end

    self.CustomBars.editBoxes[barId] = editBox
    self.CustomBars.alignButtons[barId] = alignButtons
    self.CustomBars.iconSizeSliders[barId] = iconSizeSlider
    self.CustomBars.textSizeSliders[barId] = textSizeSlider
    self.CustomBars.borderSizeSliders[barId] = borderSizeSlider
    self.CustomBars.spacingSliders[barId] = spacingSlider
    self.CustomBars.wrapButtons[barId] = wrapButtons

    -- Store container references for potential future updates
    if not self.CustomBars.containers then
        self.CustomBars.containers = {}
    end
    self.CustomBars.containers[barId] = {
        main = mainBarContainer,
        appearance = appearanceContainer,
        aura = auraContainer
    }

    -- Load current data
    self:LoadCustomBarData(barId)

    -- Force update of parent containers after adding all content
    C_Timer.After(0.1, function()
        -- Update child containers first
        if auraContainer and auraContainer.UpdateHeightFromChildren then
            auraContainer:UpdateHeightFromChildren()
        end
        if appearanceContainer and appearanceContainer.UpdateHeightFromChildren then
            appearanceContainer:UpdateHeightFromChildren()
        end
        -- Then update the main container to encompass all children
        if mainBarContainer and mainBarContainer.UpdateHeightFromChildren then
            mainBarContainer:UpdateHeightFromChildren()
        end
        self:UpdateTabContentHeight(barId)
    end)

    -- Store meta info so LoadCustomBarData can resize correctly on initial load
    if not self.CustomBars.editBoxMeta then
        self.CustomBars.editBoxMeta = {}
    end
    self.CustomBars.editBoxMeta[barId] = {
        fontString = editBoxFontString,
        padding = padding,
        restyle = RestyleEditBoxContainer
    }
end

-- Function to save aura assignments for a custom bar
function BoxxyAuras.Options:SaveCustomBarAuras(barId, auraText)
    local settings = GetCurrentProfileSettings()
    if not settings.customAuraAssignments then
        settings.customAuraAssignments = {}
    end

    -- Clear existing assignments for this bar
    for auraName, assignedBarId in pairs(settings.customAuraAssignments) do
        if assignedBarId == barId then
            settings.customAuraAssignments[auraName] = nil
        end
    end

    -- Parse new assignments
    if auraText and auraText ~= "" then
        for name in string.gmatch(auraText .. ',', "([^,]*),") do
            local trimmedName = string.match(name, "^%s*(.-)%s*$")
            if trimmedName and trimmedName ~= "" then
                settings.customAuraAssignments[trimmedName] = barId
            end
        end
    end

    -- Trigger aura update
    if BoxxyAuras.UpdateAuras then
        BoxxyAuras.UpdateAuras()
    end
end

-- Function to load data for a custom bar tab
function BoxxyAuras.Options:LoadCustomBarData(barId)
    local settings = GetCurrentProfileSettings()

    -- Load aura assignments
    if self.CustomBars.editBoxes and self.CustomBars.editBoxes[barId] then
        local auraNames = {}
        if settings.customAuraAssignments then
            for auraName, assignedBarId in pairs(settings.customAuraAssignments) do
                if assignedBarId == barId then
                    table.insert(auraNames, auraName)
                end
            end
        end
        table.sort(auraNames)
        local editBox = self.CustomBars.editBoxes[barId]
        editBox:SetText(table.concat(auraNames, ", "))

        -- Resize/restyle based on stored meta after a short delay to allow layout pass
        local meta = self.CustomBars.editBoxMeta and self.CustomBars.editBoxMeta[barId]
        if editBox and meta and meta.fontString and meta.padding and meta.restyle then
            C_Timer.After(0.05, function()
                meta.fontString:SetWidth(editBox:GetWidth() - (meta.padding * 2))
                meta.fontString:SetText(editBox:GetText())
                meta.fontString:Show()
                local measuredHeight = meta.fontString:GetStringHeight() + (meta.padding * 2)
                meta.fontString:Hide()

                editBox:SetHeight(measuredHeight)
                meta.restyle(editBox)
            end)
        end
    end

    -- Load alignment setting
    if self.CustomBars.alignButtons and self.CustomBars.alignButtons[barId] then
        local currentAlign = "CENTER" -- Default

        -- Read from customFrameProfiles for all custom frames
        if settings.customFrameProfiles and settings.customFrameProfiles[barId] then
            currentAlign = settings.customFrameProfiles[barId].customTextAlign or "CENTER"
        end

        -- Set the checkbox row value using the UIBuilder helper
        BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.CustomBars.alignButtons[barId], currentAlign)
    end

    -- Load icon size setting
    if self.CustomBars.iconSizeSliders and self.CustomBars.iconSizeSliders[barId] then
        local currentIconSize = 24 -- Default

        if settings.customFrameProfiles and settings.customFrameProfiles[barId] then
            currentIconSize = settings.customFrameProfiles[barId].iconSize or 24
        end

        self.CustomBars.iconSizeSliders[barId]:SetValue(currentIconSize)
    end

    -- Load text size setting
    if self.CustomBars.textSizeSliders and self.CustomBars.textSizeSliders[barId] then
        local currentTextSize = 8 -- Default

        if settings.customFrameProfiles and settings.customFrameProfiles[barId] then
            currentTextSize = settings.customFrameProfiles[barId].textSize or 8
        end

        self.CustomBars.textSizeSliders[barId]:SetValue(currentTextSize)
    end

    -- Load border size setting
    if self.CustomBars.borderSizeSliders and self.CustomBars.borderSizeSliders[barId] then
        local currentBorderSize = 1 -- Default

        if settings.customFrameProfiles and settings.customFrameProfiles[barId] then
            currentBorderSize = settings.customFrameProfiles[barId].borderSize or 1
        end

        self.CustomBars.borderSizeSliders[barId]:SetValue(currentBorderSize)
    end

    -- Load icon spacing setting
    if self.CustomBars.spacingSliders and self.CustomBars.spacingSliders[barId] then
        local currentSpacing = 0 -- Default

        if settings.customFrameProfiles and settings.customFrameProfiles[barId] then
            currentSpacing = settings.customFrameProfiles[barId].iconSpacing or 0
        end

        self.CustomBars.spacingSliders[barId]:SetValue(currentSpacing)
    end

    -- Load wrap direction setting
    if self.CustomBars.wrapButtons and self.CustomBars.wrapButtons[barId] then
        local currentWrap = "DOWN" -- Default

        if settings.customFrameProfiles and settings.customFrameProfiles[barId] then
            currentWrap = settings.customFrameProfiles[barId].wrapDirection or "DOWN"
        end

        BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.CustomBars.wrapButtons[barId], currentWrap)
    end
end

-- Initialize the custom bars display
C_Timer.After(0.1, function()
    if BoxxyAuras.Options and BoxxyAuras.Options.RefreshCustomBarTabs then
        BoxxyAuras.Options:RefreshCustomBarTabs()
    end
end)

-- Update reference for next container - use the configure container if it exists and is visible, otherwise the create container
local function GetLastCustomBarContainer()
    if BoxxyAuras.Options.CustomBars and BoxxyAuras.Options.CustomBars.configureBarContainer then
        local configFrame = BoxxyAuras.Options.CustomBars.configureBarContainer:GetFrame()
        if configFrame and configFrame:IsVisible() then
            return BoxxyAuras.Options.CustomBars.configureBarContainer
        end
    end
    if BoxxyAuras.Options.CustomBars and BoxxyAuras.Options.CustomBars.createBarContainer then
        return BoxxyAuras.Options.CustomBars.createBarContainer
    end
    return customBarsContainer
end

-- Store a function to get the proper last container for subsequent sections
BoxxyAuras.Options.GetCustomBarsLastContainer = GetLastCustomBarContainer
lastContainer = customBarsContainer -- Default fallback

--[[------------------------------------------------------------
-- Load, Save, and Toggle Functions
--------------------------------------------------------------]]

-- Load settings into the options UI
function BoxxyAuras.Options:Load()
    local settings = GetCurrentProfileSettings()
    if not settings then
        if BoxxyAuras.DEBUG then
            print("|cffFF0000BoxxyAuras Options Error:|r Cannot load settings: No profile loaded.")
        end
        return
    end

    if BoxxyAuras.DEBUG then
        print("|cff00FF00BoxxyAuras:|r Loading options for profile: " .. (BoxxyAurasDB.activeProfile or "Default"))
    end

    -- General Settings
    self.LockFramesCheck:SetChecked(settings.lockFrames)
    self.HideBlizzardCheck:SetChecked(settings.hideBlizzardAuras)
    self.ShowHoverBorderCheck:SetChecked(settings.showHoverBorder)

    -- Use default value (true) if enableFlashAnimationOnShow is nil
    local enableFlashOnShow = settings.enableFlashAnimationOnShow
    if enableFlashOnShow == nil then
        enableFlashOnShow = true -- Default to enabled
    end
    self.EnableFlashOnShowCheck:SetChecked(enableFlashOnShow)

    -- Use default value (true) if enableDotTickingAnimation is nil
    local enableDotTicking = settings.enableDotTickingAnimation
    if enableDotTicking == nil then
        enableDotTicking = true -- Default to enabled
    end
    self.EnableDotTickingCheck:SetChecked(enableDotTicking)

    -- Use default value (true) if showInfiniteDuration is nil
    local showInfiniteDuration = settings.showInfiniteDuration
    if showInfiniteDuration == nil then
        showInfiniteDuration = true -- Default to enabled
    end
    self.ShowInfiniteDurationCheck:SetChecked(showInfiniteDuration)

    -- Note: Demo mode is transient, not saved, so it's not loaded here.
    -- It should be off by default when opening the panel.
    self.DemoModeCheck:SetChecked(self.demoModeActive or false)

    -- Load Normal Border Color
    self:UpdateNormalBorderColorSwatch()

    -- Load Background Color
    self:UpdateBackgroundColorSwatch()

    -- Load Healing Absorb Colors
    self:UpdateHealingAbsorbColorSwatch()
    self:UpdateHealingAbsorbBGColorSwatch()

    -- Load Buff Frame Settings
    if settings.buffFrameSettings then
        -- Buff Icon Size
        if self.BuffSizeSlider and settings.buffFrameSettings.iconSize then
            self.BuffSizeSlider:SetValue(settings.buffFrameSettings.iconSize)
        end

        -- Buff Text Size
        if self.BuffTextSizeSlider and settings.buffFrameSettings.textSize then
            self.BuffTextSizeSlider:SetValue(settings.buffFrameSettings.textSize)
        end

        -- Buff Border Size
        if self.BuffBorderSizeSlider and settings.buffFrameSettings.borderSize then
            self.BuffBorderSizeSlider:SetValue(settings.buffFrameSettings.borderSize)
        end

        -- Buff Icon Spacing
        if self.BuffSpacingSlider and settings.buffFrameSettings.iconSpacing then
            self.BuffSpacingSlider:SetValue(settings.buffFrameSettings.iconSpacing)
        end

        -- Buff Text Alignment
        if self.BuffAlignCheckboxes and settings.buffFrameSettings.buffTextAlign then
            BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.BuffAlignCheckboxes, settings.buffFrameSettings.buffTextAlign)
        end

        -- Buff Wrap Direction
        if self.BuffWrapCheckboxes and settings.buffFrameSettings.wrapDirection then
            BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.BuffWrapCheckboxes, settings.buffFrameSettings.wrapDirection)
        end
    end

    -- Load Debuff Frame Settings
    if settings.debuffFrameSettings then
        -- Debuff Icon Size
        if self.DebuffSizeSlider and settings.debuffFrameSettings.iconSize then
            self.DebuffSizeSlider:SetValue(settings.debuffFrameSettings.iconSize)
        end

        -- Debuff Text Size
        if self.DebuffTextSizeSlider and settings.debuffFrameSettings.textSize then
            self.DebuffTextSizeSlider:SetValue(settings.debuffFrameSettings.textSize)
        end

        -- Debuff Border Size
        if self.DebuffBorderSizeSlider and settings.debuffFrameSettings.borderSize then
            self.DebuffBorderSizeSlider:SetValue(settings.debuffFrameSettings.borderSize)
        end

        -- Debuff Icon Spacing
        if self.DebuffSpacingSlider and settings.debuffFrameSettings.iconSpacing then
            self.DebuffSpacingSlider:SetValue(settings.debuffFrameSettings.iconSpacing)
        end

        -- Debuff Text Alignment
        if self.DebuffAlignCheckboxes and settings.debuffFrameSettings.debuffTextAlign then
            BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.DebuffAlignCheckboxes,
                settings.debuffFrameSettings.debuffTextAlign)
        end

        -- Debuff Wrap Direction
        if self.DebuffWrapCheckboxes and settings.debuffFrameSettings.wrapDirection then
            BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.DebuffWrapCheckboxes,
                settings.debuffFrameSettings.wrapDirection)
        end
    end

    -- Load Custom Bars Data
    if self.RefreshCustomBarTabs then
        self:RefreshCustomBarTabs()
    end

    -- Load Ignored Auras
    if self.IgnoredAurasEditBox then
        local ignoredAuras = {}
        if settings.ignoredAuras then
            for auraName, _ in pairs(settings.ignoredAuras) do
                table.insert(ignoredAuras, auraName)
            end
        end
        table.sort(ignoredAuras)
        self.IgnoredAurasEditBox:SetText(table.concat(ignoredAuras, ", "))

        -- Trigger resize and restyle after loading content
        C_Timer.After(0.05, function()
            if self.IgnoredAurasEditBox then
                local editBox = self.IgnoredAurasEditBox
                local currentText = editBox:GetText()

                -- Measure and resize
                if ignoredEditBoxFontString then
                    ignoredEditBoxFontString:SetWidth(editBox:GetWidth() - (ignoredPadding * 2))
                    ignoredEditBoxFontString:SetText(currentText)
                    ignoredEditBoxFontString:Show()
                    local measuredHeight = ignoredEditBoxFontString:GetStringHeight() + (ignoredPadding * 2)
                    ignoredEditBoxFontString:Hide()

                    editBox:SetHeight(measuredHeight)
                    RestyleIgnoredAurasEditBox(editBox)

                    -- Also update the container height
                    BoxxyAuras.Options:UpdateIgnoredAurasContainerHeight()
                end
            end
        end)
    end

    -- Load Aura Bar Scale (note: this only updates the slider, actual scale should already be applied to frames)
    if self.AuraBarScaleSlider and settings.auraBarScale then
        local scaleValue = settings.auraBarScale
        if scaleValue <= 0 then scaleValue = 1.0 end
        settings.auraBarScale = scaleValue
        if BoxxyAuras.DEBUG then
            print(string.format("Loading aura bar scale from settings: %.2f", scaleValue))
        end
        self.AuraBarScaleSlider:SetValue(scaleValue)
    elseif self.AuraBarScaleSlider then
        if BoxxyAuras.DEBUG then
            print("No aura bar scale in settings, setting default 1.0")
        end
        self.AuraBarScaleSlider:SetValue(1.0)
        if settings then settings.auraBarScale = 1.0 end
    end

    -- Load Options Window Scale
    if self.OptionsWindowScaleSlider and settings.optionsWindowScale then
        local scaleValue = settings.optionsWindowScale
        if scaleValue <= 0 then scaleValue = 1.0 end
        settings.optionsWindowScale = scaleValue
        self.OptionsWindowScaleSlider:SetValue(scaleValue)
        -- Apply the saved scale immediately on load so the UI reflects the correct size
        if self.ApplyOptionsWindowScale then
            self:ApplyOptionsWindowScale(scaleValue)
        end
    elseif self.OptionsWindowScaleSlider then
        -- If no scale setting exists, set default value
        self.OptionsWindowScaleSlider:SetValue(1.0)
        if self.ApplyOptionsWindowScale then
            self:ApplyOptionsWindowScale(1.0)
        end
        if settings then
            settings.optionsWindowScale = 1.0
        end
    end

    -- Initialize Profile Dropdown and UI
    self:InitializeProfileDropdown()
    self:UpdateProfileUI()
end

-- Toggle the main options window
function BoxxyAuras.Options:Toggle()
    local frame = self.Frame
    if not frame then
        return
    end

    if frame:IsShown() then
        -- Turn off demo mode when closing options
        if self.demoModeActive then
            self:SetDemoMode(false)
            if self.DemoModeCheck then
                self.DemoModeCheck:SetChecked(false)
            end
        end
        frame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    else
        self:Load() -- Load current settings into UI before showing
        frame:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- Initialize the profile dropdown menu
function BoxxyAuras.Options:InitializeProfileDropdown()
    if not self.ProfileDropdown then
        return
    end

    -- Set up the dropdown initialization function
    UIDropDownMenu_Initialize(self.ProfileDropdown, function(self, level)
        if not BoxxyAurasDB or not BoxxyAurasDB.profiles then
            return
        end

        local info = UIDropDownMenu_CreateInfo()
        local currentProfile = BoxxyAurasDB.activeProfile or "Default"

        -- Add each profile as a dropdown option
        for profileName, _ in pairs(BoxxyAurasDB.profiles) do
            info.text = profileName
            info.value = profileName
            info.checked = (profileName == currentProfile)
            info.func = function()
                -- When a new profile is selected from the dropdown, switch to it first
                BoxxyAuras:SwitchToProfile(profileName)

                -- Refresh the entire options UI so every control reflects the new active profile / remaining profiles
                if BoxxyAuras.Options and BoxxyAuras.Options.Load then
                    BoxxyAuras.Options:Load()
                elseif BoxxyAuras.Options then
                    -- Fallback partial refresh
                    if BoxxyAuras.Options.UpdateProfileUI then
                        BoxxyAuras.Options:UpdateProfileUI()
                    end
                    if BoxxyAuras.Options.InitializeProfileDropdown then
                        BoxxyAuras.Options:InitializeProfileDropdown()
                    end
                end

                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Set the dropdown text to current profile
    local currentProfile = BoxxyAurasDB and BoxxyAurasDB.activeProfile or "Default"
    UIDropDownMenu_SetText(self.ProfileDropdown, currentProfile)
end

-- Update profile-related UI elements
function BoxxyAuras.Options:UpdateProfileUI()
    if not BoxxyAurasDB then
        return
    end

    -- Update dropdown text
    local currentProfile = BoxxyAurasDB.activeProfile or "Default"
    if self.ProfileDropdown then
        UIDropDownMenu_SetText(self.ProfileDropdown, currentProfile)
    end

    -- Enable/disable delete button based on whether we have multiple profiles
    if self.DeleteProfileButton then
        local profileCount = 0
        if BoxxyAurasDB.profiles then
            for _ in pairs(BoxxyAurasDB.profiles) do
                profileCount = profileCount + 1
            end
        end

        local canDelete = profileCount > 1 and currentProfile ~= "Default"
        -- Use custom SetEnabled helper so visual + logical states update together
        if self.DeleteProfileButton.SetEnabled then
            self.DeleteProfileButton:SetEnabled(canDelete)
        else
            -- Fallback to native
            if canDelete then
                self.DeleteProfileButton:Enable()
            else
                self.DeleteProfileButton:Disable()
            end
        end
    end

    -- Update the color swatches when profile changes
    self:UpdateNormalBorderColorSwatch()
    self:UpdateBackgroundColorSwatch()
    self:UpdateHealingAbsorbColorSwatch()
    self:UpdateHealingAbsorbBGColorSwatch()
end

-- Create a new profile
function BoxxyAuras.Options:CreateProfile(profileName)
    if not profileName or profileName == "" then
        print("|cffFF0000BoxxyAuras:|r Please enter a profile name.")
        return
    end

    if not BoxxyAurasDB then
        print("|cffFF0000BoxxyAuras:|r Database not initialized.")
        return
    end

    if not BoxxyAurasDB.profiles then
        BoxxyAurasDB.profiles = {}
    end

    if BoxxyAurasDB.profiles[profileName] then
        print("|cffFF0000BoxxyAuras:|r Profile '" .. profileName .. "' already exists.")
        return
    end

    -- Create new profile with default settings
    BoxxyAurasDB.profiles[profileName] = BoxxyAuras:GetDefaultProfileSettings()
    print("|cff00FF00BoxxyAuras:|r Created profile '" .. profileName .. "'.")

    -- Switch to the new profile
    BoxxyAuras:SwitchToProfile(profileName)

    -- Force all frames to their default positions from the new profile
    -- (This overrides any LibWindow saved positions that might interfere)
    local newProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
    if newProfileSettings and BoxxyAuras.Frames then
        local frameTypes = { "Buff", "Debuff" }
        for _, frameType in ipairs(frameTypes) do
            local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
            local frame = BoxxyAuras.Frames[frameType]

            if settingsKey and newProfileSettings[settingsKey] and frame then
                local frameSettings = newProfileSettings[settingsKey]
                local anchor = frameSettings.anchor or "CENTER"
                local x = frameSettings.x or 0
                local y = frameSettings.y or 0

                -- Clear all existing points and set the default position
                frame:ClearAllPoints()
                PixelUtilCompat.SetPoint(frame, anchor, UIParent, anchor, x, y)

                -- Save this position with LibWindow so it persists
                if LibWindow and LibWindow.SavePosition then
                    print("|cFF00FF00BoxxyAuras:|r Saving position for " .. frameType)
                    LibWindow.SavePosition(frame)
                end
            end
        end
    end

    -- Fully reload the options UI so every widget reflects the new profile
    if self.Load then
        self:Load()
    else
        -- Fallback
        self:UpdateProfileUI()
        self:InitializeProfileDropdown()
    end
end

-- Copy current profile to a new profile
function BoxxyAuras.Options:CopyProfile(profileName)
    if not profileName or profileName == "" then
        print("|cffFF0000BoxxyAuras:|r Please enter a profile name.")
        return
    end

    if not BoxxyAurasDB or not BoxxyAurasDB.profiles then
        print("|cffFF0000BoxxyAuras:|r No profiles available to copy.")
        return
    end

    if BoxxyAurasDB.profiles[profileName] then
        print("|cffFF0000BoxxyAuras:|r Profile '" .. profileName .. "' already exists.")
        return
    end

    local currentProfile = BoxxyAurasDB.activeProfile or "Default"
    local currentSettings = BoxxyAurasDB.profiles[currentProfile]

    if not currentSettings then
        print("|cffFF0000BoxxyAuras:|r Current profile data not found.")
        return
    end

    -- Deep copy current profile settings
    BoxxyAurasDB.profiles[profileName] = BoxxyAuras:DeepCopyTable(currentSettings)
    print("|cff00FF00BoxxyAuras:|r Copied profile '" .. currentProfile .. "' to '" .. profileName .. "'.")

    -- Switch to the new profile
    BoxxyAuras:SwitchToProfile(profileName)
    -- Fully reload the options UI so every widget reflects the new profile
    if self.Load then
        self:Load()
    else
        -- Fallback
        self:UpdateProfileUI()
        self:InitializeProfileDropdown()
    end
end

-- Cleanup function to cancel all pending update timers
function BoxxyAuras.Options:CancelAllUpdateTimers()
    if not BoxxyAuras.Options.updateTimers then return end

    for timerKey, timer in pairs(BoxxyAuras.Options.updateTimers) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
    end

    -- Clear the timers table
    BoxxyAuras.Options.updateTimers = {}
end

-- Helper function to generate demo auras for a specific bar
function BoxxyAuras.Options:GenerateDemoAurasForBar(barId, barName)
    if not BoxxyAuras.demoAuras then
        BoxxyAuras.demoAuras = {}
    end

    local customDemoAuraTemplate = {
        {
            name = "Custom Aura",
            icon = "Interface\\Icons\\Spell_Arcane_TeleportStormwind",
            duration = 0, -- Permanent for demo
            applications = 1,
            spellId = 32345
        },
        {
            name = "Tracking",
            icon = "Interface\\Icons\\Spell_Nature_FaerieFire",
            duration = 0, -- Permanent for demo
            applications = 1,
            spellId = 32346
        },
        {
            name = "Enchant",
            icon = "Interface\\Icons\\Spell_Holy_GreaterHeal",
            duration = 0, -- Permanent for demo
            applications = 1,
            spellId = 32347
        },
        {
            name = "Proc",
            icon = "Interface\\Icons\\Spell_Lightning_LightningBolt01",
            duration = 0, -- Permanent for demo
            applications = 5,
            spellId = 32348
        }
    }

    BoxxyAuras.demoAuras[barId] = {}
    for i, templateAura in ipairs(customDemoAuraTemplate) do
        -- Deep copy to avoid modifying the template
        local newAura = BoxxyAuras:DeepCopyTable(templateAura)

        -- Customize for the specific bar
        newAura.name = barName .. " - " .. templateAura.name
        newAura.auraInstanceID = "demo_" .. barId .. "_" .. i
        newAura.expirationTime = 0 -- Always permanent for demo mode
        newAura.isDemoAura = true  -- Mark as demo aura
        table.insert(BoxxyAuras.demoAuras[barId], newAura)
    end

    if BoxxyAuras.DEBUG then
        print("|cff00FF00BoxxyAuras:|r Generated " ..
            #BoxxyAuras.demoAuras[barId] .. " demo auras for bar '" .. barName .. "'")
    end
end

-- Set demo mode on/off
function BoxxyAuras.Options:SetDemoMode(enable)
    -- Cancel any pending layout updates to prevent conflicts
    self:CancelAllUpdateTimers()

    self.demoModeActive = enable

    if enable then
        print("|cff00FF00BoxxyAuras:|r Demo mode enabled - showing test auras.")

        -- Dynamically create demo auras with varying durations for timer display
        local currentTime = GetTime()
        BoxxyAuras.demoAuras = {
            Buff = {
                {
                    name = "Demo Blessing",
                    icon = "Interface\\Icons\\Spell_Holy_GreaterBlessofKings",
                    duration = 300,                     -- 5 minutes
                    expirationTime = currentTime + 267, -- 4:27 remaining
                    applications = 1,
                    spellId = 12345,
                    auraInstanceID = "demo_buff_1",
                    isDemoAura = true
                },
                {
                    name = "Demo Shield",
                    icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
                    duration = 60,                     -- 1 minute
                    expirationTime = currentTime + 42, -- 42 seconds remaining
                    applications = 3,
                    spellId = 12346,
                    auraInstanceID = "demo_buff_2",
                    isDemoAura = true
                },
                {
                    name = "Demo Haste",
                    icon = "Interface\\Icons\\Spell_Nature_Bloodlust",
                    duration = 120,                    -- 2 minutes
                    expirationTime = currentTime + 87, -- 1:27 remaining
                    applications = 1,
                    spellId = 12347,
                    auraInstanceID = "demo_buff_3",
                    isDemoAura = true
                },
                {
                    name = "Demo Strength",
                    icon = "Interface\\Icons\\Spell_Holy_GreaterBlessofWisdom",
                    duration = 0, -- Permanent (no timer)
                    expirationTime = 0,
                    applications = 1,
                    spellId = 12348,
                    auraInstanceID = "demo_buff_4",
                    isDemoAura = true
                },
                {
                    name = "Demo Intellect",
                    icon = "Interface\\Icons\\Spell_Holy_MindVision",
                    duration = 30,                     -- 30 seconds
                    expirationTime = currentTime + 18, -- 18 seconds remaining
                    applications = 1,
                    spellId = 12349,
                    auraInstanceID = "demo_buff_5",
                    isDemoAura = true
                },
                {
                    name = "Demo Regeneration",
                    icon = "Interface\\Icons\\Spell_Nature_Rejuvenation",
                    duration = 15,                    -- 15 seconds
                    expirationTime = currentTime + 8, -- 8 seconds remaining
                    applications = 1,
                    spellId = 12350,
                    auraInstanceID = "demo_buff_6",
                    isDemoAura = true
                },
                {
                    name = "Demo Fortitude",
                    icon = "Interface\\Icons\\Spell_Holy_PrayerofFortitude",
                    duration = 0, -- Permanent (no timer)
                    expirationTime = 0,
                    applications = 1,
                    spellId = 12351,
                    auraInstanceID = "demo_buff_7",
                    isDemoAura = true
                },
                {
                    name = "Demo Spirit",
                    icon = "Interface\\Icons\\Spell_Holy_PrayerofSpirit",
                    duration = 10,                    -- 10 seconds
                    expirationTime = currentTime + 3, -- 3 seconds remaining
                    applications = 1,
                    spellId = 12352,
                    auraInstanceID = "demo_buff_8",
                    isDemoAura = true
                }
            },
            Debuff = {
                {
                    name = "Demo Curse",
                    icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
                    duration = 180,                     -- 3 minutes
                    expirationTime = currentTime + 156, -- 2:36 remaining
                    applications = 1,
                    spellId = 22345,
                    auraInstanceID = "demo_debuff_1",
                    dispelName = "CURSE",
                    isDemoAura = true
                },
                {
                    name = "Demo Poison",
                    icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
                    duration = 45,                     -- 45 seconds
                    expirationTime = currentTime + 32, -- 32 seconds remaining
                    applications = 2,
                    spellId = 22346,
                    auraInstanceID = "demo_debuff_2",
                    dispelName = "POISON",
                    isDemoAura = true
                },
                {
                    name = "Demo Disease",
                    icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
                    duration = 90,                     -- 1.5 minutes
                    expirationTime = currentTime + 74, -- 1:14 remaining
                    applications = 1,
                    spellId = 22347,
                    auraInstanceID = "demo_debuff_3",
                    dispelName = "DISEASE",
                    isDemoAura = true
                },
                {
                    name = "Demo Magic Debuff",
                    icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
                    duration = 24,                     -- 24 seconds
                    expirationTime = currentTime + 16, -- 16 seconds remaining
                    applications = 1,
                    spellId = 22348,
                    auraInstanceID = "demo_debuff_4",
                    dispelName = "MAGIC",
                    isDemoAura = true
                },
                {
                    name = "Demo Weakness",
                    icon = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth",
                    duration = 0, -- Permanent (no timer)
                    expirationTime = 0,
                    applications = 1,
                    spellId = 22349,
                    auraInstanceID = "demo_debuff_5",
                    isDemoAura = true
                },
                {
                    name = "Demo Slow",
                    icon = "Interface\\Icons\\Spell_Frost_FrostShock",
                    duration = 8,                     -- 8 seconds
                    expirationTime = currentTime + 5, -- 5 seconds remaining
                    applications = 1,
                    spellId = 22350,
                    auraInstanceID = "demo_debuff_6",
                    isDemoAura = true
                },
                {
                    name = "Demo Healing Absorb",
                    icon = "Interface\\Icons\\Spell_Shadow_AntiMagicShell",
                    duration = 60,                     -- 1 minute
                    expirationTime = currentTime + 27, -- 27 seconds remaining
                    applications = 1,
                    spellId = 22351,
                    auraInstanceID = "demo_debuff_7_absorb",
                    isDemoAura = true
                }
            }
        }

        -- Generate demo auras for all custom bars
        local settings = GetCurrentProfileSettings()
        if settings and settings.customFrameProfiles then
            local customDemoAuraTemplate = {
                {
                    name = "Custom Aura",
                    icon = "Interface\\Icons\\Spell_Arcane_TeleportStormwind",
                    duration = 240, -- 4 minutes
                    applications = 1,
                    spellId = 32345
                },
                {
                    name = "Tracking",
                    icon = "Interface\\Icons\\Spell_Nature_FaerieFire",
                    duration = 0, -- Permanent tracking (no timer)
                    applications = 1,
                    spellId = 32346
                },
                {
                    name = "Enchant",
                    icon = "Interface\\Icons\\Spell_Holy_GreaterHeal",
                    duration = 1800, -- 30 minutes
                    applications = 1,
                    spellId = 32347
                },
                {
                    name = "Proc",
                    icon = "Interface\\Icons\\Spell_Lightning_LightningBolt01",
                    duration = 12, -- 12 seconds
                    applications = 5,
                    spellId = 32348
                }
            }

            for barId, barConfig in pairs(settings.customFrameProfiles) do
                BoxxyAuras.demoAuras[barId] = {}
                for i, templateAura in ipairs(customDemoAuraTemplate) do
                    -- Deep copy to avoid modifying the template
                    local newAura = BoxxyAuras:DeepCopyTable(templateAura)

                    -- Customize for the specific bar
                    newAura.name = (barConfig.name or "Custom") .. " - " .. templateAura.name
                    newAura.auraInstanceID = "demo_" .. barId .. "_" .. i

                    -- Set realistic expiration times for timed auras
                    if newAura.duration > 0 then
                        local timeVariation = (i - 1) * 15 -- Stagger timers by 15 seconds each
                        newAura.expirationTime = currentTime + math.max(5, newAura.duration - timeVariation)
                    else
                        newAura.expirationTime = 0 -- Permanent
                    end

                    newAura.isDemoAura = true -- Mark as demo aura
                    table.insert(BoxxyAuras.demoAuras[barId], newAura)
                end
            end
        end

        -- Set up demo healing absorb tracking for the healing absorb aura
        if not BoxxyAuras.healingAbsorbTracking then
            BoxxyAuras.healingAbsorbTracking = {}
        end

        -- Create demo tracking data for the healing absorb aura
        local demoAbsorbKey = "demo_debuff_7_absorb"
        BoxxyAuras.healingAbsorbTracking[demoAbsorbKey] = {
            spellId = 22351,
            initialAmount = 10000, -- Demo: 10k shield
            currentAmount = 7000,  -- Demo: 70% remaining (7k left)
            totalAbsorbed = 3000,  -- Demo: 3k already absorbed
            lastUpdate = GetTime(),
            debuffRemoved = false
        }
    else
        print("|cff00FF00BoxxyAuras:|r Demo mode disabled.")

        -- Clear demo auras
        if BoxxyAuras.demoAuras then
            BoxxyAuras.demoAuras = nil
        end

        -- Clear demo healing absorb tracking
        if BoxxyAuras.healingAbsorbTracking then
            -- Only clear demo tracking entries, keep any real ones
            BoxxyAuras.healingAbsorbTracking["demo_debuff_7_absorb"] = nil
        end
    end

    -- Force a complete refresh to properly reset all icons when demo mode changes
    -- This ensures any lingering OnUpdate scripts or state from demo auras are cleaned up
    -- Add a small delay to prevent performance issues when creating many demo auras
    C_Timer.After(0.1, function()
        BoxxyAuras.UpdateAuras(true)

        -- If enabling demo mode, trigger healing absorb visuals for the demo absorb aura
        if enable then
            C_Timer.After(0.2, function()
                local demoAbsorbKey = "demo_debuff_7_absorb"
                if BoxxyAuras.healingAbsorbTracking and BoxxyAuras.healingAbsorbTracking[demoAbsorbKey] then
                    BoxxyAuras:UpdateHealingAbsorbVisuals(demoAbsorbKey, BoxxyAuras.healingAbsorbTracking[demoAbsorbKey])
                    if BoxxyAuras.DEBUG then
                        print("BoxxyAuras: Demo mode - Updated healing absorb visuals for demo aura")
                    end
                end
            end)
        end

        -- If enabling demo mode, set up a timer to prevent normal updates from interfering
        if enable then
            -- Cancel any existing demo update timer
            if BoxxyAuras.Options.demoUpdateTimer then
                BoxxyAuras.Options.demoUpdateTimer:Cancel()
            end

            -- Set up a repeating timer to maintain demo auras (less frequent to prevent flicker)
            BoxxyAuras.Options.demoUpdateTimer = C_Timer.NewTicker(5.0, function()
                if BoxxyAuras.Options.demoModeActive then
                    BoxxyAuras.UpdateAuras(false) -- Refresh demo auras
                end
            end)
        else
            -- Cancel the demo update timer when disabling demo mode
            if BoxxyAuras.Options.demoUpdateTimer then
                BoxxyAuras.Options.demoUpdateTimer:Cancel()
                BoxxyAuras.Options.demoUpdateTimer = nil
            end
        end
    end)
end

-- Static Popup for Delete Profile Confirmation
StaticPopupDialogs["BOXXYAURAS_DELETE_PROFILE_CONFIRM"] = {
    text = "Are you sure you want to delete the profile '%s'? This action cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, profileName)
        if not profileName then
            profileName = self.data -- use the data field if arg missing
        end

        if profileName and BoxxyAurasDB and BoxxyAurasDB.profiles then
            if BoxxyAurasDB.profiles[profileName] then
                -- Delete the profile table entry
                BoxxyAurasDB.profiles[profileName] = nil
                print("|cff00FF00BoxxyAuras:|r Deleted profile '" .. profileName .. "'.")

                -- If we just deleted the active profile, immediately switch to the Default profile
                if BoxxyAurasDB.activeProfile == profileName then
                    BoxxyAuras:SwitchToProfile("Default")
                end

                -- Fully reload the options UI so every widget reflects the new (or fallback) profile
                if BoxxyAuras.Options and BoxxyAuras.Options.Load then
                    BoxxyAuras.Options:Load()
                end
            else
                print("|cFFFF0000BoxxyAuras:|r Profile '" .. profileName .. "' not found.")
            end
        end
    end,
    OnCancel = function()
        -- Do nothing
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--[[------------------------------------------------------------
-- Slash Command Registration
--------------------------------------------------------------]]

-- Slash command handler
SLASH_BOXXYAURAS1 = "/boxxyauras"
SLASH_BOXXYAURAS2 = "/ba"

function SlashCmdList.BOXXYAURAS(msg, editBox)
    local command = msg:lower():trim()

    if command == "options" or command == "" then
        BoxxyAuras.Options:Toggle()
    elseif command == "lock" then
        local settings = BoxxyAuras:GetCurrentProfileSettings()
        settings.lockFrames = not settings.lockFrames
        BoxxyAuras.FrameHandler.ApplyLockState(settings.lockFrames)
        print("BoxxyAuras frames " .. (settings.lockFrames and "locked." or "unlocked."))
    elseif command == "debug" then
        -- Toggle the global debug flag
        BoxxyAuras.DEBUG = not BoxxyAuras.DEBUG
        print("BoxxyAuras debug mode " .. (BoxxyAuras.DEBUG and "|cff00FF00enabled|r." or "|cFFFF0000disabled|r."))
    elseif command == "reset" then
        print("|cFF00FF00BoxxyAuras:|r Resetting frame positions...")
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        local defaultSettings = BoxxyAuras:GetDefaultProfileSettings() -- Get defaults for position/scale

        if not currentSettings or not defaultSettings then
            print("|cFFFF0000BoxxyAuras Error:|r Cannot get settings to reset positions.")
            return
        end

        local frameTypes = { "Buff", "Debuff" }
        for _, frameType in ipairs(frameTypes) do
            local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
            local frame = BoxxyAuras.Frames and BoxxyAuras.Frames[frameType]

            if settingsKey and currentSettings[settingsKey] and frame then
                print("|cFF00FF00BoxxyAuras:|r   Resetting " .. frameType .. " frame saved data.")
                -- Clear DB settings
                currentSettings[settingsKey].x = nil
                currentSettings[settingsKey].y = nil
                currentSettings[settingsKey].point = nil
                currentSettings[settingsKey].scale = nil

                -- Clear size settings
                currentSettings[settingsKey].numIconsWide = nil
                currentSettings[settingsKey].iconSize = nil

                -- Apply Default Position Manually
                local defaultPos = defaultSettings[settingsKey] -- Get defaults for THIS frame type
                local defaultAnchor = defaultPos and defaultPos.anchor or "CENTER"
                local defaultX = defaultPos and defaultPos.x or 0
                local defaultY = defaultPos and defaultPos.y or 0

                -- === Update DB with default coords BEFORE SetPoint/Save ===
                currentSettings[settingsKey].x = defaultX
                currentSettings[settingsKey].y = defaultY
                currentSettings[settingsKey].point = defaultAnchor
                -- === End DB Update ===

                frame:ClearAllPoints()
                PixelUtilCompat.SetPoint(frame, defaultAnchor, UIParent, defaultAnchor, defaultX, defaultY)

                -- === Save the new default position with LibWindow ===
                if LibWindow and LibWindow.SavePosition then
                    print("|cFF00FF00BoxxyAuras:|r Saving position for " .. frameType)
                    LibWindow.SavePosition(frame)
                end
                -- === End save position ===

                -- Apply Default Scale Manually
                BoxxyAuras.FrameHandler.SetFrameScale(frame, 1.0) -- Assuming default scale is 1.0

                -- Re-apply settings to fix width/layout based on defaults
                BoxxyAuras.FrameHandler.ApplySettings(frameType)
            elseif not frame then
                print("|cFFFF0000BoxxyAuras Warning:|r Frame object not found for " .. frameType)
            end
        end

        print("|cFF00FF00BoxxyAuras:|r Frame positions and scale reset. Layout updated.")
    else
        print("BoxxyAuras: Unknown command '/ba " ..
            command .. "'. Use '/ba options', '/ba lock', '/ba reset', or '/ba debug'.")
    end
end

-- === Aura Bar Scale Slider ===
local auraBarScaleSlider = generalContainer:AddSlider("Aura Bar Scale", 0.5, 2.0, 0.05, function(value)
    -- Update saved variable but do NOT immediately rescale the aura bars.
    local currentSettings = GetCurrentProfileSettings()
    if currentSettings then
        currentSettings.auraBarScale = value
    end
end, false, { labelWidth = 140 }) -- use debounced callback

BoxxyAuras.Options.AuraBarScaleSlider = auraBarScaleSlider

-- Apply the scale only when the user releases the mouse button on the slider
if auraBarScaleSlider then
    auraBarScaleSlider:HookScript("OnMouseUp", function(self)
        local val = self:GetValue()
        if BoxxyAuras.Options and BoxxyAuras.Options.ApplyAuraBarScale then
            BoxxyAuras.Options:ApplyAuraBarScale(val)
        end
    end)
end

-- === Options Window Scale Slider ===
local optionsWindowScaleSlider = generalContainer:AddSlider("Options Window Scale", 0.5, 2.0, 0.05, function(value)
    -- Update saved variable but do NOT immediately rescale the options window.
    local currentSettings = GetCurrentProfileSettings()
    if currentSettings then
        currentSettings.optionsWindowScale = value
    end
end, false, { labelWidth = 140 }) -- use debounced callback

BoxxyAuras.Options.OptionsWindowScaleSlider = optionsWindowScaleSlider

-- Apply the scale only when the user releases the mouse button on the slider
if optionsWindowScaleSlider then
    optionsWindowScaleSlider:HookScript("OnMouseUp", function(self)
        local val = self:GetValue()
        if BoxxyAuras.Options and BoxxyAuras.Options.ApplyOptionsWindowScale then
            BoxxyAuras.Options:ApplyOptionsWindowScale(val)
        end
    end)
end

--[[------------------------------------------------------------
-- Ignored Auras Section
--------------------------------------------------------------]]

-- Function to reposition the global container based on custom bars visibility
function BoxxyAuras.Options:RepositionGlobalContainer()
    if not self.IgnoredAurasContainer then
        return
    end

    -- Get the actual bottom-most container that's currently visible
    local targetContainer = nil

    -- Check if configure container exists and is visible (custom bars exist)
    if self.CustomBars and self.CustomBars.configureBarContainer then
        local configFrame = self.CustomBars.configureBarContainer:GetFrame()
        if configFrame and configFrame:IsVisible() then
            targetContainer = self.CustomBars.configureBarContainer
        end
    end

    -- Fall back to create container if configure isn't visible
    if not targetContainer and self.CustomBars and self.CustomBars.createBarContainer then
        targetContainer = self.CustomBars.createBarContainer
    end

    -- Position relative to the target container
    if targetContainer then
        -- Use a small negative offset to align with the main content area, accounting for container padding
        self.IgnoredAurasContainer:SetPosition("TOPLEFT", targetContainer:GetFrame(), "BOTTOMLEFT", -12, -15)

        if BoxxyAuras.DEBUG then
            print("RepositionGlobalContainer: Positioned relative to " ..
                (targetContainer:GetFrame():GetName() or "unnamed container"))
        end
    end
end

-- Create Ignored Auras container
local ignoredAurasContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Ignored Auras")
-- Position relative to the proper last container (either create or configure container)
local initialParentContainer = GetLastCustomBarContainer()
if initialParentContainer then
    ignoredAurasContainer:SetPosition("TOPLEFT", initialParentContainer:GetFrame(), "BOTTOMLEFT", -12, -15)
else
    -- Fallback to custom bars container if function returns nil
    ignoredAurasContainer:SetPosition("TOPLEFT", customBarsContainer:GetFrame(), "BOTTOMLEFT", -12, -15)
end

-- Instructions text
local ignoredInstructLabel = ignoredAurasContainer:GetFrame():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
PixelUtilCompat.SetPoint(ignoredInstructLabel, "TOPLEFT", ignoredAurasContainer:GetFrame(), "TOPLEFT", 12, -35)
PixelUtilCompat.SetPoint(ignoredInstructLabel, "TOPRIGHT", ignoredAurasContainer:GetFrame(), "TOPRIGHT", -12, -35)
ignoredInstructLabel:SetText(
    "Enter exact spell names to ignore on all aura bars, separated by commas. Case-insensitive.")
ignoredInstructLabel:SetJustifyH("LEFT")
ignoredInstructLabel:SetWordWrap(true)
ignoredInstructLabel:SetTextColor(0.8, 0.8, 0.8, 1)

-- Helper to clear and redraw the background and border for the ignored auras edit box
local function RestyleIgnoredAurasEditBox(container)
    -- Remove old backdrop and border textures if present
    if container.backdropTextures then
        for _, tex in pairs(container.backdropTextures) do
            if tex and tex.Hide then tex:Hide() end
            if tex and tex.SetParent then tex:SetParent(nil) end
        end
        container.backdropTextures = nil
    end
    if container.borderTextures then
        for _, tex in pairs(container.borderTextures) do
            if tex and tex.Hide then tex:Hide() end
            if tex and tex.SetParent then tex:SetParent(nil) end
        end
        container.borderTextures = nil
    end
    -- Redraw
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        BoxxyAuras.UIUtils.DrawSlicedBG(container, "OptionsWindowBG", "backdrop", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(container, "backdrop", 0.05, 0.05, 0.05, 0.8)
        BoxxyAuras.UIUtils.DrawSlicedBG(container, "EdgedBorder", "border", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(container, "border", 0.4, 0.4, 0.4, 1)
    end
end

local ignoredPadding = 12
-- Create a hidden FontString for measuring text height
local ignoredEditBoxFontString = ignoredAurasContainer:GetFrame():CreateFontString(nil, "OVERLAY", "BAURASFont_General")
ignoredEditBoxFontString:SetWidth(ignoredAurasContainer:GetFrame():GetWidth() - 24 - (ignoredPadding * 2)) -- Match the edit box width
ignoredEditBoxFontString:SetWordWrap(true)
ignoredEditBoxFontString:SetNonSpaceWrap(false)
ignoredEditBoxFontString:Hide()

-- Create the EditBox for ignored auras
local ignoredAurasEditBox = CreateFrame("EditBox", nil, ignoredAurasContainer:GetFrame())
PixelUtilCompat.SetSize(ignoredAurasEditBox, ignoredAurasContainer:GetFrame():GetWidth() - 24, 28)  -- Reduced from 34 to 24 to account for container padding
PixelUtilCompat.SetPoint(ignoredAurasEditBox, "TOPLEFT", ignoredInstructLabel, "BOTTOMLEFT", 0, -8) -- Removed the 8px left offset
ignoredAurasEditBox:SetMultiLine(true)
ignoredAurasEditBox:SetAutoFocus(false)
ignoredAurasEditBox:SetFontObject("BAURASFont_General")
ignoredAurasEditBox:SetTextColor(1, 1, 1, 1)
ignoredAurasEditBox:SetTextInsets(ignoredPadding, ignoredPadding, ignoredPadding, ignoredPadding)
ignoredAurasEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Initial style applied directly to the edit box
RestyleIgnoredAurasEditBox(ignoredAurasEditBox)

-- OnTextChanged handler for auto-saving and resizing
ignoredAurasEditBox:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end -- Only respond to user input

    -- Debounced auto-save logic
    if not BoxxyAuras.Options.ignoredAurasSaveTimer then
        BoxxyAuras.Options.ignoredAurasSaveTimer = nil
    end

    if BoxxyAuras.Options.ignoredAurasSaveTimer then
        BoxxyAuras.Options.ignoredAurasSaveTimer:Cancel()
    end
    BoxxyAuras.Options.ignoredAurasSaveTimer = C_Timer.NewTimer(1.0, function()
        BoxxyAuras.Options:SaveIgnoredAuras(self:GetText())
        BoxxyAuras.Options.ignoredAurasSaveTimer = nil
    end)

    -- Auto-expand using FontString measurement
    ignoredEditBoxFontString:SetWidth(self:GetWidth() - (ignoredPadding * 2))
    ignoredEditBoxFontString:SetText(self:GetText())
    ignoredEditBoxFontString:Show()
    local measuredHeight = ignoredEditBoxFontString:GetStringHeight() + (ignoredPadding * 2)
    ignoredEditBoxFontString:Hide()

    PixelUtilCompat.SetHeight(self, measuredHeight)

    -- Redraw background and border at new size
    RestyleIgnoredAurasEditBox(self)

    -- Update container height after resizing
    C_Timer.After(0.01, function()
        BoxxyAuras.Options:UpdateIgnoredAurasContainerHeight()
    end)
end)

-- Store references
BoxxyAuras.Options.IgnoredAurasContainer = ignoredAurasContainer
BoxxyAuras.Options.IgnoredAurasEditBox = ignoredAurasEditBox

-- Position the ignored auras container correctly after creation
C_Timer.After(0.2, function()
    -- Force update of custom bars container height first
    if customBarsContainer and customBarsContainer.UpdateHeightFromChildren then
        customBarsContainer:UpdateHeightFromChildren()
    end

    -- Then reposition the ignored auras section
    if BoxxyAuras.Options.RepositionGlobalContainer then
        BoxxyAuras.Options:RepositionGlobalContainer()
    end
end)

-- Function to save ignored auras
function BoxxyAuras.Options:SaveIgnoredAuras(auraText)
    local settings = GetCurrentProfileSettings()
    if not settings then
        return
    end

    -- Initialize ignored auras list
    if not settings.ignoredAuras then
        settings.ignoredAuras = {}
    end

    -- Clear existing ignored auras
    wipe(settings.ignoredAuras)

    -- Parse new ignored auras
    if auraText and auraText ~= "" then
        for name in string.gmatch(auraText .. ',', "([^,]*),") do
            local trimmedName = string.match(name, "^%s*(.-)%s*$")
            if trimmedName and trimmedName ~= "" then
                -- Store as lowercase for case-insensitive matching
                settings.ignoredAuras[trimmedName:lower()] = true
            end
        end
    end

    -- Trigger aura update to apply the new ignore list
    if BoxxyAuras.UpdateAuras then
        BoxxyAuras.UpdateAuras(true) -- Force full refresh
    end

    if BoxxyAuras.DEBUG then
        local count = 0
        for _ in pairs(settings.ignoredAuras) do
            count = count + 1
        end
        print("|cff00FF00BoxxyAuras:|r Saved " .. count .. " ignored auras")
    end
end

-- NEW: Function to correctly calculate and set the height of the ignored auras container
function BoxxyAuras.Options:UpdateIgnoredAurasContainerHeight()
    if not self.IgnoredAurasContainer then return end

    local containerFrame = self.IgnoredAurasContainer:GetFrame()
    if not containerFrame or not containerFrame:IsVisible() then return end

    local top = containerFrame:GetTop()
    if not top then return end

    local lowestBottom = top

    -- Find the lowest point among the container's visible children
    for _, child in ipairs({ containerFrame:GetChildren() }) do
        if child:IsShown() and child:GetHeight() > 0 then
            local childBottom = child:GetBottom()
            if childBottom and childBottom < lowestBottom then
                lowestBottom = childBottom
            end
        end
    end

    local contentHeight = top - lowestBottom
    local titleAreaHeight = 35 -- Estimated height for title and top padding
    local bottomPadding = 12

    local newHeight = titleAreaHeight + contentHeight + bottomPadding

    -- Ensure a minimum height so the container doesn't collapse
    newHeight = math.max(newHeight, 90)

    PixelUtilCompat.SetHeight(containerFrame, newHeight)
end

-- NEW Function to handle layout refreshes
function BoxxyAuras.Options:RefreshIgnoredAurasLayout()
    if not self.IgnoredAurasEditBox then return end

    local editBox = self.IgnoredAurasEditBox
    local currentText = editBox:GetText()

    if not editBox:IsVisible() then return end

    -- Measure and resize the edit box based on its content
    if ignoredEditBoxFontString then
        ignoredEditBoxFontString:SetWidth(editBox:GetWidth() - (ignoredPadding * 2))
        ignoredEditBoxFontString:SetText(currentText)
        ignoredEditBoxFontString:Show()
        local measuredHeight = ignoredEditBoxFontString:GetStringHeight() + (ignoredPadding * 2)
        ignoredEditBoxFontString:Hide()

        editBox:SetHeight(measuredHeight)
        RestyleIgnoredAurasEditBox(editBox)

        -- Now that the edit box has the correct height, update its parent container
        self:UpdateIgnoredAurasContainerHeight()
    end
end

-- Update reference for potential future containers
lastContainer = ignoredAurasContainer
