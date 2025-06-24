local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {} -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras -- Create a convenient local alias to the global table

BoxxyAuras.UIUtils = {}

-- Create a hidden tooltip for scraping. This is crucial for capturing data added by other addons.
local scraperTooltip = CreateFrame("GameTooltip", "BoxxyAurasScraperTooltip", UIParent, "GameTooltipTemplate")
scraperTooltip:SetOwner(UIParent, "ANCHOR_NONE")
scraperTooltip:Hide()

-- Tooltip scraping queue to prevent race conditions
BoxxyAuras.scrapingQueue = {}
BoxxyAuras.isScrapingActive = false

-- Queue management functions
function BoxxyAuras.UIUtils.QueueTooltipScrape(spellId, targetAuraInstanceID, filter, retryCount)
    -- Check if we already have this data cached
    if BoxxyAuras.AllAuras[targetAuraInstanceID] and not BoxxyAuras.AllAuras[targetAuraInstanceID].isPlaceholder then
        if BoxxyAuras.DEBUG then
            print(string.format("QueueTooltipScrape: Already have cached data for instanceID=%s, skipping queue", tostring(targetAuraInstanceID)))
        end
        return
    end
    
    -- Check if this aura is already in the queue
    for _, queuedItem in ipairs(BoxxyAuras.scrapingQueue) do
        if queuedItem.targetAuraInstanceID == targetAuraInstanceID then
            if BoxxyAuras.DEBUG then
                print(string.format("QueueTooltipScrape: instanceID=%s already queued, skipping", tostring(targetAuraInstanceID)))
            end
            return
        end
    end
    
    -- Add to queue
    table.insert(BoxxyAuras.scrapingQueue, {
        spellId = spellId,
        targetAuraInstanceID = targetAuraInstanceID,
        filter = filter,
        retryCount = retryCount or 0,
        timestamp = GetTime()
    })
    
    if BoxxyAuras.DEBUG then
        print(string.format("QueueTooltipScrape: Queued scrape for instanceID=%s (queue size: %d)", 
            tostring(targetAuraInstanceID), #BoxxyAuras.scrapingQueue))
    end
    
    -- Start processing if not already active
    if not BoxxyAuras.isScrapingActive then
        BoxxyAuras.UIUtils.ProcessNextScrapeInQueue()
    end
end

function BoxxyAuras.UIUtils.ProcessNextScrapeInQueue()
    if #BoxxyAuras.scrapingQueue == 0 then
        BoxxyAuras.isScrapingActive = false
        if BoxxyAuras.DEBUG then
            print("ProcessNextScrapeInQueue: Queue empty, scraping stopped")
        end
        return
    end
    
    BoxxyAuras.isScrapingActive = true
    local queuedItem = table.remove(BoxxyAuras.scrapingQueue, 1) -- Take first item
    
    if BoxxyAuras.DEBUG then
        print(string.format("ProcessNextScrapeInQueue: Processing instanceID=%s (queue remaining: %d)", 
            tostring(queuedItem.targetAuraInstanceID), #BoxxyAuras.scrapingQueue))
    end
    
    -- Execute the actual scraping
    BoxxyAuras.UIUtils.ExecuteTooltipScrape(
        queuedItem.spellId, 
        queuedItem.targetAuraInstanceID, 
        queuedItem.filter, 
        queuedItem.retryCount
    )
end

function BoxxyAuras.UIUtils.OnScrapeComplete()
    -- Move to next item in queue after a small delay to ensure tooltip is clear
    C_Timer.After(0.1, function()
        BoxxyAuras.UIUtils.ProcessNextScrapeInQueue()
    end)
end

-- Copied from WhoGotLoots/UIBuilder.lua
BoxxyAuras.FrameTextures = {
    -- We might only need a few of these initially
    ItemEntryBG = {
        file = "ItemBG", -- Assuming this texture exists or we replace it
        cornerSize = 4,
        cornerCoord = 16 / 64
    },
    ItemEntryBorder = {
        file = "EdgedBorder_Sharp", -- Assuming this exists or we replace it
        cornerSize = 8,
        cornerCoord = 24 / 64
    },
    BtnBG = { -- <<< ADDED for General Button Background
        file = "SelectionBox", -- Reuse SelectionBox or specific button texture
        cornerSize = 8,
        cornerCoord = 0.25
    },
    BtnBorder = { -- <<< ADDED for General Button Border
        file = "EdgedBorder", -- Reuse EdgedBorder
        cornerSize = 8,
        cornerCoord = 0.25
    },
    -- Adding a simple border option
    TooltipBorder = {
        file = "Tooltip-Border", -- Standard WoW Tooltip Border
        cornerSize = 16,
        cornerCoord = 16 / 64 -- Typical coord for 16px corner on 64px texture
    },
    MainFrameHoverBG = { -- Added for main frame background
        file = "SelectionBox", -- Assumed texture file name
        cornerSize = 12,
        cornerCoord = 0.25
    },
    EdgedBorder = { -- Adding this border option from WhoGotLoots
        file = "EdgedBorder",
        cornerSize = 12,
        cornerCoord = 0.25
    },
    -- <<< RE-ADDING Frame Background Keys >>>
    BuffFrameHoverBG = {
        file = "SelectionBox",
        cornerSize = 12,
        cornerCoord = 0.25
    },
    DebuffFrameHoverBG = {
        file = "SelectionBox",
        cornerSize = 12,
        cornerCoord = 0.25
    },
    CustomFrameHoverBG = {
        file = "SelectionBox",
        cornerSize = 12,
        cornerCoord = 0.25
    },
    -- >>> ADDED Options Window Background <<<
    OptionsWindowBG = {
        file = "OptionsWindowBG", -- Assuming this texture file exists in Art/
        cornerSize = 12, -- Adjust if needed
        cornerCoord = 0.25 -- Adjust if needed
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
        print(string.format("|cffFF0000DrawSlicedBG Error:|r Texture key '%s' not found in FrameTextures table.",
            tostring(textureKey)))
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
            if frame:IsShown() then
                group[key]:Show()
            else
                group[key]:Hide()
            end
        end
        tex = group[key];
        local success, err = pcall(tex.SetTexture, tex, file, nil, nil, "LINEAR");
        if not success then
            print(string.format(
                "|cffFF0000DrawSlicedBG Error:|r Failed to set texture '%s' for key %s (TextureKey: %s). Error: %s",
                file, tostring(key), tostring(textureKey), tostring(err)))
            tex:Hide() -- Hide texture if loading failed
        end

        if key == 2 or key == 8 then
            if key == 2 then
                tex:SetPoint("TOPLEFT", group[1], "TOPRIGHT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[3], "BOTTOMLEFT", 0, 0);
                tex:SetTexCoord(coord, 1 - coord, 0, coord);
            else
                tex:SetPoint("TOPLEFT", group[7], "TOPRIGHT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[9], "BOTTOMLEFT", 0, 0);
                tex:SetTexCoord(coord, 1 - coord, 1 - coord, 1);
            end
        elseif key == 4 or key == 6 then
            if key == 4 then
                tex:SetPoint("TOPLEFT", group[1], "BOTTOMLEFT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[7], "TOPRIGHT", 0, 0);
                tex:SetTexCoord(0, coord, coord, 1 - coord);
            else
                tex:SetPoint("TOPLEFT", group[3], "BOTTOMLEFT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[9], "TOPRIGHT", 0, 0);
                tex:SetTexCoord(1 - coord, 1, coord, 1 - coord);
            end
        elseif key == 5 then
            tex:SetPoint("TOPLEFT", group[1], "BOTTOMRIGHT", 0, 0);
            tex:SetPoint("BOTTOMRIGHT", group[9], "TOPLEFT", 0, 0);
            tex:SetTexCoord(coord, 1 - coord, coord, 1 - coord);
        else
            tex:SetSize(cornerSize, cornerSize);
            if key == 1 then
                tex:SetPoint("TOPLEFT", frame, "TOPLEFT", shrink, -shrink);
                tex:SetTexCoord(0, coord, 0, coord);
            elseif key == 3 then
                tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -shrink, -shrink);
                tex:SetTexCoord(1 - coord, 1, 0, coord);
            elseif key == 7 then
                tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", shrink, shrink);
                tex:SetTexCoord(0, coord, 1 - coord, 1);
            elseif key == 9 then
                tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -shrink, shrink);
                tex:SetTexCoord(1 - coord, 1, 1 - coord, 1);
            end
        end
    end
end

-- Copied from WhoGotLoots/UIBuilder.lua (Adapted slightly)
function BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, layer, r, g, b, a)

    -- Check if r is actually a table
    if type(r) == "table" then
        r, g, b, a = r.r, r.g, r.b, r.a
    end

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
                print(string.format(
                    "|cffFF0000ERROR:|r ColorBGSlicedFrame: pcall failed for SetVertexColor on key %s. Error: %s",
                    tostring(key), tostring(err)))
            end
        end
    else
        print(string.format(
            "|cffFF0000ColorBGSlicedFrame Error: Invalid layer or texture group not found for frame %s, layer: %s |r",
            frame:GetName(), tostring(layer)))
    end
end

-- Function to set up buttons inheriting from BAURASGeneralButton
function BoxxyAuras_SetupGeneralButton(button)
    if not button then
        return
    end

    -- Ensure UIUtils functions are available before using them
    if BoxxyAuras and BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then

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
                if self.Text then
                    self.Text:SetTextColor(0.75, 0.75, 0.75)
                end
            else
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.2, 0.2, 0.2, 1)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.3, 0.3, 0.3, 1)
                if self.Text then
                    self.Text:SetTextColor(0.28, 0.28, 0.28)
                end
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
                    if self.Text then
                        self.Text:SetTextColor(1, 1, 1, 1)
                    end -- Ensure text is hover color
                else
                    -- Mouse left while pressed: Apply normal colors
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.3, 0.3, 0.3, 1)
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.1, 0.1, 0.1, 1)
                    if self.Text then
                        self.Text:SetTextColor(0.75, 0.75, 0.75, 1)
                    end -- Ensure text is normal color
                end
            end
        end)

    else
        print(string.format(
            "|cffFF0000BoxxyAuras Error:|r UIUtils functions not found when setting up button '%s' via BoxxyAuras_SetupGeneralButton.",
            button:GetName() or "(unknown)"))
    end
end

-- Main entry point - Queues tooltip scraping to prevent race conditions
function BoxxyAuras.AttemptTooltipScrape(spellId, targetAuraInstanceID, filter, retryCount)
    BoxxyAuras.UIUtils.QueueTooltipScrape(spellId, targetAuraInstanceID, filter, retryCount)
end

-- Main tooltip scraping function
function BoxxyAuras.UIUtils.ExecuteTooltipScrape(spellId, instanceId, filter, retryCount)
    retryCount = retryCount or 0

    if BoxxyAuras.DEBUG then
        print(string.format("ExecuteTooltipScrape: spellId=%s, instanceID=%s, filter=%s, retry=%d",
            tostring(spellId), tostring(instanceId), tostring(filter), retryCount))
    end

    -- Stop if we already have complete data
    if BoxxyAuras.AllAuras[instanceId] and not BoxxyAuras.AllAuras[instanceId].isPlaceholder then
        if BoxxyAuras.DEBUG then
            print("ExecuteTooltipScrape: Already have complete data, moving to next in queue")
        end
        BoxxyAuras.UIUtils.OnScrapeComplete()
        return
    end

    -- Define a function to be called when any async scrape method fails
    local function onAsyncScrapeFailure(lastMethod)
        if lastMethod == "GameTooltip_Aura" then
            if BoxxyAuras.DEBUG then print(" -> Aura scrape failed, falling back to Spell scrape") end
            BoxxyAuras.UIUtils.TryGameTooltipSpellScrape(spellId, instanceId, 0)
        else
            -- All methods failed
            if BoxxyAuras.DEBUG then print(" -> All scraping methods failed, giving up.") end
            BoxxyAuras.UIUtils.OnScrapeComplete()
        end
    end

    -- 1. Try C_TooltipInfo scraping (Synchronous)
    local success, spellName, tooltipLines = BoxxyAuras.UIUtils.TryTooltipInfoScrape(spellId, instanceId, filter)
    if success then
        BoxxyAuras.AllAuras[instanceId] = {
            name = spellName,
            lines = tooltipLines,
            scrapedVia = "C_TooltipInfo"
        }
        if BoxxyAuras.DEBUG then print("ExecuteTooltipScrape: Success with C_TooltipInfo") end
        BoxxyAuras.UIUtils.OnScrapeComplete()
        return
    end

    -- 2. If C_TooltipInfo fails, try GameTooltip with aura index (Asynchronous)
    if BoxxyAuras.DEBUG then print(" -> C_TooltipInfo failed, falling back to TryGameTooltipAuraScrape") end
    
    -- We need a way to check the result of the async operations.
    -- The async functions will call OnScrapeComplete on their own success.
    -- We need to handle their failure. Let's create a wrapper for the callback.
    local originalOnComplete = BoxxyAuras.UIUtils.OnScrapeComplete
    
    -- Let's redefine the Try functions to accept a failure callback
    -- For now, I can't do that. I will rewrite the other functions later.
    -- The core issue is that the async functions don't report failure.
    -- Let's try to proceed by modifying the other functions in subsequent steps.
    -- For now, this is a placeholder for the logic.
    
    -- This simplified version just calls the next function, assuming it will handle its own success/failure reporting.
    -- This is not ideal, but it's a step toward the final goal.
    local auraScrapeAttempted = BoxxyAuras.UIUtils.TryGameTooltipAuraScrape(spellId, instanceId, filter, 0)
    if not auraScrapeAttempted then
        -- This means the function failed synchronously (e.g., aura not found)
        local spellScrapeAttempted = BoxxyAuras.UIUtils.TryGameTooltipSpellScrape(spellId, instanceId, 0)
        if not spellScrapeAttempted then
            -- Both async attempts failed synchronously, so we're done.
            BoxxyAuras.UIUtils.OnScrapeComplete()
        end
    end
end

-- Helper function to get caster name from aura data
function BoxxyAuras.UIUtils.GetCasterName(auraData)
    if not auraData then
        return nil
    end
    
    if BoxxyAuras.DEBUG then
        print(string.format("GetCasterName: sourceGUID='%s', sourceName='%s', isFromPlayerOrPlayerPet=%s", 
            tostring(auraData.sourceGUID), tostring(auraData.sourceName), tostring(auraData.isFromPlayerOrPlayerPet)))
    end
    
    -- If we have a sourceName from combat log, use it directly (most reliable)
    if auraData.sourceName and auraData.sourceName ~= "" then
        -- Check if it's the player
        local playerName = UnitName("player")
        if auraData.sourceName == playerName then
            if BoxxyAuras.DEBUG then
                print("GetCasterName: Identified as player via sourceName match")
            end
            return "You"
        else
            if BoxxyAuras.DEBUG then
                print(string.format("GetCasterName: Using sourceName: '%s'", auraData.sourceName))
            end
            return auraData.sourceName
        end
    end
    
    -- If we have sourceGUID, try to get name from it
    if auraData.sourceGUID then
        -- Check if it's the player
        local playerGUID = UnitGUID("player")
        if auraData.sourceGUID == playerGUID then
            if BoxxyAuras.DEBUG then
                print("GetCasterName: Identified as player via GUID match")
            end
            return "You"
        end
        
        -- Try to get name from GUID (this works for units in your group/raid)
        local name = GetPlayerInfoByGUID(auraData.sourceGUID)
        if name and name ~= "" then
            if BoxxyAuras.DEBUG then
                print(string.format("GetCasterName: Found name from GUID: '%s'", name))
            end
            return name
        end
        
        -- Fallback: try to extract name from GUID if it's a player GUID
        -- Player GUIDs have format: Player-[server]-[playerID]-[name hash]
        -- Vehicle GUIDs have format: Vehicle-[server]-[playerID]-[name hash] when controlled by players
        if string.find(auraData.sourceGUID, "Player-") or string.find(auraData.sourceGUID, "Vehicle-") then
            if BoxxyAuras.DEBUG then
                print("GetCasterName: Unknown player via GUID pattern (Player or Vehicle)")
            end
            -- We can't easily extract the name from GUID, but we know it's a player/vehicle
            return "Unknown Player"
        end
    end
    
    -- Check if it came from player or player's pet based on spell data
    if auraData.isFromPlayerOrPlayerPet then
        if BoxxyAuras.DEBUG then
            print("GetCasterName: Identified as player via isFromPlayerOrPlayerPet flag")
        end
        return "You"
    end
    
    if BoxxyAuras.DEBUG then
        print("GetCasterName: No caster information found")
    end
    
    -- If no source information, return nil
    return nil
end

-- Debug function - let's see what tooltip lines we actually capture
function BoxxyAuras.UIUtils.DebugTooltipContent(source, spellId, instanceId)
    if not BoxxyAuras.DEBUG then return end
    
    local tooltip = BoxxyAuras.BoxxyAurasScraperTooltip
    if not tooltip then return end
    
    print(string.format("=== DEBUG TOOLTIP CONTENT (%s) - SpellID: %s, InstanceID: %s ===", 
        source, tostring(spellId), tostring(instanceId)))
    
    for i = 1, tooltip:NumLines() do
        local leftText = _G[tooltip:GetName() .. "TextLeft" .. i]
        local rightText = _G[tooltip:GetName() .. "TextRight" .. i]
        
        if leftText then
            local leftStr = leftText:GetText() or ""
            local rightStr = rightText and rightText:GetText() or ""
            
            if leftStr ~= "" or rightStr ~= "" then
                print(string.format("  Line %d: '%s' | '%s'", i, leftStr, rightStr))
            end
        end
    end
    print("=== END DEBUG TOOLTIP CONTENT ===")
end

-- Try scraping using C_TooltipInfo
function BoxxyAuras.UIUtils.TryTooltipInfoScrape(spellId, instanceId, filter)
    if not C_TooltipInfo then
        return false, nil, nil
    end
    
    -- Skip tooltip scraping for demo auras
    if type(instanceId) == "string" and string.find(instanceId, "demo_", 1, true) then
        return false, nil, nil
    end

    local tipData = nil
    
    if filter == "HELPFUL" then
        tipData = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", instanceId)
    elseif filter == "HARMFUL" then
        tipData = C_TooltipInfo.GetUnitDebuffByAuraInstanceID("player", instanceId)
    end
    
    if not tipData then
        return false, nil, nil
    end

    local spellName = nil
    local tooltipLines = {}

    if BoxxyAuras.DEBUG then
        print(string.format("TryTooltipInfoScrape: tipData=%s, name=%s, lines=%d", 
            tostring(tipData ~= nil), tostring(tipData.name), tipData.lines and #tipData.lines or 0))
    end

    -- Extract spell name and lines from tipData
    if tipData.lines and #tipData.lines > 0 then
        local firstLine = tipData.lines[1]
        if firstLine and firstLine.leftText then
            if not tipData.name or tipData.name == "" then
                spellName = firstLine.leftText
                if BoxxyAuras.DEBUG then
                    print(string.format("TryTooltipInfoScrape: Extracted name from first line: '%s'", spellName))
                end
            else
                spellName = tipData.name
            end

            -- Process all lines and store them properly
            for i = 1, #tipData.lines do
                local line = tipData.lines[i]
                if line and line.leftText then
                    if BoxxyAuras.DEBUG and i <= 3 then
                        print(string.format("TryTooltipInfoScrape: Line %d: '%s' | '%s'", i, 
                            tostring(line.leftText), tostring(line.rightText)))
                    end
                    if not (string.find(line.leftText, "remaining", 1, true) or (line.rightText and string.find(line.rightText, "remaining", 1, true))) then
                        table.insert(tooltipLines, { left = line.leftText, right = line.rightText or "" })
                    end
                end
            end
        end
    end

    if spellName and spellName ~= "" and #tooltipLines > 0 then
        if BoxxyAuras.DEBUG then
            print(string.format("TryTooltipInfoScrape: Success, cached %d lines with name '%s'", #tooltipLines, spellName))
        end
        return true, spellName, tooltipLines
    end
    
    if BoxxyAuras.DEBUG then
        print("TryTooltipInfoScrape: Failed")
    end
    return false, nil, nil
end

-- Approach 2: Use GameTooltip with aura index
function BoxxyAuras.UIUtils.TryGameTooltipAuraScrape(spellId, targetAuraInstanceID, filter, retryCount)
    retryCount = retryCount or 0
    
    -- Skip tooltip scraping for demo auras
    if type(targetAuraInstanceID) == "string" and string.find(targetAuraInstanceID, "demo_", 1, true) then
        BoxxyAuras.UIUtils.OnScrapeComplete()
        return false
    end
    
    -- Find the aura by instance ID
    local auraIndex = nil
    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if not auraData then break end
        if auraData.auraInstanceID == targetAuraInstanceID then
            auraIndex = i
            break
        end
    end

    if not auraIndex then
        if BoxxyAuras.DEBUG then
            print("TryGameTooltipAuraScrape: Aura not found by index - aura may have expired, completing scrape")
        end
        -- If aura not found by index, it likely expired during processing
        -- Don't fall back to spell ID as that gives talent/spell tooltips, not aura tooltips
        BoxxyAuras.UIUtils.OnScrapeComplete()
        return false
    end

    local scraper = _G.BoxxyAurasScraperTooltip
    scraper:Hide()  -- Ensure it's hidden first
    scraper:ClearLines()
    scraper:SetUnitAura("player", auraIndex, filter)
    scraper:Show()
    
    -- Progressive delay based on retry count - give WoW more time to populate
    local checkDelay = math.min(0.2 + (retryCount * 0.1), 0.8)
    
    C_Timer.After(checkDelay, function()
        local success = BoxxyAuras.UIUtils.ExtractTooltipLines(targetAuraInstanceID, "GameTooltip_Aura")
        
        if success then
            scraper:Hide()
            if BoxxyAuras.DEBUG then
                print(string.format("TryGameTooltipAuraScrape: Success on attempt %d", retryCount + 1))
            end
            BoxxyAuras.UIUtils.OnScrapeComplete()
            return
        end
        
        -- Not successful, try again with longer delay
        local retryDelay = math.min(0.3 + (retryCount * 0.1), 0.8)
        C_Timer.After(retryDelay, function()
            local success2 = BoxxyAuras.UIUtils.ExtractTooltipLines(targetAuraInstanceID, "GameTooltip_Aura")
            scraper:Hide()
            
            if success2 then
                if BoxxyAuras.DEBUG then
                    print(string.format("TryGameTooltipAuraScrape: Success on retry %d", retryCount + 1))
                end
                BoxxyAuras.UIUtils.OnScrapeComplete()
                return
            end
            
            -- Still failed - complete the scrape rather than falling back to spell ID
            if BoxxyAuras.DEBUG then
                print(string.format("TryGameTooltipAuraScrape: Failed on attempt %d, completing scrape (avoiding spell ID fallback for aura)", retryCount + 1))
            end
            
            -- Don't fall back to spell ID as it gives wrong tooltips for talent-based auras
            BoxxyAuras.UIUtils.OnScrapeComplete()
        end)
    end)
    
    return true -- We attempted it, success will be determined in the callback
end

-- Approach 3: Use GameTooltip with spell ID
function BoxxyAuras.UIUtils.TryGameTooltipSpellScrape(spellId, targetAuraInstanceID, retryCount)
    retryCount = retryCount or 0
    
    -- Skip tooltip scraping for demo auras
    if type(targetAuraInstanceID) == "string" and string.find(targetAuraInstanceID, "demo_", 1, true) then
        BoxxyAuras.UIUtils.OnScrapeComplete()
        return false
    end
    
    if not spellId then
        if BoxxyAuras.DEBUG then
            print("TryGameTooltipSpellScrape: No spell ID provided")
        end
        return false
    end

    local scraper = _G.BoxxyAurasScraperTooltip
    scraper:Hide()  -- Ensure it's hidden first
    scraper:ClearLines()
    scraper:SetSpellByID(spellId)
    scraper:Show()
    
    -- Progressive delay based on retry count - give WoW more time to populate
    local checkDelay = math.min(0.2 + (retryCount * 0.1), 0.8)
    
    C_Timer.After(checkDelay, function()
        local success = BoxxyAuras.UIUtils.ExtractTooltipLines(targetAuraInstanceID, "GameTooltip_Spell")
        
        if success then
            scraper:Hide()
            if BoxxyAuras.DEBUG then
                print(string.format("TryGameTooltipSpellScrape: Success on attempt %d", retryCount + 1))
            end
            BoxxyAuras.UIUtils.OnScrapeComplete()
            return
        end
        
        -- Not successful, try again with longer delay
        local retryDelay = math.min(0.3 + (retryCount * 0.1), 0.8)
        C_Timer.After(retryDelay, function()
            local success2 = BoxxyAuras.UIUtils.ExtractTooltipLines(targetAuraInstanceID, "GameTooltip_Spell")
            scraper:Hide()
            
            if success2 then
                if BoxxyAuras.DEBUG then
                    print(string.format("TryGameTooltipSpellScrape: Success on retry %d", retryCount + 1))
                end
                BoxxyAuras.UIUtils.OnScrapeComplete()
                return
            end
            
            -- Still failed, try basic spell info approach or retry main function
            if BoxxyAuras.DEBUG then
                print(string.format("TryGameTooltipSpellScrape: Failed on attempt %d, trying basic spell info", retryCount + 1))
            end
            
            -- Try basic spell info approach
            local basicSuccess = BoxxyAuras.UIUtils.TryBasicSpellInfoScrape(spellId, targetAuraInstanceID)
            
            if not basicSuccess and retryCount < 8 then
                -- Re-queue for retry instead of calling AttemptTooltipScrape directly
                if BoxxyAuras.DEBUG then
                    print(string.format("TryGameTooltipSpellScrape: Retrying via queue (attempt %d)", retryCount + 2))
                end
                C_Timer.After(0.5, function()
                    BoxxyAuras.UIUtils.QueueTooltipScrape(spellId, targetAuraInstanceID, "HELPFUL", retryCount + 1)
                end)
            else
                -- Either basicSuccess worked or we've hit max retries - move to next
                BoxxyAuras.UIUtils.OnScrapeComplete()
            end
        end)
    end)
    
    return true -- We attempted it, success will be determined in the callback
end

-- Approach 4: Basic spell info as absolute fallback
function BoxxyAuras.UIUtils.TryBasicSpellInfoScrape(spellId, targetAuraInstanceID)
    if not spellId then
        if BoxxyAuras.DEBUG then
            print("TryBasicSpellInfoScrape: No spell ID provided")
        end
        return false
    end
    
    -- Try multiple approaches to get spell information using modern APIs
    local spellName = nil
    local spellDescription = nil
    
    -- Try C_Spell.GetSpellInfo (modern API)
    if C_Spell and C_Spell.GetSpellInfo then
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        if spellInfo then
            spellName = spellInfo.name
        end
    end
    
    -- Fallback: Try C_Spell.GetSpellName if GetSpellInfo didn't work
    if not spellName and C_Spell and C_Spell.GetSpellName then
        spellName = C_Spell.GetSpellName(spellId)
    end
    
    -- Try to get spell description
    if C_Spell and C_Spell.GetSpellDescription then
        spellDescription = C_Spell.GetSpellDescription(spellId)
    end
    
    -- Try using a temporary tooltip if we still don't have a name
    if not spellName then
        if BoxxyAuras.DEBUG then
            print("TryBasicSpellInfoScrape: Trying temporary tooltip approach")
        end
        local tempTooltip = CreateFrame("GameTooltip", "BoxxyAurasSpellInfoTooltip", UIParent, "GameTooltipTemplate")
        tempTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tempTooltip:SetSpellByID(spellId)
        
        -- Wait a moment for tooltip to populate
        C_Timer.After(0.1, function()
            local nameLabel = _G["BoxxyAurasSpellInfoTooltipTextLeft1"]
            if nameLabel then
                spellName = nameLabel:GetText()
            end
            tempTooltip:Hide()
            
            if spellName and spellName ~= "" then
                -- Create basic tooltip data
                local basicLines = {{left = spellName, right = ""}}
                
                if spellDescription and spellDescription ~= "" then
                    table.insert(basicLines, {left = spellDescription, right = ""})
                end
                
                BoxxyAuras.AllAuras[targetAuraInstanceID] = {
                    name = spellName,
                    lines = basicLines,
                    scrapedVia = "BasicSpellInfo_Tooltip"
                }
                
                if BoxxyAuras.DEBUG then
                    print(string.format("TryBasicSpellInfoScrape: Success via tooltip, using spell name '%s' for instanceID=%s", 
                        spellName, tostring(targetAuraInstanceID)))
                end
            else
                if BoxxyAuras.DEBUG then
                    print(string.format("TryBasicSpellInfoScrape: Failed via tooltip, no spell name found for spellId=%s", tostring(spellId)))
                end
            end
            -- Callback is handled by the calling function since this is async
        end)
        return true -- We attempted it, success determined in callback
    end
    
    if spellName and spellName ~= "" then
        -- Create basic tooltip data
        local basicLines = {{left = spellName, right = ""}}
        
        if spellDescription and spellDescription ~= "" then
            table.insert(basicLines, {left = spellDescription, right = ""})
        end
        
        BoxxyAuras.AllAuras[targetAuraInstanceID] = {
            name = spellName,
            lines = basicLines,
            scrapedVia = "BasicSpellInfo"
        }
        
        if BoxxyAuras.DEBUG then
            print(string.format("TryBasicSpellInfoScrape: Success, using spell name '%s' for instanceID=%s", 
                spellName, tostring(targetAuraInstanceID)))
        end
        return true
    end
    
    if BoxxyAuras.DEBUG then
        print(string.format("TryBasicSpellInfoScrape: Failed, no spell name found for spellId=%s", tostring(spellId)))
    end
    return false
end

-- Helper function to extract lines from the scraper tooltip
function BoxxyAuras.UIUtils.ExtractTooltipLines(targetAuraInstanceID, source)
    local tooltip = BoxxyAuras.BoxxyAurasScraperTooltip
    if not tooltip then
        if BoxxyAuras.DEBUG then
            print(string.format("ExtractTooltipLines (%s): No scraper tooltip available", source))
        end
        return nil, nil
    end

    local spellNameFromTip = _G[tooltip:GetName() .. "TextLeft1"]:GetText()
    if BoxxyAuras.DEBUG then
        print(string.format("ExtractTooltipLines (%s): Checking tooltip, spellName='%s'", source, tostring(spellNameFromTip)))
        
        -- NEW: Add debug output to see all tooltip lines
        BoxxyAuras.UIUtils.DebugTooltipContent(source, "unknown", targetAuraInstanceID)
    end

    if not spellNameFromTip or spellNameFromTip == "" then
        if BoxxyAuras.DEBUG then
            print(string.format("ExtractTooltipLines (%s): No spell name found", source))
        end
        return false
    end

    for i = 1, 30 do
        local leftLabel = _G["BoxxyAurasScraperTooltipTextLeft" .. i]
        if leftLabel and leftLabel:IsShown() and leftLabel:GetText() then
            local leftText = leftLabel:GetText()
            local rightLabel = _G["BoxxyAurasScraperTooltipTextRight" .. i]
            local rightText = (rightLabel and rightLabel:IsShown() and rightLabel:GetText()) or ""
            if not (string.find(leftText, "remaining", 1, true) or string.find(rightText, "remaining", 1, true)) then
                table.insert(tooltipLines, {left = leftText, right = rightText})
            end
        else
            break
        end
    end

    if #tooltipLines > 0 then
        BoxxyAuras.AllAuras[targetAuraInstanceID] = {
            name = spellNameFromTip,
            lines = tooltipLines,
            scrapedVia = source
        }
        
        if BoxxyAuras.DEBUG then
            print(string.format("ExtractTooltipLines (%s): Success, cached %d lines for instanceID=%s", 
                source, #tooltipLines, tostring(targetAuraInstanceID)))
        end
        return true
    end
    
    if BoxxyAuras.DEBUG then
        print(string.format("ExtractTooltipLines (%s): No valid lines found", source))
    end
    return false
end

-- This new function will perform the actual scraping from the dummy tooltip
function BoxxyAuras.UIUtils.ScrapeAndCacheFromDummy(spellId, targetAuraInstanceID)
    local scraper = _G.BoxxyAurasScraperTooltip
    local tooltipLines = {}
    local spellNameFromTip = _G.BoxxyAurasScraperTooltipTextLeft1 and _G.BoxxyAurasScraperTooltipTextLeft1:GetText()

    if BoxxyAuras.DEBUG then
        print(string.format("ScrapeAndCacheFromDummy: spellName=%s", tostring(spellNameFromTip)))
    end

    if spellNameFromTip then
        for i = 1, 30 do
            local leftLabel = _G["BoxxyAurasScraperTooltipTextLeft" .. i]
            if leftLabel and leftLabel:IsShown() and leftLabel:GetText() then
                local leftText = leftLabel:GetText()
                local rightLabel = _G["BoxxyAurasScraperTooltipTextRight" .. i]
                local rightText = (rightLabel and rightLabel:IsShown() and rightLabel:GetText()) or ""
                if not (string.find(leftText, "remaining", 1, true) or string.find(rightText, "remaining", 1, true)) then
                    table.insert(tooltipLines, {left = leftText, right = rightText})
                end
            else
                break
            end
        end
    end
    
    scraper:Hide()

    -- If the dummy scrape was successful, overwrite the placeholder.
    if spellNameFromTip and #tooltipLines > 0 then
        BoxxyAuras.AllAuras[targetAuraInstanceID] = {
            name = spellNameFromTip,
            lines = tooltipLines,
            scrapedVia = "GameTooltip"
            -- isPlaceholder is now implicitly false
        }
        
        if BoxxyAuras.DEBUG then
            print(string.format("ScrapeAndCacheFromDummy: Enhanced scrape successful, cached %d lines", #tooltipLines))
        end
    else
        if BoxxyAuras.DEBUG then
            print("ScrapeAndCacheFromDummy: Enhanced scrape failed")
        end
    end
end

-- Fallback function for scraping using spell ID when aura is expired
function BoxxyAuras.UIUtils.ScrapeAndCacheFromDummySpell(spellId, targetAuraInstanceID)
    local scraper = _G.BoxxyAurasScraperTooltip
    local tooltipLines = {}
    local spellNameFromTip = _G.BoxxyAurasScraperTooltipTextLeft1 and _G.BoxxyAurasScraperTooltipTextLeft1:GetText()

    if BoxxyAuras.DEBUG then
        print(string.format("ScrapeAndCacheFromDummySpell: spellName=%s", tostring(spellNameFromTip)))
    end

    if spellNameFromTip then
        for i = 1, 30 do
            local leftLabel = _G["BoxxyAurasScraperTooltipTextLeft" .. i]
            if leftLabel and leftLabel:IsShown() and leftLabel:GetText() then
                local leftText = leftLabel:GetText()
                local rightLabel = _G["BoxxyAurasScraperTooltipTextRight" .. i]
                local rightText = (rightLabel and rightLabel:IsShown() and rightLabel:GetText()) or ""
                if not (string.find(leftText, "remaining", 1, true) or string.find(rightText, "remaining", 1, true)) then
                    table.insert(tooltipLines, {left = leftText, right = rightText})
                end
            else
                break
            end
        end
    end
    
    scraper:Hide()

    -- If the spell ID scrape was successful, cache it
    if spellNameFromTip and #tooltipLines > 0 then
        BoxxyAuras.AllAuras[targetAuraInstanceID] = {
            name = spellNameFromTip,
            lines = tooltipLines,
            scrapedVia = "SpellID_Fallback"
            -- isPlaceholder is now implicitly false
        }
        
        if BoxxyAuras.DEBUG then
            print(string.format("ScrapeAndCacheFromDummySpell: Fallback scrape successful, cached %d lines", #tooltipLines))
        end
    else
        if BoxxyAuras.DEBUG then
            print("ScrapeAndCacheFromDummySpell: Fallback scrape failed")
        end
    end
end

-- Function to check if mouse cursor is within a frame's bounds
function BoxxyAuras.IsMouseWithinFrame(frame)
    if not frame or not frame:IsVisible() then
        return false
    end
    local mouseX, mouseY = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local left, bottom, width, height = frame:GetBoundsRect()

    if not left then
        return false
    end -- Frame might not be fully positioned yet

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



