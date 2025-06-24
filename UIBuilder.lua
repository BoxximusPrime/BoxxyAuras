local addonNameString, privateTable = ...
_G.BoxxyAuras = _G.BoxxyAuras or {}
local BoxxyAuras = _G.BoxxyAuras

BoxxyAuras.UIBuilder = {}

-- Constants for consistent spacing and sizing
local ELEMENT_SPACING = -12 -- Standard spacing between elements
local HEADER_SPACING = -20 -- Spacing after section headers (reduced from -32)
local SLIDER_SPACING = -25 -- Extra spacing before sliders to prevent overlap (reduced from -35)
local GROUP_PADDING = 12 -- Internal padding for group containers (increased for better spacing)
local SLIDER_HEIGHT = 35 -- Height needed for a slider (label + slider + spacing)
local CHECKBOX_ROW_HEIGHT = 35 -- Height needed for a row of checkboxes
local BUTTON_HEIGHT = 35 -- Height needed for a button (increased to account for extra spacing)
local HEADER_HEIGHT = 32 -- Height needed for a section header

-- Helper function to get current element position info
local function GetElementInfo(parent, lastElement, spacing)
    local yOffset = spacing or ELEMENT_SPACING
    local anchor = lastElement or parent
    local anchorPoint = "TOPLEFT"
    local parentPoint = lastElement and "BOTTOMLEFT" or "TOPLEFT"
    
    if not lastElement then
        -- First element in group gets a smaller top padding
        yOffset = -16
    end
    
    return anchor, anchorPoint, parentPoint, yOffset
end

-- Create a section header with consistent styling
function BoxxyAuras.UIBuilder.CreateSectionHeader(parent, text, lastElement)
    local header = parent:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
    local anchor, anchorPoint, parentPoint, yOffset = GetElementInfo(parent, lastElement, HEADER_SPACING)
    
    -- If there's a lastElement, anchor to it with 0 xOffset. Otherwise, anchor to parent with padding.
    local xOffset = lastElement and 0 or (GROUP_PADDING + 5)

    header:SetPoint(anchorPoint, anchor, parentPoint, xOffset, yOffset)
    header:SetText("|cffb9ac9d" .. text .. "|r")
    
    return header, HEADER_HEIGHT
end

-- Create a slider with label and automatic spacing
function BoxxyAuras.UIBuilder.CreateSlider(parent, labelText, minVal, maxVal, step, lastElement, extraSpacing)
    local spacing = extraSpacing and SLIDER_SPACING or ELEMENT_SPACING
    local anchor, anchorPoint, parentPoint, yOffset = GetElementInfo(parent, lastElement, spacing)
    
    -- Create label
    local label = parent:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
    label:SetPoint(anchorPoint, anchor, parentPoint, GROUP_PADDING + 5, yOffset)
    label:SetText(labelText)
    
    -- Create slider
    local slider = CreateFrame("Slider", nil, parent, "BAURASSlider")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -10)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(160)
    
    -- Show value labels if they exist
    if slider.KeyLabel then
        slider.KeyLabel:Show()
    end
    if slider.KeyLabel2 then
        slider.KeyLabel2:Show()
    end
    
    -- Set up value display
    slider:SetScript("OnValueChanged", function(self, value)
        if self.KeyLabel then
            if step < 1 then
                self.KeyLabel:SetText(string.format("%.2f", value))
            else
                self.KeyLabel:SetText(string.format("%dpx", math.floor(value + 0.5)))
            end
        end
        local min, max = self:GetMinMaxValues()
        local range = max - min
        if range > 0 and self.VirtualThumb then
            self.VirtualThumb:SetPoint("CENTER", self, "LEFT", (value - min) / range * self:GetWidth(), 0)
        end
    end)
    
    return slider, label, SLIDER_HEIGHT
end

