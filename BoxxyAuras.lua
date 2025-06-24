local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {} -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras -- Create a convenient local alias to the global table

BoxxyAuras.Version = "1.1.0"

BoxxyAuras.AllAuras = {} -- Global cache for aura info
BoxxyAuras.recentAuraEvents = {} -- Queue for recent combat log aura events {spellId, sourceGUID, timestamp}
BoxxyAuras.Frames = {} -- << ADDED: Table to store frame references
BoxxyAuras.HoveredFrame = nil
BoxxyAuras.DEBUG = false
BoxxyAuras.lastCacheCleanup = 0 -- Track when we last cleaned the cache

-- Debounce Timer Variables
BoxxyAuras.DebounceTargetFrame = nil
BoxxyAuras.DebounceEndTime = nil

-- Previous Lock State Tracker
BoxxyAuras.WasLocked = nil

-- <<< NEW: Geometric Mouse Position Tracker >>>
BoxxyAuras.MouseInFrameGeometry = nil

local LibWindow = LibStub("LibWindow-1.1")

-- Configuration Table
BoxxyAuras.Config = {
    IconSize = 16,
    BackgroundColor = {
        r = 0.05,
        g = 0.05,
        b = 0.05,
        a = 0.9
    }, -- Icon Background
    BorderColor = {
        r = 0.3,
        g = 0.3,
        b = 0.3,
        a = 0.8
    }, -- Icon Border
    MainFrameBGColorNormal = {
        r = 0.7,
        g = 0.7,
        b = 0.7,
        a = 0.2
    }, -- Main frame normal BG
    MainFrameBGColorHover = {
        r = 0.7,
        g = 0.7,
        b = 0.7,
        a = 0.6
    }, -- Main frame hover BG
    TextHeight = 8,
    Padding = 6, -- Internal padding within AuraIcon frame
    FramePadding = 12, -- Padding between frame edge and icons
    IconSpacing = 0, -- Spacing between icons

    -- Dynamic Shake Configuration
    MinShakeScale = 2, -- Minimum visual scale of the shake effect
    MaxShakeScale = 6, -- Maximum visual scale of the shake effect
    MinDamagePercentForShake = 0.01, -- Damage as % of max health to trigger MinShakeScale (e.g., 0.01 = 1%)
    MaxDamagePercentForShake = 0.10 -- Damage as % of max health to trigger MaxShakeScale (e.g., 0.10 = 10%)
}

BoxxyAuras.FrameHoverStates = {
    BuffFrame = false,
    DebuffFrame = false,
    CustomFrame = false
}

-- <<< ADDED: Table to store leave debounce timers >>>
BoxxyAuras.FrameLeaveTimers = {}

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
    if aIsPermanent and not bIsPermanent then
        return true
    end
    if not aIsPermanent and bIsPermanent then
        return false
    end

    -- Rule 2: If both are permanent, sort alphabetically by name
    if aIsPermanent and bIsPermanent then
        local aName = a.name or ""
        local bName = b.name or ""
        return aName < bName
    end

    -- Rule 3: If both are non-permanent, use the original start time sort
    local aTrackTime = a.originalTrackTime or 0
    local bTrackTime = b.originalTrackTime or 0
    if aTrackTime == bTrackTime then
        -- Use auraInstanceID as a stable tiebreaker if track times are identical (unlikely but possible)
        return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
    end
    return aTrackTime < bTrackTime
end

-- Helper function to process new auras (buffs, debuffs, or custom)
BoxxyAuras.ProcessNewAuras = function(newAurasToAdd, trackedAuras, auraCategory)
    if not newAurasToAdd or not trackedAuras or not auraCategory then
        return
    end -- Basic validation

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
        local key = newAura.auraInstanceID
        if key and not BoxxyAuras.AllAuras[key] then
            local instanceIdForScrape = newAura.auraInstanceID
            local spellIdForScrape = newAura.spellId
            local filterForScrape = "HELPFUL" -- Default filter

            if auraCategory == "Debuff" then
                filterForScrape = "HARMFUL"
            elseif auraCategory == "Custom" then
                filterForScrape = newAura.originalAuraType or "HELPFUL"
            end

            -- Schedule the scrape to happen immediately while the aura is still active
            BoxxyAuras.AttemptTooltipScrape(spellIdForScrape, instanceIdForScrape, filterForScrape)
        end
    end
end

-- Function to define the complete default profile settings
function BoxxyAuras:GetDefaultProfileSettings()
    -- Calculate default dimensions based on Config
    local defaultPadding = BoxxyAuras.Config.Padding or 6
    local defaultIconSize_ForCalc = 24
    local defaultTextHeight = BoxxyAuras.Config.TextHeight or 8
    local defaultIconH = defaultIconSize_ForCalc + defaultTextHeight + (defaultPadding * 2)
    local defaultFramePadding = BoxxyAuras.Config.FramePadding or 6
    local defaultMinHeight = defaultFramePadding + defaultIconH + defaultFramePadding
    local defaultIconsWide_Reset = 6
    local defaultWidth = 200 -- Fallback width
    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.CalculateFrameWidth then
        defaultWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(defaultIconsWide_Reset, defaultIconSize_ForCalc) or
                           defaultWidth
    end

    return {
        lockFrames = false,
        hideBlizzardAuras = true,
        optionsScale = 1.0,
        customAuraNames = {},
        buffFrameSettings = {
            x = 0,
            y = 100,
            anchor = "CENTER",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            buffTextAlign = "CENTER",
            iconSize = 24,
            textSize = 8,
            borderSize = 1,
            width = defaultWidth
        },
        debuffFrameSettings = {
            x = 0,
            y = 200,
            anchor = "CENTER",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            debuffTextAlign = "CENTER",
            iconSize = 24,
            textSize = 8,
            borderSize = 1,
            width = defaultWidth
        },
        customFrameSettings = {
            x = 0,
            y = 300,
            anchor = "CENTER",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            customTextAlign = "CENTER",
            iconSize = 24,
            textSize = 8,
            borderSize = 1,
            width = defaultWidth
        }
    }
