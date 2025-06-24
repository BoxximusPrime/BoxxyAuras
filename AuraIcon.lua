-- Get the GLOBAL addon table correctly
local addonNameString, privateTable = ...
_G.BoxxyAuras = _G.BoxxyAuras or {}
local BoxxyAuras = _G.BoxxyAuras -- Use the global table

-- Remove redundant AllAuras creation if it's already done in BoxxyAuras.lua
-- BoxxyAuras.AllAuras = {} 

-- Add this near the top of AuraIcon.lua if it's missing
local DebuffTypeColor = {
    ["MAGIC"] = {0.2, 0.6, 1.0}, -- Blue
    ["CURSE"] = {0.6, 0.0, 1.0}, -- Purple
    ["DISEASE"] = {0.6, 0.4, 0}, -- Brown/Yellow
    ["POISON"] = {0.0, 0.6, 0}, -- Green
    ["NONE"] = {0.8, 0.0, 0.0} -- Grey for non-dispellable (placeholder, we handle NONE explicitly now)
    -- Add other potential types if needed, though these are the main player-dispellable ones
}

local AuraIcon = {}
AuraIcon.__index = AuraIcon

function AuraIcon.New(parentFrame, index, baseName)
    -- Find frame type and get config values
    local frameType
    for fType, f in pairs(BoxxyAuras.Frames or {}) do
        if f == parentFrame then
            frameType = fType;
            break
        end
    end

    local settingsKey = frameType and BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = settingsKey and BoxxyAuras:GetCurrentProfileSettings()

    -- Get icon dimensions and text size
    local iconSize = (currentSettings and currentSettings[settingsKey] and currentSettings[settingsKey].iconSize) or
                         BoxxyAuras.Config.IconSize
    local textSize = (currentSettings and currentSettings[settingsKey] and currentSettings[settingsKey].textSize) or 8
    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    -- Calculate text area height with some padding (text size + small buffer)
    local textAreaHeight = textSize + 4
    local totalHeight = iconSize + textAreaHeight + (padding * 2)
    local totalWidth = iconSize + (padding * 2)

    -- Create instance and frame
    local instance = setmetatable({}, AuraIcon)
    instance.currentSize = iconSize -- Store initial size
    instance.currentTextSize = textSize -- Track current text size

    local frame = CreateFrame("Frame", baseName .. index, parentFrame, "BackdropTemplate")
    frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
    frame:SetSize(totalWidth, totalHeight)

    -- Create core UI elements
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetSize(iconSize, iconSize)
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -padding)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local countText = frame:CreateFontString(nil, "OVERLAY", "BoxxyAuras_StackTxt")
    countText:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", 2, -2)
    countText:SetJustifyH("RIGHT")

    local countTextBg = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    countTextBg:SetColorTexture(0, 0, 0, 0.85)
    countTextBg:SetPoint("TOPLEFT", countText, "TOPLEFT", -2, 2)
    countTextBg:SetPoint("BOTTOMRIGHT", countText, "BOTTOMRIGHT", -2, -2)

    -- Create text background first (so it's behind the text)
    local durationTextBg = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    durationTextBg:SetColorTexture(0, 0, 0, 0.85)
    durationTextBg:SetPoint("TOPLEFT", texture, "BOTTOMLEFT", 0, -padding)
    durationTextBg:SetPoint("TOPRIGHT", texture, "BOTTOMRIGHT", 0, -padding)
    durationTextBg:SetPoint("BOTTOM", frame, "BOTTOM", 0, padding)

    local durationText = frame:CreateFontString(nil, "OVERLAY", "BoxxyAuras_DurationTxt")
    durationText:SetPoint("TOPLEFT", texture, "BOTTOMLEFT", 0, -padding)
    durationText:SetPoint("TOPRIGHT", texture, "BOTTOMRIGHT", 0, -padding)
    durationText:SetPoint("BOTTOM", frame, "BOTTOM", 0, padding)
    durationText:SetJustifyH("CENTER")

    -- Apply text size from settings
    local fontPath, _, fontFlags = durationText:GetFont()
    if fontPath then
        durationText:SetFont(fontPath, textSize, fontFlags)
    end

    -- Create overlay textures
    local wipeOverlay = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    wipeOverlay:SetColorTexture(1, 1, 1, 1.0)
    wipeOverlay:SetSize(iconSize, iconSize)
    wipeOverlay:SetPoint("TOPLEFT", texture, "TOPLEFT")
    wipeOverlay:SetAlpha(0)

    local shakeOverlay = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    shakeOverlay:SetColorTexture(1, 0, 0, 0.75)
    shakeOverlay:SetSize(iconSize, iconSize)
    shakeOverlay:SetPoint("TOPLEFT", texture, "TOPLEFT")
    shakeOverlay:SetAlpha(0)

    -- Get border size from settings
    local borderSize = 0 -- Default border size
    if currentSettings and settingsKey and currentSettings[settingsKey] and currentSettings[settingsKey].borderSize then
        borderSize = currentSettings[settingsKey].borderSize
    end

    -- Apply backdrop
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ItemEntryBG", "backdrop", 0)
    
    -- Create border with thickness effect
    if borderSize > 0 then
        -- Create additional border frames for thickness
        for i = 1, borderSize do
            local borderFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            borderFrame:SetAllPoints(frame)
            borderFrame:SetFrameLevel(frame:GetFrameLevel() + i)
            
            -- Use WoW's native backdrop system for thick borders
            borderFrame:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = i * 2, -- Scale edge size with border thickness
                insets = { left = -i, right = -i, top = -i, bottom = -i }
            })
            borderFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
            
            -- Store reference for cleanup
            if not frame.thickBorderFrames then
                frame.thickBorderFrames = {}
            end
            table.insert(frame.thickBorderFrames, borderFrame)
        end
    end
    
    -- Always create the base border
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "ItemEntryBorder", "border", 0)

    local cfgBG = (BoxxyAuras.Config and BoxxyAuras.Config.BackgroundColor) or {
        r = 0.05,
        g = 0.05,
        b = 0.05,
        a = 0.9
    }
    local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or {
        r = 0.3,
        g = 0.3,
        b = 0.3,
        a = 0.8
    }
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", cfgBG.r, cfgBG.g, cfgBG.b, cfgBG.a)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)

    -- Set up event handlers
    frame:SetScript("OnEnter", function()
        AuraIcon.OnEnter(instance)

        -- << NEW: When entering a child icon, explicitly cancel the parent's leave timer
        local parentFrame = instance.parentDisplayFrame
        if parentFrame and BoxxyAuras.FrameLeaveTimers[parentFrame] then
            C_Timer.Cancel(BoxxyAuras.FrameLeaveTimers[parentFrame])
            BoxxyAuras.FrameLeaveTimers[parentFrame] = nil
        end
        -- Also, ensure the global hover state is set to the parent
        BoxxyAuras.HoveredFrame = parentFrame
    end)
    frame:SetScript("OnLeave", function()
        -- OnLeave is now handled by the parent frame's OnUpdate logic,
        -- but we still need to call the instance's OnLeave for the tooltip.
        AuraIcon.OnLeave(instance)
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and instance.auraType == "HELPFUL" and not InCombatLockdown() then
            if instance.auraInstanceID then
                local buffIndex
                for i = 1, 40 do
                    local auraData = C_UnitAuras.GetAuraDataByIndex and
                                         C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                    if auraData and auraData.auraInstanceID == instance.auraInstanceID then
                        buffIndex = i
                        break
                    end
                    if not auraData then
                        break
                    end
                end
                if buffIndex then
                    CancelUnitBuff("player", buffIndex)
                end
            end
        end
    end)

    -- Create animations
    local animGroup = frame:CreateAnimationGroup()

    -- New aura animation (pop + fade in)
    local scaleAnim = animGroup:CreateAnimation("Scale")
    scaleAnim:SetScale(1.2, 1.2)
    scaleAnim:SetDuration(0.15)
    scaleAnim:SetOrder(1)
    scaleAnim:SetSmoothing("OUT")

    local scaleAnim2 = animGroup:CreateAnimation("Scale")
    scaleAnim2:SetScale(1.0, 1.0)
    scaleAnim2:SetDuration(0.15)
    scaleAnim2:SetOrder(2)
    scaleAnim2:SetSmoothing("IN")

    local alphaAnim = animGroup:CreateAnimation("Alpha")
    alphaAnim:SetFromAlpha(0)
    alphaAnim:SetToAlpha(1)
    alphaAnim:SetDuration(0.2)
    alphaAnim:SetOrder(1)

    -- Wipe overlay animations
    local wipeAlpha = animGroup:CreateAnimation("Alpha")
    wipeAlpha:SetChildKey("wipeOverlay")
    wipeAlpha:SetFromAlpha(0)
    wipeAlpha:SetToAlpha(0.75)
    wipeAlpha:SetDuration(0.1)
    wipeAlpha:SetOrder(1)
    wipeAlpha:SetSmoothing("IN")

    local wipeAlpha2 = animGroup:CreateAnimation("Alpha")
    wipeAlpha2:SetChildKey("wipeOverlay")
    wipeAlpha2:SetFromAlpha(0.75)
    wipeAlpha2:SetToAlpha(0)
    wipeAlpha2:SetDuration(0.25)
    wipeAlpha2:SetOrder(2)
    wipeAlpha2:SetSmoothing("OUT")

    local wipeSlide = animGroup:CreateAnimation("Translation")
    wipeSlide:SetChildKey("wipeOverlay")
    wipeSlide:SetOffset(0, -iconSize)
    wipeSlide:SetDuration(0.25)
    wipeSlide:SetOrder(2)
    wipeSlide:SetSmoothing("OUT")

    -- Shake animation group
    local shakeGroup = frame:CreateAnimationGroup("ShakeGroup")
    local shakeDur = 0.05
    local shakeOffset = 4

    local shake1 = shakeGroup:CreateAnimation("Translation")
    shake1:SetOffset(shakeOffset, 0)
    shake1:SetDuration(shakeDur)
    shake1:SetOrder(1)

    local shake2 = shakeGroup:CreateAnimation("Translation")
    shake2:SetOffset(-shakeOffset * 2, 0)
    shake2:SetDuration(shakeDur * 2)
    shake2:SetOrder(2)

    local shake3 = shakeGroup:CreateAnimation("Translation")
    shake3:SetOffset(shakeOffset, 0)
    shake3:SetDuration(shakeDur)
    shake3:SetOrder(3)

    local shakeOverlayFadeIn = shakeGroup:CreateAnimation("Alpha")
    shakeOverlayFadeIn:SetChildKey("shakeOverlay")
    shakeOverlayFadeIn:SetFromAlpha(0)
    shakeOverlayFadeIn:SetToAlpha(0.6)
    shakeOverlayFadeIn:SetDuration(shakeDur)
    shakeOverlayFadeIn:SetOrder(1)

    local shakeOverlayFadeOut = shakeGroup:CreateAnimation("Alpha")
    shakeOverlayFadeOut:SetChildKey("shakeOverlay")
    shakeOverlayFadeOut:SetFromAlpha(0.6)
    shakeOverlayFadeOut:SetToAlpha(0)
    shakeOverlayFadeOut:SetDuration(shakeDur * 3)
    shakeOverlayFadeOut:SetOrder(2)

    -- Store references
    instance.frame = frame
    instance.parentDisplayFrame = parentFrame
    instance.textureWidget = texture
    instance.newAuraAnimGroup = animGroup
    instance.shakeAnimGroup = shakeGroup
    instance.shakeAnim1 = shake1
    instance.shakeAnim2 = shake2
    instance.shakeAnim3 = shake3

    frame.auraTexture = texture
    frame.countText = countText
    frame.countTextBg = countTextBg
    frame.durationText = durationText
    frame.durationTextBg = durationTextBg
    frame.wipeOverlay = wipeOverlay
    frame.shakeOverlay = shakeOverlay

    -- Initialize state
    instance.duration = 0
    instance.expirationTime = 0
    instance.auraIndex = 0
    instance.tooltipUpdateTimer = 0
    frame:Hide()

    return instance
