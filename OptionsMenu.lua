local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}       -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras          -- Create a convenient local alias to the global table
BoxxyAuras.Options = {}                   -- Table to hold options elements

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
            optionsScale = 1.0,
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
        for _, fType in ipairs({ "Buff", "Debuff", "Custom" }) do
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
        for _, fType in ipairs({ "Buff", "Debuff", "Custom" }) do
            BoxxyAuras.FrameHandler.UpdateAurasInFrame(fType)
        end
    end
end

-- Apply icon size changes
function BoxxyAuras.Options:ApplyIconSizeChange(frameType)
    if not frameType then return end

    local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = GetCurrentProfileSettings()
    if not (currentSettings and settingsKey and currentSettings[settingsKey]) then return end

    local iconSize = currentSettings[settingsKey].iconSize
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

    local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = GetCurrentProfileSettings()
    if not (currentSettings and settingsKey and currentSettings[settingsKey]) then return end

    -- The AuraIcon:Resize function automatically picks up the new text size from settings.
    -- We just need to call it with the *current* icon size to trigger a refresh.
    local iconSize = currentSettings[settingsKey].iconSize
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

    local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = GetCurrentProfileSettings()
    if not (currentSettings and settingsKey and currentSettings[settingsKey]) then return end

    local borderSize = currentSettings[settingsKey].borderSize
    if borderSize == nil then return end

    -- Apply border size to all aura icons of this frame type
    local iconArray = BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[frameType]
    if iconArray then
        for _, icon in ipairs(iconArray) do
            if icon and icon.UpdateBorderSize then
                icon:UpdateBorderSize()
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

    local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = GetCurrentProfileSettings()
    if not (currentSettings and settingsKey and currentSettings[settingsKey]) then return end

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
        for _, icon in ipairs(icons) do
            if icon and icon.UpdateBorderSize then
                icon:UpdateBorderSize() -- This function re-evaluates and re-applies the border color
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
        for _, icon in ipairs(icons) do
            if icon and icon.UpdateBorderSize then
                icon:UpdateBorderSize() -- This function re-evaluates and re-applies the background color
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

-- Apply global scale changes
function BoxxyAuras.Options:ApplyScale(scale)
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
        settings.optionsScale = scale

        -- Apply the scale to all existing frames
        if BoxxyAuras.Frames then
            for frameType, frame in pairs(BoxxyAuras.Frames) do
                if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.SetFrameScale then
                    BoxxyAuras.FrameHandler.SetFrameScale(frame, scale)
                end
            end
        end

        -- Also apply to the options frame itself if desired
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
PixelUtilCompat.SetSize(optionsFrame, 300, 500) -- Adjusted size
PixelUtilCompat.SetPoint(optionsFrame, "CENTER", UIParent, "CENTER", 0, 0)
optionsFrame:SetFrameStrata("HIGH")             -- Changed from MEDIUM to HIGH to appear above aura bars
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
    -- Update UI elements based on the loaded state (Load is called by Toggle before Show)
    if BoxxyAuras.Options.UpdateProfileUI then
        BoxxyAuras.Options:UpdateProfileUI()
    end
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
PixelUtilCompat.SetSize(contentFrame, scrollFrame:GetWidth(), 700) -- <<< Increased height significantly >>>
scrollFrame:SetScrollChild(contentFrame)

-- Layout Variables (for container positioning)
local lastContainer = nil -- Will track the last created container for positioning

--[[------------------------------------------------------------
-- Profile Management Container
--------------------------------------------------------------]]
local profileContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Current Profile")

-- Profile Selection Dropdown (manual creation for complex styling)
local profileDropdown = CreateFrame("Frame", "BoxxyAurasProfileDropdown", profileContainer:GetFrame(),
    "UIDropDownMenuTemplate")
PixelUtilCompat.SetWidth(profileDropdown, profileContainer:GetFrame():GetWidth() - 24) -- Full width minus padding
profileContainer:AddElement(profileDropdown, 30)

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

-- Spacer
profileContainer:AddSpacer()

-- Profile Actions Header
profileContainer:AddHeader("Profile Actions")

-- Calculate button row dimensions for edit box alignment
local buttonRowConfig = {
    { name = "BoxxyAurasCreateProfileButton", text = "New",    width = 60 },
    { name = "BoxxyAurasCopyProfileButton",   text = "Copy",   width = 60 },
    { name = "BoxxyAurasDeleteProfileButton", text = "Delete", width = 60 }
}
local buttonDimensions = profileContainer:CalculateButtonRowDimensions(buttonRowConfig)

