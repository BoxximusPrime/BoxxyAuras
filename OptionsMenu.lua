local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}      -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras        -- Create a convenient local alias to the global table
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
            buffFrameSettings = { buffTextAlign = "CENTER", iconSize = 24 },
            debuffFrameSettings = { debuffTextAlign = "CENTER", iconSize = 24 },
            customFrameSettings = { customTextAlign = "CENTER", iconSize = 24 }
        }
    end
end

--[[------------------------------------------------------------
-- Create Main Options Frame
--------------------------------------------------------------]]
local optionsFrame = CreateFrame("Frame", "BoxxyAurasOptionsFrame", UIParent, "BackdropTemplate")
optionsFrame:SetSize(260, 500) -- Adjusted size
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
    if BoxxyAuras.Options.UpdateProfileUI then BoxxyAuras.Options:UpdateProfileUI() end
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
local scrollFrame = CreateFrame("ScrollFrame", "BoxxyAurasOptionsScrollFrame", optionsFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 10, -50)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local contentFrame = CreateFrame("Frame", "BoxxyAurasOptionsContentFrame", scrollFrame)
contentFrame:SetSize(scrollFrame:GetWidth(), 700) -- <<< Increased height significantly >>>
scrollFrame:SetScrollChild(contentFrame)

-- Layout Variables
local lastElement = contentFrame -- Start anchoring groups to the top of contentFrame
local verticalSpacing = -15 -- Initial spacing from top
local groupPadding = 10 -- Internal padding for group boxes
local groupWidth = contentFrame:GetWidth() - (groupPadding * 2)
local lastInGroup = nil -- Will track last element within a group
local groupVSpacing = 0 -- Will track vertical spacing within a group
local checkboxSpacing = 49 -- <<< Reduced spacing further >>>
local internalElementVSpacing = -12 -- << NEW: Standardized spacing between elements

--[[------------------------------------------------------------
-- Group 0: Profile Management (<< NEW GROUP >>)
--------------------------------------------------------------]]
local profileGroup = CreateFrame("Frame", "BoxxyAurasOptionsProfileGroup", contentFrame)
profileGroup:SetPoint("TOPLEFT", lastElement, "TOPLEFT", groupPadding, verticalSpacing) -- Position first group
profileGroup:SetWidth(groupWidth)
StyleGroupContainer(profileGroup) -- Use the helper to style it

lastInGroup = profileGroup -- Anchor first element to top of group
groupVSpacing = internalElementVSpacing

-- Profile Selection Dropdown Title
local profileSelectLabel = profileGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
profileSelectLabel:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
profileSelectLabel:SetText("|cffb9ac9dCurrent Profile|r")
BoxxyAuras.Options.ProfileSelectLabel = profileSelectLabel
lastInGroup = profileSelectLabel
groupVSpacing = -6

-- Profile Selection Dropdown
local profileDropdown = CreateFrame("Frame", "BoxxyAurasProfileDropdown", profileGroup, "UIDropDownMenuTemplate")
profileDropdown:SetWidth(180)
profileDropdown:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", -groupPadding + 2, groupVSpacing - 5) -- Position dropdown
profileDropdown:SetFrameLevel(profileGroup:GetFrameLevel() + 2) -- Ensure it's above the parent and its contents
BoxxyAuras.Options.ProfileDropdown = profileDropdown

-- <<< Center Dropdown Text >>>
local dropdownText = _G[profileDropdown:GetName() .. "Text"]
if dropdownText then
    dropdownText:SetJustifyH("CENTER")
    dropdownText:ClearAllPoints()
    dropdownText:SetPoint("CENTER", profileDropdown, "CENTER", 0, 0) -- Center explicitly
end
-- <<< END Center Text >>>

-- <<< ADD Styling for Dropdown >>>
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
    -- Background (using a texture similar to input boxes, slightly darker)
    BoxxyAuras.UIUtils.DrawSlicedBG(profileDropdown, "BtnBG", "backdrop", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(profileDropdown, "backdrop", 0.1, 0.1, 0.1, 0.85)
    -- Border (using standard edged border)
    BoxxyAuras.UIUtils.DrawSlicedBG(profileDropdown, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(profileDropdown, "border", 0.4, 0.4, 0.4, 0.9)
else
    -- print("|cffFF0000BoxxyAuras Options Error:|r Could not style profile dropdown.")
end
-- <<< END Styling >>>

-- <<< ADD Dropdown Arrow Texture >>>
local arrow = profileDropdown:CreateTexture(nil, "OVERLAY")
arrow:SetSize(16, 16) -- Adjust size as needed
arrow:SetPoint("RIGHT", profileDropdown, "RIGHT", -8, 0) -- Position inside, near the right edge
arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown")
arrow:SetTexCoord(0, 1, 0, 1)
-- <<< END Arrow Texture >>>

-- <<< ADD Dropdown Hover Effect >>>
profileDropdown:SetScript("OnEnter", function(self)
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.8, 0.8, 0.8, 1.0) -- Brighter border on hover
    end
end)
profileDropdown:SetScript("OnLeave", function(self)
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.4, 0.4, 0.4, 0.9) -- Revert to normal border color
    end
end)
-- <<< END Hover Effect >>>

-- <<< ADD Click handler to main frame >>>
profileDropdown:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        ToggleDropDownMenu(1, nil, self) -- Toggles the dropdown associated with this frame
    end
end)
-- <<< END Click Handler >>>

lastInGroup = profileDropdown
groupVSpacing = -8 -- Space below dropdown

-- Profile Action Label
local profileActionLabel = profileGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
profileActionLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", groupPadding, groupVSpacing)
profileActionLabel:SetText("|cffb9ac9dProfile Actions|r")
BoxxyAuras.Options.ProfileActionLabel = profileActionLabel
lastInGroup = profileActionLabel
groupVSpacing = -8

-- Profile Name EditBox (for Create/Copy)
local profileNameEditBox = CreateFrame("EditBox", "BoxxyAurasProfileNameEditBox", profileGroup, "InputBoxTemplate")
profileNameEditBox:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
profileNameEditBox:SetWidth(groupWidth - (groupPadding * 2) - 15) -- << Reduced width further
profileNameEditBox:SetHeight(20)
profileNameEditBox:SetAutoFocus(false)
profileNameEditBox:SetMaxLetters(32) -- Reasonable limit for profile names
profileNameEditBox:SetTextInsets(5, 5, 0, 0)
profileNameEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
profileNameEditBox:SetScript("OnEnterPressed", function(self)
    local name = self:GetText()
    if name and name ~= "" then
        -- print("BoxxyAuras: Enter pressed in profile name box. Use Create/Copy buttons.")
        self:SetText("") -- Clear after use
        self:ClearFocus()
    end
end)
BoxxyAuras.Options.ProfileNameEditBox = profileNameEditBox
lastInGroup = profileNameEditBox
groupVSpacing = -2 -- Space below edit box

-- Create/Copy/Delete Buttons (Side by Side)
local buttonWidth = (profileNameEditBox:GetWidth() / 3) - 2 -- << Recalculate based on new edit box width
local buttonYOffset = -5

