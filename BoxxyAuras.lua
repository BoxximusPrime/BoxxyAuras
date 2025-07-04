local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}       -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras          -- Create a convenient local alias to the global table

BoxxyAuras.Version = "1.5.0"

BoxxyAuras.AllAuras = {}         -- Global cache for aura info
BoxxyAuras.recentAuraEvents = {} -- Queue for recent combat log aura events {spellId, sourceGUID, timestamp}
BoxxyAuras.healingAbsorbTracking = {} -- Track healing absorb shield amounts
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
    Buff = false,
    Debuff = false,
    -- Custom frames will be added dynamically as they are created
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
    -- Rule: Sort by the original start time
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
        showHoverBorder = true,           -- Enable hover border by default
        enableDotTickingAnimation = true, -- Enable dot ticking animation by default
        auraBarScale = 1.0,
        optionsWindowScale = 1.0,
        textFont = "OpenSans SemiBold",   -- Default font for aura text (matches BoxxyAuras_DurationTxt)
        textColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },                 -- Default text color (white)
        normalBorderColor = { r = 0.498, g = 0.498, b = 0.498, a = 1.0 },  -- Default normal border color (127,127,127)
        normalBackgroundColor = { r = 0.15, g = 0.15, b = 0.15, a = 1.0 }, -- Default background color (25,25,25)

        -- Healing Absorb Progress Bar Colors
        healingAbsorbBarColor = { r = 0.86, g = 0.28, b = 0.13, a = 0.8 },    -- Orangish red color for absorb bar
        healingAbsorbBarBGColor = { r = 0, g = 0, b = 0, a = 0.4 },    -- Dark background for absorb bar

        -- NEW: Multiple custom bar support
        customFrameProfiles = {},
        customAuraAssignments = {}, -- Maps aura name -> custom bar ID

        -- Keep legacy fields for backwards compatibility during migration
        customAuraNames = {},
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
        },

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
            borderSize = 2,
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
            borderSize = 2,
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

