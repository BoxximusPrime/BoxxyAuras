local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras = BoxxyAuras or {}
BoxxyAuras.Options = {} -- Table to hold options elements

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

BoxxyAuras.Options.Frame = optionsFrame

-- >> ADDED: Create and Style Separate Background and Border Frames <<
local bg = CreateFrame("Frame", nil, optionsFrame);
bg:SetAllPoints();
bg:SetFrameLevel(optionsFrame:GetFrameLevel());
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(bg, "OptionsWindowBG", "backdrop", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(bg, "backdrop", 1, 1, 1, 0.95)
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not draw background.")
end

local border = CreateFrame("Frame", nil, optionsFrame);
border:SetAllPoints();
border:SetFrameLevel(optionsFrame:GetFrameLevel() + 1);
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(border, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(border, "border", 0.4, 0.4, 0.4, 1)
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not draw border.")
end

-- Title
local title = optionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Title")
title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -23)
title:SetText("BoxxyAuras Options")

-- Close Button
local closeBtn = CreateFrame("Button", "BoxxyAurasOptionsCloseButton", optionsFrame, "BAURASCloseBtn")
closeBtn:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -12, -12)
closeBtn:SetSize(12, 12)
closeBtn:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    optionsFrame:Hide()
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
        print(string.format("|cffFF0000BoxxyAuras Options Error:|r Could not style group container %s.", frame:GetName()))
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
local checkSpacing = 50 -- Horizontal spacing for checkboxes
local internalElementVSpacing = -12 -- << NEW: Standardized spacing between elements

--[[------------------------------------------------------------
-- Group 1: General Settings
--------------------------------------------------------------]]
local generalGroup = CreateFrame("Frame", "BoxxyAurasOptionsGeneralGroup", contentFrame) -- Parent to contentFrame
generalGroup:SetPoint("TOPLEFT", lastElement, "TOPLEFT", groupPadding, verticalSpacing) -- Position first group
generalGroup:SetWidth(groupWidth)
StyleGroupContainer(generalGroup)

lastInGroup = generalGroup -- Anchor first element to top of group
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Option: Lock Frames Checkbox
local lockFramesCheck = CreateFrame("CheckButton", "BoxxyAurasLockFramesCheckButton", generalGroup, "BAURASCheckBoxTemplate") -- Parent to generalGroup
lockFramesCheck:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
lockFramesCheck:SetText("Lock Frames")
lockFramesCheck:SetScript("OnClick", function(self)
    if not BoxxyAurasDB then return end
    local currentSavedState = BoxxyAurasDB.lockFrames or false
    local newState = not currentSavedState
    BoxxyAurasDB.lockFrames = newState
    BoxxyAuras.Options:ApplyLockState(newState)
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
    if not BoxxyAurasDB then return end
    local newState = not (BoxxyAurasDB.hideBlizzardAuras or false)
    BoxxyAurasDB.hideBlizzardAuras = newState
    BoxxyAuras.Options:ApplyLockState(newState)
    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.HideBlizzardCheck = hideBlizzardCheck
lastInGroup = hideBlizzardCheck

-- Set General Group Height
local lastBottomGen = lastInGroup and lastInGroup:GetBottom()
local groupTopGen = generalGroup:GetTop()
if lastBottomGen and groupTopGen then
    generalGroup:SetHeight(groupTopGen - lastBottomGen + groupPadding + 15) -- << REFINED: Add explicit bottom padding
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not calculate height for generalGroup.")
    generalGroup:SetHeight(50) -- Fallback height
end

-- Update lastElement for next group positioning
lastElement = generalGroup
verticalSpacing = -20 -- Space between groups

--[[------------------------------------------------------------
-- Group 2: Display Frame Settings (Alignment & Size)
--------------------------------------------------------------]]
local displayGroup = CreateFrame("Frame", "BoxxyAurasOptionsDisplayGroup", contentFrame) -- Parent to contentFrame
displayGroup:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing) -- Position below previous group
displayGroup:SetWidth(groupWidth)
StyleGroupContainer(displayGroup)