local createButton = CreateFrame("Button", "BoxxyAurasCreateProfileButton", profileGroup, "BAURASButtonTemplate")
createButton:SetPoint("TOPLEFT", profileNameEditBox, "BOTTOMLEFT", -3, buttonYOffset) -- << Anchor directly to edit box
createButton:SetWidth(buttonWidth); createButton:SetHeight(20)
createButton:SetText("Create")
createButton:SetScript("OnClick", function()
    local name = BoxxyAuras.Options.ProfileNameEditBox:GetText()
    if name and name ~= "" then
        BoxxyAuras.Options:CreateProfile(name)
        BoxxyAuras.Options.ProfileNameEditBox:SetText("")
    else
        -- print("BoxxyAuras Profiles: Please enter a name to create a profile.")
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.CreateProfileButton = createButton

local copyButton = CreateFrame("Button", "BoxxyAurasCopyProfileButton", profileGroup, "BAURASButtonTemplate")
copyButton:SetPoint("LEFT", createButton, "RIGHT", 3, 0) -- Position next to Create
copyButton:SetWidth(buttonWidth); copyButton:SetHeight(20)
copyButton:SetText("Copy")
copyButton:SetScript("OnClick", function()
    local name = BoxxyAuras.Options.ProfileNameEditBox:GetText()
    if name and name ~= "" then
        BoxxyAuras.Options:CopyProfile(name)
        BoxxyAuras.Options.ProfileNameEditBox:SetText("")
    else
        -- print("BoxxyAuras Profiles: Please enter a name for the copied profile.")
    end
     PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.CopyProfileButton = copyButton

local deleteButton = CreateFrame("Button", "BoxxyAurasDeleteProfileButton", profileGroup, "BAURASButtonTemplate")
deleteButton:SetPoint("LEFT", copyButton, "RIGHT", 3, 0) -- Position next to Copy
deleteButton:SetWidth(buttonWidth); deleteButton:SetHeight(20)
deleteButton:SetText("Delete")
deleteButton:SetScript("OnClick", function(self)
    -- <<< ADD Enabled Check >>>
    if not self:IsEnabled() then return end 

    local selectedProfile = BoxxyAurasDB and BoxxyAurasDB.activeProfile
    if selectedProfile then
        -- << ADD Confirmation Dialog >>
        StaticPopup_Show("BOXXYAURAS_DELETE_PROFILE_CONFIRM", selectedProfile)
    end
     PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.DeleteProfileButton = deleteButton
lastInGroup = createButton -- Anchor next group below the button row

-- Set Profile Group Height -- << REVISED >>
profileGroup:SetHeight(155) -- << Set a fixed height sufficient for contents >>

-- Update lastElement for next group positioning
lastElement = profileGroup
verticalSpacing = -5 -- Space between groups (Profile -> General)


--[[------------------------------------------------------------
-- Group 1: General Settings
--------------------------------------------------------------]]
local generalGroup = CreateFrame("Frame", "BoxxyAurasOptionsGeneralGroup", contentFrame) -- Parent to contentFrame
generalGroup:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing) -- Position below NEW profile group
generalGroup:SetWidth(groupWidth)
StyleGroupContainer(generalGroup)

lastInGroup = generalGroup -- Anchor first element to top of group
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Option: Lock Frames Checkbox
local lockFramesCheck = CreateFrame("CheckButton", "BoxxyAurasLockFramesCheckButton", generalGroup, "BAURASCheckBoxTemplate") -- Parent to generalGroup
lockFramesCheck:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
lockFramesCheck:SetText("Lock Frames")
lockFramesCheck:SetScript("OnClick", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end

    local currentSavedState = currentSettings.lockFrames
    local newState = not currentSavedState
    currentSettings.lockFrames = newState

    -- <<< MODIFIED: Directly call the FrameHandler function >>>
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.ApplyLockState then
         BoxxyAuras.FrameHandler.ApplyLockState(newState)
    else
        -- BoxxyAuras.DebugLogError("LockFramesCheck OnClick: BoxxyAuras.FrameHandler.ApplyLockState function not found!")
    end
    -- <<< END MODIFICATION >>>

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.LockFramesCheck = lockFramesCheck
lastInGroup = lockFramesCheck
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Option: Hide Blizzard Auras Checkbox
local hideBlizzardCheck = CreateFrame("CheckButton", "BoxxyAurasHideBlizzardCheckButton", generalGroup, "BAURASCheckBoxTemplate") -- Parent to generalGroup
hideBlizzardCheck:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing) -- Position below previous
hideBlizzardCheck:SetText("Hide Default Blizzard Auras")
hideBlizzardCheck:SetScript("OnClick", function(self)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end

    local currentSavedState = currentSettings.hideBlizzardAuras
    local newState = not currentSavedState
    currentSettings.hideBlizzardAuras = newState

    if BoxxyAuras.ApplyBlizzardAuraVisibility then
        BoxxyAuras.ApplyBlizzardAuraVisibility(newState)
    else
        -- BoxxyAuras.DebugLogError("HideBlizzardCheck OnClick: BoxxyAuras.ApplyBlizzardAuraVisibility not found!")
    end

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.HideBlizzardCheck = hideBlizzardCheck
lastInGroup = hideBlizzardCheck

-- Set General Group Height
local lastBottomGen = lastInGroup and lastInGroup:GetBottom()
local groupTopGen = generalGroup:GetTop()
generalGroup:SetHeight(65)

-- Update lastElement for next group positioning
lastElement = generalGroup
verticalSpacing = -5 -- Space between groups

--[[------------------------------------------------------------
-- Group 2: Display Frame Settings (Alignment & Size)
--------------------------------------------------------------]]
local displayGroup = CreateFrame("Frame", "BoxxyAurasOptionsDisplayGroup", contentFrame) -- Parent to contentFrame
displayGroup:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing) -- Position below previous group
displayGroup:SetWidth(groupWidth)
-- StyleGroupContainer(displayGroup) -- << REMOVED styling from the main container (Attempt 2)

local subGroupWidth = groupWidth - (groupPadding * 2) -- << This line is no longer needed
local subGroupVerticalSpacing = -10 -- Spacing between sub-groups
local lastSubGroup = displayGroup -- Track the last sub-group for vertical positioning

--[[------------------------
-- Sub-Group 1: Buffs
--------------------------]]
local buffSubGroup = CreateFrame("Frame", "BoxxyAurasOptionsBuffSubGroup", displayGroup)
buffSubGroup:SetPoint("TOPLEFT", lastSubGroup, "TOPLEFT", 0, internalElementVSpacing) -- << Removed horizontal padding offset
buffSubGroup:SetWidth(groupWidth) -- << Use groupWidth
StyleGroupContainer(buffSubGroup) -- << Use default keys

lastInGroup = buffSubGroup -- Reset for positioning within this sub-group
groupVSpacing = internalElementVSpacing -- Start spacing within the sub-group

-- Buff Text Alignment Title
local buffAlignLabel = buffSubGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
buffAlignLabel:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
buffAlignLabel:SetText("|cffb9ac9dBuff Text Alignment|r")
BoxxyAuras.Options.BuffAlignLabel = buffAlignLabel
lastInGroup = buffAlignLabel
groupVSpacing = -8 -- Keep smaller space after header

-- Buff Alignment Checkboxes (Left, Center, Right) - Revised Anchoring
local buffAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignLeftCheck", buffSubGroup, "BAURASCheckBoxTemplate")
buffAlignLeftCheck:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
buffAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.BuffAlignLeftCheck = buffAlignLeftCheck

local buffAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignCenterCheck", buffSubGroup, "BAURASCheckBoxTemplate")
-- <<< Anchor Center relative to Left with fixed spacing >>>
buffAlignCenterCheck:SetPoint("TOPLEFT", buffAlignLeftCheck, "TOPRIGHT", checkboxSpacing, 0)
buffAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.BuffAlignCenterCheck = buffAlignCenterCheck

local buffAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignRightCheck", buffSubGroup, "BAURASCheckBoxTemplate")
-- <<< Anchor Right relative to Center with fixed spacing >>>
buffAlignRightCheck:SetPoint("TOPLEFT", buffAlignCenterCheck, "TOPRIGHT", checkboxSpacing, 0)
buffAlignRightCheck:SetText("Right")
BoxxyAuras.Options.BuffAlignRightCheck = buffAlignRightCheck

-- Function to handle mutual exclusivity and saving for BUFFS (Defined later)
buffAlignLeftCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleBuffAlignmentClick(self, "LEFT") end)
buffAlignCenterCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleBuffAlignmentClick(self, "CENTER") end)
buffAlignRightCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleBuffAlignmentClick(self, "RIGHT") end)
lastInGroup = buffAlignLeftCheck -- Anchor next section below the row
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Buff Icon Size Slider
local buffSizeLabel = buffSubGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
buffSizeLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
buffSizeLabel:SetText("Buff Icon Size")
BoxxyAuras.Options.BuffSizeLabel = buffSizeLabel
local buffSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsBuffSizeSlider", buffSubGroup, "BAURASSlider")
buffSizeSlider:SetPoint("TOPLEFT", buffSizeLabel, "BOTTOMLEFT", 5, -10)
buffSizeSlider:SetMinMaxValues(12, 64); buffSizeSlider:SetValueStep(1); buffSizeSlider:SetObeyStepOnDrag(true); buffSizeSlider:SetWidth(160)
if buffSizeSlider.KeyLabel then buffSizeSlider.KeyLabel:Show() end; if buffSizeSlider.KeyLabel2 then buffSizeSlider.KeyLabel2:Show() end
buffSizeSlider:SetScript("OnValueChanged", function(self, value)
    if self.KeyLabel then self.KeyLabel:SetText(string.format("%dpx", math.floor(value + 0.5))) end
    local min, max = self:GetMinMaxValues(); local range = max - min
    if range > 0 and self.VirtualThumb then self.VirtualThumb:SetPoint("CENTER", self, "LEFT", (value - min) / range * self:GetWidth(), 0) end
end)
buffSizeSlider:SetScript("OnMouseUp", function(self)

    local value = math.floor(self:GetValue() + 0.5); self:SetValue(value)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then 
        BoxxyAuras.DebugLogError("BuffSizeSlider OnMouseUp: currentSettings is nil.")
        return 
    end
    
    if currentSettings.buffFrameSettings then
        currentSettings.buffFrameSettings.iconSize = value
        BoxxyAuras.Options:ApplyIconSizeChange("Buff") 
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.BuffSizeSlider = buffSizeSlider
lastInGroup = buffSizeSlider

-- Calculate Buff Sub-Group Height (Reverted)
local lastBottomBuffSub = lastInGroup and lastInGroup:GetBottom()
local groupTopBuffSub = buffSubGroup:GetTop()
buffSubGroup:SetHeight(120) -- << Reverted height >>

lastSubGroup = buffSubGroup -- Update tracking for next sub-group

--[[--------------------------
-- Sub-Group 2: Debuffs
----------------------------]]
local debuffSubGroup = CreateFrame("Frame", "BoxxyAurasOptionsDebuffSubGroup", displayGroup)
debuffSubGroup:SetPoint("TOPLEFT", lastSubGroup, "BOTTOMLEFT", 0, subGroupVerticalSpacing) -- Position below buff group, no horizontal padding
debuffSubGroup:SetWidth(groupWidth) -- << Use groupWidth
StyleGroupContainer(debuffSubGroup) -- << Use default keys

lastInGroup = debuffSubGroup -- Reset for positioning within this sub-group
groupVSpacing = internalElementVSpacing -- Start spacing within the sub-group

-- Debuff Text Alignment Title
local debuffAlignLabel = debuffSubGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
debuffAlignLabel:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
debuffAlignLabel:SetText("|cffb9ac9dDebuff Text Alignment|r")
BoxxyAuras.Options.DebuffAlignLabel = debuffAlignLabel
lastInGroup = debuffAlignLabel
groupVSpacing = -8 -- Keep smaller space after header

-- Debuff Alignment Checkboxes - Revised Anchoring
local debuffAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignLeftCheck", debuffSubGroup, "BAURASCheckBoxTemplate")
debuffAlignLeftCheck:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
debuffAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.DebuffAlignLeftCheck = debuffAlignLeftCheck

local debuffAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignCenterCheck", debuffSubGroup, "BAURASCheckBoxTemplate")
-- <<< Anchor Center relative to Left with fixed spacing >>>
debuffAlignCenterCheck:SetPoint("TOPLEFT", debuffAlignLeftCheck, "TOPRIGHT", checkboxSpacing, 0)
debuffAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.DebuffAlignCenterCheck = debuffAlignCenterCheck

local debuffAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignRightCheck", debuffSubGroup, "BAURASCheckBoxTemplate")
-- <<< Anchor Right relative to Center with fixed spacing >>>
debuffAlignRightCheck:SetPoint("TOPLEFT", debuffAlignCenterCheck, "TOPRIGHT", checkboxSpacing, 0)
debuffAlignRightCheck:SetText("Right")
BoxxyAuras.Options.DebuffAlignRightCheck = debuffAlignRightCheck

-- Function to handle mutual exclusivity and saving for DEBUFFS (Defined later)
debuffAlignLeftCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleDebuffAlignmentClick(self, "LEFT") end)
debuffAlignCenterCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleDebuffAlignmentClick(self, "CENTER") end)
debuffAlignRightCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleDebuffAlignmentClick(self, "RIGHT") end)
lastInGroup = debuffAlignLeftCheck
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Debuff Icon Size Slider
local debuffSizeLabel = debuffSubGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
debuffSizeLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
debuffSizeLabel:SetText("Debuff Icon Size")
BoxxyAuras.Options.DebuffSizeLabel = debuffSizeLabel
local debuffSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsDebuffSizeSlider", debuffSubGroup, "BAURASSlider")
debuffSizeSlider:SetPoint("TOPLEFT", debuffSizeLabel, "BOTTOMLEFT", 5, -10)
debuffSizeSlider:SetMinMaxValues(12, 64); debuffSizeSlider:SetValueStep(1); debuffSizeSlider:SetObeyStepOnDrag(true); debuffSizeSlider:SetWidth(160)
if debuffSizeSlider.KeyLabel then debuffSizeSlider.KeyLabel:Show() end; if debuffSizeSlider.KeyLabel2 then debuffSizeSlider.KeyLabel2:Show() end
debuffSizeSlider:SetScript("OnValueChanged", function(self, value)
    if self.KeyLabel then self.KeyLabel:SetText(string.format("%dpx", math.floor(value + 0.5))) end
    local min, max = self:GetMinMaxValues(); local range = max - min
    if range > 0 and self.VirtualThumb then self.VirtualThumb:SetPoint("CENTER", self, "LEFT", (value - min) / range * self:GetWidth(), 0) end
end)
debuffSizeSlider:SetScript("OnMouseUp", function(self)
    local value = math.floor(self:GetValue() + 0.5); self:SetValue(value)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then 
        BoxxyAuras.DebugLogError("DebuffSizeSlider OnMouseUp: currentSettings is nil.")
        return 
    end
    
    if currentSettings.debuffFrameSettings then
        currentSettings.debuffFrameSettings.iconSize = value
        BoxxyAuras.Options:ApplyIconSizeChange("Debuff") -- <<< Use "Debuff" >>>
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.DebuffSizeSlider = debuffSizeSlider
lastInGroup = debuffSizeSlider

-- Calculate Debuff Sub-Group Height (Reverted)
local lastBottomDebuffSub = lastInGroup and lastInGroup:GetBottom()
local groupTopDebuffSub = debuffSubGroup:GetTop()
debuffSubGroup:SetHeight(120) -- << Reverted height >>

lastSubGroup = debuffSubGroup -- Update tracking for next sub-group

--[[--------------------------
-- Sub-Group 3: Custom
----------------------------]]
local customSubGroup = CreateFrame("Frame", "BoxxyAurasOptionsCustomSubGroup", displayGroup)
customSubGroup:SetPoint("TOPLEFT", lastSubGroup, "BOTTOMLEFT", 0, subGroupVerticalSpacing) -- Position below debuff group, no horizontal padding
customSubGroup:SetWidth(groupWidth) -- << Use groupWidth
StyleGroupContainer(customSubGroup) -- << Use default keys

lastInGroup = customSubGroup -- Reset for positioning within this sub-group
groupVSpacing = internalElementVSpacing -- Start spacing within the sub-group

-- Custom Text Alignment Title
local customAlignLabel = customSubGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
customAlignLabel:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
customAlignLabel:SetText("|cffb9ac9dCustom Text Alignment|r")
BoxxyAuras.Options.CustomAlignLabel = customAlignLabel
lastInGroup = customAlignLabel
groupVSpacing = -8 -- Keep smaller space after header

-- Custom Alignment Checkboxes - Revised Anchoring
local customAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasCustomAlignLeftCheck", customSubGroup, "BAURASCheckBoxTemplate")
customAlignLeftCheck:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
customAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.CustomAlignLeftCheck = customAlignLeftCheck

local customAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasCustomAlignCenterCheck", customSubGroup, "BAURASCheckBoxTemplate")
-- <<< Anchor Center relative to Left with fixed spacing >>>
customAlignCenterCheck:SetPoint("TOPLEFT", customAlignLeftCheck, "TOPRIGHT", checkboxSpacing, 0)
customAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.CustomAlignCenterCheck = customAlignCenterCheck

local customAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasCustomAlignRightCheck", customSubGroup, "BAURASCheckBoxTemplate")
-- <<< Anchor Right relative to Center with fixed spacing >>>
customAlignRightCheck:SetPoint("TOPLEFT", customAlignCenterCheck, "TOPRIGHT", checkboxSpacing, 0)
customAlignRightCheck:SetText("Right")
BoxxyAuras.Options.CustomAlignRightCheck = customAlignRightCheck

-- Function to handle mutual exclusivity and saving for CUSTOM (Defined later)
customAlignLeftCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleCustomAlignmentClick(self, "LEFT") end)
customAlignCenterCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleCustomAlignmentClick(self, "CENTER") end)
customAlignRightCheck:SetScript("OnClick", function(self) BoxxyAuras.Options:HandleCustomAlignmentClick(self, "RIGHT") end)
lastInGroup = customAlignLeftCheck
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Custom Icon Size Slider
local customSizeLabel = customSubGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
customSizeLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
customSizeLabel:SetText("Custom Icon Size")
BoxxyAuras.Options.CustomSizeLabel = customSizeLabel
local customSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsCustomSizeSlider", customSubGroup, "BAURASSlider")
customSizeSlider:SetPoint("TOPLEFT", customSizeLabel, "BOTTOMLEFT", 5, -10)
customSizeSlider:SetMinMaxValues(12, 64); customSizeSlider:SetValueStep(1); customSizeSlider:SetObeyStepOnDrag(true); customSizeSlider:SetWidth(160)
if customSizeSlider.KeyLabel then customSizeSlider.KeyLabel:Show() end; if customSizeSlider.KeyLabel2 then customSizeSlider.KeyLabel2:Show() end
customSizeSlider:SetScript("OnValueChanged", function(self, value)
    if self.KeyLabel then self.KeyLabel:SetText(string.format("%dpx", math.floor(value + 0.5))) end
    local min, max = self:GetMinMaxValues(); local range = max - min
    if range > 0 and self.VirtualThumb then self.VirtualThumb:SetPoint("CENTER", self, "LEFT", (value - min) / range * self:GetWidth(), 0) end
end)
customSizeSlider:SetScript("OnMouseUp", function(self)
    local value = math.floor(self:GetValue() + 0.5); self:SetValue(value)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then 
        BoxxyAuras.DebugLogError("CustomSizeSlider OnMouseUp: currentSettings is nil.")
        return 
    end
    
    if currentSettings.customFrameSettings then
        currentSettings.customFrameSettings.iconSize = value
        BoxxyAuras.Options:ApplyIconSizeChange("Custom") -- <<< Use "Custom" >>>
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.CustomSizeSlider = customSizeSlider
lastInGroup = customSizeSlider

-- Button to Open Custom Aura Options
local openCustomOptionsButton = CreateFrame("Button", "BoxxyAurasOpenCustomOptionsButton", customSubGroup, "BAURASButtonTemplate") -- Parent = customSubGroup
openCustomOptionsButton:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", -5, -35) -- Position below slider (adjusted spacing)
openCustomOptionsButton:SetWidth(customSubGroup:GetWidth() - (groupPadding * 2) - 10) -- Fit within sub-group padding
openCustomOptionsButton:SetHeight(25)
openCustomOptionsButton:SetText("Set Custom Auras")
openCustomOptionsButton:SetScript("OnClick", function()
    -- <<< Restore IF check using _G >>>
    if _G.BoxxyAuras and _G.BoxxyAuras.CustomOptions and _G.BoxxyAuras.CustomOptions.Toggle then
        _G.BoxxyAuras.CustomOptions:Toggle()
    else
        -- Print an error if the table or function is missing at click time
        print("|cffFF0000BoxxyAuras Error:|r CustomOptions table or Toggle function is missing when button clicked!")
        print(string.format("  _G.BoxxyAuras.CustomOptions type: %s", type(_G.BoxxyAuras.CustomOptions)))
        if _G.BoxxyAuras.CustomOptions then
             print(string.format("  _G.BoxxyAuras.CustomOptions.Toggle type: %s", type(_G.BoxxyAuras.CustomOptions.Toggle)))
        end
    end
    
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.OpenCustomOptionsButton = openCustomOptionsButton
lastInGroup = openCustomOptionsButton -- Update lastInGroup for height calc

-- Calculate Custom Sub-Group Height (Adjusted)
local lastBottomCustomSub = lastInGroup and lastInGroup:GetBottom()
local groupTopCustomSub = customSubGroup:GetTop()
customSubGroup:SetHeight(150) -- << Increased height to fit button >>

lastSubGroup = customSubGroup -- Update tracking

-- Calculate MAIN Display Group Height (based on last sub-group)
local lastBottomDisplay = lastSubGroup and lastSubGroup:GetBottom()
local groupTopDisplay = displayGroup:GetTop()
displayGroup:SetHeight(400)

-- Update lastElement for next group positioning
lastElement = displayGroup
verticalSpacing = -30 -- Space between main groups

--[[------------------------------------------------------------
-- Group 3: Global Settings
--------------------------------------------------------------]]
local scaleGroup = CreateFrame("Frame", "BoxxyAurasOptionsScaleGroup", contentFrame)
scaleGroup:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing)
scaleGroup:SetWidth(groupWidth)
StyleGroupContainer(scaleGroup)

lastInGroup = scaleGroup
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Option: Scale Slider
local scaleSliderLabel = scaleGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
scaleSliderLabel:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
scaleSliderLabel:SetText("Global Scale")
BoxxyAuras.Options.ScaleSliderLabel = scaleSliderLabel
local scaleSlider = CreateFrame("Slider", "BoxxyAurasOptionsScaleSlider", scaleGroup, "BAURASSlider")
scaleSlider:SetPoint("TOPLEFT", scaleSliderLabel, "BOTTOMLEFT", 5, -10)
scaleSlider:SetMinMaxValues(0.5, 2.0); scaleSlider:SetValueStep(0.05); scaleSlider:SetObeyStepOnDrag(true); scaleSlider:SetWidth(160)
if scaleSlider.KeyLabel then scaleSlider.KeyLabel:Show() end; if scaleSlider.KeyLabel2 then scaleSlider.KeyLabel2:Show() end
scaleSlider:SetScript("OnValueChanged", function(self, value)
    if self.KeyLabel then self.KeyLabel:SetText(string.format("%.2f", value)) end
    local min, max = self:GetMinMaxValues(); local range = max - min
    if range > 0 and self.VirtualThumb then self.VirtualThumb:SetPoint("CENTER", self, "LEFT", (value - min) / range * self:GetWidth(), 0) end
end)
scaleSlider:SetScript("OnMouseUp", function(self)
    local value = self:GetValue(); local step = self:GetValueStep(); value = math.floor((value / step) + 0.5) * step; self:SetValue(value)
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end
    currentSettings.optionsScale = value
    
    -- <<< Trigger ApplySettings for aura frames to re-apply scale & position >>>
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.ApplySettings then
        BoxxyAuras.FrameHandler.ApplySettings("Buff")
        BoxxyAuras.FrameHandler.ApplySettings("Debuff")
        BoxxyAuras.FrameHandler.ApplySettings("Custom")
    end

    -- <<< Explicitly scale options windows >>>
    BoxxyAuras.Options:ApplyScale(value) 

    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.ScaleSlider = scaleSlider
lastInGroup = scaleSlider

-- Set Scale Group Height
local lastBottomScale = lastInGroup and lastInGroup:GetBottom()
local groupTopScale = scaleGroup:GetTop()
scaleGroup:SetHeight(50)

-- Update lastElement for next group positioning
lastElement = scaleGroup
-- verticalSpacing = -20 -- No longer needed after the last group

--[[------------------------------------------------------------
-- Dynamically Set Content Frame Height
--------------------------------------------------------------]]
local bottomPadding = 20 -- Space below the last element
local lastElementBottom = lastElement and lastElement:GetBottom()
local contentTop = contentFrame:GetTop()

if lastElementBottom and contentTop then
    local requiredHeight = contentTop - lastElementBottom + bottomPadding
    contentFrame:SetHeight(requiredHeight)
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not dynamically calculate content frame height. Using fallback.")
    -- Keep the original fallback or adjust if needed
    contentFrame:SetHeight(700)
end

--[[------------------------------------------------------------
-- Apply / Update / Handler Functions (Moved UP)
--------------------------------------------------------------]]
function BoxxyAuras.Options:ApplyLockState(lockState)
    -- << MODIFIED: Get frame references from BoxxyAuras.Frames >>
    local buffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Buff
    local debuffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Debuff
    local customFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Custom

    -- Safety check
    if not buffFrame or not debuffFrame or not customFrame then
        print("|cffFF0000BoxxyAuras Options Error:|r Could not get frame references in ApplyLockState.")
        return
    end

    local function ApplyToFrame(frame, baseName)
        if not frame then return end

        -- 1. Set Movable
        frame:SetMovable(not lockState)
        frame.isLocked = lockState

        -- 2. Handles
        if frame.handles then
            for name, handle in pairs(frame.handles) do
                handle:EnableMouse(not lockState)
                if lockState then handle:Hide() else handle:Show() end
            end
        end

        -- 3. Title Label
        local titleLabelName = baseName .. "TitleLabel"
        local titleLabel = _G[titleLabelName]
        if titleLabel then
            if lockState then titleLabel:Hide() else titleLabel:Show() end
        end

        -- 4. Background & Border Visibility/Color
        if lockState then
            -- Hide background textures
            if frame.backdropTextures then
                for _, texture in ipairs(frame.backdropTextures) do
                    if texture then texture:Hide() end
                end
            end
            -- Hide border textures
            if frame.borderTextures then
                 for _, texture in ipairs(frame.borderTextures) do
                    if texture then texture:Hide() end
                end
            end
        else
            -- Show and color background textures
            if frame.backdropTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
                for _, texture in ipairs(frame.backdropTextures) do
                    if texture then texture:Show() end -- Ensure textures are shown
                end
                -- Apply color from config
                local normalBgColor = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", normalBgColor.r, normalBgColor.g, normalBgColor.b, normalBgColor.a) -- Use full config color including alpha
            end
            -- Show and color border textures
            if frame.borderTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
                 for _, texture in ipairs(frame.borderTextures) do
                     if texture then texture:Show() end -- Ensure textures are shown
                end
                -- Apply color from config
                local normalBorderColor = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.4, g = 0.4, b = 0.4, a = 0.8 }
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", normalBorderColor.r, normalBorderColor.g, normalBorderColor.b, normalBorderColor.a) -- Use full config color including alpha
            end
        end
    end

    ApplyToFrame(buffFrame, "BuffFrame")
    ApplyToFrame(debuffFrame, "DebuffFrame")
    ApplyToFrame(customFrame, "CustomFrame")
end

function BoxxyAuras.Options:ApplyScale(scaleValue)
    if not scaleValue then return end
    local optionsFrm = self.Frame -- This one is local to Options
    local customOptionsFrm = BoxxyAuras.CustomOptions and BoxxyAuras.CustomOptions.Frame -- This one is local to CustomOptions

    -- Scale the Options Windows ONLY
    if optionsFrm then optionsFrm:SetScale(scaleValue) end
    if customOptionsFrm then customOptionsFrm:SetScale(scaleValue) end
end

function BoxxyAuras.Options:ApplyTextAlign()
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.TriggerLayout then
        BoxxyAuras.FrameHandler.TriggerLayout("Buff")
        BoxxyAuras.FrameHandler.TriggerLayout("Debuff")
        BoxxyAuras.FrameHandler.TriggerLayout("Custom")
    end
end

function BoxxyAuras.Options:ApplyIconSizeChange(frameType)
    local settingsKey = nil
    if frameType == "Buff" then settingsKey = "buffFrameSettings"
    elseif frameType == "Debuff" then settingsKey = "debuffFrameSettings"
    elseif frameType == "Custom" then settingsKey = "customFrameSettings"
    else return end

    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings or not currentSettings[settingsKey] then return end

    -- Icon size is already saved by the slider's OnMouseUp.
    -- We no longer need to read iconSize, numIconsWide, or currentSavedWidth here.

    if BoxxyAuras.FrameHandler and
       BoxxyAuras.FrameHandler.CalculateFrameWidth and -- Keep check for existence
       BoxxyAuras.FrameHandler.ApplySettings and
       BoxxyAuras.FrameHandler.LayoutAuras then

        -- Remove all width calculation/adjustment logic from here.
        -- ApplySettings in FrameHandler will now *always* calculate width based on
        -- the newly saved iconSize and the existing numIconsWide from the profile.

        -- Apply settings (will use the new iconSize and existing numIconsWide to calculate width)
        BoxxyAuras.FrameHandler.ApplySettings(frameType)

        -- Re-layout icons (will use the newly calculated frame dimensions)
        BoxxyAuras.FrameHandler.LayoutAuras(frameType)

        -- Force update on existing visible icons for size change
        local trackedAuras = BoxxyAuras.GetTrackedAuras and BoxxyAuras.GetTrackedAuras(frameType) or {}
        local visualIcons = nil
        local filter = "HELPFUL"
        if frameType == "Buff" then visualIcons = BoxxyAuras.buffIcons; filter = "HELPFUL"
        elseif frameType == "Debuff" then visualIcons = BoxxyAuras.debuffIcons; filter = "HARMFUL"
        elseif frameType == "Custom" then visualIcons = BoxxyAuras.customIcons; filter = "CUSTOM"
        end

        if visualIcons and trackedAuras then
            for i, auraData in ipairs(trackedAuras) do
                local auraIcon = visualIcons[i]
                local iconStatus = "MISSING"
                if auraIcon and auraIcon.frame and auraIcon.Update then
                    iconStatus = string.format("FOUND, IsShown: %s, Has Update: %s", tostring(auraIcon.frame:IsShown()), tostring(auraIcon.Update ~= nil))
                elseif auraIcon and auraIcon.frame then
                     iconStatus = "FOUND, Missing Update method"
                elseif auraIcon then
                     iconStatus = "FOUND, Missing frame"
                end
                
                if auraIcon and auraIcon.frame and auraIcon.frame:IsShown() and auraIcon.Update then
                    auraIcon:Update(auraData, i, filter)
                end
            end
        end
    end
end

--[[------------------------------------------------------------
-- Profile Management UI Functions (Moved UP)
--------------------------------------------------------------]]
-- << MODIFIED: Initialize Profile Dropdown Structure >>
-- This function now focuses ONLY on setting up the dropdown's item list.
function BoxxyAuras.Options:InitializeProfileDropdown()
    local dropdown = self.ProfileDropdown
    if not dropdown then
        return
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        info.minWidth = 180

        local profileNames = {}
        if BoxxyAurasDB and BoxxyAurasDB.profiles then
            for name, _ in pairs(BoxxyAurasDB.profiles) do table.insert(profileNames, name) end
            table.sort(profileNames)
        end
        if #profileNames == 0 then table.insert(profileNames, "Default") end -- Ensure Default always exists
        local defaultExists = false
        for _, name in ipairs(profileNames) do if name == "Default" then defaultExists = true; break; end end
        if not defaultExists then table.insert(profileNames, 1, "Default") end -- Add Default if missing

        -- <<< Get ACTIVE profile name for THIS character >>>
        local currentCharacterActiveProfile = "Default"
        if BoxxyAuras.GetActiveProfileName then 
            currentCharacterActiveProfile = BoxxyAuras:GetActiveProfileName()
        end

        for _, name in ipairs(profileNames) do
            info.text = name
            info.arg1 = name
            -- <<< Check against THIS character's active profile >>>
            info.checked = (name == currentCharacterActiveProfile)
            info.func = BoxxyAuras.Options.SelectProfile
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")

    dropdown:Show()
end

-- << MODIFIED: Update Profile UI >>
function BoxxyAuras.Options:UpdateProfileUI()
    local dropdown = self.ProfileDropdown
    if not dropdown then
        return
    end

    -- <<< Get ACTIVE profile name for THIS character >>>
    local activeProfile = "Default"
    if BoxxyAuras.GetActiveProfileName then 
        activeProfile = BoxxyAuras:GetActiveProfileName()
    end

    -- Set the dropdown text to the current character's active profile
    if type(activeProfile) == "string" and activeProfile ~= "" then
        UIDropDownMenu_SetText(dropdown, activeProfile)
    else
        UIDropDownMenu_SetText(dropdown, "Default") -- Fallback
    end

    -- Enable/disable delete button based on selected profile for THIS character
    if self.DeleteProfileButton then
        local canDelete = (activeProfile ~= "Default")
        self.DeleteProfileButton:SetEnabled(canDelete)
        self.DeleteProfileButton:SetAlpha(canDelete and 1 or 0.5)
    end
     -- Enable/disable copy button if a profile is selected for THIS character
    if self.CopyProfileButton then
        local canCopy = (activeProfile ~= nil) -- Can always copy if a profile is active
        self.CopyProfileButton:SetEnabled(canCopy)
        self.CopyProfileButton:SetAlpha(canCopy and 1 or 0.5)
    end
end

-- << Function called when a profile is selected from the dropdown >>
function BoxxyAuras.Options.SelectProfile(self, profileName)
    if not profileName then return end
    
    local characterKey = BoxxyAuras:GetCharacterKey()
    if not characterKey then 
        print("|cffFF0000BoxxyAuras Error:|r Could not get character key to select profile.")
        return 
    end

    -- Ensure map exists
    if not BoxxyAurasDB.characterProfileMap then BoxxyAurasDB.characterProfileMap = {} end

    local currentCharacterActiveProfile = BoxxyAurasDB.characterProfileMap[characterKey] or "Default"

    if profileName ~= currentCharacterActiveProfile then
        print(string.format("BoxxyAuras: Setting profile for %s to '%s'", characterKey, profileName))
        -- <<< SAVE to character map >>>
        BoxxyAurasDB.characterProfileMap[characterKey] = profileName

        -- Reload options UI, re-initialize frames, re-initialize auras (existing logic)
        if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.InitializeFrames then
             BoxxyAuras.FrameHandler.InitializeFrames()
        end
        if BoxxyAuras.InitializeAuras then InitializeAuras()
        elseif BoxxyAuras.UpdateAuras then BoxxyAuras.UpdateAuras() end
        if BoxxyAuras.Options.UpdateProfileUI then BoxxyAuras.Options:UpdateProfileUI() end
        if BoxxyAuras.Options.Load then BoxxyAuras.Options:Load() end

        PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end
    CloseDropDownMenus()
end

-- << Create Profile >>
function BoxxyAuras.Options:CreateProfile(profileName)
    if not profileName or profileName == "" then
        print("BoxxyAuras Profiles: Invalid profile name.")
        return
    end
    if BoxxyAurasDB.profiles[profileName] then
        print(string.format("BoxxyAuras Profiles: Profile '%s' already exists.", profileName))
        return
    end

    print(string.format("BoxxyAuras: Creating new profile '%s'", profileName))
    if BoxxyAuras.GetDefaultProfileSettings then
        BoxxyAurasDB.profiles[profileName] = CopyTable(BoxxyAuras:GetDefaultProfileSettings())
    else
         print("|cffFF0000BoxxyAuras Profiles Error:|r Cannot get default settings to create profile.")
         BoxxyAurasDB.profiles[profileName] = {} 
    end

    -- <<< Automatically switch THIS CHARACTER to the new profile >>>
    BoxxyAuras.Options.SelectProfile(nil, profileName) 
end

-- << Copy Profile >>
function BoxxyAuras.Options:CopyProfile(newProfileName)
    if not newProfileName or newProfileName == "" then
        print("BoxxyAuras Profiles: Invalid name for copy.")
        return
    end

    local currentActiveKey = "Default" 
    if BoxxyAuras.GetActiveProfileName then currentActiveKey = BoxxyAuras:GetActiveProfileName() end
    
    if BoxxyAurasDB.profiles[newProfileName] then
        -- <<< Store pending data in temporary variables >>>
        self.pendingOverwriteTarget = newProfileName
        self.pendingOverwriteSource = currentActiveKey
        
        -- Show confirmation dialog (no longer need to pass data via args)
        StaticPopup_Show("BOXXYAURAS_OVERWRITE_PROFILE_CONFIRM") 
        return 
    end

    -- Original logic if profile does NOT exist
    local sourceProfile = GetCurrentProfileSettings() -- This now gets the correct profile based on character
    if not sourceProfile then
        print("|cffFF0000BoxxyAuras Profiles Error:|r Could not get settings for current profile to copy.")
        return
    end

    print(string.format("BoxxyAuras: Copying current profile ('%s') to new profile '%s'", currentActiveKey, newProfileName))
    BoxxyAurasDB.profiles[newProfileName] = CopyTable(sourceProfile)

    BoxxyAuras.Options.SelectProfile(nil, newProfileName) -- Switch to the newly created profile
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end

-- << NEW: Function called when overwrite is confirmed >>
function BoxxyAuras.Options:CopyProfileConfirmed(data)
    local targetName = data.targetName
    local sourceKey = data.sourceKey -- The key of the profile that was active when copy was initiated

    if not targetName or not sourceKey then 
        print("|cffFF0000BoxxyAuras Profiles Error:|r Missing data for CopyProfileConfirmed.")
        return 
    end

    -- Get the settings of the currently active profile (which was the source)
    local sourceProfile = GetCurrentProfileSettings() 
    if not sourceProfile then
        print("|cffFF0000BoxxyAuras Profiles Error:|r Could not get settings for source profile ('"..sourceKey.."') to overwrite.")
        return
    end

    print(string.format("BoxxyAuras: OVERWRITING profile '%s' with current settings from '%s'", targetName, sourceKey))
    BoxxyAurasDB.profiles[targetName] = CopyTable(sourceProfile)

    -- Switch this character to the newly overwritten profile
    BoxxyAuras.Options.SelectProfile(nil, targetName) 
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end

-- << Delete Profile (Actual deletion happens in confirmation dialog handler) >>
function BoxxyAuras.Options:DeleteProfileConfirmed()
    -- <<< Get the profile name this character is currently using >>>
    local profileToDelete = "Default"
    if BoxxyAuras.GetActiveProfileName then 
        profileToDelete = BoxxyAuras:GetActiveProfileName()
    end

    if not profileToDelete or profileToDelete == "Default" then
        print("BoxxyAuras Profiles: Cannot delete the 'Default' profile.")
        return
    end

    print(string.format("BoxxyAuras: Deleting profile '%s'", profileToDelete))
    BoxxyAurasDB.profiles[profileToDelete] = nil -- Remove from the global list

    -- <<< Reset any characters using this profile back to Default >>>
    if BoxxyAurasDB.characterProfileMap then
        local charKey = BoxxyAuras:GetCharacterKey()
        for character, assignedProfile in pairs(BoxxyAurasDB.characterProfileMap) do
            if assignedProfile == profileToDelete then
                BoxxyAurasDB.characterProfileMap[character] = "Default"
                if character == charKey then -- If it was the current character, trigger immediate switch
                    BoxxyAuras.Options.SelectProfile(nil, "Default")
                end
            end
        end
    end
    
    -- If the current character wasn't using the deleted profile, just update the UI
    if (BoxxyAurasDB.characterProfileMap and BoxxyAurasDB.characterProfileMap[BoxxyAuras:GetCharacterKey()] or "Default") ~= "Default" then
        self:UpdateProfileUI() -- Refresh dropdown if current char wasn't switched
        self:Load() -- Reload options based on current char's profile (which didn't change)
    end

    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end

