local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras = BoxxyAuras or {}
BoxxyAuras.CustomOptions = {} -- Table to hold custom options elements

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
    print("|cffFF0000BoxxyAuras Custom Options Error:|r Could not draw background.")
end

-- Border
local border = CreateFrame("Frame", nil, customOptionsFrame);
border:SetAllPoints();
border:SetFrameLevel(customOptionsFrame:GetFrameLevel() + 1);
if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
    BoxxyAuras.UIUtils.DrawSlicedBG(border, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(border, "border", 0.4, 0.4, 0.4, 1)
else
    print("|cffFF0000BoxxyAuras Custom Options Error:|r Could not draw border.")
end

-- Title
local title = customOptionsFrame:CreateFontString(nil, "ARTWORK", "BAURASFont_Title")
title:SetPoint("TOPLEFT", customOptionsFrame, "TOPLEFT", 20, -23)
title:SetText("Custom Aura List")

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
scrollFrame:SetPoint("TOPLEFT", 10, -50)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50) -- Adjusted bottom point for save button

-- Edit Box for Aura Names
local editBox = CreateFrame("EditBox", "BoxxyAurasCustomAuraEditBox", scrollFrame, "BAURASEditBoxTemplate") -- Use custom template
editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 5, -5)
editBox:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -5, 5)
editBox:SetMultiLine(true)
editBox:SetMaxLetters(1024) -- Limit input length
editBox:SetAutoFocus(false)
editBox:EnableMouse(true)
editBox:SetTextInsets(5, 5, 5, 5)
-- Set font using template method if available, else manually
if editBox.SetFont then
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
else
    editBox:SetFontObject(ChatFontNormal)
end
editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
editBox:SetScript("OnTextChanged", function(self)
    -- Optional: Add visual feedback or debounce saving here if desired later
end)
scrollFrame:SetScrollChild(editBox) -- Set EditBox as the scroll child directly

BoxxyAuras.CustomOptions.EditBox = editBox

-- Save Button
local saveButton = CreateFrame("Button", "BoxxyAurasCustomOptionsSaveButton", customOptionsFrame, "BAURASButtonTemplate") -- Use custom template
saveButton:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMLEFT", 0, -35)
saveButton:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, -35)
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
    if not BoxxyAurasDB or not BoxxyAurasDB.customAuraNames then
        print("|cffFF0000BoxxyAuras Custom Options:|r Cannot load, DB or customAuraNames not found.")
        self.EditBox:SetText("")
        return
    end

    local names = {}
    for name, _ in pairs(BoxxyAurasDB.customAuraNames) do
        table.insert(names, name)
    end
    table.sort(names) -- Sort alphabetically for consistent display
    self.EditBox:SetText(table.concat(names, ", "))
end

-- Function to parse EditBox text and save to DB
function BoxxyAuras.CustomOptions:SaveCustomAuras()
    if not BoxxyAurasDB then
        print("|cffFF0000BoxxyAuras Custom Options:|r Cannot save, DB not found.")
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

    -- DEBUG: Print what we are about to save
    print("--- Debug: Saving Custom Names Table ---")
    for name, _ in pairs(newCustomNames) do print("- " .. name) end
    print("-------------------------------------")

    BoxxyAurasDB.customAuraNames = newCustomNames -- Replace the old table
    print("BoxxyAuras: Custom aura list saved.")

    -- Optionally trigger an immediate update of the aura frames
    if BoxxyAuras.UpdateAuras then
        BoxxyAuras.UpdateAuras()
    end
end

-- Function to Toggle this options frame
function BoxxyAuras.CustomOptions:Toggle()
    local frame = self.Frame
    if not frame then
        print("BoxxyAuras Error: Custom Options Frame not found for Toggle.")
        return
    end

    if frame:IsShown() then
        frame:Hide()
    else
        self:LoadCustomAuras() -- Load current names when showing
        frame:Show()
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end