lastInGroup = displayGroup -- Reset for positioning within this group
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Buff Text Alignment Title
local buffAlignLabel = displayGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
buffAlignLabel:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
buffAlignLabel:SetText("Buff Text Alignment")
BoxxyAuras.Options.BuffAlignLabel = buffAlignLabel
lastInGroup = buffAlignLabel
groupVSpacing = -8 -- Keep smaller space after header

-- Buff Alignment Checkboxes (Left, Center, Right)
local buffAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignLeftCheck", displayGroup, "BAURASCheckBoxTemplate")
buffAlignLeftCheck:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
buffAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.BuffAlignLeftCheck = buffAlignLeftCheck
local buffAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignCenterCheck", displayGroup, "BAURASCheckBoxTemplate")
buffAlignCenterCheck:SetPoint("LEFT", buffAlignLeftCheck, "RIGHT", checkSpacing, 0)
buffAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.BuffAlignCenterCheck = buffAlignCenterCheck
local buffAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignRightCheck", displayGroup, "BAURASCheckBoxTemplate")
buffAlignRightCheck:SetPoint("LEFT", buffAlignCenterCheck, "RIGHT", checkSpacing, 0)
buffAlignRightCheck:SetText("Right")
BoxxyAuras.Options.BuffAlignRightCheck = buffAlignRightCheck
-- Function to handle mutual exclusivity and saving for BUFFS (Defined later)
buffAlignLeftCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "LEFT") end)
buffAlignCenterCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "CENTER") end)
buffAlignRightCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "RIGHT") end)
lastInGroup = buffAlignLeftCheck -- Anchor next section below the row
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Buff Icon Size Slider
local buffSizeLabel = displayGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
buffSizeLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
buffSizeLabel:SetText("Buff Icon Size")
BoxxyAuras.Options.BuffSizeLabel = buffSizeLabel
local buffSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsBuffSizeSlider", displayGroup, "BAURASSlider")
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
    if BoxxyAurasDB and BoxxyAurasDB.buffFrameSettings then BoxxyAurasDB.buffFrameSettings.iconSize = value; BoxxyAuras.Options:ApplyIconSizeChange("Buff") end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.BuffSizeSlider = buffSizeSlider
lastInGroup = buffSizeSlider
groupVSpacing = internalElementVSpacing - 3 -- << Standardized spacing (slightly more after slider)

-- Debuff Text Alignment Title
local debuffAlignLabel = displayGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
debuffAlignLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", -5, groupVSpacing)
debuffAlignLabel:SetText("Debuff Text Alignment")
BoxxyAuras.Options.DebuffAlignLabel = debuffAlignLabel
lastInGroup = debuffAlignLabel
groupVSpacing = -8 -- Keep smaller space after header

-- Debuff Alignment Checkboxes
local debuffAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignLeftCheck", displayGroup, "BAURASCheckBoxTemplate")
debuffAlignLeftCheck:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
debuffAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.DebuffAlignLeftCheck = debuffAlignLeftCheck
local debuffAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignCenterCheck", displayGroup, "BAURASCheckBoxTemplate")
debuffAlignCenterCheck:SetPoint("LEFT", debuffAlignLeftCheck, "RIGHT", checkSpacing, 0)
debuffAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.DebuffAlignCenterCheck = debuffAlignCenterCheck
local debuffAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignRightCheck", displayGroup, "BAURASCheckBoxTemplate")
debuffAlignRightCheck:SetPoint("LEFT", debuffAlignCenterCheck, "RIGHT", checkSpacing, 0)
debuffAlignRightCheck:SetText("Right")
BoxxyAuras.Options.DebuffAlignRightCheck = debuffAlignRightCheck
-- Function to handle mutual exclusivity and saving for DEBUFFS (Defined later)
debuffAlignLeftCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "LEFT") end)
debuffAlignCenterCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "CENTER") end)
debuffAlignRightCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "RIGHT") end)
lastInGroup = debuffAlignLeftCheck
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Debuff Icon Size Slider
local debuffSizeLabel = displayGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
debuffSizeLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
debuffSizeLabel:SetText("Debuff Icon Size")
BoxxyAuras.Options.DebuffSizeLabel = debuffSizeLabel
local debuffSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsDebuffSizeSlider", displayGroup, "BAURASSlider")
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
    if BoxxyAurasDB and BoxxyAurasDB.debuffFrameSettings then BoxxyAurasDB.debuffFrameSettings.iconSize = value; BoxxyAuras.Options:ApplyIconSizeChange("Debuff") end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.DebuffSizeSlider = debuffSizeSlider
