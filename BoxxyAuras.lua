local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras.AllAuras = {} -- Global cache for aura info

-- Configuration Table
BoxxyAuras.Config = {
    BackgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }, -- Icon Background
    BorderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },      -- Icon Border
    MainFrameBGColorNormal = { r = 0.7, g = 0.7, b = 0.7, a = 0.2 }, -- Main frame normal BG
    MainFrameBGColorHover = { r = 0.7, g = 0.7, b = 0.7, a = 0.6 }, -- Main frame hover BG
    IconSize = 32,
    TextHeight = 12,
    Padding = 6,
    TotalIconHeight = 44,
    TotalIconWidth = 44,
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

local buffIcons = {}
local debuffIcons = {}
local iconSpacing = 4

-- New Cache Tables
local trackedBuffs = {}
local trackedDebuffs = {}

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

-- Define Constants for Layout
local AURA_ICON_WIDTH = 44 -- From AuraIcon.lua: 32 texture + 6*2 padding
local AURA_ICON_HEIGHT = 56 -- From AuraIcon.lua: 32 texture + 12 text + 6*2 padding
local TITLE_CLEARANCE = 15 -- Space above icons for title
local DEFAULT_FRAME_PADDING = 0 -- Default padding inside frame edges
local DEFAULT_ICONS_WIDE = 6 -- Default number of icons horizontally

-- Calculate minimum height (for title + 1 row)
local function CalculateMinHeight(iconH, padding, titleClearance)
    return titleClearance + padding + iconH + padding
end
local minRequiredHeight = CalculateMinHeight(AURA_ICON_HEIGHT, DEFAULT_FRAME_PADDING, TITLE_CLEARANCE)

-- Forward declaration needed if functions call each other in a loop, not strictly necessary here but good practice
local CreateResizeHandlesForFrame
local UpdateEdgeHandleDimensions
local LayoutAuras

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
                -- Get final snapped width
                local finalW, finalH = frame:GetSize()
                
                -- Save the new width
                local dbKey = nil
                if frame == buffDisplayFrame then
                    dbKey = "buffFrameSettings"
                elseif frame == debuffDisplayFrame then
                    dbKey = "debuffFrameSettings"
                end
                
                if dbKey and BoxxyAurasDB and BoxxyAurasDB[dbKey] then
                    BoxxyAurasDB[dbKey].width = finalW
                    print(string.format("BoxxyAuras: Saved %s Resized Width (W: %.1f)", dbKey, finalW))
                end

                -- Trigger final layout for the affected frame
                local iconList = nil
                if frame == buffDisplayFrame then
                    iconList = buffIcons
                elseif frame == debuffDisplayFrame then
                    iconList = debuffIcons
                end
                if iconList then
                    LayoutAuras(frame, iconList) -- Assumes LayoutAuras is defined/forward-declared
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