--[[------------------------------------------------------------
-- Click Handlers (Moved UP)
--------------------------------------------------------------]]
-- Define alignment handlers as methods of BoxxyAuras.Options
function BoxxyAuras.Options:HandleBuffAlignmentClick(clickedButton, alignmentValue)
    -- <<< Get current profile settings >>>
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end -- Safety check
    if not currentSettings.buffFrameSettings then currentSettings.buffFrameSettings = {} end -- Ensure table exists

    clickedButton:SetChecked(true)
    if clickedButton ~= self.BuffAlignLeftCheck then self.BuffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= self.BuffAlignCenterCheck then self.BuffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= self.BuffAlignRightCheck then self.BuffAlignRightCheck:SetChecked(false) end
    -- <<< Save to PROFILE >>>
    currentSettings.buffFrameSettings.buffTextAlign = alignmentValue
    self:ApplyTextAlign() -- Trigger layout update (will read from profile)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

function BoxxyAuras.Options:HandleDebuffAlignmentClick(clickedButton, alignmentValue)
    -- <<< Get current profile settings >>>
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end -- Safety check
    if not currentSettings.debuffFrameSettings then currentSettings.debuffFrameSettings = {} end -- Ensure table exists

    clickedButton:SetChecked(true)
    if clickedButton ~= self.DebuffAlignLeftCheck then self.DebuffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= self.DebuffAlignCenterCheck then self.DebuffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= self.DebuffAlignRightCheck then self.DebuffAlignRightCheck:SetChecked(false) end
     -- <<< Save to PROFILE >>>
    currentSettings.debuffFrameSettings.debuffTextAlign = alignmentValue
    self:ApplyTextAlign() -- Trigger layout update (will read from profile)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

