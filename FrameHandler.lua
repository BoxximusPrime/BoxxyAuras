local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras = BoxxyAuras or {}
BoxxyAuras.FrameHandler = {}

-- Placeholder for frame variables
local buffDisplayFrame
local debuffDisplayFrame
local customDisplayFrame

-- Define constants and shared variables needed by frame functions
local handleSize = 8
local draggingHandle = nil -- Per-frame state? Might need adjustment
local dragStartX, dragStartY = 0, 0
local frameStartX, frameStartY, frameStartW, frameStartH = 0, 0, 0, 0
local minFrameW, minFrameH = 100, 50 -- Minimum dimensions

local handlePoints = {
    Left = {"LEFT", 0, 0},
    Right = {"RIGHT", 0, 0},
}

-- Forward declarations
local LayoutAuras -- LayoutAuras is called by CreateResizeHandlesForFrame
local UpdateEdgeHandleDimensions -- Called by LayoutAuras and OnDisplayFrameResizeUpdate
local CalculateFrameWidth -- Called by ApplySettings and OnDisplayFrameResizeUpdate

-- Moved Helper function to calculate required frame width
function BoxxyAuras.FrameHandler.CalculateFrameWidth(numIcons, iconTextureSize)
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 12
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 0
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6

    -- Calculate the actual width of ONE icon frame
    local singleIconTotalWidth = iconTextureSize + (internalPadding * 2)

    -- Calculate total width using the icon's total width, spacing, and frame padding
    return (numIcons * singleIconTotalWidth) + (math.max(0, numIcons - 1) * iconSpacing) + (framePadding * 2)
end

-- Moved function: Create Resize Handles
local function CreateResizeHandlesForFrame(frame, frameName)
    frame.handles = frame.handles or {}
    -- Using minFrameW/minFrameH defined above

    for pointName, pointData in pairs(handlePoints) do
        local point, xOff, yOff = unpack(pointData)
        local handle = CreateFrame("Frame", "BoxxyAurasResizeHandle" .. frameName .. pointName, frame)
        
        local h = frame:GetHeight() * 0.8
        local w = handleSize -- Uses handleSize defined above
        yOff = 0

        handle:SetSize(w, h)
        handle.pointName = pointName
        
        handle:SetPoint(point, frame, point, xOff, yOff)
        handle:SetFrameLevel(frame:GetFrameLevel() + 10)
        handle:EnableMouse(true)

        handle.bg = handle:CreateTexture(nil, "BACKGROUND")
        handle.bg:SetAllPoints(true)
        handle.bg:SetColorTexture(0.8, 0.8, 0.8, 0.7)
        handle.bg:Hide()

        handle:SetScript("OnEnter", function(self) self.bg:Show() end)
        handle:SetScript("OnLeave", function(self)
            -- Uses frame.draggingHandle
            if frame.draggingHandle ~= self.pointName then self.bg:Hide() end
        end)

        handle:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                -- Uses frame state vars defined above (draggingHandle, dragStartX/Y, etc.)
                frame.draggingHandle = pointName
                frame.dragStartX, frame.dragStartY = GetCursorPosition()
                frame.frameStartW, frame.frameStartH = frame:GetSize()
                frame.frameStartX = frame:GetLeft()
                frame.frameStartY = frame:GetTop()
                self.bg:Show()
                
                -- *** ADDED DEBUG LOG for numIconsWide at Drag Start ***
                local dbKey = nil
                local frameType = nil
                local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
                local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
                local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()
                
                if frame == currentBuffFrame then dbKey = "buffFrameSettings" frameType = "Buff"
                elseif frame == currentDebuffFrame then dbKey = "debuffFrameSettings" frameType = "Debuff"
                elseif frame == currentCustomFrame then dbKey = "customFrameSettings" frameType = "Custom"
                end
                
                local startNumIconsWide = "???" -- Default if not found
                if dbKey and BoxxyAurasDB and BoxxyAurasDB[dbKey] and BoxxyAurasDB[dbKey].numIconsWide then
                    startNumIconsWide = BoxxyAurasDB[dbKey].numIconsWide
                end
            end
        end)
        handle:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and frame.draggingHandle == self.pointName then
                local dbKey = nil
                local frameType = nil
                -- Uses local frame variables via Getters
                local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
                local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
                local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()
                
                if frame == currentBuffFrame then 
                    dbKey = "buffFrameSettings"
                    frameType = "Buff"
                elseif frame == currentDebuffFrame then 
                    dbKey = "debuffFrameSettings"
                    frameType = "Debuff"
                elseif frame == currentCustomFrame then 
                    dbKey = "customFrameSettings"
                    frameType = "Custom"
                end
                -- Requires BoxxyAurasDB for settings access

                -- *** ADDED DEBUG LOG for numIconsWide at Drag End ***
                local endNumIconsWide = "???" -- Default if not found
                if dbKey and BoxxyAurasDB and BoxxyAurasDB[dbKey] and BoxxyAurasDB[dbKey].numIconsWide then
                    endNumIconsWide = BoxxyAurasDB[dbKey].numIconsWide
                end

                -- Calls LayoutAuras (needs to be defined in this file)
                if frameType and LayoutAuras then
                    LayoutAuras(frameType)
                else
                    BoxxyAuras.DebugLogWarning("CreateResizeHandlesForFrame OnMouseUp: Could not determine frameType or LayoutAuras not found.")
                end

                frame.draggingHandle = nil
                self.bg:Hide()
            end
        end)
        frame.handles[pointName] = handle
    end
