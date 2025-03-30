local ADDON_NAME, Addon = ... -- Get addon name and private table

local AuraIcon = {}
AuraIcon.__index = AuraIcon

-- Configuration Table
Addon.Config = {
    BackgroundColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }, -- Default: Dark grey
    BorderColor = { r = 1, g = 1, b = 1, a = 0.3 },      -- Default: Slightly lighter grey
}

local iconTextureSize = 32
local textHeight = 12 -- Estimated height needed for duration text
local padding = 6
local totalIconHeight = iconTextureSize + textHeight + (padding * 2)
local totalIconWidth = iconTextureSize + (padding * 2)

function AuraIcon.New(parentFrame, index, baseName)
    -- Create the actual frame object
    local frame = CreateFrame("Frame", baseName .. index, parentFrame, "BackdropTemplate")
    
    local instance = {}
    instance.frame = frame

    instance.frame:SetSize(totalIconWidth, totalIconHeight)

    local texture = instance.frame:CreateTexture(nil, "ARTWORK")
    texture:SetSize(iconTextureSize, iconTextureSize)
    texture:SetPoint("TOPLEFT", instance.frame, "TOPLEFT", padding, -padding)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    instance.frame.auraTexture = texture -- Give it a key on the frame
    instance.textureWidget = texture -- Store directly on instance

    local countText = instance.frame:CreateFontString(nil, "OVERLAY", nil)
    countText:SetFontObject("GameFontNormalSmall")
    countText:SetPoint("BOTTOMRIGHT", instance.textureWidget, "BOTTOMRIGHT", 1, -1) -- Anchor to textureWidget
    countText:SetJustifyH("RIGHT")
    countText:SetTextColor(1, 1, 1, 1)
    instance.frame.countText = countText

    local durationText = instance.frame:CreateFontString(nil, "OVERLAY", nil)
    durationText:SetFontObject("GameFontNormal")
    durationText:SetPoint("TOPLEFT", instance.textureWidget, "BOTTOMLEFT", 0, -padding) -- Anchor to textureWidget
    durationText:SetPoint("TOPRIGHT", instance.textureWidget, "BOTTOMRIGHT", 0, -padding) -- Anchor to textureWidget
    durationText:SetPoint("BOTTOM", instance.frame, "BOTTOM", 0, padding)
    durationText:SetJustifyH("CENTER")
    durationText:SetTextColor(1, 1, 1, 1)
    instance.frame.durationText = durationText

    -- Apply the backdrop using utility functions
    Addon.UIUtils.DrawSlicedBG(instance.frame, "ItemEntryBG", "backdrop", 0) -- Use ItemEntryBG for backdrop
    Addon.UIUtils.DrawSlicedBG(instance.frame, "ItemEntryBorder", "border", 0)   -- Use ItemEntryBorder for border

    -- Access config directly here, with fallbacks
    local cfgBG = (Addon.Config and Addon.Config.BackgroundColor) or { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }
    local cfgBorder = (Addon.Config and Addon.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }

    -- Color the backdrop and border using utility functions
    Addon.UIUtils.ColorBGSlicedFrame(instance.frame, "backdrop", cfgBG.r, cfgBG.g, cfgBG.b, cfgBG.a)
    Addon.UIUtils.ColorBGSlicedFrame(instance.frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)

    -- Store data on the instance table now
    instance.duration = 0
    instance.expirationTime = 0
    instance.auraIndex = 0
    instance.auraType = nil
    instance.spellID = nil
    instance.name = nil
    instance.auraKey = nil -- ADDED: Key to use in Addon.AllAuras
    instance.isExpired = false -- Initialize flag
    instance.auraInstanceID = nil -- Initialize
    instance.lastFormattedDurationText = nil -- Initialize state tracking
    instance.lastIsExpiredState = nil -- Initialize state tracking

    -- Set scripts on the frame, referencing methods via AuraIcon
    instance.frame:SetScript("OnLeave", function(frame_self) AuraIcon.OnLeave(instance) end)
    -- Need OnEnter set later in Update method

    instance.frame:Hide()

    -- Set metatable on the instance table
    setmetatable(instance, AuraIcon)

    return instance -- Return our instance table, not the frame
end

-- Helper to format duration (Kept internal)
local function FormatDuration(seconds)
    if seconds >= 3600 then return string.format("%.1fh", seconds / 3600)
    elseif seconds >= 60 then return string.format("%.1fm", seconds / 60)
    else return string.format("%.0fs", seconds)
    end
end