end

-- Helper to format duration
local function FormatDuration(seconds)
    if seconds >= 3600 then
        return string.format("%.0fh", seconds / 3600)
    elseif seconds >= 60 then
        return string.format("%.0fm", seconds / 60)
    else
        return string.format("%.0fs", seconds)
    end
end

function AuraIcon.Update(self, auraData, index, auraType)
    if not auraData then
        if self.frame and self.frame:IsShown() then
            self.frame:Hide()
            self.frame:SetScript("OnUpdate", nil)
        end
        return
    end

    -- Update state
    self.isExpired = auraData.forceExpired or false
    local wasHidden = not self.frame:IsShown()

    -- Handle forced expiration
    if auraData.forceExpired then
        self.lastIsExpiredState = true
        self.textureWidget:SetVertexColor(1, 0.5, 0.5)
        self.frame.durationText:SetText("0s")
        self.frame:SetScript("OnUpdate", nil)
    end

    -- Update icon appearance
    self.textureWidget:SetTexture(auraData.icon)

    -- Stack count
    if auraData.applications and auraData.applications > 1 then
        self.frame.countText:SetText(auraData.applications)
        self.frame.countText:Show()
        self.frame.countTextBg:Show()
    else
        self.frame.countText:Hide()
        self.frame.countTextBg:Hide()
    end

    -- Store data
    self.duration = auraData.duration
    self.expirationTime = auraData.expirationTime
    self.auraIndex = index
    self.auraType = auraType
    self.name = auraData.name
    if auraData.spellId then
        self.spellId = auraData.spellId
    end
    if auraData.originalAuraType then
        self.originalAuraType = auraData.originalAuraType
    end
    self.auraInstanceID = auraData.auraInstanceID
    self.slot = auraData.slot
    self.auraKey = auraData.spellId
    self.dispelName = auraData.dispelName -- Store dispel type for border color

    -- Set border color based on aura type
    if auraType == "HARMFUL" then
        local dispelType = string.upper(auraData.dispelName or "NONE")

        if dispelType == "NONE" then
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", 1.0, 0.1, 0.1, 0.9)
            self.frame.durationText:SetTextColor(1, 1, 1, 1.0)
        else
            local colorTable = DebuffTypeColor[dispelType]
            if colorTable then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", colorTable[1], colorTable[2], colorTable[3],
                    0.9)
                self.frame.durationText:SetTextColor(colorTable[1], colorTable[2], colorTable[3], 1.0)
            else
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", 1.0, 0.1, 0.1, 0.9)
                self.frame.durationText:SetTextColor(1, 1, 1, 1.0)
            end
        end
    else
        local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.8
        }
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)
        self.frame.durationText:SetTextColor(1, 1, 1, 1)
    end

    -- Set up duration tracking
    if not auraData.forceExpired and self.duration and self.duration > 0 then
        self.frame:SetScript("OnUpdate", function(_, elapsed)
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
        if self.duration == 0 or self.duration <= 0 then
            self.frame:SetScript("OnUpdate", nil)
            if self.frame.durationText then
                self.frame.durationText:Hide()
            end
        end
    end

    -- Ensure correct size by finding the correct frame type from the parent frame
    local frameType = nil
    if self.parentDisplayFrame then
        for fType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame == self.parentDisplayFrame then
                frameType = fType
                break
            end
        end
    end

    if frameType then
        local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

        if currentSettings and settingsKey and currentSettings[settingsKey] then
            local iconSize = currentSettings[settingsKey].iconSize or BoxxyAuras.Config.IconSize
            self:Resize(iconSize)
        end
    end

    -- Show frame
    if not self.frame:IsShown() then
        self.frame:Show()
    end

    -- Initial duration display
    AuraIcon.UpdateDurationDisplay(self, GetTime())
end

function AuraIcon.UpdateDurationDisplay(self, currentTime)
    if not self.frame or not self.frame:IsShown() then
        return
    end

    if self.duration and self.duration > 0 then
        local remaining = self.expirationTime - currentTime
        local isParentHovered = (self.parentDisplayFrame == BoxxyAuras.HoveredFrame) -- Check if the parent frame is THE hovered frame
        local currentIsExpired = (remaining <= 0)
        local currentFormattedText
        local showText = false
        local applyTint = false

        if not currentIsExpired then -- Active aura
            currentFormattedText = FormatDuration(remaining)
            showText = true
            applyTint = false -- No tint for active auras
        else -- Expired aura (remaining <= 0)
            applyTint = true -- Expired tint (red)
            if isParentHovered then -- If parent frame is hovered, keep showing 0s
                currentFormattedText = "0s"
                showText = true
            else -- Otherwise (expired and parent frame not hovered), hide text and stop updating
                showText = false
                self.frame:SetScript("OnUpdate", nil)
            end
        end

        -- Update text if changed or visibility changed
        if currentFormattedText ~= self.lastFormattedDurationText or showText ~= self.frame.durationText:IsShown() then
            if showText then
                self.frame.durationText:SetText(currentFormattedText)
                self.frame.durationText:Show()
            else
                self.frame.durationText:Hide()
            end
            self.lastFormattedDurationText = currentFormattedText
        end

        -- Update tint if expired state OR hover state changed
        if currentIsExpired ~= self.lastIsExpiredState or isParentHovered ~= self.lastIsParentHoveredState then
            if self.textureWidget then
                -- Apply red tint ONLY if expired AND the parent frame is being hovered
                if applyTint and isParentHovered then
                    self.textureWidget:SetVertexColor(1, 0.5, 0.5)
                else
                    -- Normal white tint if active OR expired but parent not hovered
                    self.textureWidget:SetVertexColor(1, 1, 1)
                end
            end
            self.lastIsExpiredState = currentIsExpired
            self.lastIsParentHoveredState = isParentHovered -- Store the hover state
        end
    else
        -- Handle permanent auras (ensure text hidden, tint reset, OnUpdate nil)
        if self.frame.durationText:IsShown() or self.lastFormattedDurationText then
            self.frame.durationText:Hide()
            self.lastFormattedDurationText = nil
        end

        if self.lastIsExpiredState or self.lastIsParentHoveredState then
            if self.textureWidget then
                self.textureWidget:SetVertexColor(1, 1, 1)
            end
            self.lastIsExpiredState = false
            self.lastIsParentHoveredState = false -- Reset hover state tracking too
        end

        if self.frame:GetScript("OnUpdate") then
            self.frame:SetScript("OnUpdate", nil)
        end
    end
end

function AuraIcon.OnEnter(self)
    self.isMouseOver = true
    GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    AuraIcon.RefreshTooltipContent(self)
    GameTooltip:Show()
end

-- Helper function to check if TipTac (or other addons) already added caster information
function AuraIcon.HasCasterLineInTooltip()
    if not GameTooltip:IsShown() or GameTooltip:NumLines() == 0 then
        return false
    end
    
    for i = 1, GameTooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i]
        if line then
            local text = line:GetText() or ""
            -- Check for various patterns that indicate caster information
            -- TipTac uses "Caster:", some other addons might use different patterns
            if string.find(text, "Caster:", 1, true) or 
               string.find(text, "From:", 1, true) or
               string.find(text, "Cast by:", 1, true) or
               string.find(text, "Source:", 1, true) then
                if BoxxyAuras.DEBUG then
                    print(string.format("HasCasterLineInTooltip: Found caster line at position %d: '%s'", i, text))
                end
                return true
            end
        end
    end
    
    if BoxxyAuras.DEBUG then
        print("HasCasterLineInTooltip: No caster lines found")
    end
    return false