end

-- <<< NEW Helper: Get Character Key >>>
function BoxxyAuras:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if name and realm then
        return name .. "-" .. realm
    else
        -- Fallback or error handling if name/realm aren't available
        -- This might happen very early in login
        return "UnknownCharacter"
    end
end

-- <<< NEW Helper: Get Active Profile Name for Current Character >>>
function BoxxyAuras:GetActiveProfileName()
    local charKey = self:GetCharacterKey()
    -- Ensure the map exists
    if not BoxxyAurasDB.characterProfileMap then
        BoxxyAurasDB.characterProfileMap = {}
    end
    return BoxxyAurasDB.characterProfileMap[charKey] or "Default"
end

-- Helper to get the active profile's settings table
function BoxxyAuras:GetCurrentProfileSettings()
    if not BoxxyAurasDB then
        BoxxyAurasDB = {}
    end
    if not BoxxyAurasDB.profiles then
        BoxxyAurasDB.profiles = {}
    end
    -- <<< ADDED: Ensure character map exists >>>
    if not BoxxyAurasDB.characterProfileMap then
        BoxxyAurasDB.characterProfileMap = {}
    end

    -- <<< MODIFIED: Get key based on current character >>>
    local activeKey = self:GetActiveProfileName()

    -- Ensure the profile itself exists (or create from defaults)
    if not BoxxyAurasDB.profiles[activeKey] then
        -- BoxxyAuras.DebugLog(string.format("Profile '%s' not found for character, creating from defaults.", activeKey))
        BoxxyAurasDB.profiles[activeKey] = CopyTable(self:GetDefaultProfileSettings())
    end

    local profile = BoxxyAurasDB.profiles[activeKey]

    -- <<< Ensure nested tables and default values exist (existing logic) >>>
    profile.buffFrameSettings = profile.buffFrameSettings or {}
    profile.debuffFrameSettings = profile.debuffFrameSettings or {}
    profile.customFrameSettings = profile.customFrameSettings or {}
    profile.customAuraNames = profile.customAuraNames or {}

    if profile.lockFrames == nil then
        profile.lockFrames = false
    end
    if profile.optionsScale == nil then
        profile.optionsScale = 1.0
    end
    if profile.hideBlizzardAuras == nil then
        profile.hideBlizzardAuras = true
    end

    if profile.buffFrameSettings.buffTextAlign == nil then
        profile.buffFrameSettings.buffTextAlign = "CENTER"
    end
    if profile.debuffFrameSettings.debuffTextAlign == nil then
        profile.debuffFrameSettings.debuffTextAlign = "CENTER"
    end
    if profile.customFrameSettings.customTextAlign == nil then
        profile.customFrameSettings.customTextAlign = "CENTER"
    end
    if profile.buffFrameSettings.iconSize == nil then
        profile.buffFrameSettings.iconSize = 24
    end
    if profile.debuffFrameSettings.iconSize == nil then
        profile.debuffFrameSettings.iconSize = 24
    end
    if profile.customFrameSettings.iconSize == nil then
        profile.customFrameSettings.iconSize = 24
    end
    if profile.buffFrameSettings.textSize == nil then
        profile.buffFrameSettings.textSize = 8
    end
    if profile.debuffFrameSettings.textSize == nil then
        profile.debuffFrameSettings.textSize = 8
    end
    if profile.customFrameSettings.textSize == nil then
        profile.customFrameSettings.textSize = 8
    end
    
    -- Ensure borderSize exists for all frame types
    if profile.buffFrameSettings.borderSize == nil then
        profile.buffFrameSettings.borderSize = 1
    end
    if profile.debuffFrameSettings.borderSize == nil then
        profile.debuffFrameSettings.borderSize = 1
    end
    if profile.customFrameSettings.borderSize == nil then
        profile.customFrameSettings.borderSize = 1
    end

    -- <<< ADDED: Ensure numIconsWide exists >>>
    if profile.buffFrameSettings.numIconsWide == nil then
        profile.buffFrameSettings.numIconsWide = 6
    end
    if profile.debuffFrameSettings.numIconsWide == nil then
        profile.debuffFrameSettings.numIconsWide = 6
    end
    if profile.customFrameSettings.numIconsWide == nil then
        profile.customFrameSettings.numIconsWide = 6
    end

    return profile
end