-- Create a row of mutually exclusive checkboxes (like alignment options)
function BoxxyAuras.UIBuilder.CreateMultipleChoice(parent, options, lastElement, onClickCallback)
    local spacing = ELEMENT_SPACING
    
    if lastElement and lastElement.GetObjectType and lastElement:GetObjectType() == "FontString" then
        spacing = -10
    end
    
    local anchor, anchorPoint, parentPoint, yOffset = GetElementInfo(parent, lastElement, spacing)
    local xOffset = lastElement and 0 or (GROUP_PADDING + 5)
    
    local checkboxes = {}
    local checkboxSpacing = 49
    
    for i, option in ipairs(options) do
        local checkbox = CreateFrame("CheckButton", nil, parent, "BAURASCheckBoxTemplate")
        
        if i == 1 then
            checkbox:SetPoint(anchorPoint, anchor, parentPoint, xOffset, yOffset)
        else
            checkbox:SetPoint("TOPLEFT", checkboxes[i-1], "TOPRIGHT", checkboxSpacing, 0)
        end
        
        checkbox:SetText(option.text)
        checkbox.value = option.value -- Store the value on the checkbox
        checkbox:SetScript("OnClick", function(self)
            for j, cb in ipairs(checkboxes) do
                cb:SetChecked(j == i)
            end
            
            if onClickCallback then
                onClickCallback(option.value)
            end
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        
        checkboxes[i] = checkbox
    end
    
    return checkboxes, CHECKBOX_ROW_HEIGHT
end

-- Create a button with consistent styling
function BoxxyAuras.UIBuilder.CreateButton(parent, text, width, lastElement, onClick, extraSpacing)
    local spacing = extraSpacing and -25 or ELEMENT_SPACING -- Use -25 for extra spacing, similar to sliders
    local anchor, anchorPoint, parentPoint, yOffset = GetElementInfo(parent, lastElement, spacing)
    local xOffset = lastElement and 0 or (GROUP_PADDING + 5)
    
    local button = CreateFrame("Button", nil, parent, "BAURASButtonTemplate")
    button:SetPoint(anchorPoint, anchor, parentPoint, xOffset, yOffset)
    button:SetWidth(width or (parent:GetWidth() - (GROUP_PADDING * 2) - 20)) -- Match slider width calculation
    button:SetHeight(25)
    button:SetText(text)
    
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    
    return button, BUTTON_HEIGHT
end

-- Create a container group with automatic height calculation
function BoxxyAuras.UIBuilder.CreateGroup(parent, lastElement, verticalSpacing)
    local group = CreateFrame("Frame", nil, parent)
    local spacing = verticalSpacing or -15
    
    if lastElement then
        group:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, spacing)
    else
        group:SetPoint("TOPLEFT", parent, "TOPLEFT", GROUP_PADDING, spacing)
    end
    
    local groupWidth = parent:GetWidth() - (GROUP_PADDING * 2)
    group:SetWidth(groupWidth)
    
    -- Apply styling
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
        BoxxyAuras.UIUtils.DrawSlicedBG(group, "OptionsWindowBG", "backdrop", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(group, "backdrop", 0.05, 0.05, 0.05, 0.6)
        BoxxyAuras.UIUtils.DrawSlicedBG(group, "EdgedBorder", "border", 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(group, "border", 0.2, 0.2, 0.2, 0.8)
    end
    
    -- Track elements for automatic height calculation
    group.elements = {}
    group.totalHeight = 0
    
    return group
end

-- Add an element to a group and update height tracking
function BoxxyAuras.UIBuilder.AddElementToGroup(group, element, height)
    table.insert(group.elements, element)
    group.totalHeight = group.totalHeight + height
    group.lastElement = element
    
    -- Update group height with padding
    local finalHeight = group.totalHeight + (GROUP_PADDING * 2)
    group:SetHeight(finalHeight)
    
    return element
end

-- Convenience function to create a complete slider setup
function BoxxyAuras.UIBuilder.CreateSliderGroup(parent, labelText, minVal, maxVal, step, lastElement, extraSpacing, onValueChanged, instantCallback)
    local spacing = extraSpacing and SLIDER_SPACING or ELEMENT_SPACING
    
    if lastElement and lastElement.GetObjectType and lastElement:GetObjectType() == "FontString" then
        spacing = -10
    end
    
    local anchor, anchorPoint, parentPoint, yOffset = GetElementInfo(parent, lastElement, spacing)
    local xOffset = lastElement and 0 or (GROUP_PADDING + 5)

    -- Create label
    local label = parent:CreateFontString(nil, "ARTWORK", "BAURASFont_Header")
    label:SetPoint(anchorPoint, anchor, parentPoint, xOffset, yOffset)
    label:SetText(labelText)
    
    -- Create slider (anchored to its label)
    local slider = CreateFrame("Slider", nil, parent, "BAURASSlider")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -8) -- Indent slider slightly from label
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(parent:GetWidth() - (GROUP_PADDING * 2) - 20) -- Reduced width for right-side padding
    
    -- Timer for delayed callback execution
    local delayTimer = nil
    local DELAY_TIME = 0.3 -- 300ms delay after user stops interacting
    
    -- Visual update function (always immediate)
    local function updateSliderVisuals(sld, value)
        -- Update the label on the thumb
        if sld.KeyLabel then
            local format = (sld:GetValueStep() >= 1) and "%.0fpx" or "%.2f"
            sld.KeyLabel:SetText(string.format(format, value))
        end

        -- Move the virtual thumb texture
        if sld.VirtualThumb then
            local min, max = sld:GetMinMaxValues()
            local range = max - min
            if range > 0 then
                local thumbPos = (value - min) / range
                sld.VirtualThumb:SetPoint("CENTER", sld, "LEFT", thumbPos * sld:GetWidth(), 0)
            end
        end
    end
    
    -- Debounced callback execution helper
    local function executeDebouncedCallback(value)
        if onValueChanged then
            onValueChanged(value)
        end
    end
    
    local callInstant = instantCallback ~= false -- default true if nil

    slider:SetScript("OnValueChanged", function(self, value)
        -- Always update visuals immediately
        updateSliderVisuals(self, value)

        -- If this SetValue call is part of initialization, skip user callback
        if self.suppressCallback then
            return
        end

        if callInstant then
            -- Fire callback right away
            executeDebouncedCallback(value)
        else
            -- Debounce: wait until user stops moving slider
            if delayTimer then
                delayTimer:Cancel()
            end
            delayTimer = C_Timer.NewTimer(DELAY_TIME, function()
                executeDebouncedCallback(value)
                delayTimer = nil
            end)
        end
    end)
    
    -- Set initial value to minimum value to prevent 0 scale errors
    local initialValue = math.max(minVal, slider:GetValue())
    slider.suppressCallback = true
    slider:SetValue(initialValue)
    slider.suppressCallback = nil
    
    -- Set initial visuals
    updateSliderVisuals(slider, initialValue)

    -- Store references
    slider.label = label
    
    return slider, label, SLIDER_HEIGHT
end

-- Convenience function to create a complete multiple choice setup
function BoxxyAuras.UIBuilder.CreateMultipleChoiceGroup(parent, headerText, options, lastElement, onValueChanged)
    local header, headerHeight = BoxxyAuras.UIBuilder.CreateSectionHeader(parent, headerText, lastElement)
    local checkboxes, checkboxHeight = BoxxyAuras.UIBuilder.CreateMultipleChoice(parent, options, header, onValueChanged)
    
    return checkboxes, header, headerHeight + checkboxHeight
end

-- Helper to set multiple choice value
function BoxxyAuras.UIBuilder.SetMultipleChoiceValue(checkboxes, value)
    for _, checkbox in ipairs(checkboxes) do
        checkbox:SetChecked(checkbox.value == value)
    end
end

-- Helper to get multiple choice value
function BoxxyAuras.UIBuilder.GetMultipleChoiceValue(checkboxes)
    for _, checkbox in ipairs(checkboxes) do
        if checkbox:GetChecked() then
            return checkbox.value
        end
    end
    return nil
end 