lastInGroup = debuffSizeSlider
groupVSpacing = internalElementVSpacing - 3 -- << Standardized spacing (slightly more after slider)

-- Custom Text Alignment Title
local customAlignLabel = displayGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
customAlignLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", -5, groupVSpacing)
customAlignLabel:SetText("Custom Text Alignment")
BoxxyAuras.Options.CustomAlignLabel = customAlignLabel
lastInGroup = customAlignLabel
groupVSpacing = -8 -- Keep smaller space after header

-- Custom Alignment Checkboxes
local customAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasCustomAlignLeftCheck", displayGroup, "BAURASCheckBoxTemplate")
customAlignLeftCheck:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
customAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.CustomAlignLeftCheck = customAlignLeftCheck
local customAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasCustomAlignCenterCheck", displayGroup, "BAURASCheckBoxTemplate")
customAlignCenterCheck:SetPoint("LEFT", customAlignLeftCheck, "RIGHT", checkSpacing, 0)
customAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.CustomAlignCenterCheck = customAlignCenterCheck
local customAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasCustomAlignRightCheck", displayGroup, "BAURASCheckBoxTemplate")
customAlignRightCheck:SetPoint("LEFT", customAlignCenterCheck, "RIGHT", checkSpacing, 0)
customAlignRightCheck:SetText("Right")
BoxxyAuras.Options.CustomAlignRightCheck = customAlignRightCheck
-- Function to handle mutual exclusivity and saving for CUSTOM (Defined later)
customAlignLeftCheck:SetScript("OnClick", function(self) HandleCustomAlignmentClick(self, "LEFT") end)
customAlignCenterCheck:SetScript("OnClick", function(self) HandleCustomAlignmentClick(self, "CENTER") end)
customAlignRightCheck:SetScript("OnClick", function(self) HandleCustomAlignmentClick(self, "RIGHT") end)
lastInGroup = customAlignLeftCheck
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Custom Icon Size Slider
local customSizeLabel = displayGroup:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
customSizeLabel:SetPoint("TOPLEFT", lastInGroup, "BOTTOMLEFT", 0, groupVSpacing)
customSizeLabel:SetText("Custom Icon Size")
BoxxyAuras.Options.CustomSizeLabel = customSizeLabel
local customSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsCustomSizeSlider", displayGroup, "BAURASSlider")
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
    if BoxxyAurasDB and BoxxyAurasDB.customFrameSettings then BoxxyAurasDB.customFrameSettings.iconSize = value; BoxxyAuras.Options:ApplyIconSizeChange("Custom") end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.CustomSizeSlider = customSizeSlider
lastInGroup = customSizeSlider

-- Set Display Group Height
local lastBottomDisp = lastInGroup and lastInGroup:GetBottom()
local groupTopDisp = displayGroup:GetTop()
if lastBottomDisp and groupTopDisp then
    displayGroup:SetHeight(groupTopDisp - lastBottomDisp + groupPadding + 15) -- << REFINED: Add explicit bottom padding
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not calculate height for displayGroup.")
    displayGroup:SetHeight(200) -- Fallback height
end

-- Update lastElement for next group positioning
lastElement = displayGroup
verticalSpacing = -20 -- Space between groups

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
scaleSliderLabel:SetText("Window Scale")
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
    if BoxxyAurasDB then BoxxyAurasDB.optionsScale = value; BoxxyAuras.Options:ApplyScale(value) end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)
BoxxyAuras.Options.ScaleSlider = scaleSlider
lastInGroup = scaleSlider

