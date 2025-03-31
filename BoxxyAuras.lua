local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras.AllAuras = {} -- Global cache for aura info
BoxxyAuras.updateScheduled = false -- Flag to debounce UNIT_AURA updates

-- Configuration Table
BoxxyAuras.Config = {
    BackgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }, -- Icon Background
    BorderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },      -- Icon Border
    MainFrameBGColorNormal = { r = 0.7, g = 0.7, b = 0.7, a = 0.2 }, -- Main frame normal BG
    MainFrameBGColorHover = { r = 0.7, g = 0.7, b = 0.7, a = 0.6 }, -- Main frame hover BG
    TextHeight = 8,
    Padding = 6,           -- Internal padding within AuraIcon frame
    FramePadding = 12,      -- Padding between frame edge and icons
    IconSpacing = 0,       -- Spacing between icons
}

-- Function to check if mouse cursor is within a frame's bounds
function BoxxyAuras.IsMouseWithinFrame(frame)
    if not frame or not frame:IsVisible() then return false end
    local mouseX, mouseY = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local left, bottom, width, height = frame:GetBoundsRect()

    if not left then return false end -- Frame might not be fully positioned yet

    mouseX = mouseX / scale
    mouseY = mouseY / scale

    return mouseX >= left and mouseX <= left + width and mouseY >= bottom and mouseY <= bottom + height
end

-- Create the main addon frame
local mainFrame = CreateFrame("Frame", "BoxxyAurasMainFrame", UIParent) -- No template needed now
local defaultMainFrameSettings = { -- Define defaults
    x = 0,
    y = 150,
    anchor = "CENTER",
    width = 300,
    height = 100
}

-- Create INDEPENDENT display frames parented to UIParent
local buffDisplayFrame = CreateFrame("Frame", "BoxxyBuffDisplayFrame", UIParent) -- Parent to UIParent, unique name
local debuffDisplayFrame = CreateFrame("Frame", "BoxxyDebuffDisplayFrame", UIParent) -- Parent to UIParent, unique name

-- Attach icon lists to the main addon table
BoxxyAuras.buffIcons = {}
BoxxyAuras.debuffIcons = {}

local iconSpacing = 4 -- Keep local if only used here?

-- New Cache Tables
local trackedBuffs = {}
local trackedDebuffs = {}

-- New sorting function
local function SortAurasForDisplay(a, b)
    local aIsPermanent = (a.duration or 0) == 0 or a.duration == -1 -- Check 0 or -1 for permanent
    local bIsPermanent = (b.duration or 0) == 0 or b.duration == -1

    -- Rule 1: Permanent auras come before non-permanent ones
    if aIsPermanent and not bIsPermanent then return true end
    if not aIsPermanent and bIsPermanent then return false end

    -- Rule 2: If both are permanent, sort alphabetically by name
    if aIsPermanent and bIsPermanent then
        local aName = a.name or ""
        local bName = b.name or ""
        return aName < bName
    end

    -- Rule 3: If both are non-permanent, use the original start time sort
    local aStart = (a.expirationTime or 0) - (a.duration or 0)
    local bStart = (b.expirationTime or 0) - (b.duration or 0)
    if aStart == bStart then
        return a.auraInstanceID < b.auraInstanceID -- Stable tiebreaker
    end
    return aStart < bStart
end

-- Resizing Handle Setup
local handleSize = 8
local handles = {}
local draggingHandle = nil
local dragStartX, dragStartY = 0, 0
local frameStartX, frameStartY, frameStartW, frameStartH = 0, 0, 0, 0
local minFrameW, minFrameH = 100, 50 -- Minimum dimensions

local handlePoints = {
    -- TopLeft = {"TOPLEFT", 0, 0},
    -- Top = {"TOP", 0, 0},
    -- TopRight = {"TOPRIGHT", 0, 0},
    Left = {"LEFT", 0, 0},
    Right = {"RIGHT", 0, 0},
    -- BottomLeft = {"BOTTOMLEFT", 0, 0},
    -- Bottom = {"BOTTOM", 0, 0},
    -- BottomRight = {"BOTTOMRIGHT", 0, 0},
}

-- Define Constants for Layout (Mostly defaults now, read from Config where needed)
-- local AURA_ICON_WIDTH = 44 -- Deprecated
-- local AURA_ICON_HEIGHT = 56 -- Deprecated
local TITLE_CLEARANCE = 15 -- Space above icons for title (Used for min height calc? Check usage)
-- local DEFAULT_FRAME_PADDING = 0 -- Deprecated
local DEFAULT_ICONS_WIDE = 6 -- Default number of icons horizontally

-- Calculate minimum height (for title + 1 row) - Check if still needed/used correctly
--[[ Deprecated Height Calc - Now dynamic in LayoutAuras
local function CalculateMinHeight(iconH, padding, titleClearance)
    return titleClearance + padding + iconH + padding
end
local minRequiredHeight = CalculateMinHeight(AURA_ICON_HEIGHT, DEFAULT_FRAME_PADDING, TITLE_CLEARANCE)
]]

-- Forward declaration needed if functions call each other in a loop, not strictly necessary here but good practice
local CreateResizeHandlesForFrame
local UpdateEdgeHandleDimensions

-- Generalized function to create handles for a frame
CreateResizeHandlesForFrame = function(frame, frameName)
    frame.handles = frame.handles or {}
    local minFrameW, minFrameH = 100, 50 -- Define min size here or pass as arg if needed

    for pointName, pointData in pairs(handlePoints) do
        local point, xOff, yOff = unpack(pointData)
        local handle = CreateFrame("Frame", "BoxxyAurasResizeHandle" .. frameName .. pointName, frame) -- Parent is the frame
        
        -- Only create Left and Right handles (vertical)
        local h = frame:GetHeight() * 0.8 -- Handle height is percentage of frame height
        local w = handleSize -- Fixed width for vertical handles
        yOff = 0 -- Center vertically

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
            if frame.draggingHandle ~= self.pointName then self.bg:Hide() end
        end)

        handle:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                frame.draggingHandle = pointName
                frame.dragStartX, frame.dragStartY = GetCursorPosition()
                frame.frameStartW, frame.frameStartH = frame:GetSize()
                frame.frameStartX = frame:GetLeft()
                frame.frameStartY = frame:GetTop()
                self.bg:Show() 
            end
        end)
        -- ADD OnMouseUp script to finalize resize, save, and layout
        handle:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and frame.draggingHandle == self.pointName then
                -- No need to get finalW or save width here anymore. 
                -- numIconsWide was saved during the drag in OnUpdate.
                -- The frame size is already set correctly by OnUpdate.

                -- Determine settings key (needed for print message, could remove print)
                local dbKey = nil
                if frame == buffDisplayFrame then
                    dbKey = "buffFrameSettings"
                elseif frame == debuffDisplayFrame then
                    dbKey = "debuffFrameSettings"
                end
                if dbKey and BoxxyAurasDB and BoxxyAurasDB[dbKey] then
                     -- Width is implicitly saved via numIconsWide
                end

                -- Trigger final layout for the affected frame
                local iconList = nil
                if frame == buffDisplayFrame then
                    iconList = BoxxyAuras.buffIcons
                elseif frame == debuffDisplayFrame then
                    iconList = BoxxyAuras.debuffIcons
                end
                if iconList then
                    BoxxyAuras.LayoutAuras(frame, iconList)
                end

                -- Reset dragging state and hide handle background
                frame.draggingHandle = nil
                self.bg:Hide()
            end
        end)
        frame.handles[pointName] = handle
    end