end

-- Helper function to add tooltip lines with proper wrapping and coloring for expired auras
function AuraIcon.AddWrappedTooltipLine(leftText, rightText, isTitle)
    if not leftText then return end
    
    local maxLineLength = 50 -- Reasonable character limit for wrapping
    
    -- Define proper tooltip colors
    local titleColor = {r = 1, g = 0.82, b = 0}    -- Golden yellow for spell names
    local normalColor = {r = 1, g = 1, b = 1}      -- White for descriptions
    local rightColor = {r = 1, g = 1, b = 1}       -- White for right text
    
    -- If it's a title line (first line) or has right text, use double line
    if isTitle or (rightText and rightText ~= "") then
        local leftR, leftG, leftB = titleColor.r, titleColor.g, titleColor.b
        if not isTitle then
            leftR, leftG, leftB = normalColor.r, normalColor.g, normalColor.b
        end
        GameTooltip:AddDoubleLine(leftText, rightText or "", 
            leftR, leftG, leftB, rightColor.r, rightColor.g, rightColor.b)
        return
    end
    
    -- Choose color based on line type
    local lineColor = isTitle and titleColor or normalColor
    
    -- For long descriptions, break them into multiple lines
    if string.len(leftText) > maxLineLength then
        local words = {}
        for word in string.gmatch(leftText, "%S+") do
            table.insert(words, word)
        end
        
        local currentLine = ""
        for _, word in ipairs(words) do
            local testLine = currentLine == "" and word or currentLine .. " " .. word
            if string.len(testLine) > maxLineLength and currentLine ~= "" then
                -- Add the current line and start a new one
                GameTooltip:AddLine(currentLine, lineColor.r, lineColor.g, lineColor.b, true)
                currentLine = word
            else
                currentLine = testLine
            end
        end
        
        -- Add any remaining text
        if currentLine ~= "" then
            GameTooltip:AddLine(currentLine, lineColor.r, lineColor.g, lineColor.b, true)
        end
    else
        -- Short lines can be added normally
        GameTooltip:AddLine(leftText, lineColor.r, lineColor.g, lineColor.b, true)
    end