-- Function to populate trackedAuras and create initial icons
local function InitializeAuras()
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        return
    end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then
        return
    end

    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    -- Initialize collections
    if not BoxxyAuras.auraTracking then
        BoxxyAuras.auraTracking = {}
    end

    if not BoxxyAuras.iconArrays then
        BoxxyAuras.iconArrays = {}
    end

    -- Clear all existing auras and hide icons
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        BoxxyAuras.auraTracking[frameType] = {}

        if BoxxyAuras.iconArrays[frameType] then
            for _, icon in ipairs(BoxxyAuras.iconArrays[frameType]) do
                if icon and icon.frame then
                    icon.frame:Hide()
                end
            end
        end

        BoxxyAuras.iconArrays[frameType] = {}
    end

    -- Get all current auras
    local allCurrentBuffs = {}
    local allCurrentDebuffs = {}
    local buffSlots = {C_UnitAuras.GetAuraSlots("player", "HELPFUL")}
    local debuffSlots = {C_UnitAuras.GetAuraSlots("player", "HARMFUL")}

    for i = 2, #buffSlots do
        local slot = buffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then
            auraData.slot = slot
            auraData.auraType = "HELPFUL"
            table.insert(allCurrentBuffs, auraData)
        end
    end

    for i = 2, #debuffSlots do
        local slot = debuffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then
            auraData.slot = slot
            auraData.auraType = "HARMFUL"
            table.insert(allCurrentDebuffs, auraData)
        end
    end

    -- Get custom aura assignments (case-insensitive)
    local customNamesLookup = {}
    local profileCustomAuras = currentSettings.customAuraNames
    if profileCustomAuras and type(profileCustomAuras) == "table" then
        for name, _ in pairs(profileCustomAuras) do
            -- Store lowercase version for case-insensitive matching
            customNamesLookup[string.lower(name)] = true
        end
    end

    -- Create frame-specific aura lists
    local aurasByFrame = {}

    -- Initialize collection for each frame type
    for frameType, _ in pairs(BoxxyAuras.Frames) do
        aurasByFrame[frameType] = {}
    end

    -- Assign auras to the appropriate frame types
    for _, auraData in ipairs(allCurrentBuffs) do
        local isCustom = customNamesLookup[string.lower(auraData.name or "")]
        if isCustom and aurasByFrame["Custom"] then
            auraData.originalAuraType = "HELPFUL"
            table.insert(aurasByFrame["Custom"], auraData)
        elseif aurasByFrame["Buff"] then
            table.insert(aurasByFrame["Buff"], auraData)
        end
    end

    for _, auraData in ipairs(allCurrentDebuffs) do
        local isCustom = customNamesLookup[string.lower(auraData.name or "")]
        if isCustom and aurasByFrame["Custom"] then
            auraData.originalAuraType = "HARMFUL"
            table.insert(aurasByFrame["Custom"], auraData)
        elseif aurasByFrame["Debuff"] then
            table.insert(aurasByFrame["Debuff"], auraData)
        end
    end

    -- Sort and assign auras to tracking lists
    for frameType, auras in pairs(aurasByFrame) do
        table.sort(auras, SortAurasForDisplay)
        BoxxyAuras.auraTracking[frameType] = auras
    end

    -- Create initial icons for each frame
    for frameType, frame in pairs(BoxxyAuras.Frames) do
        local auras = BoxxyAuras.auraTracking[frameType] or {}
        BoxxyAuras.iconArrays[frameType] = BoxxyAuras.iconArrays[frameType] or {}

        -- Determine aura filter for this frame type
        local auraFilter = "HELPFUL"
        if frameType == "Debuff" then
            auraFilter = "HARMFUL"
        elseif frameType == "Custom" then
            auraFilter = "CUSTOM"
        end

        -- Create icons for each aura
        for i, auraData in ipairs(auras) do
            local icon = BoxxyAuras.iconArrays[frameType][i]
            if not icon then
                local baseNamePrefix = "BoxxyAuras" .. frameType .. "Icon"
                icon = AuraIcon.New(frame, i, baseNamePrefix)
                BoxxyAuras.iconArrays[frameType][i] = icon
                if icon and icon.newAuraAnimGroup then
                    icon.newAuraAnimGroup:Play()
                end
            end

            icon:Update(auraData, i, auraFilter)
            icon.frame:Show()
        end
    end

    -- Update layout in all frames
    BoxxyAuras.FrameHandler.UpdateAllFramesAuras()
end