-- Set Scale Group Height
local lastBottomScale = lastInGroup and lastInGroup:GetBottom()
local groupTopScale = scaleGroup:GetTop()
if lastBottomScale and groupTopScale then
    scaleGroup:SetHeight(groupTopScale - lastBottomScale + groupPadding + 15) -- << REFINED: Add explicit bottom padding
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not calculate height for scaleGroup.")
    scaleGroup:SetHeight(50) -- Fallback height
end

-- Update lastElement for next group positioning
lastElement = scaleGroup
verticalSpacing = -20 -- Space between groups

--[[------------------------------------------------------------
-- Group 4: Management
--------------------------------------------------------------]]
local manageGroup = CreateFrame("Frame", "BoxxyAurasOptionsManageGroup", contentFrame)
manageGroup:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing)
manageGroup:SetWidth(groupWidth)
StyleGroupContainer(manageGroup)

lastInGroup = manageGroup
groupVSpacing = internalElementVSpacing -- << Standardized spacing

-- Button to Open Custom Aura Options
local openCustomOptionsButton = CreateFrame("Button", "BoxxyAurasOpenCustomOptionsButton", manageGroup, "BAURASButtonTemplate")
openCustomOptionsButton:SetPoint("TOPLEFT", lastInGroup, "TOPLEFT", groupPadding + 5, groupVSpacing)
openCustomOptionsButton:SetWidth(manageGroup:GetWidth() - (groupPadding * 2) - 10) -- Fit within group padding
openCustomOptionsButton:SetHeight(25)
openCustomOptionsButton:SetText("Manage Custom Aura List...")
openCustomOptionsButton:SetScript("OnClick", function()
    if BoxxyAuras.CustomOptions and BoxxyAuras.CustomOptions.Toggle then BoxxyAuras.CustomOptions:Toggle()
    else print("|cffFF0000BoxxyAuras Error:|r Custom Options module not loaded or Toggle function missing.") end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)
BoxxyAuras.Options.OpenCustomOptionsButton = openCustomOptionsButton
lastInGroup = openCustomOptionsButton

-- Set Management Group Height
local lastBottomManage = lastInGroup and lastInGroup:GetBottom()
local groupTopManage = manageGroup:GetTop()
if lastBottomManage and groupTopManage then
    manageGroup:SetHeight(groupTopManage - lastBottomManage + groupPadding + 15) -- << REFINED: Add explicit bottom padding
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not calculate height for manageGroup.")
    manageGroup:SetHeight(50) -- Fallback height
end

-- Update last element for safety, though nothing comes after currently
lastElement = manageGroup

--[[------------------------------------------------------------
-- Functions to Load/Save/Toggle
--------------------------------------------------------------]]
-- Define alignment handlers (local functions)
local function HandleBuffAlignmentClick(clickedButton, alignmentValue)
    if not BoxxyAurasDB then return end
    if not BoxxyAurasDB.buffFrameSettings then BoxxyAurasDB.buffFrameSettings = {} end
    clickedButton:SetChecked(true)
    if clickedButton ~= buffAlignLeftCheck then buffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= buffAlignCenterCheck then buffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= buffAlignRightCheck then buffAlignRightCheck:SetChecked(false) end
    BoxxyAurasDB.buffFrameSettings.buffTextAlign = alignmentValue
    BoxxyAuras.Options:ApplyTextAlign()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end
local function HandleDebuffAlignmentClick(clickedButton, alignmentValue)
    if not BoxxyAurasDB then return end
    if not BoxxyAurasDB.debuffFrameSettings then BoxxyAurasDB.debuffFrameSettings = {} end
    clickedButton:SetChecked(true)
    if clickedButton ~= debuffAlignLeftCheck then debuffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= debuffAlignCenterCheck then debuffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= debuffAlignRightCheck then debuffAlignRightCheck:SetChecked(false) end
    BoxxyAurasDB.debuffFrameSettings.debuffTextAlign = alignmentValue
    BoxxyAuras.Options:ApplyTextAlign()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end
