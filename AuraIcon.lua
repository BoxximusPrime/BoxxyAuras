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
    
    -- Determine frame type to read correct iconSize
    local settingsKey = nil
    if parentFrame == _G["BoxxyBuffDisplayFrame"] then
        settingsKey = "buffFrameSettings"
    elseif parentFrame == _G["BoxxyDebuffDisplayFrame"] then
        settingsKey = "debuffFrameSettings"
    end
    
    -- Read config/saved values INSIDE the function
    local iconTextureSize = 24 -- Default size
    if settingsKey and BoxxyAurasDB and BoxxyAurasDB[settingsKey] and BoxxyAurasDB[settingsKey].iconSize then
        iconTextureSize = BoxxyAurasDB[settingsKey].iconSize
    end
    
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local totalIconHeight = iconTextureSize + textHeight + (padding * 2)
    local totalIconWidth = iconTextureSize + (padding * 2)
    
    local instance = {}
    instance.frame = frame
    instance.parentDisplayFrame = parentFrame

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
    durationText:SetPoint("TOPLEFT", instance.textureWidget, "BOTTOMLEFT", -padding, -padding) -- Anchor top below texture (adjust left for full width)
    durationText:SetPoint("TOPRIGHT", instance.textureWidget, "BOTTOMRIGHT", padding, -padding) -- Anchor top below texture (adjust right for full width)
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

    -- Create Shake Overlay Texture (Initially hidden)
    local shakeOverlay = instance.frame:CreateTexture(nil, "OVERLAY", nil, 1) -- OVERLAY layer, subLevel 1 (above icon, below text)
    shakeOverlay:SetColorTexture(1, 0, 0, 0.75) -- Red, initially 0 alpha
    shakeOverlay:SetSize(iconTextureSize, iconTextureSize)
    shakeOverlay:SetPoint("TOPLEFT", instance.textureWidget, "TOPLEFT")
    shakeOverlay:SetAlpha(0) -- Start hidden
    instance.frame.shakeOverlay = shakeOverlay -- Store reference

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
    instance.slot = nil -- Initialize slot

    -- Set scripts on the frame, referencing methods via AuraIcon
    instance.frame:SetScript("OnEnter", function(frame_self) AuraIcon.OnEnter(instance) end)
    instance.frame:SetScript("OnLeave", function(frame_self) AuraIcon.OnLeave(instance) end)
    -- OnUpdate set later in Update method based on duration
    -- *** ADDED OnMouseUp for Right-Click Cancel ***
    instance.frame:SetScript("OnMouseUp", function(frame_self, button)
        -- Check if right-click and it's a helpful buff
        if button == "RightButton" and instance.auraType == "HELPFUL" then
            -- Check if IN COMBAT first
            if InCombatLockdown() then
                print("|cffFFCC00BoxxyAuras:|r Cannot cancel auras while in combat.")
                return -- Do nothing further if in combat
            end

            -- Proceed with cancellation logic only if NOT in combat
            if instance.auraInstanceID then
                local buffIndex = nil
                -- Find the current index of this specific aura instance using C_UnitAuras
                for i = 1, 40 do -- Check standard buff limit
                    local auraData = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                    if auraData then
                        if auraData.auraInstanceID and auraData.auraInstanceID == instance.auraInstanceID then
                            buffIndex = i
                            break
                        end
                    else
                        break
                    end
                end
                
                if buffIndex then
                    CancelUnitBuff("player", buffIndex)
                    print(string.format("Attempted to cancel buff index: %d (Name: %s, InstanceID: %s)", 
                        buffIndex, instance.name or 'Unknown', instance.auraInstanceID))
                else
                    print(string.format("Could not find current buff index for InstanceID: %s (Name: %s)", 
                        instance.auraInstanceID, instance.name or 'Unknown'))
                end
            else
                 print(string.format("Missing auraInstanceID on icon %s, cannot cancel.", frame_self:GetName() or '?'))
            end
        end
    end)
    
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

    -- Create Animation Group for Shake Effect
    local shakeGroup = instance.frame:CreateAnimationGroup("ShakeGroup")
    instance.shakeAnimGroup = shakeGroup -- Store it

    local shakeOffset = 4 -- Pixels to offset
    local shakeDur = 0.05 -- Duration of each shake segment

    -- Shake Right
    local shake1 = shakeGroup:CreateAnimation("Translation")
    shake1:SetOffset(shakeOffset, 0)
    shake1:SetDuration(shakeDur)
    shake1:SetOrder(1)

    -- Shake Left (past center)
    local shake2 = shakeGroup:CreateAnimation("Translation")
    shake2:SetOffset(-shakeOffset * 2, 0) 
    shake2:SetDuration(shakeDur * 2)
    shake2:SetOrder(2)

    -- Return to Center
    local shake3 = shakeGroup:CreateAnimation("Translation")
    shake3:SetOffset(shakeOffset, 0) 
    shake3:SetDuration(shakeDur)
    shake3:SetOrder(3)

    -- Add Alpha animations for the Red Overlay to the Shake Group
    local shakeOverlayFadeIn = shakeGroup:CreateAnimation("Alpha", "ShakeOverlayFadeIn")
    shakeOverlayFadeIn:SetChildKey("shakeOverlay") -- Target the new overlay
    shakeOverlayFadeIn:SetFromAlpha(0)
    shakeOverlayFadeIn:SetToAlpha(0.6) -- Fade in to 60% opacity
    shakeOverlayFadeIn:SetDuration(shakeDur) -- Fade in quickly with the first shake segment
    shakeOverlayFadeIn:SetOrder(1)

    local shakeOverlayFadeOut = shakeGroup:CreateAnimation("Alpha", "ShakeOverlayFadeOut")
    shakeOverlayFadeOut:SetChildKey("shakeOverlay")
    shakeOverlayFadeOut:SetFromAlpha(0.6)
    shakeOverlayFadeOut:SetToAlpha(0) -- Fade back out completely
    shakeOverlayFadeOut:SetDuration(shakeDur * 3) -- Fade out over the remaining shake duration (segments 2 & 3)
    shakeOverlayFadeOut:SetOrder(2) -- Start after the fade in

    -- Optional: Add a slight vertical shake? (Uncomment if desired)
    --[[ 
    local shakeV1 = shakeGroup:CreateAnimation("Translation")
    shakeV1:SetOffset(0, shakeOffset / 2)
    shakeV1:SetDuration(shakeDur)
    shakeV1:SetOrder(1) -- Run concurrently with horizontal shake

    local shakeV2 = shakeGroup:CreateAnimation("Translation")
    shakeV2:SetOffset(0, -shakeOffset)
    shakeV2:SetDuration(shakeDur * 2)
    shakeV2:SetOrder(2)

    local shakeV3 = shakeGroup:CreateAnimation("Translation")
    shakeV3:SetOffset(0, shakeOffset / 2)
    shakeV3:SetDuration(shakeDur)
    shakeV3:SetOrder(3)
    ]]

    return instance -- Return our instance table, not the frame
