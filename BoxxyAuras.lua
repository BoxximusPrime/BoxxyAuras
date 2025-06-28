local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}       -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras          -- Create a convenient local alias to the global table

BoxxyAuras.Version = "1.2.1"

BoxxyAuras.AllAuras = {}         -- Global cache for aura info
BoxxyAuras.recentAuraEvents = {} -- Queue for recent combat log aura events {spellId, sourceGUID, timestamp}
BoxxyAuras.Frames = {}           -- << ADDED: Table to store frame references
BoxxyAuras.iconArrays = {}       -- << ADDED: Table to store live icon objects
BoxxyAuras.auraTracking = {}     -- << ADDED: Table to track aura data
BoxxyAuras.HoveredFrame = nil
BoxxyAuras.DEBUG = false
BoxxyAuras.lastCacheCleanup = 0 -- Track when we last cleaned the cache

-- Previous Lock State Tracker
BoxxyAuras.WasLocked = nil

-- <<< NEW: Geometric Mouse Position Tracker >>>
BoxxyAuras.MouseInFrameGeometry = nil

-- <<< NEW: Icon Counters for Pooling >>>
BoxxyAuras.iconCounters = { Buff = 0, Debuff = 0, Custom = 0 }

-- <<< NEW: Central Update Manager >>>
BoxxyAuras.UpdateManager = {
    lastSlowUpdate = 0,
    lastMediumUpdate = 0,
    lastFastUpdate = 0,
    auras = {
        slow = {},   -- 1.0s updates (>60s remaining)
        medium = {}, -- 0.5s updates (10-60s remaining)
        fast = {}    -- 0.1s updates (<10s remaining)
    }
}

-- Function to determine which update tier an aura should be in
function BoxxyAuras.UpdateManager:GetTierForAura(auraIcon)
    if not auraIcon or not auraIcon.expirationTime or not auraIcon.duration or auraIcon.duration <= 0 then
        return nil -- Permanent auras or invalid auras don't need updates
    end

    local remaining = auraIcon.expirationTime - GetTime()
    if remaining <= 0 then
        return "fast" -- Expired auras need fast updates for grace period
    elseif remaining <= 10 then
        return "fast"
    elseif remaining <= 60 then
        return "medium"
    else
        return "slow"
    end
end

-- Register an aura for centralized updates
function BoxxyAuras.UpdateManager:RegisterAura(auraIcon)
    if not auraIcon or not auraIcon.frame then
        return
    end

    -- Clear any existing OnUpdate script
    auraIcon.frame:SetScript("OnUpdate", nil)

    -- Determine which tier to add to
    local tier = self:GetTierForAura(auraIcon)
    if not tier then
        return -- Permanent auras don't need updates
    end

    -- Remove from other tiers first (in case it's being moved)
    self:UnregisterAura(auraIcon)

    -- Add to appropriate tier
    table.insert(self.auras[tier], auraIcon)
    auraIcon.updateTier = tier

    if BoxxyAuras.DEBUG then
        print(string.format("UpdateManager: Registered '%s' in %s tier", auraIcon.name or "Unknown", tier))
    end
end

-- Unregister an aura from all update tiers
function BoxxyAuras.UpdateManager:UnregisterAura(auraIcon)
    if not auraIcon then
        return
    end

    for tierName, tierList in pairs(self.auras) do
        for i = #tierList, 1, -1 do
            if tierList[i] == auraIcon then
                table.remove(tierList, i)
                if BoxxyAuras.DEBUG then
                    print(string.format("UpdateManager: Unregistered '%s' from %s tier", auraIcon.name or "Unknown",
                        tierName))
                end
                break
            end
        end
    end

    auraIcon.updateTier = nil
end

-- Process a tier of auras
function BoxxyAuras.UpdateManager:ProcessTier(tierName, currentTime)
    local tierList = self.auras[tierName]
    if not tierList then
        return
    end

    for i = #tierList, 1, -1 do
        local auraIcon = tierList[i]

        -- Check if aura still exists and is valid
        if not auraIcon or not auraIcon.frame or not auraIcon.frame:IsShown() then
            table.remove(tierList, i)
        else
            -- Update the aura (call as function, not method)
            local AuraIcon = BoxxyAuras.AuraIcon
            if AuraIcon and AuraIcon.UpdateDurationDisplay then
                AuraIcon.UpdateDurationDisplay(auraIcon, currentTime)
            end

            -- Check if aura needs to move to a different tier
            local correctTier = self:GetTierForAura(auraIcon)
            if correctTier and correctTier ~= tierName then
                -- Move to correct tier
                table.remove(tierList, i)
                table.insert(self.auras[correctTier], auraIcon)
                auraIcon.updateTier = correctTier

                if BoxxyAuras.DEBUG then
                    print(string.format("UpdateManager: Moved '%s' from %s to %s tier",
                        auraIcon.name or "Unknown", tierName, correctTier))
                end
            elseif not correctTier then
                -- Aura no longer needs updates (became permanent or invalid)
                table.remove(tierList, i)
                auraIcon.updateTier = nil
            end
        end
    end
end

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
    },                                                         -- Main frame hover BG
    HoverBorderColor = { r = 0.8, g = 0.8, b = 0.8, a = 0.5 }, -- Color for the hover border
    HoverBorderTextureKey = "ThickBorder",                     -- Texture key from UIUtils.lua for the hover border
    TextHeight = 8,
    Padding = 6,                                               -- Internal padding within AuraIcon frame
    FramePadding = 18,                                         -- Padding between frame edge and icons
    IconSpacing = 0,                                           -- Spacing between icons

    -- Dynamic Shake Configuration
    MinShakeScale = 2,               -- Minimum visual scale of the shake effect
    MaxShakeScale = 6,               -- Maximum visual scale of the shake effect
    MinDamagePercentForShake = 0.01, -- Damage as % of max health to trigger MinShakeScale (e.g., 0.01 = 1%)
    MaxDamagePercentForShake = 0.10  -- Damage as % of max health to trigger MaxShakeScale (e.g., 0.10 = 10%)
}

