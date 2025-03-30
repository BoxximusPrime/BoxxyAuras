local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras.AllAuras = {} -- Global cache for aura info

-- Configuration Table
BoxxyAuras.Config = {
    BackgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }, -- Icon Background
    BorderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },      -- Icon Border
    MainFrameBGColorNormal = { r = 0.7, g = 0.7, b = 0.7, a = 0.2 }, -- Main frame normal BG
    MainFrameBGColorHover = { r = 0.7, g = 0.7, b = 0.7, a = 0.6 }, -- Main frame hover BG
    -- Add more options here later if needed
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
mainFrame:SetSize(300, 100) -- Initial size, can be adjusted
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150) -- Positioned higher up

-- Remove old backdrop setup
--[[ mainFrame:SetBackdrop(
    { ... })
mainFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.85) ]]

-- Draw backdrop and border using new utility functions
BoxxyAuras.UIUtils.DrawSlicedBG(mainFrame, "MainFrameHoverBG", "backdrop", 0)
BoxxyAuras.UIUtils.DrawSlicedBG(mainFrame, "EdgedBorder", "border", 0)

-- Set initial colors using config
local cfgMainBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
local cfgMainHover = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
local cfgMainBorder = (BoxxyAuras.Config and BoxxyAuras.Config.BorderColor) or { r = 0.5, g = 0.5, b = 0.5, a = 1.0 } -- Assuming shared border color for now

BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainBGN.r, cfgMainBGN.g, cfgMainBGN.b, cfgMainBGN.a)
BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "border", cfgMainBorder.r, cfgMainBorder.g, cfgMainBorder.b, cfgMainBorder.a)

mainFrame.isHovered = false -- Track hover state (Used for visual hover effect)
BoxxyAuras.isMouseOverMainFrame = false -- Track state for cleanup logic

mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
mainFrame:SetClampedToScreen(true)

-- Create containers *before* defining LayoutAuras
local buffFrame = CreateFrame("Frame", nil, mainFrame)
buffFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -15)
buffFrame:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -15, -15) 
buffFrame:SetHeight(60)

local debuffFrame = CreateFrame("Frame", nil, mainFrame)
debuffFrame:SetPoint("TOPLEFT", buffFrame, "BOTTOMLEFT", 0, -10)
debuffFrame:SetPoint("TOPRIGHT", buffFrame, "BOTTOMRIGHT", 0, -10)
debuffFrame:SetHeight(60)

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
    TopLeft = {"TOPLEFT", 0, 0},
    Top = {"TOP", 0, 0},
    TopRight = {"TOPRIGHT", 0, 0},
    Left = {"LEFT", 0, 0},
    Right = {"RIGHT", 0, 0},
    BottomLeft = {"BOTTOMLEFT", 0, 0},
    Bottom = {"BOTTOM", 0, 0},
    BottomRight = {"BOTTOMRIGHT", 0, 0},
}

-- Helper function to layout existing icons (Now uses buffIcons/debuffIcons)
local function LayoutAuras()
    if not buffIcons[1] or not buffIcons[1].frame then 
        return 
    end 
    
    local iconW, iconH = buffIcons[1].frame:GetSize()
    local buffContainerW = buffFrame:GetWidth()
    local debuffContainerW = debuffFrame:GetWidth()
    local buffsPerRow = math.max(1, math.floor(buffContainerW / (iconW + iconSpacing)))
    local debuffsPerRow = math.max(1, math.floor(debuffContainerW / (iconW + iconSpacing)))

    -- Layout Buffs
    local buffCount = 0
    for i, auraIcon in ipairs(buffIcons) do
        if auraIcon.frame:IsShown() then
            buffCount = buffCount + 1
            local row = math.floor((buffCount - 1) / buffsPerRow)
            local col = (buffCount - 1) % buffsPerRow
            auraIcon.frame:ClearAllPoints()
            auraIcon.frame:SetPoint("TOPLEFT", buffFrame, "TOPLEFT", col * (iconW + iconSpacing), -row * (iconH + iconSpacing))
        end
    end

    -- Layout Debuffs
    local debuffCount = 0
    for i, auraIcon in ipairs(debuffIcons) do
         if auraIcon.frame:IsShown() then
            debuffCount = debuffCount + 1
            local row = math.floor((debuffCount - 1) / debuffsPerRow)
            local col = (debuffCount - 1) % debuffsPerRow
            auraIcon.frame:ClearAllPoints()
            auraIcon.frame:SetPoint("TOPLEFT", debuffFrame, "TOPLEFT", col * (iconW + iconSpacing), -row * (iconH + iconSpacing))
        end
    end
end