end

-- Generalized function to resize edge handles 
UpdateEdgeHandleDimensions = function(frame, frameW, frameH)
    if not frame or not frame.handles then return end -- Safety check
    for pointName, handle in pairs(frame.handles) do
        -- Only Left and Right handles exist now
            handle:SetSize(handleSize, frameH * 0.8)
        end
end

-- *** Attach LayoutAuras function to the BoxxyAuras table ***
BoxxyAuras.LayoutAuras = function(targetFrame, iconList)
    if not iconList or #iconList == 0 then return end -- Simplified check
    
    -- Determine Frame Type, Alignment Setting, AND Icons Wide Setting
    local frameType = nil
    local alignment = "LEFT" -- Default alignment
    local numIconsWide = DEFAULT_ICONS_WIDE -- Default columns
    local settingsKey = nil
    
    if targetFrame == buffDisplayFrame then
        frameType = "Buff"
        settingsKey = "buffFrameSettings"
        -- Read alignment, ensure BoxxyAurasDB and the key exist
        if BoxxyAurasDB and BoxxyAurasDB[settingsKey] then
            alignment = BoxxyAurasDB[settingsKey].buffTextAlign or "LEFT"
            numIconsWide = BoxxyAurasDB[settingsKey].numIconsWide or DEFAULT_ICONS_WIDE
        end
    elseif targetFrame == debuffDisplayFrame then
        frameType = "Debuff"
        settingsKey = "debuffFrameSettings"
        if BoxxyAurasDB and BoxxyAurasDB[settingsKey] then
            alignment = BoxxyAurasDB[settingsKey].debuffTextAlign or "LEFT"
            numIconsWide = BoxxyAurasDB[settingsKey].numIconsWide or DEFAULT_ICONS_WIDE
        end
    else
        print("|cffFF0000LayoutAuras Error:|r Unknown target frame.")
        return
    end
    
    -- Get padding values from config
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6 
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6
    -- Note: internal icon Padding is used within AuraIcon.New to get iconW/iconH

    -- Count visible icons first
    local visibleIconCount = 0
    for _, auraIcon in ipairs(iconList) do
        if auraIcon.frame and auraIcon.frame:IsShown() then
            visibleIconCount = visibleIconCount + 1
        end
    end
    
    -- Calculate minimum height FIRST, even if no icons
    -- We need an icon size even if none are visible
    local iconW, iconH = nil, nil
    local currentIconSize = 24 -- Default if DB not ready
    if settingsKey and BoxxyAurasDB and BoxxyAurasDB[settingsKey] and BoxxyAurasDB[settingsKey].iconSize then
        currentIconSize = BoxxyAurasDB[settingsKey].iconSize
    end
    
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    iconW = currentIconSize + (internalPadding * 2)
    iconH = currentIconSize + textHeight + (internalPadding * 2)
    
    local iconsPerRow = math.max(1, numIconsWide)
    local numRows = math.max(1, math.ceil(visibleIconCount / iconsPerRow))
    local requiredIconBlockHeight = numRows * iconH + math.max(0, numRows - 1) * iconSpacing 
    local requiredFrameHeight = framePadding + requiredIconBlockHeight + framePadding 
    
    local minPossibleHeight = framePadding + (1 * iconH) + framePadding 
    local targetHeight = math.max(minPossibleHeight, requiredFrameHeight)

    -- Set height BEFORE checking visibleIconCount
    local frameH = targetFrame:GetHeight()
    if frameH ~= targetHeight then
        targetFrame:SetHeight(targetHeight)
        local currentWidthForHandleUpdate = targetFrame:GetWidth() 
        UpdateEdgeHandleDimensions(targetFrame, currentWidthForHandleUpdate, targetHeight)
        frameH = targetHeight 
    end

    -- NOW check if there are icons to position
    if visibleIconCount == 0 then 
        return
    end 
    
    -- Get frame width for centering
    local frameW = targetFrame:GetWidth()

    -- Pre-calculate number of icons on each row for center alignment
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
    -- For Center, we always anchor TopLeft to TopLeft
    if alignment == "CENTER" then
        frameAnchorPoint = "TOPLEFT"
        iconAnchorPoint = "TOPLEFT"
    end

    local currentVisibleIndex = 0
    for i, auraIcon in ipairs(iconList) do
        if auraIcon.frame and auraIcon.frame:IsShown() then
            currentVisibleIndex = currentVisibleIndex + 1
            local row = math.floor((currentVisibleIndex - 1) / iconsPerRow) 
            local col_from_left = (currentVisibleIndex - 1) % iconsPerRow
            auraIcon.frame:ClearAllPoints()
            
            local yOffset = -framePadding - (row * (iconH + iconSpacing))
            local xOffset = 0

            if alignment == "CENTER" then
                -- Get pre-calculated icons on this row (use row+1 for 1-based table index)
                local iconsOnThisRow = iconsPerRowNum[row + 1] or 1 
                -- Calculate the total width of icons + spacing for THIS row
                local rowWidth = iconsOnThisRow * iconW + math.max(0, iconsOnThisRow - 1) * iconSpacing
                -- Calculate starting X offset to center this row's block
                local startXForRow = (frameW - rowWidth) / 2
                -- Calculate final X offset for this specific icon
                xOffset = startXForRow + col_from_left * (iconW + iconSpacing)
            
            elseif alignment == "RIGHT" then
                -- Revert RIGHT ALIGNMENT calculation to use col_from_left
                xOffset = -(framePadding + col_from_left * (iconW + iconSpacing)) 
            else -- Default to LEFT
                xOffset = framePadding + col_from_left * (iconW + iconSpacing)
            end
            
            auraIcon.frame:SetPoint(iconAnchorPoint, targetFrame, frameAnchorPoint, xOffset, yOffset)
        end
    end
end