end

-- Moved function: Update Edge Handle Dimensions
local function UpdateEdgeHandleDimensions(frame, frameW, frameH)
    if not frame or not frame.handles then return end -- Safety check
    for pointName, handle in pairs(frame.handles) do
        -- Only Left and Right handles exist now
        -- Uses handleSize defined above
        handle:SetSize(handleSize, frameH * 0.8)
    end
end

-- Moved function: Layout Auras
LayoutAuras = function(frameType) -- Changed argument to frameType string
    -- Fetch targetFrame and iconList based on frameType
    local targetFrame = nil
    local iconList = nil
    local settingsKey = nil

    if frameType == "Buff" then
        targetFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Buff
        iconList = BoxxyAuras.buffIcons
        settingsKey = "buffFrameSettings"
    elseif frameType == "Debuff" then
        targetFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Debuff
        iconList = BoxxyAuras.debuffIcons
        settingsKey = "debuffFrameSettings"
    elseif frameType == "Custom" then
        targetFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Custom
        iconList = BoxxyAuras.customIcons
        settingsKey = "customFrameSettings"
    else
        BoxxyAuras.DebugLogError(string.format("LayoutAuras Error: Invalid frameType '%s' received.", tostring(frameType)))
        return
    end

    -- Check if frame or list is missing after lookup
    if not targetFrame then
        BoxxyAuras.DebugLogError(string.format("LayoutAuras Error: Could not find targetFrame for frameType '%s'.", frameType))
        return
    end
    if not iconList then
        BoxxyAuras.DebugLogError(string.format("LayoutAuras Error: Could not find iconList for frameType '%s'.", frameType))
        return -- Don't check #iconList here, allow empty list processing for height adjustment
    end

    local alignment = "LEFT"
    local numIconsWide = 6

    -- Read settings if key is valid
    if settingsKey and BoxxyAurasDB and BoxxyAurasDB[settingsKey] then
        alignment = BoxxyAurasDB[settingsKey][frameType:lower().."TextAlign"] or alignment -- e.g., buffTextAlign
        numIconsWide = BoxxyAurasDB[settingsKey].numIconsWide or numIconsWide
    end

    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6

    local visibleIconCount = 0
    for _, auraIcon in ipairs(iconList) do
        if auraIcon and auraIcon.frame and auraIcon.frame:IsShown() then -- Added check for auraIcon existence
            visibleIconCount = visibleIconCount + 1
        end
    end

    local iconW, iconH = nil, nil
    local currentIconSize = 24
    if settingsKey and BoxxyAurasDB and BoxxyAurasDB[settingsKey] and BoxxyAurasDB[settingsKey].iconSize then
        currentIconSize = BoxxyAurasDB[settingsKey].iconSize
    end

    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    iconW = currentIconSize + (internalPadding * 2)
    iconH = currentIconSize + textHeight + (internalPadding * 2)

    local iconsPerRow = math.max(1, numIconsWide)
    local numRows = math.max(1, math.ceil(visibleIconCount / iconsPerRow))
    if visibleIconCount == 0 then numRows = 1 end -- Ensure at least 1 row for height calculation even if empty

    local requiredIconBlockHeight = numRows * iconH + math.max(0, numRows - 1) * iconSpacing
    local requiredFrameHeight = framePadding + requiredIconBlockHeight + framePadding

    local minPossibleHeight = framePadding + (1 * iconH) + framePadding
    local targetHeight = math.max(minPossibleHeight, requiredFrameHeight)

    local frameH = targetFrame:GetHeight()
    if frameH ~= targetHeight then
        targetFrame:SetHeight(targetHeight)
        local currentWidthForHandleUpdate = targetFrame:GetWidth()
        if UpdateEdgeHandleDimensions then UpdateEdgeHandleDimensions(targetFrame, currentWidthForHandleUpdate, targetHeight) end
        frameH = targetHeight
    end

    -- Exit here if no icons need positioning
    if visibleIconCount == 0 then 
        return 
    end

    local frameW = targetFrame:GetWidth()
    local iconsPerRowNum = {}
    if alignment == "CENTER" then
        local remainingIcons = visibleIconCount
        for r = 1, numRows do
            local iconsThisRow = math.min(remainingIcons, iconsPerRow)
            iconsPerRowNum[r] = iconsThisRow
            remainingIcons = remainingIcons - iconsThisRow
        end
    end

    local frameAnchorPoint = (alignment == "RIGHT") and "TOPRIGHT" or "TOPLEFT"
    local iconAnchorPoint = frameAnchorPoint
    if alignment == "CENTER" then
        frameAnchorPoint = "TOPLEFT"
        iconAnchorPoint = "TOPLEFT"
    end

    local currentVisibleIndex = 0
    for i, auraIcon in ipairs(iconList) do
        if auraIcon and auraIcon.frame and auraIcon.frame:IsShown() then -- Added check for auraIcon existence
            currentVisibleIndex = currentVisibleIndex + 1
            local row = math.floor((currentVisibleIndex - 1) / iconsPerRow)
            local col_from_left = (currentVisibleIndex - 1) % iconsPerRow
            auraIcon.frame:ClearAllPoints()

            local yOffset = -framePadding - (row * (iconH + iconSpacing))
            local xOffset = 0

            if alignment == "CENTER" then
                local iconsOnThisRow = iconsPerRowNum[row + 1] or 1
                local rowWidth = iconsOnThisRow * iconW + math.max(0, iconsOnThisRow - 1) * iconSpacing
                local startXForRow = (frameW - rowWidth) / 2
                xOffset = startXForRow + col_from_left * (iconW + iconSpacing)
            elseif alignment == "RIGHT" then
                xOffset = -(framePadding + col_from_left * (iconW + iconSpacing))
            else -- LEFT
                xOffset = framePadding + col_from_left * (iconW + iconSpacing)
            end

            auraIcon.frame:SetPoint(iconAnchorPoint, targetFrame, frameAnchorPoint, xOffset, yOffset)
            auraIcon.frame:Show()
        end
    end