-- <<< NEW: Migration function for multiple custom bars >>>
function BoxxyAuras:MigrateProfileToMultipleCustomBars(profile)
    if not profile then
        return
    end

    -- Check if migration is needed (old format exists but new format doesn't)
    local needsMigration = profile.customAuraNames and
        next(profile.customAuraNames) and
        (not profile.customFrameProfiles or not next(profile.customFrameProfiles))

    if needsMigration then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Migrating profile to multiple custom bars format")
        end

        -- Initialize new structures if they don't exist
        profile.customFrameProfiles = profile.customFrameProfiles or {}
        profile.customAuraAssignments = profile.customAuraAssignments or {}

        -- Clear old customAuraNames since we're not migrating them to a Custom bar anymore
        if profile.customAuraNames then
            profile.customAuraNames = {}
        end

        if BoxxyAuras.DEBUG then
            print(string.format("BoxxyAuras: Migrated %d auras to Custom bar",
                profile.customAuraNames and self:TableCount(profile.customAuraNames) or 0))
        end
    end
end

-- Helper function to count table entries
function BoxxyAuras:TableCount(t)
    local count = 0
    if t then
        for _ in pairs(t) do
            count = count + 1
        end
    end
    return count
end

-- Helper function to determine if a frame type is a custom frame
function BoxxyAuras:IsCustomFrameType(frameType)
    -- Check if it's a custom frame
    local currentSettings = self:GetCurrentProfileSettings()
    if currentSettings.customFrameProfiles then
        return currentSettings.customFrameProfiles[frameType] ~= nil
    end

    return false
end

-- Helper function to get all active frame types (including dynamic custom frames)
function BoxxyAuras:GetAllActiveFrameTypes()
    local frameTypes = { "Buff", "Debuff" }

    local currentSettings = self:GetCurrentProfileSettings()
    if currentSettings.customFrameProfiles then
        for customFrameId, _ in pairs(currentSettings.customFrameProfiles) do
            table.insert(frameTypes, customFrameId)
        end
    end



    return frameTypes
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

    -- <<< NEW: Migration logic for multiple custom bars >>>
    self:MigrateProfileToMultipleCustomBars(profile)

    -- <<< Ensure nested tables and default values exist (existing logic) >>>
    profile.buffFrameSettings = profile.buffFrameSettings or {}
    profile.debuffFrameSettings = profile.debuffFrameSettings or {}

    -- Ensure new data structures exist
    profile.customFrameProfiles = profile.customFrameProfiles or {}
    profile.customAuraAssignments = profile.customAuraAssignments or {}

    -- Keep legacy fields for backwards compatibility
    profile.customFrameSettings = profile.customFrameSettings or {}
    profile.customAuraNames = profile.customAuraNames or {}

    if profile.lockFrames == nil then
        profile.lockFrames = false
    end
    if profile.auraBarScale == nil then
        profile.auraBarScale = 1.0
    end
    if profile.optionsWindowScale == nil then
        profile.optionsWindowScale = 1.0
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

    -- Ensure healing absorb colors exist
    if profile.healingAbsorbBarColor == nil then
        profile.healingAbsorbBarColor = { r = 0.86, g = 0.28, b = 0.13, a = 0.8 }
    end
    if profile.healingAbsorbBarBGColor == nil then
        profile.healingAbsorbBarBGColor = { r = 0, g = 0, b = 0, a = 0.4 }
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

    -- Create initial icons for each frame
    for frameType, frame in pairs(BoxxyAuras.Frames) do
        -- Get the correctly sorted and filtered auras for this frame
        local auras = BoxxyAuras:GetSortedAurasForFrame(frameType)
        BoxxyAuras.auraTracking[frameType] = auras

        -- Initialize icon array and pool if they don't exist
        BoxxyAuras.iconArrays[frameType] = BoxxyAuras.iconArrays[frameType] or {}
        local iconPool = BoxxyAuras.iconPools[frameType] or {}

        -- Create icons for each aura
        for i, auraData in ipairs(auras) do
            local icon = table.remove(iconPool)
            if not icon then
                local baseNamePrefix = "BoxxyAuras" .. frameType .. "Icon"
                BoxxyAuras.iconCounters[frameType] = (BoxxyAuras.iconCounters[frameType] or 0) + 1
                icon = AuraIcon.New(frame, BoxxyAuras.iconCounters[frameType], baseNamePrefix)
            end

            BoxxyAuras.iconArrays[frameType][i] = icon
            icon:Display(auraData, i, auraData.auraType, false) -- Skip intro animation at login
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

    -- << NEW: Demo Mode Handling >>
    if BoxxyAuras.Options and BoxxyAuras.Options.demoModeActive and BoxxyAuras.demoAuras then
        -- In demo mode, don't update individual frames - demo auras are stable
        if BoxxyAuras.DEBUG then
            print("UpdateSingleFrameAuras: Skipping update for " .. frameType .. " - demo mode active")
        end
        return
    end
    -- << END Demo Mode Handling >>

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
    else
        -- Clean up any forceExpired auras when hover state ends
        if BoxxyAuras.DEBUG then
            local expiredCount = 0
            for _, trackedAura in ipairs(trackedAuras) do
                if trackedAura and trackedAura.forceExpired then
                    expiredCount = expiredCount + 1
                end
            end
            if expiredCount > 0 then
                print(string.format("Single frame update: Cleaning up %d forceExpired auras from frame %s (hover ended)",
                    expiredCount, frameType))
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

    -- Filter out forceExpired auras if we shouldn't hold them anymore
    local filteredAuraList = {}
    for _, auraData in ipairs(newAuraList) do
        -- Only include forceExpired auras if we should still hold them
        if auraData.forceExpired and not shouldHoldExpiredAuras then
            if BoxxyAuras.DEBUG then
                print(string.format("Single frame: Filtering out forceExpired aura '%s' from frame %s (hover ended)",
                    auraData.name or "Unknown", frameType))
            end
            -- Skip this aura
        else
            table.insert(filteredAuraList, auraData)
        end
    end

    -- Iterate through the FILTERED list of auras
    for i, newAuraData in ipairs(filteredAuraList) do
        local newInstanceID = newAuraData.auraInstanceID
        local existing = existingAuraLookup[newInstanceID]
        local icon
        local isNewAura = false

        if existing then
            -- Aura already exists, reuse its icon
            icon = iconArray[existing.visualIndex]
            usedIcons[existing.visualIndex] = true
        else
            -- This is a completely new aura, get an icon from the pool
            icon = BoxxyAuras.GetOrCreateIcon(iconPool, i, frame, "BoxxyAuras" .. frameType .. "Icon")
            isNewAura = true

            -- Trigger tooltip scrape for the new aura
            if newAuraData.auraInstanceID and BoxxyAuras.AttemptTooltipScrape then
                local filter = newAuraData.auraType or (frameType == "Debuff" and "HARMFUL" or "HELPFUL")
                BoxxyAuras.AttemptTooltipScrape(newAuraData.spellId, newAuraData.auraInstanceID, filter)
            end
        end

        if icon then
            if BoxxyAuras.DEBUG and newAuraData.forceExpired then
                print(string.format("Updating icon for expired aura '%s' with forceExpired = %s",
                    newAuraData.name or "Unknown", tostring(newAuraData.forceExpired)))
            end
            icon:Display(newAuraData, i, newAuraData.auraType, isNewAura)
            icon.frame:Show()
            newIconArray[i] = icon
        end

        -- The new list of tracked auras is the filtered list
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

-- Helper function to update a specific frame with provided auras (used for demo mode)
function BoxxyAuras:UpdateFrameWithAuras(frameType, auraList)
    local frame = BoxxyAuras.Frames[frameType]
    if not frame then
        return
    end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then
        return
    end

    -- Initialize collections if they don't exist
    if not BoxxyAuras.auraTracking then
        BoxxyAuras.auraTracking = {}
    end
    if not BoxxyAuras.iconArrays then
        BoxxyAuras.iconArrays = {}
    end
    if not BoxxyAuras.iconPools then
        BoxxyAuras.iconPools = {}
    end

    -- Initialize for this frame type
    if not BoxxyAuras.auraTracking[frameType] then
        BoxxyAuras.auraTracking[frameType] = {}
    end
    if not BoxxyAuras.iconArrays[frameType] then
        BoxxyAuras.iconArrays[frameType] = {}
    end
    if not BoxxyAuras.iconPools[frameType] then
        BoxxyAuras.iconPools[frameType] = {}
    end

    local iconArray = BoxxyAuras.iconArrays[frameType]
    local iconPool = BoxxyAuras.iconPools[frameType]

    -- Check if we need to update (only if aura count changed or this is the first time)
    local existingAuraCount = #iconArray
    local newAuraCount = #auraList

    -- For demo mode, only update if the count has changed to prevent unnecessary re-sorting
    if existingAuraCount == newAuraCount and BoxxyAuras.Options and BoxxyAuras.Options.demoModeActive then
        -- Verify the auras are the same by checking instance IDs
        local needsUpdate = false
        for i, auraData in ipairs(auraList) do
            local existingAura = BoxxyAuras.auraTracking[frameType] and BoxxyAuras.auraTracking[frameType][i]
            if not existingAura or existingAura.auraInstanceID ~= auraData.auraInstanceID then
                needsUpdate = true
                break
            end
        end

        if not needsUpdate then
            return -- Skip update if demo auras haven't changed
        end
    end

    local newIconArray = {}
    local newTrackedAuras = {}

    -- Clear existing icons only if we're changing the count
    if existingAuraCount ~= newAuraCount then
        for i, icon in ipairs(iconArray) do
            BoxxyAuras.ReturnIconToPool(iconPool, icon)
        end
        iconArray = {} -- Clear the array
    end

    -- Create or reuse icons for the provided auras
    for i, auraData in ipairs(auraList) do
        local icon = iconArray[i] or BoxxyAuras.GetOrCreateIcon(iconPool, i, frame, "BoxxyAuras" .. frameType .. "Icon")
        local isNewAura = (iconArray[i] == nil) -- New if we had to get/create from pool
        if icon then
            icon:Display(auraData, i, auraData.auraType, isNewAura)
            icon.frame:Show()
            newIconArray[i] = icon
        end
        newTrackedAuras[i] = auraData
    end

    -- Update the tracking arrays
    BoxxyAuras.auraTracking[frameType] = newTrackedAuras
    BoxxyAuras.iconArrays[frameType] = newIconArray
end

-- Function to update displayed auras using cache comparison and stable order
BoxxyAuras.UpdateAuras = function(forceRefresh)
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    -- << NEW: Demo Mode Handling >>
    if BoxxyAuras.Options and BoxxyAuras.Options.demoModeActive and BoxxyAuras.demoAuras then
        -- In demo mode, use demo auras instead of real auras
        -- Process demo auras by frame type directly from the stored demo auras
        for frameId, demoAuras in pairs(BoxxyAuras.demoAuras) do
            if BoxxyAuras.Frames[frameId] then
                -- Create a stable copy of demo auras to prevent modifications
                local stableDemoAuras = {}
                for i, aura in ipairs(demoAuras) do
                    local stableAura = BoxxyAuras:DeepCopyTable(aura)
                    stableAura.frameType = frameId
                    stableAura.isDemoAura = true
                    stableAura.forceExpired = false -- Ensure demo auras are never treated as expired
                    table.insert(stableDemoAuras, stableAura)
                end

                BoxxyAuras:UpdateFrameWithAuras(frameId, stableDemoAuras)
            end
        end

        -- Update layout for all frames
        BoxxyAuras.FrameHandler.UpdateAllFramesAuras()
        return
    end
    -- << END Demo Mode Handling >>

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

    -- DEBUG: Check for frames with forceExpired auras that shouldn't have them
    if BoxxyAuras.DEBUG then
        for frameType, frame in pairs(BoxxyAuras.Frames) do
            local frameKey = frame:GetName() or frameType
            local shouldHoldExpiredAuras = BoxxyAuras.FrameHoverStates[frameType] or
                BoxxyAuras.FrameHoverTimers[frameKey]

            if not shouldHoldExpiredAuras and BoxxyAuras.auraTracking and BoxxyAuras.auraTracking[frameType] then
                local expiredCount = 0
                for _, aura in ipairs(BoxxyAuras.auraTracking[frameType]) do
                    if aura and aura.forceExpired then
                        expiredCount = expiredCount + 1
                    end
                end
                if expiredCount > 0 then
                    print(string.format(
                        "DEBUG: Frame %s has %d forceExpired auras but shouldn't hold them (hover=%s, timer=%s)",
                        frameType, expiredCount, tostring(BoxxyAuras.FrameHoverStates[frameType]),
                        tostring(BoxxyAuras.FrameHoverTimers[frameKey])))
                end
            end
        end
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
            else
                -- Clean up any forceExpired auras when hover state ends
                if BoxxyAuras.DEBUG then
                    local expiredCount = 0
                    for _, trackedAura in ipairs(trackedAuras) do
                        if trackedAura and trackedAura.forceExpired then
                            expiredCount = expiredCount + 1
                        end
                    end
                    if expiredCount > 0 then
                        print(string.format("UpdateAuras: Cleaning up %d forceExpired auras from frame %s (hover ended)",
                            expiredCount, frameType))
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

            -- Filter out forceExpired auras if we shouldn't hold them anymore
            local filteredAuraList = {}
            for _, auraData in ipairs(newAuraList) do
                -- Only include forceExpired auras if we should still hold them
                if auraData.forceExpired and not shouldHoldExpiredAuras then
                    if BoxxyAuras.DEBUG then
                        print(string.format("Filtering out forceExpired aura '%s' from frame %s (hover ended)",
                            auraData.name or "Unknown", frameType))
                    end
                    -- Skip this aura
                else
                    table.insert(filteredAuraList, auraData)
                end
            end

            -- 1. Iterate through the FILTERED list of auras
            for i, newAuraData in ipairs(filteredAuraList) do
                local newInstanceID = newAuraData.auraInstanceID
                local existing = existingAuraLookup[newInstanceID]
                local icon
                local isNewAura = false

                if existing then
                    -- Aura already exists, reuse its icon
                    icon = iconArray[existing.visualIndex]
                    usedIcons[existing.visualIndex] = true
                else
                    -- This is a completely new aura, get an icon from the pool
                    icon = BoxxyAuras.GetOrCreateIcon(iconPool, i, frame, "BoxxyAuras" .. frameType .. "Icon")
                    isNewAura = true

                    -- Trigger tooltip scrape for the new aura
                    if newAuraData.auraInstanceID and BoxxyAuras.AttemptTooltipScrape then
                        local filter = newAuraData.auraType or (frameType == "Debuff" and "HARMFUL" or "HELPFUL")
                        BoxxyAuras.AttemptTooltipScrape(newAuraData.spellId, newAuraData.auraInstanceID, filter)
                    end
                end

                if icon then
                    if BoxxyAuras.DEBUG and newAuraData.forceExpired then
                        print(string.format("Updating icon for expired aura '%s' with forceExpired = %s",
                            newAuraData.name or "Unknown", tostring(newAuraData.forceExpired)))
                    end
                    icon:Display(newAuraData, i, newAuraData.auraType, isNewAura)
                    icon.frame:Show()
                    newIconArray[i] = icon
                end

                -- The new list of tracked auras is the filtered list
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

        -- Safety check: Ensure frame is always hidden when returned to pool
        if icon.frame:IsShown() then
            if BoxxyAuras.DEBUG then
                print("ReturnIconToPool: Frame still showing after Reset, forcing Hide()")
            end
            icon.frame:Hide()
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
        -- For any custom frame type, we need to check both buffs and debuffs
        local isCustomFrame = self:IsCustomFrameType(frameType)

        if isCustomFrame then
            -- For Custom frames, we need to check both buffs and debuffs
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

    -- Filter out ignored auras first (applies to ALL frame types)
    if currentSettings.ignoredAuras and next(currentSettings.ignoredAuras) then
        local filteredAuras = {}
        for _, auraData in ipairs(allAuras) do
            local auraNameLower = string.lower(auraData.name or "")
            if not currentSettings.ignoredAuras[auraNameLower] then
                table.insert(filteredAuras, auraData)
            elseif self.DEBUG then
                print(string.format("BoxxyAuras: Ignoring aura '%s' (in ignored list)", auraData.name or "Unknown"))
            end
        end
        allAuras = filteredAuras
    end

    -- Build lookup tables for aura assignments
    local customAuraAssignments = {}
    local legacyCustomNamesLookup = {}

    -- NEW: Use customAuraAssignments for multiple custom bars
    if currentSettings.customAuraAssignments then
        for auraName, assignedFrameType in pairs(currentSettings.customAuraAssignments) do
            customAuraAssignments[string.lower(auraName)] = assignedFrameType
        end
    end

    -- LEGACY: Also check old customAuraNames for backwards compatibility
    if currentSettings.customAuraNames then
        for name, _ in pairs(currentSettings.customAuraNames) do
            legacyCustomNamesLookup[string.lower(name)] = true
            -- If not already assigned via new system, assign to "Custom"
            if not customAuraAssignments[string.lower(name)] then
                customAuraAssignments[string.lower(name)] = "Custom"
            end
        end
    end

    -- Filter auras based on frame type
    if frameType == "Buff" or frameType == "Debuff" then
        -- For Buff/Debuff frames, exclude auras assigned to any custom frame
        local filteredAuras = {}
        for _, auraData in ipairs(allAuras) do
            local auraNameLower = string.lower(auraData.name or "")
            local assignedTo = customAuraAssignments[auraNameLower]
            if assignedTo and not self.Frames[assignedTo] then
                assignedTo = nil -- ignore invalid assignment
            end

            -- Include aura if it's not assigned to any custom frame
            if not assignedTo then
                table.insert(filteredAuras, auraData)
            end
        end
        allAuras = filteredAuras
    elseif self:IsCustomFrameType(frameType) then
        -- For custom frames, include only auras assigned to this specific frame
        local filteredAuras = {}
        for _, auraData in ipairs(allAuras) do
            local auraNameLower = string.lower(auraData.name or "")
            local assignedTo = customAuraAssignments[auraNameLower]
            if assignedTo and not self.Frames[assignedTo] then
                assignedTo = nil
            end

            -- Include aura if it's assigned to this specific custom frame
            if assignedTo == frameType then
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
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

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

        -- Force a full update on login to ensure all auras are displayed correctly
        BoxxyAuras.UpdateAuras(true)

        -- Apply initial lock state and restore positions
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Run another full update once the player has fully entered the world – at this point
        -- the aura APIs are guaranteed to be populated.
        C_Timer.After(0.1, function()
            if BoxxyAuras and BoxxyAuras.UpdateAuras then
                BoxxyAuras.UpdateAuras(true)
            end
        end)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName,
        spellSchool, amount, overkill, school, resisted, blocked, absorbed = CombatLogGetCurrentEventInfo()

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

        -- Handle Aura Removal Events for healing absorb cleanup
        if destName and destName == UnitName("player") and subevent == "SPELL_AURA_REMOVED" then
            if spellId and BoxxyAuras.healingAbsorbTracking then
                -- Find tracking for this spell
                for trackingKey, trackingData in pairs(BoxxyAuras.healingAbsorbTracking) do
                    if trackingData.spellId == spellId then
                        -- Mark as debuff removed but don't clean up yet - the healing absorb might persist
                        trackingData.debuffRemoved = true
                        trackingData.debuffRemovedTime = GetTime()
                        
                        -- Start a timer to clean up after 30 seconds if no more absorption occurs
                        trackingData.cleanupTimer = C_Timer.NewTimer(30, function()
                            if BoxxyAuras.healingAbsorbTracking[trackingKey] then
                                BoxxyAuras.healingAbsorbTracking[trackingKey] = nil
                                -- Update visuals to hide the progress bar
                                BoxxyAuras:UpdateHealingAbsorbVisuals(trackingKey, nil)
                            end
                        end)
                        break
                    end
                end
            end
        end

        -- Handle Healing Absorb Events (SPELL_HEAL_ABSORBED) to update absorb progress
        if destName and destName == UnitName("player") and subevent == "SPELL_HEAL_ABSORBED" then
            -- For SPELL_HEAL_ABSORBED events, the parameters are:
            -- timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, 
            -- destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, 
            -- extraGUID, extraName, extraFlags, extraRaidFlags, extraSpellID, extraSpellName, extraSchool, absorbedAmount, totalAmount
            
            -- The absorb spell info is in the main spell parameters, not the "extra" ones
            local absorbSpellId = spellId
            local extraGUID, extraName, extraFlags, extraRaidFlags, extraSpellID, extraSpellName, extraSchool, absorbedAmount, totalAmount = 
                select(15, CombatLogGetCurrentEventInfo())
            
            if absorbedAmount and absorbedAmount > 0 and BoxxyAuras.healingAbsorbTracking then
                -- Find the healing absorb effect that absorbed this healing
                -- We need to match by the absorb spell ID (the main spellId, not extraSpellID)
                for trackingKey, trackingData in pairs(BoxxyAuras.healingAbsorbTracking) do
                    if trackingData.spellId == absorbSpellId and trackingData.currentAmount > 0 then
                        local oldAmount = trackingData.currentAmount
                        trackingData.currentAmount = math.max(0, trackingData.currentAmount - absorbedAmount)
                        trackingData.lastUpdate = GetTime()
                        
                        -- Cancel cleanup timer if it exists (we got new absorption activity)
                        if trackingData.cleanupTimer then
                            trackingData.cleanupTimer:Cancel()
                            trackingData.cleanupTimer = nil
                        end
                        
                        -- Check if the absorb is fully consumed
                        if trackingData.currentAmount <= 0 then
                            BoxxyAuras.healingAbsorbTracking[trackingKey] = nil
                            -- Update visuals to hide the progress bar
                            BoxxyAuras:UpdateHealingAbsorbVisuals(trackingKey, nil)
                        else
                            -- Update the visual progress bar
                            BoxxyAuras:UpdateHealingAbsorbVisuals(trackingKey, trackingData)
                        end
                        break -- Found the matching absorb, no need to continue
                    end
                end
            end
        end

        -- Handle Damage Events for Shake Effect
        if destName and destName == UnitName("player") and
            (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") then
            -- Handle cases where amount might be a string (like "ABSORB" for missed events)
            local numericAmount = (type(amount) == "number") and amount or 0
            local numericAbsorbed = (type(absorbed) == "number") and absorbed or 0
            local totalDamage = numericAmount + numericAbsorbed

            -- Enhanced debug logging for DOT shake troubleshooting
            if BoxxyAuras.DEBUG and (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") then
                print(string.format(
                    "DOT Event: %s, spellId=%s, sourceGUID=%s, amount=%s (%s), absorbed=%s (%s), totalDamage=%d",
                    subevent, tostring(spellId), tostring(sourceGUID),
                    tostring(amount), type(amount), tostring(absorbed), type(absorbed), totalDamage))
            end

            -- Allow shake even for fully absorbed damage (totalDamage can be 0 but we still want shake effect)
            if spellId and sourceGUID and BoxxyAuras.auraTracking then
                local targetAuraInstanceID = nil
                local targetFrameType = nil
                local targetAuraName = nil
                local matchedAuras = {} -- Track all potential matches for debug

                -- Check ALL frame types for matching debuffs, not just "Debuff" frame
                for frameType, trackedAuras in pairs(BoxxyAuras.auraTracking) do
                    if trackedAuras and #trackedAuras > 0 then
                        for _, trackedAura in ipairs(trackedAuras) do
                            -- Only check harmful auras (debuffs) for shake animation
                            if trackedAura and trackedAura.spellId == spellId and
                                (trackedAura.auraType == "HARMFUL" or trackedAura.originalAuraType == "HARMFUL") then
                                -- Enhanced debug logging
                                if BoxxyAuras.DEBUG and (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") then
                                    print(string.format(
                                        "  Found potential match: %s (instanceID=%s, sourceGUID=%s vs %s)",
                                        trackedAura.name or "Unknown",
                                        tostring(trackedAura.auraInstanceID),
                                        tostring(trackedAura.sourceGUID),
                                        tostring(sourceGUID)))
                                end

                                table.insert(matchedAuras, {
                                    aura = trackedAura,
                                    frameType = frameType,
                                    hasSourceMatch = (trackedAura.sourceGUID == sourceGUID)
                                })

                                -- Prioritize exact sourceGUID matches
                                if trackedAura.sourceGUID and trackedAura.sourceGUID == sourceGUID then
                                    targetAuraInstanceID = trackedAura.auraInstanceID
                                    targetFrameType = frameType
                                    targetAuraName = trackedAura.name
                                    break -- Fallback: if sourceGUID isn't stored on the trackedAura yet, match just by spellId (less accurate)
                                elseif not trackedAura.sourceGUID and not targetAuraInstanceID then
                                    targetAuraInstanceID = trackedAura.auraInstanceID
                                    targetFrameType = frameType
                                    targetAuraName = trackedAura.name
                                    -- Don't break here, keep looking for a sourceGUID match if possible
                                end
                            end
                        end
                        if targetAuraInstanceID and targetFrameType then
                            -- If we found a sourceGUID match, stop searching immediately
                            if #matchedAuras > 0 and matchedAuras[#matchedAuras].hasSourceMatch then
                                break -- Found exact match, stop searching
                            end
                        end
                    end
                end

                -- Enhanced debug logging for missing matches
                if BoxxyAuras.DEBUG and (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") and not targetAuraInstanceID then
                    print(string.format(
                        "  No matching aura found for spellId=%s, sourceGUID=%s. Checked %d potential matches:",
                        tostring(spellId), tostring(sourceGUID), #matchedAuras))
                    for i, match in ipairs(matchedAuras) do
                        print(string.format("    Match %d: %s (sourceGUID match: %s)",
                            i, match.aura.name or "Unknown", tostring(match.hasSourceMatch)))
                    end
                end

                if targetAuraInstanceID and targetFrameType then
                    -- Check if dot ticking animation is enabled
                    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
                    local animationEnabled = currentSettings and currentSettings.enableDotTickingAnimation
                    if animationEnabled == nil then
                        animationEnabled = true -- Default to enabled if setting doesn't exist
                    end

                    if animationEnabled then
                        -- Look for the icon in the correct frame type's icon array
                        if BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[targetFrameType] then
                            local iconFound = false
                            for _, auraIcon in ipairs(BoxxyAuras.iconArrays[targetFrameType]) do
                                if auraIcon and auraIcon.auraInstanceID == targetAuraInstanceID then
                                    if auraIcon.Shake then
                                        auraIcon:Shake(2.0)
                                        iconFound = true
                                        if BoxxyAuras.DEBUG then
                                            print(string.format(
                                                "✓ Triggered shake for '%s' in frame '%s' (damage: %d, absorbed: %d)",
                                                targetAuraName or "Unknown",
                                                targetFrameType, numericAmount, numericAbsorbed))
                                        end
                                    end
                                    break
                                end
                            end

                            -- Debug logging if icon not found in array
                            if BoxxyAuras.DEBUG and not iconFound and (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") then
                                print(string.format(
                                    "  Icon not found in frame '%s' icon array (instanceID=%s). Array has %d icons:",
                                    targetFrameType, tostring(targetAuraInstanceID),
                                    #BoxxyAuras.iconArrays[targetFrameType]))
                                for i, icon in ipairs(BoxxyAuras.iconArrays[targetFrameType]) do
                                    print(string.format("    Icon %d: instanceID=%s, name=%s",
                                        i, tostring(icon.auraInstanceID), tostring(icon.name)))
                                end
                            end
                        else
                            if BoxxyAuras.DEBUG and (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") then
                                print(string.format("  No icon array found for frame type '%s'", targetFrameType))
                            end
                        end
                    else
                        if BoxxyAuras.DEBUG and (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") then
                            print("  DOT ticking animation is disabled in settings")
                        end
                    end
                end
            else
                -- Debug logging for missing required data
                if BoxxyAuras.DEBUG and (subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_MISSED") then
                    print(string.format("  Missing required data: spellId=%s, sourceGUID=%s, auraTracking=%s",
                        tostring(spellId), tostring(sourceGUID), tostring(BoxxyAuras.auraTracking ~= nil)))
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
    -- NEW: Reconcile custom frames to match the new profile
    ------------------------------------------------------------------
    self:ReconcileCustomFrames(currentSettings)

    ------------------------------------------------------------------
    -- 1. Apply frame-level settings (width/scale/icon layout etc.)
    ------------------------------------------------------------------
    if self.FrameHandler and self.FrameHandler.ApplySettings then
        local frameTypes = self:GetAllActiveFrameTypes()
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
                -- Get the correct settings table for this frame type
                local settingsTable = self.FrameHandler.GetFrameSettingsTable(frameType)
                if settingsTable then
                    -- Re-register with LibWindow using the correct settings table
                    LibWindow.RegisterConfig(frame, settingsTable)

                    -- Now restore the position
                    LibWindow.RestorePosition(frame)

                    if BoxxyAuras.DEBUG then
                        print(string.format("Re-registered and restored position for %s frame", frameType))
                    end
                else
                    BoxxyAuras.DebugLogError("Could not get settings table for frame type: " .. tostring(frameType))
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
        self.UpdateAuras(true) -- Use forced refresh to ensure everything redraws properly
    end

    -- Add delayed comprehensive refresh for profile switching (similar to reload fix)
    -- This ensures borders and custom routing work correctly after profile changes
    C_Timer.After(0.3, function()
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Performing post-profile-switch comprehensive refresh for borders and routing")
        end

        if self.UpdateAuras then
            self.UpdateAuras(true) -- Force complete refresh
        end

        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Post-profile-switch refresh complete")
        end
    end)

    return true
end

function BoxxyAuras:ReconcileCustomFrames(profileSettings)
    if not self.FrameHandler or not self.FrameHandler.SetupDisplayFrame then
        return
    end

    -- 1. Get custom frames required by the new profile
    local requiredCustomFrames = {}
    if profileSettings.customFrameProfiles then
        for frameId, _ in pairs(profileSettings.customFrameProfiles) do
            requiredCustomFrames[frameId] = true
        end
    end

    -- 2. Find existing custom frames to delete
    local framesToDelete = {}
    if self.Frames then
        for frameId, frame in pairs(self.Frames) do
            -- Only consider custom frames
            if frameId ~= "Buff" and frameId ~= "Debuff" then
                if not requiredCustomFrames[frameId] then
                    table.insert(framesToDelete, frameId)
                end
            end
        end
    end

    -- 3. Delete them
    for _, frameId in ipairs(framesToDelete) do
        local frame = self.Frames[frameId]
        if frame then
            -- A simplified version of DeleteCustomBar's cleanup, without modifying the profile
            if LibWindow and LibWindow.SavePosition then
                LibWindow.SavePosition(frame)
            end -- Mimic existing logic
            frame:Hide()
            frame:SetParent(nil)
            self.Frames[frameId] = nil

            -- Clean up associated data
            if self.auraTracking then
                self.auraTracking[frameId] = nil
            end
            if self.iconArrays then
                -- Return icons to pool before clearing
                if self.iconPools and self.iconPools[frameId] and self.iconArrays[frameId] then
                    for _, icon in ipairs(self.iconArrays[frameId]) do
                        self.ReturnIconToPool(self.iconPools[frameId], icon)
                    end
                end
                self.iconArrays[frameId] = nil
            end
            if self.iconPools then
                self.iconPools[frameId] = nil
            end
            if self.FrameHoverStates then
                self.FrameHoverStates[frameId] = nil
            end
            if self.FrameVisualHoverStates then
                self.FrameVisualHoverStates[frameId] = nil
            end

            if self.DEBUG then
                print("BoxxyAuras: Removed stale custom frame '" .. frameId .. "' on profile switch.")
            end
        end
    end

    -- 4. Create missing custom frames
    if profileSettings.customFrameProfiles then
        for frameId, _ in pairs(profileSettings.customFrameProfiles) do
            if not self.Frames[frameId] then
                -- A simplified version of CreateCustomBar's frame setup
                local frame = self.FrameHandler.SetupDisplayFrame(frameId)
                if frame then
                    self.Frames = self.Frames or {}
                    self.Frames[frameId] = frame

                    -- Initialize hover states
                    if self.FrameHoverStates then
                        self.FrameHoverStates[frameId] = false
                    end
                    if self.FrameVisualHoverStates then
                        self.FrameVisualHoverStates[frameId] = false
                    end

                    -- Initialize tracking arrays
                    if not self.auraTracking then
                        self.auraTracking = {}
                    end
                    if not self.iconArrays then
                        self.iconArrays = {}
                    end
                    if not self.iconPools then
                        self.iconPools = {}
                    end

                    self.auraTracking[frameId] = {}
                    self.iconArrays[frameId] = {}
                    self.iconPools[frameId] = {}

                    -- Apply settings to the new frame
                    if self.FrameHandler.ApplySettings then
                        self.FrameHandler.ApplySettings(frameId)
                    end

                    -- Show the frame initially (it will be hidden by ApplyLockState if needed)
                    frame:Show()

                    -- Force center position for new bars to make them easy to spot
                    frame:ClearAllPoints()
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

                    -- Restore position from settings if LibWindow is available (but after we've centered it)
                    if LibWindow and LibWindow.RestorePosition then
                        LibWindow.RestorePosition(frame)
                    end

                    -- Apply current lock state to the new frame
                    if self.FrameHandler and self.FrameHandler.ApplyLockState then
                        local currentSettings = self:GetCurrentProfileSettings()
                        if currentSettings and currentSettings.lockFrames then
                            if frame.Lock then
                                frame:Lock()
                            end
                        else
                            if frame.Unlock then
                                frame:Unlock()
                            end
                        end
                    end

                    if self.DEBUG then
                        print("BoxxyAuras: Created new custom frame '" .. frameId .. "' on profile switch.")
                    end
                    -- Settings and positions will be applied later in SwitchToProfile
                end
            end
        end
    end
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
            print("OnUpdate: Calling UpdateSingleFrameAuras() for frame: " ..
                frameType .. " (HOVER TRIGGERED BORDER REFRESH)")
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

                if BoxxyAuras.DEBUG then
                    print(string.format("BORDER DEBUG: Setting frame %s border to transparent (locked)", frameType))
                end
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

                -- Note: Individual icon borders are managed by Auraicon:Display() method
                -- Frame-level border is handled in FrameHandler.SetupDisplayFrame()
            end
        end
    end

    -- Update previous lock state for next tick
    BoxxyAuras.WasLocked = currentLockState

    -- === Periodic Cache Cleanup and Force Expired Aura Cleanup ===
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

        -- Force cleanup of any stuck forceExpired auras
        local cleanupNeeded = false
        for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
            local frameKey = frame:GetName() or frameType
            local shouldHoldExpiredAuras = BoxxyAuras.FrameHoverStates[frameType] or
                BoxxyAuras.FrameHoverTimers[frameKey]

            if not shouldHoldExpiredAuras and BoxxyAuras.auraTracking and BoxxyAuras.auraTracking[frameType] then
                for _, aura in ipairs(BoxxyAuras.auraTracking[frameType]) do
                    if aura and aura.forceExpired then
                        cleanupNeeded = true
                        if BoxxyAuras.DEBUG then
                            print(string.format("Periodic cleanup: Found stuck forceExpired aura '%s' in frame %s",
                                aura.name or "Unknown", frameType))
                        end
                        break
                    end
                end
            end
        end

        if cleanupNeeded then
            if BoxxyAuras.DEBUG then
                print("Periodic cleanup: Triggering full aura update to clean up stuck expired auras")
            end
            BoxxyAuras.UpdateAuras()
        end
    end
    -- === End Cache Cleanup ===
end)

-- Function to create a new custom bar
function BoxxyAuras:CreateCustomBar(barName)
    if not barName or barName == "" then
        if self.DEBUG then
            print("BoxxyAuras: Cannot create custom bar with empty name")
        end
        return false
    end

    -- Sanitize the bar name (remove special characters, spaces, etc.)
    local sanitizedName = barName:gsub("[^%w]", "")
    if sanitizedName == "" then
        if self.DEBUG then
            print("BoxxyAuras: Bar name contains no valid characters")
        end
        return false
    end

    -- Check if bar already exists
    if self.Frames and self.Frames[sanitizedName] then
        if self.DEBUG then
            print("BoxxyAuras: Custom bar '" .. sanitizedName .. "' already exists")
        end
        return false
    end

    local currentSettings = self:GetCurrentProfileSettings()

    -- Check if it already exists in customFrameProfiles
    if currentSettings.customFrameProfiles and currentSettings.customFrameProfiles[sanitizedName] then
        if self.DEBUG then
            print("BoxxyAuras: Custom bar '" .. sanitizedName .. "' already exists in profile")
        end
        return false
    end

    -- Create the settings for the new custom bar
    currentSettings.customFrameProfiles = currentSettings.customFrameProfiles or {}
    currentSettings.customFrameProfiles[sanitizedName] = {
        name = barName, -- Store the original display name
        x = 0,
        y = 0,          -- Center of screen
        anchor = "CENTER",
        height = 50,
        numIconsWide = 6,
        customTextAlign = "CENTER",
        iconSize = 24,
        textSize = 8,
        borderSize = 1,
        iconSpacing = 0,
        wrapDirection = "DOWN",
        width = 200
    }

    -- Create the frame
    if self.FrameHandler and self.FrameHandler.SetupDisplayFrame then
        local frame = self.FrameHandler.SetupDisplayFrame(sanitizedName)
        if frame then
            self.Frames = self.Frames or {}
            self.Frames[sanitizedName] = frame

            -- Initialize hover states
            if self.FrameHoverStates then
                self.FrameHoverStates[sanitizedName] = false
            end
            if self.FrameVisualHoverStates then
                self.FrameVisualHoverStates[sanitizedName] = false
            end

            -- Initialize tracking arrays
            if not self.auraTracking then
                self.auraTracking = {}
            end
            if not self.iconArrays then
                self.iconArrays = {}
            end
            if not self.iconPools then
                self.iconPools = {}
            end

            self.auraTracking[sanitizedName] = {}
            self.iconArrays[sanitizedName] = {}
            self.iconPools[sanitizedName] = {}

            -- Apply settings to the new frame
            if self.FrameHandler.ApplySettings then
                self.FrameHandler.ApplySettings(sanitizedName)
            end

            -- Show the frame initially (it will be hidden by ApplyLockState if needed)
            frame:Show()

            -- Force center position for new bars to make them easy to spot
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

            -- Restore position from settings if LibWindow is available (but after we've centered it)
            if LibWindow and LibWindow.RestorePosition then
                LibWindow.RestorePosition(frame)
            end

            -- Apply current lock state to the new frame
            if self.FrameHandler and self.FrameHandler.ApplyLockState then
                local currentSettings = self:GetCurrentProfileSettings()
                if currentSettings and currentSettings.lockFrames then
                    if frame.Lock then
                        frame:Lock()
                    end
                else
                    if frame.Unlock then
                        frame:Unlock()
                    end
                end
            end

            if self.DEBUG then
                print("BoxxyAuras: Created custom bar '" .. sanitizedName .. "'")
            end

            return true
        end
    end

    if self.DEBUG then
        print("BoxxyAuras: Failed to create frame for custom bar '" .. sanitizedName .. "'")
    end
    return false
end

-- Function to delete a custom bar
function BoxxyAuras:DeleteCustomBar(barId)
    if not barId or barId == "" then
        if self.DEBUG then
            print("BoxxyAuras: Cannot delete custom bar with empty ID")
        end
        return false
    end

    -- Don't allow deleting standard frames
    if barId == "Buff" or barId == "Debuff" then
        if self.DEBUG then
            print("BoxxyAuras: Cannot delete standard frame: " .. barId)
        end
        return false
    end

    local currentSettings = self:GetCurrentProfileSettings()



    -- Check if the bar exists
    if not currentSettings.customFrameProfiles or not currentSettings.customFrameProfiles[barId] then
        if self.DEBUG then
            print("BoxxyAuras: Custom bar '" .. barId .. "' does not exist in profile")
        end
        return false
    end

    -- Remove any aura assignments to this bar
    if currentSettings.customAuraAssignments then
        local aurasToReassign = {}
        for auraName, assignedBarId in pairs(currentSettings.customAuraAssignments) do
            if assignedBarId == barId then
                table.insert(aurasToReassign, auraName)
            end
        end

        -- Remove the assignments
        for _, auraName in ipairs(aurasToReassign) do
            currentSettings.customAuraAssignments[auraName] = nil
            if self.DEBUG then
                print("BoxxyAuras: Removed assignment for aura '" .. auraName .. "' from deleted bar")
            end
        end
    end

    -- Remove the frame
    if self.Frames and self.Frames[barId] then
        local frame = self.Frames[barId]

        -- Clean up LibWindow registration
        if LibWindow and LibWindow.SavePosition then
            LibWindow.SavePosition(frame)
        end

        -- Hide and clean up the frame
        frame:Hide()
        frame:SetParent(nil)
        self.Frames[barId] = nil
    end

    -- Clean up tracking data
    if self.auraTracking and self.auraTracking[barId] then
        -- Return any active icons to the pool before clearing
        if self.iconArrays and self.iconArrays[barId] and self.iconPools and self.iconPools[barId] then
            for _, icon in ipairs(self.iconArrays[barId]) do
                if icon and icon.Reset then
                    icon:Reset()
                end
                table.insert(self.iconPools[barId], icon)
            end
        end

        self.auraTracking[barId] = nil
        if self.iconArrays then
            self.iconArrays[barId] = nil
        end
        if self.iconPools then
            self.iconPools[barId] = nil
        end
    end

    -- Clean up hover states
    if self.FrameHoverStates then
        self.FrameHoverStates[barId] = nil
    end
    if self.FrameVisualHoverStates then
        self.FrameVisualHoverStates[barId] = nil
    end

    -- Remove from profile
    currentSettings.customFrameProfiles[barId] = nil

    -- Trigger aura update to move orphaned auras back to their original frames
    if self.UpdateAuras then
        self.UpdateAuras()
    end

    if self.DEBUG then
        print("BoxxyAuras: Deleted custom bar '" .. barId .. "'")
    end

    return true
end

-- Function to assign an aura to a specific custom bar
function BoxxyAuras:AssignAuraToCustomBar(auraName, barId)
    if not auraName or auraName == "" then
        return false
    end

    local currentSettings = self:GetCurrentProfileSettings()
    currentSettings.customAuraAssignments = currentSettings.customAuraAssignments or {}

    if barId and barId ~= "" then
        -- Assign to specific bar
        currentSettings.customAuraAssignments[auraName] = barId
        if self.DEBUG then
            print("BoxxyAuras: Assigned aura '" .. auraName .. "' to bar '" .. barId .. "'")
        end
    else
        -- Remove assignment (aura goes back to buff/debuff frames)
        currentSettings.customAuraAssignments[auraName] = nil
        if self.DEBUG then
            print("BoxxyAuras: Removed assignment for aura '" .. auraName .. "'")
        end
    end

    -- Trigger aura update to reflect the change
    self.UpdateAuras()

    return true
end

-- Debug function to test multiple custom bars functionality
function BoxxyAuras:TestMultipleCustomBars()
    if not self.DEBUG then
        print("BoxxyAuras: Enable DEBUG mode first (BoxxyAuras.DEBUG = true)")
        return
    end

    print("=== BoxxyAuras Multiple Custom Bars Test ===")

    -- Test creating custom bars
    print("Creating test custom bars...")
    local success1 = self:CreateCustomBar("Defensives")
    local success2 = self:CreateCustomBar("Offensives")
    local success3 = self:CreateCustomBar("Utilities")

    print("Create results:", success1, success2, success3)

    -- Show current frame list
    print("Current frames:")
    for frameType, frame in pairs(self.Frames or {}) do
        print("  " .. frameType .. ": " .. tostring(frame:GetName()))
    end

    -- Show current profile structure
    local currentSettings = self:GetCurrentProfileSettings()
    print("Custom frame profiles:")
    if currentSettings.customFrameProfiles then
        for barId, settings in pairs(currentSettings.customFrameProfiles) do
            print("  " .. barId .. ": " .. (settings.name or "unnamed"))
        end
    else
        print("  None")
    end

    -- Test assigning some auras (these might not exist but that's ok for testing)
    print("Testing aura assignments...")
    self:AssignAuraToCustomBar("Power Infusion", "Offensives")
    self:AssignAuraToCustomBar("Pain Suppression", "Defensives")
    self:AssignAuraToCustomBar("Levitate", "Utilities")

    print("Current aura assignments:")
    if currentSettings.customAuraAssignments then
        for auraName, barId in pairs(currentSettings.customAuraAssignments) do
            print("  '" .. auraName .. "' -> " .. barId)
        end
    else
        print("  None")
    end

    print("=== Test Complete ===")
    print("To clean up, you can use:")
    print("  BoxxyAuras:DeleteCustomBar('Defensives')")
    print("  BoxxyAuras:DeleteCustomBar('Offensives')")
    print("  BoxxyAuras:DeleteCustomBar('Utilities')")
end

-- Function to test shake animation on all visible debuff icons
function BoxxyAuras:TestShakeAnimation()
    local shakeCount = 0

    -- Test all frame types
    for frameType, frame in pairs(self.Frames or {}) do
        if self.iconArrays and self.iconArrays[frameType] then
            for _, auraIcon in ipairs(self.iconArrays[frameType]) do
                if auraIcon and auraIcon.frame and auraIcon.frame:IsVisible() then
                    -- Only shake harmful auras (debuffs)
                    if (auraIcon.auraType == "HARMFUL" or auraIcon.originalAuraType == "HARMFUL") and auraIcon.Shake then
                        auraIcon:Shake(2.0)
                        shakeCount = shakeCount + 1
                        print(string.format("Test shake: %s in frame %s", auraIcon.name or "Unknown", frameType))
                    end
                end
            end
        end
    end

    if shakeCount == 0 then
        print("No harmful auras found to test shake animation")
    else
        print(string.format("Triggered test shake on %d debuff icons", shakeCount))
    end
end

-- Add this at the end of the file
local widgetIDCounter = 0
function BoxxyAuras:GetNextWidgetID()
    widgetIDCounter = widgetIDCounter + 1
    return widgetIDCounter
end

-- Debug function to check hover states and timers
function BoxxyAuras:DebugHoverStates()
    if not self.DEBUG then
        print("Enable BoxxyAuras.DEBUG = true first")
        return
    end

    print("=== BoxxyAuras Hover State Debug ===")
    print("Current time:", GetTime())

    print("\nFrames and their hover states:")
    for frameType, frame in pairs(self.Frames or {}) do
        local frameKey = frame:GetName() or frameType
        local mouseInFrame = self.IsMouseWithinFrame(frame)
        local hoverState = self.FrameHoverStates[frameType]
        local hoverTimer = self.FrameHoverTimers[frameKey]
        local visualHover = self.FrameVisualHoverStates[frameType]

        print(string.format("  %s (%s):", frameType, frameKey))
        print(string.format("    Mouse in frame: %s", tostring(mouseInFrame)))
        print(string.format("    Hover state: %s", tostring(hoverState)))
        print(string.format("    Hover timer: %s", tostring(hoverTimer)))
        print(string.format("    Visual hover: %s", tostring(visualHover)))
        print(string.format("    shouldHoldExpiredAuras: %s", tostring(hoverState or hoverTimer)))

        -- Check tracked auras for this frame
        if self.auraTracking and self.auraTracking[frameType] then
            local expiredCount = 0
            local totalCount = #self.auraTracking[frameType]
            for _, aura in ipairs(self.auraTracking[frameType]) do
                if aura and aura.forceExpired then
                    expiredCount = expiredCount + 1
                end
            end
            print(string.format("    Tracked auras: %d total, %d forceExpired", totalCount, expiredCount))
        end
    end

    print("=== End Debug ===")
end

-- =============================================================== --
-- BoxxyAuras:UpdateHealingAbsorbVisuals
-- Updates the visual progress bars for a specific healing absorb
-- =============================================================== --
function BoxxyAuras:UpdateHealingAbsorbVisuals(trackingKey, trackingData)
    if not trackingKey then
        return
    end

    -- Find all icons that match this absorb and update their progress bars
    for frameType, iconArray in pairs(self.iconArrays or {}) do
        if iconArray then
            for _, icon in ipairs(iconArray) do
                if icon and icon.frame and icon.auraInstanceID then
                    -- Check if this icon matches the tracking key
                    local iconTrackingKey = icon.auraInstanceID or icon.spellId
                    if iconTrackingKey == trackingKey then
                        if icon.frame.absorbProgressBar then
                            if trackingData and trackingData.initialAmount > 0 then
                                -- Update progress bar
                                local percentage = math.max(0, trackingData.currentAmount / trackingData.initialAmount)
                                icon.frame.absorbProgressBar:SetValue(percentage)
                                icon.frame.absorbProgressBar:Show()
                                
                                if BoxxyAuras.DEBUG then
                                    print(string.format("BoxxyAuras: Updated absorb bar for '%s' to %.1f%%", 
                                        icon.name or "Unknown", percentage * 100))
                                end
                            else
                                -- Hide progress bar (tracking data is nil or absorb is consumed)
                                icon.frame.absorbProgressBar:Hide()
                                if BoxxyAuras.DEBUG then
                                    print(string.format("BoxxyAuras: Hiding absorb bar for '%s' (absorb consumed or tracking removed)", 
                                        icon.name or "Unknown"))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Debug function to trace expired aura handling
function BoxxyAuras:DebugExpiredAuras(frameType)
    if not self.DEBUG then
        return
    end

    local frame = self.Frames and self.Frames[frameType]
    if not frame then
        print("DebugExpiredAuras: No frame found for " .. tostring(frameType))
        return
    end

    local frameKey = frame:GetName() or frameType
    local mouseInFrame = self.IsMouseWithinFrame(frame)
    local hoverState = self.FrameHoverStates[frameType]
    local hoverTimer = self.FrameHoverTimers[frameKey]
    local shouldHoldExpiredAuras = hoverState or hoverTimer

    print(string.format("\n=== Expired Aura Debug for %s ===", frameType))
    print(string.format("Frame key: %s", frameKey))
    print(string.format("Mouse in frame: %s", tostring(mouseInFrame)))
    print(string.format("Hover state: %s", tostring(hoverState)))
    print(string.format("Hover timer: %s", tostring(hoverTimer)))
    print(string.format("shouldHoldExpiredAuras: %s", tostring(shouldHoldExpiredAuras)))

    if self.auraTracking and self.auraTracking[frameType] then
        print(string.format("Tracked auras (%d total):", #self.auraTracking[frameType]))
        for i, aura in ipairs(self.auraTracking[frameType]) do
            if aura then
                print(string.format("  %d: %s (ID:%s, forceExpired:%s)",
                    i, aura.name or "Unknown",
                    tostring(aura.auraInstanceID),
                    tostring(aura.forceExpired)))
            end
        end
    else
        print("No tracked auras")
    end
    print("=== End Debug ===\n")
end

-- Manual function to force cleanup of all expired auras (for testing)
function BoxxyAuras:ForceCleanupExpiredAuras()
    print("=== Force Cleanup Expired Auras ===")
    local cleanedFrames = 0
    local cleanedAuras = 0

    for frameType, frame in pairs(self.Frames or {}) do
        local frameKey = frame:GetName() or frameType
        local shouldHoldExpiredAuras = self.FrameHoverStates[frameType] or self.FrameHoverTimers[frameKey]

        if self.DEBUG then
            print(string.format("Frame %s: shouldHold=%s (hover=%s, timer=%s)",
                frameType, tostring(shouldHoldExpiredAuras),
                tostring(self.FrameHoverStates[frameType]),
                tostring(self.FrameHoverTimers[frameKey])))
        end

        if self.auraTracking and self.auraTracking[frameType] then
            local expiredCount = 0
            for _, aura in ipairs(self.auraTracking[frameType]) do
                if aura and aura.forceExpired then
                    expiredCount = expiredCount + 1
                end
            end

            if expiredCount > 0 then
                print(string.format("  Frame %s has %d forceExpired auras", frameType, expiredCount))
                if not shouldHoldExpiredAuras then
                    cleanedFrames = cleanedFrames + 1
                    cleanedAuras = cleanedAuras + expiredCount
                    print(string.format("  Triggering cleanup for frame %s", frameType))
                else
                    print(string.format("  Frame %s should hold expired auras, skipping cleanup", frameType))
                end
            end
        end
    end

    if cleanedFrames > 0 then
        print(string.format("Triggering UpdateAuras to clean %d auras from %d frames", cleanedAuras, cleanedFrames))
        self.UpdateAuras()
    else
        print("No expired auras need cleanup")
    end
    print("=== End Force Cleanup ===")
end
