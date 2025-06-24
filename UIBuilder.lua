local addonNameString, privateTable = ...
_G.BoxxyAuras = _G.BoxxyAuras or {}
local BoxxyAuras = _G.BoxxyAuras

BoxxyAuras.UIBuilder = {}

-- Constants for consistent spacing and sizing
local ELEMENT_SPACING = 12 -- Standard spacing between elements
local HEADER_SPACING = 20 -- Spacing after section headers
local GROUP_PADDING = 12 -- Internal padding for group containers
local ELEMENT_PADDING = 10 -- Padding for individual elements within groups
local SLIDER_HEIGHT = 35 -- Height needed for a slider (label + slider + spacing)
local CHECKBOX_ROW_HEIGHT = 35 -- Height needed for a row of checkboxes
local BUTTON_HEIGHT = 35 -- Height needed for a button
local HEADER_HEIGHT = 32 -- Height needed for a section header
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
    slider:SetWidth(self.frame:GetWidth() - (GROUP_PADDING * 2))
    
    -- Position slider below its label
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    
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

function Container:AddCheckboxRow(options, onValueChanged)
    local checkboxes = {}
    local checkboxSpacing = 49
    
    for i, option in ipairs(options) do
        local checkbox = CreateFrame("CheckButton", nil, self.frame, "BAURASCheckBoxTemplate")
        checkbox:SetText(option.text)
        checkbox.value = option.value
        
        if i == 1 then
            -- Position first checkbox normally
            checkbox:SetPoint("TOPLEFT", self.frame, "TOPLEFT", GROUP_PADDING, self.currentY)
        else
            -- Position subsequent checkboxes to the right
            checkbox:SetPoint("TOPLEFT", checkboxes[i-1], "TOPRIGHT", checkboxSpacing, 0)
        end
        
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

function Container:AddEditBox(placeholder, maxLetters, onEnterPressed, onEscapePressed)
    local editBox = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    editBox:SetWidth(self.frame:GetWidth() - (GROUP_PADDING * 2))
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
    
    return self:AddElement(editBox, EDITBOX_HEIGHT)
end

function Container:AddCheckbox(text, onClick)
    local checkbox = CreateFrame("CheckButton", nil, self.frame, "BAURASCheckBoxTemplate")
    checkbox:SetText(text)
    
    if onClick then
        checkbox:SetScript("OnClick", onClick)
    end
    
    return self:AddElement(checkbox, 20)
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