for pointName, _ in pairs(handlePoints) do
    CreateResizeHandlesForFrame(mainFrame, pointName)
end
UpdateEdgeHandleDimensions(mainFrame, mainFrame:GetSize()) -- Call once after creation with initial size

-- Generalized OnUpdate function for resizing (NEW LOGIC)
local function OnDisplayFrameResizeUpdate(frame, elapsed)
    if not frame.draggingHandle then return end
    if not IsMouseButtonDown("LeftButton") then return end

    -- Determine settings key
    local settingsKey = nil
    if frame == buffDisplayFrame then settingsKey = "buffFrameSettings"
    elseif frame == debuffDisplayFrame then settingsKey = "debuffFrameSettings"
    else return end -- Should not happen

    if not BoxxyAurasDB or not BoxxyAurasDB[settingsKey] then return end -- Need DB

    local fixedFrameH = frame:GetHeight() 

    -- Get dynamic values including frame-specific iconSize
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6  
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    -- Get iconSize for THIS frame type
    local iconTextureSize = 24 -- Default
    if settingsKey and BoxxyAurasDB and BoxxyAurasDB[settingsKey] and BoxxyAurasDB[settingsKey].iconSize then
         iconTextureSize = BoxxyAurasDB[settingsKey].iconSize
    end
    
    -- Calculate iconW based on THIS frame's size
    local iconW = iconTextureSize + (internalPadding * 2)
    
    -- Calculate stepWidth using iconW and IconSpacing
    local stepWidth = iconW + iconSpacing
    local minNumIconsWide = 1 
    -- Calculate minFrameW based on 1 icon + FramePadding on sides
    local minFrameW = (framePadding * 2) + iconW

    -- Calculate potential width from mouse drag
    local mouseX, _ = GetCursorPosition()
    local deltaX = mouseX - (frame.dragStartX or 0) -- Change in screen pixels
    local scale = frame:GetEffectiveScale() -- Get current frame scale
    local deltaW_local = deltaX / scale -- Convert pixel change to frame's local dimension change
    
    local potentialW = 0
    local finalX = frame.frameStartX -- Frame position is in screen coordinates, so use unscaled deltaX here
    local draggingHandle = frame.draggingHandle

    if draggingHandle == "Right" then
        potentialW = frame.frameStartW + deltaW_local -- Apply local dimension change
    elseif draggingHandle == "Left" then
        potentialW = frame.frameStartW - deltaW_local -- Apply local dimension change
        finalX = frame.frameStartX + deltaX -- Frame X position adjustment uses screen pixels
    else
        return
    end
    
    -- Ensure potential width is at least minimum required for 1 icon
    potentialW = math.max(minFrameW, potentialW)

    -- Calculate how many icons *COULD* fit in the potential width (Iterative approach)
    local numIconsCheck = minNumIconsWide 
    while true do
        -- Calculate width required for ONE MORE icon using FramePadding and IconSpacing
        local widthForNextCheck = (framePadding * 2) + ((numIconsCheck + 1) * iconW) + math.max(0, numIconsCheck) * iconSpacing
        
        if potentialW >= widthForNextCheck then
            numIconsCheck = numIconsCheck + 1
        else
            break 
        end
        if numIconsCheck > 100 then break end 
    end
    local potentialNumIconsFit = numIconsCheck

    -- Get the CURRENTLY saved number of icons wide
    local currentNumIconsWide = BoxxyAurasDB[settingsKey].numIconsWide or DEFAULT_ICONS_WIDE

    local newNumIconsWide = currentNumIconsWide -- Assume no change initially
    local needsDBUpdate = false

    -- Check if the potential number of icons differs from the saved value
    if potentialNumIconsFit ~= currentNumIconsWide then
        newNumIconsWide = potentialNumIconsFit
        BoxxyAurasDB[settingsKey].numIconsWide = newNumIconsWide -- Update the saved setting
        needsDBUpdate = true
    end

    -- Calculate the snapped width BASED ON the (potentially new) numIconsWide using the helper function
    local snappedW = BoxxyAuras.CalculateFrameWidth(newNumIconsWide, iconTextureSize)
    -- snappedW = math.max(minFrameW, snappedW) -- min check is now inside helper

    -- Adjust X position if dragging left handle and width changed
    if draggingHandle == "Left" then
        finalX = frame.frameStartX + frame.frameStartW - snappedW
    end

    local currentW, _ = frame:GetSize()
    local currentX, _ = frame:GetLeft(), frame:GetTop()
    
    -- Only apply changes if width or position actually changed
    local needsFrameUpdate = (snappedW ~= currentW or finalX ~= currentX)
    if needsFrameUpdate then
        frame:SetSize(snappedW, fixedFrameH) -- Apply width based on numIconsWide, keep fixed height
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", finalX, frame.frameStartY) -- Keep original Y
        UpdateEdgeHandleDimensions(frame, snappedW, fixedFrameH)
    end
    
    -- If the DB was updated, we might want to re-layout immediately
    -- if needsDBUpdate then
    --    LayoutAuras(frame, (frame == buffDisplayFrame and BoxxyAuras.buffIcons or BoxxyAuras.debuffIcons))
    -- end 
    -- Commented out: Immediate relayout might feel jerky during drag. OnMouseUp handles final layout.
end

-- Attach the generalized OnUpdate to both frames
buffDisplayFrame:SetScript("OnUpdate", function(self, elapsed) OnDisplayFrameResizeUpdate(self, elapsed) end)
debuffDisplayFrame:SetScript("OnUpdate", function(self, elapsed) OnDisplayFrameResizeUpdate(self, elapsed) end)

