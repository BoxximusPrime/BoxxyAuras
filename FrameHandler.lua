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
                    -- BoxxyAuras.DebugLogWarning("CreateResizeHandlesForFrame OnMouseUp: Could not determine frameType or LayoutAuras not found.")
                end

                frame.draggingHandle = nil
                self.bg:Hide()

                -- Apply changes to DB
                if dbKey and BoxxyAurasDB then
                    local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
                    if currentProfileSettings and currentProfileSettings[dbKey] then
                        local newWidth = frame:GetWidth()
                        local newHeight = frame:GetHeight()
                        local newNumIconsWide = endNumIconsWide

                        currentProfileSettings[dbKey].width = newWidth
                        currentProfileSettings[dbKey].height = newHeight
                        currentProfileSettings[dbKey].numIconsWide = newNumIconsWide
                    end
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

    -- <<< Log values read from profile >>>
    local savedWidth = settings.width
    local savedNumIconsWide = settings.numIconsWide
    -- BoxxyAuras.DebugLog(string.format(
    --     "ApplySettings [%s]: READ Profile '%s' -> W=%s, numIconsWide=%s", 
    --     frameType, 
    --     BoxxyAurasDB and BoxxyAurasDB.activeProfile or "Unknown", 
    --     tostring(savedWidth),
    --     tostring(savedNumIconsWide)
    -- ))
    -- <<< END Log >>>

    -- <<< Step 1: Calculate Target Size >>>
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 12
    local iconTextureSize = settings.iconSize or 24
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6 
    local iconH = iconTextureSize + textHeight + (internalPadding * 2)
    local calculatedMinHeight = framePadding + iconH + framePadding 
    local targetHeight = settings.height or calculatedMinHeight

    local numIconsWideForCalc = settings.numIconsWide or 6 -- Use profile value or default
    numIconsWideForCalc = math.max(1, numIconsWideForCalc) 
    local calculatedWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWideForCalc, iconTextureSize)
    local targetWidth = settings.width or calculatedWidth -- Prioritize saved width
    
    -- <<< Log final targetWidth >>>
    -- BoxxyAuras.DebugLog(string.format("ApplySettings [%s]: Decided targetWidth=%.2f (Saved=%s, Calc=%.2f)", 
    --     frameType, targetWidth, tostring(savedWidth), calculatedWidth)) -- Use tostring for savedWidth
    -- <<< END Log >>>

    -- Ensure targetWidth and targetHeight are numbers before SetSize
    if type(targetWidth) ~= "number" then 
        -- BoxxyAuras.DebugLogWarning(string.format("ApplySettings [%s]: Invalid targetWidth type (%s), using calculated width %.2f", frameType, type(targetWidth), calculatedWidth))
        targetWidth = calculatedWidth
    end
    if type(targetHeight) ~= "number" then
         -- BoxxyAuras.DebugLogWarning(string.format("ApplySettings [%s]: Invalid targetHeight type (%s), using calculated min height %.2f", frameType, type(targetHeight), calculatedMinHeight))
         targetHeight = calculatedMinHeight
    end

    -- <<< Step 4: Clear Anchors >>>
    targetFrame:ClearAllPoints() 
    -- <<< SetUserPlaced moved into the timer >>>

    -- <<< Step 5: Read saved position and anchor >>>
    local savedX = settings.x or 0
    local savedY = settings.y or 0
    local savedAnchor = settings.anchor or "CENTER" -- Default to CENTER if not specified

    local targetScale = currentSettings.optionsScale or 1.0
    -- Rely on upvalues for targetWidth/targetHeight calculated earlier

    -- Ensure frame still exists
    -- NOTE: This is where the frame is actually set to the correct position and size
    if targetFrame and targetFrame:IsVisible() then
        -- <<< TEMPORARILY UNLOCK FRAME FOR POSITIONING >>>
        -- Store the intended lock state *before* unlocking
        local intendedLockState = false -- Default to unlocked
        if BoxxyAurasDB then
            local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
            intendedLockState = currentSettings.lockFrames or false
        end

        -- Temporarily ensure the frame is movable/unlocked for setting position/size
        if targetFrame.isLocked then
            targetFrame:SetMovable(true)
            targetFrame:EnableMouse(true) -- Make sure mouse interaction is enabled if needed for positioning logic (though SetUserPlaced(false) implies programmatic)
        end

        -- <<< Order: UserPlaced -> Point -> Scale -> Size >>>
        targetFrame:SetUserPlaced(false)
        targetFrame:ClearAllPoints()

        -- <<< Set Point based on savedAnchor >>>
        if savedAnchor == "CENTER" then
            -- Use CENTER for default/reset positions
            targetFrame:SetPoint("CENTER", UIParent, "CENTER", savedX, savedY)
        else -- Assume BOTTOMLEFT for user-dragged positions
            targetFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", savedX, savedY)
        end

        -- <<< Set Scale >>>
        targetFrame:SetScale(targetScale)
        targetFrame:SetSize(targetWidth, targetHeight)

        -- <<< RE-APPLY INTENDED LOCK STATE AFTER POSITIONING >>>
        -- Use the stored intended lock state
        BoxxyAuras.FrameHandler.ApplyLockState(intendedLockState)
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
            -- <<< DEBUG: Fallback Creation >>>
            -- print("BoxxyAuras DEBUG: InitializeFrames - Fallback CREATING Buff Frame!")
            -- <<< END DEBUG >>>
            buffDisplayFrame = CreateFrame("Frame", "BoxxyBuffDisplayFrame", UIParent)
            BoxxyAuras.Frames.Buff = buffDisplayFrame
            SetupDisplayFrame(buffDisplayFrame, "BuffFrame") -- Setup visuals ONLY if newly created
            CreateResizeHandlesForFrame(buffDisplayFrame, "BuffFrame") -- Create handles ONLY if newly created
            buffDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate) -- Attach update script ONLY if newly created
            C_Timer.NewTicker(0.1, function() PollFrameHoverState(buffDisplayFrame, "Buff Frame") end) -- Start timer ONLY if newly created
        end
        if not debuffDisplayFrame then
             -- <<< DEBUG: Fallback Creation >>>
             -- print("BoxxyAuras DEBUG: InitializeFrames - Fallback CREATING Debuff Frame!")
             -- <<< END DEBUG >>>
            debuffDisplayFrame = CreateFrame("Frame", "BoxxyDebuffDisplayFrame", UIParent)
            BoxxyAuras.Frames.Debuff = debuffDisplayFrame
            SetupDisplayFrame(debuffDisplayFrame, "DebuffFrame")
            CreateResizeHandlesForFrame(debuffDisplayFrame, "DebuffFrame")
            debuffDisplayFrame:SetScript("OnUpdate", OnDisplayFrameResizeUpdate)
            C_Timer.NewTicker(0.1, function() PollFrameHoverState(debuffDisplayFrame, "Debuff Frame") end)
        end
        if not customDisplayFrame then
             -- <<< DEBUG: Fallback Creation >>>
             -- print("BoxxyAuras DEBUG: InitializeFrames - Fallback CREATING Custom Frame!")
             -- <<< END DEBUG >>>
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

    -- Define defaults (Copied from BoxxyAuras.lua PLAYER_LOGIN)
    local DEFAULT_ICONS_WIDE = 6 -- Define local default
    local defaultPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local defaultIconSize_ForCalc = 24
    local defaultTextHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    local defaultIconH = defaultIconSize_ForCalc + defaultTextHeight + (defaultPadding * 2)
    local defaultFramePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local defaultMinHeight = defaultFramePadding + defaultIconH + defaultFramePadding

    -- Use GetDefaultProfileSettings from BoxxyAuras core file
    local defaultSettings = {}
    if BoxxyAuras.GetDefaultProfileSettings then
        defaultSettings = BoxxyAuras:GetDefaultProfileSettings()
    else
        -- BoxxyAuras.DebugLogError("InitializeFrames Error: BoxxyAuras.GetDefaultProfileSettings not found!")
        -- Use hardcoded local defaults as fallback
        defaultSettings = {
             buffFrameSettings = { x = 0, y = -150, anchor = "TOP", width = 300, height = defaultMinHeight, numIconsWide = DEFAULT_ICONS_WIDE, buffTextAlign = "CENTER", iconSize = 24 },
             debuffFrameSettings = { x = 0, y = -150 - defaultMinHeight - 30, anchor = "TOP", width = 300, height = defaultMinHeight, numIconsWide = DEFAULT_ICONS_WIDE, debuffTextAlign = "CENTER", iconSize = 24 },
             customFrameSettings = { x = 0, y = -150 - defaultMinHeight - 60, anchor = "TOP", width = 300, height = defaultMinHeight, numIconsWide = DEFAULT_ICONS_WIDE, customTextAlign = "CENTER", iconSize = 24 }
        }
    end

    local defaultBuffFrameSettings = defaultSettings.buffFrameSettings or {}
    local defaultDebuffFrameSettings = defaultSettings.debuffFrameSettings or {}
    local defaultCustomFrameSettings = defaultSettings.customFrameSettings or {}

    -- Helper for initializing settings (now local to this function)
    local function InitializeSettings(dbKey, defaults)
        if type(defaults) ~= "table" then
            -- BoxxyAuras.DebugLogError(string.format("InitializeSettings Error: Default settings for %s are not a table!", dbKey))
            if BoxxyAurasDB then BoxxyAurasDB[dbKey] = {} end
            return BoxxyAurasDB and BoxxyAurasDB[dbKey] or {}
        end
        if not BoxxyAurasDB then 
            -- BoxxyAuras.DebugLogError("InitializeSettings Error: BoxxyAurasDB is nil when initializing "..dbKey)
            return CopyTable(defaults)
        end
        if BoxxyAurasDB[dbKey] == nil then
            BoxxyAurasDB[dbKey] = CopyTable(defaults) -- Assumes CopyTable is available globally or in BoxxyAuras
        else
            -- Ensure nested tables exist before attempting to merge
            if type(BoxxyAurasDB[dbKey]) ~= "table" then
                -- BoxxyAuras.DebugLogError(string.format("InitializeSettings Warning: Existing DB entry for %s is not a table! Overwriting with defaults.", dbKey))
                BoxxyAurasDB[dbKey] = CopyTable(defaults)
            else
                for key, defaultValue in pairs(defaults) do
                    if BoxxyAurasDB[dbKey][key] == nil then
                        BoxxyAurasDB[dbKey][key] = defaultValue
                    end
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

    -- Update handle dimensions after initial size is set by ApplySettings
    -- Calls local UpdateEdgeHandleDimensions
    UpdateEdgeHandleDimensions(buffDisplayFrame, buffDisplayFrame:GetWidth(), buffDisplayFrame:GetHeight())
    UpdateEdgeHandleDimensions(debuffDisplayFrame, debuffDisplayFrame:GetWidth(), debuffDisplayFrame:GetHeight())
    UpdateEdgeHandleDimensions(customDisplayFrame, customDisplayFrame:GetWidth(), customDisplayFrame:GetHeight())

    -- Apply initial scale AND lock state
    if BoxxyAurasDB then
        -- Use GetCurrentProfileSettings to ensure we read from the *active* profile
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        local initialLock = currentSettings.lockFrames or false

        -- Apply lock state using the FrameHandler function
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
    --if not IsMouseButtonDown("LeftButton") then return end

    -- Determine settings key
    local settingsKey = nil
    if frame == BoxxyAuras.FrameHandler.GetBuffFrame() then settingsKey = "buffFrameSettings"
    elseif frame == BoxxyAuras.FrameHandler.GetDebuffFrame() then settingsKey = "debuffFrameSettings"
    elseif frame == BoxxyAuras.FrameHandler.GetCustomFrame() then settingsKey = "customFrameSettings"
    else return end

    -- <<< MODIFIED: Get settings from the CURRENT ACTIVE PROFILE >>>
    local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
    if not currentProfileSettings or not currentProfileSettings[settingsKey] then 
        -- print("ResizeUpdate Error: Could not get profile settings for key: " .. tostring(settingsKey))
        return -- Need profile settings to proceed
    end
    local frameSettings = currentProfileSettings[settingsKey]
    -- <<< END MODIFICATION >>>

    local fixedFrameH = frame:GetHeight()

    -- Config access (Use fallbacks if necessary)
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 12
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 0
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    -- <<< MODIFIED: Read iconSize from frameSettings >>>
    local iconTextureSize = frameSettings.iconSize or 24 -- Read from profile settings table
    -- <<< END MODIFICATION >>>

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
        if numIconsCheck > 100 then break end -- Safety break
    end
    local potentialNumIconsFit = numIconsCheck

    -- <<< MODIFIED: Update numIconsWide in the PROFILE settings >>>
    local currentNumIconsWide = frameSettings.numIconsWide or 6 -- Read from profile settings, default 6
    local newNumIconsWide = potentialNumIconsFit -- Use the calculated fit directly
    if newNumIconsWide ~= currentNumIconsWide then
        frameSettings.numIconsWide = newNumIconsWide -- Write back to profile settings table
    end
    -- <<< END MODIFICATION >>>

    -- Use iconTextureSize read from profile settings for width calculation
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
    self.draggingHandle = nil -- Clear resize handle state too, just in case

    local finalX = self:GetLeft()
    local finalY = self:GetBottom() 
    local anchorToSave = "BOTTOMLEFT"

    local settingsKey = nil 
    local frameType = nil   

    local currentBuffFrame = BoxxyAuras.FrameHandler.GetBuffFrame()
    local currentDebuffFrame = BoxxyAuras.FrameHandler.GetDebuffFrame()
    local currentCustomFrame = BoxxyAuras.FrameHandler.GetCustomFrame()

    if self == currentBuffFrame then 
        settingsKey = "buffFrameSettings"
        frameType = "Buff"
    elseif self == currentDebuffFrame then 
        settingsKey = "debuffFrameSettings"
        frameType = "Debuff"
    elseif self == currentCustomFrame then 
        settingsKey = "customFrameSettings"
        frameType = "Custom"
    end

    local currentProfileSettings = BoxxyAuras:GetCurrentProfileSettings()
    if currentProfileSettings and currentProfileSettings[settingsKey] then
        currentProfileSettings[settingsKey].x = finalX 
        currentProfileSettings[settingsKey].y = finalY 
        currentProfileSettings[settingsKey].anchor = anchorToSave
        -- Save height on drag stop? Might be redundant if only width changes
        -- currentProfileSettings[settingsKey].height = self:GetHeight() 
    else
         -- BoxxyAuras.DebugLogWarning(string.format("OnDragStop [%s]: Could not find settings table for key '%s' in active profile.", frameType, settingsKey))
    end

    -- LayoutAuras is forward declared
    if frameType and LayoutAuras then 
        LayoutAuras(frameType) 
    else
        -- BoxxyAuras.DebugLogWarning(string.format("OnDragStop Error: Could not determine frameType (%s) or LayoutAuras missing for frame %s", tostring(frameType), self:GetName()))
    end 
end