end

-- Helper to format duration (Kept internal)
local function FormatDuration(seconds)
    if seconds >= 3600 then return string.format("%.0fh", seconds / 3600) -- Format as whole number hours
    elseif seconds >= 60 then return string.format("%.0fm", seconds / 60) -- Format as whole number minutes
    else return string.format("%.0fs", seconds)
    end
end

-- Methods now operate on 'self' (the instance table) and access frame via self.frame
function AuraIcon.Update(self, auraData, auraIndex, auraType)
    if not auraData then
        if self.frame and self.frame:IsShown() then -- Only hide and clear OnUpdate if currently shown
            self.frame:Hide()
            self.frame:SetScript("OnUpdate", nil)
        end
        return
    end
    
    -- Check if the frame was hidden before this update
    local wasHidden = not self.frame:IsShown()
    
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
    self.slot = auraData.slot -- Store the slot index

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
            if self.frame.durationText then self.frame.durationText:Hide() end -- Add safety check
        end
    end -- End of check for not forceExpired

    -- If the frame was hidden and is now being updated (implicitly shown by parent logic),
    -- play the 'new aura' animation.
    if wasHidden and self.newAuraAnimGroup then
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

        -- Update Tint ONLY if expired state changed OR parent hover state changed
        -- We need to check hover state change too, because tint depends on it now
        if currentIsExpired ~= self.lastIsExpiredState or isHoveringParent ~= self.lastIsHoveringParentState then
             if self.textureWidget then
                 -- Apply red tint ONLY if expired AND hovering parent frame
                 if applyTint and isHoveringParent then 
                      self.textureWidget:SetVertexColor(1, 0.5, 0.5)
                 else -- Otherwise (Active OR Expired but not hovering parent), use normal tint
                      self.textureWidget:SetVertexColor(1, 1, 1) 
                  end
             end
             self.lastIsExpiredState = currentIsExpired -- Store new expired state
             self.lastIsHoveringParentState = isHoveringParent -- Store parent hover state
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
            -- Check if cached info and lines table exist
            if auraInfo and type(auraInfo.lines) == "table" and #auraInfo.lines > 0 then
                for idx, lineInfo in ipairs(auraInfo.lines) do 
                    -- Check if it's the first line and has both left and right parts
                    if idx == 1 and lineInfo.right then
                         GameTooltip:AddDoubleLine(lineInfo.left, lineInfo.right, 1, 0.82, 0, 1, 1, 1) -- Left (gold), Right (white)
                     else
                        -- Otherwise, just add the left line (description usually)
                        GameTooltip:AddLine(lineInfo.left, 1, 1, 1, true) -- White text
                     end
                end
            else
                GameTooltip:AddLine(self.name or "Unknown Expired Aura", 1, 1, 1, true)
            end
        end
        
        -- Always add expired tag and show immediately for this case
        GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5, true)
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