-- Function to populate trackedAuras and create initial icons
local function InitializeAuras()
    -- API Check
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        print("|cffff0000BoxxyAuras Error: C_UnitAuras Slot API not ready during Initialize!|r")
        return 
    end

    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then 
        print("|cffff0000BoxxyAuras Error: AuraIcon class not found during Initialize!|r")
        return 
    end

    -- 1. Clear existing cache and icons
    wipe(trackedBuffs)
    wipe(trackedDebuffs)
    -- We might need a more robust way to handle existing icon frames later, but wipe is ok for init
    for _, icon in ipairs(BoxxyAuras.buffIcons) do icon.frame:Hide() end
    for _, icon in ipairs(BoxxyAuras.debuffIcons) do icon.frame:Hide() end

    -- 2. Fetch current auras
    local currentBuffs = {}
    local currentDebuffs = {}
    local buffSlots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
    local debuffSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }

    for i = 2, #buffSlots do
        local slot = buffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(currentBuffs, auraData) 
        end
    end
    for i = 2, #debuffSlots do
        local slot = debuffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(currentDebuffs, auraData) 
        end
    end

    -- 3. Sort fetched auras (defines initial order)
    table.sort(currentBuffs, SortAurasForDisplay)
    table.sort(currentDebuffs, SortAurasForDisplay)

    -- 4. Populate tracked cache (copy sorted data)
    for _, auraData in ipairs(currentBuffs) do table.insert(trackedBuffs, auraData) end
    for _, auraData in ipairs(currentDebuffs) do table.insert(trackedDebuffs, auraData) end

    -- 5. Create/Update Icon Objects based on tracked cache
    for i, auraData in ipairs(trackedBuffs) do
        local auraIcon = BoxxyAuras.buffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(buffDisplayFrame, i, "BoxxyAurasBuffIcon")
            BoxxyAuras.buffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HELPFUL")
        auraIcon.frame:Show() 
    end
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = BoxxyAuras.debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffDisplayFrame, i, "BoxxyAurasDebuffIcon")
            BoxxyAuras.debuffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HARMFUL")
        auraIcon.frame:Show()
    end

    -- 6. Hide any potentially leftover icons 
    for i = #trackedBuffs + 1, #BoxxyAuras.buffIcons do BoxxyAuras.buffIcons[i].frame:Hide() end
    for i = #trackedDebuffs + 1, #BoxxyAuras.debuffIcons do BoxxyAuras.debuffIcons[i].frame:Hide() end

    -- 7. Layout the visible icons for BOTH frames
    BoxxyAuras.LayoutAuras(buffDisplayFrame, BoxxyAuras.buffIcons) 
    BoxxyAuras.LayoutAuras(debuffDisplayFrame, BoxxyAuras.debuffIcons)

    C_Timer.After(0.05, function() 
        BoxxyAuras.UpdateAuras() -- Pass true to indicate it's from OnLeave
    end)
end

-- Function to update displayed auras using cache comparison and stable order
BoxxyAuras.UpdateAuras = function() -- Make it part of the addon table
    -- API Check
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        return 
    end
    local AuraIcon = BoxxyAuras.AuraIcon
    if not AuraIcon then return end

    -- 1. Fetch current auras
    local currentBuffs = {}
    local currentDebuffs = {}
    local buffSlots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
    local debuffSlots = { C_UnitAuras.GetAuraSlots("player", "HARMFUL") }

    for i = 2, #buffSlots do
        local slot = buffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(currentBuffs, auraData) 
        end
    end
    for i = 2, #debuffSlots do
        local slot = debuffSlots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        if auraData then 
            auraData.slot = slot -- Store the slot/index on the data table
            table.insert(currentDebuffs, auraData) 
        end
    end

    -- 2. Build Current Lookup Map & Mark Tracked Auras
    local currentBuffMap = {}
    for _, auraData in ipairs(currentBuffs) do currentBuffMap[auraData.auraInstanceID] = auraData end
    local currentDebuffMap = {}
    for _, auraData in ipairs(currentDebuffs) do currentDebuffMap[auraData.auraInstanceID] = auraData end
    
    for _, trackedAura in ipairs(trackedBuffs) do trackedAura.seen = false end
    for _, trackedAura in ipairs(trackedDebuffs) do trackedAura.seen = false end

    -- Get hover states for BOTH frames using the direct check function again
    local isHoveringBuffs = BoxxyAuras.IsMouseWithinFrame(buffDisplayFrame)
    local isHoveringDebuffs = BoxxyAuras.IsMouseWithinFrame(debuffDisplayFrame)
    
    local newBuffsToAdd = {}
    local newDebuffsToAdd = {}

    -- 3. Process Current Buffs (Mark Seen / Identify New)
    for _, currentAura in ipairs(currentBuffs) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedBuffs) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                -- Update ONLY volatile data & slot
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot -- Update slot in case it changes
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            table.insert(newBuffsToAdd, currentAura) -- Add the whole auraData (includes .slot)
        end
    end
    -- Process Current Debuffs (Mark Seen / Identify New)
    for _, currentAura in ipairs(currentDebuffs) do
        local foundInTracked = false
        for _, trackedAura in ipairs(trackedDebuffs) do
            if trackedAura.auraInstanceID == currentAura.auraInstanceID then
                -- Update ONLY volatile data & slot
                trackedAura.expirationTime = currentAura.expirationTime
                trackedAura.duration = currentAura.duration
                trackedAura.slot = currentAura.slot -- Update slot in case it changes
                trackedAura.seen = true
                foundInTracked = true
                break
            end
        end
        if not foundInTracked then
            table.insert(newDebuffsToAdd, currentAura) -- Add the whole auraData (includes .slot)
        end
    end

    -- 4. Rebuild Tracked Lists (Remove or Hold Expired/Removed)
    local newTrackedBuffs = {}
    for _, trackedAura in ipairs(trackedBuffs) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil -- Ensure flag is nil for active auras
            table.insert(newTrackedBuffs, trackedAura)
        else -- Not seen: Expired or Removed
            -- Use buff frame hover state here
            if isHoveringBuffs then
                table.insert(newTrackedBuffs, trackedAura) -- Keep if hovering BUFF frame
                trackedAura.forceExpired = true -- Mark it as kept only due to hover
                -- Also ensure volatile data is cleared or set to indicate expiry if needed
                trackedAura.expirationTime = 0 -- Set expiration time to ensure it shows as expired
            else
                -- Aura is gone AND we are not hovering, remove from cache if present
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
            -- If not seen and not hovering, implicitly dropped from tracked list
        end
    end
    local newTrackedDebuffs = {}
    for _, trackedAura in ipairs(trackedDebuffs) do
        if trackedAura.seen then
            trackedAura.forceExpired = nil -- Ensure flag is nil for active auras
            table.insert(newTrackedDebuffs, trackedAura)
        else -- Not seen: Expired or Removed
             -- Use debuff frame hover state here
            if isHoveringDebuffs then
                table.insert(newTrackedDebuffs, trackedAura) -- Keep if hovering DEBUFF frame
                trackedAura.forceExpired = true -- Mark it as kept only due to hover
                trackedAura.expirationTime = 0 -- Set expiration time to ensure it shows as expired
            else
                 -- Aura is gone AND we are not hovering, remove from cache if present
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
             -- If not seen and not hovering, implicitly dropped from tracked list
        end
    end

    -- 5. Process New Auras: Replace matching expired-hovered auras or append
    local buffsToAppend = {}
    for _, newAura in ipairs(newBuffsToAdd) do 
        local replacedExpired = false
        for i, existingAura in ipairs(newTrackedBuffs) do
            -- Check if existing is expired (not seen) and matches spellId
            if not existingAura.seen and existingAura.spellId == newAura.spellId then
                newTrackedBuffs[i] = newAura -- Replace the expired data with the new aura data
                replacedExpired = true
                -- Trigger tooltip scrape check for the potentially updated aura info
                local key = newAura.spellId
        if key and not BoxxyAuras.AllAuras[key] then 
                    C_Timer.After(0.01, function() BoxxyAuras.AttemptTooltipScrape(key, newAura.auraInstanceID, "HELPFUL") end)
                end
                break -- Stop searching for this newAura
            end
        end
        if not replacedExpired then
            table.insert(buffsToAppend, newAura) -- Not replacing, mark for appending
            -- Trigger tooltip scrape for the genuinely new aura
            local key = newAura.spellId
            if key and not BoxxyAuras.AllAuras[key] then 
                C_Timer.After(0.01, function() BoxxyAuras.AttemptTooltipScrape(key, newAura.auraInstanceID, "HELPFUL") end)
            end
        end
    end
    -- Append any genuinely new buffs
    for _, auraToAppend in ipairs(buffsToAppend) do
        table.insert(newTrackedBuffs, auraToAppend)
    end

    -- Repeat for Debuffs
    local debuffsToAppend = {}
    for _, newAura in ipairs(newDebuffsToAdd) do 
        local replacedExpired = false
        for i, existingAura in ipairs(newTrackedDebuffs) do
            if not existingAura.seen and existingAura.spellId == newAura.spellId then
                newTrackedDebuffs[i] = newAura -- Replace
                replacedExpired = true
                local key = newAura.spellId
        if key and not BoxxyAuras.AllAuras[key] then 
                    C_Timer.After(0.01, function() BoxxyAuras.AttemptTooltipScrape(key, newAura.auraInstanceID, "HARMFUL") end)
                end
                break
            end
        end
        if not replacedExpired then
            table.insert(debuffsToAppend, newAura) -- Mark for appending
            local key = newAura.spellId
            if key and not BoxxyAuras.AllAuras[key] then 
                C_Timer.After(0.01, function() BoxxyAuras.AttemptTooltipScrape(key, newAura.auraInstanceID, "HARMFUL") end)
            end
        end
    end
    for _, auraToAppend in ipairs(debuffsToAppend) do
        table.insert(newTrackedDebuffs, auraToAppend)
    end

    -- 6. Replace Cache
    trackedBuffs = newTrackedBuffs
    trackedDebuffs = newTrackedDebuffs

    -- 6a. Conditionally re-sort if NOT hovering
    if not isHoveringBuffs then
        table.sort(trackedBuffs, SortAurasForDisplay)
    end
    if not isHoveringDebuffs then
        table.sort(trackedDebuffs, SortAurasForDisplay)
    end

    -- 7. Update Visual Icons based on final TRACKED cache
    for i, auraData in ipairs(trackedBuffs) do
        local auraIcon = BoxxyAuras.buffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(buffDisplayFrame, i, "BoxxyAurasBuffIcon")
            BoxxyAuras.buffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HELPFUL")
        auraIcon.frame:Show() 
    end

     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = BoxxyAuras.debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffDisplayFrame, i, "BoxxyAurasDebuffIcon")
            BoxxyAuras.debuffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HARMFUL")
        auraIcon.frame:Show()
    end

    -- 8. Hide Leftover Visual Icons
    for i = #trackedBuffs + 1, #BoxxyAuras.buffIcons do 
        if BoxxyAuras.buffIcons[i] and BoxxyAuras.buffIcons[i].frame then BoxxyAuras.buffIcons[i].frame:Hide() end
    end
    for i = #trackedDebuffs + 1, #BoxxyAuras.debuffIcons do 
        if BoxxyAuras.debuffIcons[i] and BoxxyAuras.debuffIcons[i].frame then BoxxyAuras.debuffIcons[i].frame:Hide() end
    end

    -- 9. Layout BOTH frames
    BoxxyAuras.LayoutAuras(buffDisplayFrame, BoxxyAuras.buffIcons)
    BoxxyAuras.LayoutAuras(debuffDisplayFrame, BoxxyAuras.debuffIcons)
