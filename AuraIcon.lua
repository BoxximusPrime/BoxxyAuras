local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras = BoxxyAuras or {}
BoxxyAuras.AllAuras = {} -- Global cache for aura info

-- Add this near the top of AuraIcon.lua if it's missing
local DebuffTypeColor = {
    ["MAGIC"]   = { 0.2, 0.6, 1.0 }, -- Blue
    ["CURSE"]   = { 0.6, 0.0, 1.0 }, -- Purple
    ["DISEASE"] = { 0.6, 0.4, 0 }, -- Brown/Yellow
    ["POISON"]  = { 0.0, 0.6, 0 }, -- Green
    ["NONE"]    = { 0.8, 0.8, 0.8 }, -- Grey for non-dispellable (placeholder, we handle NONE explicitly now)
    -- Add other potential types if needed, though these are the main player-dispellable ones
}

local AuraIcon = {}
AuraIcon.__index = AuraIcon

function AuraIcon.New(parentFrame, index, baseName)
    -- Create the actual frame object
    local frame = CreateFrame("Frame", baseName .. index, parentFrame, "BackdropTemplate")
    
    -- Read config values INSIDE the function
    local iconTextureSize = (BoxxyAuras.Config and BoxxyAuras.Config.IconSize) or 32
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 12
    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local totalIconHeight = iconTextureSize + textHeight + (padding * 2)
    local totalIconWidth = iconTextureSize + (padding * 2)
    
    local instance = {}
    instance.frame = frame
    instance.parentDisplayFrame = parentFrame -- Store reference to parent (buff/debuff display frame)

    instance.frame:SetSize(totalIconWidth, totalIconHeight)

    local texture = instance.frame:CreateTexture(nil, "ARTWORK")
    texture:SetSize(iconTextureSize, iconTextureSize)
    texture:SetPoint("TOPLEFT", instance.frame, "TOPLEFT", padding, -padding)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    instance.frame.auraTexture = texture -- Give it a key on the frame
    instance.textureWidget = texture -- Store directly on instance

    -- Create FontString inheriting the virtual font object
    local countText = instance.frame:CreateFontString(nil, "OVERLAY", "BoxxyAuras_StackTxt")
    countText:SetPoint("BOTTOMRIGHT", instance.textureWidget, "BOTTOMRIGHT", 2, -2) -- Anchor to textureWidget
    countText:SetJustifyH("RIGHT")
    instance.frame.countText = countText

    -- Create background for count text
    -- Use ARTWORK layer with subLevel 1 to draw above main icon (subLevel 0) but below text (OVERLAY)
    local countTextBg = instance.frame:CreateTexture(nil, "ARTWORK", nil, 1) 
    countTextBg:SetColorTexture(0, 0, 0, 0.85) -- Black, slightly transparent
    -- Anchor background relative to the text with padding
    local bgPadding = 2
    countTextBg:SetPoint("TOPLEFT", countText, "TOPLEFT", -bgPadding, bgPadding)
    countTextBg:SetPoint("BOTTOMRIGHT", countText, "BOTTOMRIGHT", bgPadding-4, -bgPadding)
    instance.frame.countTextBg = countTextBg -- Store reference

    -- Create FontString inheriting the virtual font object
    local durationText = instance.frame:CreateFontString(nil, "OVERLAY", "BoxxyAuras_DurationTxt")
    durationText:SetPoint("TOPLEFT", instance.textureWidget, "BOTTOMLEFT", 0, -padding) -- Anchor to textureWidget
    durationText:SetPoint("TOPRIGHT", instance.textureWidget, "BOTTOMRIGHT", 0, -padding) -- Anchor to textureWidget
    durationText:SetPoint("BOTTOM", instance.frame, "BOTTOM", 0, padding)
    durationText:SetJustifyH("CENTER")
    instance.frame.durationText = durationText

    -- Create Wipe Overlay Texture
    local wipeOverlay = instance.frame:CreateTexture(nil, "ARTWORK", nil, 2) -- ARTWORK layer, subLevel 2 (above icon & stack bg)
    wipeOverlay:SetColorTexture(1, 1, 1, 1.0) -- Solid White (alpha controlled by animation)
    wipeOverlay:SetSize(iconTextureSize, iconTextureSize)
    wipeOverlay:SetPoint("TOPLEFT", instance.textureWidget, "TOPLEFT")
    wipeOverlay:SetAlpha(0) -- Start hidden
    instance.frame.wipeOverlay = wipeOverlay -- Store reference

    -- Apply the backdrop using utility functions
    BoxxyAuras.UIUtils.DrawSlicedBG(instance.frame, "ItemEntryBG", "backdrop", 0) -- Use ItemEntryBG for backdrop
    BoxxyAuras.UIUtils.DrawSlicedBG(instance.frame, "ItemEntryBorder", "border", 0)   -- Use ItemEntryBorder for border

    -- Access config directly here, with fallbacks
    local cfgBG = (BoxxyAuras.Config and BoxxyAuras.Config.BackgroundColor) or { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }
    local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }

    -- Color the backdrop and border using utility functions
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(instance.frame, "backdrop", cfgBG.r, cfgBG.g, cfgBG.b, cfgBG.a)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(instance.frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)

    -- Store data on the instance table now
    instance.duration = 0
    instance.expirationTime = 0
    instance.auraIndex = 0
    instance.auraType = nil
    instance.spellID = nil
    instance.name = nil
    instance.auraKey = nil -- ADDED: Key to use in BoxxyAuras.AllAuras
    instance.isExpired = false -- Initialize flag
    instance.auraInstanceID = nil -- Initialize
    instance.lastFormattedDurationText = nil -- Initialize state tracking
    instance.lastIsExpiredState = nil -- Initialize state tracking
    instance.isMouseOver = false -- Initialize mouse over flag
    instance.tooltipUpdateTimer = 0 -- Initialize tooltip update timer

    -- Set scripts on the frame, referencing methods via AuraIcon
    instance.frame:SetScript("OnEnter", function(frame_self) AuraIcon.OnEnter(instance) end)
    instance.frame:SetScript("OnLeave", function(frame_self) AuraIcon.OnLeave(instance) end)
    -- OnUpdate set later in Update method based on duration
    
    instance.frame:Hide()

    -- Set metatable on the instance table
    setmetatable(instance, AuraIcon)

    -- Create Animation Group for New Aura Effect
    local animGroup = instance.frame:CreateAnimationGroup()
    instance.newAuraAnimGroup = animGroup -- Store it

    -- Scale Animation (Pop effect)
    local scaleAnim = animGroup:CreateAnimation("Scale")
    scaleAnim:SetScale(1.2, 1.2) -- Scale up slightly
    scaleAnim:SetDuration(0.15)
    scaleAnim:SetOrder(1)
    scaleAnim:SetSmoothing("OUT")

    local scaleAnim2 = animGroup:CreateAnimation("Scale")
    scaleAnim2:SetScale(1.0, 1.0) -- Scale back to normal
    scaleAnim2:SetDuration(0.15)
    scaleAnim2:SetOrder(2) 
    scaleAnim2:SetSmoothing("IN")

    -- Alpha Animation (Fade-in)
    local alphaAnim = animGroup:CreateAnimation("Alpha")
    alphaAnim:SetFromAlpha(0)
    alphaAnim:SetToAlpha(1)
    alphaAnim:SetDuration(0.2) -- Slightly longer fade-in
    alphaAnim:SetOrder(1) -- Run concurrently with first scale part

    -- Wipe Overlay Animations
    local wipeAlpha = animGroup:CreateAnimation("Alpha", "WipeAlpha")
    wipeAlpha:SetChildKey("wipeOverlay") -- Target the overlay texture
    wipeAlpha:SetFromAlpha(0)
    wipeAlpha:SetToAlpha(0.75) -- Fade in quickly
    wipeAlpha:SetDuration(0.1)
    wipeAlpha:SetOrder(1)
    wipeAlpha:SetSmoothing("IN")
    
    local wipeAlpha2 = animGroup:CreateAnimation("Alpha", "WipeAlpha2")
    wipeAlpha2:SetChildKey("wipeOverlay") 
    wipeAlpha2:SetFromAlpha(0.75)
    wipeAlpha2:SetToAlpha(0) -- Fade out over the slide duration
    wipeAlpha2:SetDuration(0.25) -- Duration matches slide
    wipeAlpha2:SetOrder(2)
    wipeAlpha2:SetSmoothing("OUT")

    local wipeSlide = animGroup:CreateAnimation("Translation", "WipeSlide")
    wipeSlide:SetChildKey("wipeOverlay")
    wipeSlide:SetOffset(0, -iconTextureSize) -- Move down by texture height
    wipeSlide:SetDuration(0.25) -- Slightly slower slide
    wipeSlide:SetOrder(2) -- Start after initial fade-in/pop
    wipeSlide:SetSmoothing("OUT")

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
        -- Clear OnUpdate if hiding
        self.frame:SetScript("OnUpdate", nil)
        return
    end
    -- Reset state for update (initial assumption)
    self.isExpired = false 

    -- Check for forced expired state right at the beginning
    if auraData.forceExpired then
        self.isExpired = true
        self.lastIsExpiredState = true -- Sync state tracking
        if self.textureWidget then self.textureWidget:SetVertexColor(1, 0.5, 0.5) end -- Red tint
        self.frame.durationText:SetText("0s") -- Show 0s duration
        self.frame.durationText:Show()
        self.frame:SetScript("OnUpdate", nil) -- Ensure no countdown update
    end
    
    self.textureWidget:SetTexture(auraData.icon)

    -- Use auraData.applications for stack count
    if auraData.applications and auraData.applications > 1 then 
        self.frame.countText:SetText(auraData.applications)
        self.frame.countText:Show()
        self.frame.countTextBg:Show() -- Show background too
    else
        self.frame.countText:Hide()
        self.frame.countTextBg:Hide() -- Hide background too
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
        -- Get dispel type using the correct key 'dispelName', default to "NONE", and convert to uppercase
        local dispelType = string.upper(auraData.dispelName or "NONE") 
        
        if dispelType == "NONE" then
            -- Explicitly handle "NONE" type with Red border / White text
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", 1.0, 0.1, 0.1, 0.9) -- Red border
            self.frame.durationText:SetTextColor(1, 1, 1, 1.0) -- White text
        else
            -- Handle known dispel types (MAGIC, CURSE, etc.) - Use uppercase key
            local colorTable = DebuffTypeColor[dispelType] 
            if colorTable then
                -- Use the specific color for this dispel type
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", colorTable[1], colorTable[2], colorTable[3], 0.9)
                self.frame.durationText:SetTextColor(colorTable[1], colorTable[2], colorTable[3], 1.0)
            else
                -- Fallback for any *other* unknown dispelType (should be rare)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", 1.0, 0.1, 0.1, 0.9) -- Red border
                self.frame.durationText:SetTextColor(1, 1, 1, 1.0) -- White text
            end
        end
    else -- Buffs
        -- Use configured border color for buffs, accessing config directly
        local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)
        -- Reset text color for buffs
        self.frame.durationText:SetTextColor(1, 1, 1, 1) -- White text
    end

    -- Set or clear OnUpdate based on duration, ONLY if not forceExpired
    if not auraData.forceExpired then
        if self.duration and self.duration > 0 then
            self.frame:SetScript("OnUpdate", function(frame_self, elapsed) 
                AuraIcon.UpdateDurationDisplay(self, GetTime())

                if self.isMouseOver then
                    self.tooltipUpdateTimer = self.tooltipUpdateTimer - elapsed
                    if self.tooltipUpdateTimer <= 0 then
                        if GameTooltip:IsOwned(self.frame) then
                            AuraIcon.RefreshTooltipContent(self) 
                        end
                        self.tooltipUpdateTimer = 0.5
                    end
                end
            end)
        else
            self.frame:SetScript("OnUpdate", nil)
            self.frame.durationText:Hide()
        end
    end -- End of check for not forceExpired

    -- Check if the frame is about to be shown for the first time
    local playAnim = not self.frame:IsShown()

    self.frame:Show()

    -- Play animation if it was newly shown
    if playAnim and self.newAuraAnimGroup then
        self.newAuraAnimGroup:Play()
    end
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
        -- Check the flag on the icon's parent display frame
        local isHoveringParent = self.parentDisplayFrame and self.parentDisplayFrame.isMouseOverActual
        
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
            if isHoveringParent then -- Keep showing 0s text if mouse is over
                currentFormattedText = "0s" 
                showText = true
            else -- Hide text if mouse not over AND disable OnUpdate
                showText = false
                -- Stop running OnUpdate once expired and not hovered
                self.frame:SetScript("OnUpdate", nil)
            end
        end

        -- Update Text ONLY if changed or visibility changed
        if currentFormattedText ~= self.lastFormattedDurationText or showText ~= self.frame.durationText:IsShown() then
            if showText then
                self.frame.durationText:SetText(currentFormattedText)
                self.frame.durationText:Show()
            else
                self.frame.durationText:Hide()
            end
            self.lastFormattedDurationText = currentFormattedText -- Store new text state
        end

        -- Update Tint ONLY if expired state changed
        if currentIsExpired ~= self.lastIsExpiredState then
             if self.textureWidget then
                 if applyTint then -- Expired
                     self.textureWidget:SetVertexColor(1, 0.5, 0.5)
                 else -- Active
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
        -- Make sure OnUpdate is nil for permanent auras (already done in Update, but belt-and-suspenders)
        if self.frame:GetScript("OnUpdate") then 
            self.frame:SetScript("OnUpdate", nil) 
        end
    end