function BoxxyAuras.Options:HandleCustomAlignmentClick(clickedButton, alignmentValue)
    -- <<< Get current profile settings >>>
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then return end -- Safety check
    if not currentSettings.customFrameSettings then currentSettings.customFrameSettings = {} end -- Ensure table exists

    clickedButton:SetChecked(true)
    if clickedButton ~= self.CustomAlignLeftCheck then self.CustomAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= self.CustomAlignCenterCheck then self.CustomAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= self.CustomAlignRightCheck then self.CustomAlignRightCheck:SetChecked(false) end
    -- <<< Save to PROFILE >>>
    currentSettings.customFrameSettings.customTextAlign = alignmentValue
    self:ApplyTextAlign() -- Trigger layout update (will read from profile)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end


--[[------------------------------------------------------------
-- Main Load/Toggle Functions
--------------------------------------------------------------]]
function BoxxyAuras.Options:Load()
    local currentSettings = GetCurrentProfileSettings()
    if not currentSettings then
        -- print("BoxxyAuras Error: Could not get profile settings during Options Load.")
        return
    end

    if self.LockFramesCheck then self.LockFramesCheck:SetChecked(currentSettings.lockFrames) end
    if self.HideBlizzardCheck then self.HideBlizzardCheck:SetChecked(currentSettings.hideBlizzardAuras) end

    -- Buff Settings
    if currentSettings.buffFrameSettings then
        local buffSettings = currentSettings.buffFrameSettings
        local buffAlign = buffSettings.buffTextAlign or "CENTER"
        if self.BuffAlignLeftCheck then self.BuffAlignLeftCheck:SetChecked(buffAlign == "LEFT") end
        if self.BuffAlignCenterCheck then self.BuffAlignCenterCheck:SetChecked(buffAlign == "CENTER") end
        if self.BuffAlignRightCheck then self.BuffAlignRightCheck:SetChecked(buffAlign == "RIGHT") end

        local buffSize = buffSettings.iconSize or 24
        if self.BuffSizeSlider then
            self.BuffSizeSlider:SetValue(buffSize)
            if self.BuffSizeSlider.KeyLabel then self.BuffSizeSlider.KeyLabel:SetText(string.format("%dpx", buffSize)) end
            local min, max = self.BuffSizeSlider:GetMinMaxValues(); local range = max - min
            if range > 0 and self.BuffSizeSlider.VirtualThumb then self.BuffSizeSlider.VirtualThumb:SetPoint("CENTER", self.BuffSizeSlider, "LEFT", (buffSize - min) / range * self.BuffSizeSlider:GetWidth(), 0) end
        end
        
        -- Removed loading for BuffIconsWideSlider
    end

    -- Debuff Settings
    if currentSettings.debuffFrameSettings then
        local debuffSettings = currentSettings.debuffFrameSettings
        local debuffAlign = debuffSettings.debuffTextAlign or "CENTER"
        if self.DebuffAlignLeftCheck then self.DebuffAlignLeftCheck:SetChecked(debuffAlign == "LEFT") end
        if self.DebuffAlignCenterCheck then self.DebuffAlignCenterCheck:SetChecked(debuffAlign == "CENTER") end
        if self.DebuffAlignRightCheck then self.DebuffAlignRightCheck:SetChecked(debuffAlign == "RIGHT") end

        local debuffSize = debuffSettings.iconSize or 24
        if self.DebuffSizeSlider then
            self.DebuffSizeSlider:SetValue(debuffSize)
            if self.DebuffSizeSlider.KeyLabel then self.DebuffSizeSlider.KeyLabel:SetText(string.format("%dpx", debuffSize)) end
            local min, max = self.DebuffSizeSlider:GetMinMaxValues(); local range = max - min
            if range > 0 and self.DebuffSizeSlider.VirtualThumb then self.DebuffSizeSlider.VirtualThumb:SetPoint("CENTER", self.DebuffSizeSlider, "LEFT", (debuffSize - min) / range * self.DebuffSizeSlider:GetWidth(), 0) end
        end
        
        -- Removed loading for DebuffIconsWideSlider
    end

    -- Custom Settings
    if currentSettings.customFrameSettings then
        local customSettings = currentSettings.customFrameSettings
        local customAlign = customSettings.customTextAlign or "CENTER"
        if self.CustomAlignLeftCheck then self.CustomAlignLeftCheck:SetChecked(customAlign == "LEFT") end
        if self.CustomAlignCenterCheck then self.CustomAlignCenterCheck:SetChecked(customAlign == "CENTER") end
        if self.CustomAlignRightCheck then self.CustomAlignRightCheck:SetChecked(customAlign == "RIGHT") end

        local customSize = customSettings.iconSize or 24
        if self.CustomSizeSlider then
            self.CustomSizeSlider:SetValue(customSize)
            if self.CustomSizeSlider.KeyLabel then self.CustomSizeSlider.KeyLabel:SetText(string.format("%dpx", customSize)) end
            local min, max = self.CustomSizeSlider:GetMinMaxValues(); local range = max - min
            if range > 0 and self.CustomSizeSlider.VirtualThumb then self.CustomSizeSlider.VirtualThumb:SetPoint("CENTER", self.CustomSizeSlider, "LEFT", (customSize - min) / range * self.CustomSizeSlider:GetWidth(), 0) end
        end
        
        -- Removed loading for CustomIconsWideSlider
    end

    -- Scale Settings
    if self.ScaleSlider then
        local scaleVal = currentSettings.optionsScale or 1.0
        self.ScaleSlider:SetValue(scaleVal)
        if self.ScaleSlider.KeyLabel then self.ScaleSlider.KeyLabel:SetText(string.format("%.2f", scaleVal)) end
        local min, max = self.ScaleSlider:GetMinMaxValues(); local range = max - min
        if range > 0 and self.ScaleSlider.VirtualThumb then self.ScaleSlider.VirtualThumb:SetPoint("CENTER", self.ScaleSlider, "LEFT", (scaleVal - min) / range * self.ScaleSlider:GetWidth(), 0) end
    end

    self:ApplyScale(currentSettings.optionsScale or 1.0)
    self:ApplyLockState(currentSettings.lockFrames or false)

