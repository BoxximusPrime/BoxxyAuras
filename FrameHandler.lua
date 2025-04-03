local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}      -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras        -- Create a convenient local alias to the global table
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

-- Forward declarations for drag handlers
local OnFrameDragStart
local OnFrameDragStop

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
                frame.draggingHandle = pointName
                frame.dragStartX, frame.dragStartY = GetCursorPosition() -- Raw mouse coords
                frame.frameStartW, frame.frameStartH = frame:GetSize()
                frame.frameStartX = frame:GetLeft()     -- Starting Left X
                frame.frameStartY = frame:GetBottom()   -- Store Starting Bottom Y
                self.bg:Show()
                
                if pointName == "Left" then
                    -- Store original right edge for left drag calculations
                    frame.dragOriginalRightX = frame.frameStartX + frame.frameStartW
                end
            end
        end)
        handle:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and frame.draggingHandle == self.pointName then
                local dbKey = nil
                local frameType = nil
                local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
                local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
                local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()
                
                if frame == currentBuffFrame then 
                    dbKey = "buffFrameSettings"; frameType = "Buff"
                elseif frame == currentDebuffFrame then 
                    dbKey = "debuffFrameSettings"; frameType = "Debuff"
                elseif frame == currentCustomFrame then 
                    dbKey = "customFrameSettings"; frameType = "Custom"
                end
                
                local originalRightEdgeX = frame.dragOriginalRightX -- Get stored value
                local originalBottomY = frame.frameStartY -- Get stored Bottom Y
                local isLeftHandle = (frame.draggingHandle == "Left")

                frame.draggingHandle = nil
                self.bg:Hide()

                if frameType then
                    local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
                    if currentProfileSettings and currentProfileSettings[dbKey] then
                        local frameSettings = currentProfileSettings[dbKey]
                        local finalNumIconsWide = frameSettings.numIconsWide
                        local iconSize = frameSettings.iconSize or 24

                        if isLeftHandle and originalRightEdgeX then
                            -- Calculate and SAVE the correct final X and Y for left handle
                            local finalWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(finalNumIconsWide, iconSize)
                            local finalX = originalRightEdgeX - finalWidth
                            frameSettings.x = finalX -- Update saved X coordinate
                            frameSettings.y = originalBottomY -- Update saved Y coordinate (Bottom)
                        end
                        -- For right handle, the original saved X/Y (frameStartX/Y) are already correct for BOTTOMLEFT anchor

                        BoxxyAuras.FrameHandler.ApplySettings(frameType)
                        LayoutAuras(frameType)
                        BoxxyAuras.FrameHandler.UpdateEdgeHandleDimensions(frame, frame:GetWidth(), frame:GetHeight())
                    end
                else
                    -- BoxxyAuras.DebugLogWarning("CreateResizeHandlesForFrame OnMouseUp: Could not determine frameType.")
                end
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
BoxxyAuras.FrameHandler.UpdateEdgeHandleDimensions = UpdateEdgeHandleDimensions -- Assign to handler table

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
        -- BoxxyAuras.DebugLogError(string.format("LayoutAuras Error: Invalid frameType '%s' received.", tostring(frameType)))
        return
    end

    -- Check if frame or list is missing after lookup
    if not targetFrame then
        -- BoxxyAuras.DebugLogError(string.format("LayoutAuras Error: Could not find targetFrame for frameType '%s'.", frameType))
        return
    end
    if not iconList then
        -- BoxxyAuras.DebugLogError(string.format("LayoutAuras Error: Could not find iconList for frameType '%s'.", frameType))
        return -- Don't check #iconList here, allow empty list processing for height adjustment
    end

    -- <<< DEBUG: Log Y position BEFORE layout >>>
    local yBefore = targetFrame:GetTop()
    -- BoxxyAuras.DebugLog(string.format("LayoutAuras [%s]: Y position BEFORE layout = %.2f", frameType, yBefore))
    -- <<< END DEBUG >>>

    local alignment = "LEFT"
    local numIconsWide = 6

    -- Read settings if key is valid
    local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
    local frameSettings = currentProfileSettings and currentProfileSettings[settingsKey]

    if frameSettings then
        alignment = frameSettings[frameType:lower().."TextAlign"] or alignment -- e.g., buffTextAlign
        numIconsWide = frameSettings.numIconsWide or numIconsWide
    else
        -- BoxxyAuras.DebugLogWarning(string.format("LayoutAuras [%s]: Could not find frameSettings for key '%s' in current profile.", frameType, settingsKey))
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
    if frameSettings and frameSettings.iconSize then
        currentIconSize = frameSettings.iconSize
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
    
    -- BoxxyAuras.DebugLog(string.format("LayoutAuras [%s]: Calculated TargetHeight = %.2f", frameType, targetHeight)) -- Log calculated height

    local frameH = targetFrame:GetHeight()
    if frameH ~= targetHeight then
        -- BoxxyAuras.DebugLog(string.format("LayoutAuras [%s]: Current Height (%.2f) != Target Height (%.2f). Calling SetHeight.", frameType, frameH, targetHeight)) -- Log height change
        targetFrame:SetHeight(targetHeight)
        local currentWidthForHandleUpdate = targetFrame:GetWidth()
        if UpdateEdgeHandleDimensions then UpdateEdgeHandleDimensions(targetFrame, currentWidthForHandleUpdate, targetHeight) end
        frameH = targetHeight
    end

    -- <<< DEBUG: Log Y position AFTER SetHeight >>>
    local yAfterHeightSet = targetFrame:GetTop()
    --  BoxxyAuras.DebugLog(string.format("LayoutAuras [%s]: Y position AFTER SetHeight = %.2f", frameType, yAfterHeightSet))
     -- <<< END DEBUG >>>

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

    -- <<< DEBUG: Log Y position AFTER icon layout >>>
     local yAfterLayout = targetFrame:GetTop()
    --  BoxxyAuras.DebugLog(string.format("LayoutAuras [%s]: Y position AFTER icon layout = %.2f", frameType, yAfterLayout))
     -- <<< END DEBUG >>>

    -- <<< Log numIconsWide and Frame Width Before Layout >>>
    local widthBeforeLayout = targetFrame:GetWidth()
    -- BoxxyAuras.DebugLog(string.format(
    --     "LayoutAuras [%s]: Using numIconsWide=%d | FrameWidth Before Layout=%.2f",
    --     frameType, numIconsWide, widthBeforeLayout
    -- ))
    -- <<< END Log >>>
