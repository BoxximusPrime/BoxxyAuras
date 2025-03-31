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

local currentY = -10 -- Starting Y offset for options

--[[------------------------------------------------------------
-- Option: Lock Frames Checkbox
--------------------------------------------------------------]]
local lockFramesCheck = CreateFrame("CheckButton", "BoxxyAurasLockFramesCheckButton", contentFrame, "BAURASCheckBoxTemplate") 
lockFramesCheck:SetPoint("TOPLEFT", 10, currentY)
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
    
    print("Lock Frames Clicked. New state saved:", newState) -- Debug print
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)

BoxxyAuras.Options.LockFramesCheck = lockFramesCheck
currentY = currentY - lockFramesCheck:GetHeight() - 15 -- Update Y offset for next option

--[[------------------------------------------------------------
-- Option: Scale Slider
--------------------------------------------------------------]]
-- Title for the slider
local scaleSliderLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header") -- Using standard font for now
scaleSliderLabel:SetPoint("TOPLEFT", lockFramesCheck, "BOTTOMLEFT", 0, -15) -- Position below lock check
scaleSliderLabel:SetText("Window Scale")
BoxxyAuras.Options.ScaleSliderLabel = scaleSliderLabel
currentY = currentY - scaleSliderLabel:GetHeight() - 5 -- Adjust Y

-- Create the slider
local scaleSlider = CreateFrame("Slider", "BoxxyAurasOptionsScaleSlider", contentFrame, "BAURASSlider")
scaleSlider:SetPoint("TOPLEFT", scaleSliderLabel, "BOTTOMLEFT", 5, -10) -- Position below label
scaleSlider:SetMinMaxValues(0.5, 2.0) -- Set scale range
scaleSlider:SetValueStep(0.05)      -- Set step increment
scaleSlider:SetObeyStepOnDrag(true)
scaleSlider:SetWidth(160) -- Match WhoGotLoots slider width
-- Ensure labels are available if defined in template
if scaleSlider.KeyLabel then scaleSlider.KeyLabel:Show() end
if scaleSlider.KeyLabel2 then scaleSlider.KeyLabel2:Show() end

-- OnValueChanged updates label dynamically (optional, OnMouseUp handles saving)
scaleSlider:SetScript("OnValueChanged", function(self, value)
    -- Update the main label (if it exists on the template)
    if self.KeyLabel then 
        self.KeyLabel:SetText(string.format("%.2f", value))
    end
    -- You might need to manually update thumb position if template doesn't
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
    -- Round to nearest step
    local step = self:GetValueStep()
    value = math.floor((value / step) + 0.5) * step
    self:SetValue(value) -- Snap the visual slider
    
    if BoxxyAurasDB then
        BoxxyAurasDB.optionsScale = value
        BoxxyAuras.Options:ApplyScale(value)
    end
    print("Scale Slider Value Changed:", value) -- Debug print
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) -- Sound feedback
end)

BoxxyAuras.Options.ScaleSlider = scaleSlider
currentY = currentY - scaleSlider:GetHeight() - 25 -- Update Y offset significantly for next option

--[[------------------------------------------------------------
-- Option: Buff Text Alignment
--------------------------------------------------------------]]
-- Title for the alignment options
local buffAlignLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header") 
buffAlignLabel:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -5, -30) -- Position below scale slider
buffAlignLabel:SetText("Buff Text Alignment")
BoxxyAuras.Options.BuffAlignLabel = buffAlignLabel
currentY = currentY - buffAlignLabel:GetHeight() - 10 -- Adjust Y

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

    -- 1. Force the clicked button to be checked
    clickedButton:SetChecked(true)

    -- 2. Uncheck the others in this group
    if clickedButton ~= buffAlignLeftCheck then buffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= buffAlignCenterCheck then buffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= buffAlignRightCheck then buffAlignRightCheck:SetChecked(false) end
    
    -- 3. Save the new value
    BoxxyAurasDB.buffTextAlign = alignmentValue -- Save to specific buff key
    print("Buff Alignment set to:", alignmentValue) -- Debug
    
    -- TODO: Apply alignment change immediately
    -- BoxxyAuras.Options:ApplyTextAlign(alignmentValue, "Buff")
    
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Assign OnClick scripts for BUFFS
buffAlignLeftCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "LEFT") end)
buffAlignCenterCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "CENTER") end)
buffAlignRightCheck:SetScript("OnClick", function(self) HandleBuffAlignmentClick(self, "RIGHT") end)

-- Update Y offset before Debuff section
currentY = currentY - buffAlignLeftCheck:GetHeight() - 20 -- Add more vertical space