end

function AuraIcon.RefreshTooltipContent(self)
    if not self.frame then
        return
    end

    local currentTime = GetTime()
    local remaining = (self.expirationTime or 0) - currentTime
    local isPermanent = (self.duration or 0) == 0

    GameTooltip:ClearLines()
    
    if BoxxyAuras.DEBUG then
        print(string.format("RefreshTooltipContent: aura=%s, remaining=%.1f, isPermanent=%s, expired=%s", 
            tostring(self.name), remaining, tostring(isPermanent), tostring(remaining <= 0 and not isPermanent)))
    end

    if isPermanent or remaining > 0 then
        local tooltipSet = false

        -- Handle custom auras
        if self.auraType == "CUSTOM" then
            local cachedData = self.auraInstanceID and BoxxyAuras.AllAuras[self.auraInstanceID]
            if cachedData and cachedData.lines then
                if BoxxyAuras.DEBUG then
                    print(string.format("RefreshTooltipContent: Using cached data for custom aura, %d lines", #cachedData.lines))
                end
                -- Use text wrapping to control tooltip width
                
                for i, lineInfo in ipairs(cachedData.lines) do
                    if lineInfo.left then
                        AuraIcon.AddWrappedTooltipLine(lineInfo.left, lineInfo.right, i == 1)
                    end
                end
                
                -- Add caster information if available (check if TipTac already added one)
                local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
                if casterName then
                    local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                    if BoxxyAuras.DEBUG then
                        print(string.format("Tooltip: Custom aura casterName='%s', tiptacExists=%s for instanceID=%s", 
                            tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                    end
                    if not tiptacCasterExists then
                        GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true)  -- Light blue color
                    end
                end
                
                tooltipSet = true
            else
                if BoxxyAuras.DEBUG then
                    print("RefreshTooltipContent: No cached data for custom aura")
                end
            end
        end

        -- Try SetUnitAura for regular auras
        if not tooltipSet and self.auraType ~= "CUSTOM" then
            if self.auraInstanceID and self.auraType then
                local currentIndex
                local filterToUse = self.originalAuraType or self.auraType
                for i = 1, 40 do
                    local currentAuraData = C_UnitAuras.GetAuraDataByIndex("player", i, filterToUse)
                    if currentAuraData and currentAuraData.auraInstanceID == self.auraInstanceID then
                        currentIndex = i
                        break
                    end
                end
                if currentIndex then
                    if BoxxyAuras.DEBUG then
                        print(string.format("RefreshTooltipContent: Using SetUnitAura with index %d", currentIndex))
                    end
                    GameTooltip:SetUnitAura("player", currentIndex, filterToUse)
                    
                    -- Add caster information after WoW sets the tooltip
                    local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
                    if casterName then
                        -- Check if TipTac is loaded - only use delay if it is
                        local isTipTacLoaded = (TipTac ~= nil)
                        
                        if isTipTacLoaded then
                            -- Use a small delay to let TipTac modify the tooltip first
                            C_Timer.After(0.01, function()
                                if GameTooltip:IsOwned(self.frame) then
                                    local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                                    if BoxxyAuras.DEBUG then
                                        print(string.format("Tooltip: Active aura (delayed) casterName='%s', tiptacExists=%s for instanceID=%s", 
                                            tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                                    end
                                    if not tiptacCasterExists then
                                        GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true)  -- Light blue color
                                        GameTooltip:Show()  -- Force tooltip to recalculate size
                                    end
                                end
                            end)
                        else
                            -- No TipTac, add immediately to avoid flashing
                            local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                            if BoxxyAuras.DEBUG then
                                print(string.format("Tooltip: Active aura (immediate) casterName='%s', tiptacExists=%s for instanceID=%s", 
                                    tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                            end
                            if not tiptacCasterExists then
                                GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true)  -- Light blue color
                                GameTooltip:Show()  -- Force tooltip to recalculate size
                            end
                        end
                    end
                    
                    tooltipSet = true
                else
                    if BoxxyAuras.DEBUG then
                        print("RefreshTooltipContent: Aura not found by instance ID")
                    end
                end
            end
        end

        -- Fallback to spell ID
        if not tooltipSet and self.spellId then
            if BoxxyAuras.DEBUG then
                print(string.format("RefreshTooltipContent: Using SetSpellByID with spellId %s", tostring(self.spellId)))
            end
            GameTooltip:SetSpellByID(self.spellId)
            
            -- Add caster information if available (check if TipTac already added one)
            local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
            if casterName then
                local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                if BoxxyAuras.DEBUG then
                    print(string.format("Tooltip: Fallback spell casterName='%s', tiptacExists=%s for instanceID=%s", 
                        tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                end
                if not tiptacCasterExists then
                    GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true)  -- Light blue color
                    GameTooltip:Show()  -- Force tooltip to recalculate size
                end
            end
            
            tooltipSet = true
        end

        -- Last resort
        if not tooltipSet then
            if BoxxyAuras.DEBUG then
                print("RefreshTooltipContent: Using fallback tooltip text")
            end
            GameTooltip:AddLine(self.name or "Unknown Aura")
        end

    elseif not isPermanent and remaining <= 0 then
        -- Show cached data for expired auras
        local cachedData = self.auraInstanceID and BoxxyAuras.AllAuras[self.auraInstanceID]
        if cachedData and cachedData.lines then
            if BoxxyAuras.DEBUG then
                print(string.format("RefreshTooltipContent: Using cached data for expired aura, %d lines, scrapedVia=%s, instanceID=%s", 
                    #cachedData.lines, tostring(cachedData.scrapedVia), tostring(self.auraInstanceID)))
            end
            
            -- Use text wrapping to control tooltip width
            
            for i, lineInfo in ipairs(cachedData.lines) do
                if lineInfo.left then
                    AuraIcon.AddWrappedTooltipLine(lineInfo.left, lineInfo.right, i == 1)
                end
            end
            
            -- Add caster information if available (check if TipTac already added one)
            local casterName = AuraIcon.GetCasterNameFromCurrentData(self)
            if casterName then
                local tiptacCasterExists = AuraIcon.HasCasterLineInTooltip()
                if BoxxyAuras.DEBUG then
                    print(string.format("Tooltip: Expired aura casterName='%s', tiptacExists=%s for instanceID=%s", 
                        tostring(casterName), tostring(tiptacCasterExists), tostring(self.auraInstanceID)))
                end
                if not tiptacCasterExists then
                    GameTooltip:AddLine("From: " .. casterName, 0.5, 0.8, 1.0, true)  -- Light blue color
                    GameTooltip:Show()  -- Force tooltip to recalculate size
                end
            end
            
            GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5, true)
        else
            if BoxxyAuras.DEBUG then
                print(string.format("RefreshTooltipContent: No cached data for expired aura (instanceID=%s)", tostring(self.auraInstanceID)))
                -- Let's also debug what IS in the cache
                print("Current cache contents:")
                for id, data in pairs(BoxxyAuras.AllAuras or {}) do
                    print(string.format("  - ID: %s, Name: %s, ScrapedVia: %s", tostring(id), tostring(data.name), tostring(data.scrapedVia)))
                end
            end
            GameTooltip:AddLine(self.name or "Unknown Expired Aura", 1, 1, 1, true)
            GameTooltip:AddLine("(Expired)", 1, 0.5, 0.5, true)
        end
    else
        if BoxxyAuras.DEBUG then
            print("RefreshTooltipContent: Unknown aura state")
        end
        GameTooltip:AddLine(self.name or "Unknown Aura State")
    end
end

function AuraIcon.OnLeave(self)
    if not self.frame then
        return
    end
    self.isMouseOver = false
    GameTooltip:Hide()
end

function AuraIcon:Shake(scale)
    if not self.frame or not self.shakeAnim1 or not self.shakeAnim2 or not self.shakeAnim3 then
        return
    end

    local scaledOffset = math.min(4 * (scale or 1.0), 12)
    scaledOffset = math.max(scaledOffset, 1)

    self.shakeAnim1:SetOffset(0, -scaledOffset)
    self.shakeAnim2:SetOffset(0, scaledOffset * 2)
    self.shakeAnim3:SetOffset(0, -scaledOffset)

    if self.shakeAnimGroup and not self.shakeAnimGroup:IsPlaying() then
        self.shakeAnimGroup:Play()
    end
end

function AuraIcon:UpdateBorderSize()
    if not self.frame then
        return
    end

    -- Find frame type and get border size setting
    local frameType = nil
    if self.parentDisplayFrame then
        for fType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame == self.parentDisplayFrame then
                frameType = fType
                break
            end
        end
    end

    local borderSize = 0 -- Default border size
    if frameType then
        local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if currentSettings and settingsKey and currentSettings[settingsKey] and currentSettings[settingsKey].borderSize then
            borderSize = currentSettings[settingsKey].borderSize
        end
    end

    -- Redraw the border with the new size using thick border frames
    if BoxxyAuras.UIUtils and BoxxyAuras.UIUtils.DrawSlicedBG then
        -- Clear existing thick border frames
        if self.frame.thickBorderFrames then
            for _, borderFrame in ipairs(self.frame.thickBorderFrames) do
                if borderFrame then
                    borderFrame:Hide()
                    borderFrame:SetParent(nil)
                end
            end
            self.frame.thickBorderFrames = nil
        end
        
        -- Create new thick border frames
        if borderSize > 0 then
            for i = 1, borderSize do
                local borderFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
                borderFrame:SetAllPoints(self.frame)
                borderFrame:SetFrameLevel(self.frame:GetFrameLevel() + i)
                
                -- Use WoW's native backdrop system for thick borders
                borderFrame:SetBackdrop({
                    bgFile = nil,
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = i * 2, -- Scale edge size with border thickness
                    insets = { left = -i, right = -i, top = -i, bottom = -i }
                })
                
                -- Store reference for cleanup
                if not self.frame.thickBorderFrames then
                    self.frame.thickBorderFrames = {}
                end
                table.insert(self.frame.thickBorderFrames, borderFrame)
            end
        end
        
        -- Get the appropriate colors for both base border and thick borders
        local r, g, b, a = 0.3, 0.3, 0.3, 0.8 -- Default colors
        
        if self.auraType == "HARMFUL" then
            local dispelType = string.upper(self.dispelName or "NONE")
            if dispelType == "NONE" then
                r, g, b, a = 1.0, 0.1, 0.1, 0.9
            else
                local colorTable = DebuffTypeColor[dispelType]
                if colorTable then
                    r, g, b, a = colorTable[1], colorTable[2], colorTable[3], 0.9
                else
                    r, g, b, a = 1.0, 0.1, 0.1, 0.9
                end
            end
        else
            local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
            r, g, b, a = cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a
        end
        
        -- Apply color to base border
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self.frame, "border", r, g, b, a)
        
        -- Apply color to thick border frames
        if self.frame.thickBorderFrames then
            for _, borderFrame in ipairs(self.frame.thickBorderFrames) do
                if borderFrame then
                    borderFrame:SetBackdropBorderColor(r, g, b, a)
                end
            end
        end
    end
end

function AuraIcon:Resize(newIconSize)
    if not self.frame or not self.textureWidget then
        if BoxxyAuras.DEBUG then
            print("BoxxyAuras ERROR: Invalid icon instance in Resize - missing frame or texture")
        end
        return
    end

    -- Prevent unnecessary resizing only when both icon and text sizes are unchanged
    if self.currentSize and self.currentSize == newIconSize and self.currentTextSize and self.currentTextSize == textSize then
        return
    end

    if BoxxyAuras.DEBUG then
        local frameType = "unknown"
        if self.parentDisplayFrame then
            for fType, frame in pairs(BoxxyAuras.Frames or {}) do
                if frame == self.parentDisplayFrame then
                    frameType = fType
                    break
                end
            end
        end
        print("BoxxyAuras: Resizing " .. frameType .. " icon from " .. (self.currentSize or "unset") .. " to " ..
                  newIconSize)
    end

    -- Get current text size from settings
    local frameType = nil
    if self.parentDisplayFrame then
        for fType, frame in pairs(BoxxyAuras.Frames or {}) do
            if frame == self.parentDisplayFrame then
                frameType = fType
                break
            end
        end
    end
    
    local textSize = 8 -- default
    if frameType then
        local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if currentSettings and settingsKey and currentSettings[settingsKey] then
            textSize = currentSettings[settingsKey].textSize or 8
        end
    end
    
    local padding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local textAreaHeight = textSize + 4
    local newHeight = newIconSize + textAreaHeight + (padding * 2)
    local newWidth = newIconSize + (padding * 2)

    -- Store the new size
    self.currentSize = newIconSize
    self.currentTextSize = textSize

    -- Resize frame and widgets
    self.frame:SetSize(newWidth, newHeight)
    self.textureWidget:SetSize(newIconSize, newIconSize)

    -- Resize overlays
    if self.frame.wipeOverlay then
        self.frame.wipeOverlay:SetSize(newIconSize, newIconSize)
    end
    if self.frame.shakeOverlay then
        self.frame.shakeOverlay:SetSize(newIconSize, newIconSize)
    end

    -- Reposition text elements
    if self.frame.countText then
        self.frame.countText:ClearAllPoints()
        self.frame.countText:SetPoint("BOTTOMRIGHT", self.textureWidget, "BOTTOMRIGHT", 2, -2)
    end

    if self.frame.durationText then
        self.frame.durationText:ClearAllPoints()
        self.frame.durationText:SetPoint("TOPLEFT", self.textureWidget, "BOTTOMLEFT", 0, -padding)
        self.frame.durationText:SetPoint("TOPRIGHT", self.textureWidget, "BOTTOMRIGHT", 0, -padding)
        self.frame.durationText:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, padding)

        -- Update font size if it changed
        local fontPath, _, fontFlags = self.frame.durationText:GetFont()
        if fontPath then
            self.frame.durationText:SetFont(fontPath, textSize, fontFlags)
        end
    end

    -- Reposition text background to match text
    if self.frame.durationTextBg then
        self.frame.durationTextBg:ClearAllPoints()
        self.frame.durationTextBg:SetPoint("TOPLEFT", self.textureWidget, "BOTTOMLEFT", 0, -padding)
        self.frame.durationTextBg:SetPoint("TOPRIGHT", self.textureWidget, "BOTTOMRIGHT", 0, -padding)
        self.frame.durationTextBg:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, padding)
    end

    -- Re-anchor overlay textures
    if self.frame.wipeOverlay then
        self.frame.wipeOverlay:ClearAllPoints()
        self.frame.wipeOverlay:SetPoint("TOPLEFT", self.textureWidget, "TOPLEFT")
    end

    if self.frame.shakeOverlay then
        self.frame.shakeOverlay:ClearAllPoints()
        self.frame.shakeOverlay:SetPoint("TOPLEFT", self.textureWidget, "TOPLEFT")
    end
end

-- Helper function to get caster name from tracked aura data
function AuraIcon.GetCasterNameFromCurrentData(self)
    if not self or not self.auraInstanceID then
        return nil
    end
    
    -- Always try to get source info from our tracked data first
    -- This is where we store the sourceGUID from combat log events
    for frameType, auras in pairs(BoxxyAuras.auraTracking or {}) do
        for _, aura in ipairs(auras or {}) do
            if aura.auraInstanceID == self.auraInstanceID then
                if BoxxyAuras.DEBUG then
                    print(string.format("GetCasterNameFromCurrentData: Found tracked aura with sourceGUID='%s'", 
                        tostring(aura.sourceGUID)))
                end
                return BoxxyAuras.UIUtils.GetCasterName(aura)
            end
        end
    end
    
    if BoxxyAuras.DEBUG then
        print(string.format("GetCasterNameFromCurrentData: No tracked data found for instanceID=%s", 
            tostring(self.auraInstanceID)))
    end
    
    -- Fallback: if no tracked data, we can't reliably determine caster
    -- WoW's live APIs don't preserve original caster information
    return nil
end

-- Assign to the global table
BoxxyAuras.AuraIcon = AuraIcon