BoxxyAuras.FrameHoverStates = {
    BuffFrame = false,
    DebuffFrame = false,
    CustomFrame = false
}

-- <<< UPDATED: Per-frame hover and timer tracking >>>
BoxxyAuras.FrameHoverTimers = {}                                                     -- Track individual timers for each frame
BoxxyAuras.FrameVisualHoverStates = {}                                               -- Track visual hover states (instant, no timer)
BoxxyAuras.FrameLeaveTimers = {}                                                     -- Legacy - kept for compatibility

local customDisplayFrame = CreateFrame("Frame", "BoxxyCustomDisplayFrame", UIParent) -- NEW Custom Frame
BoxxyAuras.customIcons = {}                                                          -- NEW Custom Icon List

-- Create the main addon frame
local mainFrame = CreateFrame("Frame", "BoxxyAurasMainFrame", UIParent) -- No template needed now
local defaultMainFrameSettings = {                                      -- Define defaults
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

local iconSpacing = 4       -- Keep local if only used here?

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
        defaultWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(defaultIconsWide_Reset, defaultIconSize_ForCalc, 0) or
            defaultWidth
    end

    return {
        lockFrames = false,
        hideBlizzardAuras = true,
        showHoverBorder = true,                                            -- Enable hover border by default
        optionsScale = 1.0,
        normalBorderColor = { r = 0.498, g = 0.498, b = 0.498, a = 1.0 },  -- Default normal border color (127,127,127)
        normalBackgroundColor = { r = 0.15, g = 0.15, b = 0.15, a = 1.0 }, -- Default background color (25,25,25)
        customAuraNames = {},
        buffFrameSettings = {
            -- Default: lower of the three bars, roughly top-middle of the screen
            x = 0,
            y = -180,       -- 180px below the top edge
            anchor = "TOP", -- anchor to top of UIParent for consistency across resolutions
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            buffTextAlign = "CENTER",
            iconSize = 24,
            textSize = 8,
            borderSize = 1,
            iconSpacing = 0,
            wrapDirection = "DOWN",
            width = defaultWidth
        },
        debuffFrameSettings = {
            -- Positioned above the Buff bar
            x = 0,
            y = -120,
            anchor = "TOP",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            debuffTextAlign = "CENTER",
            iconSize = 24,
            textSize = 8,
            borderSize = 1,
            iconSpacing = 0,
            wrapDirection = "DOWN",
            width = defaultWidth
        },
        customFrameSettings = {
            -- Highest bar in the default stack
            x = 0,
            y = -60,
            anchor = "TOP",
            height = defaultMinHeight,
            numIconsWide = defaultIconsWide_Reset,
            customTextAlign = "CENTER",
            iconSize = 24,
            textSize = 8,
            borderSize = 1,
            iconSpacing = 0,
            wrapDirection = "DOWN",
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
    if profile.showHoverBorder == nil then
        profile.showHoverBorder = true
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

    -- Ensure iconSpacing exists for all frame types
    if profile.buffFrameSettings.iconSpacing == nil then
        profile.buffFrameSettings.iconSpacing = 0
    end
    if profile.debuffFrameSettings.iconSpacing == nil then
        profile.debuffFrameSettings.iconSpacing = 0
    end
    if profile.customFrameSettings.iconSpacing == nil then
        profile.customFrameSettings.iconSpacing = 0
    end

    -- Ensure wrapDirection exists for all frame types
    if profile.buffFrameSettings.wrapDirection == nil then
        profile.buffFrameSettings.wrapDirection = "DOWN"
    end
    if profile.debuffFrameSettings.wrapDirection == nil then
        profile.debuffFrameSettings.wrapDirection = "DOWN"
    end
    if profile.customFrameSettings.wrapDirection == nil then
        profile.customFrameSettings.wrapDirection = "DOWN"
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

    -- Ensure normalBorderColor exists
    if profile.normalBorderColor == nil then
        profile.normalBorderColor = { r = 0.498, g = 0.498, b = 0.498, a = 0.8 }
    end

    -- Ensure normalBackgroundColor exists
    if profile.normalBackgroundColor == nil then
        profile.normalBackgroundColor = { r = 0.098, g = 0.098, b = 0.098, a = 1.0 }
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

    -- Clear all existing auras and return icons to their pools
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        BoxxyAuras.auraTracking[frameType] = {}

        if not BoxxyAuras.iconPools[frameType] then BoxxyAuras.iconPools[frameType] = {} end
        local iconPool = BoxxyAuras.iconPools[frameType]

        if BoxxyAuras.iconArrays[frameType] then
            for _, icon in ipairs(BoxxyAuras.iconArrays[frameType]) do
                if icon and icon.frame then
                    -- Use the comprehensive Reset method instead of manual cleanup
                    if icon.Reset then
                        icon:Reset()
                    else
                        -- Fallback for older icon instances
                        icon.frame:Hide()
                        icon.frame:SetScript("OnUpdate", nil)
                    end
                    table.insert(iconPool, icon)
                end
            end
        end

        BoxxyAuras.iconArrays[frameType] = {}
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
        local buffSlots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
        local debuffSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }

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
                slot = 0,                    -- Demo auras don't have real slots
                auraType = "CUSTOM",
                originalAuraType = "HELPFUL" -- Default to helpful for custom demo auras
            }
            if aurasByFrame["Custom"] then
                table.insert(aurasByFrame["Custom"], auraData)
            end
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
        local iconPool = BoxxyAuras.iconPools[frameType] or {}

        -- Determine aura filter for this frame type
        local auraFilter = "HELPFUL"
        if frameType == "Debuff" then
            auraFilter = "HARMFUL"
        elseif frameType == "Custom" then
            auraFilter = "CUSTOM"
        end

        -- Create icons for each aura
        for i, auraData in ipairs(auras) do
            local icon = table.remove(iconPool)
            if not icon then
                local baseNamePrefix = "BoxxyAuras" .. frameType .. "Icon"
                BoxxyAuras.iconCounters[frameType] = BoxxyAuras.iconCounters[frameType] + 1
                icon = AuraIcon.New(frame, BoxxyAuras.iconCounters[frameType], baseNamePrefix)
            end

            BoxxyAuras.iconArrays[frameType][i] = icon
            if icon and icon.newAuraAnimGroup then
                icon.newAuraAnimGroup:Play()
            end

            icon:Update(auraData, i, auraFilter)
            icon.frame:Show()
        end
    end

    -- Update layout in all frames
    BoxxyAuras.FrameHandler.UpdateAllFramesAuras()
end

-- Function to update auras for a single frame (targeted update)
BoxxyAuras.UpdateSingleFrameAuras = function(frameType)
    if not BoxxyAuras.Frames or not BoxxyAuras.Frames[frameType] then
        if BoxxyAuras.DEBUG then
            print("UpdateSingleFrameAuras: Frame not found: " .. tostring(frameType))
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

    local frame = BoxxyAuras.Frames[frameType]

    -- Initialize tracking lists for this frame type if they don't exist
    if not BoxxyAuras.auraTracking[frameType] then
        BoxxyAuras.auraTracking[frameType] = {}
    end
    if not BoxxyAuras.iconArrays[frameType] then
        BoxxyAuras.iconArrays[frameType] = {}
    end
    if not BoxxyAuras.iconPools[frameType] then
        BoxxyAuras.iconPools[frameType] = {}
    end

    local newAuraList = BoxxyAuras:GetSortedAurasForFrame(frameType)
    local trackedAuras = BoxxyAuras.auraTracking[frameType] or {}
    local iconArray = BoxxyAuras.iconArrays[frameType] or {}
    local iconPool = BoxxyAuras.iconPools[frameType] or {}

    -- Create a lookup for the new auras for quick checks
    local newAuraLookup = {}
    for _, aura in ipairs(newAuraList) do
        newAuraLookup[aura.auraInstanceID] = true
    end

    -- Check for expired auras that should be held
    local frameKey = frame:GetName() or frameType
    local shouldHoldExpiredAuras = BoxxyAuras.FrameHoverStates[frameType] or BoxxyAuras.FrameHoverTimers[frameKey]

    if shouldHoldExpiredAuras then
        for _, trackedAura in ipairs(trackedAuras) do
            if trackedAura and not newAuraLookup[trackedAura.auraInstanceID] then
                -- This aura expired and we are (or were recently) hovering the frame, so hold it.
                trackedAura.forceExpired = true
                table.insert(newAuraList, trackedAura)
                newAuraLookup[trackedAura.auraInstanceID] = true -- Add to lookup to prevent re-adding
                if BoxxyAuras.DEBUG then
                    print(string.format("Single frame update: Holding expired aura '%s' in frame %s",
                        trackedAura.name or "Unknown", frameType))
                end
            end
        end
    end

    -- Re-sort the list if we added expired auras, to maintain order
    table.sort(newAuraList, SortAurasForDisplay)

    -- Create a lookup of existing aura instance IDs for efficient matching
    local existingAuraLookup = {}
    for i, auraData in ipairs(trackedAuras) do
        if auraData and auraData.auraInstanceID then
            existingAuraLookup[auraData.auraInstanceID] = { data = auraData, visualIndex = i }
        end
    end

    local newTrackedAuras = {}
    local newIconArray = {}
    local usedIcons = {} -- Keep track of icons from the old array that are being kept

    -- Iterate through the NEW list of auras
    for i, newAuraData in ipairs(newAuraList) do
        local newInstanceID = newAuraData.auraInstanceID
        local existing = existingAuraLookup[newInstanceID]
        local icon

        if existing then
            -- Aura already exists, reuse its icon
            icon = iconArray[existing.visualIndex]
            usedIcons[existing.visualIndex] = true
        else
            -- This is a completely new aura, get an icon from the pool
            icon = BoxxyAuras.GetOrCreateIcon(iconPool, i, frame, "BoxxyAuras" .. frameType .. "Icon")
            if icon and icon.newAuraAnimGroup then
                icon.newAuraAnimGroup:Play() -- Play new aura animation
            end

            -- Trigger tooltip scrape for the new aura
            if newAuraData.auraInstanceID and BoxxyAuras.AttemptTooltipScrape then
                local filter = newAuraData.auraType or (frameType == "Debuff" and "HARMFUL" or "HELPFUL")
                BoxxyAuras.AttemptTooltipScrape(newAuraData.spellId, newAuraData.auraInstanceID, filter)
            end
        end

        if icon then
            local auraFilter = (frameType == "Debuff") and "HARMFUL" or "HELPFUL"
            if BoxxyAuras.DEBUG and newAuraData.forceExpired then
                print(string.format("Single frame update: Updating icon for expired aura '%s' with forceExpired = %s",
                    newAuraData.name or "Unknown", tostring(newAuraData.forceExpired)))
            end
            icon:Update(newAuraData, i, auraFilter)
            icon.frame:Show()
            newIconArray[i] = icon
        end

        newTrackedAuras[i] = newAuraData
    end

    -- Return any unused icons to the pool
    for i, icon in ipairs(iconArray) do
        if not usedIcons[i] then
            BoxxyAuras.ReturnIconToPool(iconPool, icon)
        end
    end

    -- Replace the old tracking lists with the new ones
    BoxxyAuras.auraTracking[frameType] = newTrackedAuras
    BoxxyAuras.iconArrays[frameType] = newIconArray

    -- Update layout for this specific frame
    BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
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

    -- Re-fetch, sort, and filter all auras using the new helper function
    local aurasByFrame = {}
    for frameType, _ in pairs(BoxxyAuras.Frames) do
        aurasByFrame[frameType] = BoxxyAuras:GetSortedAurasForFrame(frameType)
    end

    -- Loop through each frame type to update its icons
    for frameType, newAuraList in pairs(aurasByFrame) do
        local frame = BoxxyAuras.Frames[frameType]
        if frame then
            local trackedAuras = BoxxyAuras.auraTracking[frameType] or {}
            local iconArray = BoxxyAuras.iconArrays[frameType] or {}
            local iconPool = BoxxyAuras.iconPools[frameType] or {}

            -- Create a lookup for the new auras for quick checks
            local newAuraLookup = {}
            for _, aura in ipairs(newAuraList) do
                newAuraLookup[aura.auraInstanceID] = true
            end

            -- Check for expired auras that should be held
            -- We check both current hover state AND if the frame has any pending timer
            local frameKey = frame:GetName() or frameType
            local shouldHoldExpiredAuras = BoxxyAuras.FrameHoverStates[frameType] or
                BoxxyAuras.FrameHoverTimers[frameKey]

            if shouldHoldExpiredAuras then
                for _, trackedAura in ipairs(trackedAuras) do
                    if trackedAura and not newAuraLookup[trackedAura.auraInstanceID] then
                        -- This aura expired and we are (or were recently) hovering the frame, so hold it.
                        trackedAura.forceExpired = true
                        table.insert(newAuraList, trackedAura)
                        newAuraLookup[trackedAura.auraInstanceID] = true -- Add to lookup to prevent re-adding
                        if BoxxyAuras.DEBUG then
                            print(string.format("Holding expired aura '%s' in frame %s (hovered=%s, timer=%s)",
                                trackedAura.name or "Unknown", frameType,
                                tostring(BoxxyAuras.FrameHoverStates[frameType]),
                                tostring(BoxxyAuras.FrameHoverTimers[frameKey] ~= nil)))
                        end
                    end
                end
            end

            -- Re-sort the list if we added expired auras, to maintain order
            table.sort(newAuraList, SortAurasForDisplay)

            -- Create a lookup of existing aura instance IDs for efficient matching
            local existingAuraLookup = {}
            for i, auraData in ipairs(trackedAuras) do
                if auraData and auraData.auraInstanceID then
                    existingAuraLookup[auraData.auraInstanceID] = { data = auraData, visualIndex = i }
                end
            end

            local newTrackedAuras = {}
            local newIconArray = {}
            local usedIcons = {} -- Keep track of icons from the old array that are being kept

            -- 1. Iterate through the NEW list of auras
            for i, newAuraData in ipairs(newAuraList) do
                local newInstanceID = newAuraData.auraInstanceID
                local existing = existingAuraLookup[newInstanceID]
                local icon

                if existing then
                    -- Aura already exists, reuse its icon
                    icon = iconArray[existing.visualIndex]
                    usedIcons[existing.visualIndex] = true
                else
                    -- This is a completely new aura, get an icon from the pool
                    icon = BoxxyAuras.GetOrCreateIcon(iconPool, i, frame, "BoxxyAuras" .. frameType .. "Icon")
                    if icon and icon.newAuraAnimGroup then
                        icon.newAuraAnimGroup:Play() -- Play new aura animation
                    end

                    -- Trigger tooltip scrape for the new aura
                    if newAuraData.auraInstanceID and BoxxyAuras.AttemptTooltipScrape then
                        local filter = newAuraData.auraType or (frameType == "Debuff" and "HARMFUL" or "HELPFUL")
                        BoxxyAuras.AttemptTooltipScrape(newAuraData.spellId, newAuraData.auraInstanceID, filter)
                    end
                end

                if icon then
                    local auraFilter = (frameType == "Debuff") and "HARMFUL" or "HELPFUL"
                    if BoxxyAuras.DEBUG and newAuraData.forceExpired then
                        print(string.format("Updating icon for expired aura '%s' with forceExpired = %s",
                            newAuraData.name or "Unknown", tostring(newAuraData.forceExpired)))
                    end
                    icon:Update(newAuraData, i, auraFilter)
                    icon.frame:Show()
                    newIconArray[i] = icon
                end

                -- The new list of tracked auras is simply the new list from the game
                newTrackedAuras[i] = newAuraData
            end

            -- 2. Return any unused icons to the pool
            for i, icon in ipairs(iconArray) do
                if not usedIcons[i] then
                    BoxxyAuras.ReturnIconToPool(iconPool, icon)
                end
            end

            -- 3. Replace the old tracking lists with the new ones
            BoxxyAuras.auraTracking[frameType] = newTrackedAuras
            BoxxyAuras.iconArrays[frameType] = newIconArray
        else
            if BoxxyAuras.DEBUG then
                print("UpdateAuras: Skipping update for non-existent frame: " .. tostring(frameType))
            end
        end
    end

    -- Finally, update the layout in all frames
    BoxxyAuras.FrameHandler.UpdateAllFramesAuras()
end

function BoxxyAuras.GetOrCreateIcon(pool, index, parent, baseNamePrefix)
    local icon = table.remove(pool)
    if not icon then
        local AuraIcon = BoxxyAuras.AuraIcon
        if not AuraIcon then return nil end
        BoxxyAuras.iconCounters[parent:GetName()] = (BoxxyAuras.iconCounters[parent:GetName()] or 0) + 1
        icon = AuraIcon.New(parent, BoxxyAuras.iconCounters[parent:GetName()], baseNamePrefix)
    end
    return icon
end

function BoxxyAuras.ReturnIconToPool(pool, icon)
    if icon and icon.frame then
        if icon.Reset then
            icon:Reset()
        else
            -- Fallback for older/simpler icons
            icon.frame:Hide()
            icon.frame:SetScript("OnUpdate", nil)
        end
        table.insert(pool, icon)
    end
end

function BoxxyAuras:GetSortedAurasForFrame(frameType)
    local allAuras = {}
    local currentSettings = self:GetCurrentProfileSettings()

    -- Determine which auras to fetch based on demo mode
    if self.Options and self.Options.demoModeActive and self.demoAuras then
        if self.demoAuras and self.demoAuras[frameType] then
            for _, demoAura in ipairs(self.demoAuras[frameType]) do
                local auraData = {
                    name = demoAura.name,
                    icon = demoAura.icon,
                    duration = demoAura.duration,
                    expirationTime = demoAura.expirationTime,
                    applications = demoAura.applications,
                    spellId = demoAura.spellId,
                    auraInstanceID = demoAura.auraInstanceID,
                    slot = 0,
                    auraType = frameType == "Debuff" and "HARMFUL" or "HELPFUL",
                    dispelName = demoAura.dispelName
                }
                table.insert(allAuras, auraData)
            end
        end
    else
        -- Fetch live auras from the game
        if frameType == "Custom" then
            -- For Custom, we need to check both buffs and debuffs
            local filters = { "HELPFUL", "HARMFUL" }
            for _, filter in ipairs(filters) do
                if C_UnitAuras and C_UnitAuras.GetAuraSlots then
                    local auraSlots = { C_UnitAuras.GetAuraSlots("player", filter) }
                    for i = 2, #auraSlots do
                        local slot = auraSlots[i]
                        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
                        if auraData then
                            auraData.slot = slot
                            auraData.auraType = filter
                            table.insert(allAuras, auraData)
                        end
                    end
                end
            end
        else
            -- For Buff/Debuff, fetch only the specific type
            local filter = (frameType == "Debuff") and "HARMFUL" or "HELPFUL"
            if C_UnitAuras and C_UnitAuras.GetAuraSlots then
                local auraSlots = { C_UnitAuras.GetAuraSlots("player", filter) }
                for i = 2, #auraSlots do
                    local slot = auraSlots[i]
                    local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
                    if auraData then
                        auraData.slot = slot
                        auraData.auraType = filter
                        table.insert(allAuras, auraData)
                    end
                end
            end
        end
    end

    -- For Buff and Debuff frames, we need to filter out auras designated for the Custom frame
    local customNamesLookup = {}
    if currentSettings.customAuraNames then
        for name, _ in pairs(currentSettings.customAuraNames) do
            customNamesLookup[string.lower(name)] = true
        end
    end

    if frameType == "Buff" or frameType == "Debuff" then
        local filteredAuras = {}
        for _, auraData in ipairs(allAuras) do
            if not customNamesLookup[string.lower(auraData.name or "")] then
                table.insert(filteredAuras, auraData)
            end
        end
        allAuras = filteredAuras
    elseif frameType == "Custom" then
        local filteredAuras = {}
        for _, auraData in ipairs(allAuras) do
            if customNamesLookup[string.lower(auraData.name or "")] then
                table.insert(filteredAuras, auraData)
            end
        end
        allAuras = filteredAuras
    end

    table.sort(allAuras, SortAurasForDisplay)
    return allAuras
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

-- Helper function to check if a frame is currently hovered (for external use)
function BoxxyAuras.IsFrameHovered(frameType)
    return BoxxyAuras.FrameHoverStates[frameType] or false
end

-- Helper function to check if a frame is visually hovered (instant, no timer)
function BoxxyAuras.IsFrameVisuallyHovered(frameType)
    return BoxxyAuras.FrameVisualHoverStates[frameType] or false
end

-- Debug function to check LibWindow registration and position data
function BoxxyAuras:DebugFramePositions()
    if not BoxxyAuras.DEBUG then
        print("Enable BoxxyAuras.DEBUG = true first")
        return
    end

    local currentSettings = self:GetCurrentProfileSettings()
    print("=== BoxxyAuras Frame Position Debug ===")
    print("Active Profile:", self:GetActiveProfileName())

    for frameType, frame in pairs(self.Frames or {}) do
        local settingsKey = self.FrameHandler.GetSettingsKeyFromFrameType(frameType)
        print(string.format("\n%s Frame (%s):", frameType, frame:GetName() or "unnamed"))
        print("  Settings Key:", settingsKey)

        if settingsKey and currentSettings[settingsKey] then
            local settings = currentSettings[settingsKey]
            print("  Position Data:")
            for key, value in pairs(settings) do
                if key == "x" or key == "y" or key == "point" or key == "anchor" or key == "scale" then
                    print(string.format("    %s: %s", key, tostring(value)))
                end
            end

            local x, y = frame:GetCenter()
            if x and y then
                print(string.format("  Current Position: %.2f, %.2f", x, y))
            end
        else
            print("  No position data found!")
        end
    end
    print("=== End Debug ===")
end

-- Update SetTrackedAuras to use the new auraTracking table
function BoxxyAuras.SetTrackedAuras(frameType, newList)
    if not BoxxyAuras.auraTracking then
        BoxxyAuras.auraTracking = {}
    end

    BoxxyAuras.auraTracking[frameType] = newList
end

-- Central Update Manager Frame
local updateManagerFrame = CreateFrame("Frame")
updateManagerFrame:SetScript("OnUpdate", function(_, elapsed)
    local mgr = BoxxyAuras.UpdateManager
    local currentTime = GetTime()

    -- Update all timers every frame
    mgr.lastFastUpdate = mgr.lastFastUpdate + elapsed
    mgr.lastMediumUpdate = mgr.lastMediumUpdate + elapsed
    mgr.lastSlowUpdate = mgr.lastSlowUpdate + elapsed

    -- Process fast tier (0.1s intervals)
    if mgr.lastFastUpdate >= 0.1 then
        mgr:ProcessTier("fast", currentTime)
        mgr.lastFastUpdate = 0
    end

    -- Process medium tier (0.5s intervals)
    if mgr.lastMediumUpdate >= 0.5 then
        mgr:ProcessTier("medium", currentTime)
        mgr.lastMediumUpdate = 0
    end

    -- Process slow tier (1.0s intervals)
    if mgr.lastSlowUpdate >= 1.0 then
        mgr:ProcessTier("slow", currentTime)
        mgr.lastSlowUpdate = 0
    end
end)

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Combat end event

-- Key event handling frame for arrow key nudging
local keyEventFrame = CreateFrame("Frame")

-- Function to enable keyboard handling (only when unlocked)
function BoxxyAuras.EnableKeyboardHandling()
    if InCombatLockdown() then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Cannot enable keyboard handling during combat")
        end
        return false
    end

    if not keyEventFrame:IsKeyboardEnabled() then
        keyEventFrame:SetPropagateKeyboardInput(true)
        keyEventFrame:EnableKeyboard(true)
        keyEventFrame:SetFrameStrata("HIGH")
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Enabled keyboard handling for arrow key nudging")
        end
    end
    return true
end

-- Function to disable keyboard handling (when locked)
function BoxxyAuras.DisableKeyboardHandling()
    if InCombatLockdown() then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Cannot disable keyboard handling during combat")
        end
        return false
    end

    if keyEventFrame:IsKeyboardEnabled() then
        keyEventFrame:EnableKeyboard(false)
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Disabled keyboard handling (frames locked)")
        end
    end
    return true
end

keyEventFrame:SetScript("OnKeyDown", function(self, key)
    -- Don't handle key events during combat (protected functions)
    if InCombatLockdown() then
        return
    end

    -- Reset propagation to true first (default state)
    self:SetPropagateKeyboardInput(true)

    -- Find which frame is currently hovered (keyboard handling only enabled when unlocked)
    local hoveredFrame = nil
    local hoveredFrameType = nil
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if BoxxyAuras.FrameHoverStates[frameType] then
            hoveredFrame = frame
            hoveredFrameType = frameType
            break
        end
    end

    if not hoveredFrame then
        return
    end

    -- Handle arrow key movement
    local deltaX, deltaY = 0, 0
    if key == "LEFT" then
        deltaX = -1
    elseif key == "RIGHT" then
        deltaX = 1
    elseif key == "UP" then
        deltaY = 1
    elseif key == "DOWN" then
        deltaY = -1
    else
        return -- Not an arrow key, let other handlers process it
    end

    -- We're handling an arrow key, so don't propagate it
    self:SetPropagateKeyboardInput(false)

    -- Move the frame
    local currentX, currentY = hoveredFrame:GetCenter()
    if currentX and currentY then
        hoveredFrame:ClearAllPoints()
        hoveredFrame:SetPoint("CENTER", UIParent, "CENTER",
            (currentX - UIParent:GetWidth() / 2) + deltaX,
            (currentY - UIParent:GetHeight() / 2) + deltaY)

        -- Save the new position using LibWindow
        if LibWindow and LibWindow.SavePosition then
            LibWindow.SavePosition(hoveredFrame)
        end

        if BoxxyAuras.DEBUG then
            print(string.format("Nudged %s frame by (%d, %d)", hoveredFrameType, deltaX, deltaY))
        end
    end
end)

-- Add OnKeyUp handler to ensure proper key propagation reset
keyEventFrame:SetScript("OnKeyUp", function(self, key)
    -- Don't handle key events during combat (protected functions)
    if InCombatLockdown() then
        return
    end

    -- Always reset propagation on key release
    self:SetPropagateKeyboardInput(true)
end)

-- Keyboard handling will be enabled/disabled by ApplyLockState based on frame lock state
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= addonNameString then return end

        -- Initialize the database and default profile structure
        BoxxyAurasDB = BoxxyAurasDB or {}
        BoxxyAurasDB.profiles = BoxxyAurasDB.profiles or {}
        BoxxyAurasDB.characterProfileMap = BoxxyAurasDB.characterProfileMap or {}
        BoxxyAuras.iconPools = BoxxyAuras.iconPools or {} -- << FIX: Initialize icon pools

        -- Ensure a default profile exists on first ever load
        if not BoxxyAurasDB.profiles["Default"] then
            BoxxyAurasDB.profiles["Default"] = BoxxyAuras:GetDefaultProfileSettings()
        end
        BoxxyAurasDB.activeProfile = BoxxyAurasDB.activeProfile or "Default"

        -- Set the character's profile
        local charKey = BoxxyAuras:GetCharacterKey()
        if not BoxxyAurasDB.characterProfileMap[charKey] then
            BoxxyAurasDB.characterProfileMap[charKey] = BoxxyAurasDB.activeProfile
        else
            BoxxyAurasDB.activeProfile = BoxxyAurasDB.characterProfileMap[charKey]
        end

        -- <<< FIX: Initialize frames BEFORE loading options >>>
        if BoxxyAuras.FrameHandler and BoxxyAuras.FrameHandler.InitializeFrames then
            BoxxyAuras.FrameHandler.InitializeFrames()
        end

        -- Now that frames exist, create and load the options menu
        if BoxxyAuras.Options and BoxxyAuras.Options.Create then
            BoxxyAuras.Options:Create()
            BoxxyAuras.Options:Load()
        end

        -- Apply settings to the newly created frames
        if BoxxyAuras.FrameHandler.ApplySettings then
            for _, frameType in ipairs({ "Buff", "Debuff", "Custom" }) do
                BoxxyAuras.FrameHandler.ApplySettings(frameType)
            end
        end
    elseif event == "PLAYER_LOGIN" then
        -- This event runs after ADDON_LOADED when the player is in the world.
        -- Frames and settings are already loaded. Now we can show things.
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        BoxxyAuras.ApplyBlizzardAuraVisibility(currentSettings.hideBlizzardAuras)

        -- Initialize the aura tracking systems
        local success, err = pcall(InitializeAuras)
        if not success then
            BoxxyAuras.DebugLogError("Error in InitializeAuras (pcall): " .. tostring(err))
        end

        -- Force a full update on login to ensure all auras are displayed correctly
        BoxxyAuras.UpdateAuras(true)

        -- Apply initial lock state and restore positions
        C_Timer.After(0.1, function()
            local finalSettings = BoxxyAuras:GetCurrentProfileSettings()

            -- First restore positions for all frames
            if LibWindow then
                for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
                    if frame then
                        LibWindow.RestorePosition(frame)
                        if BoxxyAuras.DEBUG then
                            print(string.format("Restored position for %s frame during login", frameType))
                        end
                    end
                end
            end

            -- Then apply lock state if needed
            if finalSettings.lockFrames then
                BoxxyAuras.FrameHandler.ApplyLockState(true)
                if BoxxyAuras.DEBUG then
                    print("Applied lock state during login")
                end
            end
        end)
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
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended, check if we need to enable keyboard handling based on lock state
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if currentSettings and not currentSettings.lockFrames then
            BoxxyAuras.EnableKeyboardHandling()
        end
    end
end)

