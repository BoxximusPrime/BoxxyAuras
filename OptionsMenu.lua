local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras = BoxxyAuras or {}
BoxxyAuras.Options = {} -- Table to hold options elements

--[[------------------------------------------------------------
-- Create Main Options Frame
--------------------------------------------------------------]]
local optionsFrame = CreateFrame("Frame", "BoxxyAurasOptionsFrame", UIParent, "BackdropTemplate")
optionsFrame:SetSize(250, 300) -- Adjusted size
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
-- Create the background frame
local bg = CreateFrame("Frame", nil, optionsFrame);
bg:SetAllPoints();
bg:SetFrameLevel(optionsFrame:GetFrameLevel()); -- Set frame level relative to parent
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(bg, "OptionsWindowBG", "backdrop", 0) -- Use the new texture key
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(bg, "backdrop", 1, 1, 1, 0.95) -- Adjust color/alpha as needed (e.g., white, slightly transparent)
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not draw background.")
end

-- Create the border frame
local border = CreateFrame("Frame", nil, optionsFrame);
border:SetAllPoints();
border:SetFrameLevel(optionsFrame:GetFrameLevel() + 1); -- Ensure border is above background
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(border, "EdgedBorder", "border", 0) -- Use the same EdgedBorder
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(border, "border", 0.4, 0.4, 0.4, 1) -- Border color
else
    print("|cffFF0000BoxxyAuras Options Error:|r Could not draw border.")
end

-- Title
local title = optionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Title") -- Using standard font for now
title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -23)
title:SetText("BoxxyAuras Options")

-- Close Button (Using Custom Template)
local closeBtn = CreateFrame("Button", "BoxxyAurasOptionsCloseButton", optionsFrame, "BAURASCloseBtn") 
closeBtn:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -12, -12) -- Adjusted position slightly if needed
closeBtn:SetSize(12, 12) -- Set size explicitly if template doesn't
closeBtn:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) -- Or custom sound from template if defined
    optionsFrame:Hide()
end)

--[[------------------------------------------------------------
-- Scroll Frame & Content
--------------------------------------------------------------]]
local scrollFrame = CreateFrame("ScrollFrame", "BoxxyAurasOptionsScrollFrame", optionsFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 10, -50)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local contentFrame = CreateFrame("Frame", "BoxxyAurasOptionsContentFrame", scrollFrame)
contentFrame:SetSize(scrollFrame:GetWidth(), 400) -- Initial height, can grow
scrollFrame:SetScrollChild(contentFrame)

--[[------------------------------------------------------------
-- Option: Lock Frames Checkbox
--------------------------------------------------------------]]
local lockFramesCheck = CreateFrame("CheckButton", "BoxxyAurasLockFramesCheckButton", contentFrame, "BAURASCheckBoxTemplate") 
lockFramesCheck:SetPoint("TOPLEFT", 10, -10) -- Initial Y offset
lockFramesCheck:SetText("Lock Frames") -- Use the custom template's SetText method

-- OnClick saves the setting
lockFramesCheck:SetScript("OnClick", function(self)
    if not BoxxyAurasDB then return end -- Safety check
    
    -- 1. Read the CURRENT saved state
    local currentSavedState = BoxxyAurasDB.lockFrames or false 
    
    -- 2. Determine the NEW state
    local newState = not currentSavedState
    
    -- 3. Save the NEW state
    BoxxyAurasDB.lockFrames = newState
    
    -- 4. Apply the NEW state's effects
    BoxxyAuras.Options:ApplyLockState(newState)
    
    -- 5. Manually set the checkbox's visual state to match the NEW state
    self:SetChecked(newState)
    
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)

BoxxyAuras.Options.LockFramesCheck = lockFramesCheck
-- Space before next option
local lastElement = lockFramesCheck 
local verticalSpacing = -15

--[[------------------------------------------------------------
-- Option: Hide Blizzard Auras Checkbox
--------------------------------------------------------------]]
local hideBlizzardCheck = CreateFrame("CheckButton", "BoxxyAurasHideBlizzardCheckButton", contentFrame, "BAURASCheckBoxTemplate") 
hideBlizzardCheck:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing) -- Position below previous
hideBlizzardCheck:SetText("Hide Default Blizzard Auras")

hideBlizzardCheck:SetScript("OnClick", function(self)
    if not BoxxyAurasDB then return end

    local newState = not (BoxxyAurasDB.hideBlizzardAuras or false) 
    BoxxyAurasDB.hideBlizzardAuras = newState

    -- Call the function from the main addon table now
    BoxxyAuras.ApplyBlizzardAuraVisibility(newState)

    self:SetChecked(newState)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)