-- Generalized Layout Function
LayoutAuras = function(targetFrame, iconList)
    if not iconList or #iconList == 0 then return end -- Simplified check
    
    -- Get padding from config, default to 4 if not set
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 4

    -- Count visible icons first
    local visibleIconCount = 0
    for _, auraIcon in ipairs(iconList) do
        if auraIcon.frame and auraIcon.frame:IsShown() then
            visibleIconCount = visibleIconCount + 1
        end
    end
    
    if visibleIconCount == 0 then return end -- Nothing to layout

    -- Ensure the first icon and its frame actually exist before getting size
    local firstVisibleIconFrame = nil
    for _, auraIcon in ipairs(iconList) do
        if auraIcon.frame and auraIcon.frame:IsShown() then
            firstVisibleIconFrame = auraIcon.frame
            break
        end
    end
    
    if not firstVisibleIconFrame then
        print(string.format("DEBUG LayoutAuras: Could not find a visible icon frame in list for %s.", targetFrame:GetName() or "UnknownFrame"))
        return
    end

    local iconW, iconH = firstVisibleIconFrame:GetSize()
    local frameW, frameH = targetFrame:GetSize()
    local containerW = frameW - (framePadding * 2)
    local iconsPerRow = math.max(1, math.floor(containerW / (iconW + framePadding)))

    -- Calculate required height based on number of rows
    local numRows = math.max(1, math.ceil(visibleIconCount / iconsPerRow))
    local requiredIconBlockHeight = numRows * iconH + math.max(0, numRows - 1) * framePadding
    local requiredFrameHeight = TITLE_CLEARANCE + framePadding + requiredIconBlockHeight + framePadding
    
    -- Adjust frame height if needed
    if frameH ~= requiredFrameHeight then
        targetFrame:SetHeight(requiredFrameHeight)
        UpdateEdgeHandleDimensions(targetFrame, frameW, requiredFrameHeight) -- Update handles to match new height
        -- Re-get frameH as it changed (Important! Though not used further down in current logic)
        frameH = requiredFrameHeight 
    end

    -- Get the top-left backdrop texture to use as a visual anchor
    local anchorTexture = targetFrame.backdropTextures and targetFrame.backdropTextures[1]
    if not anchorTexture then
        print("|cffFF0000LayoutAuras Error:|r Cannot find anchor texture (backdropTextures[1]) for " .. (targetFrame:GetName() or "UnknownFrame"))
        return
    end

    local currentVisibleIndex = 0
    for i, auraIcon in ipairs(iconList) do
        if auraIcon.frame and auraIcon.frame:IsShown() then
            currentVisibleIndex = currentVisibleIndex + 1
            local row = math.floor((currentVisibleIndex - 1) / iconsPerRow)
            local col = (currentVisibleIndex - 1) % iconsPerRow
            auraIcon.frame:ClearAllPoints()
            
            -- Calculate center X relative to anchor texture's TOPLEFT
            local centerX = framePadding + col * (iconW + framePadding) + (iconW / 2) + BoxxyAuras.Config.Padding
            -- Calculate center Y relative to anchor texture's TOPLEFT
            local centerY = -(framePadding + (iconH / 2) + row * (iconH + framePadding)) - BoxxyAuras.Config.Padding
            
            -- Anchor icon's CENTER to the anchor texture's TOPLEFT with calculated offsets
            auraIcon.frame:SetPoint("CENTER", anchorTexture, "TOPLEFT", centerX, centerY)
        end
    end
end

for pointName, _ in pairs(handlePoints) do
    CreateResizeHandlesForFrame(mainFrame, pointName)
end
UpdateEdgeHandleDimensions(mainFrame, mainFrame:GetSize()) -- Call once after creation with initial size