--[[------------------------------------------------------------
-- Option: Debuff Text Alignment
--------------------------------------------------------------]]
-- Title for the alignment options
local debuffAlignLabel = contentFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header") 
debuffAlignLabel:SetPoint("TOPLEFT", buffAlignLeftCheck, "BOTTOMLEFT", 0, -15) -- Position below first row of checks
debuffAlignLabel:SetText("Debuff Text Alignment")
BoxxyAuras.Options.DebuffAlignLabel = debuffAlignLabel
currentY = currentY - debuffAlignLabel:GetHeight() - 10 -- Adjust Y

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

    -- 1. Force the clicked button to be checked
    clickedButton:SetChecked(true)

    -- 2. Uncheck the others in this group
    if clickedButton ~= debuffAlignLeftCheck then debuffAlignLeftCheck:SetChecked(false) end
    if clickedButton ~= debuffAlignCenterCheck then debuffAlignCenterCheck:SetChecked(false) end
    if clickedButton ~= debuffAlignRightCheck then debuffAlignRightCheck:SetChecked(false) end

    -- 3. Save the new value
    BoxxyAurasDB.debuffTextAlign = alignmentValue -- Save to specific debuff key
    print("Debuff Alignment set to:", alignmentValue) -- Debug

    -- TODO: Apply alignment change immediately
    -- BoxxyAuras.Options:ApplyTextAlign(alignmentValue, "Debuff")

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Assign OnClick scripts for DEBUFFS
debuffAlignLeftCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "LEFT") end)
debuffAlignCenterCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "CENTER") end)
debuffAlignRightCheck:SetScript("OnClick", function(self) HandleDebuffAlignmentClick(self, "RIGHT") end)

-- Update Y offset for next section
currentY = currentY - debuffAlignLeftCheck:GetHeight() - 15

-- Add more options here using currentY offset...

--[[------------------------------------------------------------
-- Functions to Load/Save/Toggle
--------------------------------------------------------------]]