end

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN") 
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    local unit = (...)
    if event == "PLAYER_LOGIN" then
        -- Draw and Color mainFrame backdrop/border here, AFTER UIUtils is loaded
        BoxxyAuras.UIUtils.DrawSlicedBG(mainFrame, "MainFrameHoverBG", "backdrop", 0)
        BoxxyAuras.UIUtils.DrawSlicedBG(mainFrame, "EdgedBorder", "border", 0)
        
        local cfgMainBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
        local cfgMainBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.5, g = 0.5, b = 0.5, a = 1.0 }
        
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainBGN.r, cfgMainBGN.g, cfgMainBGN.b, cfgMainBGN.a)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "border", cfgMainBorder.r, cfgMainBorder.g, cfgMainBorder.b, cfgMainBorder.a)
        
        -- Initialize Saved Variables
        if BoxxyAurasDB == nil then BoxxyAurasDB = {} end
        
        -- Define defaults INSIDE the handler, right before use
        -- Calculate default minimum height based on config and DEFAULT icon size
        local defaultPadding = BoxxyAuras.Config.Padding or 6
        local defaultIconSize_ForCalc = 24 -- Define default size for height calculation
        local defaultTextHeight = BoxxyAuras.Config.TextHeight or 8
        local defaultIconH = defaultIconSize_ForCalc + defaultTextHeight + (defaultPadding * 2) 
        local defaultFramePadding = BoxxyAuras.Config.FramePadding or 6
        local defaultMinHeight = defaultFramePadding + defaultIconH + defaultFramePadding 
        
        local defaultBuffFrameSettings = {
            x = 0, y = -150, anchor = "TOP",
            width = 300, height = defaultMinHeight,
            numIconsWide = DEFAULT_ICONS_WIDE, 
            buffTextAlign = "CENTER",
            iconSize = 24 -- <<< ADDED Default Buff Icon Size
        }
        local defaultDebuffFrameSettings = {
            x = 0, y = -150 - defaultMinHeight - 30, anchor = "TOP",
            width = 300, height = defaultMinHeight, 
            numIconsWide = DEFAULT_ICONS_WIDE, 
            debuffTextAlign = "CENTER",
            iconSize = 24 -- <<< ADDED Default Debuff Icon Size
        }
        
        local function InitializeSettings(dbKey, defaults)
            -- Add a check here just in case
            if type(defaults) ~= "table" then
                print(string.format("|cffFF0000BoxxyAuras Error:|r Default settings for %s are not a table!", dbKey))
                BoxxyAurasDB[dbKey] = {} -- Initialize empty to prevent further errors
                return BoxxyAurasDB[dbKey]
            end
            
            if BoxxyAurasDB[dbKey] == nil then 
                BoxxyAurasDB[dbKey] = CopyTable(defaults)
            else -- Ensure all keys exist even if DB entry exists
            for key, defaultValue in pairs(defaults) do
                if BoxxyAurasDB[dbKey][key] == nil then
                    BoxxyAurasDB[dbKey][key] = defaultValue
                    end
                end
            end
            return BoxxyAurasDB[dbKey]
        end
        
        -- Default hideBlizzardAuras if needed (ensure it exists in DB)
        if BoxxyAurasDB.hideBlizzardAuras == nil then BoxxyAurasDB.hideBlizzardAuras = true end -- Default to TRUE

        local buffSettings = InitializeSettings("buffFrameSettings", defaultBuffFrameSettings)
        local debuffSettings = InitializeSettings("debuffFrameSettings", defaultDebuffFrameSettings)

        -- Apply Settings (sets width/pos/min_height) using the now global function
        BoxxyAuras.ApplySettings(buffDisplayFrame, buffSettings, "Buff Frame")
        BoxxyAuras.ApplySettings(debuffDisplayFrame, debuffSettings, "Debuff Frame")

        -- Apply Blizzard frame visibility setting AFTER DB init
        BoxxyAuras.ApplyBlizzardAuraVisibility(BoxxyAurasDB.hideBlizzardAuras)

        -- Initialize Handles (uses width set above, initial height might be small)
        CreateResizeHandlesForFrame(buffDisplayFrame, "BuffFrame") 
        CreateResizeHandlesForFrame(debuffDisplayFrame, "DebuffFrame") 
        local buffW, buffH = buffDisplayFrame:GetSize()
        local debuffW, debuffH = debuffDisplayFrame:GetSize()
        UpdateEdgeHandleDimensions(buffDisplayFrame, buffW, buffH) -- Handles will resize when LayoutAuras sets final height
        UpdateEdgeHandleDimensions(debuffDisplayFrame, debuffW, debuffH)
        
        -- Setup Display Frames visuals AFTER settings applied
        BoxxyAuras.SetupDisplayFrame(buffDisplayFrame, "BuffFrame")
        BoxxyAuras.SetupDisplayFrame(debuffDisplayFrame, "DebuffFrame")
        
        -- >> ADDED BACK: Apply initial scale AND lock state to Buff/Debuff frames after setup <<
        if BoxxyAurasDB then
            local initialScale = BoxxyAurasDB.optionsScale or 1.0
            local initialLock = BoxxyAurasDB.lockFrames or false
            
            -- Apply Scale directly to buff/debuff frames
            if buffDisplayFrame then buffDisplayFrame:SetScale(initialScale) end
            if debuffDisplayFrame then debuffDisplayFrame:SetScale(initialScale) end
            
            -- Apply Lock State directly within the timer for initial load
            if initialLock then
                local function DirectApplyLock(frame, baseName)
                    if not frame then return end
                    
                    frame:SetMovable(false)
                    frame.isLocked = true
                    frame.wasLocked = true -- Sync state for polling
                    
                    -- Hide handles
                    if frame.handles then
                        for name, handle in pairs(frame.handles) do
                            handle:EnableMouse(false)
                            handle:Hide()
                        end
                    end
                    -- Hide title
                    local titleLabelName = baseName .. "TitleLabel"
                    local titleLabel = _G[titleLabelName]
                    if titleLabel then titleLabel:Hide() end
                    
                    -- Hide background/border (Set alpha to 0)
                    if frame.backdropTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
                        local currentBgColor = frame.backdropTextures[5] and {frame.backdropTextures[5]:GetVertexColor()} or {0.1, 0.1, 0.1}
                        BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", currentBgColor[1], currentBgColor[2], currentBgColor[3], 0)
                    end
                    if frame.borderTextures and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
                        local currentBorderColor = frame.borderTextures[5] and {frame.borderTextures[5]:GetVertexColor()} or {0.4, 0.4, 0.4}
                        BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", currentBorderColor[1], currentBorderColor[2], currentBorderColor[3], 0)
                    end
                end
                
                DirectApplyLock(buffDisplayFrame, "BuffFrame")
                DirectApplyLock(debuffDisplayFrame, "DebuffFrame")
            else
                    -- Optional: Add logic here if you need to ensure frames are explicitly UNLOCKED on load 
                    -- (though ApplySettings and SetupDisplayFrame should handle default appearance)
                    print("BoxxyAuras: Initial lock state is false, no direct locking needed.") -- DEBUG
            end
            -- REMOVED call to BoxxyAuras.Options.ApplyLockState from timer
        end
        
        -- Start polling timers AFTER setup is complete
        C_Timer.NewTicker(0.2, function() BoxxyAuras.PollFrameHoverState(buffDisplayFrame, "Buff Frame") end) 
        C_Timer.NewTicker(0.2, function() BoxxyAuras.PollFrameHoverState(debuffDisplayFrame, "Debuff Frame") end)

        -- Schedule Initial Aura Load
        C_Timer.After(0.2, InitializeAuras) 
    elseif event == "UNIT_AURA" and unit == "player" then
        -- Debounce the update
        if not BoxxyAuras.updateScheduled then
            BoxxyAuras.updateScheduled = true
            C_Timer.After(0.1, function() 
                BoxxyAuras.updateScheduled = false -- Reset flag before running
                BoxxyAuras.UpdateAuras()
            end)
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()

        -- Check if the event is spell damage taken by the player
        if destName and destName == UnitName("player") and 
           (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE") then
            -- Check if the damage source spellId matches any tracked debuff
            if spellId and #trackedDebuffs > 0 then
                for _, trackedDebuff in ipairs(trackedDebuffs) do
                    -- Compare spell IDs
                    -- Use correct camelCase: trackedDebuff.spellId
                    -- Make sure trackedDebuff and its spellID exist before comparing
                    if trackedDebuff and trackedDebuff.spellId and trackedDebuff.spellId == spellId then
                        -- Found a match! Print a debug message.

                        -- Find the corresponding AuraIcon instance and call Shake
                        for _, auraIcon in ipairs(BoxxyAuras.debuffIcons) do
                            -- Check if the icon exists and its instance ID matches
                            if auraIcon and auraIcon.auraInstanceID and auraIcon.auraInstanceID == trackedDebuff.auraInstanceID then
                                if auraIcon.Shake then -- Check if the Shake method exists
                                    auraIcon:Shake()
                                else
                                     print("|cffFF0000BoxxyAuras ERROR:|r Shake method not found on AuraIcon instance!")
                                end
                                break -- Found the icon, no need to continue looping
                            end
                        end
                        
                        break -- Stop checking once found
                    end
                end
            end
        end
    end
end)

