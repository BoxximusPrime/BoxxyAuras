local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}      -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras        -- Create a convenient local alias to the global table

BoxxyAuras.UIUtils = {}

-- Copied from WhoGotLoots/UIBuilder.lua
BoxxyAuras.FrameTextures =
{
    -- We might only need a few of these initially
    ItemEntryBG = {
        file = "ItemBG", -- Assuming this texture exists or we replace it
        cornerSize = 4,
        cornerCoord = 16/64,
    },
    ItemEntryBorder = {
        file = "EdgedBorder_Sharp", -- Assuming this exists or we replace it
        cornerSize = 8,
        cornerCoord = 24/64,
    },
    BtnBG = { -- <<< ADDED for General Button Background
        file = "SelectionBox", -- Reuse SelectionBox or specific button texture
        cornerSize = 8, 
        cornerCoord = 0.25,
    },
    BtnBorder = { -- <<< ADDED for General Button Border
        file = "EdgedBorder", -- Reuse EdgedBorder
        cornerSize = 8,
        cornerCoord = 0.25,
    },
    -- Adding a simple border option
    TooltipBorder = {
        file = "Tooltip-Border", -- Standard WoW Tooltip Border
        cornerSize = 16,
        cornerCoord = 16/64, -- Typical coord for 16px corner on 64px texture
    },
    MainFrameHoverBG = { -- Added for main frame background
        file = "SelectionBox", -- Assumed texture file name
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    EdgedBorder = { -- Adding this border option from WhoGotLoots
        file = "EdgedBorder",
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    -- <<< RE-ADDING Frame Background Keys >>>
    BuffFrameHoverBG = { 
        file = "SelectionBox", 
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    DebuffFrameHoverBG = { 
        file = "SelectionBox", 
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    CustomFrameHoverBG = { 
        file = "SelectionBox", 
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    -- >>> ADDED Options Window Background <<<
    OptionsWindowBG = {
        file = "OptionsWindowBG", -- Assuming this texture file exists in Art/
        cornerSize = 12,        -- Adjust if needed
        cornerCoord = 0.25,       -- Adjust if needed
    }
    -- Add more keys from WhoGotLoots FrameTextures if needed
}

-- Copied from WhoGotLoots/UIBuilder.lua (Adapted slightly)
function BoxxyAuras.UIUtils.DrawSlicedBG(frame, textureKey, layer, shrink)
    shrink = shrink or 0;
    local group, subLevel;

    if layer == "backdrop" then
        if not frame.backdropTextures then
            frame.backdropTextures = {};
        end
        group = frame.backdropTextures;
        subLevel = -8; -- Ensure backdrop is behind other things
    elseif layer == "border" then
        if not frame.borderTextures then
            frame.borderTextures = {};
        end
        group = frame.borderTextures;
        subLevel = -7; -- Ensure border is above backdrop but behind content
    else
        return
    end

    local data = BoxxyAuras.FrameTextures[textureKey];
    if not data then
        print(string.format("|cffFF0000DrawSlicedBG Error:|r Texture key '%s' not found in FrameTextures table.", tostring(textureKey)))
        return
    end

    -- Construct file path - ensures forward slashes and adds extension
    local file = "Interface/AddOns/BoxxyAuras/Art/" .. data.file .. ".tga";
    local cornerSize = data.cornerSize;
    local coord = data.cornerCoord;
    local buildOrder = {1, 3, 7, 9, 2, 4, 6, 8, 5};
    local tex, key;

    for i = 1, 9 do
        key = buildOrder[i];
        if not group[key] then
            group[key] = frame:CreateTexture(nil, "BACKGROUND", nil, subLevel);
        else
            -- Texture already exists, ensure it's shown if frame is shown
            if frame:IsShown() then group[key]:Show() else group[key]:Hide() end
        end
        tex = group[key];
        local success, err = pcall(tex.SetTexture, tex, file, nil, nil, "LINEAR");
        if not success then
            print(string.format("|cffFF0000DrawSlicedBG Error:|r Failed to set texture '%s' for key %s (TextureKey: %s). Error: %s", file, tostring(key), tostring(textureKey), tostring(err)))
            tex:Hide() -- Hide texture if loading failed
        end

        if key == 2 or key == 8 then
            if key == 2 then
                tex:SetPoint("TOPLEFT", group[1], "TOPRIGHT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[3], "BOTTOMLEFT", 0, 0);
                tex:SetTexCoord(coord, 1-coord, 0, coord);
            else
                tex:SetPoint("TOPLEFT", group[7], "TOPRIGHT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[9], "BOTTOMLEFT", 0, 0);
                tex:SetTexCoord(coord, 1-coord, 1-coord, 1);
            end
        elseif key == 4 or key == 6 then
            if key == 4 then
                tex:SetPoint("TOPLEFT", group[1], "BOTTOMLEFT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[7], "TOPRIGHT", 0, 0);
                tex:SetTexCoord(0, coord, coord, 1-coord);
            else
                tex:SetPoint("TOPLEFT", group[3], "BOTTOMLEFT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[9], "TOPRIGHT", 0, 0);
                tex:SetTexCoord(1-coord, 1, coord, 1-coord);
            end
        elseif key == 5 then
            tex:SetPoint("TOPLEFT", group[1], "BOTTOMRIGHT", 0, 0);
            tex:SetPoint("BOTTOMRIGHT", group[9], "TOPLEFT", 0, 0);
            tex:SetTexCoord(coord, 1-coord, coord, 1-coord);
        else
            tex:SetSize(cornerSize, cornerSize);
            if key == 1 then
                tex:SetPoint("TOPLEFT", frame, "TOPLEFT", shrink, -shrink);
                tex:SetTexCoord(0, coord, 0, coord);
            elseif key == 3 then
                tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -shrink, -shrink);
                tex:SetTexCoord(1-coord, 1, 0, coord);
            elseif key == 7 then
                tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", shrink, shrink);
                tex:SetTexCoord(0, coord, 1-coord, 1);
            elseif key == 9 then
                tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -shrink, shrink);
                tex:SetTexCoord(1-coord, 1, 1-coord, 1);
            end
        end
    end
end

-- Copied from WhoGotLoots/UIBuilder.lua (Adapted slightly)
function BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, layer, r, g, b, a)
    local group = nil

    if layer == "backdrop" then
        group = frame.backdropTextures
    elseif layer == "border" then
        group = frame.borderTextures
    end

    if group then
        for key, tex in pairs(group) do
            local success, err = pcall(tex.SetVertexColor, tex, r, g, b, a)
            if not success then
                print(string.format("|cffFF0000ERROR:|r ColorBGSlicedFrame: pcall failed for SetVertexColor on key %s. Error: %s", tostring(key), tostring(err)))
            end
        end
    else
        print(string.format("|cffFF0000ColorBGSlicedFrame Error: Invalid layer or texture group not found for frame %s, layer: %s |r", frame:GetName(), tostring(layer)))
    end 
end

-- Function to set up buttons inheriting from BAURASGeneralButton
function BoxxyAuras_SetupGeneralButton(button)
    if not button then return end

    -- Ensure UIUtils functions are available before using them
    if BoxxyAuras and BoxxyAuras.UIUtils and 
       BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        
        -- Draw initial background and border
        BoxxyAuras.UIUtils.DrawSlicedBG(button, "BtnBG", "backdrop", -2)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(button, "backdrop", 0.3, 0.3, 0.3, 1) -- Default backdrop color
        BoxxyAuras.UIUtils.DrawSlicedBG(button, "BtnBorder", "border", -2)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(button, "border", 0.1, 0.1, 0.1, 1) -- Default border color

        -- Define methods directly on the button object
        function button:SetText(text)
            if self.Text then -- Check if the FontString child exists
                self.Text:SetText(text)
            end
        end

        function button:SetEnabled(enabled)
            self.Enabled = enabled -- Use the .Enabled property set in XML OnLoad
            -- Update appearance based on enabled state
            if enabled then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.3, 0.3, 0.3, 1)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.1, 0.1, 0.1, 1)
                if self.Text then self.Text:SetTextColor(0.75, 0.75, 0.75) end
            else
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.2, 0.2, 0.2, 1)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.3, 0.3, 0.3, 1)
                if self.Text then self.Text:SetTextColor(0.28, 0.28, 0.28) end
            end
        end

        function button:IsEnabled()
            return self.Enabled
        end

        -- Apply the initial enabled state visuals
        button:SetEnabled(button.Enabled)

        -- <<< ADDED LUA HOVER SCRIPTS >>>
        button:SetScript("OnEnter", function(self)
            if self:IsEnabled() then
                 BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.4, 0.4, 0.4, 1) 
                 BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.2, 0.2, 0.2, 1)
                 if self.Text then 
                    self.Text:SetTextColor(1, 1, 1, 1) -- White on hover
                 end
            end
        end)

        button:SetScript("OnLeave", function(self)
            if self:IsEnabled() then
                 BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.3, 0.3, 0.3, 1) 
                 BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.1, 0.1, 0.1, 1)
                 if self.Text then
                     self.Text:SetTextColor(0.75, 0.75, 0.75, 1) -- Default enabled grey
                 end
            end
        end)

        -- <<< ADDED MouseDown/MouseUp Scripts >>>
        button:SetScript("OnMouseDown", function(self)
            if self:IsEnabled() then
                -- Move text down+right
                if self.Text then
                    self.Text:ClearAllPoints()
                    self.Text:SetPoint("CENTER", self, "CENTER", 1, -1) -- Adjust offset as needed
                end
                -- Optional: Set "pressed" colors (e.g., slightly darker than hover)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.35, 0.35, 0.35, 1) 
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.15, 0.15, 0.15, 1) 
            end
        end)

        button:SetScript("OnMouseUp", function(self)
            if self:IsEnabled() then
                -- Move text back to center
                if self.Text then
                    self.Text:ClearAllPoints()
                    self.Text:SetPoint("CENTER", self, "CENTER", 0, 0)
                end
                
                -- Re-apply hover or normal colors based on mouse position
                if self:IsMouseOver() then 
                    -- Still hovering: Apply hover colors
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.4, 0.4, 0.4, 1) 
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.2, 0.2, 0.2, 1)
                    if self.Text then self.Text:SetTextColor(1, 1, 1, 1) end -- Ensure text is hover color
                else
                    -- Mouse left while pressed: Apply normal colors
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.3, 0.3, 0.3, 1) 
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.1, 0.1, 0.1, 1)
                    if self.Text then self.Text:SetTextColor(0.75, 0.75, 0.75, 1) end -- Ensure text is normal color
                end
            end
        end)

    else
        print(string.format("|cffFF0000BoxxyAuras Error:|r UIUtils functions not found when setting up button '%s' via BoxxyAuras_SetupGeneralButton.", button:GetName() or "(unknown)"))
    end
