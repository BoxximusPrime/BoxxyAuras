local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras.AllAuras = {} -- Global cache for aura info
BoxxyAuras.recentAuraEvents = {} -- Queue for recent combat log aura events {spellId, sourceGUID, timestamp}
BoxxyAuras.Frames = {} -- << ADDED: Table to store frame references

-- Configuration Table
BoxxyAuras.Config = {
    BackgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }, -- Icon Background
    BorderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },      -- Icon Border
    MainFrameBGColorNormal = { r = 0.7, g = 0.7, b = 0.7, a = 0.2 }, -- Main frame normal BG
    MainFrameBGColorHover = { r = 0.7, g = 0.7, b = 0.7, a = 0.6 }, -- Main frame hover BG
    TextHeight = 8,
    Padding = 6,           -- Internal padding within AuraIcon frame
    FramePadding = 12,      -- Padding between frame edge and icons
    IconSpacing = 0,       -- Spacing between icons

    -- Dynamic Shake Configuration
    MinShakeScale = 2,        -- Minimum visual scale of the shake effect
    MaxShakeScale = 6,        -- Maximum visual scale of the shake effect
    MinDamagePercentForShake = 0.01, -- Damage as % of max health to trigger MinShakeScale (e.g., 0.01 = 1%)
    MaxDamagePercentForShake = 0.10, -- Damage as % of max health to trigger MaxShakeScale (e.g., 0.10 = 10%)
}

BoxxyAuras.FrameHoverStates = {
    BuffFrame = false,
    DebuffFrame = false,
    CustomFrame = false,
}

local customDisplayFrame = CreateFrame("Frame", "BoxxyCustomDisplayFrame", UIParent) -- NEW Custom Frame
BoxxyAuras.customIcons = {} -- NEW Custom Icon List


-- Create the main addon frame
local mainFrame = CreateFrame("Frame", "BoxxyAurasMainFrame", UIParent) -- No template needed now
local defaultMainFrameSettings = { -- Define defaults
    x = 0,
    y = 150,
    anchor = "CENTER",
    width = 300,
    height = 100
}

-- Attach icon lists to the main addon table
BoxxyAuras.buffIcons = {}
BoxxyAuras.debuffIcons = {}
BoxxyAuras.customIcons = {} -- NEW Custom Icon List

local iconSpacing = 4 -- Keep local if only used here?

-- New Cache Tables
local trackedBuffs = {}
local trackedDebuffs = {}
local trackedCustom = {} -- NEW Cache for Custom Bar

-- New sorting function
local function SortAurasForDisplay(a, b)
    local aIsPermanent = (a.duration or 0) == 0 or a.duration == -1 -- Check 0 or -1 for permanent
    local bIsPermanent = (b.duration or 0) == 0 or b.duration == -1

    -- Rule 1: Permanent auras come before non-permanent ones
    if aIsPermanent and not bIsPermanent then return true end
    if not aIsPermanent and bIsPermanent then return false end

    -- Rule 2: If both are permanent, sort alphabetically by name
    if aIsPermanent and bIsPermanent then
        local aName = a.name or ""
        local bName = b.name or ""
        return aName < bName
    end

    -- Rule 3: If both are non-permanent, use the original start time sort
    local aStart = (a.expirationTime or 0) - (a.duration or 0)
    local bStart = (b.expirationTime or 0) - (b.duration or 0)
    if aStart == bStart then
        return a.auraInstanceID < b.auraInstanceID -- Stable tiebreaker
    end
    return aStart < bStart
end

-- Helper function to process new auras (buffs, debuffs, or custom)
-- It handles replacing expired-hovered auras or appending new ones,
-- and triggers tooltip scraping if needed.
BoxxyAuras.ProcessNewAuras = function(newAurasToAdd, trackedAuras, auraCategory)
    if not newAurasToAdd or not trackedAuras or not auraCategory then return end -- Basic validation

    for _, newAura in ipairs(newAurasToAdd) do
        local replacedExpired = false
        local replacedIndex = -1 -- Keep track if we replaced

        -- Attempt to replace an expired-hovered aura first
        for i, existingAura in ipairs(trackedAuras) do
            -- Check if existing is marked as expired due to hover AND matches the new spellId
            if existingAura.forceExpired and existingAura.spellId == newAura.spellId then
                trackedAuras[i] = newAura -- Replace the expired data in place (modifies the table passed by reference)
                replacedExpired = true
                replacedIndex = i
                break -- Stop searching for this newAura, only replace one slot
            end
        end

        -- If no suitable expired slot was found, append the new aura
        if not replacedExpired then
            table.insert(trackedAuras, newAura) -- Append (modifies the table passed by reference)
        end

        -- Trigger tooltip scrape for the newly added/updated aura if not already cached
        -- This happens whether it replaced an old one or was appended.
        local key = newAura.spellId
        if key and not BoxxyAuras.AllAuras[key] then
            local instanceIdForScrape = newAura.auraInstanceID
            local filterForScrape = "HELPFUL" -- Default filter

            if auraCategory == "Debuff" then
                filterForScrape = "HARMFUL"
            elseif auraCategory == "Custom" then
                -- For custom auras, use the original type stored when routing, fallback to HELPFUL
                filterForScrape = newAura.originalAuraType or "HELPFUL"
            end
            
            -- Ensure we have an instance ID before attempting scrape
            if instanceIdForScrape then
                BoxxyAuras.AttemptTooltipScrape(key, instanceIdForScrape, filterForScrape)
            else
                -- This might happen if the aura appeared and disappeared extremely quickly
                -- or if C_UnitAuras data lacked an instance ID, which shouldn't normally occur.
                -- BoxxyAuras.DebugLog(string.format("BoxxyAuras DEBUG: Missing instanceIdForScrape for SpellID %s (%s) in ProcessNewAuras", 
                --     tostring(key), newAura.name or "N/A"))
            end
        end
    end
    -- trackedAuras table is modified directly (by reference), no need to return it