end
BoxxyAuras.FrameHandler.LayoutAuras = LayoutAuras -- Assign to handler table if needed externally

-- Moved function: Poll Frame Hover State
local function PollFrameHoverState(frame, frameDesc)
    if not frame then
        BoxxyAuras.DebugLogWarning("PollFrameHoverState - frame is nil")
        return
    end 
    
    -- Requires BoxxyAuras.IsMouseWithinFrame function
    local mouseIsOverNow = BoxxyAuras.IsMouseWithinFrame(frame) 
    local wasOver = frame.isMouseOver 
    local wasLocked = frame.wasLocked 
    local isLockedNow = frame.isLocked 

    -- Uses local frame variables via Getters
    local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
    local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
    local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()

    -- Update global hover state table in BoxxyAuras
    if frame == currentBuffFrame then BoxxyAuras.FrameHoverStates.BuffFrame = mouseIsOverNow
    elseif frame == currentDebuffFrame then BoxxyAuras.FrameHoverStates.DebuffFrame = mouseIsOverNow
    elseif frame == currentCustomFrame then BoxxyAuras.FrameHoverStates.CustomFrame = mouseIsOverNow
    end
    
    local needsUpdate = (mouseIsOverNow ~= wasOver) or (isLockedNow ~= wasLocked)
    
    if needsUpdate then
        frame.isMouseOver = mouseIsOverNow 
        frame.wasLocked = isLockedNow      
        
        -- Logic for immediate expired aura removal on mouse leave
        if not mouseIsOverNow and wasOver then 
            local sourceTrackedList = nil
            local visualIconList = nil
            local targetFrame = frame 
            local listType = nil

            if frame == currentBuffFrame then 
                listType = "Buff"
                visualIconList = BoxxyAuras.buffIcons
            elseif frame == currentDebuffFrame then 
                listType = "Debuff"
                visualIconList = BoxxyAuras.debuffIcons
            elseif frame == currentCustomFrame then 
                listType = "Custom"
                visualIconList = BoxxyAuras.customIcons
            end

            -- Requires access to tracked lists from BoxxyAuras
            -- TODO: Implement GetTrackedAuras/SetTrackedAuras in BoxxyAuras.lua
            if listType and BoxxyAuras.GetTrackedAuras then 
                sourceTrackedList = BoxxyAuras.GetTrackedAuras(listType)
            end

            if sourceTrackedList and visualIconList then
                local newTrackedList = {}
                local hasExpiredAurasToRemove = false
                for _, trackedAura in ipairs(sourceTrackedList) do
                    if not trackedAura.forceExpired then
                        trackedAura.forceExpired = nil 
                        table.insert(newTrackedList, trackedAura)
                    else
                        hasExpiredAurasToRemove = true 
                    end
                end

                if hasExpiredAurasToRemove then
                    local keptInstanceIDs = {}
                    for _, keptAura in ipairs(newTrackedList) do
                        if keptAura.auraInstanceID then keptInstanceIDs[keptAura.auraInstanceID] = true end
                    end

                    for _, auraIcon in ipairs(visualIconList) do
                        if auraIcon and auraIcon.frame and auraIcon.auraInstanceID then
                            if not keptInstanceIDs[auraIcon.auraInstanceID] then auraIcon.frame:Hide() end
                        end
                    end

                    -- Requires SetTrackedAuras in BoxxyAuras.lua
                    if listType and BoxxyAuras.SetTrackedAuras then 
                        BoxxyAuras.SetTrackedAuras(listType, newTrackedList)
                    end
                    
                    -- Calls local LayoutAuras
                    LayoutAuras(listType) 
                end
            end
        end
        
        -- Update visual background AND border effect
        local backdropGroupName = "backdrop" 
        local borderGroupName = "border"
        
        local hasBackdrop = frame and frame.backdropTextures
        local hasBorder = frame and frame.borderTextures

        if not hasBackdrop and not frame.textureSetupComplete then 
            BoxxyAuras.DebugLogError(string.format("Poll Error [V2]: backdropTextures NOT FOUND for %s! Frame Type: %s", frameDesc or "UnknownFrame", type(frame)))
        end
        if not hasBorder and not frame.textureSetupComplete then 
             BoxxyAuras.DebugLogError(string.format("Poll Error [V2]: borderTextures NOT FOUND for %s! Frame Type: %s", frameDesc or "UnknownFrame", type(frame)))
        end

        if hasBackdrop and hasBorder then
            local r_bg, g_bg, b_bg, a_bg = 0, 0, 0, 0 
            local r_br, g_br, b_br, a_br = 0, 0, 0, 0 

            if isLockedNow then
                a_bg = 0
                a_br = 0
            else
                -- Requires BoxxyAuras.Config
                local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
                local cfgHover = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
                
                if mouseIsOverNow and not frame.draggingHandle then 
                    r_bg, g_bg, b_bg, a_bg = cfgHover.r, cfgHover.g, cfgHover.b, cfgHover.a
                else 
                    r_bg, g_bg, b_bg, a_bg = cfgBGN.r, cfgBGN.g, cfgBGN.b, cfgBGN.a
                end
                
                local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
                r_br, g_br, b_br, a_br = cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a
            end
            
            -- Requires BoxxyAuras.UIUtils
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, backdropGroupName, r_bg, g_bg, b_bg, a_bg)
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, borderGroupName, r_br, g_br, b_br, a_br)
        end
    end
