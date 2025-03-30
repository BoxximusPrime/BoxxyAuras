local ADDON_NAME, Addon = ... -- Get addon name and private table
Addon.AllAuras = {} -- Global cache for aura info

-- Configuration Table
Addon.Config = {
    BackgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.9 }, -- Icon Background
    BorderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },      -- Icon Border
    MainFrameBGColorNormal = { r = 0.7, g = 0.7, b = 0.7, a = 0.2 }, -- Main frame normal BG
    MainFrameBGColorHover = { r = 0.7, g = 0.7, b = 0.7, a = 0.6 }, -- Main frame hover BG
    -- Add more options here later if needed
}

-- Function to check if mouse cursor is within a frame's bounds
function Addon.IsMouseWithinFrame(frame)
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
Addon.UIUtils.DrawSlicedBG(mainFrame, "MainFrameHoverBG", "backdrop", 0)
Addon.UIUtils.DrawSlicedBG(mainFrame, "EdgedBorder", "border", 0)

-- Set initial colors using config
local cfgMainBGN = (Addon.Config and Addon.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
local cfgMainHover = (Addon.Config and Addon.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
local cfgMainBorder = (Addon.Config and Addon.Config.BorderColor) or { r = 0.5, g = 0.5, b = 0.5, a = 1.0 } -- Assuming shared border color for now

Addon.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainBGN.r, cfgMainBGN.g, cfgMainBGN.b, cfgMainBGN.a)
Addon.UIUtils.ColorBGSlicedFrame(mainFrame, "border", cfgMainBorder.r, cfgMainBorder.g, cfgMainBorder.b, cfgMainBorder.a)

mainFrame.isHovered = false -- Track hover state (Used for visual hover effect)
Addon.isMouseOverMainFrame = false -- Track state for cleanup logic

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
        print("LayoutAuras: No buff icons found to get dimensions from.")
        return 
    end 
    
    local iconW, iconH = buffIcons[1].frame:GetSize()
    local buffContainerW = buffFrame:GetWidth()
    local debuffContainerW = debuffFrame:GetWidth()
    local buffsPerRow = math.max(1, math.floor(buffContainerW / (iconW + iconSpacing)))
    local debuffsPerRow = math.max(1, math.floor(debuffContainerW / (iconW + iconSpacing)))
    -- print(string.format("LayoutAuras: BuffContW=%.1f, DebuffContW=%.1f, IconsPerRow Buffs=%d, Debuffs=%d", 
    --     buffContainerW, debuffContainerW, buffsPerRow, debuffsPerRow))

    -- Layout Buffs
    local buffCount = 0
    for i, auraIcon in ipairs(buffIcons) do
        if auraIcon.frame:IsShown() then
            -- print(string.format("LayoutAuras: Positioning Buff %d", i))
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
            -- print(string.format("LayoutAuras: Positioning Debuff %d", i))
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
    print("BoxxyAuras: InitializeAuras Running...")
    -- API Check
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        print("|cffff0000BoxxyAuras Error: C_UnitAuras Slot API not ready during Initialize!|r")
        return 
    end

    local AuraIcon = Addon.AuraIcon
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
    print(string.format("InitializeAuras: Fetched %d buffs, %d debuffs.", #currentBuffs, #currentDebuffs))

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
    print("InitializeAuras: Updating Buff Icons...")
    for i, auraData in ipairs(trackedBuffs) do
        local auraIcon = buffIcons[i]
        if not auraIcon then
            print(string.format("- Creating Buff Icon %d for %s", i, auraData.name or "??"))
            auraIcon = AuraIcon.New(buffFrame, i, "BoxxyAurasBuffIcon")
            buffIcons[i] = auraIcon
        else
            print(string.format("- Updating Buff Icon %d for %s", i, auraData.name or "??"))
        end
        auraIcon:Update(auraData, i, "HELPFUL")
    end
    print("InitializeAuras: Updating Debuff Icons...")
     for i, auraData in ipairs(trackedDebuffs) do
        local auraIcon = debuffIcons[i]
        if not auraIcon then
            print(string.format("- Creating Debuff Icon %d for %s", i, auraData.name or "??"))
            auraIcon = AuraIcon.New(debuffFrame, i, "BoxxyAurasDebuffIcon")
            debuffIcons[i] = auraIcon
        else
            print(string.format("- Updating Debuff Icon %d for %s", i, auraData.name or "??"))
        end
        auraIcon:Update(auraData, i, "HARMFUL")
    end

    -- 6. Hide any potentially leftover icons 
    print("InitializeAuras: Hiding leftover icons...")
    for i = #trackedBuffs + 1, #buffIcons do buffIcons[i].frame:Hide() end
    for i = #trackedDebuffs + 1, #debuffIcons do debuffIcons[i].frame:Hide() end

    -- 7. Layout the visible icons
    print("InitializeAuras: Calling LayoutAuras...")
    LayoutAuras()
    -- DEBUG: Check visibility after layout
    if buffIcons[1] and buffIcons[1].frame then
        print("InitializeAuras: First buff icon visible state: " .. tostring(buffIcons[1].frame:IsShown()))
    end
    print("BoxxyAuras: InitializeAuras Complete.")
end

-- Function to update displayed auras using cache comparison and stable order
local function UpdateAuras() -- Removed forceNoHover parameter
    -- API Check
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        return 
    end
    local AuraIcon = Addon.AuraIcon
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

    local isHovering = Addon.IsMouseWithinFrame(mainFrame)
    -- REMOVED: forceNoHover override logic
    --[[ 
    if forceNoHover then
        print("DEBUG UpdateAuras: Forcing isHovering to false due to OnLeave trigger.")
        isHovering = false 
    end
    ]]
    
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
            end
            -- If not seen and not hovering, implicitly dropped
        end
    end
    local newTrackedDebuffs = {}
    for _, trackedAura in ipairs(trackedDebuffs) do
        if trackedAura.seen then
            table.insert(newTrackedDebuffs, trackedAura)
        else
            if isHovering then
                table.insert(newTrackedDebuffs, trackedAura)
            end
        end
    end

    -- 5. Append New Auras & Trigger Scrape if needed
    for _, newAura in ipairs(newBuffsToAdd) do 
        table.insert(newTrackedBuffs, newAura)
        local key = newAura.spellId -- Use spellId as the key
        -- Check if not already successfully scraped (key doesn't exist in AllAuras)
        if key and not Addon.AllAuras[key] then 
            print(string.format("DEBUG UpdateAuras: Scheduling scrape for new buff key: %s (InstanceID: %s)", tostring(key), tostring(newAura.auraInstanceID))) -- DEBUG
            -- Schedule scrape using spellId, instanceId, and filter
            C_Timer.After(0.01, function() 
                Addon.AttemptTooltipScrape(key, newAura.auraInstanceID, "HELPFUL") 
            end)
        end
    end
    for _, newAura in ipairs(newDebuffsToAdd) do 
        table.insert(newTrackedDebuffs, newAura) 
        local key = newAura.spellId -- Use spellId as the key
        -- Check if not already successfully scraped (key doesn't exist in AllAuras)
        if key and not Addon.AllAuras[key] then 
            -- Addon.AllAuras[key] = { pending = true } -- REMOVED: No longer using pending state
             print(string.format("DEBUG UpdateAuras: Scheduling scrape for new debuff key: %s (InstanceID: %s)", tostring(key), tostring(newAura.auraInstanceID))) -- DEBUG
             -- Schedule scrape using spellId, instanceId, and filter
            C_Timer.After(0.01, function() 
                Addon.AttemptTooltipScrape(key, newAura.auraInstanceID, "HARMFUL") 
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
        print("EVENT: PLAYER_LOGIN - Scheduling Initial Aura Load") 
        C_Timer.After(0.2, InitializeAuras) 
    elseif event == "UNIT_AURA" and unit == "player" then
        -- Re-enabled: Always schedule update on UNIT_AURA
        C_Timer.After(0.1, UpdateAuras)
        -- print("EVENT: UNIT_AURA (player) - Ignored during cache build") -- Removed message
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
    local currentlyOver = Addon.IsMouseWithinFrame(mainFrame)
    if currentlyOver ~= mainFrame.isHovered then
        mainFrame.isHovered = currentlyOver -- Update stored state
        local cfgMainBGN = (Addon.Config and Addon.Config.MainFrameBGColorNormal) or { r = 0.1, g = 0.1, b = 0.1, a = 0.85 }
        local cfgMainHover = (Addon.Config and Addon.Config.MainFrameBGColorHover) or { r = 0.2, g = 0.2, b = 0.2, a = 0.90 }
        
        if currentlyOver and not draggingHandle then -- Only apply hover color if not dragging a handle
            Addon.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainHover.r, cfgMainHover.g, cfgMainHover.b, cfgMainHover.a)
        else -- Apply normal color if not over, or if dragging
            Addon.UIUtils.ColorBGSlicedFrame(mainFrame, "backdrop", cfgMainBGN.r, cfgMainBGN.g, cfgMainBGN.b, cfgMainBGN.a)
        end
    end
end

-- Create a ticker for the main frame hover check
C_Timer.NewTicker(0.15, CheckMainFrameHover)

-- Polling function for mouse hover state and cleanup trigger
function Addon.PollMouseOverState()
    local mouseIsOverNow = Addon.IsMouseWithinFrame(mainFrame)
    
    if mouseIsOverNow ~= Addon.isMouseOverMainFrame then
        -- State changed
        local wasOver = Addon.isMouseOverMainFrame
        Addon.isMouseOverMainFrame = mouseIsOverNow -- Update the state
        
        if not mouseIsOverNow and wasOver then
            -- Changed from true (over) to false (not over)
            print("DEBUG Poll: Mouse left frame, scheduling UpdateAuras for cleanup.")
            -- Schedule the standard update; it will see isHovering is false
            C_Timer.After(0.05, UpdateAuras) 
        end
    end
end

-- Start the polling timer
C_Timer.NewTicker(0.2, Addon.PollMouseOverState) -- Check every 0.2 seconds

-- #region Debug Frame Setup
local debugFrame = CreateFrame("Frame", "BoxxyAurasDebugFrame", UIParent, "BackdropTemplate")
debugFrame:SetSize(400, 300)
debugFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -150)
debugFrame:SetClampedToScreen(true)
debugFrame:SetMovable(true)
debugFrame:EnableMouse(true)
debugFrame:RegisterForDrag("LeftButton")
debugFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
debugFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
debugFrame:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background", 
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border", 
    tile = true, tileSize = 32, edgeSize = 32, 
    insets = { left = 11, right = 12, top = 12, bottom = 11 } 
})
debugFrame:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
debugFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
debugFrame:Show() -- Show by default

local debugTitle = debugFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
debugTitle:SetPoint("TOP", debugFrame, "TOP", 0, -15)
debugTitle:SetText("BoxxyAuras Cache Debug")

-- Create a single FontString for all text
local debugTextDisplay = debugFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
debugTextDisplay:SetPoint("TOPLEFT", debugTitle, "BOTTOMLEFT", 0, -10) -- Anchor below title
debugTextDisplay:SetPoint("BOTTOMRIGHT", debugFrame, "BOTTOMRIGHT", -15, 85) -- Anchor near test button area
debugTextDisplay:SetJustifyH("LEFT")
debugTextDisplay:SetJustifyV("TOP")
debugTextDisplay:SetTextColor(1, 1, 1, 1)
debugTextDisplay:SetWordWrap(true) -- Enable word wrap

-- #region Test Button Elements
local testInputYOffset = - (debugFrame:GetHeight() - 70) -- Position near bottom

-- Spell Name Input
local debugSpellNameLabel = debugFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
debugSpellNameLabel:SetPoint("TOPLEFT", debugTextDisplay, "BOTTOMLEFT", 0, -10) -- Re-anchor below text display
debugSpellNameLabel:SetText("Spell Name:")

local debugSpellNameInput = CreateFrame("EditBox", "BoxxyDebugSpellNameInput", debugFrame, "InputBoxTemplate")
debugSpellNameInput:SetSize(180, 32)
debugSpellNameInput:SetPoint("LEFT", debugSpellNameLabel, "RIGHT", 5, 0)
debugSpellNameInput:SetTextInsets(5, 5, 5, 5)
debugSpellNameInput:SetAutoFocus(false)
debugSpellNameInput:SetText("Arcane Intellect") -- Default value
debugSpellNameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
debugSpellNameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Filter Input
local debugFilterLabel = debugFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
debugFilterLabel:SetPoint("TOPLEFT", debugSpellNameLabel, "BOTTOMLEFT", 0, -15)
debugFilterLabel:SetText("Filter (H/F):")

local debugFilterInput = CreateFrame("EditBox", "BoxxyDebugFilterInput", debugFrame, "InputBoxTemplate")
debugFilterInput:SetSize(80, 32)
debugFilterInput:SetPoint("LEFT", debugFilterLabel, "RIGHT", 5, 0)
debugFilterInput:SetTextInsets(5, 5, 5, 5)
debugFilterInput:SetAutoFocus(false)
debugFilterInput:SetText("HELPFUL") -- Default value
debugFilterInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
debugFilterInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Test Button
local debugTestButton = CreateFrame("Button", "BoxxyDebugTestButton", debugFrame, "UIPanelButtonTemplate")
debugTestButton:SetSize(100, 25)
debugTestButton:SetPoint("TOPRIGHT", debugFrame, "BOTTOMRIGHT", -15, -15) -- Anchor to main debug frame bottom right
debugTestButton:SetText("Test Aura")

-- Test Function (Adapted from /script)
function Addon.TestGetUnitAura(spellName, filter)
    if not spellName or spellName == "" then 
        print("|cffFF0000Error:|r Please enter a Spell Name.")
        return
    end
    local upperFilter = string.upper(filter or "")
    if upperFilter ~= "HELPFUL" and upperFilter ~= "HARMFUL" then
        print("|cffFF0000Error:|r Filter must be HELPFUL or HARMFUL.")
        return
    end

    local foundIndex = nil
    print(string.format("Testing: Searching for '%s' with filter '%s'...", spellName, upperFilter))
    for i = 1, 40 do 
        local d = C_UnitAuras.GetAuraDataByIndex("player", i, upperFilter)
        if d and d.name == spellName then 
            foundIndex = i
            print(string.format("Found '%s' at index: %d", spellName, i))
            break
        end 
    end 

    if foundIndex then 
        print(string.format("Attempting C_TooltipInfo.GetUnitAura('player', %d, '%s')...", foundIndex, upperFilter))
        local data = C_TooltipInfo.GetUnitAura("player", foundIndex, upperFilter)
        if data then 
            print(string.format("|cff00FF00Success!|r Got data for index %d", foundIndex))
            for k,v in pairs(data) do 
                if k ~= 'lines' then
                   print("  ", k, ":", tostring(v))
                end
            end
            if data.lines then 
                print("--- Tooltip Lines ---")
                for idx,line in ipairs(data.lines) do 
                     local left = line and line.leftText or "nil"
                     local right = line and line.rightText or "nil"
                     print(string.format("  Line %d: L='%s' | R='%s'", idx, tostring(left), tostring(right)))
                end 
                 print("---------------------")
            else
                 print("  (No 'lines' table found in data)")
            end
        else 
            print(string.format("|cffFF0000Failure!|r C_TooltipInfo.GetUnitAura failed for index %d", foundIndex))
        end 
    else 
        print(string.format("|cffFF0000Error:|r Could not find '%s' with filter '%s' on player.", spellName, upperFilter))
    end
end

-- Button OnClick Script
debugTestButton:SetScript("OnClick", function()
    local name = debugSpellNameInput:GetText()
    local filter = debugFilterInput:GetText()
    Addon.TestGetUnitAura(name, filter)
end)
-- #endregion Test Button Elements

function Addon.UpdateDebugDisplay()
    if not debugFrame or not debugFrame:IsVisible() then return end
    print("DEBUG Display: UpdateDebugDisplay called (Single Text Mode).") 

    -- Check debugTextDisplay state
    if not debugTextDisplay then
        print("DEBUG Display: Error - debugTextDisplay is nil!")
        return
    end

    local outputText = "" -- Start with an empty string
    local numItems = 0

    -- Build the output string
    for spellId, data in pairs(Addon.AllAuras) do
        numItems = numItems + 1
        if type(data) == "table" and data.name and data.lines then
            -- Add Spell Header
            outputText = outputText .. string.format("|cffFFD700%s|r\n", data.name) -- Add name and newline
            
            -- Add Tooltip Lines (indented)
            if type(data.lines) == "table" and #data.lines > 0 then
                for i, lineText in ipairs(data.lines) do
                    outputText = outputText .. string.format("  %s\n", lineText or "NIL_LINE") -- Indent and add newline
                end
            else
                 outputText = outputText .. "  - Empty Tooltip Data\n" -- Indicate empty
            end
             outputText = outputText .. "\n" -- Add a blank line between entries
        else
            -- Log invalid data structure found in cache
            print(string.format("DEBUG Display: Skipping Item - Invalid data structure in cache for SpellID: %s", tostring(spellId)))
        end
    end

    if numItems == 0 then
         outputText = "Cache is empty."
    end
    
    -- Set the text of the single FontString
    print("DEBUG Display: Setting text for debugTextDisplay.")
    debugTextDisplay:SetText(outputText)
    print("DEBUG Display: Update finished.")

end

-- Slash command handler
SLASH_BOXXYDEBUG1 = "/boxxydebug"
function SlashCmdList.BOXXYDEBUG(msg, editBox)
    local command = strlower(msg or "")
    if command == "toggle" then
        if debugFrame:IsShown() then
            debugFrame:Hide()
            print("BoxxyAuras Debug Frame Hidden.")
        else
            debugFrame:Show()
            Addon.UpdateDebugDisplay() -- Update when showing
            print("BoxxyAuras Debug Frame Shown.")
        end
    elseif command == "update" then
         if debugFrame:IsShown() then
             Addon.UpdateDebugDisplay()
             print("BoxxyAuras Debug Frame Updated.")
         else
             print("BoxxyAuras Debug Frame is hidden. Use '/boxxydebug toggle' to show it first.")
         end
    else
        print("Usage: /boxxydebug [toggle|update]")
    end
end

-- Initial update of the debug frame when UI loads (if shown)
if debugFrame:IsShown() then
    Addon.UpdateDebugDisplay()
end

-- #endregion Debug Frame Setup

print("BoxxyAuras loaded!") 

-- Tooltip Scraping Function (Using GetUnitAura, finds index via auraInstanceID)
function Addon.AttemptTooltipScrape(spellId, targetAuraInstanceID, filter) 
    -- Check if already scraped (key exists in AllAuras) - Use spellId as key
    if spellId and Addon.AllAuras[spellId] then return end 
    -- Validate inputs 
    if not spellId or not targetAuraInstanceID or not filter then 
        print(string.format("DEBUG Scrape Error: Invalid arguments. spellId: %s, instanceId: %s, filter: %s",
            tostring(spellId), tostring(targetAuraInstanceID), tostring(filter)))
        return 
    end

    print(string.format("DEBUG Scrape: Received request for SpellID %s, InstanceID %s (%s)", 
        tostring(spellId), tostring(targetAuraInstanceID), filter)) -- Log received args

    -- Find the CURRENT index for this specific aura instance
    local currentAuraIndex = nil
    print(string.format("DEBUG Scrape: Starting loop to find index for InstanceID %s (%s)...", tostring(targetAuraInstanceID), filter)) -- Log loop start
    for i = 1, 40 do -- Check up to 40 auras (standard limit)
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if auraData then
            -- Log aura found at this index
            print(string.format("  > Index %d: Found Aura '%s' (InstanceID: %s)", i, auraData.name or "N/A", auraData.auraInstanceID or "N/A")) 
            -- Compare instance IDs
            if auraData.auraInstanceID == targetAuraInstanceID then
                currentAuraIndex = i
                print(string.format("    >> MATCH FOUND at index %d for target InstanceID %s", i, tostring(targetAuraInstanceID))) -- Log match
                break
            end
        end
    end
    print("DEBUG Scrape: Loop finished.") -- Log loop end

    -- If we didn't find the aura instance (it might have expired/shifted instantly), abort scrape
    if not currentAuraIndex then
        print(string.format("DEBUG Scrape: Aborted. Could not find current index for InstanceID %s (%s). Aura likely expired.", 
            tostring(targetAuraInstanceID), filter))
        return
    end

    print(string.format("DEBUG Scrape: Attempting GetUnitAura for SpellID: %s (Found Index: %s, Filter: %s) using InstanceID %s", 
        tostring(spellId), tostring(currentAuraIndex), filter, tostring(targetAuraInstanceID)))

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
                table.insert(tooltipLines, lineText)
                print(string.format("  Line %d: %s", i, lineText)) -- Debug print per line
            end
        end
    end

    print(string.format("DEBUG Scrape: Added %d lines for SpellID: %s (Name from tip: %s)", 
        #tooltipLines, tostring(spellId), tostring(spellNameFromTip)))

    -- Store tooltip lines if found using spellId as key
    if spellId and #tooltipLines > 0 then
        -- Store name and lines in a sub-table
        Addon.AllAuras[spellId] = { 
            name = spellNameFromTip or ("SpellID: " .. spellId), -- Fallback if name wasn't extracted
            lines = tooltipLines 
        }
        Addon.UpdateDebugDisplay() -- Update debug frame after successful scrape
    end
end 