BoxxyAuras.Options.HideBlizzardCheck = hideBlizzardCheck
-- Update last element for next anchor
lastElement = hideBlizzardCheck
verticalSpacing = -15 -- Reset/adjust spacing

--[[------------------------------------------------------------
-- Option: Buff Text Alignment
--------------------------------------------------------------]]
-- Title for the alignment options
local buffAlignLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header") 
buffAlignLabel:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing - 10) -- Position below previous, adjust spacing
buffAlignLabel:SetText("Buff Text Alignment")
BoxxyAuras.Options.BuffAlignLabel = buffAlignLabel

-- Checkboxes (arranged horizontally)
local checkSpacing = 50 -- DOUBLED spacing

-- Left Align Checkbox (Buffs)
local buffAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignLeftCheck", contentFrame, "BAURASCheckBoxTemplate") 
buffAlignLeftCheck:SetPoint("TOPLEFT", buffAlignLabel, "BOTTOMLEFT", 0, -8)
buffAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.BuffAlignLeftCheck = buffAlignLeftCheck

-- Center Align Checkbox (Buffs)
local buffAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignCenterCheck", contentFrame, "BAURASCheckBoxTemplate") 
buffAlignCenterCheck:SetPoint("LEFT", buffAlignLeftCheck, "RIGHT", checkSpacing, 0) -- Position next to Left
buffAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.BuffAlignCenterCheck = buffAlignCenterCheck

-- Right Align Checkbox (Buffs)
local buffAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasBuffAlignRightCheck", contentFrame, "BAURASCheckBoxTemplate") 
buffAlignRightCheck:SetPoint("LEFT", buffAlignCenterCheck, "RIGHT", checkSpacing, 0) -- Position next to Center with EXTRA spacing
buffAlignRightCheck:SetText("Right")
BoxxyAuras.Options.BuffAlignRightCheck = buffAlignRightCheck

-- Function to handle mutual exclusivity and saving for BUFFS
local function HandleBuffAlignmentClick(clickedButton, alignmentValue)
    if not BoxxyAurasDB then return end
    -- Ensure the settings table exists
    if not BoxxyAurasDB.buffFrameSettings then BoxxyAurasDB.buffFrameSettings = {} end 

    -- 1. Force the clicked button to be checked
    clickedButton:SetChecked(true)

    -- 2. Uncheck the others in this group
    if clickedButton ~= buffAlignLeftCheck then buffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= buffAlignCenterCheck then buffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= buffAlignRightCheck then buffAlignRightCheck:SetChecked(false) end
    
    -- 3. Save the new value INSIDE buffFrameSettings
    BoxxyAurasDB.buffFrameSettings.buffTextAlign = alignmentValue 
    
    -- Call function to apply alignment change immediately
    BoxxyAuras.Options:ApplyTextAlign()
    
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Assign OnClick scripts for BUFFS
buffAlignLeftCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "LEFT") end)
buffAlignCenterCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "CENTER") end)
buffAlignRightCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "RIGHT") end)

-- Update last element for next anchor
lastElement = buffAlignLeftCheck -- Anchor next section below the row of checkboxes
verticalSpacing = -20 -- Add more vertical space

--[[------------------------------------------------------------
-- Option: Debuff Text Alignment
--------------------------------------------------------------]]
-- Title for the alignment options
local debuffAlignLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header") 
debuffAlignLabel:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", -5, verticalSpacing) -- Position below Buff Size Slider
debuffAlignLabel:SetText("Debuff Text Alignment")
BoxxyAuras.Options.DebuffAlignLabel = debuffAlignLabel

-- Checkboxes (arranged horizontally)
-- Note: Reuses the checkSpacing value defined above
-- Left Align Checkbox (Debuffs)
local debuffAlignLeftCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignLeftCheck", contentFrame, "BAURASCheckBoxTemplate") 
debuffAlignLeftCheck:SetPoint("TOPLEFT", debuffAlignLabel, "BOTTOMLEFT", 0, -8)
debuffAlignLeftCheck:SetText("Left")
BoxxyAuras.Options.DebuffAlignLeftCheck = debuffAlignLeftCheck

-- Center Align Checkbox (Debuffs)
local debuffAlignCenterCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignCenterCheck", contentFrame, "BAURASCheckBoxTemplate") 
debuffAlignCenterCheck:SetPoint("LEFT", debuffAlignLeftCheck, "RIGHT", checkSpacing, 0) -- Position next to Left
debuffAlignCenterCheck:SetText("Center")
BoxxyAuras.Options.DebuffAlignCenterCheck = debuffAlignCenterCheck