-- Profile Name EditBox (aligned with button row)
local editBoxOffset = buttonDimensions.startX + 6 -- Small adjustment to account for edit box visual padding
local profileNameEditBox = profileContainer:AddEditBox("", 32, function(self)
    local name = self:GetText()
    if name and name ~= "" then
        self:SetText("")
        self:ClearFocus()
    end
end, nil, buttonDimensions.totalWidth - 6, editBoxOffset)
BoxxyAuras.Options.ProfileNameEditBox = profileNameEditBox

-- Profile Action Buttons (centered row)
local profileButtons = profileContainer:AddButtonRow({
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
local hideBlizzardCheck = generalContainer:AddCheckbox("Hide Default Blizzard Auras", function(self)
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
local demoModeCheck = generalContainer:AddCheckbox("Demo Mode (Show Test Auras)", function(self)
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

-- Update reference for next container
lastContainer = generalContainer

--[[------------------------------------------------------------
-- Display Frame Settings (Alignment & Size)
--------------------------------------------------------------]]

--[[------------------------
-- Buff Settings Container
--------------------------]]
local buffContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Buff Settings")
buffContainer:SetPosition("TOPLEFT", lastContainer:GetFrame(), "BOTTOMLEFT", 0, -15)

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
local buffSizeSlider = buffContainer:AddSlider("Buff Icon Size", 12, 64, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.iconSize = value
    BoxxyAuras.Options:ApplyIconSizeChange("Buff")
end)
BoxxyAuras.Options.BuffSizeSlider = buffSizeSlider

-- Buff Text Size Slider
local buffTextSizeSlider = buffContainer:AddSlider("Buff Text Size", 6, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.textSize = value
    BoxxyAuras.Options:ApplyTextSizeChange("Buff")
end)
BoxxyAuras.Options.BuffTextSizeSlider = buffTextSizeSlider

-- Buff Border Size Slider
local buffBorderSizeSlider = buffContainer:AddSlider("Buff Border Size", 0, 3, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.borderSize = value
    BoxxyAuras.Options:ApplyBorderSizeChange("Buff")
end)
BoxxyAuras.Options.BuffBorderSizeSlider = buffBorderSizeSlider

-- Buff Icon Spacing Slider
local buffSpacingSlider = buffContainer:AddSlider("Buff Icon Spacing", -10, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
    settings.buffFrameSettings.iconSpacing = value
    BoxxyAuras.Options:ApplyIconSpacingChange("Buff")
end)
BoxxyAuras.Options.BuffSpacingSlider = buffSpacingSlider

-- Update reference for next container
lastContainer = buffContainer

--[[--------------------------
-- Debuff Settings Container
----------------------------]]
local debuffContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Debuff Settings")
debuffContainer:SetPosition("TOPLEFT", lastContainer:GetFrame(), "BOTTOMLEFT", 0, -15)

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
local debuffSizeSlider = debuffContainer:AddSlider("Debuff Icon Size", 12, 64, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.iconSize = value
    BoxxyAuras.Options:ApplyIconSizeChange("Debuff")
end)
BoxxyAuras.Options.DebuffSizeSlider = debuffSizeSlider

-- Debuff Text Size Slider
local debuffTextSizeSlider = debuffContainer:AddSlider("Debuff Text Size", 6, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.textSize = value
    BoxxyAuras.Options:ApplyTextSizeChange("Debuff")
end)
BoxxyAuras.Options.DebuffTextSizeSlider = debuffTextSizeSlider

-- Debuff Border Size Slider
local debuffBorderSizeSlider = debuffContainer:AddSlider("Debuff Border Size", 0, 3, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.borderSize = value
    BoxxyAuras.Options:ApplyBorderSizeChange("Debuff")
end)
BoxxyAuras.Options.DebuffBorderSizeSlider = debuffBorderSizeSlider

-- Debuff Icon Spacing Slider
local debuffSpacingSlider = debuffContainer:AddSlider("Debuff Icon Spacing", -10, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
    settings.debuffFrameSettings.iconSpacing = value
    BoxxyAuras.Options:ApplyIconSpacingChange("Debuff")
end)
BoxxyAuras.Options.DebuffSpacingSlider = debuffSpacingSlider

-- Update reference for next container
lastContainer = debuffContainer

--[[--------------------------
-- Custom Settings Container
----------------------------]]
local customContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Custom Settings")
customContainer:SetPosition("TOPLEFT", lastContainer:GetFrame(), "BOTTOMLEFT", 0, -15)

-- Custom Text Alignment
local customAlignCheckboxes = customContainer:AddCheckboxRow(
    { { text = "Left", value = "LEFT" }, { text = "Center", value = "CENTER" }, { text = "Right", value = "RIGHT" } },
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.customFrameSettings then settings.customFrameSettings = {} end
        settings.customFrameSettings.customTextAlign = value
        BoxxyAuras.Options:ApplyTextAlign("Custom")
    end
)
BoxxyAuras.Options.CustomAlignCheckboxes = customAlignCheckboxes

-- Add spacer before wrap direction
customContainer:AddSpacer()

-- Custom Wrap Direction
local customWrapCheckboxes = customContainer:AddCheckboxRow(
    { { text = "Wrap Down", value = "DOWN" }, { text = "Wrap Up", value = "UP" } },
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.customFrameSettings then settings.customFrameSettings = {} end
        settings.customFrameSettings.wrapDirection = value
        BoxxyAuras.Options:ApplyWrapDirection("Custom")
    end
)
BoxxyAuras.Options.CustomWrapCheckboxes = customWrapCheckboxes

-- Add spacer between alignment and sliders
customContainer:AddSpacer()

-- Custom Icon Size Slider
local customSizeSlider = customContainer:AddSlider("Custom Icon Size", 12, 64, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.customFrameSettings then settings.customFrameSettings = {} end
    settings.customFrameSettings.iconSize = value
    BoxxyAuras.Options:ApplyIconSizeChange("Custom")
end)
BoxxyAuras.Options.CustomSizeSlider = customSizeSlider

-- Custom Text Size Slider
local customTextSizeSlider = customContainer:AddSlider("Custom Text Size", 6, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.customFrameSettings then settings.customFrameSettings = {} end
    settings.customFrameSettings.textSize = value
    BoxxyAuras.Options:ApplyTextSizeChange("Custom")
end)
BoxxyAuras.Options.CustomTextSizeSlider = customTextSizeSlider

-- Custom Border Size Slider
local customBorderSizeSlider = customContainer:AddSlider("Custom Border Size", 0, 3, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.customFrameSettings then settings.customFrameSettings = {} end
    settings.customFrameSettings.borderSize = value
    BoxxyAuras.Options:ApplyBorderSizeChange("Custom")
end)
BoxxyAuras.Options.CustomBorderSizeSlider = customBorderSizeSlider

-- Custom Icon Spacing Slider
local customSpacingSlider = customContainer:AddSlider("Custom Icon Spacing", -10, 20, 1, function(value)
    local settings = GetCurrentProfileSettings()
    if not settings.customFrameSettings then settings.customFrameSettings = {} end
    settings.customFrameSettings.iconSpacing = value
    BoxxyAuras.Options:ApplyIconSpacingChange("Custom")
end)
BoxxyAuras.Options.CustomSpacingSlider = customSpacingSlider

-- Button to Open Custom Aura Options
local customOptionsButton = customContainer:AddButton("Set Custom Auras", nil, function()
    if _G.BoxxyAuras and _G.BoxxyAuras.CustomOptions and _G.BoxxyAuras.CustomOptions.Toggle then
        _G.BoxxyAuras.CustomOptions:Toggle()
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.OpenCustomOptionsButton = customOptionsButton

-- Update reference for next container
lastContainer = customContainer

--[[------------------------------------------------------------
-- Global Settings Container
--------------------------------------------------------------]]
local globalContainer = BoxxyAuras.UIBuilder.CreateContainer(contentFrame, "Global Scale")
globalContainer:SetPosition("TOPLEFT", lastContainer:GetFrame(), "BOTTOMLEFT", 0, -15)

-- Global Scale Slider
local scaleSlider = globalContainer:AddSlider("", 0.5, 2.0, 0.05, function(value)
    -- Update saved variable but do NOT immediately rescale the options window.
    local currentSettings = GetCurrentProfileSettings()
    if currentSettings then
        currentSettings.optionsScale = value
    end
end, false) -- instantCallback: false (debounced)

BoxxyAuras.Options.ScaleSlider = scaleSlider

-- Apply the scale only when the user releases the mouse button on the slider
if scaleSlider then
    scaleSlider:HookScript("OnMouseUp", function(self)
        local val = self:GetValue()
        if BoxxyAuras.Options and BoxxyAuras.Options.ApplyScale then
            BoxxyAuras.Options:ApplyScale(val)
        end
    end)
end

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

    -- Note: Demo mode is transient, not saved, so it's not loaded here.
    -- It should be off by default when opening the panel.
    self.DemoModeCheck:SetChecked(self.demoModeActive or false)

    -- Load Normal Border Color
    self:UpdateNormalBorderColorSwatch()

    -- Load Background Color
    self:UpdateBackgroundColorSwatch()

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

    -- Load Custom Frame Settings
    if settings.customFrameSettings then
        -- Custom Icon Size
        if self.CustomSizeSlider and settings.customFrameSettings.iconSize then
            self.CustomSizeSlider:SetValue(settings.customFrameSettings.iconSize)
        end

        -- Custom Text Size
        if self.CustomTextSizeSlider and settings.customFrameSettings.textSize then
            self.CustomTextSizeSlider:SetValue(settings.customFrameSettings.textSize)
        end

        -- Custom Border Size
        if self.CustomBorderSizeSlider and settings.customFrameSettings.borderSize then
            self.CustomBorderSizeSlider:SetValue(settings.customFrameSettings.borderSize)
        end

        -- Custom Icon Spacing
        if self.CustomSpacingSlider and settings.customFrameSettings.iconSpacing then
            self.CustomSpacingSlider:SetValue(settings.customFrameSettings.iconSpacing)
        end

        -- Custom Text Alignment
        if self.CustomAlignCheckboxes and settings.customFrameSettings.customTextAlign then
            BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.CustomAlignCheckboxes,
                settings.customFrameSettings.customTextAlign)
        end

        -- Custom Wrap Direction
        if self.CustomWrapCheckboxes and settings.customFrameSettings.wrapDirection then
            BoxxyAuras.UIBuilder.SetCheckboxRowValue(self.CustomWrapCheckboxes,
                settings.customFrameSettings.wrapDirection)
        end
    end

    -- Load Global Settings
    if self.ScaleSlider and settings.optionsScale then
        -- Ensure scale value is valid (greater than 0)
        local scaleValue = settings.optionsScale
        if scaleValue <= 0 then
            scaleValue = 1.0                   -- Default to 1.0 if invalid
            settings.optionsScale = scaleValue -- Update the settings too
        end
        self.ScaleSlider:SetValue(scaleValue)
        -- Apply the saved scale immediately on load so the UI reflects the correct size
        if self.ApplyScale then
            self:ApplyScale(scaleValue)
        end
    elseif self.ScaleSlider then
        -- If no scale setting exists, set default value
        self.ScaleSlider:SetValue(1.0)
        if self.ApplyScale then
            self:ApplyScale(1.0)
        end
        if settings then
            settings.optionsScale = 1.0
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
        local frameTypes = { "Buff", "Debuff", "Custom" }
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

-- Set demo mode on/off
function BoxxyAuras.Options:SetDemoMode(enable)
    -- Cancel any pending layout updates to prevent conflicts
    self:CancelAllUpdateTimers()

    self.demoModeActive = enable

    if enable then
        print("|cff00FF00BoxxyAuras:|r Demo mode enabled - showing test auras.")

        -- Create some test auras for each frame type
        if not BoxxyAuras.demoAuras then
            BoxxyAuras.demoAuras = {
                Buff = {
                    {
                        name = "Demo Blessing",
                        icon = "Interface\\Icons\\Spell_Holy_GreaterBlessofKings",
                        duration = 300,
                        expirationTime = GetTime() + 300,
                        applications = 1,
                        spellId = 12345,
                        auraInstanceID = "demo_buff_1"
                    },
                    {
                        name = "Demo Shield",
                        icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
                        duration = 0, -- Permanent
                        expirationTime = 0,
                        applications = 3,
                        spellId = 12346,
                        auraInstanceID = "demo_buff_2"
                    },
                    {
                        name = "Demo Haste",
                        icon = "Interface\\Icons\\Spell_Nature_Bloodlust",
                        duration = 120,
                        expirationTime = GetTime() + 120,
                        applications = 1,
                        spellId = 12347,
                        auraInstanceID = "demo_buff_3"
                    },
                    {
                        name = "Demo Strength",
                        icon = "Interface\\Icons\\Spell_Holy_GreaterBlessofWisdom",
                        duration = 600,
                        expirationTime = GetTime() + 600,
                        applications = 1,
                        spellId = 12348,
                        auraInstanceID = "demo_buff_4"
                    },
                    {
                        name = "Demo Intellect",
                        icon = "Interface\\Icons\\Spell_Holy_MindVision",
                        duration = 450,
                        expirationTime = GetTime() + 450,
                        applications = 1,
                        spellId = 12349,
                        auraInstanceID = "demo_buff_5"
                    },
                    {
                        name = "Demo Regeneration",
                        icon = "Interface\\Icons\\Spell_Nature_Rejuvenation",
                        duration = 90,
                        expirationTime = GetTime() + 90,
                        applications = 1,
                        spellId = 12350,
                        auraInstanceID = "demo_buff_6"
                    },
                    {
                        name = "Demo Fortitude",
                        icon = "Interface\\Icons\\Spell_Holy_PrayerofFortitude",
                        duration = 1800,
                        expirationTime = GetTime() + 1800,
                        applications = 1,
                        spellId = 12351,
                        auraInstanceID = "demo_buff_7"
                    },
                    {
                        name = "Demo Spirit",
                        icon = "Interface\\Icons\\Spell_Holy_PrayerofSpirit",
                        duration = 1200,
                        expirationTime = GetTime() + 1200,
                        applications = 1,
                        spellId = 12352,
                        auraInstanceID = "demo_buff_8"
                    }
                },
                Debuff = {
                    {
                        name = "Demo Curse",
                        icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
                        duration = 60,
                        expirationTime = GetTime() + 60,
                        applications = 1,
                        spellId = 22345,
                        auraInstanceID = "demo_debuff_1",
                        dispelName = "CURSE"
                    },
                    {
                        name = "Demo Poison",
                        icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
                        duration = 45,
                        expirationTime = GetTime() + 45,
                        applications = 2,
                        spellId = 22346,
                        auraInstanceID = "demo_debuff_2",
                        dispelName = "POISON"
                    },
                    {
                        name = "Demo Disease",
                        icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
                        duration = 30,
                        expirationTime = GetTime() + 30,
                        applications = 1,
                        spellId = 22347,
                        auraInstanceID = "demo_debuff_3",
                        dispelName = "DISEASE"
                    },
                    {
                        name = "Demo Magic Debuff",
                        icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
                        duration = 25,
                        expirationTime = GetTime() + 25,
                        applications = 1,
                        spellId = 22348,
                        auraInstanceID = "demo_debuff_4",
                        dispelName = "MAGIC"
                    },
                    {
                        name = "Demo Weakness",
                        icon = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth",
                        duration = 40,
                        expirationTime = GetTime() + 40,
                        applications = 1,
                        spellId = 22349,
                        auraInstanceID = "demo_debuff_5"
                    },
                    {
                        name = "Demo Slow",
                        icon = "Interface\\Icons\\Spell_Frost_FrostShock",
                        duration = 15,
                        expirationTime = GetTime() + 15,
                        applications = 1,
                        spellId = 22350,
                        auraInstanceID = "demo_debuff_6"
                    }
                },
                Custom = {
                    {
                        name = "Demo Custom Aura",
                        icon = "Interface\\Icons\\Spell_Arcane_TeleportStormwind",
                        duration = 180,
                        expirationTime = GetTime() + 180,
                        applications = 1,
                        spellId = 32345,
                        auraInstanceID = "demo_custom_1"
                    },
                    {
                        name = "Demo Tracking",
                        icon = "Interface\\Icons\\Spell_Nature_FaerieFire",
                        duration = 0, -- Permanent
                        expirationTime = 0,
                        applications = 1,
                        spellId = 32346,
                        auraInstanceID = "demo_custom_2"
                    },
                    {
                        name = "Demo Enchant",
                        icon = "Interface\\Icons\\Spell_Holy_GreaterHeal",
                        duration = 300,
                        expirationTime = GetTime() + 300,
                        applications = 1,
                        spellId = 32347,
                        auraInstanceID = "demo_custom_3"
                    },
                    {
                        name = "Demo Proc",
                        icon = "Interface\\Icons\\Spell_Lightning_LightningBolt01",
                        duration = 12,
                        expirationTime = GetTime() + 12,
                        applications = 5,
                        spellId = 32348,
                        auraInstanceID = "demo_custom_4"
                    }
                }
            }
        end

        -- Update expiration times for demo auras
        for frameType, auras in pairs(BoxxyAuras.demoAuras) do
            for _, aura in ipairs(auras) do
                if aura.duration > 0 then
                    aura.expirationTime = GetTime() + aura.duration
                end
            end
        end
    else
        print("|cff00FF00BoxxyAuras:|r Demo mode disabled.")

        -- Clear demo auras
        if BoxxyAuras.demoAuras then
            BoxxyAuras.demoAuras = nil
        end
    end

    -- Force a complete refresh to properly reset all icons when demo mode changes
    -- This ensures any lingering OnUpdate scripts or state from demo auras are cleaned up
    -- Add a small delay to prevent performance issues when creating many demo auras
    C_Timer.After(0.1, function()
        BoxxyAuras.UpdateAuras(true)
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

        local frameTypes = { "Buff", "Debuff", "Custom" }
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