end

-- Function to populate trackedAuras and create initial icons
local function InitializeAuras()
    -- API Check
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        BoxxyAuras.DebugLogError("C_UnitAuras Slot API not ready during Initialize!")
        return
    end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then 
        BoxxyAuras.DebugLogError("AuraIcon class not found during Initialize!")
        return
    end

    -- 1. Clear existing cache and icons
    wipe(trackedBuffs)
    wipe(trackedDebuffs)
    wipe(trackedCustom) -- NEW Cache for Custom Bar
    -- We might need a more robust way to handle existing icon frames later, but wipe is ok for init
    for _, icon in ipairs(BoxxyAuras.buffIcons) do icon.frame:Hide() end
    for _, icon in ipairs(BoxxyAuras.debuffIcons) do icon.frame:Hide() end
    for _, icon in ipairs(BoxxyAuras.customIcons) do icon.frame:Hide() end

    -- 2. Fetch current auras
    local allCurrentBuffs = {}
    local allCurrentDebuffs = {}
    local currentCustom = {} -- NEW Cache for Custom Bar
    local buffSlots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
    local debuffSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }
    -- NOTE: We fetch ALL buffs/debuffs, then route them based on name.

    for i = 2, #buffSlots do
        local slot = buffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(allCurrentBuffs, auraData) 
        end
    end
    for i = 2, #debuffSlots do
        local slot = debuffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(allCurrentDebuffs, auraData) 
        end
    end

    -- 1b. Create custom name lookup for efficient checking
    local customNamesLookup = {}
    if BoxxyAurasDB and BoxxyAurasDB.customAuraNames then
        if type(BoxxyAurasDB.customAuraNames) == "table" then
            for name, _ in pairs(BoxxyAurasDB.customAuraNames) do
                customNamesLookup[name] = true
            end
        else
            BoxxyAuras.DebugLogError("customAuraNames in DB is not a table!")
        end
    end

    -- 1c. Route fetched auras into CUSTOM or regular buff/debuff lists
    local currentBuffs = {} -- Will hold buffs NOT going to custom bar
    local currentDebuffs = {} -- Will hold debuffs NOT going to custom bar
    local currentCustom = {} -- Will hold auras MATCHING custom names (can be buff or debuff)

    for _, auraData in ipairs(allCurrentBuffs) do
        local isCustom = customNamesLookup[auraData.name]
        if isCustom then
            auraData.originalAuraType = "HELPFUL" -- << Store original type
            table.insert(currentCustom, auraData)
        else
            table.insert(currentBuffs, auraData)
        end
    end
    for _, auraData in ipairs(allCurrentDebuffs) do
        local isCustom = customNamesLookup[auraData.name]
        if isCustom then
            auraData.originalAuraType = "HARMFUL" -- << Store original type
            table.insert(currentCustom, auraData)
        else
            table.insert(currentDebuffs, auraData)
        end
    end

    -- 3. Sort fetched auras (defines initial order)
    table.sort(currentBuffs, SortAurasForDisplay)
    table.sort(currentDebuffs, SortAurasForDisplay)
    table.sort(currentCustom, SortAurasForDisplay)

    -- 4. Populate tracked cache (copy sorted data)
    for _, auraData in ipairs(currentBuffs) do table.insert(trackedBuffs, auraData) end
    for _, auraData in ipairs(currentDebuffs) do table.insert(trackedDebuffs, auraData) end
    for _, auraData in ipairs(currentCustom) do table.insert(trackedCustom, auraData) end

    -- 5. Create/Update Icon Objects based on tracked cache
    -- Get frame references first
    local buffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Buff
    local debuffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Debuff
    local customFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Custom

    -- Safety check frames
    if not buffFrame then BoxxyAuras.DebugLogError("InitializeAuras Error: Buff frame not found in BoxxyAuras.Frames!"); return end
    if not debuffFrame then BoxxyAuras.DebugLogError("InitializeAuras Error: Debuff frame not found in BoxxyAuras.Frames!"); return end
    if not customFrame then BoxxyAuras.DebugLogError("InitializeAuras Error: Custom frame not found in BoxxyAuras.Frames!"); return end

    for i, auraData in ipairs(trackedBuffs) do
        local auraIcon = BoxxyAuras.buffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(buffFrame, i, "BoxxyAurasBuffIcon") -- Use retrieved frame
            BoxxyAuras.buffIcons[i] = auraIcon
            -- Play animation ONLY when newly created
            if auraIcon and auraIcon.newAuraAnimGroup then
                auraIcon.newAuraAnimGroup:Play()
            end
        end
        auraIcon:Update(auraData, i, "HELPFUL")
        auraIcon.frame:Show() 
    end
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = BoxxyAuras.debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffFrame, i, "BoxxyAurasDebuffIcon") -- Use retrieved frame
            BoxxyAuras.debuffIcons[i] = auraIcon
            -- Play animation ONLY when newly created
            if auraIcon and auraIcon.newAuraAnimGroup then
                auraIcon.newAuraAnimGroup:Play()
            end
        end
        auraIcon:Update(auraData, i, "HARMFUL")
        auraIcon.frame:Show()
    end
    for i, auraData in ipairs(trackedCustom) do
        local auraIcon = BoxxyAuras.customIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(customFrame, i, "BoxxyAurasCustomIcon") -- Use retrieved frame
            BoxxyAuras.customIcons[i] = auraIcon
            -- Play animation ONLY when newly created
            if auraIcon and auraIcon.newAuraAnimGroup then
                auraIcon.newAuraAnimGroup:Play()
            end
        end
        auraIcon:Update(auraData, i, "CUSTOM")
        auraIcon.frame:Show()
    end

    -- 6. Hide any potentially leftover icons 
    for i = #trackedBuffs + 1, #BoxxyAuras.buffIcons do BoxxyAuras.buffIcons[i].frame:Hide() end
    for i = #trackedDebuffs + 1, #BoxxyAuras.debuffIcons do BoxxyAuras.debuffIcons[i].frame:Hide() end
    for i = #trackedCustom + 1, #BoxxyAuras.customIcons do BoxxyAuras.customIcons[i].frame:Hide() end

    -- 7. Layout the visible icons using the FrameHandler
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.LayoutAuras then
        BoxxyAuras.FrameHandler.LayoutAuras("Buff")
        BoxxyAuras.FrameHandler.LayoutAuras("Debuff")
        BoxxyAuras.FrameHandler.LayoutAuras("Custom")
    else
        BoxxyAuras.DebugLogError("InitializeAuras Error: FrameHandler.LayoutAuras not found!")
    end