end

function BoxxyAuras.Options:Toggle()
    if self.Frame and self.Frame:IsShown() then
        self.Frame:Hide()
    elseif self.Frame then
        -- << MOVED Load() call >>
        -- Ensure the frame exists and is shown BEFORE loading data
        -- that might depend on UI elements initialized in OnShow.
        self.Frame:Show() -- Triggers OnShow which initializes dropdown structure
        self:Load()      -- Load settings into the controls
        -- OnShow also calls UpdateProfileUI at the end to set dropdown text/buttons
    else
        print("BoxxyAuras Error: Options Frame not found for Toggle.")
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

--[[------------------------------------------------------------
-- Slash Command & Static Popup (Define LAST)
--------------------------------------------------------------]]
SLASH_BOXXYAURASOPTIONS1 = "/boxxyauras"
SLASH_BOXXYAURASOPTIONS2 = "/ba"
SlashCmdList["BOXXYAURASOPTIONS"] = function(msg)
    local command = msg and string.lower(string.trim(msg)) or ""
    BoxxyAuras.Options:Toggle()
end

-- << NEW: Confirmation Dialog for Deleting Profile >>
StaticPopupDialogs["BOXXYAURAS_DELETE_PROFILE_CONFIRM"] = {
    text = "Are you sure you want to delete the profile |cffffd100%s|r?",
    button1 = ACCEPT, 
    button2 = CANCEL, 
    OnAccept = function(self, data)
        if BoxxyAuras.Options.DeleteProfileConfirmed then
            BoxxyAuras.Options:DeleteProfileConfirmed()
        end
    end,
    OnCancel = function(self, data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3 
}

-- <<< NEW: Confirmation Dialog for Overwriting Profile >>>
StaticPopupDialogs["BOXXYAURAS_OVERWRITE_PROFILE_CONFIRM"] = {
    -- <<< Remove %s placeholders from base text >>>
    text = "Profile already exists. Overwrite it with the current settings?", 
    button1 = ACCEPT,
    button2 = CANCEL,
    -- Remove data fields, no longer trying to pass via popup system
    hasEditBox = false, 
    
    OnShow = function(self)
        -- <<< Format text here using temp vars >>>
        local targetName = BoxxyAuras.Options.pendingOverwriteTarget or "UnknownTarget"
        local sourceKey = BoxxyAuras.Options.pendingOverwriteSource or "UnknownSource"
        -- Define the format string here instead
        local formatString = "Profile |cffffd100%s|r already exists. Overwrite it with the settings from profile |cffffd100%s|r?"
        self.text:SetFormattedText(formatString, targetName, sourceKey)
    end,

    OnAccept = function(self, systemData) 
        if BoxxyAuras.Options.CopyProfileConfirmed then
            -- <<< Get data from temporary variables >>>
            local targetName = BoxxyAuras.Options.pendingOverwriteTarget
            local sourceKey = BoxxyAuras.Options.pendingOverwriteSource
            -- <<< Clear temporary variables >>>
            BoxxyAuras.Options.pendingOverwriteTarget = nil
            BoxxyAuras.Options.pendingOverwriteSource = nil
            
            if type(targetName) ~= "string" or type(sourceKey) ~= "string" then
                 print("|cffFF0000BoxxyAuras Profile Error:|r Failed to retrieve valid profile names from temporary Options variables.")
                 print(string.format("  (targetName: %s, sourceKey: %s)", tostring(targetName), tostring(sourceKey)))
                 return
            end

            local eventData = { targetName = targetName, sourceKey = sourceKey }
            BoxxyAuras.Options:CopyProfileConfirmed(eventData)
        else
             print("|cffFF0000BoxxyAuras Profile Error:|r CopyProfileConfirmed function not found!")
        end
    end,
    OnCancel = function(self, data) 
        -- <<< Clear temporary variables on cancel too >>>
        BoxxyAuras.Options.pendingOverwriteTarget = nil
        BoxxyAuras.Options.pendingOverwriteSource = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true, -- Automatically calls OnCancel
    preferredIndex = 3
}