-- Re-enabled Generalized polling function for mouse hover state
BoxxyAuras.PollFrameHoverState = function(frame, frameDesc) -- Make it part of the addon table
    if not frame then return end -- Safety check
    
    -- Determine current hover state unless locked (locked frames ignore mouse)
    local mouseIsOverNow = not frame.isLocked and BoxxyAuras.IsMouseWithinFrame(frame)
    local wasOver = frame.isMouseOver -- Read/Write state from frame object
    local wasLocked = frame.wasLocked -- Read previous lock state
    local isLockedNow = frame.isLocked -- Read current lock state
    
    -- Determine if state needs updating (hover changed OR lock changed)
    local needsUpdate = (mouseIsOverNow ~= wasOver) or (isLockedNow ~= wasLocked)
    
    if needsUpdate then
        -- State changed: Update internal flags
        frame.isMouseOver = mouseIsOverNow -- Update hover state
        frame.wasLocked = isLockedNow      -- Update previous lock state for next poll
        
        -- *** RE-ADD: Trigger UpdateAuras shortly after mouse leaves (if not locked) ***
        if not mouseIsOverNow and wasOver and not isLockedNow then 
           C_Timer.After(0.05, BoxxyAuras.UpdateAuras) 
        end
        
        -- Update visual background AND border effect for THIS frame
        local backdropGroupName = "backdrop" 
        local borderGroupName = "border"
        
        -- Check if texture groups exist before coloring
        local hasBackdrop = frame and frame.backdropTextures
        local hasBorder = frame and frame.borderTextures

        if hasBackdrop or hasBorder then -- Proceed if at least one exists
            local r_bg, g_bg, b_bg, a_bg = 0, 0, 0, 0 -- Background RGBA
            local r_br, g_br, b_br, a_br = 0, 0, 0, 0 -- Border RGBA (initially transparent)

            if isLockedNow then
                -- If locked, set alpha to 0 for both regardless of hover
                a_bg = 0
                a_br = 0
            else
                -- If unlocked, use normal/hover colors for background
        local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
        local cfgHover = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
                
                if mouseIsOverNow and not frame.draggingHandle then 
                    r_bg, g_bg, b_bg, a_bg = cfgHover.r, cfgHover.g, cfgHover.b, cfgHover.a
                else 
                    r_bg, g_bg, b_bg, a_bg = cfgBGN.r, cfgBGN.g, cfgBGN.b, cfgBGN.a
                end
                
                -- Set border to be visible when unlocked (use configured color)
                local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
                r_br, g_br, b_br, a_br = cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a
            end
            
            -- Apply the calculated colors/alphas
            if hasBackdrop then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, backdropGroupName, r_bg, g_bg, b_bg, a_bg)
            end
            if hasBorder then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, borderGroupName, r_br, g_br, b_br, a_br)
            end
        else
             print(string.format("|cffFF0000DEBUG Poll Error:|r backdropTextures OR borderTextures NOT FOUND for %s! Frame Type: %s", frameDesc or "UnknownFrame", type(frame)))
        end
    end