end

function AuraIcon.OnEnter(self)
    self.isMouseOver = true -- Set flag when mouse enters
    GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines() -- Clear any previous tooltip content immediately
    
    AuraIcon.RefreshTooltipContent(self) -- Use the new refresh function
    
    GameTooltip:Show() -- Show the newly populated tooltip
end

-- New function to handle the logic of setting tooltip content
function AuraIcon.RefreshTooltipContent(self)
    if not self.frame then return end
    
    local currentTime = GetTime()
    local remaining = (self.expirationTime or 0) - currentTime 
    local isPermanent = (self.duration or 0) == 0

    GameTooltip:ClearLines() -- Clear lines before repopulating

    if isPermanent or remaining > 0 then -- If permanent or still active
        -- Prioritize SetSpellByID if we have a spellID
        if self.spellID then 
             GameTooltip:SetSpellByID(self.spellID) 
        -- Fallback to SetUnitAura IF we can find the current index for the instance ID
        elseif self.auraInstanceID and self.auraType then
            local currentIndex = nil
            -- Try to find the current index matching the instance ID
            for i = 1, 40 do 
                local currentAuraData = C_UnitAuras.GetAuraDataByIndex("player", i, self.auraType)
                if currentAuraData and currentAuraData.auraInstanceID == self.auraInstanceID then
                    currentIndex = i
                    break
                end
            end
            
            if currentIndex then
                -- Found current index, use it
                GameTooltip:SetUnitAura("player", currentIndex, self.auraType)
            else
                -- Couldn't find current index (aura likely expired/shifted), show name only
                GameTooltip:AddLine(self.name or "Unknown Aura (Index Changed)")
            end
        -- Final fallback to just the name if no SpellID or InstanceID
        else 
            GameTooltip:AddLine(self.name or "Unknown Aura")
        end
        -- No need to call GameTooltip:Show() here, it's already shown

    elseif not isPermanent and remaining <= 0 then -- If expired but held
        local tooltipSet = false
        -- Try using game functions first for potential auto-update
        if self.spellID then 
             GameTooltip:SetSpellByID(self.spellID) 
             tooltipSet = true
        elseif self.auraInstanceID and self.auraType then
            local currentIndex = nil
            for i = 1, 40 do 
                local currentAuraData = C_UnitAuras.GetAuraDataByIndex("player", i, self.auraType)
                if currentAuraData and currentAuraData.auraInstanceID == self.auraInstanceID then
                    currentIndex = i
                    break
                end
            end
            if currentIndex then
                GameTooltip:SetUnitAura("player", currentIndex, self.auraType)
                tooltipSet = true
            end
        end

        -- If game functions failed, fallback to manual lines from cache or name
        if not tooltipSet then
            local auraInfo = self.auraKey and BoxxyAuras.AllAuras[self.auraKey]
            if auraInfo and type(auraInfo.lines) == "table" and #auraInfo.lines > 0 then
                for idx, line in ipairs(auraInfo.lines) do 
                    if idx == 1 then
                        GameTooltip:AddLine(line, 1, 0.82, 0, true) -- Name in gold
                    else
                        GameTooltip:AddLine(line, 1, 1, 1, true) -- Description in white
                    end
                end
            else
                GameTooltip:AddLine(self.name or "Unknown Expired Aura", 1, 1, 1, true)
            end
        end
        
        -- Always add expired tag and show immediately for this case
        GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5)
        -- No need to call GameTooltip:Show() here

    else -- Should not happen
        GameTooltip:AddLine(self.name or "Unknown Aura State")
        -- No need to call GameTooltip:Show() here
    end
end

function AuraIcon.OnLeave(self)
     if not self.frame then return end
     self.isMouseOver = false -- Clear flag when mouse leaves
    GameTooltip:Hide()
end

-- Expose the AuraIcon class to the addon
BoxxyAuras.AuraIcon = AuraIcon 