local function CreateResizeHandle(pointName)
    local point, xOff, yOff = unpack(handlePoints[pointName])
    local handle = CreateFrame("Frame", "BoxxyAurasResizeHandle" .. pointName, mainFrame)
    
    -- Determine size based on handle type (restore large edge size logic)
    local isCorner = string.find(pointName, "Left") or string.find(pointName, "Right")
    local isVerticalEdge = pointName == "Left" or pointName == "Right"
    local isHorizontalEdge = pointName == "Top" or pointName == "Bottom"

    local w, h = handleSize, handleSize
    if isHorizontalEdge then
        w = mainFrame:GetWidth() * 0.8
        xOff = 0 -- Center horizontally
    elseif isVerticalEdge then
        h = mainFrame:GetHeight() * 0.8
        yOff = 0 -- Center vertically
    end
    handle:SetSize(w, h)
    handle.pointName = pointName
    
    handle:SetPoint(point, mainFrame, point, xOff, yOff)
    handle:SetFrameLevel(mainFrame:GetFrameLevel() + 10) 
    handle:EnableMouse(true)

    -- Background visual fills the handle frame
    handle.bg = handle:CreateTexture(nil, "BACKGROUND")
    handle.bg:SetAllPoints(true) -- Fill the parent handle frame
    handle.bg:SetColorTexture(0.8, 0.8, 0.8, 0.7) 
    handle.bg:Hide()

    handle:SetScript("OnEnter", function(self)
        self.bg:Show()
        -- Could try setting cursor here, but it's often restricted
    end)

    handle:SetScript("OnLeave", function(self)
        if draggingHandle ~= pointName then
            self.bg:Hide()
        end
    end)

    handle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            draggingHandle = pointName
            dragStartX, dragStartY = GetCursorPosition()
            frameStartW, frameStartH = mainFrame:GetSize()
            frameStartX = mainFrame:GetLeft()
            frameStartY = mainFrame:GetTop()
            self.bg:Show() -- Keep visible while dragging
        end
    end)

    -- OnMouseUp is handled globally below
    handles[pointName] = handle
end

-- New function to resize edge handles (accepts dimensions)
local function UpdateEdgeHandleDimensions(frameW, frameH)
    -- local frameW, frameH = mainFrame:GetSize() -- Use passed args
    for pointName, handle in pairs(handles) do
        local isVerticalEdge = pointName == "Left" or pointName == "Right"
        local isHorizontalEdge = pointName == "Top" or pointName == "Bottom"

        if isHorizontalEdge then
            handle:SetSize(frameW * 0.8, handleSize)
            -- handle:SetPoint... (Commented out)
        elseif isVerticalEdge then
            handle:SetSize(handleSize, frameH * 0.8)
            -- handle:SetPoint... (Commented out)
        end
    end
end

for pointName, _ in pairs(handlePoints) do
    CreateResizeHandle(pointName)
end
UpdateEdgeHandleDimensions(mainFrame:GetSize()) -- Call once after creation with initial size

-- Main frame OnUpdate to handle the resizing logic
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    if not draggingHandle then return end

    if IsMouseButtonDown("LeftButton") then
        local mouseX, mouseY = GetCursorPosition()
        local deltaX = mouseX - dragStartX
        local deltaY = mouseY - dragStartY

        -- Calculate final target dimensions and position
        local finalW, finalH = frameStartW, frameStartH
        local finalX, finalY = frameStartX, frameStartY

        -- Adjust based on handle being dragged
        if string.find(draggingHandle, "Right") then
            finalW = math.max(minFrameW, frameStartW + deltaX)
        elseif string.find(draggingHandle, "Left") then
            finalW = math.max(minFrameW, frameStartW - deltaX)
            finalX = frameStartX + deltaX
            if finalX + finalW > frameStartX + frameStartW then
               finalX = frameStartX + frameStartW - finalW
            end
        end

        if string.find(draggingHandle, "Top") then
            finalH = math.max(minFrameH, frameStartH + deltaY) 
            finalY = frameStartY + deltaY
             local frameBottomY = frameStartY - frameStartH
             if finalY - finalH < frameBottomY then 
                finalH = finalY - frameBottomY
                finalH = math.max(minFrameH, finalH)
                finalY = frameBottomY + finalH
             end
        elseif string.find(draggingHandle, "Bottom") then
            finalH = math.max(minFrameH, frameStartH - deltaY) -- Remember this uses -deltaY
        end

        -- Check if anything actually needs to change
        local currentW, currentH = self:GetSize()
        local currentX, currentY = self:GetLeft(), self:GetTop()
        local needsUpdate = (finalW ~= currentW or finalH ~= currentH or finalX ~= currentX or finalY ~= currentY)

        if needsUpdate then
            -- Apply size change first
            if finalW ~= currentW or finalH ~= currentH then
                self:SetSize(finalW, finalH)
            end

            -- *Always* re-apply position after potential size change
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", finalX, finalY)

            -- Update edge handle dimensions
            UpdateEdgeHandleDimensions(finalW, finalH)

            -- Re-layout auras immediately after resizing
            LayoutAuras()
        end
    else
        -- Button is up, stop dragging
        local stoppedHandle = draggingHandle 
        draggingHandle = nil 
        if handles[stoppedHandle] then
            handles[stoppedHandle].bg:Hide() 
        end
        self:StopMovingOrSizing() 
        -- TODO: Save new size/pos potentially here
        -- local finalW, finalH = self:GetSize()
        -- local finalX, finalY = self:GetLeft(), self:GetTop()
        -- Save finalW, finalH, finalX, finalY in SavedVariables

        -- Final layout update after drag finishes
        LayoutAuras()
    end