end

-- Tooltip Scraping Function (Using GetUnitAura, finds index via auraInstanceID)
function BoxxyAuras.AttemptTooltipScrape(spellId, targetAuraInstanceID, filter) 
    -- Check if already scraped (key exists in AllAuras) - Use spellId as key
    if spellId and BoxxyAuras.AllAuras[spellId] then return end 
    -- Validate inputs 
    if not spellId or not targetAuraInstanceID or not filter then 
        print(string.format("DEBUG Scrape Error: Invalid arguments. spellId: %s, instanceId: %s, filter: %s",
            tostring(spellId), tostring(targetAuraInstanceID), tostring(filter)))
        return 
    end

    -- Find the CURRENT index for this specific aura instance
    local currentAuraIndex = nil
    for i = 1, 40 do -- Check up to 40 auras (standard limit)
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if auraData then
            -- Compare instance IDs
            if auraData.auraInstanceID == targetAuraInstanceID then
                currentAuraIndex = i
                break
            end
        end
    end

    -- If we didn't find the aura instance (it might have expired/shifted instantly), abort scrape
    if not currentAuraIndex then
        return
    end

    local tipData = C_TooltipInfo.GetUnitAura("player", currentAuraIndex, filter) 

    if not tipData then 
        -- This failure is now less likely, but could still happen in rare cases
        print(string.format("DEBUG Scrape Error: GetUnitAura failed unexpectedly for SpellID: %s (Found Index: %s, Filter: %s) via InstanceID %s", 
            tostring(spellId), tostring(currentAuraIndex), filter, tostring(targetAuraInstanceID)))
        return
    end

    -- Get tooltip lines
    local tooltipLines = {}
    local spellNameFromTip = nil -- Variable to store name from tooltip
    if tipData.lines then
        for i = 1, #tipData.lines do
            local lineData = tipData.lines[i]
            if lineData and lineData.leftText then
                local lineText = lineData.leftText
                if lineData.rightText then 
                    lineText = lineText .. " " .. lineData.rightText 
                end
                -- Store the first line's left text as the potential name
                if i == 1 and lineData.leftText then 
                    spellNameFromTip = lineData.leftText
                end
                
                -- Check if the line contains "remaining" (case-insensitive)
                if not string.find(lineText, "remaining", 1, true) then
                    table.insert(tooltipLines, lineText)
                end
            end
        end
    end
end 