-- Function to update displayed auras using cache comparison and stable order
BoxxyAuras.UpdateAuras = function(forceRefresh)

    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    -- Clean up recent aura events older than 0.5 seconds
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
    for i = n, validIndex, -1 do
        table.remove(BoxxyAuras.recentAuraEvents)
    end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras ERROR: AuraIcon class not found in UpdateAuras")
        end
        return
    end

    -- If we're doing a forced refresh, completely clear and rebuild all auras
    if forceRefresh then
        -- Initialize auras from scratch
        InitializeAuras()

        -- Update all frames after initialization
        BoxxyAuras.FrameHandler.UpdateAllFramesAuras()

        -- Apply initial lock state after everything is initialized
        local finalSettings = BoxxyAuras:GetCurrentProfileSettings() -- Get settings again to be sure
        if finalSettings.lockFrames then
            -- BoxxyAuras.FrameHandler.ApplyLockState(true) -- Apply immediately (OLD)
            -- Apply lock state after a short delay to allow UI to settle
            C_Timer.After(0.1, function()
                if BoxxyAuras:GetCurrentProfileSettings().lockFrames then -- Re-check in case user unlocked super fast
                    BoxxyAuras.FrameHandler.ApplyLockState(true)
                    if BoxxyAuras.DEBUG then
                        print("Delayed ApplyLockState(true) executed after login.")
                    end
                end
            end)
        end

        return
    end

    -- Initialize necessary collections if they don't exist
    if not BoxxyAuras.auraTracking then
        BoxxyAuras.auraTracking = {}
    end
    if not BoxxyAuras.iconArrays then
        BoxxyAuras.iconArrays = {}
    end
    if not BoxxyAuras.iconPools then
        BoxxyAuras.iconPools = {}
    end

    -- Make sure our frame-specific collections exist for all registered frames
    for frameType, frame in pairs(BoxxyAuras.Frames) do
        -- Initialize tracking lists for this frame type if they don't exist
        if not BoxxyAuras.auraTracking[frameType] then
            BoxxyAuras.auraTracking[frameType] = {}
        end

        -- Initialize icon arrays for this frame type if they don't exist
        if not BoxxyAuras.iconArrays[frameType] then
            BoxxyAuras.iconArrays[frameType] = {}
        end

        -- Initialize icon pools for this frame type if they don't exist
        if not BoxxyAuras.iconPools[frameType] then
            BoxxyAuras.iconPools[frameType] = {}
        end
    end

    -- Get all current auras
    local allCurrentBuffs = {}
    local allCurrentDebuffs = {}
    
    -- Check if demo mode is active
    if BoxxyAuras.Options and BoxxyAuras.Options.demoModeActive and BoxxyAuras.demoAuras then
        -- Use demo auras instead of real auras
        if BoxxyAuras.demoAuras.Buff then
            for _, demoAura in ipairs(BoxxyAuras.demoAuras.Buff) do
                local auraData = {
                    name = demoAura.name,
                    icon = demoAura.icon,
                    duration = demoAura.duration,
                    expirationTime = demoAura.expirationTime,
                    applications = demoAura.applications,
                    spellId = demoAura.spellId,
                    auraInstanceID = demoAura.auraInstanceID,
                    slot = 0, -- Demo auras don't have real slots
                    auraType = "HELPFUL"
                }
                table.insert(allCurrentBuffs, auraData)
            end
        end
        
        if BoxxyAuras.demoAuras.Debuff then
            for _, demoAura in ipairs(BoxxyAuras.demoAuras.Debuff) do
                local auraData = {
                    name = demoAura.name,
                    icon = demoAura.icon,
                    duration = demoAura.duration,
                    expirationTime = demoAura.expirationTime,
                    applications = demoAura.applications,
                    spellId = demoAura.spellId,
                    auraInstanceID = demoAura.auraInstanceID,
                    slot = 0, -- Demo auras don't have real slots
                    auraType = "HARMFUL",
                    dispelName = demoAura.dispelName
                }
                table.insert(allCurrentDebuffs, auraData)
            end
        end
    else
        -- Use real auras from the game API
        local buffSlots = {C_UnitAuras.GetAuraSlots("player", "HELPFUL")}
        local debuffSlots = {C_UnitAuras.GetAuraSlots("player", "HARMFUL")}

        for i = 2, #buffSlots do
            local slot = buffSlots[i]
            local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
            if auraData then
                auraData.slot = slot
                auraData.auraType = "HELPFUL"
                table.insert(allCurrentBuffs, auraData)
            end
        end
        for i = 2, #debuffSlots do
            local slot = debuffSlots[i]
            local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
            if auraData then
                auraData.slot = slot
                auraData.auraType = "HARMFUL"
                table.insert(allCurrentDebuffs, auraData)
            end
        end
    end

    -- Get custom aura assignments (case-insensitive)
    local customNamesLookup = {}
    local profileCustomAuras = currentSettings.customAuraNames
    if profileCustomAuras and type(profileCustomAuras) == "table" then
        for name, _ in pairs(profileCustomAuras) do
            -- Store lowercase version for case-insensitive matching
            customNamesLookup[string.lower(name)] = true
        end
    end

    -- Create frame-specific aura lists
    local aurasByFrame = {}

    -- Initialize collection for each frame type
    for frameType, _ in pairs(BoxxyAuras.Frames) do
        aurasByFrame[frameType] = {}
    end

    -- Assign auras to the appropriate frame types
    for _, auraData in ipairs(allCurrentBuffs) do
        local isCustom = customNamesLookup[string.lower(auraData.name or "")]
        if isCustom and aurasByFrame["Custom"] then
            auraData.originalAuraType = "HELPFUL"
            table.insert(aurasByFrame["Custom"], auraData)
        elseif aurasByFrame["Buff"] then
            table.insert(aurasByFrame["Buff"], auraData)
        end
    end

    for _, auraData in ipairs(allCurrentDebuffs) do
        local isCustom = customNamesLookup[string.lower(auraData.name or "")]
        if isCustom and aurasByFrame["Custom"] then
            auraData.originalAuraType = "HARMFUL"
            table.insert(aurasByFrame["Custom"], auraData)
        elseif aurasByFrame["Debuff"] then
            table.insert(aurasByFrame["Debuff"], auraData)
        end
    end

    -- Add demo custom auras if demo mode is active
    if BoxxyAuras.Options and BoxxyAuras.Options.demoModeActive and BoxxyAuras.demoAuras and BoxxyAuras.demoAuras.Custom then
        for _, demoAura in ipairs(BoxxyAuras.demoAuras.Custom) do
            local auraData = {
                name = demoAura.name,
                icon = demoAura.icon,
                duration = demoAura.duration,
                expirationTime = demoAura.expirationTime,
                applications = demoAura.applications,
                spellId = demoAura.spellId,
                auraInstanceID = demoAura.auraInstanceID,
                slot = 0, -- Demo auras don't have real slots
                auraType = "HELPFUL", -- Default for custom demo auras
                originalAuraType = "HELPFUL"
            }
            if aurasByFrame["Custom"] then
                table.insert(aurasByFrame["Custom"], auraData)
            end
        end
    end

    -- Process auras for each frame type
    for frameType, frame in pairs(BoxxyAuras.Frames) do
        local trackedAuras = BoxxyAuras.auraTracking[frameType] or {}
        local currentAuras = aurasByFrame[frameType] or {}

        -- Mark all current tracked auras as unseen
        for _, trackedAura in ipairs(trackedAuras) do
            trackedAura.seen = false
        end

        -- Identify new auras and update existing ones
        local newAurasToAdd = {}

        for _, currentAura in ipairs(currentAuras) do
            local foundInTracked = false
            for _, trackedAura in ipairs(trackedAuras) do
                if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                    -- Update existing aura data - **DO NOT update originalTrackTime**
                    trackedAura.spellId = currentAura.spellId
                    trackedAura.originalAuraType = currentAura.originalAuraType or currentAura.auraType
                    trackedAura.expirationTime = currentAura.expirationTime
                    trackedAura.duration = currentAura.duration
                    trackedAura.slot = currentAura.slot
                    trackedAura.seen = true
                    -- trackedAura.originalTrackTime remains untouched if it exists
                    foundInTracked = true
                    break
                end
            end

            if not foundInTracked then
                -- Process source GUID from recent events for all aura types
                for i = #BoxxyAuras.recentAuraEvents, 1, -1 do
                    local event = BoxxyAuras.recentAuraEvents[i]
                    if event.spellId == currentAura.spellId then
                        currentAura.sourceGUID = event.sourceGUID
                        currentAura.sourceName = event.sourceName  -- Also store the name for debugging
                        if BoxxyAuras.DEBUG then
                            print(string.format("ProcessNewAuras: Assigned sourceGUID=%s (%s) to %s aura spellId=%s", 
                                tostring(event.sourceGUID), tostring(event.sourceName), frameType, tostring(event.spellId)))
                        end
                        table.remove(BoxxyAuras.recentAuraEvents, i)
                        break
                    end
                end

                -- **Add originalTrackTime when adding a new aura**
                currentAura.originalTrackTime = GetTime()
                table.insert(newAurasToAdd, currentAura)
            end
        end

        -- Handle expired auras
        local newTrackedAuras = {}
        for _, trackedAura in ipairs(trackedAuras) do
            if trackedAura.seen then
                trackedAura.forceExpired = nil
                table.insert(newTrackedAuras, trackedAura)
            else
                -- Aura has expired THIS TICK. We should have already scraped its tooltip when it was active.
                local instanceIdForScrape = trackedAura.auraInstanceID

                -- Check if the current frame is the one being hovered (logically)
                if frame == BoxxyAuras.HoveredFrame then -- <<< Use Logical Hover Check >>>
                    -- Keep the aura, mark as forceExpired
                    trackedAura.forceExpired = true
                    trackedAura.expirationTime = 0 -- Ensure it's treated as expired
                    table.insert(newTrackedAuras, trackedAura)
                else
                    -- Not hovering this frame, remove the aura from tracking
                    -- Note: We keep the cached tooltip data in BoxxyAuras.AllAuras
                    -- in case we need to show this aura again later
                    -- Don't add it to newTrackedAuras
                end
            end
        end

        -- Process new auras for this frame
        if frameType == "Buff" then
            BoxxyAuras.ProcessNewAuras(newAurasToAdd, newTrackedAuras, "Buff")
        elseif frameType == "Debuff" then
            BoxxyAuras.ProcessNewAuras(newAurasToAdd, newTrackedAuras, "Debuff")
        elseif frameType == "Custom" then
            BoxxyAuras.ProcessNewAuras(newAurasToAdd, newTrackedAuras, "Custom")
        else
            -- For any other frame types, we'll use a generic approach
            BoxxyAuras.ProcessNewAuras(newAurasToAdd, newTrackedAuras, frameType)
        end

        -- Update tracking list for this frame
        BoxxyAuras.auraTracking[frameType] = newTrackedAuras

        -- Sort auras if not hovering the current frame
        if frame ~= BoxxyAuras.HoveredFrame then
            table.sort(BoxxyAuras.auraTracking[frameType], SortAurasForDisplay)
        end

        -- Update icons for this frame type
        UpdateIconsForFrame(frameType, frame, BoxxyAuras.auraTracking[frameType])
    end

    -- Update layout in all frames
    BoxxyAuras.FrameHandler.UpdateAllFramesAuras()