end

-- Function to update displayed auras using cache comparison and stable order
BoxxyAuras.UpdateAuras = function() -- Make it part of the addon table
    -- BoxxyAuras.DebugLog("UpdateAuras: Function Start")

    -- 1a. Clean recentAuraEvents queue (remove entries older than ~0.5 seconds)
    local cleanupTime = GetTime() - 0.5
    local n = #BoxxyAuras.recentAuraEvents
    local validIndex = 1
    for i = 1, n do
        if BoxxyAuras.recentAuraEvents[i].timestamp >= cleanupTime then
            if i ~= validIndex then
                BoxxyAuras.recentAuraEvents[validIndex] = BoxxyAuras.recentAuraEvents[i]
            end
            validIndex = validIndex + 1
        end
    end
    -- Trim the end of the table
    for i = n, validIndex, -1 do
        table.remove(BoxxyAuras.recentAuraEvents)
    end

    -- API Check
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        return
    end
    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then return end

    -- 1. Fetch current auras
    local allCurrentBuffs = {} -- Temp list to hold all fetched buffs
    local allCurrentDebuffs = {} -- Temp list to hold all fetched debuffs
    local currentCustom = {} -- NEW Cache for Custom Bar
    local buffSlots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
    local debuffSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }
    -- NOTE: We fetch ALL buffs/debuffs, then route them based on name.

    for i = 2, #buffSlots do
        local slot = buffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(allCurrentBuffs, auraData) 
        end
    end
    for i = 2, #debuffSlots do
        local slot = debuffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(allCurrentDebuffs, auraData) 
        end
    end

    -- 1b. Create custom name lookup for efficient checking
    local customNamesLookup = {}
    if BoxxyAurasDB and BoxxyAurasDB.customAuraNames then
        if type(BoxxyAurasDB.customAuraNames) == "table" then
            for name, _ in pairs(BoxxyAurasDB.customAuraNames) do
                customNamesLookup[name] = true
            end
        else
            BoxxyAuras.DebugLogError("customAuraNames in DB is not a table!")
        end
    end

    -- 1c. Route fetched auras into CUSTOM or regular buff/debuff lists
    local currentBuffs = {} -- Will hold buffs NOT going to custom bar
    local currentDebuffs = {} -- Will hold debuffs NOT going to custom bar
    local currentCustom = {} -- Will hold auras MATCHING custom names (can be buff or debuff)

    for _, auraData in ipairs(allCurrentBuffs) do
        local isCustom = customNamesLookup[auraData.name]
        if isCustom then
            table.insert(currentCustom, auraData)
        else
            table.insert(currentBuffs, auraData)
        end
    end
    for _, auraData in ipairs(allCurrentDebuffs) do
        if customNamesLookup[auraData.name] then
            table.insert(currentCustom, auraData)
        else
            table.insert(currentDebuffs, auraData)
        end
    end

    -- 2. Build Current Lookup Map & Mark Tracked Auras
    local currentBuffMap = {}
    for _, auraData in ipairs(currentBuffs) do currentBuffMap[auraData.auraInstanceID] = auraData end -- MODIFIED: Use currentBuffs
    local currentDebuffMap = {}
    for _, auraData in ipairs(currentDebuffs) do currentDebuffMap[auraData.auraInstanceID] = auraData end -- MODIFIED: Use currentDebuffs
    local currentCustomMap = {}
    for _, auraData in ipairs(currentCustom) do currentCustomMap[auraData.auraInstanceID] = auraData end -- This one is already correct
    
    for _, trackedAura in ipairs(trackedBuffs) do trackedAura.seen = false end
    for _, trackedAura in ipairs(trackedDebuffs) do trackedAura.seen = false end
    for _, trackedAura in ipairs(trackedCustom) do trackedAura.seen = false end
    
    local newBuffsToAdd = {}
    local newDebuffsToAdd = {}
    local newCustomsToAdd = {}

    -- 3a. Process Current REGULAR Buffs (Mark Seen / Identify New)
    for _, currentAura in ipairs(currentBuffs) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedBuffs) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                trackedAura.spellId = currentAura.spellId
                trackedAura.originalAuraType = currentAura.originalAuraType
                -- Update ONLY volatile data & slot
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot -- Update slot in case it changes
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            table.insert(newBuffsToAdd, currentAura) -- Add the whole auraData (includes .slot)
        end
    end

    -- 3b. Process Current REGULAR Debuffs (Mark Seen / Identify New & Try to Match sourceGUID)
    for _, currentAura in ipairs(currentDebuffs) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedDebuffs) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                -- Update ONLY volatile data & slot
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot -- Update slot in case it changes
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            -- This is a new debuff according to C_UnitAuras
            -- Try to find a matching recent combat log event to get sourceGUID
            local foundEventMatch = false
            for i = #BoxxyAuras.recentAuraEvents, 1, -1 do -- Iterate backwards for potentially better timing match
                local event = BoxxyAuras.recentAuraEvents[i]
                if event.spellId == currentAura.spellId then
                    -- Match found! Assign GUID and remove event from queue
                    currentAura.sourceGUID = event.sourceGUID
                    table.remove(BoxxyAuras.recentAuraEvents, i)
                    foundEventMatch = true
                    break -- Stop searching events for this aura
                end
            end

            table.insert(newDebuffsToAdd, currentAura) -- Add aura data (potentially with sourceGUID now)
        end
    end
    -- 3c. Process Current CUSTOM Auras (Mark Seen / Identify New & Try to Match sourceGUID)
    for _, currentAura in ipairs(currentCustom) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedCustom) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                -- Update ONLY volatile data & slot
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot -- Update slot in case it changes
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            -- This is a new custom according to C_UnitAuras
            -- Try to find a matching recent combat log event to get sourceGUID
            local foundEventMatch = false
            for i = #BoxxyAuras.recentAuraEvents, 1, -1 do -- Iterate backwards for potentially better timing match
                local event = BoxxyAuras.recentAuraEvents[i]
                if event.spellId == currentAura.spellId then
                    -- Match found! Assign GUID and remove event from queue
                    currentAura.sourceGUID = event.sourceGUID
                    table.remove(BoxxyAuras.recentAuraEvents, i)
                    foundEventMatch = true
                    break -- Stop searching events for this aura
                end
            end

            table.insert(newCustomsToAdd, currentAura) -- Add aura data (potentially with sourceGUID now)
        end
    end

    -- 4. Rebuild Tracked Lists (Remove or Hold Expired/Removed)
    -- BoxxyAuras.DebugLog("UpdateAuras: Starting Step 4 (Rebuild Tracked Lists)")
    local newTrackedBuffs = {}
    for _, trackedAura in ipairs(trackedBuffs) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil -- Ensure flag is nil for active auras
            table.insert(newTrackedBuffs, trackedAura)
        else -- Not seen: Expired or Removed
            -- Use buff frame hover state here
            if BoxxyAuras.FrameHoverStates.BuffFrame then
                table.insert(newTrackedBuffs, trackedAura) -- Keep if hovering BUFF frame
                trackedAura.forceExpired = true -- Mark it as kept only due to hover
                -- Also ensure volatile data is cleared or set to indicate expiry if needed
                trackedAura.expirationTime = 0 -- Set expiration time to ensure it shows as expired
            else
                -- Aura is gone AND we are not hovering.
                -- Remove from cache ONLY if not hovering (and cache entry exists).
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    -- BoxxyAuras.DebugLog(string.format("UpdateAuras: Removing SpellID %d from cache (Not Hovering Buffs)", trackedAura.spellId))
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
            -- If not seen and not hovering, implicitly dropped from tracked list
        end
    end
    local newTrackedDebuffs = {}
    for _, trackedAura in ipairs(trackedDebuffs) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil -- Ensure flag is nil for active auras
            table.insert(newTrackedDebuffs, trackedAura)
        else -- Not seen: Expired or Removed
             -- Use debuff frame hover state here
            if BoxxyAuras.FrameHoverStates.DebuffFrame then
                table.insert(newTrackedDebuffs, trackedAura) -- Keep if hovering DEBUFF frame
                trackedAura.forceExpired = true -- Mark it as kept only due to hover
                trackedAura.expirationTime = 0 -- Set expiration time to ensure it shows as expired
            else
                 -- Aura is gone AND we are not hovering.
                 -- Remove from cache ONLY if not hovering.
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    -- BoxxyAuras.DebugLog(string.format("UpdateAuras: Removing SpellID %d from cache (Not Hovering Debuffs)", trackedAura.spellId))
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
             -- If not seen and not hovering, implicitly dropped from tracked list
        end
    end
    local newTrackedCustoms = {}
    for _, trackedAura in ipairs(trackedCustom) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil -- Ensure flag is nil for active auras
            table.insert(newTrackedCustoms, trackedAura)
        else -- Not seen: Expired or Removed
             -- Use custom frame hover state here
            if BoxxyAuras.FrameHoverStates.CustomFrame then
                table.insert(newTrackedCustoms, trackedAura) -- Keep if hovering CUSTOM frame
                trackedAura.forceExpired = true -- Mark it as kept only due to hover
                trackedAura.expirationTime = 0 -- Set expiration time to ensure it shows as expired
            else
                 -- Aura is gone AND we are not hovering.
                 -- Remove from cache ONLY if not hovering.
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    -- BoxxyAuras.DebugLog(string.format("UpdateAuras: Removing SpellID %d from cache (Not Hovering Custom)", trackedAura.spellId))
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
             -- If not seen and not hovering, implicitly dropped from tracked list
        end
    end

    -- 5. Process New Auras using the Helper Function
    -- BoxxyAuras.DebugLog("UpdateAuras: Starting Step 5 (ProcessNewAuras)")
    -- The helper modifies the newTracked* lists directly
    BoxxyAuras.ProcessNewAuras(newBuffsToAdd, newTrackedBuffs, "Buff")
    BoxxyAuras.ProcessNewAuras(newDebuffsToAdd, newTrackedDebuffs, "Debuff")
    BoxxyAuras.ProcessNewAuras(newCustomsToAdd, newTrackedCustoms, "Custom")
    -- BoxxyAuras.DebugLog("UpdateAuras: Finished Step 5 (ProcessNewAuras)")

    -- 6. Replace Module-Level Cache with the Updated Local Lists
    -- BoxxyAuras.DebugLog("UpdateAuras: Starting Step 6 (Replace Cache)")
    -- This step is crucial because ProcessNewAuras modified the *local* tables (newTrackedBuffs, etc.)
    trackedBuffs = newTrackedBuffs
    trackedDebuffs = newTrackedDebuffs
    trackedCustom = newTrackedCustoms
    -- BoxxyAuras.DebugLog("UpdateAuras: Finished Step 6 (Replace Cache)")

    -- 6a. Conditionally re-sort if NOT hovering (read state from FrameHoverStates table)
    -- BoxxyAuras.DebugLog("UpdateAuras: Starting Step 6a (Conditional Sort)")
    if not BoxxyAuras.FrameHoverStates.BuffFrame then
        table.sort(trackedBuffs, SortAurasForDisplay)
    end
    if not BoxxyAuras.FrameHoverStates.DebuffFrame then
        table.sort(trackedDebuffs, SortAurasForDisplay)
    end
    if not BoxxyAuras.FrameHoverStates.CustomFrame then
        table.sort(trackedCustom, SortAurasForDisplay)
    end
    -- BoxxyAuras.DebugLog("UpdateAuras: Finished Step 6a (Conditional Sort)")

    -- 7. Update Visual Icons based on final TRACKED cache using Icon Pools
    -- BoxxyAuras.DebugLog("UpdateAuras: Starting Step 7 (Update Visual Icons with Pools")
    local buffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Buff
    local debuffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Debuff
    local customFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Custom

    if not buffFrame then BoxxyAuras.DebugLogError("UpdateAuras Step 7: Buff frame not found!"); return end
    if not debuffFrame then BoxxyAuras.DebugLogError("UpdateAuras Step 7: Debuff frame not found!"); return end
    if not customFrame then BoxxyAuras.DebugLogError("UpdateAuras Step 7: Custom frame not found!"); return end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then BoxxyAuras.DebugLogError("UpdateAuras Step 7: AuraIcon class not found!"); return end

    -- Initialize Pools if they don't exist
    BoxxyAuras.buffIconPool = BoxxyAuras.buffIconPool or {}
    BoxxyAuras.debuffIconPool = BoxxyAuras.debuffIconPool or {}
    BoxxyAuras.customIconPool = BoxxyAuras.customIconPool or {}

    -- Helper function to get or create an icon
    local function GetOrCreateIcon(pool, activeList, parentFrame, baseNamePrefix)
        local icon = table.remove(pool) -- Try to get from pool
        if not icon then
            -- Create new one if pool is empty. Generate a unique name.
            local newIndex = (#activeList + #pool + 1)
            icon = AuraIcon.New(parentFrame, newIndex, baseNamePrefix)
            -- BoxxyAuras.DebugLog(" -> Created New Icon: " .. baseNamePrefix .. newIndex)
        end
        return icon
    end

    -- Helper function to return an icon to the pool
    local function ReturnIconToPool(pool, icon)
        if icon and icon.frame then
            icon.frame:Hide()
            table.insert(pool, icon) -- Add to pool
        end
    end

    -- --- Process Buffs ---
    local currentBuffIcons = {} -- Build a new list for this cycle
    local usedBuffIcons = {} -- Keep track of which visual icons we used/reused

    for i, auraData in ipairs(trackedBuffs) do
        local targetIcon = nil
        local playedAnimation = false

        -- Try to find an existing visual icon matching this aura instance
        local foundMatch = false
        for visualIndex, existingIcon in ipairs(BoxxyAuras.buffIcons) do
            if not usedBuffIcons[visualIndex] and existingIcon and existingIcon.auraInstanceID == auraData.auraInstanceID then
                targetIcon = existingIcon
                usedBuffIcons[visualIndex] = true -- Mark as used
                foundMatch = true
                break
            end
        end

        -- If no match found, get one from pool or create new
        if not foundMatch then
            targetIcon = GetOrCreateIcon(BoxxyAuras.buffIconPool, currentBuffIcons, buffFrame, "BoxxyAurasBuffIcon")
            -- Play animation ONLY when newly assigned from pool/creation
            if targetIcon and targetIcon.newAuraAnimGroup then
                targetIcon.newAuraAnimGroup:Play()
                playedAnimation = true
            end
        end

        -- Update and show the assigned icon
        if targetIcon then
            targetIcon:Update(auraData, i, "HELPFUL")
            targetIcon.frame:Show()
            currentBuffIcons[i] = targetIcon -- Place in the new list at correct index
            -- Optional Debug: Log which icon was used/created/animated
            -- BoxxyAuras.DebugLog(string.format(" -> Buff [%d] %s: Assigned Icon (Anim: %s)", i, auraData.name, tostring(playedAnimation)))
        else
            BoxxyAuras.DebugLogError("UpdateAuras Step 7: Failed to get/create/assign buff icon for index " .. i)
        end
    end

    -- Return unused visual icons (those not marked in usedBuffIcons) to the pool
    for visualIndex, existingIcon in ipairs(BoxxyAuras.buffIcons) do
        if not usedBuffIcons[visualIndex] then
            ReturnIconToPool(BoxxyAuras.buffIconPool, existingIcon)
        end
    end

    -- Replace the old visual list with the new one
    BoxxyAuras.buffIcons = currentBuffIcons

    -- --- Process Debuffs (Similar Logic) ---
    local currentDebuffIcons = {}
    local usedDebuffIcons = {}
    for i, auraData in ipairs(trackedDebuffs) do
        local targetIcon = nil
        local playedAnimation = false
        local foundMatch = false
        for visualIndex, existingIcon in ipairs(BoxxyAuras.debuffIcons) do
            if not usedDebuffIcons[visualIndex] and existingIcon and existingIcon.auraInstanceID == auraData.auraInstanceID then
                targetIcon = existingIcon
                usedDebuffIcons[visualIndex] = true
                foundMatch = true
                break
            end
        end
        if not foundMatch then
            targetIcon = GetOrCreateIcon(BoxxyAuras.debuffIconPool, currentDebuffIcons, debuffFrame, "BoxxyAurasDebuffIcon")
            if targetIcon and targetIcon.newAuraAnimGroup then
                targetIcon.newAuraAnimGroup:Play()
                playedAnimation = true
            end
        end
        if targetIcon then
            targetIcon:Update(auraData, i, "HARMFUL")
            targetIcon.frame:Show()
            currentDebuffIcons[i] = targetIcon
        else
            BoxxyAuras.DebugLogError("UpdateAuras Step 7: Failed to get/create/assign debuff icon for index " .. i)
        end
    end
    for visualIndex, existingIcon in ipairs(BoxxyAuras.debuffIcons) do
        if not usedDebuffIcons[visualIndex] then
            ReturnIconToPool(BoxxyAuras.debuffIconPool, existingIcon)
        end
    end
    BoxxyAuras.debuffIcons = currentDebuffIcons

    -- --- Process Custom (Similar Logic) ---
    local currentCustomIcons = {}
    local usedCustomIcons = {}
    for i, auraData in ipairs(trackedCustom) do
        local targetIcon = nil
        local playedAnimation = false
        local foundMatch = false
        for visualIndex, existingIcon in ipairs(BoxxyAuras.customIcons) do
            if not usedCustomIcons[visualIndex] and existingIcon and existingIcon.auraInstanceID == auraData.auraInstanceID then
                targetIcon = existingIcon
                usedCustomIcons[visualIndex] = true
                foundMatch = true
                break
            end
        end
        if not foundMatch then
            targetIcon = GetOrCreateIcon(BoxxyAuras.customIconPool, currentCustomIcons, customFrame, "BoxxyAurasCustomIcon")
            if targetIcon and targetIcon.newAuraAnimGroup then
                targetIcon.newAuraAnimGroup:Play()
                playedAnimation = true
            end
        end
        if targetIcon then
            targetIcon:Update(auraData, i, "CUSTOM")
            targetIcon.frame:Show()
            currentCustomIcons[i] = targetIcon
        else
            BoxxyAuras.DebugLogError("UpdateAuras Step 7: Failed to get/create/assign custom icon for index " .. i)
        end
    end
    for visualIndex, existingIcon in ipairs(BoxxyAuras.customIcons) do
        if not usedCustomIcons[visualIndex] then
            ReturnIconToPool(BoxxyAuras.customIconPool, existingIcon)
        end
    end
    BoxxyAuras.customIcons = currentCustomIcons

    -- 8. Layout the visible icons using the FrameHandler
    -- BoxxyAuras.DebugLog("UpdateAuras: Starting Step 8 (LayoutAuras Calls)") -- Renumbered Step
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.LayoutAuras then
        -- BoxxyAuras.DebugLog(" -> Calling LayoutAuras('Buff')")
        BoxxyAuras.FrameHandler.LayoutAuras("Buff")
        -- BoxxyAuras.DebugLog(" -> Calling LayoutAuras('Debuff')")
        BoxxyAuras.FrameHandler.LayoutAuras("Debuff")
        -- BoxxyAuras.DebugLog(" -> Calling LayoutAuras('Custom')")
        BoxxyAuras.FrameHandler.LayoutAuras("Custom")
        -- BoxxyAuras.DebugLog("UpdateAuras: Finished Step 9 (LayoutAuras Calls)")
    else
        BoxxyAuras.DebugLogError("UpdateAuras Error: FrameHandler.LayoutAuras not found!")
    end
end

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN") 
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    local unit = (...)
    if event == "PLAYER_LOGIN" then
        
        -- Draw and Color mainFrame backdrop/border here, AFTER UIUtils is loaded
        -- <<< ADDED Safety Checks >>>
        if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
            BoxxyAuras.UIUtils.DrawSlicedBG(mainFrame, "MainFrameHoverBG", "backdrop", 0)
            BoxxyAuras.UIUtils.DrawSlicedBG(mainFrame, "EdgedBorder", "border", 0)
        else
            BoxxyAuras.DebugLogError("UIUtils.DrawSlicedBG not available during mainFrame setup!")
        end
        
        local cfgMainBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
        local cfgMainBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.5, g = 0.5, b = 0.5, a = 1.0 }
        
        -- <<< ADDED Safety Checks >>>
        if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainBGN.r, cfgMainBGN.g, cfgMainBGN.b, cfgMainBGN.a)
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "border", cfgMainBorder.r, cfgMainBorder.g, cfgMainBorder.b, cfgMainBorder.a)
        else
             BoxxyAuras.DebugLogError("UIUtils.ColorBGSlicedFrame not available during mainFrame setup!")
        end
        
        -- Initialize Saved Variables
        if BoxxyAurasDB == nil then BoxxyAurasDB = {} end
        
        -- Default hideBlizzardAuras if needed (ensure it exists in DB)
        if BoxxyAurasDB.hideBlizzardAuras == nil then BoxxyAurasDB.hideBlizzardAuras = true end -- Default to TRUE

        -- Apply Blizzard frame visibility setting AFTER DB init
        BoxxyAuras.ApplyBlizzardAuraVisibility(BoxxyAurasDB.hideBlizzardAuras)

        -- ===> Initialize Frames using the FrameHandler <===
        if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.InitializeFrames then
            local initSuccess, initErr = pcall(BoxxyAuras.FrameHandler.InitializeFrames)
            if not initSuccess then
                BoxxyAuras.DebugLogError("Error calling FrameHandler.InitializeFrames: " .. tostring(initErr))
            end
        else
            BoxxyAuras.DebugLogError("FrameHandler.InitializeFrames not found during PLAYER_LOGIN!")
        end

        -- Schedule Initial Aura Load
        local success, err = pcall(InitializeAuras)
        if not success then
            BoxxyAuras.DebugLogError("Error in InitializeAuras (pcall): " .. tostring(err))
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName, spellSchool, amount = CombatLogGetCurrentEventInfo()

        -- Check if damage tick to player
        if destName and destName == UnitName("player") and (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE") then
            -- Use spellId AND sourceGUID to find the specific debuff instance
            if spellId and sourceGUID and amount and amount > 0 and #trackedDebuffs > 0 then
                local targetAuraInstanceID = nil
                -- Find the tracked debuff matching BOTH spellId and sourceGUID
                for _, trackedDebuff in ipairs(trackedDebuffs) do
                    if trackedDebuff and trackedDebuff.spellId == spellId and trackedDebuff.sourceGUID == sourceGUID then
                        targetAuraInstanceID = trackedDebuff.auraInstanceID
                        break -- Found the specific debuff instance
                    end
                end

                -- If we found the specific instance, find its icon and shake it
                if targetAuraInstanceID then
                    for _, auraIcon in ipairs(BoxxyAuras.debuffIcons) do
                        if auraIcon and auraIcon.auraInstanceID == targetAuraInstanceID then
                            if auraIcon.Shake then
                                -- Calculate Shake Scale
                                local shakeScale = 1.0 -- Default scale
                                local maxHealth = UnitHealthMax("player")
                                if maxHealth and maxHealth > 0 then
                                    local damagePercent = amount / maxHealth

                                    -- Get config values with defaults
                                    local minScale = BoxxyAuras.Config.MinShakeScale or 0.5
                                    local maxScale = BoxxyAuras.Config.MaxShakeScale or 2.0
                                    local minPercent = BoxxyAuras.Config.MinDamagePercentForShake or 0.01
                                    local maxPercent = BoxxyAuras.Config.MaxDamagePercentForShake or 0.10

                                    if minPercent >= maxPercent then maxPercent = minPercent + 0.01 end -- Ensure range is valid

                                    if damagePercent <= minPercent then
                                        shakeScale = minScale
                                    elseif damagePercent >= maxPercent then
                                        shakeScale = maxScale
                                    else
                                        -- Linear interpolation between min and max scale
                                        local percentInRange = (damagePercent - minPercent) / (maxPercent - minPercent)
                                        shakeScale = minScale + (maxScale - minScale) * percentInRange
                                    end
                                end

                                -- Add print before calling Shake
                                auraIcon:Shake(shakeScale) -- Pass the calculated scale
                            else
                                BoxxyAuras.DebugLogError("Shake method not found on AuraIcon instance!")
                            end
                            break -- Found the specific icon
                        end
                    end
                end
            end -- End 'if spellId and sourceGUID and amount...'

        -- Check if aura change on player
        elseif destGUID == UnitGUID("player") and 
               (subevent == "SPELL_AURA_APPLIED" or 
                subevent == "SPELL_AURA_REFRESH" or 
                subevent == "SPELL_AURA_REMOVED" or 
                subevent == "SPELL_AURA_APPLIED_DOSE" or
                subevent == "SPELL_AURA_REMOVED_DOSE") then

            if spellId and sourceGUID and (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" or subevent == "SPELL_AURA_APPLIED_DOSE") then
                local eventData = { spellId = spellId, sourceGUID = sourceGUID, timestamp = timestamp } -- Use event timestamp
                table.insert(BoxxyAuras.recentAuraEvents, eventData)
            end

            -- DEBUG: Log before calling UpdateAuras
            -- BoxxyAuras.DebugLog(string.format("Event Handler: Triggering UpdateAuras for event %s, spellId %s", tostring(subevent), tostring(spellId)))
            BoxxyAuras.UpdateAuras()
        end -- Close 'if destName... elseif destGUID...'
    end -- Close 'elseif event == "COMBAT_LOG_..."'
end)

-- Getter/Setter for tracked aura lists needed by FrameHandler
function BoxxyAuras.GetTrackedAuras(listType)
    if listType == "Buff" then return trackedBuffs end
    if listType == "Debuff" then return trackedDebuffs end
    if listType == "Custom" then return trackedCustom end
    BoxxyAuras.DebugLogError("GetTrackedAuras: Invalid listType - " .. tostring(listType))
    return {}
end

function BoxxyAuras.SetTrackedAuras(listType, newList)
    if listType == "Buff" then trackedBuffs = newList
    elseif listType == "Debuff" then trackedDebuffs = newList
    elseif listType == "Custom" then trackedCustom = newList
    else 
        BoxxyAuras.DebugLogError("SetTrackedAuras: Invalid listType - " .. tostring(listType))
    end
end

-- *** ADDED: Function to hide/show default Blizzard Buff/Debuff frames ***
function BoxxyAuras.ApplyBlizzardAuraVisibility(shouldHide)
    -- Ensure BuffFrame and DebuffFrame are valid global names
    local buffFrame = _G['BuffFrame']
    local debuffFrame = _G['DebuffFrame']
    if buffFrame and debuffFrame then
        if shouldHide then 
            buffFrame:Hide()
            debuffFrame:Hide()
        else 
            buffFrame:Show()
            debuffFrame:Show()
        end
    else
        BoxxyAuras.DebugLogError("Default Blizzard BuffFrame or DebuffFrame not found when trying to apply visibility setting.")
    end
end