-- Right Align Checkbox (Debuffs)
local debuffAlignRightCheck = CreateFrame("CheckButton", "BoxxyAurasDebuffAlignRightCheck", contentFrame, "BAURASCheckBoxTemplate") 
debuffAlignRightCheck:SetPoint("LEFT", debuffAlignCenterCheck, "RIGHT", checkSpacing, 0) -- Position next to Center with EXTRA spacing
debuffAlignRightCheck:SetText("Right")
BoxxyAuras.Options.DebuffAlignRightCheck = debuffAlignRightCheck

-- Function to handle mutual exclusivity and saving for DEBUFFS
local function HandleDebuffAlignmentClick(clickedButton, alignmentValue)
    if not BoxxyAurasDB then return end
    -- Ensure the settings table exists
    if not BoxxyAurasDB.debuffFrameSettings then BoxxyAurasDB.debuffFrameSettings = {} end

    -- 1. Force the clicked button to be checked
    clickedButton:SetChecked(true)

    -- 2. Uncheck the others in this group
    if clickedButton ~= debuffAlignLeftCheck then debuffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= debuffAlignCenterCheck then debuffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= debuffAlignRightCheck then debuffAlignRightCheck:SetChecked(false) end

    -- 3. Save the new value INSIDE debuffFrameSettings
    BoxxyAurasDB.debuffFrameSettings.debuffTextAlign = alignmentValue 
    
    -- Call function to apply alignment change immediately
    BoxxyAuras.Options:ApplyTextAlign()

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Assign OnClick scripts for DEBUFFS
debuffAlignLeftCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "LEFT") end)
debuffAlignCenterCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "CENTER") end)
debuffAlignRightCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "RIGHT") end)

-- Update last element for next anchor
lastElement = debuffAlignLeftCheck -- Anchor next section below the row of checkboxes
verticalSpacing = -20 -- Reset/adjust spacing

--[[------------------------------------------------------------
-- Option: Buff Icon Size Slider
--------------------------------------------------------------]]
local buffSizeLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header") 
buffSizeLabel:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing) -- Position below buff align checks
buffSizeLabel:SetText("Buff Icon Size")
BoxxyAuras.Options.BuffSizeLabel = buffSizeLabel

local buffSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsBuffSizeSlider", contentFrame, "BAURASSlider")
buffSizeSlider:SetPoint("TOPLEFT", buffSizeLabel, "BOTTOMLEFT", 5, -10) 
buffSizeSlider:SetMinMaxValues(12, 64) -- Sensible range
buffSizeSlider:SetValueStep(1)        -- Integer steps
buffSizeSlider:SetObeyStepOnDrag(true)
buffSizeSlider:SetWidth(160)
if buffSizeSlider.KeyLabel then buffSizeSlider.KeyLabel:Show() end
if buffSizeSlider.KeyLabel2 then buffSizeSlider.KeyLabel2:Show() end

-- OnValueChanged updates label dynamically
buffSizeSlider:SetScript("OnValueChanged", function(self, value)
    if self.KeyLabel then 
        self.KeyLabel:SetText(string.format("%dpx", math.floor(value + 0.5))) -- Show integer value
    end
    -- Update thumb position
    local min, max = self:GetMinMaxValues()
    local range = max - min
    if range > 0 and self.VirtualThumb then 
        local thumbPos = (value - min) / range
        self.VirtualThumb:SetPoint("CENTER", self, "LEFT", thumbPos * self:GetWidth(), 0)
    end
end)

-- OnMouseUp saves the value and triggers update
buffSizeSlider:SetScript("OnMouseUp", function(self)
    local value = math.floor(self:GetValue() + 0.5) -- Get integer value
    self:SetValue(value) -- Snap the visual slider
    
    if BoxxyAurasDB and BoxxyAurasDB.buffFrameSettings then
        BoxxyAurasDB.buffFrameSettings.iconSize = value
        -- Trigger icon recreation and layout for BUFFS only
        BoxxyAuras.Options:ApplyIconSizeChange("Buff") 
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)

BoxxyAuras.Options.BuffSizeSlider = buffSizeSlider
-- Update last element for next anchor
lastElement = buffSizeSlider
verticalSpacing = -25 -- Update Y offset

--[[------------------------------------------------------------
-- Option: Debuff Icon Size Slider
--------------------------------------------------------------]]
local debuffSizeLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header") 
debuffSizeLabel:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing) -- Position below debuff align checks
debuffSizeLabel:SetText("Debuff Icon Size")
BoxxyAuras.Options.DebuffSizeLabel = debuffSizeLabel

