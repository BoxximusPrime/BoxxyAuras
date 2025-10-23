local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}       -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras          -- Create a convenient local alias to the global table

BoxxyAuras.Version = "1.5.3"

BoxxyAuras.AllAuras = {}              -- Global cache for aura info
BoxxyAuras.recentAuraEvents = {}      -- Queue for recent combat log aura events {spellId, sourceGUID, timestamp}
BoxxyAuras.healingAbsorbTracking = {} -- Track healing absorb shield amounts
BoxxyAuras.healingAbsorbTracker = {   -- Enhanced healing absorb detection
    trackedAmount = 0,                -- Currently tracked healing absorb amount
    confirmedAbsorbs = {},            -- Confirmed healing absorb spell IDs
    lastAuraApplicationTime = 0       -- Track when the last aura was applied for correlation
}
BoxxyAuras.Frames = {}                -- << ADDED: Table to store frame references
BoxxyAuras.iconArrays = {}            -- << ADDED: Table to store live icon objects
BoxxyAuras.auraTracking = {}          -- << ADDED: Table to track aura data
BoxxyAuras.HoveredFrame = nil
BoxxyAuras.DEBUG = false
BoxxyAuras.lastCacheCleanup = 0    -- Track when we last cleaned the cache
BoxxyAuras.weaponEnchantCache = {} -- Cache weapon enchant information by slot

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
        -- Handle mixed string/number types by converting to string for comparison
        local aInstanceID = tostring(a.auraInstanceID or "0")
        local bInstanceID = tostring(b.auraInstanceID or "0")
        return aInstanceID < bInstanceID
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
        showInfiniteDuration = true,      -- Show ∞ symbol for infinite duration auras by default
        auraBarScale = 1.0,
        optionsWindowScale = 1.0,
        textFont = "OpenSans SemiBold",                                    -- Default font for aura text (matches BoxxyAuras_DurationTxt)
        textColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },                -- Default text color (white)
        normalBorderColor = { r = 0.498, g = 0.498, b = 0.498, a = 1.0 },  -- Default normal border color (127,127,127)
        normalBackgroundColor = { r = 0.15, g = 0.15, b = 0.15, a = 1.0 }, -- Default background color (25,25,25)

        -- Healing Absorb Progress Bar Colors
        healingAbsorbBarColor = { r = 0.86, g = 0.28, b = 0.13, a = 0.8 }, -- Orangish red color for absorb bar
        healingAbsorbBarBGColor = { r = 0, g = 0, b = 0, a = 0.4 },        -- Dark background for absorb bar

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
    if profile.showInfiniteDuration == nil then
        profile.showInfiniteDuration = true
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
        -- Build a list of expired auras with their original positions
        local expiredAurasWithPositions = {}
        for i, trackedAura in ipairs(trackedAuras) do
            if trackedAura and not newAuraLookup[trackedAura.auraInstanceID] then
                -- This aura expired and we are (or were recently) hovering the frame, so hold it.
                trackedAura.forceExpired = true
                table.insert(expiredAurasWithPositions, { aura = trackedAura, originalIndex = i })
                newAuraLookup[trackedAura.auraInstanceID] = true -- Add to lookup to prevent re-adding
                if BoxxyAuras.DEBUG then
                    print(string.format("Single frame update: Holding expired aura '%s' in frame %s at position %d",
                        trackedAura.name or "Unknown", frameType, i))
                end
            end
        end

        -- Insert expired auras back at their original positions
        -- Sort by originalIndex in descending order to insert from back to front (avoids index shifting issues)
        table.sort(expiredAurasWithPositions, function(a, b) return a.originalIndex > b.originalIndex end)
        for _, expiredData in ipairs(expiredAurasWithPositions) do
            -- Insert at the original position, but clamp to list bounds
            local insertPos = math.min(expiredData.originalIndex, #newAuraList + 1)
            table.insert(newAuraList, insertPos, expiredData.aura)
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

            -- Trigger tooltip scrape for the new aura (skip weapon enchants)
            if newAuraData.auraInstanceID and not newAuraData.isWeaponEnchant and BoxxyAuras.AttemptTooltipScrape then
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
                -- Build a list of expired auras with their original positions
                local expiredAurasWithPositions = {}
                for i, trackedAura in ipairs(trackedAuras) do
                    if trackedAura and not newAuraLookup[trackedAura.auraInstanceID] then
                        -- This aura expired and we are (or were recently) hovering the frame, so hold it.
                        trackedAura.forceExpired = true
                        table.insert(expiredAurasWithPositions, { aura = trackedAura, originalIndex = i })
                        newAuraLookup[trackedAura.auraInstanceID] = true -- Add to lookup to prevent re-adding
                        if BoxxyAuras.DEBUG then
                            print(string.format(
                                "Holding expired aura '%s' in frame %s at position %d (hovered=%s, timer=%s)",
                                trackedAura.name or "Unknown", frameType, i,
                                tostring(BoxxyAuras.FrameHoverStates[frameType]),
                                tostring(BoxxyAuras.FrameHoverTimers[frameKey] ~= nil)))
                        end
                    end
                end

                -- Insert expired auras back at their original positions
                -- Sort by originalIndex in descending order to insert from back to front (avoids index shifting issues)
                table.sort(expiredAurasWithPositions, function(a, b) return a.originalIndex > b.originalIndex end)
                for _, expiredData in ipairs(expiredAurasWithPositions) do
                    -- Insert at the original position, but clamp to list bounds
                    local insertPos = math.min(expiredData.originalIndex, #newAuraList + 1)
                    table.insert(newAuraList, insertPos, expiredData.aura)
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

                    -- Trigger tooltip scrape for the new aura (skip weapon enchants)
                    if newAuraData.auraInstanceID and not newAuraData.isWeaponEnchant and BoxxyAuras.AttemptTooltipScrape then
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

-- Add weapon enchants to the aura list
function BoxxyAuras:AddWeaponEnchantsToAuraList(allAuras, existingTrackTimes)
    -- GetWeaponEnchantInfo returns info for all weapon slots
    local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID,
    hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID,
    hasRangedEnchant, rangedExpiration, rangedCharges, rangedEnchantID = GetWeaponEnchantInfo()

    -- Main hand weapon enchant
    if hasMainHandEnchant and mainHandExpiration and mainHandExpiration > 0 then
        local enchantData = self:CreateWeaponEnchantAuraData("mainhand", mainHandExpiration, mainHandCharges,
            mainHandEnchantID, existingTrackTimes)
        if enchantData then
            table.insert(allAuras, enchantData)
            if self.DEBUG then
                print(string.format("BoxxyAuras: Added main hand weapon enchant: %s (expires in: %.1fs)",
                    enchantData.name or "Unknown", mainHandExpiration / 1000))
            end
        end
    end

    -- Off hand weapon enchant
    if hasOffHandEnchant and offHandExpiration and offHandExpiration > 0 then
        local enchantData = self:CreateWeaponEnchantAuraData("offhand", offHandExpiration, offHandCharges,
            offHandEnchantID, existingTrackTimes)
        if enchantData then
            table.insert(allAuras, enchantData)
            if self.DEBUG then
                print(string.format("BoxxyAuras: Added off hand weapon enchant: %s (expires in: %.1fs)",
                    enchantData.name or "Unknown", offHandExpiration / 1000))
            end
        end
    end

    -- Ranged weapon enchant (for older expansions)
    if hasRangedEnchant and rangedExpiration and rangedExpiration > 0 then
        local enchantData = self:CreateWeaponEnchantAuraData("ranged", rangedExpiration, rangedCharges, rangedEnchantID,
            existingTrackTimes)
        if enchantData then
            table.insert(allAuras, enchantData)
            if self.DEBUG then
                print(string.format("BoxxyAuras: Added ranged weapon enchant: %s (expires in: %.1fs)",
                    enchantData.name or "Unknown", rangedExpiration / 1000))
            end
        end
    end

    if self.DEBUG then
        print(string.format("Weapon enchant scan: MH=%s, OH=%s, Ranged=%s",
            tostring(hasMainHandEnchant), tostring(hasOffHandEnchant), tostring(hasRangedEnchant)))
    end
end

-- Create aura data structure for weapon enchants
function BoxxyAuras:CreateWeaponEnchantAuraData(slot, expiration, charges, enchantID, existingTrackTimes)
    -- Generate a unique instance ID for weapon enchants
    local instanceId = "weapon_enchant_" .. slot .. "_" .. (enchantID or 0)

    -- Look up existing track time from the provided lookup table
    local cachedTrackTime = existingTrackTimes and existingTrackTimes[instanceId]

    -- For weapon enchants, we just get the weapon information
    -- Following Blizzard's UI pattern: show weapon icon and weapon tooltip
    local weaponName, weaponIcon, weaponQuality, slotID = self:GetWeaponEnchantDetails(slot, enchantID)

    -- Build color-coded display name using weapon name and quality
    local displayName = weaponName
    if weaponName and weaponQuality then
        local qualityColor = ITEM_QUALITY_COLORS[weaponQuality]
        if qualityColor then
            displayName = string.format("|c%s%s|r", qualityColor.hex, weaponName)
        end
    elseif not weaponName then
        -- Fallback name if we can't get weapon info
        if slot == "mainhand" then
            displayName = "Main Hand Weapon"
        elseif slot == "offhand" then
            displayName = "Off Hand Weapon"
        else
            displayName = "Weapon"
        end

        if self.DEBUG then
            print(string.format("Using fallback name for %s weapon enchant (enchantID: %d)", slot, enchantID or 0))
        end
    end

    if not weaponIcon then
        -- Use a generic weapon icon as fallback
        weaponIcon = 135913 -- Generic enchant glow icon
    end

    -- Calculate expiration time (expiration is in milliseconds from GetWeaponEnchantInfo)
    local expirationTime = 0
    local duration = 0
    if expiration and expiration > 0 then
        expirationTime = GetTime() + (expiration / 1000)
        duration = expiration / 1000
    else
        return nil -- No valid expiration means no enchant
    end

    -- Use cached originalTrackTime if available, otherwise set to current time for new enchants
    -- This keeps weapon enchants in a stable position in the sort order
    local originalTrackTime = cachedTrackTime or GetTime()

    return {
        name = displayName, -- Color-coded weapon name
        icon = weaponIcon,  -- Weapon icon
        duration = duration,
        expirationTime = expirationTime,
        applications = charges and charges > 0 and charges or nil,
        spellId = nil,                        -- Set to nil - we'll use inventory tooltip instead
        enchantID = enchantID,                -- Store the original enchant ID
        auraInstanceID = instanceId,
        slot = 0,                             -- Weapon enchants don't use normal aura slots
        auraType = "HELPFUL",                 -- Weapon enchants are helpful effects
        dispelName = nil,                     -- Weapon enchants typically can't be dispelled
        isWeaponEnchant = true,               -- Flag to identify as weapon enchant
        weaponSlot = slot,                    -- Track which weapon slot (mainhand/offhand)
        slotID = slotID,                      -- Inventory slot ID (16 or 17) for tooltip
        weaponName = weaponName,              -- Store weapon name separately
        weaponQuality = weaponQuality,        -- Store weapon quality for coloring
        originalTrackTime = originalTrackTime -- Add for sorting consistency
    }
end

-- Get weapon enchant details - simplified to just return weapon info (matching Blizzard UI)
function BoxxyAuras:GetWeaponEnchantDetails(slot, enchantID)
    -- First, check if we have cached weapon info for this slot and enchant ID
    local cacheKey = slot .. "_" .. (enchantID or 0)
    if self.weaponEnchantCache[cacheKey] then
        if self.DEBUG then
            print(string.format("Using cached weapon info for %s enchant", slot))
        end
        return self.weaponEnchantCache[cacheKey].weaponName,
            self.weaponEnchantCache[cacheKey].weaponIcon,
            self.weaponEnchantCache[cacheKey].weaponQuality,
            self.weaponEnchantCache[cacheKey].slotID
    end

    -- Get weapon information from inventory slot
    local slotID = (slot == "mainhand") and 16 or 17 -- Main hand = 16, Off hand = 17

    local weaponName = nil
    local weaponIcon = nil
    local weaponQuality = nil

    -- Get weapon icon
    weaponIcon = GetInventoryItemTexture("player", slotID)

    -- Get weapon name and quality from item link
    local itemLink = GetInventoryItemLink("player", slotID)
    if itemLink then
        weaponName = GetItemInfo(itemLink)
        local _, _, itemQuality = GetItemInfo(itemLink)
        weaponQuality = itemQuality
    end

    if self.DEBUG then
        print(string.format("Weapon enchant on %s: weapon='%s', quality=%s, icon=%s",
            slot, tostring(weaponName), tostring(weaponQuality), tostring(weaponIcon)))
    end

    -- Cache the weapon info including originalTrackTime for stable sorting
    if weaponName and weaponIcon then
        -- Preserve existing originalTrackTime if it exists
        local existingTrackTime = self.weaponEnchantCache[cacheKey] and
            self.weaponEnchantCache[cacheKey].originalTrackTime
        self.weaponEnchantCache[cacheKey] = {
            weaponName = weaponName,
            weaponIcon = weaponIcon,
            weaponQuality = weaponQuality,
            slotID = slotID,
            enchantID = enchantID,
            slot = slot,
            originalTrackTime = existingTrackTime or GetTime()
        }
    end

    return weaponName, weaponIcon, weaponQuality, slotID
end

-- Helper function to get the full enchant spell name from a shortened version
function BoxxyAuras:GetFullEnchantName(shortName)
    if not shortName then return nil end

    local lowerName = string.lower(shortName)

    -- Map common shortened enchant names to their full spell names
    local enchantNameMap = {
        windfury = "Windfury Weapon",
        flametongue = "Flametongue Weapon",
        frostbrand = "Frostbrand Weapon",
        earthliving = "Earthliving Weapon",
        rockbiter = "Rockbiter Weapon",
    }

    -- Check if we have a mapping for this enchant
    for short, full in pairs(enchantNameMap) do
        if string.find(lowerName, short) then
            return full
        end
    end

    -- If no mapping found, return the original name (may already have "Weapon" suffix)
    return shortName
end

-- Helper function to get the actual spell ID for an enchant (for proper tooltips)
function BoxxyAuras:GetEnchantSpellId(enchantName)
    if not enchantName then return nil end

    local lowerName = string.lower(enchantName)

    -- Map enchant names to their spell IDs (the actual spell that applies the buff)
    -- Multiple IDs are tried in order - different expansions use different spell IDs
    local enchantSpellMap = {
        ["windfury weapon"] = { 33757, 8232, 10486 },     -- Windfury Weapon (various ranks/expansions)
        ["flametongue weapon"] = { 318038, 8024, 10526 }, -- Flametongue Weapon (Shadowlands+, Classic, TBC)
        ["frostbrand weapon"] = { 196834, 8033, 8038 },   -- Frostbrand Weapon (Legion+, Classic, TBC)
        ["earthliving weapon"] = { 51730 },               -- Earthliving Weapon (WotLK+)
        ["rockbiter weapon"] = { 193796, 8017, 8018 },    -- Rockbiter Weapon (Legion+, Classic, TBC)
    }

    -- Helper function to check if a spell ID exists and return it
    local function validateSpellId(spellId)
        if not spellId then return nil end
        -- Use C_Spell.GetSpellName for modern WoW API
        local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId) or
            GetSpellInfo and GetSpellInfo(spellId)
        return spellName and spellId or nil
    end

    -- Try exact match first
    local spellIds = enchantSpellMap[lowerName]
    if spellIds then
        -- If it's a table, try each spell ID in order
        if type(spellIds) == "table" then
            for _, spellId in ipairs(spellIds) do
                local validId = validateSpellId(spellId)
                if validId then
                    if self.DEBUG then
                        print(string.format("Found valid spell ID %d for '%s'", validId, enchantName))
                    end
                    return validId
                end
            end
        else
            return validateSpellId(spellIds)
        end
    end

    -- Try partial match
    for enchant, spellIds in pairs(enchantSpellMap) do
        if string.find(lowerName, enchant) then
            if type(spellIds) == "table" then
                for _, spellId in ipairs(spellIds) do
                    local validId = validateSpellId(spellId)
                    if validId then
                        if self.DEBUG then
                            print(string.format("Found valid spell ID %d for '%s' (partial match)", validId, enchantName))
                        end
                        return validId
                    end
                end
            else
                return validateSpellId(spellIds)
            end
        end
    end

    if self.DEBUG then
        print(string.format("No valid spell ID found for '%s'", enchantName))
    end

    return nil
end

-- Check if text represents a temporary weapon enchant
function BoxxyAuras:IsTemporaryEnchantText(text)
    if not text then return false end

    local lowerText = string.lower(text)

    -- First, exclude common weapon stat lines and item properties
    local excludePatterns = {
        "%+%d+ critical strike",
        "%+%d+ haste",
        "%+%d+ mastery",
        "%+%d+ versatility",
        "%+%d+ stamina",
        "%+%d+ strength",
        "%+%d+ agility",
        "%+%d+ intellect",
        "durability",
        "binds when",
        "item level",
        "requires level",
        "unique%-equipped",
        "sell price",
        "speed",
        "damage per second",
        "damage",
        "armor",
    }

    for _, pattern in ipairs(excludePatterns) do
        if string.find(lowerText, pattern) then
            return false
        end
    end

    -- Look for common temporary enchant keywords
    -- These are broad patterns that should catch most temporary weapon buffs
    local enchantKeywords = {
        "weapon",      -- Catches "Windfury Weapon", "Flametongue Weapon", etc.
        "oil",         -- Weapon oils
        "stone",       -- Sharpening/grinding stones
        "poison",      -- Rogue poisons
        "imbue",       -- General imbue effects
        "venom",       -- Poison variants
        "sharpened",   -- Sharpening effects
        "weighted",    -- Weightstone effects
        "windfury",    -- Shaman enchants
        "flametongue", -- Shaman enchants
        "frostbrand",  -- Shaman enchants
        "earthliving", -- Shaman enchants
        "rockbiter",   -- Shaman enchants
    }

    for _, keyword in ipairs(enchantKeywords) do
        if string.find(lowerText, keyword) then
            -- Found a potential enchant keyword
            -- Make sure it's not part of the weapon name itself by checking
            -- if it's in a line that looks like an enchant effect
            return true
        end
    end

    -- Also check for pattern like "Something (X min)" or "Something (X sec)"
    -- which is very common for temporary enchants
    if string.find(lowerText, "%(%d+ min%)") or string.find(lowerText, "%(%d+ sec%)") then
        return true
    end

    return false
end

-- Try to get enchant information directly from enchant ID
-- This is now a minimal fallback - we prefer tooltip scanning
function BoxxyAuras:GetEnchantInfoFromID(enchantID)
    if not enchantID then return nil, nil end

    -- Only keep a minimal set of static fallbacks for common enchants
    -- These are used only if tooltip scanning fails
    local knownEnchantNames = {
        [5401] = { name = "Windfury Weapon", icon = 136018 },
        [283] = { name = "Windfury Weapon", icon = 136018 },
        [5] = { name = "Flametongue Weapon", icon = 135814 },
        [5400] = { name = "Flametongue Weapon", icon = 135814 }, -- Another Flametongue ID
        [2] = { name = "Frostbrand Weapon", icon = 135847 },
        [1] = { name = "Rockbiter Weapon", icon = 136086 },
        [3021] = { name = "Earthliving Weapon", icon = 136026 },
    }

    local knownEnchant = knownEnchantNames[enchantID]
    if knownEnchant then
        if self.DEBUG then
            print(string.format("Using static fallback for enchantID %d: '%s'", enchantID, knownEnchant.name))
        end
        return knownEnchant.name, knownEnchant.icon
    end

    if self.DEBUG then
        print(string.format("No static fallback for enchantID: %d", enchantID))
    end

    return nil, nil
end -- Try to get an appropriate icon for the enchant based on its name

function BoxxyAuras:GetEnchantIconFromName(enchantName)
    if not enchantName then return nil end

    local name = string.lower(enchantName)

    -- Common shaman weapon imbues
    if string.find(name, "windfury") then
        return 136018 -- Windfury weapon icon
    elseif string.find(name, "flametongue") then
        return 135814 -- Flametongue weapon icon
    elseif string.find(name, "frostbrand") then
        return 135847 -- Frostbrand weapon icon
    elseif string.find(name, "earthliving") then
        return 136026 -- Earthliving weapon icon
    elseif string.find(name, "rockbiter") then
        return 136086 -- Rockbiter weapon icon
        -- Common temporary weapon oils/enchants
    elseif string.find(name, "oil") then
        return 134939 -- Generic oil icon
    elseif string.find(name, "poison") or string.find(name, "venom") then
        return 132273 -- Poison icon
    elseif string.find(name, "stone") or string.find(name, "sharp") or string.find(name, "weight") then
        return 135225 -- Sharpening/grinding stone icon
    end

    -- Default enchant icon for unrecognized enchants
    return 135913
end

-- Scan and cache weapon enchant information for all equipped weapons
function BoxxyAuras:ScanAndCacheWeaponEnchants()
    -- Get current weapon enchant info
    local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID,
    hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID = GetWeaponEnchantInfo()

    if self.DEBUG then
        print("BoxxyAuras: Scanning weapon enchants...")
        print(string.format("  Main Hand: hasEnchant=%s, ID=%s", tostring(hasMainHandEnchant),
            tostring(mainHandEnchantID)))
        print(string.format("  Off Hand: hasEnchant=%s, ID=%s", tostring(hasOffHandEnchant), tostring(offHandEnchantID)))
    end

    -- Clear cache entries for slots that no longer have enchants
    if not hasMainHandEnchant then
        for key in pairs(self.weaponEnchantCache) do
            if string.find(key, "^mainhand_") then
                self.weaponEnchantCache[key] = nil
                if self.DEBUG then
                    print("  Cleared mainhand cache entry: " .. key)
                end
            end
        end
    end

    if not hasOffHandEnchant then
        for key in pairs(self.weaponEnchantCache) do
            if string.find(key, "^offhand_") then
                self.weaponEnchantCache[key] = nil
                if self.DEBUG then
                    print("  Cleared offhand cache entry: " .. key)
                end
            end
        end
    end

    -- Scan and cache main hand enchant if present
    if hasMainHandEnchant and mainHandEnchantID then
        self:GetWeaponEnchantDetails("mainhand", mainHandEnchantID)
    end

    -- Scan and cache off hand enchant if present
    if hasOffHandEnchant and offHandEnchantID then
        self:GetWeaponEnchantDetails("offhand", offHandEnchantID)
    end

    if self.DEBUG then
        print("BoxxyAuras: Weapon enchant scan complete")
    end
end

function BoxxyAuras:GetSortedAurasForFrame(frameType)
    local allAuras = {}
    local currentSettings = self:GetCurrentProfileSettings()

    -- Build a lookup of existing originalTrackTime values to preserve sort order
    local existingTrackTimes = {}
    if self.auraTracking and self.auraTracking[frameType] then
        for _, trackedAura in ipairs(self.auraTracking[frameType]) do
            if trackedAura.auraInstanceID and trackedAura.originalTrackTime then
                existingTrackTimes[trackedAura.auraInstanceID] = trackedAura.originalTrackTime
            end
        end
    end

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
                            -- Preserve originalTrackTime from existing tracked auras, or set to current time for new auras
                            auraData.originalTrackTime = existingTrackTimes[auraData.auraInstanceID] or GetTime()
                            table.insert(allAuras, auraData)
                        end
                    end
                end
            end

            -- Add weapon enchants for custom frames (they can show as helpful effects)
            self:AddWeaponEnchantsToAuraList(allAuras, existingTrackTimes)
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
                        -- Preserve originalTrackTime from existing tracked auras, or set to current time for new auras
                        auraData.originalTrackTime = existingTrackTimes[auraData.auraInstanceID] or GetTime()
                        table.insert(allAuras, auraData)
                    end
                end
            end

            -- Add weapon enchants to Buff frames (they are helpful effects)
            if filter == "HELPFUL" then
                self:AddWeaponEnchantsToAuraList(allAuras, existingTrackTimes)
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
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Combat end event
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED") -- Weapon enchant events

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

        -- Initialize healing absorb tracking
        BoxxyAuras:InitializeHealingAbsorbTracking()

        -- Scan and cache weapon enchants on login
        BoxxyAuras:ScanAndCacheWeaponEnchants()

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
            (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" or subevent == "SPELL_AURA_APPLIED_DOSE") then
            if spellId and sourceGUID then
                -- Store this for quick lookup when processing new auras
                table.insert(BoxxyAuras.recentAuraEvents, {
                    spellId = spellId,
                    sourceGUID = sourceGUID,
                    sourceName = sourceName,
                    timestamp = GetTime()
                })
            end

            -- NEW: Check if this debuff application/refresh caused a healing absorb increase
            if spellId and spellName then
                -- Use a small delay to ensure the aura is fully applied before checking absorb amounts
                C_Timer.After(0.1, function()
                    if subevent == "SPELL_AURA_REFRESH" then
                        -- Handle refresh separately to reset progress bars to full
                        BoxxyAuras:HandleHealingAbsorbRefresh(spellId, spellName)
                    else
                        -- Handle new applications normally
                        BoxxyAuras:CheckForHealingAbsorbIncrease(spellId, spellName)
                    end
                end)
            end
        end

        -- Handle healing events to re-sync our tracked absorb amount
        if destName and destName == UnitName("player") and
            (subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL") then
            -- Healing occurred - re-sync our tracked amount
            C_Timer.After(0.1, function()
                BoxxyAuras:UpdateTrackedHealingAbsorbAmount()
            end)
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
                            if BoxxyAuras.healingAbsorbTracking and BoxxyAuras.healingAbsorbTracking[trackingKey] then
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

            if BoxxyAuras.DEBUG then
                print(string.format(
                    "Healing Absorb Event: %s, spellId=%s, sourceGUID=%s, destGUID=%s, absorbedAmount=%s (type:%s), totalAmount=%s",
                    subevent, tostring(absorbSpellId), tostring(sourceGUID), tostring(destGUID),
                    tostring(absorbedAmount), type(absorbedAmount), tostring(totalAmount)))
            end

            -- Initialize tracking if this is the first time we see this absorb in action
            if absorbedAmount and type(absorbedAmount) == "number" and absorbedAmount > 0 then
                if not BoxxyAuras.healingAbsorbTracking then
                    BoxxyAuras.healingAbsorbTracking = {}
                end

                -- Try to find existing tracking or create new tracking
                local trackingKey = nil
                local trackingData = nil
                local auraData = nil

                -- First, try to find existing tracking by spell ID (broader search)
                for key, data in pairs(BoxxyAuras.healingAbsorbTracking) do
                    if data.spellId == absorbSpellId and not data.fullyConsumed then
                        trackingKey = key
                        trackingData = data
                        if BoxxyAuras.DEBUG then
                            print(string.format("Found existing tracking for spellId %d with key %s", absorbSpellId,
                                tostring(key)))
                        end
                        break
                    end
                end

                -- If no existing tracking found, search for current aura and create new tracking
                if not trackingData then
                    -- Search through all tracked auras to find this spell ID
                    for frameType, auras in pairs(BoxxyAuras.auraTracking or {}) do
                        for _, aura in ipairs(auras) do
                            if aura and aura.spellId == absorbSpellId and aura.auraType == "HARMFUL" then
                                trackingKey = aura.auraInstanceID or aura.spellId
                                auraData = aura

                                if BoxxyAuras.DEBUG then
                                    print(string.format("Found aura for new tracking: %s (instanceID=%s, spellId=%d)",
                                        aura.name or "Unknown", tostring(aura.auraInstanceID), aura.spellId))
                                end
                                break
                            end
                        end
                        if auraData then break end
                    end

                    if auraData then
                        -- Try to get initial amount from aura data
                        local initialAmount = 0

                        -- Check aura points array first
                        if auraData.points and type(auraData.points) == "table" and #auraData.points > 0 then
                            for i, point in ipairs(auraData.points) do
                                if point and point > 0 then
                                    initialAmount = point
                                    if BoxxyAuras.DEBUG then
                                        print(string.format("Got initial amount from aura points: %d", initialAmount))
                                    end
                                    break
                                end
                            end
                        end

                        -- Fallback: estimate based on absorbed amount
                        if initialAmount <= 0 then
                            -- Use a more conservative multiplier and add some buffer
                            initialAmount = math.max(absorbedAmount * 10, absorbedAmount + 500000)
                            if BoxxyAuras.DEBUG then
                                print(string.format("Estimated initial amount: %d (based on absorbed: %d)", initialAmount,
                                    absorbedAmount))
                            end
                        end

                        trackingData = {
                            initialAmount = initialAmount,
                            currentAmount = initialAmount, -- Start with full amount, we'll subtract below
                            spellId = absorbSpellId,
                            auraInstanceID = auraData.auraInstanceID,
                            lastUpdate = GetTime(),
                            fullyConsumed = false
                        }
                        if not BoxxyAuras.healingAbsorbTracking then
                            BoxxyAuras.healingAbsorbTracking = {}
                        end
                        BoxxyAuras.healingAbsorbTracking[trackingKey] = trackingData

                        if BoxxyAuras.DEBUG then
                            print(string.format(
                                "Created new healing absorb tracking for spellId %d, instanceID %s (initial: %d, source: %s)",
                                absorbSpellId, tostring(auraData.auraInstanceID), initialAmount,
                                (auraData.points and #auraData.points > 0) and "aura_points" or "estimate"))
                        end
                    end
                end

                -- Now process the absorb if we have tracking data
                if trackingData then
                    local oldAmount = trackingData.currentAmount
                    trackingData.currentAmount = math.max(0, trackingData.currentAmount - absorbedAmount)
                    trackingData.lastUpdate = GetTime()

                    -- Cancel cleanup timer if it exists (we got new absorption activity)
                    if trackingData.cleanupTimer then
                        trackingData.cleanupTimer:Cancel()
                        trackingData.cleanupTimer = nil
                    end

                    if BoxxyAuras.DEBUG then
                        print(string.format("Updated absorb tracking: %d -> %d (absorbed: %d)",
                            oldAmount, trackingData.currentAmount, absorbedAmount))
                    end

                    -- Check if the absorb is fully consumed
                    if trackingData.currentAmount <= 0 then
                        -- Don't immediately remove tracking, just mark as consumed
                        trackingData.fullyConsumed = true
                        -- Update visuals to hide the progress bar
                        BoxxyAuras:UpdateHealingAbsorbVisuals(trackingKey, nil)

                        -- Set a timer to clean up after a delay
                        trackingData.cleanupTimer = C_Timer.NewTimer(5, function()
                            if BoxxyAuras.healingAbsorbTracking and BoxxyAuras.healingAbsorbTracking[trackingKey] then
                                BoxxyAuras.healingAbsorbTracking[trackingKey] = nil
                            end
                        end)
                    else
                        -- Update the visual progress bar
                        BoxxyAuras:UpdateHealingAbsorbVisuals(trackingKey, trackingData)
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
                            -- Skip expired auras - we only want to shake active auras
                            local isExpiredAura = false
                            if trackedAura.forceExpired then
                                isExpiredAura = true
                            elseif trackedAura.expirationTime and trackedAura.expirationTime > 0 then
                                isExpiredAura = trackedAura.expirationTime <= GetTime()
                            end

                            if trackedAura and trackedAura.spellId == spellId and
                                (trackedAura.auraType == "HARMFUL" or trackedAura.originalAuraType == "HARMFUL") and
                                not isExpiredAura then -- Only shake active (non-expired) auras
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
    elseif event == "WEAPON_ENCHANT_CHANGED" then
        -- Weapon enchant changed, scan and cache enchant information
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: WEAPON_ENCHANT_CHANGED event received")
        end

        -- Scan and cache weapon enchant names from tooltips
        BoxxyAuras:ScanAndCacheWeaponEnchants()

        -- Trigger aura update to include/remove weapon enchants
        BoxxyAuras.UpdateAuras()
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
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: UpdateHealingAbsorbVisuals called without trackingKey")
        end
        return
    end

    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Updating healing absorb visuals for '%s'", trackingKey))
    end

    -- Find all icons that match this absorb and update their progress bars
    local foundMatch = false
    for frameType, iconArray in pairs(self.iconArrays or {}) do
        if iconArray then
            for _, icon in ipairs(iconArray) do
                if icon and icon.frame and (icon.auraInstanceID or icon.spellId) then
                    -- Check if this icon matches the tracking key
                    local iconTrackingKey = icon.auraInstanceID or icon.spellId
                    local spellIdMatch = false

                    -- First try exact tracking key match
                    local isMatch = (tostring(iconTrackingKey) == tostring(trackingKey))

                    -- If no exact match, try spell ID match for healing absorbs
                    if not isMatch and trackingData and trackingData.spellId and icon.spellId then
                        isMatch = (icon.spellId == trackingData.spellId and icon.auraType == "HARMFUL")
                        spellIdMatch = true
                    end

                    if BoxxyAuras.DEBUG then
                        print(string.format(
                            "  Checking icon: %s (instanceID=%s, spellId=%s) against trackingKey=%s (match=%s, spellIdMatch=%s)",
                            icon.name or "Unknown", tostring(icon.auraInstanceID), tostring(icon.spellId),
                            tostring(trackingKey), tostring(isMatch), tostring(spellIdMatch)))
                    end

                    if isMatch then
                        foundMatch = true

                        -- CRITICAL: Skip all updates for expired auras in UpdateHealingAbsorbVisuals
                        -- The AuraIcon:Display method is the sole authority for expired aura progress bars
                        local isIconExpired = false
                        if icon.isExpired then
                            isIconExpired = true
                        elseif icon.expirationTime and icon.expirationTime > 0 then
                            isIconExpired = icon.expirationTime <= GetTime()
                        end

                        if isIconExpired then
                            if BoxxyAuras.DEBUG then
                                print(string.format(
                                    "BoxxyAuras: Skipping visual update for expired aura '%s' (instanceID=%s) - AuraIcon:Display handles expired auras",
                                    icon.name or "Unknown", tostring(icon.auraInstanceID)))
                            end
                            -- Do NOT touch expired auras here - let AuraIcon:Display handle them
                        elseif icon.frame.absorbProgressBar then
                            -- This is an active (non-expired) aura, update its progress bar
                            if trackingData and trackingData.initialAmount and trackingData.initialAmount > 0 and not trackingData.fullyConsumed then
                                -- Update progress bar for active auras only
                                local percentage = math.max(0, trackingData.currentAmount / trackingData.initialAmount)
                                icon.frame.absorbProgressBar:SetValue(percentage)
                                icon.frame.absorbProgressBar:Show()

                                if BoxxyAuras.DEBUG then
                                    print(string.format("BoxxyAuras: Updated absorb bar for '%s' to %.1f%% (%d/%d)",
                                        icon.name or "Unknown", percentage * 100, trackingData.currentAmount,
                                        trackingData.initialAmount))
                                end
                            else
                                -- Hide progress bar (tracking data is nil or absorb is consumed)
                                icon.frame.absorbProgressBar:Hide()
                                if BoxxyAuras.DEBUG then
                                    print(string.format(
                                        "BoxxyAuras: Hiding absorb bar for '%s' (absorb consumed or tracking removed)",
                                        icon.name or "Unknown"))
                                end
                            end
                        else
                            if BoxxyAuras.DEBUG then
                                print(string.format("BoxxyAuras: Icon '%s' has no absorbProgressBar!",
                                    icon.name or "Unknown"))
                            end
                        end
                    end
                end
            end
        end
    end

    if not foundMatch and BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: No matching icon found for trackingKey '%s'", trackingKey))
        if trackingData and trackingData.spellId then
            print(string.format("  Also searched for spellId %d", trackingData.spellId))
        end
    end
end

-- =============================================================== --
-- Event-Driven Healing Absorb Detection System
-- =============================================================== --

-- Initialize the healing absorb tracking
function BoxxyAuras:InitializeHealingAbsorbTracking()
    self.healingAbsorbTracker.trackedAmount = UnitGetTotalHealAbsorbs("player") or 0
    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Initialized healing absorb tracking at %d",
            self.healingAbsorbTracker.trackedAmount))
    end
end

-- Update tracked amount (called after healing events to re-sync)
function BoxxyAuras:UpdateTrackedHealingAbsorbAmount()
    local currentAmount = UnitGetTotalHealAbsorbs("player") or 0
    local previousAmount = self.healingAbsorbTracker.trackedAmount

    if currentAmount ~= previousAmount then
        local amountChange = currentAmount - previousAmount

        if BoxxyAuras.DEBUG then
            print(string.format("BoxxyAuras: Healing absorb amount changed: %d -> %d (change: %+d)",
                previousAmount, currentAmount, amountChange))
        end

        -- Update our tracked amount
        self.healingAbsorbTracker.trackedAmount = currentAmount

        -- If healing absorbs changed, sync our tracking data and update visuals
        if amountChange ~= 0 then
            if BoxxyAuras.DEBUG then
                print(string.format("BoxxyAuras: Calling sync due to absorb change: %+d", amountChange))
            end

            self:SyncTrackingWithActualAbsorbs()

            -- Update all healing absorb visuals to reflect the new amounts
            if BoxxyAuras.DEBUG then
                print("BoxxyAuras: Updating visuals for all tracking data after sync")
            end

            for trackingKey, trackingData in pairs(self.healingAbsorbTracking or {}) do
                if trackingData then
                    self:UpdateHealingAbsorbVisuals(trackingKey, trackingData)
                    if BoxxyAuras.DEBUG then
                        print(string.format("BoxxyAuras: Updated visuals for key %s (current: %d, initial: %d)",
                            tostring(trackingKey), trackingData.currentAmount or 0, trackingData.initialAmount or 0))
                    end
                end
            end
        end
    end
end

-- Update progress bars when healing reduces absorb amounts
function BoxxyAuras:UpdateHealingAbsorbProgressBars(healingAmount)
    if not self.healingAbsorbTracking then
        return
    end

    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Updating progress bars after %d healing", healingAmount))
    end

    -- First pass: count active (non-expired) absorbs and their total amount
    local activeAbsorbs = {}
    local totalActiveAmount = 0

    for trackingKey, trackingData in pairs(self.healingAbsorbTracking) do
        if trackingData.currentAmount and trackingData.currentAmount > 0 then
            -- Check if this aura is still active (not expired AND not held due to hover)
            local isAuraActive = self:IsHealingAbsorbAuraActive(trackingData.spellId, trackingData.auraInstanceID)
            local isAuraHeld = self:IsHealingAbsorbAuraHeld(trackingData.spellId, trackingData.auraInstanceID)

            -- Only include auras that are truly active (not expired and not just held on hover)
            if isAuraActive and not isAuraHeld then
                activeAbsorbs[trackingKey] = trackingData
                totalActiveAmount = totalActiveAmount + trackingData.currentAmount

                if BoxxyAuras.DEBUG then
                    print(string.format("BoxxyAuras: Active absorb found - key: %s, amount: %d",
                        tostring(trackingKey), trackingData.currentAmount))
                end
            else
                if BoxxyAuras.DEBUG then
                    local reason = not isAuraActive and "expired" or "held on hover"
                    print(string.format("BoxxyAuras: Skipping %s absorb - SpellID: %d, InstanceID: %s",
                        reason, trackingData.spellId or 0, tostring(trackingData.auraInstanceID)))
                end
            end
        end
    end

    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Found %d active absorbs with total amount %d",
            self:TableCount(activeAbsorbs), totalActiveAmount))
    end

    -- If no active absorbs found, skip distribution but still update visuals to clear expired bars
    if self:TableCount(activeAbsorbs) == 0 then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: No active absorbs found, updating visuals to clear any remaining bars")
        end

        -- Update visuals for any tracking data to ensure expired auras show 0 progress
        for trackingKey, trackingData in pairs(self.healingAbsorbTracking) do
            -- For expired/held auras, pass nil as trackingData to hide/reset the progress bar
            self:UpdateHealingAbsorbVisuals(trackingKey, nil)
        end
        return
    end

    -- Second pass: distribute healing proportionally among active absorbs only
    for trackingKey, trackingData in pairs(activeAbsorbs) do
        if healingAmount <= 0 then
            break
        end

        -- Calculate proportional reduction based on this absorb's share of total active absorbs
        local proportionalReduction
        if totalActiveAmount > 0 then
            local proportion = trackingData.currentAmount / totalActiveAmount
            proportionalReduction = math.min(healingAmount * proportion, trackingData.currentAmount)
        else
            proportionalReduction = 0
        end

        -- Apply the reduction
        trackingData.currentAmount = trackingData.currentAmount - proportionalReduction
        trackingData.lastUpdate = GetTime()

        if trackingData.currentAmount <= 0 then
            trackingData.fullyConsumed = true
        end

        -- Update the visual progress bar
        self:UpdateHealingAbsorbVisuals(trackingKey, trackingData)

        if BoxxyAuras.DEBUG then
            print(string.format("BoxxyAuras: Updated tracking for key %s: %d/%d remaining (reduced by %.1f)",
                tostring(trackingKey), trackingData.currentAmount, trackingData.initialAmount, proportionalReduction))
        end

        healingAmount = healingAmount - proportionalReduction
    end
end -- Check if a healing absorb aura is still active (not expired)

function BoxxyAuras:IsHealingAbsorbAuraActive(spellId, auraInstanceID)
    if not spellId then
        return false
    end

    -- Search through all current aura tracking to see if this aura is still active
    for frameType, auras in pairs(self.auraTracking or {}) do
        for _, aura in ipairs(auras) do
            if aura and aura.spellId == spellId then
                -- If we have an instance ID, match it exactly
                if auraInstanceID and aura.auraInstanceID then
                    if aura.auraInstanceID == auraInstanceID then
                        -- Check if this aura is not marked as expired
                        local currentTime = GetTime()

                        -- Check for forced expiration flag
                        if aura.forceExpired then
                            return false
                        end

                        -- Check for time-based expiration
                        local isExpired = (aura.expirationTime and aura.expirationTime > 0 and
                            aura.expirationTime <= currentTime)
                        return not isExpired
                    end
                else
                    -- No instance ID to match, just check if any aura with this spell ID is active
                    local currentTime = GetTime()

                    -- Check for forced expiration flag
                    if not aura.forceExpired then
                        -- Check for time-based expiration
                        local isExpired = (aura.expirationTime and aura.expirationTime > 0 and
                            aura.expirationTime <= currentTime)
                        if not isExpired then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- Check if a healing absorb aura is being held on hover (expired but still displayed)
function BoxxyAuras:IsHealingAbsorbAuraHeld(spellId, auraInstanceID)
    if not spellId then
        return false
    end

    -- Search through all current aura tracking to see if this aura is held due to hover
    for frameType, auras in pairs(self.auraTracking or {}) do
        for _, aura in ipairs(auras) do
            if aura and aura.spellId == spellId then
                -- If we have an instance ID, match it exactly
                if auraInstanceID and aura.auraInstanceID then
                    if aura.auraInstanceID == auraInstanceID then
                        -- Return true if this aura is marked as forceExpired (held on hover)
                        return aura.forceExpired or false
                    end
                else
                    -- No instance ID to match, check if any aura with this spell ID is held
                    if aura.forceExpired then
                        return true
                    end
                end
            end
        end
    end

    return false
end -- Check if a debuff application caused healing absorb increase

function BoxxyAuras:CheckForHealingAbsorbIncrease(spellId, spellName)
    local currentAmount = UnitGetTotalHealAbsorbs("player") or 0
    local trackedAmount = self.healingAbsorbTracker.trackedAmount

    if currentAmount > trackedAmount then
        local increase = currentAmount - trackedAmount

        -- This spell caused a healing absorb increase - mark it as confirmed
        self.healingAbsorbTracker.confirmedAbsorbs[spellId] = {
            spellName = spellName,
            confirmedAt = GetTime(),
            sampleIncrease = increase
        }

        -- Update our tracked amount
        self.healingAbsorbTracker.trackedAmount = currentAmount

        if BoxxyAuras.DEBUG then
            print(string.format("BoxxyAuras: Confirmed healing absorb - %s (%d) increased absorbs by %d (total: %d)",
                spellName or "Unknown", spellId, increase, currentAmount))
        end

        return true
    end

    return false
end

-- Handle healing absorb aura refresh - reset progress bars to full
function BoxxyAuras:HandleHealingAbsorbRefresh(spellId, spellName)
    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Handling healing absorb refresh for %s (%d)", spellName or "Unknown", spellId))
    end

    -- First, check if this actually increased the total absorb amount
    local currentAmount = UnitGetTotalHealAbsorbs("player") or 0
    local trackedAmount = self.healingAbsorbTracker.trackedAmount
    local actualIncrease = currentAmount - trackedAmount

    if actualIncrease > 0 then
        -- The refresh increased absorbs, treat as a new application
        self.healingAbsorbTracker.trackedAmount = currentAmount

        if BoxxyAuras.DEBUG then
            print(string.format("BoxxyAuras: Refresh increased absorbs by %d (total: %d)", actualIncrease, currentAmount))
        end
    end

    -- Find existing tracking data for this spell and refresh it
    local refreshedTracking = false
    local oldTrackingKeys = {}

    -- First, collect all tracking keys for this spell ID
    for trackingKey, trackingData in pairs(self.healingAbsorbTracking or {}) do
        if trackingData.spellId == spellId then
            table.insert(oldTrackingKeys, trackingKey)
        end
    end

    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Found %d existing tracking entries for spell %d", #oldTrackingKeys, spellId))
    end

    for _, trackingKey in ipairs(oldTrackingKeys) do
        local trackingData = self.healingAbsorbTracking[trackingKey]
        if trackingData then
            -- Check if this tracking key corresponds to the current active aura
            local isCurrentAura = self:IsHealingAbsorbAuraActive(trackingData.spellId, trackingData.auraInstanceID)

            if isCurrentAura then
                -- This is the current active aura, refresh it
                local newAbsorbAmount = self:GetCurrentAbsorbAmountForSpell(spellId)

                if newAbsorbAmount and newAbsorbAmount > 0 then
                    -- Reset tracking data to full amount
                    trackingData.initialAmount = newAbsorbAmount
                    trackingData.currentAmount = newAbsorbAmount
                    trackingData.lastUpdate = GetTime()
                    trackingData.fullyConsumed = false

                    -- Update the visual progress bar to show full (100%)
                    self:UpdateHealingAbsorbVisuals(trackingKey, trackingData)

                    refreshedTracking = true

                    if BoxxyAuras.DEBUG then
                        print(string.format("BoxxyAuras: Refreshed active tracking for key %s with new amount %d",
                            tostring(trackingKey), newAbsorbAmount))
                    end
                else
                    -- Fallback: Use the increase amount or estimate
                    local refreshAmount = actualIncrease > 0 and actualIncrease or (trackingData.initialAmount or 100000)
                    trackingData.initialAmount = refreshAmount
                    trackingData.currentAmount = refreshAmount
                    trackingData.lastUpdate = GetTime()
                    trackingData.fullyConsumed = false

                    self:UpdateHealingAbsorbVisuals(trackingKey, trackingData)
                    refreshedTracking = true

                    if BoxxyAuras.DEBUG then
                        print(string.format("BoxxyAuras: Refreshed active tracking for key %s with fallback amount %d",
                            tostring(trackingKey), refreshAmount))
                    end
                end
            else
                -- This is an old/inactive aura, remove its tracking
                if BoxxyAuras.DEBUG then
                    print(string.format("BoxxyAuras: Removing old tracking for key %s (inactive aura)",
                        tostring(trackingKey)))
                end
                self:UpdateHealingAbsorbVisuals(trackingKey, nil) -- Hide progress bar
                self.healingAbsorbTracking[trackingKey] = nil
            end
        end
    end
    if not refreshedTracking then
        -- No existing tracking found, treat as new application
        if BoxxyAuras.DEBUG then
            print(string.format("BoxxyAuras: No existing tracking found for refresh, treating as new application"))
        end
        self:CheckForHealingAbsorbIncrease(spellId, spellName)
    end
end

-- Get the current absorb amount for a specific spell ID from aura data
function BoxxyAuras:GetCurrentAbsorbAmountForSpell(spellId)
    -- Search through current aura tracking to find this spell
    for frameType, auras in pairs(self.auraTracking or {}) do
        for _, aura in ipairs(auras) do
            if aura and aura.spellId == spellId and aura.auraType == "HARMFUL" then
                -- Try to get absorb amount from aura points
                if aura.points and type(aura.points) == "table" and #aura.points > 0 then
                    for i, point in ipairs(aura.points) do
                        if point and point > 0 then
                            return point
                        end
                    end
                end

                -- Fallback: Try other methods to determine absorb amount
                -- Could expand this with tooltip scanning if needed
                break
            end
        end
    end

    return nil
end

-- Sync our tracking data with actual absorb amounts to prevent drift
function BoxxyAuras:SyncTrackingWithActualAbsorbs()
    local actualTotalAbsorbs = UnitGetTotalHealAbsorbs("player") or 0

    -- Calculate what our tracking data thinks the total should be
    local trackedTotal = 0
    local activeTrackingData = {}
    local inactiveTrackingKeys = {}

    for trackingKey, trackingData in pairs(self.healingAbsorbTracking or {}) do
        if trackingData.currentAmount and trackingData.currentAmount > 0 and not trackingData.fullyConsumed then
            -- Only count tracking data for auras that are still active
            local isActive = self:IsHealingAbsorbAuraActive(trackingData.spellId, trackingData.auraInstanceID)
            local isHeld = self:IsHealingAbsorbAuraHeld(trackingData.spellId, trackingData.auraInstanceID)

            if BoxxyAuras.DEBUG then
                print(string.format("BoxxyAuras: Checking tracking key %s - current: %d, active: %s, held: %s",
                    tostring(trackingKey), trackingData.currentAmount, tostring(isActive), tostring(isHeld)))
            end

            if isActive and not isHeld then
                trackedTotal = trackedTotal + trackingData.currentAmount
                table.insert(activeTrackingData, { key = trackingKey, data = trackingData })

                if BoxxyAuras.DEBUG then
                    print(string.format("BoxxyAuras: Added to active tracking - key: %s, amount: %d",
                        tostring(trackingKey), trackingData.currentAmount))
                end
            else
                -- Mark for cleanup if not active and not held
                if not isActive and not isHeld then
                    table.insert(inactiveTrackingKeys, trackingKey)
                    if BoxxyAuras.DEBUG then
                        print(string.format("BoxxyAuras: Marked inactive tracking key %s for cleanup",
                            tostring(trackingKey)))
                    end
                end
            end
        else
            -- Mark fully consumed or zero-amount tracking for cleanup
            table.insert(inactiveTrackingKeys, trackingKey)
            if BoxxyAuras.DEBUG then
                print(string.format("BoxxyAuras: Marked consumed/zero tracking key %s for cleanup", tostring(trackingKey)))
            end
        end
    end

    -- Clean up inactive tracking data
    for _, keyToRemove in ipairs(inactiveTrackingKeys) do
        if self.healingAbsorbTracking[keyToRemove] then
            if BoxxyAuras.DEBUG then
                print(string.format("BoxxyAuras: Removing inactive tracking key %s", tostring(keyToRemove)))
            end
            -- Update visuals to hide the progress bar before removing
            self:UpdateHealingAbsorbVisuals(keyToRemove, nil)
            self.healingAbsorbTracking[keyToRemove] = nil
        end
    end
    if BoxxyAuras.DEBUG then
        print(string.format("BoxxyAuras: Sync check - Actual: %d, Tracked: %d, Difference: %d",
            actualTotalAbsorbs, trackedTotal, actualTotalAbsorbs - trackedTotal))
    end

    -- If there's a significant difference, adjust our tracking proportionally
    if trackedTotal > 0 and (math.abs(actualTotalAbsorbs - trackedTotal) > 100 or actualTotalAbsorbs == 0) then -- Much lower threshold + special case for 0
        local adjustmentRatio = actualTotalAbsorbs / trackedTotal

        if BoxxyAuras.DEBUG then
            print(string.format(
                "BoxxyAuras: Syncing tracking data with adjustment ratio: %.3f (actual: %d, tracked: %d)",
                adjustmentRatio, actualTotalAbsorbs, trackedTotal))
        end

        for _, entry in ipairs(activeTrackingData) do
            local oldAmount = entry.data.currentAmount
            entry.data.currentAmount = math.floor(entry.data.currentAmount * adjustmentRatio)
            entry.data.lastUpdate = GetTime()

            -- Mark as consumed if amount reaches 0
            if entry.data.currentAmount <= 0 then
                entry.data.fullyConsumed = true
            end

            if BoxxyAuras.DEBUG then
                print(string.format("BoxxyAuras: Adjusted tracking key %s: %d -> %d (consumed: %s)",
                    tostring(entry.key), oldAmount, entry.data.currentAmount, tostring(entry.data.fullyConsumed or false)))
            end
        end
    elseif trackedTotal == 0 and actualTotalAbsorbs == 0 then
        -- Both are 0, no sync needed but update visuals for any expired/held auras
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: Both actual and tracked absorbs are 0, updating visuals for expired auras")
        end

        for trackingKey, trackingData in pairs(self.healingAbsorbTracking or {}) do
            -- For any tracking data (including expired/held auras), ensure visuals show 0
            self:UpdateHealingAbsorbVisuals(trackingKey, nil)
        end
    elseif trackedTotal > 0 and actualTotalAbsorbs == 0 then
        -- All absorbs consumed, mark tracking as consumed
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras: All absorbs consumed, marking tracking as consumed")
        end

        for _, entry in ipairs(activeTrackingData) do
            entry.data.currentAmount = 0
            entry.data.fullyConsumed = true
            entry.data.lastUpdate = GetTime()
        end

        -- Also handle any other tracking data (expired/held auras)
        for trackingKey, trackingData in pairs(self.healingAbsorbTracking or {}) do
            self:UpdateHealingAbsorbVisuals(trackingKey, nil)
        end
    end
end

-- Check if an aura is a confirmed healing absorb
function BoxxyAuras:IsConfirmedHealingAbsorb(spellId)
    if not spellId then return false end

    local confirmed = self.healingAbsorbTracker.confirmedAbsorbs[spellId]
    if confirmed then
        -- Keep confirmed absorbs for 10 minutes
        if GetTime() - confirmed.confirmedAt < 600 then
            return true
        else
            -- Clean up old confirmations
            self.healingAbsorbTracker.confirmedAbsorbs[spellId] = nil
        end
    end

    return false
end -- Debug function to trace expired aura handling

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