local function HandleCustomAlignmentClick(clickedButton, alignmentValue)
    if not BoxxyAurasDB then return end
    if not BoxxyAurasDB.customFrameSettings then BoxxyAurasDB.customFrameSettings = {} end
    clickedButton:SetChecked(true)
    if clickedButton ~= customAlignLeftCheck then customAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= customAlignCenterCheck then customAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= customAlignRightCheck then customAlignRightCheck:SetChecked(false) end
    BoxxyAurasDB.customFrameSettings.customTextAlign = alignmentValue
    BoxxyAuras.Options:ApplyTextAlign()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Main Options Functions
function BoxxyAuras.Options:Load()
    if not BoxxyAurasDB then
        print("BoxxyAuras Error: BoxxyAurasDB not found during Options Load.")
        return
    end
    -- Ensure nested tables exist for safety before reading
    if not BoxxyAurasDB.buffFrameSettings then BoxxyAurasDB.buffFrameSettings = {} end
    if not BoxxyAurasDB.debuffFrameSettings then BoxxyAurasDB.debuffFrameSettings = {} end
    if not BoxxyAurasDB.customFrameSettings then BoxxyAurasDB.customFrameSettings = {} end

    -- Initialize defaults if necessary
    if BoxxyAurasDB.lockFrames == nil then BoxxyAurasDB.lockFrames = false end
    if BoxxyAurasDB.optionsScale == nil then BoxxyAurasDB.optionsScale = 1.0 end
    if BoxxyAurasDB.buffFrameSettings.buffTextAlign == nil then BoxxyAurasDB.buffFrameSettings.buffTextAlign = "CENTER" end
    if BoxxyAurasDB.debuffFrameSettings.debuffTextAlign == nil then BoxxyAurasDB.debuffFrameSettings.debuffTextAlign = "CENTER" end
    if BoxxyAurasDB.customFrameSettings.customTextAlign == nil then BoxxyAurasDB.customFrameSettings.customTextAlign = "CENTER" end
    if BoxxyAurasDB.buffFrameSettings.iconSize == nil then BoxxyAurasDB.buffFrameSettings.iconSize = 24 end
    if BoxxyAurasDB.debuffFrameSettings.iconSize == nil then BoxxyAurasDB.debuffFrameSettings.iconSize = 24 end
    if BoxxyAurasDB.customFrameSettings.iconSize == nil then BoxxyAurasDB.customFrameSettings.iconSize = 24 end
    if BoxxyAurasDB.hideBlizzardAuras == nil then BoxxyAurasDB.hideBlizzardAuras = true end

    -- Set Lock checkbox state
    if self.LockFramesCheck then self.LockFramesCheck:SetChecked(BoxxyAurasDB.lockFrames) end
    -- Set Hide Blizzard checkbox state
    if self.HideBlizzardCheck then self.HideBlizzardCheck:SetChecked(BoxxyAurasDB.hideBlizzardAuras) end

    -- Load BUFF text alignment setting
    local buffAlign = BoxxyAurasDB.buffFrameSettings.buffTextAlign
    if self.BuffAlignLeftCheck then self.BuffAlignLeftCheck:SetChecked(buffAlign == "LEFT") end
    if self.BuffAlignCenterCheck then self.BuffAlignCenterCheck:SetChecked(buffAlign == "CENTER") end
    if self.BuffAlignRightCheck then self.BuffAlignRightCheck:SetChecked(buffAlign == "RIGHT") end

    -- Load Buff Icon Size Slider
    if self.BuffSizeSlider then
        local buffSize = BoxxyAurasDB.buffFrameSettings.iconSize
        self.BuffSizeSlider:SetValue(buffSize)
        if self.BuffSizeSlider.KeyLabel then self.BuffSizeSlider.KeyLabel:SetText(string.format("%dpx", buffSize)) end
        local min, max = self.BuffSizeSlider:GetMinMaxValues(); local range = max - min
        if range > 0 and self.BuffSizeSlider.VirtualThumb then self.BuffSizeSlider.VirtualThumb:SetPoint("CENTER", self.BuffSizeSlider, "LEFT", (buffSize - min) / range * self.BuffSizeSlider:GetWidth(), 0) end
    end

    -- Load DEBUFF text alignment setting
    local debuffAlign = BoxxyAurasDB.debuffFrameSettings.debuffTextAlign
    if self.DebuffAlignLeftCheck then self.DebuffAlignLeftCheck:SetChecked(debuffAlign == "LEFT") end
    if self.DebuffAlignCenterCheck then self.DebuffAlignCenterCheck:SetChecked(debuffAlign == "CENTER") end
    if self.DebuffAlignRightCheck then self.DebuffAlignRightCheck:SetChecked(debuffAlign == "RIGHT") end

    -- Load Debuff Icon Size Slider
    if self.DebuffSizeSlider then
        local debuffSize = BoxxyAurasDB.debuffFrameSettings.iconSize
        self.DebuffSizeSlider:SetValue(debuffSize)
        if self.DebuffSizeSlider.KeyLabel then self.DebuffSizeSlider.KeyLabel:SetText(string.format("%dpx", debuffSize)) end
        local min, max = self.DebuffSizeSlider:GetMinMaxValues(); local range = max - min
        if range > 0 and self.DebuffSizeSlider.VirtualThumb then self.DebuffSizeSlider.VirtualThumb:SetPoint("CENTER", self.DebuffSizeSlider, "LEFT", (debuffSize - min) / range * self.DebuffSizeSlider:GetWidth(), 0) end
    end

    -- Load CUSTOM text alignment setting
    local customAlign = BoxxyAurasDB.customFrameSettings.customTextAlign
    if self.CustomAlignLeftCheck then self.CustomAlignLeftCheck:SetChecked(customAlign == "LEFT") end
    if self.CustomAlignCenterCheck then self.CustomAlignCenterCheck:SetChecked(customAlign == "CENTER") end
    if self.CustomAlignRightCheck then self.CustomAlignRightCheck:SetChecked(customAlign == "RIGHT") end

    -- Load Custom Icon Size Slider
    if self.CustomSizeSlider then
        local customSize = BoxxyAurasDB.customFrameSettings.iconSize
        self.CustomSizeSlider:SetValue(customSize)
        if self.CustomSizeSlider.KeyLabel then self.CustomSizeSlider.KeyLabel:SetText(string.format("%dpx", customSize)) end
        local min, max = self.CustomSizeSlider:GetMinMaxValues(); local range = max - min
        if range > 0 and self.CustomSizeSlider.VirtualThumb then self.CustomSizeSlider.VirtualThumb:SetPoint("CENTER", self.CustomSizeSlider, "LEFT", (customSize - min) / range * self.CustomSizeSlider:GetWidth(), 0) end
    end

    -- Set Scale slider value
    if self.ScaleSlider then
        local scaleVal = BoxxyAurasDB.optionsScale
        self.ScaleSlider:SetValue(scaleVal)
        if self.ScaleSlider.KeyLabel then self.ScaleSlider.KeyLabel:SetText(string.format("%.2f", scaleVal)) end
        local min, max = self.ScaleSlider:GetMinMaxValues(); local range = max - min
        if range > 0 and self.ScaleSlider.VirtualThumb then self.ScaleSlider.VirtualThumb:SetPoint("CENTER", self.ScaleSlider, "LEFT", (scaleVal - min) / range * self.ScaleSlider:GetWidth(), 0) end
    end

    -- Apply the loaded states that affect visuals immediately
    self:ApplyLockState(BoxxyAurasDB.lockFrames)
    self:ApplyScale(BoxxyAurasDB.optionsScale)
    self:ApplyTextAlign()