end
BoxxyAuras.FrameHandler.LayoutAuras = LayoutAuras -- Assign to handler table if needed externally

-- Moved function: Poll Frame Hover State
local function PollFrameHoverState(frame, frameDesc)
    if not frame then
        -- BoxxyAuras.DebugLogWarning("PollFrameHoverState - frame is nil") -- Already logged elsewhere if creation failed
        return
    end 
    
    -- <<< REMOVED DEBUG >>>
    -- local pollBackdropExists = frame.backdropTextures ~= nil
    -- local pollBorderExists = frame.borderTextures ~= nil
    -- if not pollBackdropExists or not pollBorderExists then
    --      BoxxyAuras.DebugLog(string.format("PollFrameHoverState [%s]: Texture check at POLL START. Backdrop: %s, Border: %s",
    --         frame:GetName() or frameDesc or "Unknown",
    --         tostring(pollBackdropExists),
    --         tostring(pollBorderExists)
    --      ))
    -- end
    -- <<< END REMOVED DEBUG >>>
    
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
        
        -- <<< MODIFIED: Check texture tables AGAIN right before use >>>
        local hasBackdrop = frame and frame.backdropTextures
        local hasBorder = frame and frame.borderTextures

        -- Removed old logging check that was here
        -- if not hasBackdrop and not frame.textureSetupComplete then 
        --     BoxxyAuras.DebugLogError(string.format("Poll Error [V2]: backdropTextures NOT FOUND for %s! Frame Type: %s", frameDesc or "UnknownFrame", type(frame)))
        -- end
        -- if not hasBorder and not frame.textureSetupComplete then 
        --      BoxxyAuras.DebugLogError(string.format("Poll Error [V2]: borderTextures NOT FOUND for %s! Frame Type: %s", frameDesc or "UnknownFrame", type(frame)))
        -- end
        if not hasBackdrop then
            -- BoxxyAuras.DebugLogError(string.format("Poll Error [V2]: backdropTextures NOT FOUND for %s! Frame Type: %s", frameDesc or "UnknownFrame", type(frame)))
        end
        if not hasBorder then
             -- BoxxyAuras.DebugLogError(string.format("Poll Error [V2]: borderTextures NOT FOUND for %s! Frame Type: %s", frameDesc or "UnknownFrame", type(frame)))
        end
        -- <<< END MODIFIED CHECK >>>

        -- Only proceed if BOTH exist
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
        -- BoxxyAuras.DebugLogError(string.format("Failed to create TitleLabel for Frame='%s', Name='%s'", frame:GetName() or "N/A", tostring(frameName)))
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    -- Use the named functions now
    frame:SetScript("OnDragStart", OnFrameDragStart) 
    frame:SetScript("OnDragStop", OnFrameDragStop)  

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
        -- BoxxyAuras.DebugLogError(string.format("ApplySettings Error: Invalid frameType '%s' received.", tostring(frameType)))
        return
    end

    if not targetFrame then
        -- BoxxyAuras.DebugLogError(string.format("ApplySettings Error: Target frame not found for type '%s'.", frameType))
        return
    end

    -- <<< Use GetCurrentProfileSettings helper for safety and consistency >>>
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings() -- From BoxxyAuras.lua
    if not currentSettings then
        -- BoxxyAuras.DebugLogError(string.format("ApplySettings Error: Could not get current profile settings!"))
        return
    end
    local settings = currentSettings[settingsKey] -- e.g., currentSettings.buffFrameSettings
    -- <<< END Use GetCurrentProfileSettings >>>

    if not settings then
        -- BoxxyAuras.DebugLogError(string.format("ApplySettings Error: Settings table missing for key '%s' in current profile.", settingsKey))
        return -- Need settings to proceed
    end

    -- <<< Read target scale >>>
    local targetScale = currentSettings.optionsScale or 1.0

    -- <<< Log values read from profile (numIconsWide is key now) >>>
    local savedNumIconsWide = settings.numIconsWide
    local savedIconSize = settings.iconSize
    -- BoxxyAuras.DebugLog(string.format(
    --     "ApplySettings [%s]: READ Profile '%s' -> numIconsWide=%s, iconSize=%s",
    --     frameType,
    --     BoxxyAurasDB and BoxxyAurasDB.activeProfile or "Unknown",
    --     tostring(savedNumIconsWide),
    --     tostring(savedIconSize)
    -- ))
    -- <<< END Log >>>

    -- <<< Step 1: Calculate Target Size BASED ON SETTINGS >>>
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 12
    local iconTextureSize = settings.iconSize or 24 -- Read from settings
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local iconH = iconTextureSize + textHeight + (internalPadding * 2)
    local calculatedMinHeight = framePadding + iconH + framePadding -- Minimum height for one row

    local numIconsWideForCalc = settings.numIconsWide or 6 -- Use profile value or default
    numIconsWideForCalc = math.max(1, numIconsWideForCalc)
    -- <<< ALWAYS calculate width now >>>
    local targetWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWideForCalc, iconTextureSize)

    -- <<< Log final targetWidth >>>
    -- BoxxyAuras.DebugLog(string.format("ApplySettings [%s]: Calculated targetWidth=%.2f based on numIcons=%d, iconSize=%d",
    --     frameType, targetWidth, numIconsWideForCalc, iconTextureSize))
    -- <<< END Log >>>

    -- Ensure targetWidth is a number before SetSize
    if type(targetWidth) ~= "number" then
        -- BoxxyAuras.DebugLogWarning(string.format("ApplySettings [%s]: Invalid calculated targetWidth type (%s), using fallback 100", frameType, type(targetWidth)))
        targetWidth = 100 -- Fallback width
    end
    -- Height will be adjusted by LayoutAuras, use calculatedMinHeight for SetSize
    local targetHeight = calculatedMinHeight


    -- <<< Step 4: Clear Anchors >>> -- MOVED BEFORE POSITIONING LOGIC
    targetFrame:ClearAllPoints()
    -- SetUserPlaced is handled within the positioning block now

    -- <<< Step 5: Read saved position and anchor >>>
    local savedX = settings.x or 0
    local savedY = settings.y or 0
    local savedAnchor = settings.anchor or "BOTTOMLEFT" -- <<< Default anchor is BOTTOMLEFT >>>

    -- <<< Get Scale to adjust coordinates >>>
    local targetScale = currentSettings.optionsScale or 1.0
    -- <<< Adjust saved coordinates by scale >>>
    local adjustedX = savedX
    local adjustedY = savedY

    -- Ensure frame still exists
    -- NOTE: This is where the frame is actually set to the correct position and size
    if targetFrame then -- Removed IsVisible check, apply even if hidden? Or keep it? Let's keep it for now.
        -- <<< TEMPORARILY UNLOCK FRAME FOR POSITIONING >>>
        -- Store the intended lock state *before* unlocking
        local intendedLockState = false -- Default to unlocked
        if BoxxyAurasDB then
            local currentProfileSettingsCheck = BoxxyAuras:GetCurrentProfileSettings() -- Re-get just in case
            if currentProfileSettingsCheck then intendedLockState = currentProfileSettingsCheck.lockFrames or false end
        end

        -- Temporarily ensure the frame is movable/unlocked for setting position/size
        local wasLocked = targetFrame.isLocked
        if wasLocked then
            targetFrame:SetMovable(true)
            targetFrame:EnableMouse(true)
        end

        -- <<< Order: Scale -> Size -> UserPlaced -> Point >>>
        targetFrame:SetScale(targetScale)
        targetFrame:SetSize(targetWidth, targetHeight)
        targetFrame:SetUserPlaced(false) -- Indicate programmatic positioning
        targetFrame:ClearAllPoints() -- Clear again just to be safe

        -- <<< Set Point based on savedAnchor using ADJUSTED coordinates >>>
        if savedAnchor == "CENTER" then
            targetFrame:SetPoint("CENTER", UIParent, "CENTER", adjustedX, adjustedY)
        else -- Assume BOTTOMLEFT for user-dragged positions and default
            targetFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", adjustedX, adjustedY)
        end

        -- <<< RE-APPLY INTENDED LOCK STATE AFTER POSITIONING >>>
        -- Use the stored intended lock state (or re-apply if it wasn't locked)
        targetFrame:SetMovable(not intendedLockState)
        targetFrame:EnableMouse(not intendedLockState)
        -- The full ApplyLockState might handle visuals better if needed later
        -- BoxxyAuras.FrameHandler.ApplyLockState(intendedLockState) -- Maybe too heavy here? Let's try direct set first.
        -- If direct set causes issues with handles/visuals, revert to calling ApplyLockState(intendedLockState)
        if targetFrame.titleLabel then targetFrame.titleLabel:EnableMouse(not intendedLockState) end -- Update title label mouse state too
        if targetFrame.handles then -- Update handle mouse state
            for _, handle in pairs(targetFrame.handles) do handle:EnableMouse(not intendedLockState) end
        end
        targetFrame.isLocked = intendedLockState -- Make sure internal state matches


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
        return
    end

    if targetFrame and iconList and LayoutAuras then -- Calls local LayoutAuras
        LayoutAuras(frameType)
    end
end

-- *** NEW Function to Apply Lock State ***
function BoxxyAuras.FrameHandler.ApplyLockState(isLocked)
    local framesToUpdate = { BoxxyAuras.Frames.Buff, BoxxyAuras.Frames.Debuff, BoxxyAuras.Frames.Custom }

    for _, frame in ipairs(framesToUpdate) do
        if frame then
            frame.isLocked = isLocked
            frame:SetMovable(not isLocked)
            frame:EnableMouse(not isLocked) -- Primary control

            -- Handles
            if frame.handles then
                for handleName, handle in pairs(frame.handles) do
                    handle:EnableMouse(not isLocked) 
                    if isLocked then
                        handle:Hide()
                    else
                        handle:Show()
                    end
                end
            end

            -- Title Label
            if frame.titleLabel then
                frame.titleLabel:EnableMouse(not isLocked)
                if isLocked then
                    frame.titleLabel:Hide()
                else
                    frame.titleLabel:Show()
                end
            end

            -- Control Background/Border Visibility via Alpha & Show/Hide
            local backdropGroupName = "backdrop"
            local borderGroupName = "border"
            local r_bg, g_bg, b_bg, a_bg = 0, 0, 0, 0
            local r_br, g_br, b_br, a_br = 0, 0, 0, 0

            if not isLocked then
                -- Use normal colors when unlocked
                local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
                local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
                r_bg, g_bg, b_bg, a_bg = cfgBGN.r, cfgBGN.g, cfgBGN.b, cfgBGN.a
                r_br, g_br, b_br, a_br = cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a
                
                -- <<< Explicitly Show Textures >>>
                if frame.backdropTextures then
                    for _, texture in pairs(frame.backdropTextures) do if texture then texture:Show() end end
                end
                 if frame.borderTextures then
                    for _, texture in pairs(frame.borderTextures) do if texture then texture:Show() end end
                end
            else
                -- Alpha set to 0 when locked
                a_bg = 0
                a_br = 0
                -- Colors don't matter, but set defaults
                local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
                local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
                r_bg, g_bg, b_bg = cfgBGN.r, cfgBGN.g, cfgBGN.b
                r_br, g_br, b_br = cfgBorder.r, cfgBorder.g, cfgBorder.b

                -- <<< Textures are hidden implicitly by alpha=0, no need to call Hide() >>>
            end

            -- Apply colors/alpha (Assumes textures exist)
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
    -- <<< MODIFIED: Get existing frames from the main addon table >>>
    buffDisplayFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Buff
    debuffDisplayFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Debuff
    customDisplayFrame = BoxxyAuras.Frames and BoxxyAuras.Frames.Custom

    -- <<< ADDED: Safety Check & Fallback Creation >>>
    if not buffDisplayFrame or not debuffDisplayFrame or not customDisplayFrame then
        -- BoxxyAuras.DebugLogError("InitializeFrames Warning: One or more main display frames not found in BoxxyAuras.Frames! Attempting fallback creation. Check load order.")
        -- Attempt to create them *now* as a fallback, but this indicates an earlier load order issue.
        if not buffDisplayFrame then
            buffDisplayFrame = CreateFrame("Frame", "BoxxyBuffDisplayFrame", UIParent)
            BoxxyAuras.Frames.Buff = buffDisplayFrame
            SetupDisplayFrame(buffDisplayFrame, "BuffFrame")
            CreateResizeHandlesForFrame(buffDisplayFrame, "BuffFrame")
            buffDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate)
            C_Timer.NewTicker(0.1, function() PollFrameHoverState(buffDisplayFrame, "Buff Frame") end)
        end
        if not debuffDisplayFrame then
            debuffDisplayFrame = CreateFrame("Frame", "BoxxyDebuffDisplayFrame", UIParent)
            BoxxyAuras.Frames.Debuff = debuffDisplayFrame
            SetupDisplayFrame(debuffDisplayFrame, "DebuffFrame")
            CreateResizeHandlesForFrame(debuffDisplayFrame, "DebuffFrame")
            debuffDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate)
            C_Timer.NewTicker(0.1, function() PollFrameHoverState(debuffDisplayFrame, "Debuff Frame") end)
        end
        if not customDisplayFrame then
            customDisplayFrame = CreateFrame("Frame", "BoxxyCustomDisplayFrame", UIParent)
            BoxxyAuras.Frames.Custom = customDisplayFrame
            SetupDisplayFrame(customDisplayFrame, "CustomFrame")
            CreateResizeHandlesForFrame(customDisplayFrame, "CustomFrame")
            customDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate)
            C_Timer.NewTicker(0.1, function() PollFrameHoverState(customDisplayFrame, "Custom Frame") end)
        end
    end
    -- <<< END MODIFICATION & SAFETY CHECK >>>

    -- Ensure DB is initialized (Assume BoxxyAuras main file ensures this)
    if BoxxyAurasDB == nil then
        -- BoxxyAuras.DebugLogError("InitializeFrames: BoxxyAurasDB is nil!")
        BoxxyAurasDB = {} -- Initialize locally? Risky.
    end

    -- Define defaults (No longer includes width/height, uses numIconsWide)
    local DEFAULT_ICONS_WIDE = 6
    local DEFAULT_ICON_SIZE = 24

    -- Use GetDefaultProfileSettings from BoxxyAuras core file
    local defaultSettings = {}
    if BoxxyAuras.GetDefaultProfileSettings then
        defaultSettings = BoxxyAuras:GetDefaultProfileSettings()
        -- Ensure defaults have the core keys we need now
        if not defaultSettings.buffFrameSettings then defaultSettings.buffFrameSettings = {} end
        if not defaultSettings.debuffFrameSettings then defaultSettings.debuffFrameSettings = {} end
        if not defaultSettings.customFrameSettings then defaultSettings.customFrameSettings = {} end
        defaultSettings.buffFrameSettings.numIconsWide = defaultSettings.buffFrameSettings.numIconsWide or DEFAULT_ICONS_WIDE
        defaultSettings.buffFrameSettings.iconSize = defaultSettings.buffFrameSettings.iconSize or DEFAULT_ICON_SIZE
        defaultSettings.debuffFrameSettings.numIconsWide = defaultSettings.debuffFrameSettings.numIconsWide or DEFAULT_ICONS_WIDE
        defaultSettings.debuffFrameSettings.iconSize = defaultSettings.debuffFrameSettings.iconSize or DEFAULT_ICON_SIZE
        defaultSettings.customFrameSettings.numIconsWide = defaultSettings.customFrameSettings.numIconsWide or DEFAULT_ICONS_WIDE
        defaultSettings.customFrameSettings.iconSize = defaultSettings.customFrameSettings.iconSize or DEFAULT_ICON_SIZE
    else
        -- BoxxyAuras.DebugLogError("InitializeFrames Error: BoxxyAuras.GetDefaultProfileSettings not found!")
        -- Use hardcoded local defaults as fallback
        defaultSettings = {
             buffFrameSettings = { x = 0, y = -150, anchor = "TOP", numIconsWide = DEFAULT_ICONS_WIDE, buffTextAlign = "CENTER", iconSize = DEFAULT_ICON_SIZE },
             debuffFrameSettings = { x = 0, y = -200, anchor = "TOP", numIconsWide = DEFAULT_ICONS_WIDE, debuffTextAlign = "CENTER", iconSize = DEFAULT_ICON_SIZE },
             customFrameSettings = { x = 0, y = -250, anchor = "TOP", numIconsWide = DEFAULT_ICONS_WIDE, customTextAlign = "CENTER", iconSize = DEFAULT_ICON_SIZE }
        }
    end

    local defaultBuffFrameSettings = defaultSettings.buffFrameSettings or {}
    local defaultDebuffFrameSettings = defaultSettings.debuffFrameSettings or {}
    local defaultCustomFrameSettings = defaultSettings.customFrameSettings or {}

    -- Helper for initializing settings (Checks for numIconsWide/iconSize)
    local function InitializeSettings(settingsKey, defaults)
        local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
        if not currentProfileSettings then
            -- BoxxyAuras.DebugLogError("InitializeSettings Error: Could not get current profile settings for " .. settingsKey)
            return CopyTable(defaults) -- Return a copy of defaults if profile is missing
        end

        if type(currentProfileSettings[settingsKey]) ~= "table" then
            -- BoxxyAuras.DebugLogWarning(string.format("InitializeSettings Warning: Existing settings for %s is not a table! Using defaults.", settingsKey))
            currentProfileSettings[settingsKey] = CopyTable(defaults)
        else
            -- Ensure core keys exist
            if currentProfileSettings[settingsKey].numIconsWide == nil then
                 currentProfileSettings[settingsKey].numIconsWide = defaults.numIconsWide or DEFAULT_ICONS_WIDE
            end
            if currentProfileSettings[settingsKey].iconSize == nil then
                 currentProfileSettings[settingsKey].iconSize = defaults.iconSize or DEFAULT_ICON_SIZE
            end
            -- Merge other defaults if missing
            for key, defaultValue in pairs(defaults) do
                if currentProfileSettings[settingsKey][key] == nil then
                    currentProfileSettings[settingsKey][key] = defaultValue
                end
            end
        end
        return currentProfileSettings[settingsKey]
    end


    local buffSettings = InitializeSettings("buffFrameSettings", defaultBuffFrameSettings)
    local debuffSettings = InitializeSettings("debuffFrameSettings", defaultDebuffFrameSettings)
    local customSettings = InitializeSettings("customFrameSettings", defaultCustomFrameSettings)

    -- Apply Settings (Will calculate initial width based on saved/default numIconsWide & iconSize)
    ApplySettings("Buff")
    ApplySettings("Debuff")
    ApplySettings("Custom")

    -- Initial Layout (To set correct height based on content/rows)
    LayoutAuras("Buff")
    LayoutAuras("Debuff")
    LayoutAuras("Custom")

    -- Update handle dimensions AFTER initial size and layout are done
    UpdateEdgeHandleDimensions(buffDisplayFrame, buffDisplayFrame:GetWidth(), buffDisplayFrame:GetHeight())
    UpdateEdgeHandleDimensions(debuffDisplayFrame, debuffDisplayFrame:GetWidth(), debuffDisplayFrame:GetHeight())
    UpdateEdgeHandleDimensions(customDisplayFrame, customDisplayFrame:GetWidth(), customDisplayFrame:GetHeight())

    -- Apply initial scale AND lock state
    if BoxxyAurasDB then
        local finalCurrentSettings = BoxxyAuras:GetCurrentProfileSettings() -- Read one last time
        local initialLock = false
        if finalCurrentSettings then initialLock = finalCurrentSettings.lockFrames or false end

        -- Apply lock state using the FrameHandler function (Handles visuals)
        BoxxyAuras.FrameHandler.ApplyLockState(initialLock)
    end
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

    -- Determine settings key
    local settingsKey = nil
    if frame == BoxxyAuras.FrameHandler.GetBuffFrame() then settingsKey = "buffFrameSettings"
    elseif frame == BoxxyAuras.FrameHandler.GetDebuffFrame() then settingsKey = "debuffFrameSettings"
    elseif frame == BoxxyAuras.FrameHandler.GetCustomFrame() then settingsKey = "customFrameSettings"
    else return end

    local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
    if not currentProfileSettings or not currentProfileSettings[settingsKey] then
        return
    end
    local frameSettings = currentProfileSettings[settingsKey]

    -- Config access
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 12
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 0
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local iconTextureSize = frameSettings.iconSize or 24

    local iconW = iconTextureSize + (internalPadding * 2)
    local minFrameW_Dynamic = (framePadding * 2) + iconW

    local mouseX, _ = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local draggingHandle = frame.draggingHandle
    local potentialW = 0

    if draggingHandle == "Right" then
        local deltaX = mouseX - (frame.dragStartX or 0)
        local deltaW_local = deltaX / scale
        potentialW = frame.frameStartW + deltaW_local
        potentialW = math.max(minFrameW_Dynamic, potentialW)

    elseif draggingHandle == "Left" then
        local originalRightEdgeX = frame.dragOriginalRightX
        if not originalRightEdgeX then return end -- Safety
        
        -- Calculate potential new left edge based on mouse X relative to screen left
        -- Need current mouse X relative to original mouse down X
        local deltaX = mouseX - (frame.dragStartX or 0)
        local currentLeftX = frame.frameStartX + (deltaX / scale) -- Predicted new left edge
        
        potentialW = originalRightEdgeX - currentLeftX
        potentialW = math.max(minFrameW_Dynamic, potentialW)
    else
        return
    end

    -- Icon fitting calculation (potentialNumIconsFit)
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

    -- Update numIconsWide in settings if changed
    local currentNumIconsWide = frameSettings.numIconsWide or 6
    local newNumIconsWide = potentialNumIconsFit
    local numIconsChanged = false
    if newNumIconsWide ~= currentNumIconsWide then
        frameSettings.numIconsWide = newNumIconsWide
        numIconsChanged = true
    end

    -- <<< Visual Update Logic >>>
    local calculatedWidthForVisual = BoxxyAuras.FrameHandler.CalculateFrameWidth(newNumIconsWide, iconTextureSize)
    local currentW = frame:GetWidth()
    local widthChanged = (calculatedWidthForVisual ~= currentW)

    if draggingHandle == "Right" and (numIconsChanged or widthChanged) then 
        -- Right Handle: Update size visually
        frame:SetSize(calculatedWidthForVisual, frame:GetHeight())
        if BoxxyAuras.FrameHandler.UpdateEdgeHandleDimensions then 
            BoxxyAuras.FrameHandler.UpdateEdgeHandleDimensions(frame, calculatedWidthForVisual, frame:GetHeight()) -- Use table reference
        end
        -- <<< Trigger layout if VISUAL width changed >>>
        if widthChanged then 
            local frameType = BoxxyAuras.FrameHandler.GetFrameType(frame) -- Use table reference
            if frameType then LayoutAuras(frameType) end
        end

    elseif draggingHandle == "Left" and (numIconsChanged or widthChanged) then
        -- Left Handle: Update size AND position visually using BOTTOMLEFT anchor
        local originalRightEdgeX = frame.dragOriginalRightX
        local startBottomY = frame.frameStartY -- <<< Use the stored Bottom Y from OnMouseDown >>>
        if not originalRightEdgeX or not startBottomY then return end -- Safety check

        local visualX = originalRightEdgeX - calculatedWidthForVisual
        local currentX = frame:GetLeft()

        if calculatedWidthForVisual ~= currentW or visualX ~= currentX then
            frame:SetSize(calculatedWidthForVisual, frame:GetHeight())
            frame:ClearAllPoints()
            -- <<< Use BOTTOMLEFT anchor with original starting Bottom Y >>>
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", visualX, startBottomY)
            if BoxxyAuras.FrameHandler.UpdateEdgeHandleDimensions then 
                BoxxyAuras.FrameHandler.UpdateEdgeHandleDimensions(frame, calculatedWidthForVisual, frame:GetHeight()) 
            end
            if calculatedWidthForVisual ~= currentW or visualX ~= currentX then
                local frameType = BoxxyAuras.FrameHandler.GetFrameType(frame) 
                if frameType then LayoutAuras(frameType) end
            end
        end
    end