end

-- Function to update icons for a specific frame
function UpdateIconsForFrame(frameType, frame, auras)
    if not frame or not auras then
        return
    end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras ERROR: AuraIcon class not found in UpdateIconsForFrame")
        end
        return
    end

    -- Ensure icon pool and array exist
    BoxxyAuras.iconPools[frameType] = BoxxyAuras.iconPools[frameType] or {}
    BoxxyAuras.iconArrays[frameType] = BoxxyAuras.iconArrays[frameType] or {}

    local iconPool = BoxxyAuras.iconPools[frameType]
    local iconArray = BoxxyAuras.iconArrays[frameType]

    -- Determine the aura filter type based on frame type
    local auraFilter = "HELPFUL"
    if frameType == "Debuff" then
        auraFilter = "HARMFUL"
    elseif frameType == "Custom" then
        auraFilter = "CUSTOM"
    end

    -- Helper functions
    local function GetOrCreateIcon(pool, index, parentFrame, baseNamePrefix)
        local icon = table.remove(pool)
        if not icon then
            local uniqueName = baseNamePrefix .. index
            icon = AuraIcon.New(parentFrame, index, baseNamePrefix)
        end
        return icon
    end

    local function ReturnIconToPool(pool, icon)
        if icon and icon.frame then
            icon.frame:Hide()
            table.insert(pool, icon)
        end
    end

    -- Update icons
    local currentIcons = {}
    local usedIcons = {}

    for i, auraData in ipairs(auras) do
        local targetIcon = nil
        local foundMatch = false

        -- Try to find an existing icon that matches this aura
        for visualIndex, existingIcon in ipairs(iconArray) do
            if not usedIcons[visualIndex] and existingIcon and existingIcon.auraInstanceID == auraData.auraInstanceID then
                targetIcon = existingIcon
                usedIcons[visualIndex] = true
                foundMatch = true
                break
            end
        end

        -- Create a new icon if needed
        if not foundMatch then
            local baseNamePrefix = "BoxxyAuras" .. frameType .. "Icon"
            targetIcon = GetOrCreateIcon(iconPool, i, frame, baseNamePrefix)
            if targetIcon and targetIcon.newAuraAnimGroup then
                targetIcon.newAuraAnimGroup:Play()
            end
        end

        -- Update the icon with aura data
        if targetIcon then
            targetIcon:Update(auraData, i, auraFilter)
            targetIcon.frame:Show()
            currentIcons[i] = targetIcon
        end
    end

    -- Return unused icons to the pool
    for visualIndex, existingIcon in ipairs(iconArray) do
        if not usedIcons[visualIndex] then
            ReturnIconToPool(iconPool, existingIcon)
        end
    end

    -- Update the icon array for this frame
    BoxxyAuras.iconArrays[frameType] = currentIcons