local debuffSizeSlider = CreateFrame("Slider", "BoxxyAurasOptionsDebuffSizeSlider", contentFrame, "BAURASSlider")
debuffSizeSlider:SetPoint("TOPLEFT", debuffSizeLabel, "BOTTOMLEFT", 5, -10) 
debuffSizeSlider:SetMinMaxValues(12, 64) 
debuffSizeSlider:SetValueStep(1)
debuffSizeSlider:SetObeyStepOnDrag(true)
debuffSizeSlider:SetWidth(160)
if debuffSizeSlider.KeyLabel then debuffSizeSlider.KeyLabel:Show() end
if debuffSizeSlider.KeyLabel2 then debuffSizeSlider.KeyLabel2:Show() end

-- OnValueChanged updates label dynamically
debuffSizeSlider:SetScript("OnValueChanged", function(self, value)
    if self.KeyLabel then 
        self.KeyLabel:SetText(string.format("%dpx", math.floor(value + 0.5)))
    end
    local min, max = self:GetMinMaxValues()
    local range = max - min
    if range > 0 and self.VirtualThumb then 
        local thumbPos = (value - min) / range
        self.VirtualThumb:SetPoint("CENTER", self, "LEFT", thumbPos * self:GetWidth(), 0)
    end
end)

-- OnMouseUp saves the value and triggers update
debuffSizeSlider:SetScript("OnMouseUp", function(self)
    local value = math.floor(self:GetValue() + 0.5)
    self:SetValue(value)
    
    if BoxxyAurasDB and BoxxyAurasDB.debuffFrameSettings then
        BoxxyAurasDB.debuffFrameSettings.iconSize = value
        -- Trigger icon recreation and layout for DEBUFFS only
        BoxxyAuras.Options:ApplyIconSizeChange("Debuff") 
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)

BoxxyAuras.Options.DebuffSizeSlider = debuffSizeSlider
-- Update last element for next anchor
lastElement = debuffSizeSlider
verticalSpacing = -25

--[[------------------------------------------------------------
-- Option: Scale Slider
--------------------------------------------------------------]]
-- Title for the slider
local scaleSliderLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
scaleSliderLabel:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", -5, verticalSpacing) -- Position below debuff size slider
scaleSliderLabel:SetText("Window Scale")
BoxxyAuras.Options.ScaleSliderLabel = scaleSliderLabel

-- Create the slider
local scaleSlider = CreateFrame("Slider", "BoxxyAurasOptionsScaleSlider", contentFrame, "BAURASSlider")
scaleSlider:SetPoint("TOPLEFT", scaleSliderLabel, "BOTTOMLEFT", 5, -10) -- Position below label
scaleSlider:SetMinMaxValues(0.5, 2.0) -- Set scale range
scaleSlider:SetValueStep(0.05)      -- Set step increment
scaleSlider:SetObeyStepOnDrag(true)
scaleSlider:SetWidth(160)
-- Ensure labels are available if defined in template
if scaleSlider.KeyLabel then scaleSlider.KeyLabel:Show() end
if scaleSlider.KeyLabel2 then scaleSlider.KeyLabel2:Show() end

-- OnValueChanged updates label dynamically
scaleSlider:SetScript("OnValueChanged", function(self, value)
    if self.KeyLabel then 
        self.KeyLabel:SetText(string.format("%.2f", value))
    end
    local min, max = self:GetMinMaxValues()
    local range = max - min
    if range > 0 and self.VirtualThumb then 
        local thumbPos = (value - min) / range
        self.VirtualThumb:SetPoint("CENTER", self, "LEFT", thumbPos * self:GetWidth(), 0)
    end
end)

-- OnMouseUp saves the value and applies the scale
scaleSlider:SetScript("OnMouseUp", function(self)
    local value = self:GetValue()
    local step = self:GetValueStep()
    value = math.floor((value / step) + 0.5) * step
    self:SetValue(value) -- Snap the visual slider
    
    if BoxxyAurasDB then
        BoxxyAurasDB.optionsScale = value
        BoxxyAuras.Options:ApplyScale(value)
    end
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end)

BoxxyAuras.Options.ScaleSlider = scaleSlider

-- <<<< INSERT BUTTON START >>>>
-- Update last element for positioning the new button
lastElement = scaleSlider
verticalSpacing = -35 -- Add more space before the button

