local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}      -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras        -- Create a convenient local alias to the global table
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
        local key = newAura.spellId
        if key and not BoxxyAuras.AllAuras[key] then
            local instanceIdForScrape = newAura.auraInstanceID
            local filterForScrape = "HELPFUL" -- Default filter

            if auraCategory == "Debuff" then
                filterForScrape = "HARMFUL"
            elseif auraCategory == "Custom" then
                filterForScrape = newAura.originalAuraType or "HELPFUL"
            end
            
            if instanceIdForScrape then
                BoxxyAuras.AttemptTooltipScrape(key, instanceIdForScrape, filterForScrape)
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
         defaultWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(defaultIconsWide_Reset, defaultIconSize_ForCalc) or defaultWidth
    end


    return {
        lockFrames = false,
        hideBlizzardAuras = true,
        optionsScale = 1.0,
        customAuraNames = {},
        buffFrameSettings = { x = -300, y = 200, anchor = "BOTTOMLEFT", height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, buffTextAlign = "CENTER", iconSize = 24, width = defaultWidth },
        debuffFrameSettings = { x = 100, y = 200, anchor = "BOTTOMLEFT", height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, debuffTextAlign = "CENTER", iconSize = 24, width = defaultWidth },
        customFrameSettings = { x = -100, y = 100, anchor = "BOTTOMLEFT", height = defaultMinHeight, numIconsWide = defaultIconsWide_Reset, customTextAlign = "CENTER", iconSize = 24, width = defaultWidth }
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
    if not BoxxyAurasDB then BoxxyAurasDB = {} end
    if not BoxxyAurasDB.profiles then BoxxyAurasDB.profiles = {} end
    -- <<< ADDED: Ensure character map exists >>>
    if not BoxxyAurasDB.characterProfileMap then BoxxyAurasDB.characterProfileMap = {} end 

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

    if profile.lockFrames == nil then profile.lockFrames = false end
    if profile.optionsScale == nil then profile.optionsScale = 1.0 end
    if profile.hideBlizzardAuras == nil then profile.hideBlizzardAuras = true end

    if profile.buffFrameSettings.buffTextAlign == nil then profile.buffFrameSettings.buffTextAlign = "CENTER" end
    if profile.debuffFrameSettings.debuffTextAlign == nil then profile.debuffFrameSettings.debuffTextAlign = "CENTER" end
    if profile.customFrameSettings.customTextAlign == nil then profile.customFrameSettings.customTextAlign = "CENTER" end
    if profile.buffFrameSettings.iconSize == nil then profile.buffFrameSettings.iconSize = 24 end
    if profile.debuffFrameSettings.iconSize == nil then profile.debuffFrameSettings.iconSize = 24 end
    if profile.customFrameSettings.iconSize == nil then profile.customFrameSettings.iconSize = 24 end
    
    -- <<< ADDED: Ensure numIconsWide exists >>>
    if profile.buffFrameSettings.numIconsWide == nil then profile.buffFrameSettings.numIconsWide = 6 end
    if profile.debuffFrameSettings.numIconsWide == nil then profile.debuffFrameSettings.numIconsWide = 6 end
    if profile.customFrameSettings.numIconsWide == nil then profile.customFrameSettings.numIconsWide = 6 end

    return profile
end

-- Function to populate trackedAuras and create initial icons
local function InitializeAuras()
    -- <<< DEBUG >>>
    -- print("BoxxyAuras DEBUG: InitializeAuras START")
    -- <<< END DEBUG >>>

    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        -- BoxxyAuras.DebugLogError("C_UnitAuras Slot API not ready during Initialize!")
        return
    end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then 
        -- BoxxyAuras.DebugLogError("AuraIcon class not found during Initialize!")
        return
    end

    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    wipe(trackedBuffs)
    wipe(trackedDebuffs)
    wipe(trackedCustom)
    for _, icon in ipairs(BoxxyAuras.buffIcons) do icon.frame:Hide() end
    for _, icon in ipairs(BoxxyAuras.debuffIcons) do icon.frame:Hide() end
    for _, icon in ipairs(BoxxyAuras.customIcons) do icon.frame:Hide() end

    local allCurrentBuffs = {}
    local allCurrentDebuffs = {}
    local currentCustom = {}
    local buffSlots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
    local debuffSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }

    for i = 2, #buffSlots do
        local slot = buffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot
            table.insert(allCurrentBuffs, auraData) 
        end
    end
    for i = 2, #debuffSlots do
        local slot = debuffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then
            auraData.slot = slot
            table.insert(allCurrentDebuffs, auraData) 
        end
    end

    local customNamesLookup = {}
    local profileCustomAuras = currentSettings.customAuraNames
    if profileCustomAuras then
        if type(profileCustomAuras) == "table" then
            for name, _ in pairs(profileCustomAuras) do
                customNamesLookup[name] = true
            end
        else
            -- BoxxyAuras.DebugLogError("customAuraNames in CURRENT PROFILE is not a table!")
        end
    end

    local currentBuffs = {}
    local currentDebuffs = {}
    local currentCustom = {}

    for _, auraData in ipairs(allCurrentBuffs) do
        local isCustom = customNamesLookup[auraData.name]
        if isCustom then
            auraData.originalAuraType = "HELPFUL"
            table.insert(currentCustom, auraData)
        else
            table.insert(currentBuffs, auraData)
        end
    end
    for _, auraData in ipairs(allCurrentDebuffs) do
        local isCustom = customNamesLookup[auraData.name]
        if isCustom then
            auraData.originalAuraType = "HARMFUL"
            table.insert(currentCustom, auraData)
        else
            table.insert(currentDebuffs, auraData)
        end
    end

    table.sort(currentBuffs, SortAurasForDisplay)
    table.sort(currentDebuffs, SortAurasForDisplay)
    table.sort(currentCustom, SortAurasForDisplay)

    for _, auraData in ipairs(currentBuffs) do table.insert(trackedBuffs, auraData) end
    for _, auraData in ipairs(currentDebuffs) do table.insert(trackedDebuffs, auraData) end
    for _, auraData in ipairs(currentCustom) do table.insert(trackedCustom, auraData) end

    local buffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Buff
    local debuffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Debuff
    local customFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Custom

    if not buffFrame then -- BoxxyAuras.DebugLogError("InitializeAuras Error: Buff frame not found in BoxxyAuras.Frames!");
        return end
    if not debuffFrame then -- BoxxyAuras.DebugLogError("InitializeAuras Error: Debuff frame not found in BoxxyAuras.Frames!");
        return end
    if not customFrame then -- BoxxyAuras.DebugLogError("InitializeAuras Error: Custom frame not found in BoxxyAuras.Frames!");
        return end

    for i, auraData in ipairs(trackedBuffs) do
        local auraIcon = BoxxyAuras.buffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(buffFrame, i, "BoxxyAurasBuffIcon")
            BoxxyAuras.buffIcons[i] = auraIcon
            if auraIcon and auraIcon.newAuraAnimGroup then
                auraIcon.newAuraAnimGroup:Play()
            end
        end
        -- <<< DEBUG >>>
        -- print(string.format("BoxxyAuras DEBUG: InitializeAuras - Updating Buff Icon %d for SpellID %s", i, tostring(auraData and auraData.spellId or 'NIL')))
        -- <<< END DEBUG >>>
        auraIcon:Update(auraData, i, "HELPFUL")
        auraIcon.frame:Show() 
    end
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = BoxxyAuras.debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffFrame, i, "BoxxyAurasDebuffIcon")
            BoxxyAuras.debuffIcons[i] = auraIcon
            if auraIcon and auraIcon.newAuraAnimGroup then
                auraIcon.newAuraAnimGroup:Play()
            end
        end
        -- <<< DEBUG >>>
        -- print(string.format("BoxxyAuras DEBUG: InitializeAuras - Updating Debuff Icon %d for SpellID %s", i, tostring(auraData and auraData.spellId or 'NIL')))
        -- <<< END DEBUG >>>
        auraIcon:Update(auraData, i, "HARMFUL")
        auraIcon.frame:Show()
    end
    for i, auraData in ipairs(trackedCustom) do
        local auraIcon = BoxxyAuras.customIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(customFrame, i, "BoxxyAurasCustomIcon")
            BoxxyAuras.customIcons[i] = auraIcon
            if auraIcon and auraIcon.newAuraAnimGroup then
                auraIcon.newAuraAnimGroup:Play()
            end
        end
        -- <<< DEBUG >>>
        -- print(string.format("BoxxyAuras DEBUG: InitializeAuras - Updating Custom Icon %d for SpellID %s", i, tostring(auraData and auraData.spellId or 'NIL')))
        -- <<< END DEBUG >>>
        auraIcon:Update(auraData, i, "CUSTOM")
        auraIcon.frame:Show()
    end

    for i = #trackedBuffs + 1, #BoxxyAuras.buffIcons do BoxxyAuras.buffIcons[i].frame:Hide() end
    for i = #trackedDebuffs + 1, #BoxxyAuras.debuffIcons do BoxxyAuras.debuffIcons[i].frame:Hide() end
    for i = #trackedCustom + 1, #BoxxyAuras.customIcons do BoxxyAuras.customIcons[i].frame:Hide() end

    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.LayoutAuras then
        BoxxyAuras.FrameHandler.LayoutAuras("Buff")
        BoxxyAuras.FrameHandler.LayoutAuras("Debuff")
        BoxxyAuras.FrameHandler.LayoutAuras("Custom")
    else
        -- BoxxyAuras.DebugLogError("InitializeAuras Error: FrameHandler.LayoutAuras not found!")
    end

    -- <<< DEBUG >>>
    -- print("BoxxyAuras DEBUG: InitializeAuras END")
    -- <<< END DEBUG >>>