end

-- We need to update GetTrackedAuras to use the new auraTracking table
function BoxxyAuras.GetTrackedAuras(frameType)
    if not BoxxyAuras.auraTracking then
        BoxxyAuras.auraTracking = {}
    end

    if not BoxxyAuras.auraTracking[frameType] then
        BoxxyAuras.auraTracking[frameType] = {}
    end

    return BoxxyAuras.auraTracking[frameType]
end

-- Update SetTrackedAuras to use the new auraTracking table
function BoxxyAuras.SetTrackedAuras(frameType, newList)
    if not BoxxyAuras.auraTracking then
        BoxxyAuras.auraTracking = {}
    end

    BoxxyAuras.auraTracking[frameType] = newList
end

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    local unit = (...)
    if event == "PLAYER_LOGIN" then

        if BoxxyAurasDB == nil then
            BoxxyAurasDB = {}
        end
        if BoxxyAurasDB.profiles == nil then
            BoxxyAurasDB.profiles = {}
        end
        if BoxxyAurasDB.activeProfile == nil then
            BoxxyAurasDB.activeProfile = "Default"
        end
        if BoxxyAuras.Frames == nil then
            BoxxyAuras.Frames = {}
        end

        local framesToCreate = {"Buff", "Debuff", "Custom"}
        for _, frameType in ipairs(framesToCreate) do
            BoxxyAuras.Frames[frameType] = BoxxyAuras.FrameHandler.SetupDisplayFrame(frameType)
        end

        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        BoxxyAuras.ApplyBlizzardAuraVisibility(currentSettings.hideBlizzardAuras)

        if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.InitializeFrames then
            local initSuccess, initErr = pcall(BoxxyAuras.FrameHandler.InitializeFrames)
            if not initSuccess then
            end
        end

        local success, err = pcall(InitializeAuras)
        if not success then
            BoxxyAuras.DebugLogError("Error in InitializeAuras (pcall): " .. tostring(err))
        end

        -- Force a full update on login to ensure all auras get originalTrackTime
        BoxxyAuras.UpdateAuras(true)

        -- Apply initial lock state after everything is initialized
        local finalSettings = BoxxyAuras:GetCurrentProfileSettings() -- Get settings again to be sure
        if finalSettings.lockFrames then
            -- BoxxyAuras.FrameHandler.ApplyLockState(true) -- Apply immediately (OLD)
            -- Apply lock state after a short delay to allow UI to settle
            C_Timer.After(0.1, function()
                if BoxxyAuras:GetCurrentProfileSettings().lockFrames then -- Re-check in case user unlocked super fast
                    BoxxyAuras.FrameHandler.ApplyLockState(true)
                    if BoxxyAuras.DEBUG then
                        print("Delayed ApplyLockState(true) executed after login.")
                    end
                end
            end)
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName,
            spellSchool, amount = CombatLogGetCurrentEventInfo()

        -- Handle Aura Application Events to capture source GUID
        if destName and destName == UnitName("player") and 
            (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH") then
            if spellId and sourceGUID then
                -- Store this for quick lookup when processing new auras
                table.insert(BoxxyAuras.recentAuraEvents, {
                    spellId = spellId,
                    sourceGUID = sourceGUID,
                    sourceName = sourceName,
                    timestamp = GetTime()
                })
                
                if BoxxyAuras.DEBUG then
                    print(string.format("Combat Log: %s applied spellId=%s from sourceGUID=%s (%s)", 
                        subevent, tostring(spellId), tostring(sourceGUID), tostring(sourceName)))
                end
            end
        end

        -- Handle Damage Events for Shake Effect
        if destName and destName == UnitName("player") and
            (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE") then
            -- Use correct tracking table and check it exists
            if spellId and sourceGUID and amount and amount > 0 and BoxxyAuras.auraTracking and
                BoxxyAuras.auraTracking["Debuff"] and #BoxxyAuras.auraTracking["Debuff"] > 0 then
                local targetAuraInstanceID = nil
                -- Iterate over the correct tracking table
                for _, trackedDebuff in ipairs(BoxxyAuras.auraTracking["Debuff"]) do
                    -- Match based on spellId AND sourceGUID if available
                    if trackedDebuff and trackedDebuff.spellId == spellId then
                        if trackedDebuff.sourceGUID and trackedDebuff.sourceGUID == sourceGUID then
                            targetAuraInstanceID = trackedDebuff.auraInstanceID
                            break
                            -- Fallback: if sourceGUID isn't stored on the trackedDebuff yet, match just by spellId (less accurate)
                        elseif not trackedDebuff.sourceGUID then
                            targetAuraInstanceID = trackedDebuff.auraInstanceID
                            -- Don't break here, keep looking for a sourceGUID match if possible
                        end
                    end
                end

                if targetAuraInstanceID then
                    -- Iterate over the correct icon array
                    if BoxxyAuras.iconArrays and BoxxyAuras.iconArrays["Debuff"] then
                        for _, auraIcon in ipairs(BoxxyAuras.iconArrays["Debuff"]) do
                            if auraIcon and auraIcon.auraInstanceID == targetAuraInstanceID then
                                if auraIcon.Shake then
                                    local shakeScale = 1.0
                                    local maxHealth = UnitHealthMax("player")
                                    if maxHealth and maxHealth > 0 then
                                        local damagePercent = amount / maxHealth
                                        local minScale = BoxxyAuras.Config.MinShakeScale or 0.5
                                        local maxScale = BoxxyAuras.Config.MaxShakeScale or 2.0
                                        local minPercent = BoxxyAuras.Config.MinDamagePercentForShake or 0.01
                                        local maxPercent = BoxxyAuras.Config.MaxDamagePercentForShake or 0.10
                                        if minPercent >= maxPercent then
                                            maxPercent = minPercent + 0.01
                                        end
                                        if damagePercent <= minPercent then
                                            shakeScale = minScale
                                        elseif damagePercent >= maxPercent then
                                            shakeScale = maxScale
                                        else
                                            local percentInRange =
                                                (damagePercent - minPercent) / (maxPercent - minPercent)
                                            shakeScale = minScale + (maxScale - minScale) * percentInRange
                                        end
                                    end
                                    auraIcon:Shake(shakeScale)
                                end
                                break
                            end
                        end
                    end
                end
            end
        end -- end of COMBAT_LOG damage handling

    elseif event == "UNIT_AURA" then
        local unitId = ...
        if unitId == "player" then
            BoxxyAuras.UpdateAuras()
        end
    end
end)

function BoxxyAuras.ApplyBlizzardAuraVisibility(shouldHide)
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
        -- BoxxyAuras.DebugLogError("Default Blizzard BuffFrame or DebuffFrame not found when trying to apply visibility setting.")
    end
end

-- Profile Management Functions

-- Switch to a different profile
function BoxxyAuras:SwitchToProfile(profileName)
    if not profileName or profileName == "" then
        print("|cffFF0000BoxxyAuras:|r Invalid profile name.")
        return false
    end
    
    if not BoxxyAurasDB then
        print("|cffFF0000BoxxyAuras:|r Database not initialized.")
        return false
    end
    
    if not BoxxyAurasDB.profiles then
        BoxxyAurasDB.profiles = {}
    end
    
    -- Create profile if it doesn't exist
    if not BoxxyAurasDB.profiles[profileName] then
        BoxxyAurasDB.profiles[profileName] = self:GetDefaultProfileSettings()
        print("|cff00FF00BoxxyAuras:|r Created new profile '" .. profileName .. "'.")
    end
    
    -- Set as active profile
    BoxxyAurasDB.activeProfile = profileName
    
    -- Update character mapping
    if not BoxxyAurasDB.characterProfileMap then
        BoxxyAurasDB.characterProfileMap = {}
    end
    local charKey = self:GetCharacterKey()
    BoxxyAurasDB.characterProfileMap[charKey] = profileName
    
    print("|cff00FF00BoxxyAuras:|r Switched to profile '" .. profileName .. "'.")
    
    -- Apply the new settings to all frame types
    if self.FrameHandler and self.FrameHandler.ApplySettings then
        local frameTypes = {"Buff", "Debuff", "Custom"}
        for _, frameType in ipairs(frameTypes) do
            self.FrameHandler.ApplySettings(frameType)
        end
    end
    
    -- Update auras to reflect new settings
    if self.UpdateAuras then
        self.UpdateAuras()
    end
    
    return true
end

-- Deep copy a table (recursive)
function BoxxyAuras:DeepCopyTable(original)
    if type(original) ~= "table" then
        return original
    end
    
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = self:DeepCopyTable(value)
        else
            copy[key] = value
        end
    end
    
    return copy
end

-- Global OnUpdate frame for hover state management
local hoverCheckFrame = CreateFrame("Frame")
hoverCheckFrame:SetScript("OnUpdate", function(self, elapsed)

    local currentLockState = BoxxyAuras:GetCurrentProfileSettings().lockFrames

    -- === Check for Unlock Transition ===
    if BoxxyAuras.WasLocked == true and currentLockState == false then
        if BoxxyAuras.DEBUG then
            print("Detected Unlock Transition: Force restoring frame visuals.")
        end
        for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", BoxxyAuras.Config.MainFrameBGColorNormal)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", BoxxyAuras.Config.BorderColor)
            end
        end
    end
    -- === End Unlock Check ===

    -- === Process Expired Debounce Timer ===
    if BoxxyAuras.DebounceEndTime and GetTime() >= BoxxyAuras.DebounceEndTime then
        if BoxxyAuras.DEBUG then
            print("Debounce timer expired for: " ..
                      (BoxxyAuras.DebounceTargetFrame and BoxxyAuras.DebounceTargetFrame:GetName() or "nil"))
        end
        BoxxyAuras.HoveredFrame = nil -- Clear the actual hover state
        BoxxyAuras.DebounceTargetFrame = nil -- Clear debounce target
        BoxxyAuras.DebounceEndTime = nil -- Clear debounce time
        BoxxyAuras.UpdateAuras() -- Trigger aura update AFTER clearing hover
    end
    -- === End Debounce Check ===

    local currentActualHovered = BoxxyAuras.HoveredFrame -- Which frame are we truly considering hovered?
    local frameMouseIsCurrentlyIn = nil

    -- 1. Determine which frame the mouse is physically inside
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if frame:IsVisible() and (BoxxyAuras.IsMouseWithinFrame(frame) or BoxxyAuras.FrameHandler.IsMouseOverAnyIcon(frame)) then
            frameMouseIsCurrentlyIn = frame
            -- If we entered a frame, we should cancel any pending leave timer.
            if BoxxyAuras.DebounceEndTime then
                BoxxyAuras.DebounceTargetFrame = nil
                BoxxyAuras.DebounceEndTime = nil
            end
            break
        end
    end
    BoxxyAuras.MouseInFrameGeometry = frameMouseIsCurrentlyIn -- Keep for other potential uses

    -- 2. Handle the LOGICAL hover state (aura persistence) - This is now independent of lock state
    if frameMouseIsCurrentlyIn then
        -- Mouse is inside a frame's geometry. This is now our hovered frame.
        if currentActualHovered ~= frameMouseIsCurrentlyIn then
            -- We entered a new frame or re-entered during a debounce period.
            if BoxxyAuras.DEBUG then print("Logical hover changed to: " .. frameMouseIsCurrentlyIn:GetName()) end
            BoxxyAuras.HoveredFrame = frameMouseIsCurrentlyIn
            BoxxyAuras.UpdateAuras() -- Update immediately as the hover context has changed
        end
        -- Since we are clearly inside a frame, cancel any pending leave-debounce timer.
        if BoxxyAuras.DebounceEndTime then
            if BoxxyAuras.DEBUG then print("Cancelled debounce timer because mouse entered " .. frameMouseIsCurrentlyIn:GetName()) end
            BoxxyAuras.DebounceTargetFrame = nil
            BoxxyAuras.DebounceEndTime = nil
        end
    else
        -- Mouse is NOT inside any frame's geometry.
        if currentActualHovered and not BoxxyAuras.DebounceEndTime then
            -- We just left a frame and are not already in a debounce period. Start the timer.
            if BoxxyAuras.DEBUG then print("Mouse left " .. currentActualHovered:GetName() .. ", starting debounce.") end
            BoxxyAuras.DebounceTargetFrame = currentActualHovered
            BoxxyAuras.DebounceEndTime = GetTime() + 1.0
            -- Don't clear HoveredFrame here; wait for the timer to expire.
        end
    end

    -- 3. Handle the VISUAL state for all frames based on logical hover and lock state
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if frame then
            if currentLockState then
                -- Frame is LOCKED: Set to be fully transparent.
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", 0, 0, 0, 0)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", 0, 0, 0, 0)
            else
                -- Frame is UNLOCKED: Set color based on hover.
                if frame == BoxxyAuras.HoveredFrame then
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", BoxxyAuras.Config.MainFrameBGColorHover)
                else
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", BoxxyAuras.Config.MainFrameBGColorNormal)
                end
                -- Always show border when unlocked.
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", BoxxyAuras.Config.BorderColor)
            end
        end
    end

    -- Update previous lock state for next tick
    BoxxyAuras.WasLocked = currentLockState
    
    -- === Periodic Cache Cleanup ===
    local currentTime = GetTime()
    if currentTime - BoxxyAuras.lastCacheCleanup > 300 then -- Clean every 5 minutes
        BoxxyAuras.lastCacheCleanup = currentTime
        
        -- Clean up old cached tooltip data
        local activeInstanceIds = {}
        
        -- Collect all currently active aura instance IDs
        for frameType, auras in pairs(BoxxyAuras.auraTracking or {}) do
            for _, aura in ipairs(auras or {}) do
                if aura.auraInstanceID then
                    activeInstanceIds[aura.auraInstanceID] = true
                end
            end
        end
        
        -- Remove cached data for auras that are no longer tracked anywhere
        local removedCount = 0
        for instanceId, _ in pairs(BoxxyAuras.AllAuras or {}) do
            if not activeInstanceIds[instanceId] then
                BoxxyAuras.AllAuras[instanceId] = nil
                removedCount = removedCount + 1
            end
        end
        
        if BoxxyAuras.DEBUG and removedCount > 0 then
            print(string.format("Cache cleanup: Removed %d old tooltip entries", removedCount))
        end
    end
    -- === End Cache Cleanup ===
end)