-- Common Frame Setup Function
BoxxyAuras.SetupDisplayFrame = function(frame, frameName) -- Make it part of addon table
    -- Draw backdrop and border using new utility functions
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, frameName .. "HoverBG", "backdrop", 0)
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "EdgedBorder", "border", 0)

    -- Set initial colors using config
    local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
    local cfgHover = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
    local cfgBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.5, g = 0.5, b = 0.5, a = 1.0 } -- Assuming shared border color for now

    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", cfgBGN.r, cfgBGN.g, cfgBGN.b, cfgBGN.a)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", cfgBorder.r, cfgBorder.g, cfgBorder.b, cfgBorder.a)

    -- Create and Anchor Title Label
    local labelText = (frameName == "BuffFrame") and "Buffs" or "Debuffs" -- Should correctly set text to "Buffs" for the buff frame
    local titleLabel = frame:CreateFontString(frameName .. "TitleLabel", "OVERLAY", "GameFontNormalLarge")
        
    if titleLabel then
        -- Anchor the label's bottom-left to the frame's top-left, placing it above the frame
        titleLabel:ClearAllPoints() -- Clear previous points just in case
        titleLabel:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2) -- (0, 2) adds 2px vertical space above
        titleLabel:SetJustifyH("LEFT")
        titleLabel:SetTextColor(1, 1, 1, 0.9) -- White, slightly transparent
        titleLabel:SetText(labelText)
        frame.titleLabel = titleLabel -- Store reference if needed
    else
        -- This error would print if CreateFontString failed
        print(string.format("|cffFF0000DEBUG SetupDisplayFrame Error:|r Failed to create TitleLabel for Frame='%s', Name='%s'",
            frame:GetName() or "N/A", tostring(frameName)))
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) 
        -- Only start moving if the frame is not locked
        if not self.isLocked then
            self:StartMoving() 
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        -- DEBUG: Check self at the start of OnDragStop
        if not self then
            print("self is nil in OnDragStop!")
            return -- Can't do anything if self is nil
        end

        -- Simplified logic: If OnDragStop fires, attempt to stop moving and save.
        if type(self.StopMovingOrSizing) == "function" then
            self:StopMovingOrSizing()
        end

        -- Reset dragging handle state regardless
        self.draggingHandle = nil

        -- Save new position
        local finalX, finalY = self:GetLeft(), self:GetTop()
        local dbKey = nil
        if self == buffDisplayFrame then
            dbKey = "buffFrameSettings"
        elseif self == debuffDisplayFrame then
            dbKey = "debuffFrameSettings"
        end

        if dbKey and BoxxyAurasDB and BoxxyAurasDB[dbKey] then
            BoxxyAurasDB[dbKey].x = finalX
            BoxxyAurasDB[dbKey].y = finalY
            BoxxyAurasDB[dbKey].anchor = "TOPLEFT"
        end

        -- Final layout update
        local iconList = nil
        if self == buffDisplayFrame then
            iconList = BoxxyAuras.buffIcons
        elseif self == debuffDisplayFrame then
            iconList = BoxxyAuras.debuffIcons
        end

        if iconList then
            BoxxyAuras.LayoutAuras(self, iconList)
        end
    end)
    frame:SetClampedToScreen(true)
end 

-- *** MOVE ApplySettings Function OUTSIDE of PLAYER_LOGIN and attach to BoxxyAuras ***
BoxxyAuras.ApplySettings = function(frame, settings, frameDesc)
    -- Get dynamic values needed for width/height calculation
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6 
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6   
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6 
    -- Get iconSize for THIS frame type
    local iconTextureSize = 24 -- Default
    if settings and settings.iconSize then
         iconTextureSize = settings.iconSize
    end
    local textHeight = (BoxxyAuras.Config and BoxxyAuras.Config.TextHeight) or 8
    
    -- Calculate base icon dimensions for THIS frame type
    local iconW = iconTextureSize + (internalPadding * 2)
    local iconH = iconTextureSize + textHeight + (internalPadding * 2)
    
    -- Determine width based on numIconsWide using the helper function
    local numIconsWide = settings.numIconsWide or DEFAULT_ICONS_WIDE -- Need default?
    local local_DEFAULT_ICONS_WIDE = 6 
    numIconsWide = settings.numIconsWide or local_DEFAULT_ICONS_WIDE
    numIconsWide = math.max(1, numIconsWide) 
    local calculatedWidth = BoxxyAuras.CalculateFrameWidth(numIconsWide, iconTextureSize)
    
    -- Calculate minimum height (for 1 row) using THIS frame's iconH
    local calculatedMinHeight = framePadding + iconH + framePadding 
    
    -- Set Width, MINIMUM Height, and Position
    frame:SetSize(calculatedWidth, calculatedMinHeight) 
            frame:ClearAllPoints()
    -- Handle different anchors
    if settings.anchor == "CENTER" then
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    elseif settings.anchor == "TOP" then
        frame:SetPoint("TOP", UIParent, "TOP", settings.x, settings.y)
    else -- Default to TOPLEFT 
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.x, settings.y)
    end
end 

-- *** ADD Helper function to calculate required frame width ***
function BoxxyAuras.CalculateFrameWidth(numIcons, iconSize)
    -- Get padding/spacing values from config
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    
    -- Ensure valid inputs (defaults)
    numIcons = numIcons or 1
    iconSize = iconSize or 24
    
    -- Calculate base icon width based on texture size and internal padding
    local iconW = iconSize + (internalPadding * 2)
    
    -- Calculate total width
    local calculatedWidth = (framePadding * 2) + (numIcons * iconW) + math.max(0, numIcons - 1) * iconSpacing
    
    -- Calculate minimum width (for 1 icon) just in case numIcons was 0 somehow
    local minFrameW = (framePadding * 2) + (1 * iconW) 
    
    return math.max(minFrameW, calculatedWidth)
end

-- *** ADD Helper function to trigger layout for a specific frame type ***
function BoxxyAuras.TriggerLayout(frameType)
    local targetFrame = nil
    local iconList = nil

    if frameType == "Buff" then
        targetFrame = _G["BoxxyBuffDisplayFrame"]
        iconList = BoxxyAuras.buffIcons
    elseif frameType == "Debuff" then
        targetFrame = _G["BoxxyDebuffDisplayFrame"]
        iconList = BoxxyAuras.debuffIcons
    else
        print(string.format("BoxxyAuras Error: Invalid frameType '%s' passed to TriggerLayout.", tostring(frameType)))
        return
    end

    if targetFrame and iconList and BoxxyAuras.LayoutAuras then
        BoxxyAuras.LayoutAuras(targetFrame, iconList)
    else
        print(string.format("BoxxyAuras Warning: Could not trigger layout for %s. Frame or Icons missing?", frameType))
    end
end 

-- >> ADDED: Function to show/hide default Blizzard frames <<
function BoxxyAuras.ApplyBlizzardAuraVisibility(shouldHide)
    -- Check if BuffFrame exists before trying to modify it
    -- It might not be loaded immediately on PLAYER_LOGIN
    if BuffFrame then
        if shouldHide then
            BuffFrame:Hide()
            DebuffFrame:Hide()
            print("BoxxyAuras: Hiding default Blizzard aura frames (BuffFrame and DebuffFrame).")
        else
            BuffFrame:Show()
            DebuffFrame:Show()
            print("BoxxyAuras: Showing default Blizzard aura frame (BuffFrame).")
        end
    else
        -- If BuffFrame isn't ready, try again shortly after
        C_Timer.After(0.5, function() 
            if BuffFrame then
                if shouldHide then BuffFrame:Hide() else BuffFrame:Show() end
                print("BoxxyAuras: Applied Blizzard frame visibility (delayed).")
            else
                 print("BoxxyAuras Warning: BuffFrame still not found after delay.")
            end
        end)
    end
end 