-- Button to Open Custom Aura Options
local openCustomOptionsButton = CreateFrame("Button", "BoxxyAurasOpenCustomOptionsButton", contentFrame, "BAURASButtonTemplate")
openCustomOptionsButton:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, verticalSpacing)
openCustomOptionsButton:SetWidth(contentFrame:GetWidth() - 20) -- Make it wide
openCustomOptionsButton:SetHeight(25)
openCustomOptionsButton:SetText("Manage Custom Aura List...")
openCustomOptionsButton:SetScript("OnClick", function()
    if BoxxyAuras.CustomOptions and BoxxyAuras.CustomOptions.Toggle then
        BoxxyAuras.CustomOptions:Toggle()
    else
        print("|cffFF0000BoxxyAuras Error:|r Custom Options module not loaded or Toggle function missing.")
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) -- Use standard click sound
end)

BoxxyAuras.Options.OpenCustomOptionsButton = openCustomOptionsButton

-- Update last element in case more options are added later
lastElement = openCustomOptionsButton
verticalSpacing = -15
-- <<<< INSERT BUTTON END >>>>

--[[------------------------------------------------------------
-- Functions to Load/Save/Toggle
--------------------------------------------------------------]]

function BoxxyAuras.Options:Load()
    if not BoxxyAurasDB then 
        print("BoxxyAuras Error: BoxxyAurasDB not found during Options Load.")
        return 
    end 
    -- Ensure nested tables exist for safety before reading
    if not BoxxyAurasDB.buffFrameSettings then BoxxyAurasDB.buffFrameSettings = {} end
    if not BoxxyAurasDB.debuffFrameSettings then BoxxyAurasDB.debuffFrameSettings = {} end

    -- Initialize defaults if necessary (should be handled by PLAYER_LOGIN, but belt-and-suspenders)
    if BoxxyAurasDB.lockFrames == nil then BoxxyAurasDB.lockFrames = false end
    if BoxxyAurasDB.optionsScale == nil then BoxxyAurasDB.optionsScale = 1.0 end
    if BoxxyAurasDB.buffFrameSettings.buffTextAlign == nil then BoxxyAurasDB.buffFrameSettings.buffTextAlign = "CENTER" end
    if BoxxyAurasDB.debuffFrameSettings.debuffTextAlign == nil then BoxxyAurasDB.debuffFrameSettings.debuffTextAlign = "CENTER" end
    if BoxxyAurasDB.buffFrameSettings.iconSize == nil then BoxxyAurasDB.buffFrameSettings.iconSize = 24 end
    if BoxxyAurasDB.debuffFrameSettings.iconSize == nil then BoxxyAurasDB.debuffFrameSettings.iconSize = 24 end
    -- No need to default numIconsWide here, PLAYER_LOGIN handles that

    -- Default hideBlizzardAuras if needed
    if BoxxyAurasDB.hideBlizzardAuras == nil then BoxxyAurasDB.hideBlizzardAuras = true end -- Default to TRUE

    -- Set Lock checkbox state
    if self.LockFramesCheck then
        self.LockFramesCheck:SetChecked(BoxxyAurasDB.lockFrames)
    end
    -- Set Scale slider value
    if self.ScaleSlider then
        self.ScaleSlider:SetValue(BoxxyAurasDB.optionsScale)
        -- Update label based on loaded value (using OnValueChanged logic)
        if self.ScaleSlider.KeyLabel then 
            self.ScaleSlider.KeyLabel:SetText(string.format("%.2f", BoxxyAurasDB.optionsScale))
        end
        -- Update thumb position based on loaded value
        local min, max = self.ScaleSlider:GetMinMaxValues()
        local range = max - min
        if range > 0 and self.ScaleSlider.VirtualThumb then 
            local thumbPos = (BoxxyAurasDB.optionsScale - min) / range
            self.ScaleSlider.VirtualThumb:SetPoint("CENTER", self.ScaleSlider, "LEFT", thumbPos * self.ScaleSlider:GetWidth(), 0)
        end
    end
    
    -- Load BUFF text alignment setting FROM NESTED location
    local buffAlign = BoxxyAurasDB.buffFrameSettings.buffTextAlign
    if self.BuffAlignLeftCheck then self.BuffAlignLeftCheck:SetChecked(buffAlign == "LEFT") end
    if self.BuffAlignCenterCheck then self.BuffAlignCenterCheck:SetChecked(buffAlign == "CENTER") end
    if self.BuffAlignRightCheck then self.BuffAlignRightCheck:SetChecked(buffAlign == "RIGHT") end

    -- Load DEBUFF text alignment setting FROM NESTED location
    local debuffAlign = BoxxyAurasDB.debuffFrameSettings.debuffTextAlign
    if self.DebuffAlignLeftCheck then self.DebuffAlignLeftCheck:SetChecked(debuffAlign == "LEFT") end
    if self.DebuffAlignCenterCheck then self.DebuffAlignCenterCheck:SetChecked(debuffAlign == "CENTER") end
    if self.DebuffAlignRightCheck then self.DebuffAlignRightCheck:SetChecked(debuffAlign == "RIGHT") end

    -- Load Buff Icon Size Slider
    if self.BuffSizeSlider then
        local buffSize = BoxxyAurasDB.buffFrameSettings.iconSize
        self.BuffSizeSlider:SetValue(buffSize)
        -- Update label
        if self.BuffSizeSlider.KeyLabel then 
            self.BuffSizeSlider.KeyLabel:SetText(string.format("%dpx", buffSize))
        end
        -- Update thumb
        local min, max = self.BuffSizeSlider:GetMinMaxValues()
        local range = max - min
        if range > 0 and self.BuffSizeSlider.VirtualThumb then 
            local thumbPos = (buffSize - min) / range
            self.BuffSizeSlider.VirtualThumb:SetPoint("CENTER", self.BuffSizeSlider, "LEFT", thumbPos * self.BuffSizeSlider:GetWidth(), 0)
        end
    end
    
    -- Load Debuff Icon Size Slider
    if self.DebuffSizeSlider then
        local debuffSize = BoxxyAurasDB.debuffFrameSettings.iconSize
        self.DebuffSizeSlider:SetValue(debuffSize)
        -- Update label
        if self.DebuffSizeSlider.KeyLabel then 
            self.DebuffSizeSlider.KeyLabel:SetText(string.format("%dpx", debuffSize))
        end
        -- Update thumb
        local min, max = self.DebuffSizeSlider:GetMinMaxValues()
        local range = max - min
        if range > 0 and self.DebuffSizeSlider.VirtualThumb then 
            local thumbPos = (debuffSize - min) / range
            self.DebuffSizeSlider.VirtualThumb:SetPoint("CENTER", self.DebuffSizeSlider, "LEFT", thumbPos * self.DebuffSizeSlider:GetWidth(), 0)
        end
    end

    -- Load Hide Blizzard Auras checkbox state
    if self.HideBlizzardCheck then
        self.HideBlizzardCheck:SetChecked(BoxxyAurasDB.hideBlizzardAuras)
    end

    -- Apply the loaded states
    self:ApplyLockState(BoxxyAurasDB.lockFrames)
    self:ApplyScale(BoxxyAurasDB.optionsScale)
    self:ApplyTextAlign()
    -- ApplyBlizzardAuraVisibility is now called on PLAYER_LOGIN
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