function BoxxyAuras.Options:Load()
    if not BoxxyAurasDB then 
        print("BoxxyAuras Error: BoxxyAurasDB not found during Options Load.")
        return 
    end 

    -- Initialize default if necessary
    if BoxxyAurasDB.lockFrames == nil then
        BoxxyAurasDB.lockFrames = false
    end
    -- >> ADDED: Initialize scale default <<
    if BoxxyAurasDB.optionsScale == nil then
        BoxxyAurasDB.optionsScale = 1.0
    end

    -- Set checkbox state
    if self.LockFramesCheck then
        self.LockFramesCheck:SetChecked(BoxxyAurasDB.lockFrames)
    end
    -- >> ADDED: Set slider value and apply scale <<
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
    
    -- >> UPDATED: Load BUFF text alignment setting <<
    if BoxxyAurasDB.buffTextAlign == nil then
        BoxxyAurasDB.buffTextAlign = "CENTER" -- Default to Center
    end
    if self.BuffAlignLeftCheck then self.BuffAlignLeftCheck:SetChecked(BoxxyAurasDB.buffTextAlign == "LEFT") end
    if self.BuffAlignCenterCheck then self.BuffAlignCenterCheck:SetChecked(BoxxyAurasDB.buffTextAlign == "CENTER") end
    if self.BuffAlignRightCheck then self.BuffAlignRightCheck:SetChecked(BoxxyAurasDB.buffTextAlign == "RIGHT") end
    -- TODO: Call apply function here too when implemented
    -- self:ApplyTextAlign(BoxxyAurasDB.buffTextAlign, "Buff")

    -- >> ADDED: Load DEBUFF text alignment setting <<
    if BoxxyAurasDB.debuffTextAlign == nil then
        BoxxyAurasDB.debuffTextAlign = "CENTER" -- Default to Center
    end
    if self.DebuffAlignLeftCheck then self.DebuffAlignLeftCheck:SetChecked(BoxxyAurasDB.debuffTextAlign == "LEFT") end
    if self.DebuffAlignCenterCheck then self.DebuffAlignCenterCheck:SetChecked(BoxxyAurasDB.debuffTextAlign == "CENTER") end
    if self.DebuffAlignRightCheck then self.DebuffAlignRightCheck:SetChecked(BoxxyAurasDB.debuffTextAlign == "RIGHT") end
    -- TODO: Call apply function here too when implemented
    -- self:ApplyTextAlign(BoxxyAurasDB.debuffTextAlign, "Debuff")

    -- Apply the loaded states
    self:ApplyLockState(BoxxyAurasDB.lockFrames)
    self:ApplyScale(BoxxyAurasDB.optionsScale)
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

    -- Helper function to apply state to a frame
    local function ApplyToFrame(frame, baseName) -- Accept baseName
        if not frame then return end 
        
        frame:SetMovable(not lockState)
        frame.isLocked = lockState -- Store lock state directly on frame for polling function

        -- Hide/Show resize handles based on lock state
        if frame.handles then
            print(string.format("ApplyLockState Debug (%s): Found handles table.", baseName)) -- DEBUG
            for name, handle in pairs(frame.handles) do
                handle:EnableMouse(not lockState) -- Prevent mouse interaction on handles when locked
                if lockState then 
                    handle:Hide() 
                    print(string.format("ApplyLockState Debug (%s): Hiding handle %s.", baseName, name)) -- DEBUG
                else 
                    handle:Show() 
                    print(string.format("ApplyLockState Debug (%s): Showing handle %s.", baseName, name)) -- DEBUG
                end
            end
        else
            print(string.format("ApplyLockState Debug (%s): Handles table NOT found.", baseName)) -- DEBUG
        end

        -- Hide/Show Title Label
        local titleLabelName = baseName .. "TitleLabel" -- Use baseName
        local titleLabel = _G[titleLabelName]
        if titleLabel then
            print(string.format("ApplyLockState Debug (%s): Found title label %s.", baseName, titleLabelName)) -- DEBUG
            if lockState then 
                titleLabel:Hide() 
                print(string.format("ApplyLockState Debug (%s): Hiding title label.", baseName)) -- DEBUG
            else 
                titleLabel:Show() 
                print(string.format("ApplyLockState Debug (%s): Showing title label.", baseName)) -- DEBUG
            end
        else
            print(string.format("ApplyLockState Debug (%s): Title label %s NOT found.", baseName, titleLabelName)) -- DEBUG
        end

        -- Set background/border alpha DIRECTLY here as well as relying on polling
        local bgAlpha = lockState and 0 or (BoxxyAuras.Config.MainFrameBGColorNormal and BoxxyAuras.Config.MainFrameBGColorNormal.a) or 0.85
        local borderAlpha = lockState and 0 or (BoxxyAuras.Config.BorderColor and BoxxyAuras.Config.BorderColor.a) or 0.8
        if frame.backdropTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            -- Use existing colors, just change alpha
            local currentBgColor = frame.backdropTextures[5] and {frame.backdropTextures[5]:GetVertexColor()} or {0.1, 0.1, 0.1} -- Get center texture color or default
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", currentBgColor[1], currentBgColor[2], currentBgColor[3], bgAlpha)
            print(string.format("ApplyLockState Debug (%s): Directly setting backdrop alpha to %.2f.", baseName, bgAlpha)) -- DEBUG
        end
         if frame.borderTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            local currentBorderColor = frame.borderTextures[5] and {frame.borderTextures[5]:GetVertexColor()} or {0.4, 0.4, 0.4} -- Get center texture color or default
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", currentBorderColor[1], currentBorderColor[2], currentBorderColor[3], borderAlpha)
            print(string.format("ApplyLockState Debug (%s): Directly setting border alpha to %.2f.", baseName, borderAlpha)) -- DEBUG
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
    
    -- print("BoxxyAuras: Lock state applied - ", tostring(lockState)) -- Optional debug
end

-- >> ADDED: Function to apply scale <<
function BoxxyAuras.Options:ApplyScale(scaleValue)
    if not scaleValue then return end

    local buffFrame = _G["BoxxyBuffDisplayFrame"]
    local debuffFrame = _G["BoxxyDebuffDisplayFrame"]
    local optionsFrm = self.Frame -- Use self.Frame for the options frame

    if buffFrame then buffFrame:SetScale(scaleValue) end
    if debuffFrame then debuffFrame:SetScale(scaleValue) end
    if optionsFrm then optionsFrm:SetScale(scaleValue) end
    
    -- We might need to re-layout auras after scaling, especially if size changes? (Consider later if needed)
    -- if BoxxyAuras.LayoutAuras then
    --    if buffFrame and BoxxyAuras.buffIcons then BoxxyAuras.LayoutAuras(buffFrame, BoxxyAuras.buffIcons) end
    --    if debuffFrame and BoxxyAuras.debuffIcons then BoxxyAuras.LayoutAuras(debuffFrame, BoxxyAuras.debuffIcons) end
    -- end
end

--[[------------------------------------------------------------
-- Slash Command
--------------------------------------------------------------]]
SLASH_BOXXYAURASOPTIONS1 = "/boxxyauras"
SLASH_BOXXYAURASOPTIONS2 = "/ba"
SlashCmdList["BOXXYAURASOPTIONS"] = function(msg)
    BoxxyAuras.Options:Toggle()
end

print("BoxxyAuras Options Menu Loaded")
