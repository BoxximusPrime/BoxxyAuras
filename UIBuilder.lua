local addonNameString, privateTable = ...
_G.BoxxyAuras = _G.BoxxyAuras or {}
local BoxxyAuras = _G.BoxxyAuras

BoxxyAuras.UIBuilder = {}

-- Constants for consistent spacing and sizing
local ELEMENT_SPACING = 0 -- Standard spacing between elements
local HEADER_SPACING = 0 -- Spacing after section headers
local GROUP_PADDING = 12 -- Internal padding for group containers
local ELEMENT_PADDING = 0 -- Padding for individual elements within groups
local SLIDER_HEIGHT = 60 -- Height needed for a slider (label + slider + spacing)
local SLIDER_HORIZONTAL_PADDING = 15 -- Extra horizontal padding for sliders to prevent thumb overflow
local CHECKBOX_ROW_HEIGHT = 15 -- Height needed for a row of checkboxes
local BUTTON_HEIGHT = 35 -- Height needed for a button
local HEADER_HEIGHT = 22 -- Height needed for a section header
local EDITBOX_HEIGHT = 25 -- Height needed for an edit box

-- Container Class
local Container = {}
Container.__index = Container

function Container:new(parent, title)
    local container = {}
    setmetatable(container, Container)
    
    -- Create the frame
    container.frame = CreateFrame("Frame", nil, parent)
    container.elements = {}
    container.currentY = -GROUP_PADDING -- Start with top padding
    container.parent = parent
    container.title = title
    
    -- Set initial size
    local width = parent:GetWidth() - (GROUP_PADDING * 2)
    container.frame:SetWidth(width)
    container.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", GROUP_PADDING, 0)
    
    -- Apply styling
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
        BoxxyAuras.UIUtils.DrawSlicedBG(container.frame, "OptionsWindowBG", "backdrop", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(container.frame, "backdrop", 0.05, 0.05, 0.05, 0.6)
        BoxxyAuras.UIUtils.DrawSlicedBG(container.frame, "EdgedBorder", "border", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(container.frame, "border", 0.2, 0.2, 0.2, 0.8)
    end
    
    -- Add title if provided
    if title then
        container:AddHeader(title)
    end
    
    return container
end

function Container:AddElement(element, height)
    table.insert(self.elements, element)
    
    -- Position the element
    element:SetPoint("TOPLEFT", self.frame, "TOPLEFT", GROUP_PADDING, self.currentY)
    
    -- Update current Y position for next element
    self.currentY = self.currentY - height - ELEMENT_SPACING
    
    -- Update container height
    local totalHeight = math.abs(self.currentY) + GROUP_PADDING
    self.frame:SetHeight(totalHeight)
    
    return element
end

function Container:AddHeader(text)
    local header = self.frame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
    header:SetText("|cffb9ac9d" .. text .. "|r")
    return self:AddElement(header, HEADER_HEIGHT)
end

function Container:AddSlider(labelText, minVal, maxVal, step, onValueChanged, instantCallback)
    -- Create label
    local label = self.frame:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
    label:SetText(labelText)
    self:AddElement(label, 0) -- No extra spacing for label, slider will add the height
    
    -- Create slider
    local slider = CreateFrame("Slider", nil, self.frame, "BAURASSlider")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(self.frame:GetWidth() - (GROUP_PADDING * 2) - (SLIDER_HORIZONTAL_PADDING * 2))
    
    -- Position slider below its label with horizontal padding
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", SLIDER_HORIZONTAL_PADDING, -8)
    
    -- Set up value display and callbacks
    local delayTimer = nil
    local DELAY_TIME = 0.3
    
    local function updateSliderVisuals(sld, value)
        if sld.KeyLabel then
            local format = (sld:GetValueStep() >= 1) and "%.0fpx" or "%.2f"
            sld.KeyLabel:SetText(string.format(format, value))
        end
        if sld.VirtualThumb then
            local min, max = sld:GetMinMaxValues()
            local range = max - min
            if range > 0 then
                local thumbPos = (value - min) / range
                sld.VirtualThumb:SetPoint("CENTER", sld, "LEFT", thumbPos * sld:GetWidth(), 0)
            end
        end
    end
    
    local callInstant = instantCallback ~= false
    
    slider:SetScript("OnValueChanged", function(self, value)
        updateSliderVisuals(self, value)
        if self.suppressCallback then return end
        
        if callInstant then
            if onValueChanged then onValueChanged(value) end
        else
            if delayTimer then delayTimer:Cancel() end
            delayTimer = C_Timer.NewTimer(DELAY_TIME, function()
                if onValueChanged then onValueChanged(value) end
                delayTimer = nil
            end)
        end
    end)
    
    -- Set initial value
    local initialValue = math.max(minVal, slider:GetValue())
    slider.suppressCallback = true
    slider:SetValue(initialValue)
    slider.suppressCallback = nil
    updateSliderVisuals(slider, initialValue)
    
    -- Update container position (slider takes up the space)
    self.currentY = self.currentY - SLIDER_HEIGHT - ELEMENT_SPACING
    local totalHeight = math.abs(self.currentY) + GROUP_PADDING
    self.frame:SetHeight(totalHeight)
    
    slider.label = label
    return slider
end

function Container:CalculateCheckboxWidth(text)
    -- Calculate the width needed for a checkbox with the given text
    -- Based on the BAURASCheckBoxTemplate structure: 12px checkbox + 4px padding + label width
    local checkboxWidth = 12 -- Size of the checkbox icon from XML
    local padding = 4 -- Padding between checkbox and label from XML
    
    -- Create a temporary font string to measure text width
    local tempFont = self.frame:CreateFontString(nil, "ARTWORK", "BAURASFont_Checkbox")
    tempFont:SetText(text)
    local labelWidth = tempFont:GetStringWidth()
    tempFont:Hide() -- Hide but don't destroy immediately to avoid issues
    
    -- Clean up the temporary font string after a brief delay
    C_Timer.After(0.1, function()
        if tempFont then
            tempFont:Hide()
            tempFont:SetParent(nil)
        end
    end)
    
    return checkboxWidth + padding + labelWidth
end

function Container:AddCheckboxRow(options, onValueChanged)
    local checkboxes = {}
    
    -- First pass: create all checkboxes and calculate their widths
    local checkboxWidths = {}
    local totalCheckboxWidth = 0
    
    for i, option in ipairs(options) do
        local checkbox = CreateFrame("CheckButton", nil, self.frame, "BAURASCheckBoxTemplate")
        checkbox:SetText(option.text)
        checkbox.value = option.value
        
        -- Calculate this checkbox's width
        local width = self:CalculateCheckboxWidth(option.text)
        checkboxWidths[i] = width
        totalCheckboxWidth = totalCheckboxWidth + width
        
        checkbox:SetScript("OnClick", function(self)
            for j, cb in ipairs(checkboxes) do
                cb:SetChecked(j == i)
            end
            if onValueChanged then
                onValueChanged(option.value)
            end
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        
        checkboxes[i] = checkbox
    end
    
    -- Use fixed spacing between checkboxes
    local fixedSpacing = 10 -- Fixed 20px spacing between checkboxes
    
    -- Second pass: position the checkboxes with fixed spacing
    local currentX = GROUP_PADDING
    
    for i, checkbox in ipairs(checkboxes) do
        checkbox:SetPoint("TOPLEFT", self.frame, "TOPLEFT", currentX, self.currentY)
        
        -- Update position for next checkbox (current position + this checkbox's width + fixed spacing)
        currentX = currentX + checkboxWidths[i] + fixedSpacing
    end
    
    -- Update container position
    self.currentY = self.currentY - CHECKBOX_ROW_HEIGHT - ELEMENT_SPACING
    local totalHeight = math.abs(self.currentY) + GROUP_PADDING
    self.frame:SetHeight(totalHeight)
    
    return checkboxes
end

function Container:AddButton(text, width, onClick)
    local button = CreateFrame("Button", nil, self.frame, "BAURASButtonTemplate")
    button:SetText(text)
    button:SetWidth(width or (self.frame:GetWidth() - (GROUP_PADDING * 2)))
    button:SetHeight(25)
    
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    
    return self:AddElement(button, BUTTON_HEIGHT)
end

function Container:AddEditBox(placeholder, maxLetters, onEnterPressed, onEscapePressed, customWidth, customXOffset)
    local editBox = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    
    -- Use custom width and positioning if provided, otherwise use full width
    if customWidth and customXOffset then
        editBox:SetWidth(customWidth)
        editBox:SetPoint("TOPLEFT", self.frame, "TOPLEFT", GROUP_PADDING + customXOffset, self.currentY)
    else
        editBox:SetWidth(self.frame:GetWidth() - (GROUP_PADDING * 2))
        editBox:SetPoint("TOPLEFT", self.frame, "TOPLEFT", GROUP_PADDING, self.currentY)
    end
    
    editBox:SetHeight(20)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(maxLetters or 32)
    editBox:SetTextInsets(5, 5, 0, 0)
    
    if placeholder then
        editBox:SetText(placeholder)
    end
    
    editBox:SetScript("OnEscapePressed", onEscapePressed or function(self)
        self:ClearFocus()
    end)
    
    editBox:SetScript("OnEnterPressed", onEnterPressed or function(self)
        local text = self:GetText()
        if text and text ~= "" then
            self:SetText("")
            self:ClearFocus()
        end
    end)
    
    -- Update container position manually since we're not using AddElement
    self.currentY = self.currentY - EDITBOX_HEIGHT - ELEMENT_SPACING
    local totalHeight = math.abs(self.currentY) + GROUP_PADDING
    self.frame:SetHeight(totalHeight)
    
    return editBox
end

function Container:AddCheckbox(text, onClick)
    local checkbox = CreateFrame("CheckButton", nil, self.frame, "BAURASCheckBoxTemplate")
    checkbox:SetText(text)
    
    if onClick then
        checkbox:SetScript("OnClick", onClick)
    end
    
    return self:AddElement(checkbox, 20)
end

function Container:AddSpacer(height)
    -- Create an invisible frame that just takes up space
    local spacer = CreateFrame("Frame", nil, self.frame)
    spacer:SetWidth(1) -- Minimal width since it's invisible
    spacer:SetHeight(height or 10) -- Default 10px height
    
    -- Update container position without using AddElement since we don't need positioning
    self.currentY = self.currentY - (height or 10) - ELEMENT_SPACING
    local totalHeight = math.abs(self.currentY) + GROUP_PADDING
    self.frame:SetHeight(totalHeight)
    
    return spacer
end

function Container:CalculateButtonRowDimensions(buttons)
    -- Calculate the dimensions for a button row without creating it
    local buttonSpacing = 5 -- Space between buttons
    local totalButtonWidth = 0
    
    -- Calculate total width needed for all buttons
    for _, buttonInfo in ipairs(buttons) do
        totalButtonWidth = totalButtonWidth + (buttonInfo.width or 60)
    end
    totalButtonWidth = totalButtonWidth + (buttonSpacing * (#buttons - 1))
    
    -- Calculate starting position to center the button row
    local containerWidth = self.frame:GetWidth() - (GROUP_PADDING * 2)
    local startX = (containerWidth - totalButtonWidth) / 2
    
    return {
        startX = startX,
        totalWidth = totalButtonWidth,
        buttonSpacing = buttonSpacing
    }
end

function Container:AddButtonRow(buttons)
    -- Create a row of buttons with equal spacing
    local buttonFrames = {}
    local dimensions = self:CalculateButtonRowDimensions(buttons)
    
    for i, buttonInfo in ipairs(buttons) do
        local button = CreateFrame("Button", buttonInfo.name, self.frame, "BAURASButtonTemplate")
        button:SetWidth(buttonInfo.width or 60)
        button:SetHeight(25)
        button:SetText(buttonInfo.text)
        
        if i == 1 then
            -- Position first button
            button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", GROUP_PADDING + dimensions.startX, self.currentY)
        else
            -- Position subsequent buttons to the right
            button:SetPoint("LEFT", buttonFrames[i-1], "RIGHT", dimensions.buttonSpacing, 0)
        end
        
        if buttonInfo.onClick then
            button:SetScript("OnClick", buttonInfo.onClick)
        end
        
        buttonFrames[i] = button
    end
    
    -- Update container position
    self.currentY = self.currentY - BUTTON_HEIGHT - ELEMENT_SPACING
    local totalHeight = math.abs(self.currentY) + GROUP_PADDING
    self.frame:SetHeight(totalHeight)
    
    return buttonFrames
end

function Container:GetFrame()
    return self.frame
end

function Container:SetPosition(point, relativeTo, relativePoint, xOffset, yOffset)
    self.frame:SetPoint(point, relativeTo, relativePoint, xOffset or 0, yOffset or 0)
end

-- Public API Functions
function BoxxyAuras.UIBuilder.CreateContainer(parent, title)
    return Container:new(parent, title)
end

-- Helper functions for setting checkbox values
function BoxxyAuras.UIBuilder.SetCheckboxRowValue(checkboxes, value)
    for _, checkbox in ipairs(checkboxes) do
        checkbox:SetChecked(checkbox.value == value)
    end
end

function BoxxyAuras.UIBuilder.GetCheckboxRowValue(checkboxes)
    for _, checkbox in ipairs(checkboxes) do
        if checkbox:GetChecked() then
            return checkbox.value
        end
    end
    return nil
end