-- Methods now operate on 'self' (the instance table) and access frame via self.frame
function AuraIcon.Update(self, auraData, auraIndex, auraType)
    if not auraData then
        self.frame:Hide()
        return
    end
    -- Reset state for update
    self.isExpired = false 
    
    self.textureWidget:SetTexture(auraData.icon)

    if auraData.count and auraData.count > 1 then
        self.frame.countText:SetText(auraData.count)
        self.frame.countText:Show()
    else
        self.frame.countText:Hide()
    end

    -- Store data on the instance
    self.duration = auraData.duration
    self.expirationTime = auraData.expirationTime
    self.auraIndex = auraIndex
    self.auraType = auraType
    self.spellID = auraData.spellID
    self.name = auraData.name
    self.auraInstanceID = auraData.auraInstanceID 

    -- Determine key for global cache - Use spellId ONLY
    self.auraKey = auraData.spellId -- No fallback to name

    if auraType == "HARMFUL" then
        local r, g, b = DebuffTypeColor[auraData.dispelType or "none"]
        if r then
            -- Color the border using utility function
            Addon.UIUtils.ColorBGSlicedFrame(self.frame, "border", r, g, b, 0.9)
        else
            Addon.UIUtils.ColorBGSlicedFrame(self.frame, "border", 0.6, 0.1, 0.1, 0.8)
        end
    else -- Buffs
        -- Use configured border color for buffs, accessing config directly
        local cfgBorder = (Addon.Config and Addon.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
        -- Color the border using utility function
        Addon.UIUtils.ColorBGSlicedFrame(self.frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)
    end

    -- Set OnEnter script referencing the instance
    self.frame:SetScript("OnEnter", function(frame_self) AuraIcon.OnEnter(self) end)

    self.frame:Show()
end

function AuraIcon.UpdateDurationDisplay(self, currentTime)
    -- Check self.frame first
    if not self.frame then return end

    -- Debug Check (Should pass now if self.frame exists)
    if type(self.frame) ~= "table" or not self.frame.GetObjectType or self.frame:GetObjectType() ~= "Frame" then
        print(string.format("|cffff0000Warning: UpdateDurationDisplay found unexpected self.frame! Type: %s, GetObjectType: %s|r", 
            type(self.frame), 
            (type(self.frame) == "table" and self.frame.GetObjectType and self.frame:GetObjectType()) or "N/A"
        ))
        return
    end

    if not self.frame:IsShown() then return end

    if self.duration and self.duration > 0 then
        local remaining = self.expirationTime - currentTime
        local isHovering = Addon.IsMouseWithinFrame(mainFrame) -- Re-get hover state here
        
        local currentIsExpired = (remaining <= 0) -- Calculate current expired state
        local currentFormattedText = nil
        local showText = false
        local applyTint = false

        if not currentIsExpired then -- remaining > 0
            currentFormattedText = FormatDuration(remaining)
            showText = true
            applyTint = false -- Active tint (white)
        else -- Expired (remaining <= 0)
            applyTint = true -- Expired tint (red)
            if isHovering then -- Keep showing 0s text if mouse is over
                currentFormattedText = "0s" 
                showText = true
            else -- Hide text if mouse not over
                showText = false
            end
        end

        -- Update Text ONLY if changed or visibility changed
        if currentFormattedText ~= self.lastFormattedDurationText or showText ~= self.frame.durationText:IsShown() then
            if showText then
                -- print(string.format("DEBUG Duration: Update Text - %s (%s)", self.name, currentFormattedText)) -- Optional Debug
                self.frame.durationText:SetText(currentFormattedText)
                self.frame.durationText:Show()
            else
                -- print(string.format("DEBUG Duration: Hide Text - %s", self.name)) -- Optional Debug
                self.frame.durationText:Hide()
            end
            self.lastFormattedDurationText = currentFormattedText -- Store new text state
        end

        -- Update Tint ONLY if expired state changed
        if currentIsExpired ~= self.lastIsExpiredState then
             if self.textureWidget then
                 if applyTint then -- Expired
                     -- print(string.format("DEBUG Duration: Update Tint RED - %s", self.name)) -- Optional Debug
                     self.textureWidget:SetVertexColor(1, 0.5, 0.5)
                 else -- Active
                     -- print(string.format("DEBUG Duration: Update Tint WHITE - %s", self.name)) -- Optional Debug
                     self.textureWidget:SetVertexColor(1, 1, 1) 
                 end
             end
             self.lastIsExpiredState = currentIsExpired -- Store new expired state
        end
        
        -- self.isExpired = currentIsExpired -- Update main flag if needed elsewhere (Redundant? Already set in main Update?)

    else -- Permanent aura or no duration
        -- Ensure text is hidden and state is cleared if it was previously showing duration
        if self.frame.durationText:IsShown() or self.lastFormattedDurationText then 
            self.frame.durationText:Hide()
            self.lastFormattedDurationText = nil
        end
        -- Ensure tint is reset if it was previously expired
        if self.lastIsExpiredState then
             if self.textureWidget then self.textureWidget:SetVertexColor(1, 1, 1) end
             self.lastIsExpiredState = false -- Reset state
        end
    end
end

function AuraIcon.OnEnter(self)
    if not self.frame then return end

    local currentTime = GetTime()
    local remaining = (self.expirationTime or 0) - currentTime 
    local isPermanent = (self.duration or 0) == 0
    -- local hasSpellID = (self.spellID ~= nil)

    -- REMOVED: Debug print

    GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")

    if isPermanent or remaining > 0 then -- If permanent or still active
        -- Just set the tooltip normally, no caching attempted here
        if self.auraIndex and self.auraType then
            GameTooltip:SetUnitAura("player", self.auraIndex, self.auraType)
        elseif self.spellID then 
             GameTooltip:SetSpellByID(self.spellID) 
        else -- Fallback if index and spellID are missing
            GameTooltip:SetText(self.name or "Unknown Aura")
        end

        -- Show tooltip after a tiny delay
        C_Timer.After(0.01, function() 
            if GameTooltip:IsOwned(self.frame) then -- Check if tooltip is still for this frame
                GameTooltip:Show()
            end
        end)

    elseif not isPermanent and remaining <= 0 then -- If expired but held
        print(string.format("DEBUG OnEnter Expired: Checking cache with self.auraKey = %s", tostring(self.auraKey)))
        local auraInfo = self.auraKey and Addon.AllAuras[self.auraKey]

        local function ShowExpiredTooltip(finalCheckInfo)
            -- This function runs either immediately or after a delay
            -- finalCheckInfo is the result of the cache lookup inside the timer, if applicable
            if not GameTooltip:IsOwned(self.frame) then return end -- Tooltip changed owner
            
            local displayInfo = finalCheckInfo or auraInfo -- Use info from final check if available ({ name=..., lines=... } table or nil)

            -- Check if the INNER lines table exists and has lines
            if displayInfo and type(displayInfo.lines) == "table" and #displayInfo.lines > 0 then
                -- Use cached lines from global cache (accessing displayInfo.lines)
                print(string.format("DEBUG OnEnter Expired: Using global cache for key: %s (%d lines from displayInfo.lines)", tostring(self.auraKey), #displayInfo.lines))
                GameTooltip:ClearLines() -- Clear potentially stale lines
                -- Iterate over displayInfo.lines
                for _, line in ipairs(displayInfo.lines) do 
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            else
                -- Fallback if no lines found after check/delay
                print(string.format("DEBUG OnEnter Expired: Fallback after check/delay for key: %s (Info found: %s, Valid Lines: %s)", 
                    tostring(self.auraKey), 
                    tostring(displayInfo ~= nil), 
                    tostring(displayInfo and type(displayInfo.lines) == "table" and #displayInfo.lines > 0)))
                GameTooltip:ClearLines()
                -- Fallback uses self.name, or the stored name if available
                local fallbackName = (displayInfo and displayInfo.name) or self.name or "Unknown Expired Aura"
                GameTooltip:AddLine(fallbackName, 1, 1, 1, true)
            end
            -- Add (Expired) tag after main content
            GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5)
            GameTooltip:Show()
        end

        -- Check if cache is ready immediately (checking displayInfo.lines)
        if auraInfo and type(auraInfo.lines) == "table" and #auraInfo.lines > 0 then
            -- Cache ready immediately
            print("DEBUG OnEnter Expired: Cache ready immediately.")
            ShowExpiredTooltip() -- Call directly, passing current (good) auraInfo implicitly
        else
            -- Cache not ready (nil or not a table/empty) - wait briefly
            print("DEBUG OnEnter Expired: Cache not ready, scheduling check.")
            -- Set a minimal tooltip initially to prevent flicker? 
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.name or "...", 1, 1, 1, true) -- Placeholder
            GameTooltip:AddLine("(Waiting for cache...)", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5)
            GameTooltip:Show()
            
            C_Timer.After(0.2, function() 
                 if not self or not self.frame or not self.frame:IsShown() then return end -- Check instance validity
                 local finalAuraInfo = self.auraKey and Addon.AllAuras[self.auraKey]
                 ShowExpiredTooltip(finalAuraInfo) -- Call deferred, passing result of final check
            end)
        end

        -- REMOVED Add (Expired) tag here, moved into ShowExpiredTooltip
        -- REMOVED Caster Info section as C_UnitInfo is nil
    else -- Should not happen
        GameTooltip:SetText(self.name or "Unknown Aura State")
    end
end

function AuraIcon.OnLeave(self)
     if not self.frame then return end
    GameTooltip:Hide()
end

-- Expose the AuraIcon class to the addon
Addon.AuraIcon = AuraIcon 