function BoxxyAuras.ApplyBlizzardAuraVisibility(shouldHide)
    local buffFrame = _G['BuffFrame']
    local debuffFrame = _G['DebuffFrame']

    if buffFrame and debuffFrame then
        -- Store original Show methods if we haven't already (or if they were nil before)
        if not BoxxyAuras.origBuffFrameShow and buffFrame.Show then
            BoxxyAuras.origBuffFrameShow = buffFrame.Show
        end
        if not BoxxyAuras.origDebuffFrameShow and debuffFrame.Show then
            BoxxyAuras.origDebuffFrameShow = debuffFrame.Show
        end

        if shouldHide then
            buffFrame:Hide()
            debuffFrame:Hide()
            buffFrame.Show = function() end
            debuffFrame.Show = function() end
        else
            -- Restore original Show methods if we have them
            if BoxxyAuras.origBuffFrameShow then
                buffFrame.Show = BoxxyAuras.origBuffFrameShow
            end
            if BoxxyAuras.origDebuffFrameShow then
                debuffFrame.Show = BoxxyAuras.origDebuffFrameShow
            end
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

    -- Obtain a reference to the settings that we just switched to for convenience
    local currentSettings = self:GetCurrentProfileSettings() or {}

    ------------------------------------------------------------------
    -- 1. Apply frame-level settings (width/scale/icon layout etc.)
    ------------------------------------------------------------------
    if self.FrameHandler and self.FrameHandler.ApplySettings then
        local frameTypes = { "Buff", "Debuff", "Custom" }
        for _, frameType in ipairs(frameTypes) do
            self.FrameHandler.ApplySettings(frameType)
        end
    end

    ------------------------------------------------------------------
    -- 2. Re-register and restore frame positions for this profile (LibWindow)
    ------------------------------------------------------------------
    if LibWindow and self.Frames then
        for frameType, frame in pairs(self.Frames) do
            if frame then
                -- Re-register the frame with the correct settings path for this profile
                local settingsKey = self.FrameHandler.GetSettingsKeyFromFrameType(frameType)
                if settingsKey then
                    -- Ensure the settings table exists
                    if not currentSettings[settingsKey] then
                        currentSettings[settingsKey] = {}
                    end

                    -- Re-register with LibWindow using the correct settings table
                    LibWindow.RegisterConfig(frame, currentSettings[settingsKey])

                    -- Now restore the position
                    LibWindow.RestorePosition(frame)

                    if BoxxyAuras.DEBUG then
                        print(string.format("Re-registered and restored position for %s frame", frameType))
                    end
                else
                    BoxxyAuras.DebugLogError("Could not determine settings key for frame type: " .. tostring(frameType))
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- 3. Apply lock/unlock state for frames
    ------------------------------------------------------------------
    if self.FrameHandler and self.FrameHandler.ApplyLockState and currentSettings.lockFrames ~= nil then
        self.FrameHandler.ApplyLockState(currentSettings.lockFrames)
    end

    ------------------------------------------------------------------
    -- 4. Apply Blizzard aura visibility according to profile setting
    ------------------------------------------------------------------
    if currentSettings.hideBlizzardAuras ~= nil then
        self.ApplyBlizzardAuraVisibility(currentSettings.hideBlizzardAuras)
    end

    ------------------------------------------------------------------
    -- 5. Refresh border/background colors for all existing icons
    ------------------------------------------------------------------
    if self.Options then
        if self.Options.ApplyNormalBorderColorChange then
            self.Options:ApplyNormalBorderColorChange()
        end
        if self.Options.ApplyBackgroundColorChange then
            self.Options:ApplyBackgroundColorChange()
        end
    end

    ------------------------------------------------------------------
    -- 6. Finally trigger a full aura update so icon durations, sizes, etc. refresh
    ------------------------------------------------------------------
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
    local hoverColor = BoxxyAuras.Config.HoverBorderColor
    local currentTime = GetTime()

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

    -- === NEW: Per-Frame Hover Management ===
    local frameMouseIsCurrentlyIn = nil
    local framesNeedingUpdate = {}

    -- Check each frame individually
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if frame and frame:IsVisible() then
            local frameKey = frame:GetName() or frameType
            local mouseInThisFrame = BoxxyAuras.IsMouseWithinFrame(frame) or
                BoxxyAuras.FrameHandler.IsMouseOverAnyIcon(frame)

            -- === VISUAL HOVER STATE (instant, no timer) ===
            local wasVisuallyHovered = BoxxyAuras.FrameVisualHoverStates[frameType]
            BoxxyAuras.FrameVisualHoverStates[frameType] = mouseInThisFrame

            -- === AURA PERSISTENCE STATE (with timer) ===
            if mouseInThisFrame then
                frameMouseIsCurrentlyIn = frame -- For legacy compatibility

                -- Mouse entered this frame
                if not BoxxyAuras.FrameHoverStates[frameType] then
                    if BoxxyAuras.DEBUG then
                        print("Mouse entered frame: " .. frameKey)
                    end
                    BoxxyAuras.FrameHoverStates[frameType] = true
                    framesNeedingUpdate[frameType] = true
                end

                -- Cancel any pending timer for this frame
                if BoxxyAuras.FrameHoverTimers[frameKey] then
                    if BoxxyAuras.DEBUG then
                        print("Cancelled leave timer for frame: " .. frameKey)
                    end
                    BoxxyAuras.FrameHoverTimers[frameKey] = nil
                end
            else
                -- Mouse not in this frame
                if BoxxyAuras.FrameHoverStates[frameType] and not BoxxyAuras.FrameHoverTimers[frameKey] then
                    -- We were hovering but mouse left and no timer is running - start timer
                    if BoxxyAuras.DEBUG then
                        print("Mouse left frame: " .. frameKey .. ", starting 1-second timer")
                    end
                    BoxxyAuras.FrameHoverTimers[frameKey] = currentTime + 1.0
                end

                -- Check if timer expired for this frame
                if BoxxyAuras.FrameHoverTimers[frameKey] and currentTime >= BoxxyAuras.FrameHoverTimers[frameKey] then
                    if BoxxyAuras.DEBUG then
                        print("Hover timer expired for frame: " .. frameKey)
                    end
                    BoxxyAuras.FrameHoverStates[frameType] = false
                    BoxxyAuras.FrameHoverTimers[frameKey] = nil
                    framesNeedingUpdate[frameType] = true
                end
            end
        end
    end

    -- Legacy compatibility: set global HoveredFrame to the first frame that's currently hovered
    BoxxyAuras.HoveredFrame = nil
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if BoxxyAuras.FrameHoverStates[frameType] then
            BoxxyAuras.HoveredFrame = frame
            break
        end
    end

    -- Keep legacy mouse tracking for other potential uses
    BoxxyAuras.MouseInFrameGeometry = frameMouseIsCurrentlyIn

    -- Update auras only for frames that had hover state changes
    for frameType, _ in pairs(framesNeedingUpdate) do
        if BoxxyAuras.DEBUG then
            print("OnUpdate: Calling UpdateSingleFrameAuras() for frame: " .. frameType)
        end
        BoxxyAuras.UpdateSingleFrameAuras(frameType)
    end

    -- === Handle Visual State for All Frames ===
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    local showHoverBorder = currentSettings and currentSettings.showHoverBorder

    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if frame then
            local isVisuallyHovered = BoxxyAuras.FrameVisualHoverStates[frameType] -- Instant visual hover
            local isAuraHovered = BoxxyAuras.FrameHoverStates[frameType]           -- Delayed aura persistence hover

            if currentLockState then
                -- Frame is LOCKED: Hide normal visuals, but show hover border on hover if enabled
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", 0, 0, 0, 0)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", 0, 0, 0, 0)
                if isVisuallyHovered and showHoverBorder then
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "hoverBorder", hoverColor)
                else
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "hoverBorder", hoverColor.r, hoverColor.g, hoverColor.b,
                        0)
                end
            else
                -- Frame is UNLOCKED: Set color based on hover
                if isAuraHovered then
                    -- Use aura persistence state for background color (maintains visual feedback during timer)
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", BoxxyAuras.Config.MainFrameBGColorHover)
                else
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", BoxxyAuras.Config.MainFrameBGColorNormal)
                end

                -- Use visual hover state for hover border (instant response)
                if isVisuallyHovered and showHoverBorder then
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "hoverBorder", hoverColor)
                else
                    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "hoverBorder", hoverColor.r, hoverColor.g, hoverColor.b,
                        0)
                end

                -- Always show border when unlocked
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
