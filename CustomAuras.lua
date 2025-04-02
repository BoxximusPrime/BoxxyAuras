local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras = BoxxyAuras or {}
BoxxyAuras.CustomOptions = {} -- Table to hold custom options elements

-- <<< NEW: Local reference to the profile settings helper >>>
local function GetCurrentProfileSettings()
    -- Ensure the main addon table and function exist
    if BoxxyAuras and BoxxyAuras.GetCurrentProfileSettings then
        return BoxxyAuras:GetCurrentProfileSettings()
    else
        -- Fallback or error if the main function isn't loaded yet or missing
        -- print("|cffFF0000BoxxyAuras CustomOptions Error:|r Cannot get profile settings helper function!")
        return { customAuraNames = {} } -- Return a safe default structure
    end
end

--[[------------------------------------------------------------
-- Create Custom Aura Options Frame
--------------------------------------------------------------]]
local customOptionsFrame = CreateFrame("Frame", "BoxxyAurasCustomOptionsFrame", UIParent, "BackdropTemplate")
customOptionsFrame:SetSize(300, 250) -- Slightly wider for text area
customOptionsFrame:SetPoint("CENTER", UIParent, "CENTER", 50, 50) -- Offset slightly from main options
customOptionsFrame:SetFrameStrata("HIGH") -- Appear above main options if both open
customOptionsFrame:SetMovable(true)
customOptionsFrame:EnableMouse(true)
customOptionsFrame:RegisterForDrag("LeftButton")
customOptionsFrame:SetScript("OnDragStart", customOptionsFrame.StartMoving)
customOptionsFrame:SetScript("OnDragStop", customOptionsFrame.StopMovingOrSizing)
customOptionsFrame:Hide() -- Start hidden

BoxxyAuras.CustomOptions.Frame = customOptionsFrame

-- Apply similar background and border styling
-- Background
local bg = CreateFrame("Frame", nil, customOptionsFrame);
bg:SetAllPoints();
bg:SetFrameLevel(customOptionsFrame:GetFrameLevel());
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(bg, "OptionsWindowBG", "backdrop", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(bg, "backdrop", 1, 1, 1, 0.95)
else
    -- print("|cffFF0000BoxxyAuras Custom Options Error:|r Could not draw background.")
end

-- Border
local border = CreateFrame("Frame", nil, customOptionsFrame);
border:SetAllPoints();
border:SetFrameLevel(customOptionsFrame:GetFrameLevel() + 1);
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(border, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(border, "border", 0.4, 0.4, 0.4, 1)
else
    -- print("|cffFF0000BoxxyAuras Custom Options Error:|r Could not draw border.")
end

-- Title
local title = customOptionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Title")
title:SetPoint("TOPLEFT", customOptionsFrame, "TOPLEFT", 20, -23)
title:SetText("Custom Aura List")

-- Instruction Label
local instructionLabel = customOptionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
instructionLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -15) -- Below title
instructionLabel:SetPoint("RIGHT", customOptionsFrame, "RIGHT", -10, 0)
instructionLabel:SetText("Enter exact spell names, separated by commas. Case-sensitive.")
instructionLabel:SetJustifyH("LEFT")
instructionLabel:SetWordWrap(true)

-- Close Button
local closeBtn = CreateFrame("Button", "BoxxyAurasCustomOptionsCloseButton", customOptionsFrame, "BAURASCloseBtn")
closeBtn:SetPoint("TOPRIGHT", customOptionsFrame, "TOPRIGHT", -12, -12)
closeBtn:SetSize(12, 12)
closeBtn:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    customOptionsFrame:Hide()
end)

--[[------------------------------------------------------------
-- Content: Scroll Frame, Edit Box, Save Button
--------------------------------------------------------------]]
local scrollFrame = CreateFrame("ScrollFrame", "BoxxyAurasCustomOptionsScrollFrame", customOptionsFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", instructionLabel, "BOTTOMLEFT", -5, -5) -- Position below new label
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50) 

-- Edit Box for Aura Names
local editBox = CreateFrame("EditBox", "BoxxyAurasCustomAuraEditBox", scrollFrame) -- Removed template for manual setup
editBox:SetPoint("TOPLEFT")
editBox:SetWidth(scrollFrame:GetWidth()) 
editBox:SetHeight(600) -- Height for ~6-7 lines
editBox:SetMultiLine(true)
editBox:SetAutoFocus(false)
editBox:SetTextInsets(15, 15, 15, 15)
-- Set font using template method if available, else manually
if editBox.SetFont then
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 10, "") -- Decreased Font Size to 10
else
    editBox:SetFontObject(ChatFontNormal)
end
editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
editBox:SetScript("OnTextChanged", function(self)
    -- Optional: Add visual feedback or debounce saving here if desired later
end)