end

-- <<< Helper Function to get frame type string >>>
local function GetFrameType(frameObj)
    if not frameObj then return nil end
    if frameObj == BoxxyAuras.FrameHandler.GetBuffFrame() then return "Buff"
    elseif frameObj == BoxxyAuras.FrameHandler.GetDebuffFrame() then return "Debuff"
    elseif frameObj == BoxxyAuras.FrameHandler.GetCustomFrame() then return "Custom"
    else return nil end
end
BoxxyAuras.FrameHandler.GetFrameType = GetFrameType -- Assign to handler table

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

-- <<< ADDED: Assign local functions needed externally >>>
BoxxyAuras.FrameHandler.SetupDisplayFrame = SetupDisplayFrame
BoxxyAuras.FrameHandler.CreateResizeHandlesForFrame = CreateResizeHandlesForFrame
BoxxyAuras.FrameHandler.OnDisplayFrameResizeUpdate = OnDisplayFrameResizeUpdate -- Assign the global function by its name
-- <<< END ADDED ASSIGNMENTS >>>

-- Helper Function: Calculate Frame Width based on icons
local function CalculateFrameWidth(numIconsWide, iconSize)
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local iconW = iconSize + (internalPadding * 2)
    local width = framePadding + (numIconsWide * iconW) + math.max(0, numIconsWide - 1) * iconSpacing + framePadding
    return width
