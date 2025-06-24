local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {} -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras -- Create a convenient local alias to the global table
BoxxyAuras.Options = {} -- Table to hold options elements

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
        for _, fType in ipairs({"Buff", "Debuff", "Custom"}) do
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
end

-- Apply global scale changes
function BoxxyAuras.Options:ApplyScale(scale)
    -- Validate scale value - must be greater than 0
    if not scale or scale <= 0 then
        if BoxxyAuras.DEBUG then
            print("|cffFF0000BoxxyAuras Error:|r Invalid scale value: " .. tostring(scale) .. ". Using default scale of 1.0")
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
    end
end

--[[------------------------------------------------------------
-- Create Main Options Frame
--------------------------------------------------------------]]
local optionsFrame = CreateFrame("Frame", "BoxxyAurasOptionsFrame", UIParent, "BackdropTemplate")
optionsFrame:SetSize(300, 500) -- Adjusted size
optionsFrame:SetPoint("CENTER", UIParent, "CENTER")
optionsFrame:SetFrameStrata("MEDIUM")
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
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
bg:SetAllPoints();
bg:SetFrameLevel(optionsFrame:GetFrameLevel());
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(bg, "OptionsWindowBG", "backdrop", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(bg, "backdrop", 1, 1, 1, 0.95)
else
    -- print("|cffFF0000BoxxyAuras Options Error:|r Could not draw background.")
end

local border = CreateFrame("Frame", nil, optionsFrame);
border:SetAllPoints();
border:SetFrameLevel(optionsFrame:GetFrameLevel() + 1);
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(border, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(border, "border", 0.4, 0.4, 0.4, 1)
else
    -- print("|cffFF0000BoxxyAuras Options Error:|r Could not draw border.")
end

-- Title
local title = optionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Title")
title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -23)
title:SetText("BoxxyAuras Options")

-- <<< ADDED: Version Text >>>
local versionText = optionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Vers") -- Use a smaller font
versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2) -- Position below title
local versionString = "v" .. (BoxxyAuras and BoxxyAuras.Version or "?.?.?") -- Get version safely
versionText:SetText(versionString)
versionText:SetTextColor(0.7, 0.7, 0.7, 0.9) -- Slightly greyed out
BoxxyAuras.Options.VersionText = versionText -- Store reference if needed
-- <<< END Version Text >>>

-- Close Button
local closeBtn = CreateFrame("Button", "BoxxyAurasOptionsCloseButton", optionsFrame, "BAURASCloseBtn")
closeBtn:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -12, -12)
closeBtn:SetSize(12, 12)
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
scrollFrame:SetPoint("TOPLEFT", 10, -50)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

-- <<< ADDED: Adjust Mouse Wheel Scroll Speed >>>
local SCROLL_STEP_REDUCTION_FACTOR = 0.9 -- Adjust this value (e.g., 0.5 for half speed)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local scrollBar = _G[self:GetName() .. "ScrollBar"];
    local currentStep = SCROLL_FRAME_SCROLL_STEP or 16 -- Use default Blizzard step or fallback
    local newStep = math.max(1, math.floor(currentStep * SCROLL_STEP_REDUCTION_FACTOR)) -- Reduce step, ensure at least 1

    if (delta > 0) then
        scrollBar:SetValue(scrollBar:GetValue() - newStep);
    else
        scrollBar:SetValue(scrollBar:GetValue() + newStep);
    end
end);
-- <<< END Scroll Speed Adjustment >>>

local contentFrame = CreateFrame("Frame", "BoxxyAurasOptionsContentFrame", scrollFrame)
contentFrame:SetSize(scrollFrame:GetWidth(), 700) -- <<< Increased height significantly >>>
scrollFrame:SetScrollChild(contentFrame)