end
BoxxyAuras.FrameHandler.PollFrameHoverState = PollFrameHoverState -- Assign to handler table if needed externally

-- Moved function: Setup Display Frame
local function SetupDisplayFrame(frame, frameName)
    local backdropTextureKey = frameName .. "HoverBG"
    local borderTextureKey = "EdgedBorder"
    
    frame.textureSetupComplete = false
    
    -- Requires BoxxyAuras.UIUtils
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, backdropTextureKey, "backdrop", 0)
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, borderTextureKey, "border", 0)

    if frame.backdropTextures and frame.borderTextures then
        frame.textureSetupComplete = true
    else
        frame.textureSetupComplete = false
        BoxxyAuras.DebugLogWarning(string.format("Texture setup might have failed for %s.", frameName))
    end

    -- Requires BoxxyAuras.Config
    local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
    local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.5, g = 0.5, b = 0.5, a = 1.0 }

    -- Requires BoxxyAuras.UIUtils
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", cfgBGN.r, cfgBGN.g, cfgBGN.b, cfgBGN.a)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)

    local labelText
    if frameName == "BuffFrame" then labelText = "Buffs"
    elseif frameName == "DebuffFrame" then labelText = "Debuffs"
    elseif frameName == "CustomFrame" then labelText = "Custom"
    else labelText = frameName end
    
    local titleLabel = frame:CreateFontString(frameName .. "TitleLabel", "OVERLAY", "GameFontNormalLarge")
    if titleLabel then
        titleLabel:ClearAllPoints()
        titleLabel:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
        titleLabel:SetJustifyH("LEFT")
        titleLabel:SetTextColor(1, 1, 1, 0.9)
        titleLabel:SetText(labelText)
        frame.titleLabel = titleLabel
    else
        BoxxyAuras.DebugLogError(string.format("Failed to create TitleLabel for Frame='%s', Name='%s'", frame:GetName() or "N/A", tostring(frameName)))
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) 
        if not self.isLocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self then
            BoxxyAuras.DebugLogError("self is nil in OnDragStop!")
            return
        end

        if type(self.StopMovingOrSizing) == "function" then self:StopMovingOrSizing() end
        self.draggingHandle = nil

        local finalX, finalY = self:GetLeft(), self:GetTop()
        local dbKey = nil
        -- Uses local frame variables via Getters
        local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
        local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
        local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()

        if self == currentBuffFrame then dbKey = "buffFrameSettings"
        elseif self == currentDebuffFrame then dbKey = "debuffFrameSettings"
        elseif self == currentCustomFrame then dbKey = "customFrameSettings" end

        -- Requires BoxxyAurasDB
        if dbKey and BoxxyAurasDB and BoxxyAurasDB[dbKey] then
            BoxxyAurasDB[dbKey].x = finalX
            BoxxyAurasDB[dbKey].y = finalY
            BoxxyAurasDB[dbKey].anchor = "TOPLEFT"
        end

        -- Determine frameType based on self
        local frameType = nil
        if self == currentBuffFrame then frameType = "Buff"
        elseif self == currentDebuffFrame then frameType = "Debuff"
        elseif self == currentCustomFrame then frameType = "Custom"
        end
        
        -- Calls local LayoutAuras with the correct frameType string
        if frameType and LayoutAuras then 
            LayoutAuras(frameType) 
        else
            BoxxyAuras.DebugLogWarning(string.format("OnDragStop Error: Could not determine frameType (%s) or LayoutAuras missing for frame %s", tostring(frameType), self:GetName()))
        end 
    end)
    frame:SetClampedToScreen(true)