end
BoxxyAuras.FrameHandler.CalculateFrameWidth = CalculateFrameWidth

-- <<< NEW Helper Function: Calculate Icons Wide from Frame Width >>>
local function CalculateIconsWideFromWidth(frameWidth, iconSize)
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local iconW = iconSize + (internalPadding * 2)

    local usableWidth = frameWidth - (framePadding * 2)
    if usableWidth <= 0 then return 1 end -- Avoid division by zero or negative counts

    -- Calculate how many icons fit (ignoring spacing first for simplicity)
    local baseIconCount = math.floor(usableWidth / iconW)
    if baseIconCount <= 0 then return 1 end

    -- Now account for spacing
    local widthWithSpacing = (baseIconCount * iconW) + math.max(0, baseIconCount - 1) * iconSpacing
    -- If the calculated width WITH spacing exceeds usable width, we need one less icon
    if widthWithSpacing > usableWidth and baseIconCount > 1 then
        baseIconCount = baseIconCount - 1
    end

    return math.max(1, baseIconCount) -- Ensure at least 1
end
BoxxyAuras.FrameHandler.CalculateIconsWideFromWidth = CalculateIconsWideFromWidth

-- Moved Drag Handler: OnFrameDragStart
OnFrameDragStart = function(self)
    if not self.isLocked then 
        -- <<< REMOVED Explicit anchor setting before dragging >>>
        self:StartMoving() 
    end