-- Layout Variables
local lastElement = contentFrame -- Start anchoring groups to the top of contentFrame
local verticalSpacing = -10 -- Reduced initial spacing from top (was -15)
local groupPadding = 10 -- Internal padding for group boxes
local groupWidth = contentFrame:GetWidth() - (groupPadding * 2)
local lastInGroup = nil -- Will track last element within a group
local groupVSpacing = 0 -- Will track vertical spacing within a group
local checkboxSpacing = 49 -- <<< Reduced spacing further >>>
local internalElementVSpacing = -12 -- << NEW: Standardized spacing between elements

--[[------------------------------------------------------------
-- Group 0: Profile Management
--------------------------------------------------------------]]
local profileGroup = BoxxyAuras.UIBuilder.CreateGroup(contentFrame, nil, verticalSpacing)

-- Profile Selection Header and Dropdown
local profileSelectHeader, profileSelectHeaderHeight = BoxxyAuras.UIBuilder.CreateSectionHeader(profileGroup, "Current Profile", nil)
BoxxyAuras.Options.ProfileSelectLabel = profileSelectHeader
BoxxyAuras.UIBuilder.AddElementToGroup(profileGroup, profileSelectHeader, profileSelectHeaderHeight)

-- Profile Selection Dropdown (manual creation but positioned using UIBuilder spacing)
local profileDropdown = CreateFrame("Frame", "BoxxyAurasProfileDropdown", profileGroup, "UIDropDownMenuTemplate")
profileDropdown:SetWidth(180)
profileDropdown:SetPoint("TOPLEFT", profileSelectHeader, "BOTTOMLEFT", 5, -8) -- Reduced spacing
profileDropdown:SetFrameLevel(profileGroup:GetFrameLevel() + 2)
BoxxyAuras.Options.ProfileDropdown = profileDropdown

-- Center Dropdown Text
local dropdownText = _G[profileDropdown:GetName() .. "Text"]
if dropdownText then
    dropdownText:SetJustifyH("CENTER")
    dropdownText:ClearAllPoints()
    dropdownText:SetPoint("CENTER", profileDropdown, "CENTER", 0, 0)
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
arrow:SetSize(16, 16)
arrow:SetPoint("RIGHT", profileDropdown, "RIGHT", -8, 0)
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

-- Add dropdown to group tracking
BoxxyAuras.UIBuilder.AddElementToGroup(profileGroup, profileDropdown, 30)

-- Profile Actions Header
local profileActionHeader, profileActionHeaderHeight = BoxxyAuras.UIBuilder.CreateSectionHeader(profileGroup, "Profile Actions", profileGroup.lastElement)
BoxxyAuras.Options.ProfileActionLabel = profileActionHeader
BoxxyAuras.UIBuilder.AddElementToGroup(profileGroup, profileActionHeader, profileActionHeaderHeight)

-- Profile Name EditBox
local profileNameEditBox = CreateFrame("EditBox", "BoxxyAurasProfileNameEditBox", profileGroup, "InputBoxTemplate")
profileNameEditBox:SetPoint("TOPLEFT", profileActionHeader, "BOTTOMLEFT", 5, -8) -- Reduced spacing
profileNameEditBox:SetWidth(profileGroup:GetWidth() - 20)
profileNameEditBox:SetHeight(20)
profileNameEditBox:SetAutoFocus(false)
profileNameEditBox:SetMaxLetters(32)
profileNameEditBox:SetTextInsets(5, 5, 0, 0)
profileNameEditBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
profileNameEditBox:SetScript("OnEnterPressed", function(self)
    local name = self:GetText()
    if name and name ~= "" then
        self:SetText("")
        self:ClearFocus()
    end
end)
BoxxyAuras.Options.ProfileNameEditBox = profileNameEditBox
BoxxyAuras.UIBuilder.AddElementToGroup(profileGroup, profileNameEditBox, 25)