end

-- Moved function: Apply Settings
local function ApplySettings(frameType) -- Changed primary arg to frameType
    -- Get frame and settings based on type
    local targetFrame = BoxxyAuras.Frames and BoxxyAuras.Frames[frameType]
    local settingsKey = nil
    if frameType == "Buff" then settingsKey = "buffFrameSettings"
    elseif frameType == "Debuff" then settingsKey = "debuffFrameSettings"
    elseif frameType == "Custom" then settingsKey = "customFrameSettings"
    else
        BoxxyAuras.DebugLogError(string.format("ApplySettings Error: Invalid frameType '%s' received.", tostring(frameType)))
        return
    end

    if not targetFrame then 
        BoxxyAuras.DebugLogError(string.format("ApplySettings Error: Target frame not found for type '%s'.", frameType))
        return 
    end

    local settings = BoxxyAurasDB and BoxxyAurasDB[settingsKey]
    if not settings then
        BoxxyAuras.DebugLogError(string.format("ApplySettings Error: Settings not found in DB for key '%s'.", settingsKey))
        return -- Need settings to proceed
    end

    -- Requires BoxxyAuras.Config
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6 
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6   
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6 
    
    local iconTextureSize = settings.iconSize or 24 -- Use fetched settings
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    
    local iconW = iconTextureSize + (internalPadding * 2)
    local iconH = iconTextureSize + textHeight + (internalPadding * 2)
    
    local numIconsWide = settings.numIconsWide or 6 -- Use fetched settings
    numIconsWide = math.max(1, numIconsWide) 
    
    -- Requires BoxxyAuras.FrameHandler.CalculateFrameWidth
    local calculatedWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconTextureSize)
    
    local calculatedMinHeight = framePadding + iconH + framePadding 
    
    targetFrame:SetSize(calculatedWidth, calculatedMinHeight) -- Apply size to targetFrame
    targetFrame:ClearAllPoints()
    -- Apply positioning based on fetched settings
    if settings.anchor == "CENTER" then
        targetFrame:SetPoint("CENTER", UIParent, "CENTER", settings.x or 0, settings.y or 0)
    elseif settings.anchor == "TOP" then
        targetFrame:SetPoint("TOP", UIParent, "TOP", settings.x or 0, settings.y or 0)
    else -- Default to TOPLEFT
        targetFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.x or 0, settings.y or 0)
    end
end 
BoxxyAuras.FrameHandler.ApplySettings = ApplySettings -- Assign to handler table if needed externally

-- Moved function: Trigger Layout Helper
function BoxxyAuras.FrameHandler.TriggerLayout(frameType)
    local targetFrame = nil
    local iconList = nil
    
    -- Uses local frame variables via Getters
    local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
    local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
    local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()

    if frameType == "Buff" then
        targetFrame = currentBuffFrame
        iconList = BoxxyAuras.buffIcons -- Requires BoxxyAuras icon list
    elseif frameType == "Debuff" then
        targetFrame = currentDebuffFrame
        iconList = BoxxyAuras.debuffIcons -- Requires BoxxyAuras icon list
    elseif frameType == "Custom" then
        targetFrame = currentCustomFrame
        iconList = BoxxyAuras.customIcons -- Requires BoxxyAuras icon list
    else
        BoxxyAuras.DebugLogError(string.format("FrameHandler Error: Invalid frameType '%s' passed to TriggerLayout.", tostring(frameType)))
        return
    end

    if targetFrame and iconList and LayoutAuras then -- Calls local LayoutAuras
        LayoutAuras(frameType)
    else
        BoxxyAuras.DebugLogWarning(string.format("FrameHandler Warning: Could not trigger layout for %s. Frame, Icons, or LayoutAuras missing?", frameType))
    end