-- Function to apply the lock state (called elsewhere)
function BoxxyAuras.Options:ApplyLockState(lockState)
    local buffFrame = _G["BoxxyBuffDisplayFrame"]
    local debuffFrame = _G["BoxxyDebuffDisplayFrame"]
    local customFrame = _G["BoxxyCustomDisplayFrame"] -- <<< ADDED Reference

    -- Helper function to apply state to a frame
    local function ApplyToFrame(frame, baseName) -- Accept baseName
        if not frame then return end 
        
        frame:SetMovable(not lockState)
        frame.isLocked = lockState -- Store lock state directly on frame for polling function

        -- Hide/Show resize handles based on lock state
        if frame.handles then
            for name, handle in pairs(frame.handles) do
                handle:EnableMouse(not lockState) -- Prevent mouse interaction on handles when locked
                if lockState then 
                    handle:Hide() 
                else 
                    handle:Show() 
                end
            end
        end

        -- Hide/Show Title Label
        local titleLabelName = baseName .. "TitleLabel" -- Use baseName
        local titleLabel = _G[titleLabelName]
        if titleLabel then
            if lockState then 
                titleLabel:Hide() 
            else 
                titleLabel:Show() 
            end
        end

        -- Set background/border alpha DIRECTLY here as well as relying on polling
        local bgAlpha = lockState and 0 or (BoxxyAuras.Config.MainFrameBGColorNormal and BoxxyAuras.Config.MainFrameBGColorNormal.a) or 0.85
        local borderAlpha = lockState and 0 or (BoxxyAuras.Config.BorderColor and BoxxyAuras.Config.BorderColor.a) or 0.8
        if frame.backdropTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            -- Use existing colors, just change alpha
            local currentBgColor = frame.backdropTextures[5] and {frame.backdropTextures[5]:GetVertexColor()} or {0.1, 0.1, 0.1} -- Get center texture color or default
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", currentBgColor[1], currentBgColor[2], currentBgColor[3], bgAlpha)
        end
         if frame.borderTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            local currentBorderColor = frame.borderTextures[5] and {frame.borderTextures[5]:GetVertexColor()} or {0.4, 0.4, 0.4} -- Get center texture color or default
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", currentBorderColor[1], currentBorderColor[2], currentBorderColor[3], borderAlpha)
        end

        -- Trigger an immediate update via polling (still useful for hover state changes)
        -- Check if the polling function exists before calling
        if BoxxyAuras.PollFrameHoverState then
            -- We need to temporarily set isMouseOver to nil to force a state check
            local currentMouseOver = frame.isMouseOver
            frame.isMouseOver = nil -- Force re-evaluation in PollFrameHoverState
            -- Call the polling function, it will handle both background and border based on frame.isLocked
            BoxxyAuras.PollFrameHoverState(frame, frame:GetName()) 
            frame.isMouseOver = currentMouseOver -- Restore original hover state
        end
    end

    ApplyToFrame(buffFrame, "BuffFrame") -- Pass baseName
    ApplyToFrame(debuffFrame, "DebuffFrame") -- Pass baseName
    ApplyToFrame(customFrame, "CustomFrame") -- <<< ADDED Call for custom frame