end

function BoxxyAuras.Options:Toggle()
    if self.Frame and self.Frame:IsShown() then
        self.Frame:Hide()
    elseif self.Frame then
        self:Load() -- Load settings when showing
        self.Frame:Show()
    else
        print("BoxxyAuras Error: Options Frame not found for Toggle.")
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

function BoxxyAuras.Options:ApplyLockState(lockState)
    local buffFrame = _G["BoxxyBuffDisplayFrame"]
    local debuffFrame = _G["BoxxyDebuffDisplayFrame"]
    local customFrame = _G["BoxxyCustomDisplayFrame"]

    local function ApplyToFrame(frame, baseName)
        if not frame then return end
        frame:SetMovable(not lockState)
        frame.isLocked = lockState

        if frame.handles then
            for name, handle in pairs(frame.handles) do
                handle:EnableMouse(not lockState)
                if lockState then handle:Hide() else handle:Show() end
            end
        end

        local titleLabelName = baseName .. "TitleLabel"
        local titleLabel = _G[titleLabelName]
        if titleLabel then
            if lockState then titleLabel:Hide() else titleLabel:Show() end
        end

        local bgAlpha = lockState and 0 or (BoxxyAuras.Config.MainFrameBGColorNormal and BoxxyAuras.Config.MainFrameBGColorNormal.a) or 0.85
        local borderAlpha = lockState and 0 or (BoxxyAuras.Config.BorderColor and BoxxyAuras.Config.BorderColor.a) or 0.8
        if frame.backdropTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            local currentBgColor = frame.backdropTextures[5] and {frame.backdropTextures[5]:GetVertexColor()} or {0.1, 0.1, 0.1}
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", currentBgColor[1], currentBgColor[2], currentBgColor[3], bgAlpha)
        end
         if frame.borderTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            local currentBorderColor = frame.borderTextures[5] and {frame.borderTextures[5]:GetVertexColor()} or {0.4, 0.4, 0.4}
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", currentBorderColor[1], currentBorderColor[2], currentBorderColor[3], borderAlpha)
        end
    end

    ApplyToFrame(buffFrame, "BuffFrame")
    ApplyToFrame(debuffFrame, "DebuffFrame")
    ApplyToFrame(customFrame, "CustomFrame")