end

-- *** NEW Function to Apply Lock State ***
function BoxxyAuras.FrameHandler.ApplyLockState(isLocked)
    local framesToUpdate = { BoxxyAuras.Frames.Buff, BoxxyAuras.Frames.Debuff, BoxxyAuras.Frames.Custom }

    for _, frame in ipairs(framesToUpdate) do
        if frame then
            frame:SetMovable(not isLocked)
            frame:EnableMouse(not isLocked) -- Enable/disable mouse based on lock state
            frame.isLocked = isLocked

            -- Show/Hide Handles
            if frame.handles then
                for handleName, handle in pairs(frame.handles) do
                    if isLocked then
                        handle:EnableMouse(false)
                        handle:Hide()
                    else
                        handle:EnableMouse(true)
                        handle:Show()
                    end
                end
            end

            -- Show/Hide Title Label
            if frame.titleLabel then
                if isLocked then frame.titleLabel:Hide() else frame.titleLabel:Show() end
            end

            -- Adjust Background/Border Alpha (using PollFrameHoverState logic)
            local backdropGroupName = "backdrop" 
            local borderGroupName = "border"
            local r_bg, g_bg, b_bg, a_bg = 0, 0, 0, 0 
            local r_br, g_br, b_br, a_br = 0, 0, 0, 0 

            if isLocked then
                a_bg = 0
                a_br = 0
            else
                -- Use normal colors when unlocked (hover handled by PollFrameHoverState)
                local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
                local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
                r_bg, g_bg, b_bg, a_bg = cfgBGN.r, cfgBGN.g, cfgBGN.b, cfgBGN.a
                r_br, g_br, b_br, a_br = cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a
            end

            if frame.backdropTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, backdropGroupName, r_bg, g_bg, b_bg, a_bg)
            end
            if frame.borderTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, borderGroupName, r_br, g_br, b_br, a_br)
            end
        end
    end
end

