local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {} -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras -- Create a convenient local alias to the global table
BoxxyAuras.AllAuras = {} -- Global cache for aura info
BoxxyAuras.recentAuraEvents = {} -- Queue for recent combat log aura events {spellId, sourceGUID, timestamp}
BoxxyAuras.Frames = {} -- << ADDED: Table to store frame references
BoxxyAuras.HoveredFrame = nil
BoxxyAuras.DEBUG = true

BoxxyAuras.Version = "1.0.0"

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
    local aStart = (a.expirationTime or 0) - (a.duration or 0)
    local bStart = (b.expirationTime or 0) - (b.duration or 0)
    if aStart == bStart then
        return a.auraInstanceID < b.auraInstanceID -- Stable tiebreaker
    end
    return aStart < bStart
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
            local filterForScrape = "HELPFUL" -- Default filter

            if auraCategory == "Debuff" then
                filterForScrape = "HARMFUL"
            elseif auraCategory == "Custom" then
                filterForScrape = newAura.originalAuraType or "HELPFUL"
            end

            if instanceIdForScrape then
                BoxxyAuras.AttemptTooltipScrape(newAura.spellId, instanceIdForScrape, filterForScrape)
            else
                -- BoxxyAuras.DebugLog(string.format("BoxxyAuras DEBUG: Missing instanceIdForScrape for SpellID %s (%s) in ProcessNewAuras", 
                --     tostring(key), newAura.name or "N/A"))
            end
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
            x = -300,
            y = 200,
            anchor = "BOTTOMLEFT",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            buffTextAlign = "CENTER",
            iconSize = 24,
            width = defaultWidth
        },
        debuffFrameSettings = {
            x = 100,
            y = 200,
            anchor = "BOTTOMLEFT",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            debuffTextAlign = "CENTER",
            iconSize = 24,
            width = defaultWidth
        },
        customFrameSettings = {
            x = -100,
            y = 100,
            anchor = "BOTTOMLEFT",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            customTextAlign = "CENTER",
            iconSize = 24,
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

    -- Get custom aura assignments
    local customNamesLookup = {}
    local profileCustomAuras = currentSettings.customAuraNames
    if profileCustomAuras and type(profileCustomAuras) == "table" then
        for name, _ in pairs(profileCustomAuras) do
            customNamesLookup[name] = true
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
        local isCustom = customNamesLookup[auraData.name]
        if isCustom and aurasByFrame["Custom"] then
            auraData.originalAuraType = "HELPFUL"
            table.insert(aurasByFrame["Custom"], auraData)
        elseif aurasByFrame["Buff"] then
            table.insert(aurasByFrame["Buff"], auraData)
        end
    end

    for _, auraData in ipairs(allCurrentDebuffs) do
        local isCustom = customNamesLookup[auraData.name]
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
    if BoxxyAuras.DEBUG then
        print("BoxxyAuras.UpdateAuras called" .. (forceRefresh and " with forceRefresh=true" or ""))
    end

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
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Performing full aura refresh")
        end

        -- Initialize auras from scratch
        InitializeAuras()

        -- Update all frames after initialization
        BoxxyAuras.FrameHandler.UpdateAllFramesAuras()

        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Full aura refresh complete")
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

    -- Get custom aura assignments
    local customNamesLookup = {}
    local profileCustomAuras = currentSettings.customAuraNames
    if profileCustomAuras and type(profileCustomAuras) == "table" then
        for name, _ in pairs(profileCustomAuras) do
            customNamesLookup[name] = true
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
        local isCustom = customNamesLookup[auraData.name]
        if isCustom and aurasByFrame["Custom"] then
            auraData.originalAuraType = "HELPFUL"
            table.insert(aurasByFrame["Custom"], auraData)
        elseif aurasByFrame["Buff"] then
            table.insert(aurasByFrame["Buff"], auraData)
        end
    end

    for _, auraData in ipairs(allCurrentDebuffs) do
        local isCustom = customNamesLookup[auraData.name]
        if isCustom and aurasByFrame["Custom"] then
            auraData.originalAuraType = "HARMFUL"
            table.insert(aurasByFrame["Custom"], auraData)
        elseif aurasByFrame["Debuff"] then
            table.insert(aurasByFrame["Debuff"], auraData)
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
                    -- Update existing aura data
                    trackedAura.spellId = currentAura.spellId
                    trackedAura.originalAuraType = currentAura.originalAuraType or currentAura.auraType
                    trackedAura.expirationTime = currentAura.expirationTime
                    trackedAura.duration = currentAura.duration
                    trackedAura.slot = currentAura.slot
                    trackedAura.seen = true
                    foundInTracked = true
                    break
                end
            end

            if not foundInTracked then
                -- Process source GUID from recent events if needed
                if frameType ~= "Buff" then -- Only for non-buff auras
                    for i = #BoxxyAuras.recentAuraEvents, 1, -1 do
                        local event = BoxxyAuras.recentAuraEvents[i]
                        if event.spellId == currentAura.spellId then
                            currentAura.sourceGUID = event.sourceGUID
                            table.remove(BoxxyAuras.recentAuraEvents, i)
                            break
                        end
                    end
                end

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
                -- Check if the current frame is the one being hovered
                if frame == BoxxyAuras.HoveredFrame then
                    -- Keep the aura, mark as forceExpired
                    trackedAura.forceExpired = true
                    trackedAura.expirationTime = 0 -- Ensure it's treated as expired
                    table.insert(newTrackedAuras, trackedAura)

                    if BoxxyAuras.DEBUG then
                        print("BoxxyAuras: Keeping expired aura " .. (trackedAura.name or "unknown") ..
                                  " in hovered frame " .. (frame:GetName() or "?"))
                    end
                else
                    -- Not hovering this frame, remove the aura from tracking and cache
                    if trackedAura.auraInstanceID and BoxxyAuras.AllAuras[trackedAura.auraInstanceID] then
                        BoxxyAuras.AllAuras[trackedAura.auraInstanceID] = nil
                        if BoxxyAuras.DEBUG then
                            print("BoxxyAuras: Removing expired aura " .. (trackedAura.name or "unknown") ..
                                      " from cache and non-hovered frame")
                        end
                    end
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

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName,
            spellSchool, amount = CombatLogGetCurrentEventInfo()

        -- Handle Damage Events for Shake Effect
        if destName and destName == UnitName("player") and
            (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE") then
            if spellId and sourceGUID and amount and amount > 0 and #trackedDebuffs > 0 then
                local targetAuraInstanceID = nil
                for _, trackedDebuff in ipairs(trackedDebuffs) do
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
                    for _, auraIcon in ipairs(BoxxyAuras.debuffIcons) do
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
                                        local percentInRange = (damagePercent - minPercent) / (maxPercent - minPercent)
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

-- Slash command handler
SLASH_BOXXYAURAS1 = "/boxxyauras"
SLASH_BOXXYAURAS2 = "/ba"

function SlashCmdList.BOXXYAURAS(msg, editBox)
    local command = msg:lower():trim()

    if command == "options" or command == "" then
        BoxxyAuras.Options:Toggle()
    elseif command == "lock" then
        local settings = BoxxyAuras:GetCurrentProfileSettings()
        settings.lockFrames = not settings.lockFrames
        BoxxyAuras.FrameHandler.ApplyLockState(settings.lockFrames)
        print("BoxxyAuras frames " .. (settings.lockFrames and "locked." or "unlocked."))
    elseif command == "reset" then
        print("|cFF00FF00BoxxyAuras:|r Resetting frame positions...")
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if not currentSettings then
            print("|cFFFF0000BoxxyAuras Error:|r Cannot get current settings to reset positions.")
            return
        end

        local frameTypes = {"Buff", "Debuff", "Custom"}
        for _, frameType in ipairs(frameTypes) do
            local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
            if settingsKey and currentSettings[settingsKey] then
                print("|cFF00FF00BoxxyAuras:|r   Resetting " .. frameType .. " frame saved data.")
                currentSettings[settingsKey].x = nil
                currentSettings[settingsKey].y = nil
                currentSettings[settingsKey].point = nil
                currentSettings[settingsKey].scale = 1.0
            end
        end

        -- Re-initialize frames to apply the reset defaults
        BoxxyAuras.FrameHandler.InitializeFrames()
        print("|cFF00FF00BoxxyAuras:|r Frame positions reset. You may need to /reload for all changes to take effect.")

    else
        print("BoxxyAuras: Unknown command '/ba " .. command .. "'. Use '/ba options', '/ba lock', or '/ba reset'.")
    end
end

-- <<< NEW: Global OnUpdate frame for hover state management >>>
local hoverCheckFrame = CreateFrame("Frame")
hoverCheckFrame:SetScript("OnUpdate", function(self, elapsed)
    local currentHovered = BoxxyAuras.HoveredFrame

    -- <<< ADDED: Skip checks if currently resizing the hovered frame >>>
    if currentHovered and currentHovered.isResizing then
        -- Keep hover visuals active and prevent leave logic/debounce while actively resizing
        if not BoxxyAuras.Config.FramesLocked then
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(currentHovered, "backdrop", BoxxyAuras.Config.MainFrameBGColorHover)
        end
        -- Also cancel any pending leave debounce if we start resizing
        if currentHovered.leaveDebounceEndTime then
            currentHovered.leaveDebounceEndTime = nil
        end
        return -- Skip the rest of the checks
    end
    -- <<< END ADDED CHECK >>>

    -- First, process any frame waiting for its debounce timer to finish for AURA cleanup
    if currentHovered and currentHovered.leaveDebounceEndTime and GetTime() >= currentHovered.leaveDebounceEndTime then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Debounce timer finished for frame " .. currentHovered:GetName() ..
                      ". Clearing HoveredFrame and updating auras.")
        end

        -- Timer finished for aura cleanup
        local previouslyHovered = currentHovered -- Store reference before clearing
        BoxxyAuras.HoveredFrame = nil -- Clear global reference *only now*
        previouslyHovered.leaveDebounceEndTime = nil -- Clear the timer flag

        BoxxyAuras.UpdateAuras() -- Force update to remove expired icons

        -- Hide handles now that hover is truly over
        if previouslyHovered.handles then
            if previouslyHovered.handles.left then
                previouslyHovered.handles.left:Hide()
            end
            if previouslyHovered.handles.right then
                previouslyHovered.handles.right:Hide()
            end
        end

        currentHovered = nil -- Update local variable since we just left
    end

    -- Next, check the current hover state based on mouse position for VISUALS
    if currentHovered and currentHovered:IsVisible() then
        -- Check if cursor is still inside the frame
        local isInside = BoxxyAuras.IsMouseWithinFrame(currentHovered)

        if not isInside then
            -- Cursor is OUTSIDE the frame
            -- Reset background color *immediately* if not locked
            if not BoxxyAuras.Config.FramesLocked then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(currentHovered, "backdrop",
                    BoxxyAuras.Config.MainFrameBGColorNormal)
            end

            -- Check if we haven't already started the debounce timer for AURA cleanup
            if not currentHovered.leaveDebounceEndTime then
                if BoxxyAuras.DEBUG then
                    print("BoxxyAuras: Mouse left hovered frame " .. currentHovered:GetName() ..
                              ", starting 1s debounce for aura cleanup.")
                end
                -- Start the debounce timer
                currentHovered.leaveDebounceEndTime = GetTime() + 1.0
            end
        else
            -- Cursor is INSIDE the frame
            -- Ensure hover visuals are applied
            if not BoxxyAuras.Config.FramesLocked then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(currentHovered, "backdrop",
                    BoxxyAuras.Config.MainFrameBGColorHover)
            end

            -- If a debounce timer was previously started (mouse left then quickly re-entered), clear it
            if currentHovered.leaveDebounceEndTime then
                if BoxxyAuras.DEBUG then
                    print("BoxxyAuras: Mouse re-entered frame " .. currentHovered:GetName() ..
                              " during debounce, cancelling aura cleanup timer.")
                end
                currentHovered.leaveDebounceEndTime = nil
            end
        end
    else
        -- If HoveredFrame was somehow set but isn't visible, clear it immediately
        if BoxxyAuras.HoveredFrame then
            if BoxxyAuras.DEBUG then
                print("BoxxyAuras: Clearing invisible/invalid HoveredFrame: " .. BoxxyAuras.HoveredFrame:GetName())
            end
            if BoxxyAuras.HoveredFrame.leaveDebounceEndTime then -- Clear timer just in case
                BoxxyAuras.HoveredFrame.leaveDebounceEndTime = nil
            end
            BoxxyAuras.HoveredFrame = nil
        end
    end
end)