end

-- Moved Drag Handler: OnFrameDragStop
OnFrameDragStop = function(self)
    if not self then
        -- BoxxyAuras.DebugLogError("self is nil in OnDragStop!")
        return
    end

    if type(self.StopMovingOrSizing) == "function" then self:StopMovingOrSizing() end
    self.draggingHandle = nil -- Clear resize handle state

    -- <<< Save BOTTOMLEFT coordinates >>>
    local finalX = self:GetLeft()
    local finalY = self:GetBottom() 
    local anchorToSave = "BOTTOMLEFT"

    local settingsKey = nil
    local frameType = nil

    local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
    local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
    local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()

    if self == currentBuffFrame then settingsKey = "buffFrameSettings"; frameType = "Buff"
    elseif self == currentDebuffFrame then settingsKey = "debuffFrameSettings"; frameType = "Debuff"
    elseif self == currentCustomFrame then settingsKey = "customFrameSettings"; frameType = "Custom"
    end

    local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
    if currentProfileSettings and currentProfileSettings[settingsKey] then
        currentProfileSettings[settingsKey].x = finalX
        currentProfileSettings[settingsKey].y = finalY
        currentProfileSettings[settingsKey].anchor = anchorToSave
    else
         -- BoxxyAuras.DebugLogWarning(string.format("OnDragStop [%s]: Could not find settings table for key '%s' in active profile.", frameType, settingsKey))
    end

    -- Apply Settings ensures final state is correct
    if frameType then
        BoxxyAuras.FrameHandler.ApplySettings(frameType)
    end
end