-- Initialization function for all frames
function BoxxyAuras.FrameHandler.InitializeFrames()
    buffDisplayFrame = CreateFrame("Frame", "BoxxyBuffDisplayFrame", UIParent)
    debuffDisplayFrame = CreateFrame("Frame", "BoxxyDebuffDisplayFrame", UIParent)
    customDisplayFrame = CreateFrame("Frame", "BoxxyCustomDisplayFrame", UIParent)

    BoxxyAuras.Frames.Buff = buffDisplayFrame
    BoxxyAuras.Frames.Debuff = debuffDisplayFrame
    BoxxyAuras.Frames.Custom = customDisplayFrame

    -- Ensure DB is initialized (Assume BoxxyAuras main file ensures this)
    if BoxxyAurasDB == nil then 
        BoxxyAuras.DebugLogError("InitializeFrames: BoxxyAurasDB is nil!")
        BoxxyAurasDB = {} -- Initialize locally? Risky.
    end

    -- Define defaults (Copied from BoxxyAuras.lua PLAYER_LOGIN)
    local DEFAULT_ICONS_WIDE = 6 -- Define local default
    local defaultPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local defaultIconSize_ForCalc = 24
    local defaultTextHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    local defaultIconH = defaultIconSize_ForCalc + defaultTextHeight + (defaultPadding * 2)
    local defaultFramePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local defaultMinHeight = defaultFramePadding + defaultIconH + defaultFramePadding

    local defaultBuffFrameSettings = {
        x = 0, y = -150, anchor = "TOP",
        width = 300, height = defaultMinHeight,
        numIconsWide = DEFAULT_ICONS_WIDE,
        buffTextAlign = "CENTER",
        iconSize = 24
    }
    local defaultDebuffFrameSettings = {
        x = 0, y = -150 - defaultMinHeight - 30, anchor = "TOP",
        width = 300, height = defaultMinHeight,
        numIconsWide = DEFAULT_ICONS_WIDE,
        debuffTextAlign = "CENTER",
        iconSize = 24
    }
    local defaultCustomFrameSettings = {
        x = 0, y = -150 - defaultMinHeight - 60, anchor = "TOP",
        width = 300, height = defaultMinHeight,
        numIconsWide = DEFAULT_ICONS_WIDE,
        customTextAlign = "CENTER",
        iconSize = 24
    }

    -- Helper for initializing settings (now local to this function)
    local function InitializeSettings(dbKey, defaults)
        if type(defaults) ~= "table" then
            BoxxyAuras.DebugLogError(string.format("InitializeSettings Error: Default settings for %s are not a table!", dbKey))
            if BoxxyAurasDB then BoxxyAurasDB[dbKey] = {} end
            return BoxxyAurasDB and BoxxyAurasDB[dbKey] or {}
        end
        if not BoxxyAurasDB then 
            BoxxyAuras.DebugLogError("InitializeSettings Error: BoxxyAurasDB is nil when initializing "..dbKey)
            return CopyTable(defaults)
        end
        if BoxxyAurasDB[dbKey] == nil then
            BoxxyAurasDB[dbKey] = CopyTable(defaults) -- Assumes CopyTable is available globally or in BoxxyAuras
        else
            for key, defaultValue in pairs(defaults) do
                if BoxxyAurasDB[dbKey][key] == nil then
                    BoxxyAurasDB[dbKey][key] = defaultValue
                end
            end
        end
        return BoxxyAurasDB[dbKey]
    end

    local buffSettings = InitializeSettings("buffFrameSettings", defaultBuffFrameSettings)
    local debuffSettings = InitializeSettings("debuffFrameSettings", defaultDebuffFrameSettings)
    local customSettings = InitializeSettings("customFrameSettings", defaultCustomFrameSettings)

    -- Apply Settings (Calls local ApplySettings function)
    ApplySettings("Buff")
    ApplySettings("Debuff")
    ApplySettings("Custom")

    -- Initialize Handles (Calls local CreateResizeHandlesForFrame)
    CreateResizeHandlesForFrame(buffDisplayFrame, "BuffFrame")
    CreateResizeHandlesForFrame(debuffDisplayFrame, "DebuffFrame")
    CreateResizeHandlesForFrame(customDisplayFrame, "CustomFrame")
    
    -- Update handle dimensions after initial size is set by ApplySettings
    -- Calls local UpdateEdgeHandleDimensions
    UpdateEdgeHandleDimensions(buffDisplayFrame, buffDisplayFrame:GetWidth(), buffDisplayFrame:GetHeight())
    UpdateEdgeHandleDimensions(debuffDisplayFrame, debuffDisplayFrame:GetWidth(), debuffDisplayFrame:GetHeight())
    UpdateEdgeHandleDimensions(customDisplayFrame, customDisplayFrame:GetWidth(), customDisplayFrame:GetHeight())

    -- Setup Display Frames visuals (Calls local SetupDisplayFrame)
    SetupDisplayFrame(buffDisplayFrame, "BuffFrame")
    SetupDisplayFrame(debuffDisplayFrame, "DebuffFrame")
    SetupDisplayFrame(customDisplayFrame, "CustomFrame")

    -- Apply initial scale AND lock state
    if BoxxyAurasDB then
        local initialScale = BoxxyAurasDB.optionsScale or 1.0
        local initialLock = BoxxyAurasDB.lockFrames or false

        if buffDisplayFrame then buffDisplayFrame:SetScale(initialScale) end
        if debuffDisplayFrame then debuffDisplayFrame:SetScale(initialScale) end
        if customDisplayFrame then customDisplayFrame:SetScale(initialScale) end

        -- Apply initial lock state using the new function
        BoxxyAuras.FrameHandler.ApplyLockState(initialLock)
    end

    -- Start polling timers (Calls local PollFrameHoverState)
    C_Timer.NewTicker(0.1, function() PollFrameHoverState(buffDisplayFrame, "Buff Frame") end)
    C_Timer.NewTicker(0.1, function() PollFrameHoverState(debuffDisplayFrame, "Debuff Frame") end)
    C_Timer.NewTicker(0.1, function() PollFrameHoverState(customDisplayFrame, "Custom Frame") end)

    -- Attach the resize update function (local OnDisplayFrameResizeUpdate)
    buffDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate)
    debuffDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate)
    customDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate)
end

-- Getters
function BoxxyAuras.FrameHandler.GetBuffFrame() return buffDisplayFrame end
function BoxxyAuras.FrameHandler.GetDebuffFrame() return debuffDisplayFrame end
function BoxxyAuras.FrameHandler.GetCustomFrame() return customDisplayFrame end