end

function BoxxyAuras.Options:ApplyScale(scaleValue)
    if not scaleValue then return end
    local buffFrame = _G["BoxxyBuffDisplayFrame"]
    local debuffFrame = _G["BoxxyDebuffDisplayFrame"]
    local customFrame = _G["BoxxyCustomDisplayFrame"]
    local optionsFrm = self.Frame
    local customOptionsFrm = BoxxyAuras.CustomOptions and BoxxyAuras.CustomOptions.Frame

    if buffFrame then buffFrame:SetScale(scaleValue) end
    if debuffFrame then debuffFrame:SetScale(scaleValue) end
    if customFrame then customFrame:SetScale(scaleValue) end
    if optionsFrm then optionsFrm:SetScale(scaleValue) end
    if customOptionsFrm then customOptionsFrm:SetScale(scaleValue) end
end

function BoxxyAuras.Options:ApplyTextAlign()
    if BoxxyAuras.TriggerLayout then
        BoxxyAuras.TriggerLayout("Buff")
        BoxxyAuras.TriggerLayout("Debuff")
        BoxxyAuras.TriggerLayout("Custom")
    else
        print("BoxxyAuras Error: TriggerLayout function not found in ApplyTextAlign.")
    end
end

function BoxxyAuras.Options:ApplyIconSizeChange(frameType)
    print(string.format("Applying Icon Size change for %s", frameType))
    local iconList, settingsKey, targetFrame = nil, nil, nil
    local newSize = 24

    if frameType == "Buff" then
        iconList, settingsKey, targetFrame = BoxxyAuras.buffIcons, "buffFrameSettings", _G["BoxxyBuffDisplayFrame"]
    elseif frameType == "Debuff" then
        iconList, settingsKey, targetFrame = BoxxyAuras.debuffIcons, "debuffFrameSettings", _G["BoxxyDebuffDisplayFrame"]
    elseif frameType == "Custom" then
        iconList, settingsKey, targetFrame = BoxxyAuras.customIcons, "customFrameSettings", _G["BoxxyCustomDisplayFrame"]
    else
        print("ApplyIconSizeChange Error: Invalid frameType")
        return
    end

    if not targetFrame then print("ApplyIconSizeChange Error: Target frame not found."); return end

    local currentNumIconsWide = 6
    if BoxxyAurasDB and BoxxyAurasDB[settingsKey] then
        newSize = BoxxyAurasDB[settingsKey].iconSize or 24
        currentNumIconsWide = BoxxyAurasDB[settingsKey].numIconsWide or 6
    end

    if BoxxyAuras.CalculateFrameWidth then
        local newWidth = BoxxyAuras.CalculateFrameWidth(currentNumIconsWide, newSize)
        targetFrame:SetWidth(newWidth)
    else
        print("ApplyIconSizeChange Warning: CalculateFrameWidth function not found.")
    end

    if iconList and iconList[1] and iconList[1].Resize then
        for _, auraIcon in ipairs(iconList) do
            if auraIcon.frame then auraIcon:Resize(newSize) end
        end
        if BoxxyAuras.TriggerLayout then BoxxyAuras.TriggerLayout(frameType)
        else print("BoxxyAuras Error: TriggerLayout not found after resizing icons.") end
    else
         print(string.format("BoxxyAuras Warning: Could not resize icons for %s. List or Resize method missing?", frameType))
         if BoxxyAuras.InitializeAuras then BoxxyAuras.InitializeAuras()
         else print("BoxxyAuras Error: InitializeAuras not found as fallback.") end
    end