-- Create Profile Button
local createButton, createButtonHeight = BoxxyAuras.UIBuilder.CreateButton(
    profileGroup, "Create Profile", 60, profileGroup.lastElement,
    function()
        local name = BoxxyAuras.Options.ProfileNameEditBox:GetText()
        if name and name ~= "" then
            BoxxyAuras.Options:CreateProfile(name)
            BoxxyAuras.Options.ProfileNameEditBox:SetText("")
        end
        PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end
)
BoxxyAuras.Options.CreateProfileButton = createButton
BoxxyAuras.UIBuilder.AddElementToGroup(profileGroup, createButton, createButtonHeight)

-- Copy Profile Button (positioned next to Create button)
local copyButton = CreateFrame("Button", "BoxxyAurasCopyProfileButton", profileGroup, "BAURASButtonTemplate")
copyButton:SetPoint("LEFT", createButton, "RIGHT", 5, 0)
copyButton:SetWidth(60)
copyButton:SetHeight(25)
copyButton:SetText("Copy")
copyButton:SetScript("OnClick", function()
    local name = BoxxyAuras.Options.ProfileNameEditBox:GetText()
    if name and name ~= "" then
        BoxxyAuras.Options:CopyProfile(name)
        BoxxyAuras.Options.ProfileNameEditBox:SetText("")
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.CopyProfileButton = copyButton

-- Delete Profile Button (positioned next to Copy button)
local deleteButton = CreateFrame("Button", "BoxxyAurasDeleteProfileButton", profileGroup, "BAURASButtonTemplate")
deleteButton:SetPoint("LEFT", copyButton, "RIGHT", 5, 0)
deleteButton:SetWidth(60)
deleteButton:SetHeight(25)
deleteButton:SetText("Delete")
deleteButton:SetScript("OnClick", function(self)
    if not self:IsEnabled() then
        return
    end
    local selectedProfile = BoxxyAurasDB and BoxxyAurasDB.activeProfile
    if selectedProfile then
        StaticPopup_Show("BOXXYAURAS_DELETE_PROFILE_CONFIRM", selectedProfile)
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.DeleteProfileButton = deleteButton

-- Update lastElement for next group positioning
lastElement = profileGroup
verticalSpacing = -10 -- Reduced space between groups

--[[------------------------------------------------------------
-- Group 1: General Settings
--------------------------------------------------------------]]
local generalGroup = BoxxyAuras.UIBuilder.CreateGroup(contentFrame, lastElement, verticalSpacing)

-- General Settings Header
local generalHeader, generalHeaderHeight = BoxxyAuras.UIBuilder.CreateSectionHeader(generalGroup, "General Settings", nil)
BoxxyAuras.UIBuilder.AddElementToGroup(generalGroup, generalHeader, generalHeaderHeight)

-- Lock Frames Checkbox
local lockFramesCheck = CreateFrame("CheckButton", "BoxxyAurasLockFramesCheckButton", generalGroup, "BAURASCheckBoxTemplate")
lockFramesCheck:SetPoint("TOPLEFT", generalHeader, "BOTTOMLEFT", 5, -8) -- Reduced spacing
lockFramesCheck:SetText("Lock Frames")
lockFramesCheck:SetScript("OnClick", function(self)
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
BoxxyAuras.UIBuilder.AddElementToGroup(generalGroup, lockFramesCheck, 20)

-- Hide Blizzard Auras Checkbox
local hideBlizzardCheck = CreateFrame("CheckButton", "BoxxyAurasHideBlizzardCheckButton", generalGroup, "BAURASCheckBoxTemplate")
hideBlizzardCheck:SetPoint("TOPLEFT", lockFramesCheck, "BOTTOMLEFT", 0, -8) -- Reduced spacing
hideBlizzardCheck:SetText("Hide Default Blizzard Auras")
hideBlizzardCheck:SetScript("OnClick", function(self)
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
BoxxyAuras.UIBuilder.AddElementToGroup(generalGroup, hideBlizzardCheck, 20)

-- Demo Mode Checkbox
local demoModeCheck = CreateFrame("CheckButton", "BoxxyAurasDemoModeCheckButton", generalGroup, "BAURASCheckBoxTemplate")
demoModeCheck:SetPoint("TOPLEFT", hideBlizzardCheck, "BOTTOMLEFT", 0, -8) -- Reduced spacing
demoModeCheck:SetText("Demo Mode (Show Test Auras)")
demoModeCheck:SetScript("OnClick", function(self)
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
BoxxyAuras.UIBuilder.AddElementToGroup(generalGroup, demoModeCheck, 20)

-- Update lastElement for next group positioning
lastElement = generalGroup
verticalSpacing = -10 -- Space between groups

--[[------------------------------------------------------------
-- Group 2: Display Frame Settings (Alignment & Size)
--------------------------------------------------------------]]
local subGroupVerticalSpacing = -20 -- Spacing between sub-groups

local currentSettings = GetCurrentProfileSettings() -- Get settings once at the top

--[[------------------------
-- Sub-Group 1: Buffs
--------------------------]]
local buffSubGroup = BoxxyAuras.UIBuilder.CreateGroup(contentFrame, lastElement, verticalSpacing)
lastElement = buffSubGroup -- The next group will anchor to this one

-- Buff Text Alignment
local buffAlignCheckboxes, buffAlignHeader, buffAlignHeight = BoxxyAuras.UIBuilder.CreateMultipleChoiceGroup(
    buffSubGroup, "Buff Text Alignment", {{text = "Left", value = "LEFT"}, {text = "Center", value = "CENTER"}, {text = "Right", value = "RIGHT"}},
    buffSubGroup.lastElement,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
        settings.buffFrameSettings.buffTextAlign = value
        BoxxyAuras.Options:ApplyTextAlign("Buff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(buffSubGroup, buffAlignCheckboxes[1], buffAlignHeight)
BoxxyAuras.Options.BuffAlignCheckboxes = buffAlignCheckboxes -- Store the table of checkboxes

-- Buff Icon Size Slider
local buffSizeSlider, buffSizeLabel, buffSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    buffSubGroup, "Buff Icon Size", 12, 64, 1, buffSubGroup.lastElement, false,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
        settings.buffFrameSettings.iconSize = value
        BoxxyAuras.Options:ApplyIconSizeChange("Buff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(buffSubGroup, buffSizeSlider, buffSizeHeight)
BoxxyAuras.Options.BuffSizeSlider = buffSizeSlider

-- Buff Text Size Slider
local buffTextSizeSlider, buffTextSizeLabel, buffTextSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    buffSubGroup, "Buff Text Size", 6, 20, 1, buffSubGroup.lastElement, true,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
        settings.buffFrameSettings.textSize = value
        BoxxyAuras.Options:ApplyTextSizeChange("Buff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(buffSubGroup, buffTextSizeSlider, buffTextSizeHeight)
BoxxyAuras.Options.BuffTextSizeSlider = buffTextSizeSlider

-- Buff Border Size Slider
local buffBorderSizeSlider, buffBorderSizeLabel, buffBorderSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    buffSubGroup, "Buff Border Size", 0, 5, 1, buffSubGroup.lastElement, true,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.buffFrameSettings then settings.buffFrameSettings = {} end
        settings.buffFrameSettings.borderSize = value
        BoxxyAuras.Options:ApplyBorderSizeChange("Buff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(buffSubGroup, buffBorderSizeSlider, buffBorderSizeHeight)
BoxxyAuras.Options.BuffBorderSizeSlider = buffBorderSizeSlider

--[[--------------------------
-- Sub-Group 2: Debuffs
----------------------------]]
local debuffSubGroup = BoxxyAuras.UIBuilder.CreateGroup(contentFrame, lastElement, subGroupVerticalSpacing)
lastElement = debuffSubGroup

-- Debuff Text Alignment
local debuffAlignCheckboxes, debuffAlignHeader, debuffAlignHeight = BoxxyAuras.UIBuilder.CreateMultipleChoiceGroup(
    debuffSubGroup, "Debuff Text Alignment", {{text = "Left", value = "LEFT"}, {text = "Center", value = "CENTER"}, {text = "Right", value = "RIGHT"}},
    debuffSubGroup.lastElement,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
        settings.debuffFrameSettings.debuffTextAlign = value
        BoxxyAuras.Options:ApplyTextAlign("Debuff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(debuffSubGroup, debuffAlignCheckboxes[1], debuffAlignHeight)
BoxxyAuras.Options.DebuffAlignCheckboxes = debuffAlignCheckboxes

-- Debuff Icon Size Slider
local debuffSizeSlider, debuffSizeLabel, debuffSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    debuffSubGroup, "Debuff Icon Size", 12, 64, 1, debuffSubGroup.lastElement, false,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
        settings.debuffFrameSettings.iconSize = value
        BoxxyAuras.Options:ApplyIconSizeChange("Debuff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(debuffSubGroup, debuffSizeSlider, debuffSizeHeight)
BoxxyAuras.Options.DebuffSizeSlider = debuffSizeSlider

-- Debuff Text Size Slider
local debuffTextSizeSlider, debuffTextSizeLabel, debuffTextSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    debuffSubGroup, "Debuff Text Size", 6, 20, 1, debuffSubGroup.lastElement, true,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
        settings.debuffFrameSettings.textSize = value
        BoxxyAuras.Options:ApplyTextSizeChange("Debuff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(debuffSubGroup, debuffTextSizeSlider, debuffTextSizeHeight)
BoxxyAuras.Options.DebuffTextSizeSlider = debuffTextSizeSlider

-- Debuff Border Size Slider
local debuffBorderSizeSlider, debuffBorderSizeLabel, debuffBorderSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    debuffSubGroup, "Debuff Border Size", 0, 5, 1, debuffSubGroup.lastElement, true,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.debuffFrameSettings then settings.debuffFrameSettings = {} end
        settings.debuffFrameSettings.borderSize = value
        BoxxyAuras.Options:ApplyBorderSizeChange("Debuff")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(debuffSubGroup, debuffBorderSizeSlider, debuffBorderSizeHeight)
BoxxyAuras.Options.DebuffBorderSizeSlider = debuffBorderSizeSlider

--[[--------------------------
-- Sub-Group 3: Custom
----------------------------]]
local customSubGroup = BoxxyAuras.UIBuilder.CreateGroup(contentFrame, lastElement, subGroupVerticalSpacing)
lastElement = customSubGroup

-- Custom Text Alignment
local customAlignCheckboxes, customAlignHeader, customAlignHeight = BoxxyAuras.UIBuilder.CreateMultipleChoiceGroup(
    customSubGroup, "Custom Text Alignment", {{text = "Left", value = "LEFT"}, {text = "Center", value = "CENTER"}, {text = "Right", value = "RIGHT"}},
    customSubGroup.lastElement,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.customFrameSettings then settings.customFrameSettings = {} end
        settings.customFrameSettings.customTextAlign = value
        BoxxyAuras.Options:ApplyTextAlign("Custom")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(customSubGroup, customAlignCheckboxes[1], customAlignHeight)
BoxxyAuras.Options.CustomAlignCheckboxes = customAlignCheckboxes

-- Custom Icon Size Slider
local customSizeSlider, customSizeLabel, customSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    customSubGroup, "Custom Icon Size", 12, 64, 1, customSubGroup.lastElement, false,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.customFrameSettings then settings.customFrameSettings = {} end
        settings.customFrameSettings.iconSize = value
        BoxxyAuras.Options:ApplyIconSizeChange("Custom")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(customSubGroup, customSizeSlider, customSizeHeight)
BoxxyAuras.Options.CustomSizeSlider = customSizeSlider

-- Custom Text Size Slider
local customTextSizeSlider, customTextSizeLabel, customTextSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    customSubGroup, "Custom Text Size", 6, 20, 1, customSubGroup.lastElement, true,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.customFrameSettings then settings.customFrameSettings = {} end
        settings.customFrameSettings.textSize = value
        BoxxyAuras.Options:ApplyTextSizeChange("Custom")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(customSubGroup, customTextSizeSlider, customTextSizeHeight)
BoxxyAuras.Options.CustomTextSizeSlider = customTextSizeSlider

-- Custom Border Size Slider
local customBorderSizeSlider, customBorderSizeLabel, customBorderSizeHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    customSubGroup, "Custom Border Size", 0, 5, 1, customSubGroup.lastElement, true,
    function(value)
        local settings = GetCurrentProfileSettings()
        if not settings.customFrameSettings then settings.customFrameSettings = {} end
        settings.customFrameSettings.borderSize = value
        BoxxyAuras.Options:ApplyBorderSizeChange("Custom")
    end
)
BoxxyAuras.UIBuilder.AddElementToGroup(customSubGroup, customBorderSizeSlider, customBorderSizeHeight)
BoxxyAuras.Options.CustomBorderSizeSlider = customBorderSizeSlider

-- Button to Open Custom Aura Options
local customOptionsButton, customOptionsButtonHeight = BoxxyAuras.UIBuilder.CreateButton(
    customSubGroup, "Set Custom Auras", nil, customSubGroup.lastElement,
    function()
        if _G.BoxxyAuras and _G.BoxxyAuras.CustomOptions and _G.BoxxyAuras.CustomOptions.Toggle then
            _G.BoxxyAuras.CustomOptions:Toggle()
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end,
    true -- Extra spacing since this follows a slider
)
BoxxyAuras.UIBuilder.AddElementToGroup(customSubGroup, customOptionsButton, customOptionsButtonHeight)
BoxxyAuras.Options.OpenCustomOptionsButton = customOptionsButton

-- Calculate MAIN Display Group Height (based on its children)
local totalDisplayHeight = buffSubGroup:GetHeight() + debuffSubGroup:GetHeight() + customSubGroup:GetHeight() + (subGroupVerticalSpacing * 2) + 10 -- Add final padding
-- The line above seems to reference a displayGroup that no longer exists. I'll just remove this for now as the groups manage their own height.

-- Update lastElement for next group positioning
lastElement = customSubGroup -- Update this to the last created subgroup
verticalSpacing = -20 -- Space between main groups

--[[------------------------------------------------------------
-- Group 3: Global Settings
--------------------------------------------------------------]]
local globalGroup = BoxxyAuras.UIBuilder.CreateGroup(contentFrame, lastElement, verticalSpacing)

-- Global Settings Header
local globalHeader, globalHeaderHeight = BoxxyAuras.UIBuilder.CreateSectionHeader(globalGroup, "Global Settings", nil)
BoxxyAuras.UIBuilder.AddElementToGroup(globalGroup, globalHeader, globalHeaderHeight)

-- Global Scale Slider
local scaleSlider, scaleLabel, scaleHeight = BoxxyAuras.UIBuilder.CreateSliderGroup(
    globalGroup, "Global Scale", 0.5, 2.0, 0.05, globalHeader, false,
    function(value)
        -- Update saved variable but do NOT immediately rescale the options window.
        local currentSettings = GetCurrentProfileSettings()
        if currentSettings then
            currentSettings.optionsScale = value
        end
    end,
    false -- <-- instantCallback: false (debounced)
)
BoxxyAuras.Options.ScaleSlider = scaleSlider
BoxxyAuras.UIBuilder.AddElementToGroup(globalGroup, scaleSlider, scaleHeight)

-- Apply the scale only when the user releases the mouse button on the slider
if scaleSlider then
    scaleSlider:HookScript("OnMouseUp", function(self)
        local val = self:GetValue()
        if BoxxyAuras.Options and BoxxyAuras.Options.ApplyScale then
            BoxxyAuras.Options:ApplyScale(val)
        end
    end)
end

-- Update lastElement for next group positioning
lastElement = globalGroup
verticalSpacing = -10 -- Space between groups

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

    -- Note: Demo mode is transient, not saved, so it's not loaded here.
    -- It should be off by default when opening the panel.
    self.DemoModeCheck:SetChecked(self.demoModeActive or false)

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
        
        -- Buff Text Alignment
        if self.BuffAlignCheckboxes and settings.buffFrameSettings.buffTextAlign then
            BoxxyAuras.UIBuilder.SetMultipleChoiceValue(self.BuffAlignCheckboxes, settings.buffFrameSettings.buffTextAlign)
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
        
        -- Debuff Text Alignment
        if self.DebuffAlignCheckboxes and settings.debuffFrameSettings.debuffTextAlign then
            BoxxyAuras.UIBuilder.SetMultipleChoiceValue(self.DebuffAlignCheckboxes, settings.debuffFrameSettings.debuffTextAlign)
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
        
        -- Custom Text Alignment
        if self.CustomAlignCheckboxes and settings.customFrameSettings.customTextAlign then
            BoxxyAuras.UIBuilder.SetMultipleChoiceValue(self.CustomAlignCheckboxes, settings.customFrameSettings.customTextAlign)
        end
    end

    -- Load Global Settings
    if self.ScaleSlider and settings.optionsScale then
        -- Ensure scale value is valid (greater than 0)
        local scaleValue = settings.optionsScale
        if scaleValue <= 0 then
            scaleValue = 1.0 -- Default to 1.0 if invalid
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
                BoxxyAuras:SwitchToProfile(profileName)
                BoxxyAuras.Options:UpdateProfileUI()
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
        
        -- Disable delete if only one profile or if current profile is "Default"
        local canDelete = profileCount > 1 and currentProfile ~= "Default"
        if canDelete then
            self.DeleteProfileButton:Enable()
        else
            self.DeleteProfileButton:Disable()
        end
    end
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
    self:UpdateProfileUI()
    self:InitializeProfileDropdown()
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
    self:UpdateProfileUI()
    self:InitializeProfileDropdown()
end

-- Set demo mode on/off
function BoxxyAuras.Options:SetDemoMode(enable)
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

    -- Finally, trigger a full aura update to reflect the new state
    BoxxyAuras.UpdateAuras()
end

-- Static Popup for Delete Profile Confirmation
StaticPopupDialogs["BOXXYAURAS_DELETE_PROFILE_CONFIRM"] = {
    text = "Are you sure you want to delete the profile '%s'? This action cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, profileName)
        if profileName and BoxxyAurasDB and BoxxyAurasDB.profiles then
            if BoxxyAurasDB.profiles[profileName] then
                BoxxyAurasDB.profiles[profileName] = nil
                print("|cff00FF00BoxxyAuras:|r Deleted profile '" .. profileName .. "'.")
                
                -- If we deleted the active profile, switch to Default
                if BoxxyAurasDB.activeProfile == profileName then
                    BoxxyAuras:SwitchToProfile("Default")
                end
                
                -- Update the UI
                if BoxxyAuras.Options then
                    BoxxyAuras.Options:UpdateProfileUI()
                    BoxxyAuras.Options:InitializeProfileDropdown()
                end
            else
                print("|cffFF0000BoxxyAuras:|r Profile '" .. profileName .. "' not found.")
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
    elseif command == "reset" then
        print("|cFF00FF00BoxxyAuras:|r Resetting frame positions...")
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        local defaultSettings = BoxxyAuras:GetDefaultProfileSettings() -- Get defaults for position/scale

        if not currentSettings or not defaultSettings then
            print("|cFFFF0000BoxxyAuras Error:|r Cannot get settings to reset positions.")
            return
        end

        local frameTypes = {"Buff", "Debuff", "Custom"}
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
                frame:SetPoint(defaultAnchor, UIParent, defaultAnchor, defaultX, defaultY)

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
        print("BoxxyAuras: Unknown command '/ba " .. command .. "'. Use '/ba options', '/ba lock', or '/ba reset'.")
    end
end