-- *** ADDED Shake Method ***
function AuraIcon:Shake()
    if not self.frame then return end -- Safety check
    -- Play the shake animation if it exists and isn't already playing
    if self.shakeAnimGroup and not self.shakeAnimGroup:IsPlaying() then
        self.shakeAnimGroup:Play()
    end
end

-- *** ADDED Resize Method ***
function AuraIcon:Resize(newIconSize)
    if not self.frame or not self.textureWidget then return end -- Safety check
    
    -- Read current config values needed for calculation
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6 -- Internal padding
    
    -- Calculate new total dimensions
    local newTotalIconHeight = newIconSize + textHeight + (padding * 2)
    local newTotalIconWidth = newIconSize + (padding * 2)
    
    -- Resize the main frame
    self.frame:SetSize(newTotalIconWidth, newTotalIconHeight)
    
    -- Resize the icon texture widget
    self.textureWidget:SetSize(newIconSize, newIconSize)
    
    -- Optional: Re-anchor elements if needed. Let's re-anchor text elements 
    -- relative to texture widget or frame to be safe.
    if self.frame.countText then
        self.frame.countText:ClearAllPoints()
        self.frame.countText:SetPoint("BOTTOMRIGHT", self.textureWidget, "BOTTOMRIGHT", 2, -2)
    end
    if self.frame.countTextBg then
        -- Assuming it uses the same padding logic
        local bgPadding = 2
        self.frame.countTextBg:ClearAllPoints()
        self.frame.countTextBg:SetPoint("TOPLEFT", self.frame.countText, "TOPLEFT", -bgPadding, bgPadding)
        self.frame.countTextBg:SetPoint("BOTTOMRIGHT", self.frame.countText, "BOTTOMRIGHT", bgPadding - 4, -bgPadding)
    end
    if self.frame.durationText then
        self.frame.durationText:ClearAllPoints()
        self.frame.durationText:SetPoint("TOPLEFT", self.textureWidget, "BOTTOMLEFT", -padding, -padding)
        self.frame.durationText:SetPoint("TOPRIGHT", self.textureWidget, "BOTTOMRIGHT", padding, -padding)
        self.frame.durationText:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, padding)
    end
    if self.frame.wipeOverlay then 
        self.frame.wipeOverlay:ClearAllPoints()
        self.frame.wipeOverlay:SetSize(newIconSize, newIconSize) -- Also resize wipe overlay
        self.frame.wipeOverlay:SetPoint("TOPLEFT", self.textureWidget, "TOPLEFT")
    end
end

-- Expose the AuraIcon class to the addon
BoxxyAuras.AuraIcon = AuraIcon