-- Generalized OnUpdate function for resizing
local function OnDisplayFrameResizeUpdate(frame, elapsed)
    -- Only run logic if we are actively dragging this frame's handle
    if not frame.draggingHandle then return end

    -- Only run resize calculations if the Left Mouse Button is still held down
    if not IsMouseButtonDown("LeftButton") then 
        -- Button was released - OnMouseUp script on handle will finalize
        return 
    end
    
    local minFrameW = 100 -- Min width remains
    local fixedFrameH = frame:GetHeight() -- Use the current fixed height
    
    -- Get padding from config
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or DEFAULT_FRAME_PADDING
    
    -- Use constants for icon size
    local stepWidth = AURA_ICON_WIDTH + framePadding -- Width per icon + space
    local minFrameW = stepWidth + (framePadding * 2) -- Min width for 1 icon

    local mouseX, mouseY = GetCursorPosition()
    local deltaX = mouseX - (frame.dragStartX or 0)
    -- No deltaY needed

    local potentialW = 0
    local finalX = frame.frameStartX -- Position only changes when dragging Left handle
    local draggingHandle = frame.draggingHandle

    -- Calculate potential new width based on the handle being dragged
    if draggingHandle == "Right" then
        potentialW = frame.frameStartW + deltaX
    elseif draggingHandle == "Left" then
        potentialW = frame.frameStartW - deltaX
        finalX = frame.frameStartX + deltaX
    else
        return -- Should not happen with only Left/Right handles
    end

    -- Snap width calculation
    -- Calculate how many icons should fit based on potential width
    local numIconsFit = math.max(1, math.floor((potentialW - framePadding) / stepWidth)) 
    -- Calculate the exact width needed for that many icons + padding
    local snappedW = framePadding + numIconsFit * stepWidth + BoxxyAuras.Config.IconSize / 2 + numIconsFit * BoxxyAuras.Config.Padding
    -- Ensure minimum width
    snappedW = math.max(minFrameW, snappedW)

    -- Adjust X position if dragging left handle and width changed due to snap
    if draggingHandle == "Left" then
        finalX = frame.frameStartX + frame.frameStartW - snappedW
    end

    local currentW, currentH = frame:GetSize()
    local currentX, currentY = frame:GetLeft(), frame:GetTop()
    
    -- Only apply changes if dimensions or position actually changed
    local needsUpdate = (snappedW ~= currentW or finalX ~= currentX)
    if needsUpdate then
        frame:SetSize(snappedW, fixedFrameH) -- Apply snapped width and fixed height
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", finalX, frame.frameStartY) -- Keep original Y
        UpdateEdgeHandleDimensions(frame, snappedW, fixedFrameH) -- Update handles for THIS frame
    end
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
    for _, icon in ipairs(buffIcons) do icon.frame:Hide() end
    for _, icon in ipairs(debuffIcons) do icon.frame:Hide() end

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
    local function sortByStartTime(a, b)
        local aIsPermanent = (a.duration or 0) == 0
        local bIsPermanent = (b.duration or 0) == 0
        if aIsPermanent and not bIsPermanent then return true end 
        if not aIsPermanent and bIsPermanent then return false end
        if aIsPermanent and bIsPermanent then return a.auraInstanceID < b.auraInstanceID end 
        local aStart = (a.expirationTime or 0) - (a.duration or 0)
        local bStart = (b.expirationTime or 0) - (b.duration or 0)
        return aStart < bStart
    end
    table.sort(currentBuffs, sortByStartTime)
    table.sort(currentDebuffs, sortByStartTime)

    -- 4. Populate tracked cache (copy sorted data)
    for _, auraData in ipairs(currentBuffs) do table.insert(trackedBuffs, auraData) end
    for _, auraData in ipairs(currentDebuffs) do table.insert(trackedDebuffs, auraData) end

    -- 5. Create/Update Icon Objects based on tracked cache
    for i, auraData in ipairs(trackedBuffs) do
        local auraIcon = buffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(buffDisplayFrame, i, "BoxxyAurasBuffIcon")
            buffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HELPFUL")
        auraIcon.frame:Show() 
    end
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffDisplayFrame, i, "BoxxyAurasDebuffIcon")
            debuffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HARMFUL")
        auraIcon.frame:Show()
    end

    -- 6. Hide any potentially leftover icons 
    for i = #trackedBuffs + 1, #buffIcons do buffIcons[i].frame:Hide() end
    for i = #trackedDebuffs + 1, #debuffIcons do debuffIcons[i].frame:Hide() end

    -- 7. Layout the visible icons for BOTH frames
    LayoutAuras(buffDisplayFrame, buffIcons) 
    LayoutAuras(debuffDisplayFrame, debuffIcons)

    -- 8. Layout -- REMOVED Redundant Call
    -- LayoutAuras(buffFrame, buffIcons)

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

    -- Get hover states for BOTH frames using polling function
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
            table.insert(newTrackedBuffs, trackedAura)
        else -- Not seen: Expired or Removed
            -- Use buff frame hover state here
            if isHoveringBuffs then
                table.insert(newTrackedBuffs, trackedAura) -- Keep if hovering BUFF frame
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
            table.insert(newTrackedDebuffs, trackedAura)
        else -- Not seen: Expired or Removed
             -- Use debuff frame hover state here
            if isHoveringDebuffs then
                table.insert(newTrackedDebuffs, trackedAura) -- Keep if hovering DEBUFF frame
            else
                 -- Aura is gone AND we are not hovering, remove from cache if present
                if trackedAura.spellId and BoxxyAuras.AllAuras[trackedAura.spellId] then
                    BoxxyAuras.AllAuras[trackedAura.spellId] = nil
                end
            end
             -- If not seen and not hovering, implicitly dropped from tracked list
        end
    end

    -- 5. Append New Auras & Trigger Scrape if needed
    for _, newAura in ipairs(newBuffsToAdd) do 
        table.insert(newTrackedBuffs, newAura)
        local key = newAura.spellId -- Use spellId as the key
        -- Check if not already successfully scraped (key doesn't exist in AllAuras)
        if key and not BoxxyAuras.AllAuras[key] then 
            -- Schedule scrape using spellId, instanceId, and filter
            C_Timer.After(0.01, function() 
                BoxxyAuras.AttemptTooltipScrape(key, newAura.auraInstanceID, "HELPFUL") 
            end)
        end
    end
    for _, newAura in ipairs(newDebuffsToAdd) do 
        table.insert(newTrackedDebuffs, newAura) 
        local key = newAura.spellId -- Use spellId as the key
        -- Check if not already successfully scraped (key doesn't exist in AllAuras)
        if key and not BoxxyAuras.AllAuras[key] then 
            -- Schedule scrape using spellId, instanceId, and filter
            C_Timer.After(0.01, function() 
                BoxxyAuras.AttemptTooltipScrape(key, newAura.auraInstanceID, "HARMFUL") 
            end)
        end
    end

    -- 6. Replace Cache
    trackedBuffs = newTrackedBuffs
    trackedDebuffs = newTrackedDebuffs

    -- 7. Update Visual Icons based on final TRACKED cache
    for i, auraData in ipairs(trackedBuffs) do
        local auraIcon = buffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(buffDisplayFrame, i, "BoxxyAurasBuffIcon")
            buffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HELPFUL")
        auraIcon.frame:Show() 
    end
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffDisplayFrame, i, "BoxxyAurasDebuffIcon")
            debuffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HARMFUL")
        auraIcon.frame:Show()
    end

    -- 8. Hide Leftover Visual Icons
    for i = #trackedBuffs + 1, #buffIcons do 
        if buffIcons[i] and buffIcons[i].frame then buffIcons[i].frame:Hide() end
    end
    for i = #trackedDebuffs + 1, #debuffIcons do 
        if debuffIcons[i] and debuffIcons[i].frame then debuffIcons[i].frame:Hide() end
    end

    -- 9. Layout BOTH frames
    LayoutAuras(buffDisplayFrame, buffIcons)
    LayoutAuras(debuffDisplayFrame, debuffIcons)

    C_Timer.After(0.05, function() 
        BoxxyAuras.UpdateAuras() -- Pass true to indicate it's from OnLeave
    end)
end

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN") 
eventFrame:RegisterEvent("UNIT_AURA")
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
        local defaultBuffFrameSettings = {
            x = -150,
            y = 150,
            anchor = "CENTER",
            width = defaultWidth, -- Use calculated default width
            height = minRequiredHeight -- Use calculated MINIMUM height
        }
        local defaultDebuffFrameSettings = {
            x = 150,
            y = 150,
            anchor = "CENTER",
            width = defaultWidth, -- Use calculated default width
            height = minRequiredHeight -- Use calculated MINIMUM height
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
            end
            -- Ensure all keys exist
            for key, defaultValue in pairs(defaults) do
                if BoxxyAurasDB[dbKey][key] == nil then
                    BoxxyAurasDB[dbKey][key] = defaultValue
                end
            end
            return BoxxyAurasDB[dbKey]
        end
        
        local buffSettings = InitializeSettings("buffFrameSettings", defaultBuffFrameSettings)
        local debuffSettings = InitializeSettings("debuffFrameSettings", defaultDebuffFrameSettings)

        -- Load and Apply Settings Function
        local function ApplySettings(frame, settings, frameDesc)
            -- Get padding from config or use default
            local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or DEFAULT_FRAME_PADDING
            
            -- Snap saved width to nearest icon multiple
            local savedWidth = settings.width
            local stepWidth = AURA_ICON_WIDTH + framePadding
            local minFrameW = stepWidth + (framePadding * 2) -- Ensure at least one icon fits
            
            local usableWidth = savedWidth - (framePadding * 2)
            local numIconsFit = math.max(1, math.floor((usableWidth + framePadding) / stepWidth))
            local snappedUsableW = numIconsFit * stepWidth - framePadding
            local snappedWidth = math.max(minFrameW, snappedUsableW + (framePadding * 2))
            
            -- Use saved height (or default min height) initially
            local initialHeight = settings.height 
            
            print(string.format("BoxxyAuras: Loading %s Settings (Anchor: %s, X: %.1f, Y: %.1f, SavedW: %.1f -> SnappedW: %.1f, InitialH: %.1f)", 
                frameDesc, settings.anchor, settings.x, settings.y, savedWidth, snappedWidth, initialHeight))
            
            frame:SetSize(snappedWidth, initialHeight) -- Apply snapped width and initial height
            frame:ClearAllPoints()
            if settings.anchor == "CENTER" then
                frame:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
            else -- Assume TOPLEFT 
                 frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.x, settings.y)
            end
            -- UpdateEdgeHandleDimensions(frame, settings.width, settings.height) -- Call later when handles exist
            -- LayoutAuras(frame, ...) -- Call later when icons exist
        end
        
        ApplySettings(buffDisplayFrame, buffSettings, "Buff Frame")
        ApplySettings(debuffDisplayFrame, debuffSettings, "Debuff Frame")

        -- Initialize Handles (after setting size/pos)
        CreateResizeHandlesForFrame(buffDisplayFrame, "BuffFrame") 
        CreateResizeHandlesForFrame(debuffDisplayFrame, "DebuffFrame") 
        UpdateEdgeHandleDimensions(buffDisplayFrame, buffSettings.width, buffSettings.height)
        UpdateEdgeHandleDimensions(debuffDisplayFrame, debuffSettings.width, debuffSettings.height)
        
        -- Setup Display Frames visuals AFTER settings applied
        BoxxyAuras.SetupDisplayFrame(buffDisplayFrame, "BuffFrame")
        BoxxyAuras.SetupDisplayFrame(debuffDisplayFrame, "DebuffFrame")
        
        -- Start polling timers AFTER setup is complete
        C_Timer.NewTicker(0.2, function() BoxxyAuras.PollFrameHoverState(buffDisplayFrame, "Buff Frame") end) 
        C_Timer.NewTicker(0.2, function() BoxxyAuras.PollFrameHoverState(debuffDisplayFrame, "Debuff Frame") end)
        print("BoxxyAuras: Polling timers started.") -- Debug confirmation
        
        -- Schedule Initial Aura Load
        C_Timer.After(0.2, InitializeAuras) 
    elseif event == "UNIT_AURA" and unit == "player" then
        -- Re-enabled: Always schedule update on UNIT_AURA
        -- Wrap the call in an anonymous function to ensure scope
        C_Timer.After(0.1, function() BoxxyAuras.UpdateAuras() end) 
    end
end)