-- Keep the original OnDisplayFrameResizeUpdate function for now
-- It will be moved/integrated later
-- Generalized OnUpdate function for resizing (NEW LOGIC)
function OnDisplayFrameResizeUpdate(frame, elapsed)
    if not frame then return end -- Added safety check
    if not frame.draggingHandle then return end
    if not IsMouseButtonDown("LeftButton") then return end

    -- Determine settings key
    local settingsKey = nil
    -- Need access to the frame variables (buffDisplayFrame, etc.)
    -- This check needs to happen *after* the frames are created in InitializeFrames
    if frame == BoxxyAuras.FrameHandler.GetBuffFrame() then settingsKey = "buffFrameSettings"
    elseif frame == BoxxyAuras.FrameHandler.GetDebuffFrame() then settingsKey = "debuffFrameSettings"
    elseif frame == BoxxyAuras.FrameHandler.GetCustomFrame() then settingsKey = "customFrameSettings"
    else return end

    if not BoxxyAurasDB or not BoxxyAurasDB[settingsKey] then return end

    local fixedFrameH = frame:GetHeight()

    -- Config access
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local iconTextureSize = 24
    if settingsKey and BoxxyAurasDB and BoxxyAurasDB[settingsKey] and BoxxyAurasDB[settingsKey].iconSize then
         iconTextureSize = BoxxyAurasDB[settingsKey].iconSize
    end

    local iconW = iconTextureSize + (internalPadding * 2)
    local minFrameW_Dynamic = (framePadding * 2) + iconW -- Minimum width for 1 icon

    -- Dragging calculations
    local mouseX, _ = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    
    local potentialW = 0
    local finalX = frame.frameStartX -- Default for right handle drag
    local widthToApply = 0 -- Width that will actually be set
    local draggingHandle = frame.draggingHandle

    if draggingHandle == "Right" then
        local deltaX = mouseX - (frame.dragStartX or 0)
        local deltaW_local = deltaX / scale
        potentialW = frame.frameStartW + deltaW_local
        potentialW = math.max(minFrameW_Dynamic, potentialW)
    elseif draggingHandle == "Left" then
        local deltaX = mouseX - (frame.dragStartX or 0)
        local deltaW_local = deltaX / scale
        potentialW = frame.frameStartW - deltaW_local -- Width if left edge followed mouse
        potentialW = math.max(minFrameW_Dynamic, potentialW)
        -- finalX calculation still happens AFTER snappedW is determined below
    else
        return
    end

    -- Icon fitting calculation (Uses potentialW determined above)
    local minNumIconsWide = 1
    local numIconsCheck = minNumIconsWide
    while true do
        local widthForNextCheck = (framePadding * 2) + ((numIconsCheck + 1) * iconW) + math.max(0, numIconsCheck) * iconSpacing
        if potentialW >= widthForNextCheck then
            numIconsCheck = numIconsCheck + 1
        else
            break
        end
        if numIconsCheck > 100 then break end
    end
    local potentialNumIconsFit = numIconsCheck

    -- Update DB and calculate snapped width
    local currentNumIconsWide = BoxxyAurasDB[settingsKey].numIconsWide or DEFAULT_ICONS_WIDE
    local newNumIconsWide = potentialNumIconsFit -- Use the calculated fit directly
    if newNumIconsWide ~= currentNumIconsWide then
        BoxxyAurasDB[settingsKey].numIconsWide = newNumIconsWide
    end

    local snappedW = BoxxyAuras.FrameHandler.CalculateFrameWidth(newNumIconsWide, iconTextureSize)
    widthToApply = snappedW -- This is the width we will set

    -- Adjust X pos for left drag (using the new snappedW)
    if draggingHandle == "Left" then
        local originalRightEdgeX = frame.frameStartX + frame.frameStartW -- Recalculate for clarity
        finalX = originalRightEdgeX - snappedW -- Position left edge based on fixed right edge and snapped width
    end

    -- Apply frame updates if needed
    local currentW, _ = frame:GetSize()
    local currentX, _ = frame:GetLeft()

    -- Compare against widthToApply and finalX
    local needsFrameUpdate = (widthToApply ~= currentW or finalX ~= currentX)
    if needsFrameUpdate then
        frame:SetSize(widthToApply, fixedFrameH)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", finalX, frame.frameStartY)
        if UpdateEdgeHandleDimensions then UpdateEdgeHandleDimensions(frame, widthToApply, fixedFrameH) end
    end
end

-- Placeholder for attaching OnUpdate script - will be done in InitializeFrames later
--[[
for pointName, _ in pairs(handlePoints) do
    CreateResizeHandlesForFrame(mainFrame, pointName)
end
UpdateEdgeHandleDimensions(mainFrame, mainFrame:GetSize())

buffDisplayFrame:SetScript("OnUpdate", function(self, elapsed) OnDisplayFrameResizeUpdate(self, elapsed) end)
debuffDisplayFrame:SetScript("OnUpdate", function(self, elapsed) OnDisplayFrameResizeUpdate(self, elapsed) end)
customDisplayFrame:SetScript("OnUpdate", function(self, elapsed) OnDisplayFrameResizeUpdate(self, elapsed) end)
]]