end

-- >> ADDED: Function to apply scale <<
function BoxxyAuras.Options:ApplyScale(scaleValue)
    if not scaleValue then return end

    local buffFrame = _G["BoxxyBuffDisplayFrame"]
    local debuffFrame = _G["BoxxyDebuffDisplayFrame"]
    local customFrame = _G["BoxxyCustomDisplayFrame"] -- <<< ADDED Reference to custom display frame
    local optionsFrm = self.Frame -- Use self.Frame for the main options frame
    local customOptionsFrm = BoxxyAuras.CustomOptions and BoxxyAuras.CustomOptions.Frame -- <<< ADDED Reference to custom options frame

    if buffFrame then buffFrame:SetScale(scaleValue) end
    if debuffFrame then debuffFrame:SetScale(scaleValue) end
    if customFrame then customFrame:SetScale(scaleValue) end -- <<< ADDED Scaling for custom display frame
    if optionsFrm then optionsFrm:SetScale(scaleValue) end
    if customOptionsFrm then customOptionsFrm:SetScale(scaleValue) end -- <<< ADDED Scaling for custom options frame
end

-- >> ADDED: Function to apply text alignment <<
function BoxxyAuras.Options:ApplyTextAlign()
    -- Re-layout both frames whenever alignment changes
    if BoxxyAuras.TriggerLayout then 
        BoxxyAuras.TriggerLayout("Buff")
        BoxxyAuras.TriggerLayout("Debuff")
    end
end

-- >> MOVED & RENAMED: Function to show/hide default Blizzard frames <<
function BoxxyAuras.ApplyBlizzardAuraVisibility(shouldHide)
    -- Check if BuffFrame exists before trying to modify it
    if BuffFrame then
        if shouldHide then
            BuffFrame:Hide()
            -- TemporaryEnchantFrame might not exist or be relevant in modern UI
        else
            BuffFrame:Show()
        end
    else
        print("BoxxyAuras Warning: BuffFrame not found when trying to apply visibility setting.")
    end
end