end

-- Function to update displayed auras using cache comparison and stable order
BoxxyAuras.UpdateAuras = function()
    -- <<< DEBUG >>>
    -- print("BoxxyAuras DEBUG: UpdateAuras START")
    -- <<< END DEBUG >>>
    
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

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

    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        -- print("BoxxyAuras DEBUG: UpdateAuras - C_UnitAuras not ready, exiting.") -- Added debug exit reason
        return
    end
    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then 
        -- print("BoxxyAuras DEBUG: UpdateAuras - AuraIcon class not found, exiting.") -- Added debug exit reason
        return 
    end

    local allCurrentBuffs = {}
    local allCurrentDebuffs = {}
    local currentCustom = {}
    local buffSlots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
    local debuffSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }

    for i = 2, #buffSlots do
        local slot = buffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot
            table.insert(allCurrentBuffs, auraData) 
        end
    end
    for i = 2, #debuffSlots do
        local slot = debuffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then
            auraData.slot = slot
            table.insert(allCurrentDebuffs, auraData) 
        end
    end

    local customNamesLookup = {}
    local profileCustomAuras = currentSettings.customAuraNames
    if profileCustomAuras then
        if type(profileCustomAuras) == "table" then
            for name, _ in pairs(profileCustomAuras) do
                customNamesLookup[name] = true
            end
        else
            -- BoxxyAuras.DebugLogError("customAuraNames in CURRENT PROFILE is not a table!")
        end
    end

    local currentBuffs = {}
    local currentDebuffs = {}
    local currentCustom = {}

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

    local currentBuffMap = {}
    for _, auraData in ipairs(currentBuffs) do currentBuffMap[auraData.auraInstanceID] = auraData end
    local currentDebuffMap = {}
    for _, auraData in ipairs(currentDebuffs) do currentDebuffMap[auraData.auraInstanceID] = auraData end
    local currentCustomMap = {}
    for _, auraData in ipairs(currentCustom) do currentCustomMap[auraData.auraInstanceID] = auraData end
    
    for _, trackedAura in ipairs(trackedBuffs) do trackedAura.seen = false end
    for _, trackedAura in ipairs(trackedDebuffs) do trackedAura.seen = false end
    for _, trackedAura in ipairs(trackedCustom) do trackedAura.seen = false end
    
    local newBuffsToAdd = {}
    local newDebuffsToAdd = {}
    local newCustomsToAdd = {}

    for _, currentAura in ipairs(currentBuffs) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedBuffs) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                trackedAura.spellId = currentAura.spellId
                trackedAura.originalAuraType = currentAura.originalAuraType
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            table.insert(newBuffsToAdd, currentAura)
        end
    end

    for _, currentAura in ipairs(currentDebuffs) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedDebuffs) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            local foundEventMatch = false
            for i = #BoxxyAuras.recentAuraEvents, 1, -1 do
                local event = BoxxyAuras.recentAuraEvents[i]
                if event.spellId == currentAura.spellId then
                    currentAura.sourceGUID = event.sourceGUID
                    table.remove(BoxxyAuras.recentAuraEvents, i)
                    foundEventMatch = true
                    break
                end
            end

            table.insert(newDebuffsToAdd, currentAura)
        end
    end
    for _, currentAura in ipairs(currentCustom) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedCustom) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            local foundEventMatch = false
            for i = #BoxxyAuras.recentAuraEvents, 1, -1 do
                local event = BoxxyAuras.recentAuraEvents[i]
                if event.spellId == currentAura.spellId then
                    currentAura.sourceGUID = event.sourceGUID
                    table.remove(BoxxyAuras.recentAuraEvents, i)
                    foundEventMatch = true
                    break
                end
            end

            table.insert(newCustomsToAdd, currentAura)
        end
    end

    local newTrackedBuffs = {}
    for _, trackedAura in ipairs(trackedBuffs) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil
            table.insert(newTrackedBuffs, trackedAura)
        else
            if BoxxyAuras.FrameHoverStates.BuffFrame then
                table.insert(newTrackedBuffs, trackedAura)
                trackedAura.forceExpired = true
                trackedAura.expirationTime = 0
            else
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    -- BoxxyAuras.DebugLog(string.format("UpdateAuras: Removing SpellID %d from cache (Not Hovering Buffs)", trackedAura.spellId))
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
        end
    end
    local newTrackedDebuffs = {}
    for _, trackedAura in ipairs(trackedDebuffs) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil
            table.insert(newTrackedDebuffs, trackedAura)
        else
            if BoxxyAuras.FrameHoverStates.DebuffFrame then
                table.insert(newTrackedDebuffs, trackedAura)
                trackedAura.forceExpired = true
                trackedAura.expirationTime = 0
            else
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    -- BoxxyAuras.DebugLog(string.format("UpdateAuras: Removing SpellID %d from cache (Not Hovering Debuffs)", trackedAura.spellId))
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
        end
    end
    local newTrackedCustoms = {}
    for _, trackedAura in ipairs(trackedCustom) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil
            table.insert(newTrackedCustoms, trackedAura)
        else
            if BoxxyAuras.FrameHoverStates.CustomFrame then
                table.insert(newTrackedCustoms, trackedAura)
                trackedAura.forceExpired = true
                trackedAura.expirationTime = 0
            else
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    -- BoxxyAuras.DebugLog(string.format("UpdateAuras: Removing SpellID %d from cache (Not Hovering Custom)", trackedAura.spellId))
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
        end
    end

    BoxxyAuras.ProcessNewAuras(newBuffsToAdd, newTrackedBuffs, "Buff")
    BoxxyAuras.ProcessNewAuras(newDebuffsToAdd, newTrackedDebuffs, "Debuff")
    BoxxyAuras.ProcessNewAuras(newCustomsToAdd, newTrackedCustoms, "Custom")

    trackedBuffs = newTrackedBuffs
    trackedDebuffs = newTrackedDebuffs
    trackedCustom = newTrackedCustoms

    if not BoxxyAuras.FrameHoverStates.BuffFrame then
        table.sort(trackedBuffs, SortAurasForDisplay)
    end
    if not BoxxyAuras.FrameHoverStates.DebuffFrame then
        table.sort(trackedDebuffs, SortAurasForDisplay)
    end
    if not BoxxyAuras.FrameHoverStates.CustomFrame then
        table.sort(trackedCustom, SortAurasForDisplay)
    end

    local buffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Buff
    local debuffFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Debuff
    local customFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Custom

    if not buffFrame then -- BoxxyAuras.DebugLogError("UpdateAuras Step 7: Buff frame not found!");
        return end
    if not debuffFrame then -- BoxxyAuras.DebugLogError("UpdateAuras Step 7: Debuff frame not found!");
        return end
    if not customFrame then -- BoxxyAuras.DebugLogError("UpdateAuras Step 7: Custom frame not found!");
        return end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then -- BoxxyAuras.DebugLogError("UpdateAuras Step 7: AuraIcon class not found!");
        return end

    BoxxyAuras.buffIconPool = BoxxyAuras.buffIconPool or {}
    BoxxyAuras.debuffIconPool = BoxxyAuras.debuffIconPool or {}
    BoxxyAuras.customIconPool = BoxxyAuras.customIconPool or {}

    local function GetOrCreateIcon(pool, activeList, parentFrame, baseNamePrefix)
        local icon = table.remove(pool)
        if not icon then
            local newIndex = (#activeList + #pool + 1)
            icon = AuraIcon.New(parentFrame, newIndex, baseNamePrefix)
        end
        return icon
    end

    local function ReturnIconToPool(pool, icon)
        if icon and icon.frame then
            icon.frame:Hide()
            table.insert(pool, icon)
        end
    end

    local currentBuffIcons = {}
    local usedBuffIcons = {}

    for i, auraData in ipairs(trackedBuffs) do
        local targetIcon = nil
        local playedAnimation = false

        local foundMatch = false
        for visualIndex, existingIcon in ipairs(BoxxyAuras.buffIcons) do
            if not usedBuffIcons[visualIndex] and existingIcon and existingIcon.auraInstanceID == auraData.auraInstanceID then
                targetIcon = existingIcon
                usedBuffIcons[visualIndex] = true
                foundMatch = true
                break
            end
        end

        if not foundMatch then
            targetIcon = GetOrCreateIcon(BoxxyAuras.buffIconPool, currentBuffIcons, buffFrame, "BoxxyAurasBuffIcon")
            if targetIcon and targetIcon.newAuraAnimGroup then
                targetIcon.newAuraAnimGroup:Play()
                playedAnimation = true
            end
        end

        if targetIcon then
            -- <<< DEBUG >>>
            -- print(string.format("BoxxyAuras DEBUG: UpdateAuras - Updating Buff Icon %d for SpellID %s", i, tostring(auraData and auraData.spellId or 'NIL')))
            -- <<< END DEBUG >>>
            targetIcon:Update(auraData, i, "HELPFUL")
            targetIcon.frame:Show()
            currentBuffIcons[i] = targetIcon
        else
            -- BoxxyAuras.DebugLogError("UpdateAuras Step 7: Failed to get/create/assign buff icon for index " .. i)
        end
    end

    for visualIndex, existingIcon in ipairs(BoxxyAuras.buffIcons) do
        if not usedBuffIcons[visualIndex] then
            ReturnIconToPool(BoxxyAuras.buffIconPool, existingIcon)
        end
    end

    BoxxyAuras.buffIcons = currentBuffIcons

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
            -- <<< DEBUG >>>
            -- print(string.format("BoxxyAuras DEBUG: UpdateAuras - Updating Debuff Icon %d for SpellID %s", i, tostring(auraData and auraData.spellId or 'NIL')))
            -- <<< END DEBUG >>>
            targetIcon:Update(auraData, i, "HARMFUL")
            targetIcon.frame:Show()
            currentDebuffIcons[i] = targetIcon
        else
            -- BoxxyAuras.DebugLogError("UpdateAuras Step 7: Failed to get/create/assign debuff icon for index " .. i)
        end
    end
    for visualIndex, existingIcon in ipairs(BoxxyAuras.debuffIcons) do
        if not usedDebuffIcons[visualIndex] then
            ReturnIconToPool(BoxxyAuras.debuffIconPool, existingIcon)
        end
    end
    BoxxyAuras.debuffIcons = currentDebuffIcons

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
            -- <<< DEBUG >>>
            -- print(string.format("BoxxyAuras DEBUG: UpdateAuras - Updating Custom Icon %d for SpellID %s", i, tostring(auraData and auraData.spellId or 'NIL')))
            -- <<< END DEBUG >>>
            targetIcon:Update(auraData, i, "CUSTOM")
            targetIcon.frame:Show()
            currentCustomIcons[i] = targetIcon
        else
            -- BoxxyAuras.DebugLogError("UpdateAuras Step 7: Failed to get/create/assign custom icon for index " .. i)
        end
    end
    for visualIndex, existingIcon in ipairs(BoxxyAuras.customIcons) do
        if not usedCustomIcons[visualIndex] then
            ReturnIconToPool(BoxxyAuras.customIconPool, existingIcon)
        end
    end
    BoxxyAuras.customIcons = currentCustomIcons

    if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.LayoutAuras then
        BoxxyAuras.FrameHandler.LayoutAuras("Buff")
        BoxxyAuras.FrameHandler.LayoutAuras("Debuff")
        BoxxyAuras.FrameHandler.LayoutAuras("Custom")
    else
        -- BoxxyAuras.DebugLogError("UpdateAuras Error: FrameHandler.LayoutAuras not found!")
    end

    -- <<< DEBUG >>>
    -- print("BoxxyAuras DEBUG: UpdateAuras END")
    -- <<< END DEBUG >>>
end

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN") 
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    local unit = (...)
    if event == "PLAYER_LOGIN" then
        
        if BoxxyAurasDB == nil then BoxxyAurasDB = {} end
        if BoxxyAurasDB.profiles == nil then BoxxyAurasDB.profiles = {} end
        if BoxxyAurasDB.activeProfile == nil then BoxxyAurasDB.activeProfile = "Default" end
        if BoxxyAuras.Frames == nil then BoxxyAuras.Frames = {} end

        if not BoxxyAuras.Frames.Buff then
            BoxxyAuras.Frames.Buff = CreateFrame("Frame", "BoxxyBuffDisplayFrame", UIParent)
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.SetupDisplayFrame then
                BoxxyAuras.FrameHandler.SetupDisplayFrame(BoxxyAuras.Frames.Buff, "BuffFrame")
            end

            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.CreateResizeHandlesForFrame then
                BoxxyAuras.FrameHandler.CreateResizeHandlesForFrame(BoxxyAuras.Frames.Buff, "BuffFrame")
            end
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.OnDisplayFrameResizeUpdate then
                BoxxyAuras.Frames.Buff:SetScript("OnUpdate", BoxxyAuras.FrameHandler.OnDisplayFrameResizeUpdate)
            end
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.PollFrameHoverState then
                C_Timer.NewTicker(0.1, function() BoxxyAuras.FrameHandler.PollFrameHoverState(BoxxyAuras.Frames.Buff, "Buff Frame") end)
            end
        end
        
        if not BoxxyAuras.Frames.Debuff then
            BoxxyAuras.Frames.Debuff = CreateFrame("Frame", "BoxxyDebuffDisplayFrame", UIParent)
             if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.SetupDisplayFrame then
                 BoxxyAuras.FrameHandler.SetupDisplayFrame(BoxxyAuras.Frames.Debuff, "DebuffFrame")
             end
             
             if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.CreateResizeHandlesForFrame then
                 BoxxyAuras.FrameHandler.CreateResizeHandlesForFrame(BoxxyAuras.Frames.Debuff, "DebuffFrame")
            end
             if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.OnDisplayFrameResizeUpdate then
                 BoxxyAuras.Frames.Debuff:SetScript("OnUpdate", BoxxyAuras.FrameHandler.OnDisplayFrameResizeUpdate)
             end
             if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.PollFrameHoverState then
                 C_Timer.NewTicker(0.1, function() BoxxyAuras.FrameHandler.PollFrameHoverState(BoxxyAuras.Frames.Debuff, "Debuff Frame") end)
             end
        end
        
        if not BoxxyAuras.Frames.Custom then
            BoxxyAuras.Frames.Custom = CreateFrame("Frame", "BoxxyCustomDisplayFrame", UIParent)
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.SetupDisplayFrame then
                BoxxyAuras.FrameHandler.SetupDisplayFrame(BoxxyAuras.Frames.Custom, "CustomFrame")
            end
            
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.CreateResizeHandlesForFrame then
                BoxxyAuras.FrameHandler.CreateResizeHandlesForFrame(BoxxyAuras.Frames.Custom, "CustomFrame")
            end
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.OnDisplayFrameResizeUpdate then
                BoxxyAuras.Frames.Custom:SetScript("OnUpdate", BoxxyAuras.FrameHandler.OnDisplayFrameResizeUpdate)
            end
            if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.PollFrameHoverState then
                C_Timer.NewTicker(0.1, function() BoxxyAuras.FrameHandler.PollFrameHoverState(BoxxyAuras.Frames.Custom, "Custom Frame") end)
            end
        end

        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

        BoxxyAuras.ApplyBlizzardAuraVisibility(currentSettings.hideBlizzardAuras)
        
        if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.InitializeFrames then
            local initSuccess, initErr = pcall(BoxxyAuras.FrameHandler.InitializeFrames)
            if not initSuccess then
                -- BoxxyAuras.DebugLogError("Error calling FrameHandler.InitializeFrames: " .. tostring(initErr))
            end
        else
            -- BoxxyAuras.DebugLogError("FrameHandler.InitializeFrames not found during PLAYER_LOGIN!")
        end

        local success, err = pcall(InitializeAuras)
        if not success then
            -- BoxxyAuras.DebugLogError("Error in InitializeAuras (pcall): " .. tostring(err))
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName, spellSchool, amount = CombatLogGetCurrentEventInfo()

        if destName and destName == UnitName("player") and (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE") then
            if spellId and sourceGUID and amount and amount > 0 and #trackedDebuffs > 0 then
                local targetAuraInstanceID = nil
                for _, trackedDebuff in ipairs(trackedDebuffs) do
                    if trackedDebuff and trackedDebuff.spellId == spellId and trackedDebuff.sourceGUID == sourceGUID then
                        targetAuraInstanceID = trackedDebuff.auraInstanceID
                        break
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

                                    if minPercent >= maxPercent then maxPercent = minPercent + 0.01 end

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
                            else
                                -- BoxxyAuras.DebugLogError("Shake method not found on AuraIcon instance!")
                            end
                            break
                        end
                    end
                end
            end

        elseif destGUID == UnitGUID("player") and 
               (subevent == "SPELL_AURA_APPLIED" or 
                subevent == "SPELL_AURA_REFRESH" or 
                subevent == "SPELL_AURA_REMOVED" or 
                subevent == "SPELL_AURA_APPLIED_DOSE" or
                subevent == "SPELL_AURA_REMOVED_DOSE") then

            if spellId and sourceGUID and (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" or subevent == "SPELL_AURA_APPLIED_DOSE") then
                local eventData = { spellId = spellId, sourceGUID = sourceGUID, timestamp = timestamp }
                table.insert(BoxxyAuras.recentAuraEvents, eventData)
            end

            BoxxyAuras.UpdateAuras()
        end
    end
end)

function BoxxyAuras.GetTrackedAuras(listType)
    if listType == "Buff" then return trackedBuffs end
    if listType == "Debuff" then return trackedDebuffs end
    if listType == "Custom" then return trackedCustom end
    -- BoxxyAuras.DebugLogError("GetTrackedAuras: Invalid listType - " .. tostring(listType))
    return {}
end

function BoxxyAuras.SetTrackedAuras(listType, newList)
    if listType == "Buff" then trackedBuffs = newList
    elseif listType == "Debuff" then trackedDebuffs = newList
    elseif listType == "Custom" then trackedCustom = newList
    else 
        -- BoxxyAuras.DebugLogError("SetTrackedAuras: Invalid listType - " .. tostring(listType))
    end
end

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