end)

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
            auraIcon = AuraIcon.New(buffFrame, i, "BoxxyAurasBuffIcon")
            buffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HELPFUL")
    end
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffFrame, i, "BoxxyAurasDebuffIcon")
            debuffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HARMFUL")
    end

    -- 6. Hide any potentially leftover icons 
    for i = #trackedBuffs + 1, #buffIcons do buffIcons[i].frame:Hide() end
    for i = #trackedDebuffs + 1, #debuffIcons do debuffIcons[i].frame:Hide() end

    -- 7. Layout the visible icons
    LayoutAuras()

    C_Timer.After(0.05, function() 
        UpdateAuras() -- Pass true to indicate it's from OnLeave
    end)
end

-- Function to update displayed auras using cache comparison and stable order
local function UpdateAuras() -- Removed forceNoHover parameter
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

    local isHovering = BoxxyAuras.IsMouseWithinFrame(mainFrame)
    
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
            if isHovering then
                table.insert(newTrackedBuffs, trackedAura) -- Keep if hovering
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
            if isHovering then
                table.insert(newTrackedDebuffs, trackedAura) -- Keep if hovering
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
            auraIcon = AuraIcon.New(buffFrame, i, "BoxxyAurasBuffIcon")
            buffIcons[i] = auraIcon
        end
        auraIcon:Update(auraData, i, "HELPFUL")
        auraIcon.frame:Show() 
    end
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = debuffIcons[i]
        if not auraIcon then
            auraIcon = AuraIcon.New(debuffFrame, i, "BoxxyAurasDebuffIcon")
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

    -- 9. Layout
    LayoutAuras()

    C_Timer.After(0.05, function() 
        UpdateAuras() -- Pass true to indicate it's from OnLeave
    end)
end

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN") 
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    local unit = (...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.2, InitializeAuras) 
    elseif event == "UNIT_AURA" and unit == "player" then
        -- Re-enabled: Always schedule update on UNIT_AURA
        C_Timer.After(0.1, UpdateAuras)
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

-- New function to check and apply main frame hover effect
local function CheckMainFrameHover()
    local currentlyOver = BoxxyAuras.IsMouseWithinFrame(mainFrame)
    if currentlyOver ~= mainFrame.isHovered then
        mainFrame.isHovered = currentlyOver -- Update stored state
        local cfgMainBGN = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
        local cfgMainHover = (BoxxyAuras.Config and BoxxyAuras.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
        
        if currentlyOver and not draggingHandle then -- Only apply hover color if not dragging a handle
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainHover.r, cfgMainHover.g, cfgMainHover.b, cfgMainHover.a)
        else -- Apply normal color if not over, or if dragging
            BoxxyAuras.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainBGN.r, cfgMainBGN.g, cfgMainBGN.b, cfgMainBGN.a)
        end
    end
end

-- Create a ticker for the main frame hover check
C_Timer.NewTicker(0.15, CheckMainFrameHover)

-- Polling function for mouse hover state and cleanup trigger
function BoxxyAuras.PollMouseOverState()
    local mouseIsOverNow = BoxxyAuras.IsMouseWithinFrame(mainFrame)
    
    if mouseIsOverNow ~= BoxxyAuras.isMouseOverMainFrame then
        -- State changed
        local wasOver = BoxxyAuras.isMouseOverMainFrame
        BoxxyAuras.isMouseOverMainFrame = mouseIsOverNow -- Update the state
        
        if not mouseIsOverNow and wasOver then
            -- Changed from true (over) to false (not over)
            C_Timer.After(0.05, UpdateAuras) 
        end
    end
end

-- Start the polling timer
C_Timer.NewTicker(0.2, BoxxyAuras.PollMouseOverState) -- Check every 0.2 seconds

print("BoxxyAuras loaded!") 

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