-- <<< ADD Border >>>
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
    -- Draw the border using EdgedBorder texture
    BoxxyAuras.UIUtils.DrawSlicedBG(editBox, "EdgedBorder", "border", 0)
    -- Set initial border color (e.g., dark grey)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(editBox, "border", 0.6, 0.6, 0.6, 1)
else
    -- print("|cffFF0000BoxxyAuras Custom Options Error:|r Could not draw EditBox border (UIUtils missing).")
end

scrollFrame:SetScrollChild(editBox) -- Set EditBox as the scroll child directly

BoxxyAuras.CustomOptions.EditBox = editBox

-- Save Button
local saveButton = CreateFrame("Button", "BoxxyAurasCustomOptionsSaveButton", customOptionsFrame, "BAURASButtonTemplate") 
saveButton:SetPoint("BOTTOMLEFT", customOptionsFrame, "BOTTOMLEFT", 10, 10)
saveButton:SetPoint("BOTTOMRIGHT", customOptionsFrame, "BOTTOMRIGHT", -10, 10)
saveButton:SetHeight(25)
saveButton:SetText("Save Custom Auras")
saveButton:SetScript("OnClick", function()
    BoxxyAuras.CustomOptions:SaveCustomAuras()
    PlaySound(SOUNDKIT.UI_GARRISON_MISSION_COMPLETE) -- Or another satisfying sound
end)

BoxxyAuras.CustomOptions.SaveButton = saveButton

--[[------------------------------------------------------------
-- Functions to Load/Save/Toggle
--------------------------------------------------------------]]

-- Function to load aura names into the EditBox
function BoxxyAuras.CustomOptions:LoadCustomAuras()
    -- <<< Get settings from the CURRENTLY ACTIVE profile >>>
    local currentSettings = GetCurrentProfileSettings()

    if not currentSettings then
        -- print("|cffFF0000BoxxyAuras Custom Options:|r Cannot load, could not get profile settings.")
        self.EditBox:SetText("")
        return
    end

    -- <<< Use customAuraNames from the profile settings >>>
    local profileCustomAuras = currentSettings.customAuraNames
    if not profileCustomAuras then
        --  print("|cffFF0000BoxxyAuras Custom Options:|r Cannot load, customAuraNames not found in profile.")
         self.EditBox:SetText("")
         return
    end


    local names = {}
    -- <<< Iterate over the profile's custom aura names >>>
    for name, _ in pairs(profileCustomAuras) do
        table.insert(names, name)
    end
    table.sort(names) -- Sort alphabetically for consistent display
    self.EditBox:SetText(table.concat(names, ", "))
end

-- Function to parse EditBox text and save to DB
function BoxxyAuras.CustomOptions:SaveCustomAuras()
     -- <<< Get settings from the CURRENTLY ACTIVE profile >>>
    local currentSettings = GetCurrentProfileSettings()

    if not currentSettings then
        -- print("|cffFF0000BoxxyAuras Custom Options:|r Cannot save, could not get profile settings.")
        return
    end
    if not self.EditBox then return end

    local text = self.EditBox:GetText()
    local newCustomNames = {}

    -- Split the string by commas, trim whitespace
    for name in string.gmatch(text .. ',', "([^,]*),") do -- Add trailing comma to catch last item
        local trimmedName = string.trim(name)
        if trimmedName ~= "" then
            newCustomNames[trimmedName] = true -- Add to the new table
        end
    end

    -- <<< Save the new list to the ACTIVE profile's settings >>>
    currentSettings.customAuraNames = newCustomNames

    -- Optionally trigger an immediate update of the aura frames
    -- UpdateAuras will now read the custom list from the active profile automatically
    if BoxxyAuras.UpdateAuras then
        BoxxyAuras.UpdateAuras()
    end
end

-- Function to Toggle this options frame
function BoxxyAuras.CustomOptions:Toggle()
    local frame = self.Frame
    if not frame then
        -- print("BoxxyAuras Error: Custom Options Frame not found for Toggle.")
        return
    end

    if frame:IsShown() then
        frame:Hide()
    else
        -- <<< Positioning Logic Start >>>
        local mainOptions = BoxxyAuras.Options and BoxxyAuras.Options.Frame
        if mainOptions and mainOptions:IsShown() then
            frame:ClearAllPoints()
            local offset = 10 -- Pixels between frames
            
            -- Always position to the right
            frame:SetPoint("TOPLEFT", mainOptions, "TOPRIGHT", offset, 0)
        else
            -- Fallback if main options aren't shown or found: Center with offset
            -- BoxxyAuras.DebugLog("CustomPos Decision: Placing FALLBACK (Main Hidden)")
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 50, 50) 
        end
        -- <<< Positioning Logic End >>>
        
        -- <<< LoadCustomAuras now reads from the active profile >>>
        self:LoadCustomAuras() -- Load current names when showing
        frame:Show()
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end