end

--[[------------------------------------------------------------
-- Slash Command
--------------------------------------------------------------]]
SLASH_BOXXYAURASOPTIONS1 = "/boxxyauras"
SLASH_BOXXYAURASOPTIONS2 = "/ba"
SlashCmdList["BOXXYAURASOPTIONS"] = function(msg)
    local command = msg and string.lower(string.trim(msg)) or ""
    if command == "reset" then
        print("BoxxyAuras: Resetting frame settings to default.")
        local defaultPadding = BoxxyAuras.Config.Padding or 6
        local defaultIconSize_ForCalc = 24
        local defaultTextHeight = BoxxyAuras.Config.TextHeight or 8
        local defaultIconH = defaultIconSize_ForCalc + defaultTextHeight + (defaultPadding * 2)
        local defaultFramePadding = BoxxyAuras.Config.FramePadding or 6
        local defaultMinHeight = defaultFramePadding + defaultIconH + defaultFramePadding
        local defaultIconsWide_Reset = 6

        local defaultBuffFrameSettings_Reset = { x = 0, y = -150, anchor = "TOP", height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, buffTextAlign = "CENTER", iconSize = 24 }
        local defaultDebuffFrameSettings_Reset = { x = 0, y = -150 - defaultMinHeight - 30, anchor = "TOP", height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, debuffTextAlign = "CENTER", iconSize = 24 }
        local defaultCustomFrameSettings_Reset = { x = 0, y = -150 - defaultMinHeight - 60, anchor = "TOP", height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, customTextAlign = "CENTER", iconSize = 24 }

        BoxxyAurasDB.buffFrameSettings = CopyTable(defaultBuffFrameSettings_Reset)
        BoxxyAurasDB.debuffFrameSettings = CopyTable(defaultDebuffFrameSettings_Reset)
        BoxxyAurasDB.customFrameSettings = CopyTable(defaultCustomFrameSettings_Reset) -- Reset custom frame too

        local applyFunc = BoxxyAuras.ApplySettings
        if not applyFunc then print("BoxxyAuras Error: ApplySettings function not found for reset."); return end

        local buffFrame = _G["BoxxyBuffDisplayFrame"]
        local debuffFrame = _G["BoxxyDebuffDisplayFrame"]
        local customFrame = _G["BoxxyCustomDisplayFrame"]

        if buffFrame then applyFunc(buffFrame, BoxxyAurasDB.buffFrameSettings, "Buff Frame") end
        if debuffFrame then applyFunc(debuffFrame, BoxxyAurasDB.debuffFrameSettings, "Debuff Frame") end
        if customFrame then applyFunc(customFrame, BoxxyAurasDB.customFrameSettings, "Custom Frame") end -- Apply reset to custom

        if BoxxyAuras.InitializeAuras then BoxxyAuras.InitializeAuras()
        elseif BoxxyAuras.UpdateAuras then BoxxyAuras.UpdateAuras() end

        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    else
        BoxxyAuras.Options:Toggle()
    end
end