-- Add new function to handle icon size changes
function BoxxyAuras.Options:ApplyIconSizeChange(frameType)
    print(string.format("Applying Icon Size change for %s", frameType))
    
    local iconList = nil
    local settingsKey = nil
    local newSize = 24 -- Default
    local targetFrame = nil

    if frameType == "Buff" then
        iconList = BoxxyAuras.buffIcons
        settingsKey = "buffFrameSettings"
        targetFrame = _G["BoxxyBuffDisplayFrame"]
    elseif frameType == "Debuff" then
        iconList = BoxxyAuras.debuffIcons
        settingsKey = "debuffFrameSettings"
        targetFrame = _G["BoxxyDebuffDisplayFrame"]
    else
        print("ApplyIconSizeChange Error: Invalid frameType")
        return
    end
    
    if not targetFrame then
        print("ApplyIconSizeChange Error: Target frame not found.")
        return
    end

    -- Get the new size and current numIconsWide from DB
    local currentNumIconsWide = 6 -- Default
    if BoxxyAurasDB and BoxxyAurasDB[settingsKey] then
        newSize = BoxxyAurasDB[settingsKey].iconSize or 24
        currentNumIconsWide = BoxxyAurasDB[settingsKey].numIconsWide or 6
    end

    -- *** Recalculate and Set Frame Width ***
    if BoxxyAuras.CalculateFrameWidth then
        local newWidth = BoxxyAuras.CalculateFrameWidth(currentNumIconsWide, newSize)
        print(string.format("ApplyIconSizeChange: Setting %s width to %.1f (NumIcons: %d, IconSize: %d)", 
            frameType, newWidth, currentNumIconsWide, newSize))
        targetFrame:SetWidth(newWidth)
    else
        print("ApplyIconSizeChange Warning: CalculateFrameWidth function not found.")
    end

    -- *** RE-INSERT ICON RESIZE AND LAYOUT TRIGGER ***
    -- Check if icon list and resize method exist
    if iconList and iconList[1] and iconList[1].Resize then
        -- Loop through existing icons and resize them
        for _, auraIcon in ipairs(iconList) do
            if auraIcon.frame then -- Check if icon is valid
                auraIcon:Resize(newSize)
            end
        end
        
        -- After resizing icons, trigger layout for the affected frame
        if BoxxyAuras.TriggerLayout then
            BoxxyAuras.TriggerLayout(frameType)
        else
             print("BoxxyAuras Error: TriggerLayout not found after resizing icons.")
        end
    else
         print(string.format("BoxxyAuras Warning: Could not resize icons for %s. List or Resize method missing?", frameType))
         -- Fallback: Try full Init as before if Resize isn't available? 
         if BoxxyAuras.InitializeAuras then
             print("Fallback: Calling InitializeAuras")
             BoxxyAuras.InitializeAuras()
         else
             print("BoxxyAuras Error: InitializeAuras not found as fallback.")
         end
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
        -- Reset Saved Variables to Defaults
        print("BoxxyAuras: Resetting frame settings to default.")
        
        -- Define defaults (Redefine here for clarity - using TOP anchors)
        local defaultPadding = BoxxyAuras.Config.Padding or 6
        local defaultIconSize = BoxxyAuras.Config.IconSize or 32
        local defaultTextHeight = BoxxyAuras.Config.TextHeight or 8
        local defaultIconH = defaultIconSize + defaultTextHeight + (defaultPadding * 2) 
        local defaultFramePadding = BoxxyAuras.Config.FramePadding or 6
        local defaultMinHeight = defaultFramePadding + defaultIconH + defaultFramePadding 
        local defaultIconsWide_Reset = 6 -- Use a literal default here

        local defaultBuffFrameSettings_Reset = {
            x = 0, y = -150, anchor = "TOP",
            height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, buffTextAlign = "CENTER" 
        }
        local defaultDebuffFrameSettings_Reset = {
            x = 0, y = -150 - defaultMinHeight - 30, anchor = "TOP",
            height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, debuffTextAlign = "CENTER" 
        }
        
        -- Overwrite saved settings with defaults
        BoxxyAurasDB.buffFrameSettings = CopyTable(defaultBuffFrameSettings_Reset)
        BoxxyAurasDB.debuffFrameSettings = CopyTable(defaultDebuffFrameSettings_Reset)
        
        -- Re-apply settings to the frames
        local buffFrame = _G["BoxxyBuffDisplayFrame"]
        local debuffFrame = _G["BoxxyDebuffDisplayFrame"]
        
        -- We need the ApplySettings function. Check if it exists on the main addon table.
        local applyFunc = BoxxyAuras.ApplySettings -- Check if it was attached to the main table
        if not applyFunc then 
            -- Try finding it attached to Options if it wasn't on main (less likely)
            if BoxxyAuras.Options and BoxxyAuras.Options.ApplySettings then 
                applyFunc = BoxxyAuras.Options.ApplySettings
            else
                 print("BoxxyAuras Error: ApplySettings function not found for reset.")
            end
        end

        if applyFunc then 
            if buffFrame then 
                applyFunc(buffFrame, BoxxyAurasDB.buffFrameSettings, "Buff Frame") 
            end
            if debuffFrame then 
                applyFunc(debuffFrame, BoxxyAurasDB.debuffFrameSettings, "Debuff Frame") 
            end
        end

        -- Trigger a layout update
        if BoxxyAuras.InitializeAuras then 
            BoxxyAuras.InitializeAuras() -- Re-running init should relayout both
        elseif BoxxyAuras.UpdateAuras then
             BoxxyAuras.UpdateAuras() -- Fallback to update if init isn't available
        end

        -- PlaySound(SOUNDKIT.UI_SCROLL_DOWN)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) -- Use a known working sound
        
    else -- Default action: Toggle options menu
        BoxxyAuras.Options:Toggle()
    end
end