-- New ticker function to update duration displays
local function UpdateAllDurationDisplays()
    local currentTime = GetTime()
    for _, icon in ipairs(buffIcons) do
        icon:UpdateDurationDisplay(currentTime)
    end
    for _, icon in ipairs(debuffIcons) do
        icon:UpdateDurationDisplay(currentTime)
    end
end

-- Create a ticker to call the new duration update function
C_Timer.NewTicker(0.25, UpdateAllDurationDisplays) -- Increased interval from 0.1

-- Re-enabled Generalized polling function for mouse hover state 
BoxxyAuras.PollFrameHoverState = function(frame, frameDesc) -- Make it part of the addon table
    if not frame then return end -- Safety check
    
    local mouseIsOverNow = BoxxyAuras.IsMouseWithinFrame(frame)
    local wasOver = frame.isMouseOver -- Read/Write state from frame object
    
    if mouseIsOverNow ~= wasOver then
        -- State changed
        frame.isMouseOver = mouseIsOverNow -- Update the state ON THE FRAME
        
        if not mouseIsOverNow and wasOver then
            -- Changed from true (over) to false (not over)
            -- print(string.format("DEBUG Poll: Mouse left %s, scheduling UpdateAuras for cleanup.", frameDesc))
            -- Schedule the standard update; it will see the new hover state
            C_Timer.After(0.05, BoxxyAuras.UpdateAuras) -- Call the public function
        end
        
        -- Update visual hover effect for THIS frame
        local cfgBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
        local cfgHover = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
        local backdropGroupName = "backdrop" -- Assuming this is the correct group name
        
        -- DEBUG: Check if the texture group exists before coloring
        if frame and frame.backdropTextures then
            -- print(string.format("DEBUG Poll: Found backdropTextures for %s (Type: %s)", frameDesc, type(frame.backdropTextures)))
        else
             print(string.format("|cffFF0000DEBUG Poll Error:|r backdropTextures NOT FOUND for %s! Frame Type: %s", frameDesc, type(frame)))
             -- Optionally skip coloring if group not found to avoid errors, though error indicates deeper issue
             -- return 
        end
        
        if mouseIsOverNow and not frame.draggingHandle then 
             BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, backdropGroupName, cfgHover.r, cfgHover.g, cfgHover.b, cfgHover.a)
        else 
             BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, backdropGroupName, cfgBGN.r, cfgBGN.g, cfgBGN.b, cfgBGN.a)
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
                -- else
                    -- Optional: Log skipped line
                    -- print(string.format("DEBUG Scrape: Skipping line containing 'remaining': %s", lineText))
                end
            end
        end
    end

    -- Store tooltip lines if found using spellId as key
    if spellId and #tooltipLines > 0 then
        -- Store name and lines in a sub-table
        BoxxyAuras.AllAuras[spellId] = { 
            name = spellNameFromTip or ("SpellID: " .. spellId), -- Fallback if name wasn't extracted
            lines = tooltipLines 
        }
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

    -- DEBUG: Check label creation and frameName
    print(string.format("DEBUG SetupDisplayFrame: Frame='%s', Name='%s', LabelText='%s', TitleLabelObj=%s",
        frame:GetName() or "N/A", tostring(frameName), tostring(labelText), tostring(titleLabel)))

    if titleLabel then
        -- Anchor the label's bottom-left to the frame's top-left, placing it above the frame
        titleLabel:ClearAllPoints() -- Clear previous points just in case
        titleLabel:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2) -- (0, 2) adds 2px vertical space above
        titleLabel:SetJustifyH("LEFT")
        titleLabel:SetTextColor(1, 1, 1, 0.9) -- White, slightly transparent
        titleLabel:SetText(labelText)
        frame.titleLabel = titleLabel -- Store reference if needed

        -- DEBUG: Check visibility and alpha after setting text
        print(string.format("DEBUG SetupDisplayFrame: Label '%s' IsShown=%s, Alpha=%.2f",
            titleLabel:GetName(), tostring(titleLabel:IsShown()), titleLabel:GetAlpha()))
    else
        -- This error would print if CreateFontString failed
        print(string.format("|cffFF0000DEBUG SetupDisplayFrame Error:|r Failed to create TitleLabel for Frame='%s', Name='%s'",
            frame:GetName() or "N/A", tostring(frameName)))
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Reset dragging handle state when frame drag stops
        self.draggingHandle = nil 
        
        -- Save new position (width/height saved on handle release)
        local finalX, finalY = self:GetLeft(), self:GetTop()
        -- Determine the correct DB key based on the frame being dragged
        local dbKey = nil
        if self == buffDisplayFrame then -- Use global buffDisplayFrame
            dbKey = "buffFrameSettings"
        elseif self == debuffDisplayFrame then -- Use global debuffDisplayFrame
            dbKey = "debuffFrameSettings"
        end
        
        if dbKey and BoxxyAurasDB and BoxxyAurasDB[dbKey] then
            BoxxyAurasDB[dbKey].x = finalX
            BoxxyAurasDB[dbKey].y = finalY
            BoxxyAurasDB[dbKey].anchor = "TOPLEFT" -- Assume TOPLEFT after drag
            print(string.format("BoxxyAuras: Saved %s Drag Position (X:%.1f, Y:%.1f)", dbKey, finalX, finalY))
        end

        -- ADDED: Final layout update after frame drag finishes using GLOBAL lists/function
        local iconList = nil
        if self == buffDisplayFrame then -- Use global buffDisplayFrame/buffIcons
            iconList = buffIcons
        elseif self == debuffDisplayFrame then -- Use global debuffDisplayFrame/debuffIcons
            iconList = debuffIcons
        end
        
        -- Call the GLOBAL LayoutAuras function
        if iconList then
            LayoutAuras(self, iconList) 
        end
    end)
    frame:SetClampedToScreen(true)
end 