end 

-- Tooltip Scraping Function (Using GetUnitAura, finds index via auraInstanceID)
function BoxxyAuras.AttemptTooltipScrape(spellId, targetAuraInstanceID, filter) 
    -- Check if already scraped (key exists in AllAuras) - Use spellId as key
    if spellId and BoxxyAuras.AllAuras[spellId] then return end 
    -- Validate inputs 
    if not spellId or not targetAuraInstanceID or not filter then 
        print(string.format("DEBUG Scrape Error: Invalid arguments. spellId: %s, instanceId: %s, filter: %s",
            tostring(spellId), tostring(targetAuraInstanceID), tostring(filter)))
        return 
    end

    -- Find the CURRENT index for this specific aura instance
    local currentAuraIndex = nil
    for i = 1, 40 do -- Check up to 40 auras (standard limit)
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if auraData then
            -- Compare instance IDs
            if auraData.auraInstanceID == targetAuraInstanceID then
                currentAuraIndex = i
                break
            end
        end
    end

    local tipData = C_TooltipInfo.GetUnitAura("player", currentAuraIndex, filter)

    if not tipData then 
        -- This failure is now less likely, but could still happen in rare cases
        print(string.format("DEBUG Scrape Error: GetUnitAura failed unexpectedly for SpellID: %s (Found Index: %s, Filter: %s) via InstanceID %s", 
            tostring(spellId), tostring(currentAuraIndex), filter, tostring(targetAuraInstanceID)))
        return
    end

    -- Get tooltip lines
    local tooltipLines = {}
    local spellNameFromTip = nil -- Variable to store name from tooltip

    -- Use a flag to track if we have processed the first line
    local firstLineProcessed = false

    if tipData.lines then
        for i = 1, #tipData.lines do
            local lineData = tipData.lines[i]
            if lineData and lineData.leftText then
                local lineText = lineData.leftText -- Keep original left text separate
                if lineData.rightText then 
                    lineText = lineText .. " " .. lineData.rightText 
                end
                
                -- Store the first line's left text as the potential name
                if not firstLineProcessed and lineData.leftText then
                    spellNameFromTip = lineData.leftText
                    firstLineProcessed = true -- Mark as processed here, even if skipped below
                end
                
                -- *** ADDED: Duration Check ***
                local isDurationLine = false
                local lowerLineText = string.lower(lineText)
                if string.find(lowerLineText, "second") or 
                   string.find(lowerLineText, "minute") or 
                   string.find(lowerLineText, "hour") then
                    isDurationLine = true
                end
                
                -- Store left and right parts separately ONLY if NOT a duration line
                if not isDurationLine then
                    local lineInfo = { left = lineData.leftText }
                    if lineData.rightText then
                        lineInfo.right = lineData.rightText
                    end
                    table.insert(tooltipLines, lineInfo)
                end
            end
        end
    end

    -- Store the collected lines in the global cache using spellId as the key
    if spellId and tooltipLines and #tooltipLines > 0 then
        BoxxyAuras.AllAuras[spellId] = { 
            name = spellNameFromTip or "Unknown", -- Store the name from the first line
            lines = tooltipLines -- Store the table of line info tables
        }
    elseif spellId then
        -- Even if no lines after filtering, store something to prevent re-scraping
        BoxxyAuras.AllAuras[spellId] = { 
            name = spellNameFromTip or "Unknown", 
            lines = {}
        }
    end

    -- Store SOMETHING minimal in the cache to prevent re-scraping, but don't process lines
    if spellId then
        local existingCache = BoxxyAuras.AllAuras[spellId]
        -- Only add minimal cache if it doesn't exist at all
        if not existingCache then
            print("Didn't end up cached, THIS SHOULD NOT HAPPEN")
        end
    end
end 

-- Function to check if mouse cursor is within a frame's bounds
function BoxxyAuras.IsMouseWithinFrame(frame)
    if not frame or not frame:IsVisible() then return false end
    local mouseX, mouseY = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local left, bottom, width, height = frame:GetBoundsRect()

    if not left then return false end -- Frame might not be fully positioned yet

    mouseX = mouseX / scale
    mouseY = mouseY / scale

    return mouseX >= left and mouseX <= left + width and mouseY >= bottom and mouseY <= bottom + height
end

function BoxxyAuras.DebugLog(message)
    print(string.format("DEBUG: %s", message))
end

function BoxxyAuras.DebugLogError(message)
    print(string.format("|cffFF0000ERROR:|r %s", message))
end

function BoxxyAuras.DebugLogWarning(message)
    print(string.format("|cffFFFF00WARNING:|r %s", message))
end
