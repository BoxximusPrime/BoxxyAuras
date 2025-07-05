local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {}       -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras          -- Create a convenient local alias to the global table
BoxxyAuras.FrameHandler = {}
BoxxyAurasDB = BoxxyAurasDB or {}

-- PixelUtil Compatibility Layer
local PixelUtilCompat = {}

-- Standard WoW API fallback functions
local function FallbackSetPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
    frame:SetPoint(point, relativeTo, relativePoint, xOffset or 0, yOffset or 0)
end

local function FallbackSetSize(frame, width, height)
    frame:SetSize(width, height)
end

local function FallbackSetWidth(frame, width)
    frame:SetWidth(width)
end

local function FallbackSetHeight(frame, height)
    frame:SetHeight(height)
end

if PixelUtil then
    -- Use native PixelUtil with error handling - fall back to standard methods if they fail
    function PixelUtilCompat.SetPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
        local success, err = pcall(PixelUtil.SetPoint, frame, point, relativeTo, relativePoint, xOffset, yOffset)
        if not success then
            FallbackSetPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
        end
    end

    function PixelUtilCompat.SetSize(frame, width, height)
        local success, err = pcall(PixelUtil.SetSize, frame, width, height)
        if not success then
            FallbackSetSize(frame, width, height)
        end
    end

    function PixelUtilCompat.SetWidth(frame, width)
        local success, err = pcall(PixelUtil.SetWidth, frame, width)
        if not success then
            FallbackSetWidth(frame, width)
        end
    end

    function PixelUtilCompat.SetHeight(frame, height)
        local success, err = pcall(PixelUtil.SetHeight, frame, height)
        if not success then
            FallbackSetHeight(frame, height)
        end
    end
else
    -- Fallback implementations using standard WoW API
    PixelUtilCompat.SetPoint = FallbackSetPoint
    PixelUtilCompat.SetSize = FallbackSetSize
    PixelUtilCompat.SetWidth = FallbackSetWidth
    PixelUtilCompat.SetHeight = FallbackSetHeight
end

-- SetAllPoints is not part of PixelUtil - it's a standard frame method
function PixelUtilCompat.SetAllPoints(frame, relativeTo)
    frame:SetAllPoints(relativeTo)
end

-- Import LibWindow
local LibWindow = LibStub("LibWindow-1.1")

-- Define constants and shared variables needed by frame functions
local HandleWidth = 12 -- Increased handle size SIGNIFICANTLY for testing

-- =========================================
--       LOCAL HELPER FUNCTIONS (RESIZE - User Provided Version)
-- =========================================

local function HandleOnMouseDown(self, button)
    if BoxxyAuras.DEBUG then
        print("=== RESIZE START === HandleOnMouseDown fired for handle: " .. self:GetName() .. " Button: " .. button)
    end
    -- Check current profile lock state instead of Config.FramesLocked
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    if button == "LeftButton" and not currentSettings.lockFrames then
        local parentFrame = self:GetParent()
        local resizeSide = self.resizeSide

        parentFrame.isResizing = true
        parentFrame.pendingNumIconsWide = nil -- Clear pending count on new drag
        parentFrame.startNumIconsWide = nil   -- Clear start count on new drag

        if BoxxyAuras.DEBUG then
            print(string.format("Starting resize for %s, side=%s, initial width=%.1f", parentFrame:GetName(),
                resizeSide, parentFrame:GetWidth()))
        end
        local cursorX = GetCursorPosition() / parentFrame:GetEffectiveScale()
        parentFrame.resizeStartX = cursorX
        parentFrame.resizeStartWidth = parentFrame:GetWidth()
        local left, bottom, width, height = parentFrame:GetRect()
        parentFrame.resizeStartLeft = left
        parentFrame.resizeStartBottom = bottom
        parentFrame.resizeStartRight = left + width
        parentFrame.resizeStartTop = bottom + height
        if self.resizeSide == "LEFT" then
            parentFrame.resizeEdgeOffset = cursorX - left
        elseif self.resizeSide == "RIGHT" then
            parentFrame.resizeEdgeOffset = cursorX - (left + parentFrame:GetWidth())
        end
        parentFrame.resizeHandle = self

        -- Inline OnUpdate logic from user snippet
        parentFrame:SetScript("OnUpdate", function(self, elapsed)
            if self.isResizing and self.resizeStartX and self.resizeStartWidth then
                local curX = GetCursorPosition() / self:GetEffectiveScale()
                local deltaX = curX - self.resizeStartX

                -- Get settings and calculate needed dimensions
                local frameType
                for fType, f in pairs(BoxxyAuras.Frames or {}) do
                    if f == self then
                        frameType = fType;
                        break
                    end
                end
                if not frameType then return end

                local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
                if not frameSettings then return end

                local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
                if not currentSettings or not frameSettings then return end

                local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
                local userIconSpacing = frameSettings.iconSpacing
                local baseIconSpacing = userIconSpacing ~= nil and userIconSpacing or
                    (BoxxyAuras.Config.IconSpacing or 6)
                local framePadding = BoxxyAuras.Config.FramePadding or 6
                local internalPadding = BoxxyAuras.Config.Padding or 6
                -- Use user spacing as final value, or add border spacing if using default
                local borderSize = frameSettings.borderSize or 0
                local borderSpacing = BoxxyAuras.FrameHandler.CalculateBorderSpacing(borderSize)
                local iconSpacing = userIconSpacing ~= nil and baseIconSpacing or (baseIconSpacing + borderSpacing)
                local iconWidth = iconSize + (internalPadding * 2)
                local iconSlotWidth = iconWidth + iconSpacing

                -- More direct calculation for new icon count
                local startNumIcons = self.startNumIconsWide or frameSettings.numIconsWide or 1
                if not self.startNumIconsWide then
                    self.startNumIconsWide = startNumIcons
                end

                local iconDelta = 0
                if self.resizeHandle.resizeSide == "RIGHT" then
                    iconDelta = deltaX / iconSlotWidth
                elseif self.resizeHandle.resizeSide == "LEFT" then
                    iconDelta = -deltaX / iconSlotWidth
                end

                local newNumIcons = math.max(1, math.floor(startNumIcons + iconDelta + 0.5))
                newNumIcons = math.min(newNumIcons, 20) -- Cap at a reasonable maximum

                -- Get the last number of icons we snapped to during this drag session
                local lastNumIcons = self.pendingNumIconsWide or startNumIcons

                -- Only fire resize logic if the target number of icons has changed
                if newNumIcons ~= lastNumIcons then
                    if BoxxyAuras.DEBUG then
                        print(string.format("SNAP: %d -> %d icons (deltaX: %.1f, iconDelta: %.2f)", lastNumIcons,
                            newNumIcons, deltaX, iconDelta))
                    end

                    -- Store the new pending icon count. This is crucial to prevent log spam and jitter.
                    self.pendingNumIconsWide = newNumIcons

                    -- Calculate the EXACT width needed for the new number of icons to snap to
                    local calculatedWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(newNumIcons, iconSize,
                        borderSize, frameSettings)

                    -- Set the frame to this exact width to complete the "snap"
                    PixelUtilCompat.SetWidth(self, calculatedWidth)

                    -- Reposition frame to keep the opposite edge stationary
                    local wrapDir = frameSettings.wrapDirection or "DOWN"
                    local newLeft
                    if self.resizeHandle.resizeSide == "LEFT" then
                        newLeft = self.resizeStartRight - calculatedWidth
                    else
                        newLeft = self.resizeStartLeft
                    end

                    if wrapDir == "UP" then
                        if self.resizeHandle.resizeSide == "LEFT" then
                            self:ClearAllPoints()
                            PixelUtilCompat.SetPoint(self, "BOTTOMRIGHT", UIParent, "BOTTOMLEFT",
                                self.resizeStartRight, self.resizeStartBottom)
                        else
                            self:ClearAllPoints()
                            PixelUtilCompat.SetPoint(self, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft,
                                self.resizeStartBottom)
                        end
                    else
                        self:ClearAllPoints()
                        PixelUtilCompat.SetPoint(self, "TOPLEFT", UIParent, "BOTTOMLEFT", newLeft,
                            self.resizeStartTop)
                    end

                    -- Update the aura layout with the new icon count
                    BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType, newNumIcons)
                end
            end
        end)
    end
end

local function HandleOnMouseUp(self, button)
    -- Check current profile lock state instead of Config.FramesLocked
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    if button == "LeftButton" and not currentSettings.lockFrames then
        local parentFrame = self:GetParent()
        if parentFrame.isResizing then
            parentFrame.lastResizeTime = GetTime()
            parentFrame.isResizing = false

            -- Stop the OnUpdate script
            parentFrame:SetScript("OnUpdate", nil)

            -- Reset cursor
            ResetCursor()

            -- Save the FINAL calculated numIconsWide and position
            local frameType = nil
            for fType, f in pairs(BoxxyAuras.Frames or {}) do
                if f == parentFrame then
                    frameType = fType;
                    break
                end
            end

            if frameType then
                local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
                if frameSettings then
                    local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
                    local userIconSpacing = frameSettings.iconSpacing
                    local baseIconSpacing = userIconSpacing ~= nil and userIconSpacing or
                        (BoxxyAuras.Config.IconSpacing or 6)
                    local framePadding = BoxxyAuras.Config.FramePadding or 6
                    local internalPadding = BoxxyAuras.Config.Padding or 6
                    -- Use user spacing as final value, or add border spacing if using default
                    local borderSize = frameSettings.borderSize or 0
                    local borderSpacing = BoxxyAuras.FrameHandler.CalculateBorderSpacing(borderSize)
                    local iconSpacing = userIconSpacing ~= nil and baseIconSpacing or (baseIconSpacing + borderSpacing)
                    local iconWidth = iconSize + (internalPadding * 2)
                    local iconSlotWidth = iconWidth + iconSpacing

                    -- Recalculate final numIcons based on the frame's width *at the end* of the drag
                    local finalWidth = parentFrame:GetWidth()
                    local finalAvailableWidth = finalWidth - (framePadding * 2) + iconSpacing

                    -- Determine final icon count using pending value from drag if available
                    local finalNumIcons = parentFrame.pendingNumIconsWide or
                        math.max(1, math.floor(finalAvailableWidth / iconSlotWidth))
                    parentFrame.pendingNumIconsWide = nil

                    if frameSettings.numIconsWide ~= finalNumIcons then
                        if BoxxyAuras.DEBUG then
                            print(string.format("Saving FINAL numIconsWide for %s: %d (was %d)", frameType,
                                finalNumIcons, frameSettings.numIconsWide or -1))
                        end
                        frameSettings.numIconsWide = finalNumIcons
                    end

                    if BoxxyAuras.DEBUG then
                        local calculatedWidthCheck = BoxxyAuras.FrameHandler.CalculateFrameWidth(finalNumIcons, iconSize,
                            borderSize, frameSettings)
                        print(string.format("Resize END: frame '%s' finalWidth=%.1f, finalNumIcons=%d, calcWidth=%.1f",
                            frameType, finalWidth, finalNumIcons, calculatedWidthCheck))
                    end

                    -- Snap frame width to exact calculated width for finalNumIcons to avoid fractional rounding issues
                    local finalTargetWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(finalNumIcons, iconSize,
                        borderSize, frameSettings)
                    if math.abs(parentFrame:GetWidth() - finalTargetWidth) > 0.5 then
                        PixelUtilCompat.SetWidth(parentFrame, finalTargetWidth)
                    end
                    -- Reposition horizontally based on which handle was dragged to keep opposite edge stationary
                    local wrapDir = frameSettings.wrapDirection or "DOWN"
                    local newLeft
                    if parentFrame.resizeHandle and parentFrame.resizeHandle.resizeSide == "LEFT" then
                        newLeft = parentFrame.resizeStartRight - finalTargetWidth
                    else
                        newLeft = parentFrame.resizeStartLeft
                    end
                    parentFrame:ClearAllPoints()
                    if wrapDir == "UP" then
                        -- keep bottom fixed when wrapping up
                        PixelUtilCompat.SetPoint(parentFrame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft,
                            parentFrame.resizeStartBottom)
                    else
                        -- keep top fixed when wrapping down (default)
                        PixelUtilCompat.SetPoint(parentFrame, "TOPLEFT", UIParent, "BOTTOMLEFT", newLeft,
                            parentFrame.resizeStartTop)
                    end
                end
            end

            -- === Final Layout Update ===
            BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
            -- === End Final Layout ===

            LibWindow.SavePosition(parentFrame) -- Save final position

            -- === Explicitly re-anchor handles to final frame state ===
            if parentFrame.handles and parentFrame.handles.left then
                parentFrame.handles.left:ClearAllPoints()
                parentFrame.handles.left:SetPoint("LEFT", parentFrame, "LEFT", 0, 0)
            end
            if parentFrame.handles and parentFrame.handles.right then
                parentFrame.handles.right:ClearAllPoints()
                parentFrame.handles.right:SetPoint("RIGHT", parentFrame, "RIGHT", 0, 0)
            end
            -- === End re-anchor ===

            -- Reset temporary state vars (ensure they are cleared)
            parentFrame.resizeStartX = nil
            parentFrame.resizeStartWidth = nil
            parentFrame.resizeStartLeft = nil
            parentFrame.resizeStartBottom = nil
            parentFrame.resizeStartTop = nil
            parentFrame.resizeStartRight = nil
            parentFrame.resizeEdgeOffset = nil
            parentFrame.resizeHandle = nil
            parentFrame.startNumIconsWide = nil -- Reset start icons count

            -- Re-add final alpha check for handle
            if self:IsMouseOver() then
                self:SetBackdropColor(1.0, 1.0, 1.0, 0.8) -- Keep lit if mouse still over
            else
                -- self:SetBackdropColor(1.0, 1.0, 1.0, 0.15) -- OLD: Dim if mouse left during drag
                self:SetBackdropColor(1.0, 1.0, 1.0, 0) -- NEW: Make transparent
            end
        end
    end
end

-- =========================================
--          (RE)IMPLEMENTATIONS BELOW
-- =========================================

function BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    if frameType == "Buff" then
        return "buffFrameSettings"
    elseif frameType == "Debuff" then
        return "debuffFrameSettings"
    else
        -- Check if it's a custom frame
        if BoxxyAuras and BoxxyAuras.GetCurrentProfileSettings then
            local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
            if currentSettings.customFrameProfiles and currentSettings.customFrameProfiles[frameType] then
                -- For custom frames, the settings are stored directly in customFrameProfiles[frameType]
                return "customFrameProfiles." .. frameType
            end
        end
        return nil
    end
end

-- Helper function to get the actual settings table for a frame type
function BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not BoxxyAuras or not BoxxyAuras.GetCurrentProfileSettings then
        return nil
    end

    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    if not currentSettings then
        return nil
    end

    if frameType == "Buff" then
        currentSettings.buffFrameSettings = currentSettings.buffFrameSettings or {}
        return currentSettings.buffFrameSettings
    elseif frameType == "Debuff" then
        currentSettings.debuffFrameSettings = currentSettings.debuffFrameSettings or {}
        return currentSettings.debuffFrameSettings
    else
        -- Check if it's a custom frame
        if currentSettings.customFrameProfiles and currentSettings.customFrameProfiles[frameType] then
            return currentSettings.customFrameProfiles[frameType]
        end
        return nil
    end
end

-- Helper to calculate actual visual spacing needed based on border size
function BoxxyAuras.FrameHandler.CalculateBorderSpacing(borderSize)
    if borderSize == 0 then
        return 0 -- No border = no extra spacing
    elseif borderSize == 1 then
        return 1 -- Standard border = 1 pixel spacing
    else
        -- Thick border grows by 2 pixels per size level above 1
        return 1 + (borderSize - 1) * 2 -- size 2 = 3, size 3 = 5, size 4 = 7, etc.
    end
end

-- Calculate Width Helper (Keep this utility)
function BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconSize, borderSize, frameSettings)
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6

    -- Use per-frame spacing if frameSettings provided, otherwise use global config
    local iconSpacing
    if frameSettings and frameSettings.iconSpacing ~= nil then
        -- Use user-defined spacing as final value
        iconSpacing = frameSettings.iconSpacing
    else
        -- Fall back to old behavior (global config + border spacing)
        local baseIconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6
        local borderSpacing = BoxxyAuras.FrameHandler.CalculateBorderSpacing(borderSize or 0)
        iconSpacing = baseIconSpacing + borderSpacing
    end

    local iconW = iconSize + (internalPadding * 2)
    local width = framePadding + (numIconsWide * iconW) + math.max(0, numIconsWide - 1) * iconSpacing + framePadding
    return math.ceil(width)
end

-- Frame Setup
function BoxxyAuras.FrameHandler.SetupDisplayFrame(frameName)
    local frame = CreateFrame("Frame", "BoxxyAuraPanel_" .. frameName, UIParent)
    frame:SetFrameStrata("MEDIUM") -- Explicitly set parent strata

    -- Get the correct settings for this frame type
    local settingsTable = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameName)
    if not settingsTable then
        BoxxyAuras.DebugLogError("Unable to get settings table for frame: " .. tostring(frameName))
        return nil
    end

    -- Migration: Check if position data was saved under the old incorrect key and migrate it
    local oldKey = frameName -- This was the incorrect key used before
    local oldPositionData = BoxxyAurasDB.profiles[BoxxyAurasDB.activeProfile][oldKey]
    if oldPositionData and type(oldPositionData) == "table" then
        -- Check if this looks like LibWindow position data (has x, y, point, etc.)
        if oldPositionData.x or oldPositionData.y or oldPositionData.point then
            if BoxxyAuras.DEBUG then
                print(string.format("Migrating position data from old key '%s' to settings table", oldKey))
            end
            -- Copy position data to the correct location
            for key, value in pairs(oldPositionData) do
                if key == "x" or key == "y" or key == "point" or key == "anchor" or key == "scale" then
                    settingsTable[key] = value
                end
            end
            -- Clean up the old incorrect entry
            BoxxyAurasDB.profiles[BoxxyAurasDB.activeProfile][oldKey] = nil
        end
    end

    -- Calculate frame size based on number of icons and icon size (default border size 0 for setup)
    local frameSize = BoxxyAuras.FrameHandler.CalculateFrameWidth(1, BoxxyAuras.Config.IconSize, 0)
    PixelUtilCompat.SetSize(frame, frameSize, frameSize)
    PixelUtilCompat.SetPoint(frame, "CENTER", UIParent, "CENTER", 0, 0)

    -- Draw frame visuals (Keep this part as it sets up appearance)
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "MainFrameHoverBG", "backdrop", 0)
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "EdgedBorder", "border", 0)
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, BoxxyAuras.Config.HoverBorderTextureKey or "ItemEntryBorder", "hoverBorder", 0)

    -- Set colors
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", BoxxyAuras.Config.MainFrameBGColorNormal)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", BoxxyAuras.Config.BorderColor)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "hoverBorder", 1, 1, 1, 0) -- Start transparent

    -- Create handles
    CreateHandles(frame)

    -- Prepare LibWindow for dragging - use the settings table directly
    LibWindow.RegisterConfig(frame, settingsTable)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    -- Create title label
    local labelText = frameName:gsub("Frame", "") -- Simple label
    local titleLabel = frame:CreateFontString(frameName .. "TitleLabel", "OVERLAY", "GameFontNormalLarge")
    if titleLabel then
        titleLabel:ClearAllPoints()
        titleLabel:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
        titleLabel:SetJustifyH("LEFT")
        titleLabel:SetTextColor(1, 1, 1, 0.9)
        titleLabel:SetText(labelText)
        frame.titleLabel = titleLabel
    end

    -- Register for drag events
    frame:SetScript("OnDragStart", function(self)
        -- Check current lock state before allowing drag
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if not currentSettings.lockFrames then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        -- Only process drag stop if we're actually movable (not locked)
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
        if not currentSettings.lockFrames then
            self:StopMovingOrSizing()
            LibWindow.SavePosition(self)
        end
    end)

    -- Add right-click handler to open options window (only when unlocked)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            -- Check if frames are locked - if so, don't handle the right-click
            local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
            if currentSettings and currentSettings.lockFrames then
                return -- Let the click pass through to whatever is underneath
            end

            if BoxxyAuras.Options and BoxxyAuras.Options.Toggle then
                BoxxyAuras.Options:Toggle()
            end
        end
    end)

    -- Register helper methods.
    function frame:Lock(button)
        -- Set to a semi-transparent red for debugging hitbox visibility
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0, 0, 0, 0)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0, 0, 0, 0) -- Keep border hidden
        if self.titleLabel then
            self.titleLabel:Hide()
        end -- Hide title

        -- Disable all mouse interaction when locked to avoid interfering with other UI elements
        self:SetMovable(false)  -- Disable moving
        self:RegisterForDrag()  -- Clear drag registration
        self:EnableMouse(false) -- Disable mouse completely - no interference with clicks underneath

        -- Also hide handles since they won't be usable
        if self.handles then
            if self.handles.left then
                self.handles.left:Hide()
                self.handles.left:EnableMouse(false) -- Disable mouse on handles too
            end
            if self.handles.right then
                self.handles.right:Hide()
                self.handles.right:EnableMouse(false) -- Disable mouse on handles too
            end
        end
    end

    function frame:Unlock()
        if BoxxyAuras.DEBUG then
            print("Executing frame:Unlock() for " .. self:GetName())
        end
        self:Show()
        if self.titleLabel then
            self.titleLabel:Show()
        end

        -- Apply colors
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", BoxxyAuras.Config.MainFrameBGColorNormal)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", BoxxyAuras.Config.BorderColor) -- Restore border

        -- Re-enable mouse interaction for clicks/drags
        self:SetMovable(true)              -- Re-enable moving
        self:RegisterForDrag("LeftButton") -- Re-register for drag events
        self:EnableMouse(true)             -- Re-enable mouse interaction

        -- Icon frames keep their mouse enabled throughout (for tooltips)

        -- Also show handles and re-enable their mouse interaction
        if self.handles then
            if self.handles.left then
                self.handles.left:Show()
                self.handles.left:EnableMouse(true) -- Re-enable mouse on handles
            end
            if self.handles.right then
                self.handles.right:Show()
                self.handles.right:EnableMouse(true) -- Re-enable mouse on handles
            end
        end
    end

    function frame:SetFrameScale(scale)
        self:SetScale(scale)
    end

    -- Now, load the position if we have it.
    LibWindow.RestorePosition(frame)

    return frame
end

function CreateHandles(frame)
    local FrameHeight = frame:GetHeight()

    -- Store resizing state (keep this part)
    frame.isResizing = false
    frame.resizeStartX = nil
    frame.resizeStartWidth = nil
    frame.resizeHandle = nil
    frame.lastResizeTime = 0

    -- Create handles
    local leftHandle = CreateFrame("Frame", frame:GetName() .. "LeftHandle", frame, "BackdropTemplate")

    if BoxxyAuras.DEBUG then
        print(string.format("CreateHandles (%s) - parentH: %.2f, FrameHeight: %.2f, handleSize: %d", frame:GetName(),
            FrameHeight, FrameHeight, HandleWidth or -1))
    end

    PixelUtilCompat.SetSize(leftHandle, HandleWidth, FrameHeight)
    PixelUtilCompat.SetPoint(leftHandle, "LEFT", frame, "LEFT", 0, 0) -- Corrected anchor
    leftHandle:SetFrameLevel(frame:GetFrameLevel() + 10)              -- Add back frame level
    leftHandle:SetFrameStrata("HIGH")                                 -- Add back strata
    leftHandle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,
        edgeSize = 0,
        insets = {
            left = 0,
            right = 0,
            top = 0,
            bottom = 0
        }
    })
    leftHandle:SetBackdropColor(1.0, 1.0, 1.0, 0)          -- NEW: Start transparent
    leftHandle:EnableMouse(true)
    leftHandle.resizeSide = "LEFT"                         -- Add back resize side
    leftHandle:SetScript("OnMouseDown", HandleOnMouseDown) -- Add back mouse down
    leftHandle:SetScript("OnMouseUp", HandleOnMouseUp)     -- Add back mouse up
    leftHandle:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnEnter: Parent (%s) isLocked=%s, isResizing=%s", self:GetName(), parentName,
                tostring(isLocked), tostring(parent.isResizing)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0.8)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0.8", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked=%s or Parent Resizing=%s)", self:GetName(),
                    tostring(isLocked), tostring(parent.isResizing)))
            end
        end
    end)
    leftHandle:SetScript("OnLeave", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnLeave: Parent (%s) isLocked=%s, isResizing=%s", self:GetName(), parentName,
                tostring(isLocked), tostring(parent.isResizing)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked=%s or Parent Resizing=%s)", self:GetName(),
                    tostring(isLocked), tostring(parent.isResizing)))
            end
        end
    end)

    -- Store handle reference
    if not frame.handles then
        frame.handles = {}
    end
    frame.handles.left = leftHandle

    -- Create right handle
    local rightHandle = CreateFrame("Frame", frame:GetName() .. "RightHandle", frame, "BackdropTemplate")

    if BoxxyAuras.DEBUG then
        print(string.format("CreateHandles (%s) - parentH: %.2f, FrameHeight: %.2f, handleSize: %d", frame:GetName(),
            FrameHeight, FrameHeight, HandleWidth or -1))
    end

    PixelUtilCompat.SetSize(rightHandle, HandleWidth, FrameHeight)
    PixelUtilCompat.SetPoint(rightHandle, "RIGHT", frame, "RIGHT", 0, 0) -- Corrected anchor
    rightHandle:SetFrameLevel(frame:GetFrameLevel() + 10)                -- Add back frame level
    rightHandle:SetFrameStrata("HIGH")                                   -- Add back strata
    rightHandle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,
        edgeSize = 0,
        insets = {
            left = 0,
            right = 0,
            top = 0,
            bottom = 0
        }
    })
    rightHandle:SetBackdropColor(1.0, 1.0, 1.0, 0)          -- NEW: Start transparent
    rightHandle:EnableMouse(true)
    rightHandle.resizeSide = "RIGHT"                        -- Add back resize side
    rightHandle:SetScript("OnMouseDown", HandleOnMouseDown) -- Add back mouse down
    rightHandle:SetScript("OnMouseUp", HandleOnMouseUp)     -- Add back mouse up
    rightHandle:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnEnter: Parent (%s) isLocked=%s, isResizing=%s", self:GetName(), parentName,
                tostring(isLocked), tostring(parent.isResizing)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0.8)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0.8", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked=%s or Parent Resizing=%s)", self:GetName(),
                    tostring(isLocked), tostring(parent.isResizing)))
            end
        end
    end)
    rightHandle:SetScript("OnLeave", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnLeave: Parent (%s) isLocked=%s, isResizing=%s", self:GetName(), parentName,
                tostring(isLocked), tostring(parent.isResizing)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked=%s or Parent Resizing=%s)", self:GetName(),
                    tostring(isLocked), tostring(parent.isResizing)))
            end
        end
    end)

    -- Store handle reference
    frame.handles.right = rightHandle
end

function BoxxyAuras.FrameHandler.UpdateFrame(frame)
    -- Find the frame type
    local frameType = nil
    for fType, f in pairs(BoxxyAuras.Frames or {}) do
        if f == frame then
            frameType = fType
            break
        end
    end

    if not frameType then
        BoxxyAuras.DebugLogError("Could not determine frame type in UpdateFrame for frame: " ..
            (frame:GetName() or "unnamed"))
        return
    end

    -- Get frame settings table directly (works for custom frames too)
    local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not frameSettings then
        BoxxyAuras.DebugLogError("No settings found for frame type: " .. frameType)
        return
    end

    -- Calculate frame width
    local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
    local numIconsWide = frameSettings.numIconsWide or 1
    local borderSize = frameSettings.borderSize or 0
    local frameWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconSize, borderSize, frameSettings)

    -- Set the frame size
    PixelUtilCompat.SetWidth(frame, frameWidth)

    -- Update aura layout
    BoxxyAuras.FrameHandler.UpdateAurasInFrame(frame)
end

-- Update all frames
function BoxxyAuras.FrameHandler.UpdateAllFramesAuras()
    for frameType, _ in pairs(BoxxyAuras.Frames or {}) do
        BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
    end
end

-- Layout auras in the frame
function BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType, overrideNumIconsWide)
    local frame = BoxxyAuras.Frames and BoxxyAuras.Frames[frameType]
    if not frame then
        -- This can happen during initial load, not necessarily an error.
        return
    end

    -- Get frame settings using the new helper
    local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not frameSettings then
        if BoxxyAuras.DEBUG then
            print("UpdateAurasInFrame: No settings found for frame type: " .. tostring(frameType))
        end
        return
    end

    -- Use override if provided, otherwise use settings
    local numIconsWide = overrideNumIconsWide or frameSettings.numIconsWide or 1
    local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
    local userIconSpacing = frameSettings.iconSpacing
    local baseIconSpacing = userIconSpacing ~= nil and userIconSpacing or (BoxxyAuras.Config.IconSpacing or 6)
    local borderSize = frameSettings.borderSize or 0
    local borderSpacing = BoxxyAuras.FrameHandler.CalculateBorderSpacing(borderSize)
    local iconSpacing = userIconSpacing ~= nil and baseIconSpacing or (baseIconSpacing + borderSpacing)
    local growDirection = frameSettings.growDirection or "RIGHT"
    local wrapDirection = frameSettings.wrapDirection or "DOWN"

    -- Get the sorted auras for this frame
    local iconsToDisplay = BoxxyAuras.iconArrays[frameType] or {}
    local numAuras = #iconsToDisplay

    if BoxxyAuras.DEBUG then
        print(string.format("UpdateAurasInFrame (%s): Laying out %d auras, %d wide. Grow: %s, Wrap: %s",
            frameType, numAuras, numIconsWide, growDirection, wrapDirection))
    end

    -- Calculate total dimensions and positioning values
    local framePadding = BoxxyAuras.Config.FramePadding or 6
    local internalPadding = BoxxyAuras.Config.Padding or 6
    local textSize = frameSettings.textSize or 8
    local textAreaHeight = textSize + 4                             -- Matches AuraIcon.lua
    local iconW = iconSize + internalPadding * 2
    local iconH = iconSize + textAreaHeight + (internalPadding * 2) -- Corrected height
    local slotW = iconW + iconSpacing
    local slotH = iconH + iconSpacing

    -- Calculate total rows needed
    local numRows = math.ceil(numAuras / numIconsWide)
    if numRows == 0 then
        numRows = 1
    end -- Ensure frame has at least 1 row height even if empty

    -- Calculate required frame dimensions
    local requiredWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconSize, borderSize,
        frameSettings)
    local requiredHeight = framePadding + (numRows * iconH) + math.max(0, numRows - 1) * iconSpacing + framePadding

    -- Resize the frame
    local currentWidth = frame:GetWidth()
    local currentHeight = frame:GetHeight()

    -- Only resize if needed to avoid redundant operations
    if math.abs(currentWidth - requiredWidth) > 0.5 or math.abs(currentHeight - requiredHeight) > 0.5 then
        if BoxxyAuras.DEBUG then
            print(string.format("UpdateAurasInFrame (%s): Resizing frame from %.1fx%.1f to %.1fx%.1f",
                frameType, currentWidth, currentHeight, requiredWidth, requiredHeight))
        end

        -- Store the current position before resizing
        local left, top, bottom
        if wrapDirection == "UP" then
            left, bottom = frame:GetLeft(), frame:GetBottom()
        else
            left, top = frame:GetLeft(), frame:GetTop()
        end

        PixelUtilCompat.SetSize(frame, requiredWidth, requiredHeight)

        -- Re-apply the position to anchor the correct edge
        if wrapDirection == "UP" then
            if left and bottom then
                frame:ClearAllPoints()
                PixelUtilCompat.SetPoint(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            end
        else
            if left and top then
                frame:ClearAllPoints()
                PixelUtilCompat.SetPoint(frame, "TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
    end

    -- Update handle sizes to match new frame height (critical for visual consistency)
    if frame.handles and frame.handles.left then
        PixelUtilCompat.SetHeight(frame.handles.left, requiredHeight)
    end
    if frame.handles and frame.handles.right then
        PixelUtilCompat.SetHeight(frame.handles.right, requiredHeight)
    end

    -- Get alignment setting for this frame type
    local alignment = "LEFT" -- Default alignment
    if frameType == "Buff" and frameSettings.buffTextAlign then
        alignment = frameSettings.buffTextAlign
    elseif frameType == "Debuff" and frameSettings.debuffTextAlign then
        alignment = frameSettings.debuffTextAlign
    elseif BoxxyAuras:IsCustomFrameType(frameType) and frameSettings.customTextAlign then
        -- For custom frames, use customTextAlign
        alignment = frameSettings.customTextAlign
    end

    -- Position the icons
    local startX, startY, anchorPoint, xMult, yMult

    if growDirection == "LEFT" then
        xMult = -1
    else -- RIGHT
        xMult = 1
    end

    if wrapDirection == "UP" then
        yMult = 1
    else -- DOWN
        yMult = -1
    end

    -- Determine anchor point based on growth directions
    if yMult == 1 then     -- UP
        if xMult == 1 then -- RIGHT
            anchorPoint = "BOTTOMLEFT"
        else               -- LEFT
            anchorPoint = "BOTTOMRIGHT"
        end
    else                   -- DOWN
        if xMult == 1 then -- RIGHT
            anchorPoint = "TOPLEFT"
        else               -- LEFT
            anchorPoint = "TOPRIGHT"
        end
    end

    startX = framePadding * xMult
    startY = framePadding * yMult

    -- Loop through auras and place them
    for i, icon in ipairs(iconsToDisplay) do
        if icon and icon.frame then
            local actualIndex = i

            -- For RIGHT alignment, reverse the order within each row so newer auras appear on the left
            if alignment == "RIGHT" then
                local row = math.floor((i - 1) / numIconsWide)
                local col = (i - 1) % numIconsWide
                local iconsInThisRow = math.min(numIconsWide, numAuras - (row * numIconsWide))

                -- Reverse the column position within this row
                local reversedCol = (iconsInThisRow - 1) - col
                actualIndex = (row * numIconsWide) + reversedCol + 1
            end

            local col = (actualIndex - 1) % numIconsWide
            local row = math.floor((actualIndex - 1) / numIconsWide)

            -- Calculate how many icons are in this row
            local iconsInThisRow = math.min(numIconsWide, numAuras - (row * numIconsWide))

            -- Calculate the total width of content in this row
            local rowContentWidth = (iconsInThisRow * iconW) + math.max(0, iconsInThisRow - 1) * iconSpacing

            -- Calculate available space in the frame
            local frameContentWidth = requiredWidth - (2 * framePadding)
            local unusedSpace = frameContentWidth - rowContentWidth

            -- Calculate alignment offset for this row
            local alignmentOffset = 0
            if alignment == "CENTER" then
                alignmentOffset = unusedSpace / 2
            elseif alignment == "RIGHT" then
                alignmentOffset = unusedSpace
            end -- LEFT uses 0 offset (no change)

            -- Apply alignment offset to the starting position
            local rowStartX = startX + (alignmentOffset * xMult)

            local xPos = rowStartX + (col * slotW * xMult)
            local yPos = startY + (row * slotH * yMult)

            if icon.frame:IsShown() then            -- Only reposition visible icons
                icon.frame:ClearAllPoints()
                if BoxxyAuras.DEBUG and i <= 2 then -- Limit debug spam
                    print(string.format(
                        "  -> Placing icon %d (%s) at [%d, %d] -> (%.1f, %.1f) anchored to %s of parent (alignment: %s, offset: %.1f, actualIndex: %d)",
                        i, tostring(icon.name), col, row, xPos, yPos, anchorPoint, alignment, alignmentOffset,
                        actualIndex))
                end
                PixelUtilCompat.SetPoint(icon.frame, anchorPoint, frame, anchorPoint, xPos, yPos)
            end
        end
    end
end

-- The TriggerLayout function should call LayoutAuras
BoxxyAuras.FrameHandler.TriggerLayout = function(frameType)
    local frame = BoxxyAuras.Frames[frameType]
    if frame then
        BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
    else
        BoxxyAuras.DebugLogError("TriggerLayout called for unknown frame type: " .. tostring(frameType))
    end
end

-- Let's also implement InitializeFrames to create and set up the frame instances
function BoxxyAuras.FrameHandler.InitializeFrames()
    -- Create frames if they don't exist
    if not BoxxyAuras.Frames then
        BoxxyAuras.Frames = {}
    end

    -- Ensure active profile exists
    if not BoxxyAurasDB.activeProfile then
        BoxxyAurasDB.activeProfile = "Default"
    end

    if not BoxxyAurasDB.profiles then
        BoxxyAurasDB.profiles = {}
    end

    if not BoxxyAurasDB.profiles[BoxxyAurasDB.activeProfile] then
        BoxxyAurasDB.profiles[BoxxyAurasDB.activeProfile] = {}
    end

    -- Get current settings to check for custom frames
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    -- Create the standard frame types first
    local standardFrameTypes = { "Buff", "Debuff" }

    for _, frameType in ipairs(standardFrameTypes) do
        if not BoxxyAuras.Frames[frameType] then
            -- Create frame
            local frame = BoxxyAuras.FrameHandler.SetupDisplayFrame(frameType)
            BoxxyAuras.Frames[frameType] = frame

            -- DON'T restore position here - it will be done later after lock state is applied
        end

        -- Initialize hover states for this frame type
        if BoxxyAuras.FrameHoverStates then
            BoxxyAuras.FrameHoverStates[frameType] = false
        end
        if BoxxyAuras.FrameVisualHoverStates then
            BoxxyAuras.FrameVisualHoverStates[frameType] = false
        end
    end

    -- Create dynamic custom frames from customFrameProfiles
    if currentSettings.customFrameProfiles then
        for customFrameId, customFrameSettings in pairs(currentSettings.customFrameProfiles) do
            if not BoxxyAuras.Frames[customFrameId] then
                -- Create the custom frame
                local frame = BoxxyAuras.FrameHandler.SetupDisplayFrame(customFrameId)
                BoxxyAuras.Frames[customFrameId] = frame

                -- Initialize hover states for this custom frame
                if BoxxyAuras.FrameHoverStates then
                    BoxxyAuras.FrameHoverStates[customFrameId] = false
                end
                if BoxxyAuras.FrameVisualHoverStates then
                    BoxxyAuras.FrameVisualHoverStates[customFrameId] = false
                end

                -- Show the frame initially
                frame:Show()

                -- Restore position from settings if LibWindow is available
                if LibWindow and LibWindow.RestorePosition then
                    LibWindow.RestorePosition(frame)
                end

                if BoxxyAuras.DEBUG then
                    print(string.format("Created dynamic custom frame: %s", customFrameId))
                end
            end
        end
    end

    -- Apply current settings to all frames
    local allFrameTypes = BoxxyAuras:GetAllActiveFrameTypes()
    for _, frameType in ipairs(allFrameTypes) do
        BoxxyAuras.FrameHandler.ApplySettings(frameType)
    end
end

-- Implement the ApplySettings function
function BoxxyAuras.FrameHandler.ApplySettings(frameType, resetPosition_IGNORED)
    local frame = BoxxyAuras.Frames[frameType]
    if not frame then
        return
    end

    -- Get frame settings using the new helper
    local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)
    if not frameSettings then
        if BoxxyAuras.DEBUG then
            print("ApplySettings: No settings found for frame type: " .. tostring(frameType))
        end
        return
    end

    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    -- Apply frame scale if specified using our helper method
    if frameSettings.scale then
        BoxxyAuras.FrameHandler.SetFrameScale(frame, frameSettings.scale)
    end

    -- Apply global scale if specified - this overrides individual frame scale
    if currentSettings.auraBarScale then
        local currentScale = frame:GetScale()
        local targetScale = currentSettings.auraBarScale
        -- Only apply scale if it has actually changed (with small tolerance for floating point comparison)
        if math.abs(currentScale - targetScale) > 0.001 then
            if BoxxyAuras.DEBUG then
                print(string.format("Applying auraBarScale %.2f to frame %s (was %.2f)", targetScale, frameType,
                    currentScale))
            end
            BoxxyAuras.FrameHandler.SetFrameScale(frame, targetScale)

            -- CRITICAL: After changing the scale, we must tell LibWindow to save this new state.
            -- This updates its database and prevents it from restoring the old scale later.
            if LibWindow and LibWindow.SavePosition then
                if BoxxyAuras.DEBUG then
                    print(string.format("  -> Saving new state for %s to LibWindow", frameType))
                end
                LibWindow.SavePosition(frame)
            end
        elseif BoxxyAuras.DEBUG then
            print(string.format("Skipping auraBarScale application for %s - already at %.2f", frameType, targetScale))
        end
    else
        if BoxxyAuras.DEBUG then
            print(string.format("No auraBarScale found for frame %s", frameType))
        end
    end

    -- Calculate frame width based on config
    local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
    local numIconsWide = frameSettings.numIconsWide or 1
    local borderSize = frameSettings.borderSize or 0
    local frameWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconSize, borderSize, frameSettings)

    -- Check if this frame is right-aligned to determine growth direction
    local alignment = "LEFT" -- Default alignment
    if frameType == "Buff" and frameSettings.buffTextAlign then
        alignment = frameSettings.buffTextAlign
    elseif frameType == "Debuff" and frameSettings.debuffTextAlign then
        alignment = frameSettings.debuffTextAlign
    elseif BoxxyAuras:IsCustomFrameType(frameType) and frameSettings.customTextAlign then
        alignment = frameSettings.customTextAlign
    end

    -- For right-aligned frames, we need special handling to grow left instead of right
    if alignment == "RIGHT" then
        local currentWidth = frame:GetWidth()
        local widthDelta = frameWidth - currentWidth
        
        -- Only do special handling if the width is actually changing
        if math.abs(widthDelta) > 0.1 then
            -- Get current position
            local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
            
            if point and relativeTo and relativePoint then
                -- Calculate current right edge position
                local currentLeft = frame:GetLeft()
                local currentRightEdge = currentLeft + currentWidth
                
                -- Set the new width
                frame:SetWidth(frameWidth)
                
                -- Calculate the new X offset to maintain the right edge position
                -- We adjust the existing offset by the width change
                local newXOfs = xOfs - widthDelta
                
                -- Clear points and reposition using the original anchor point
                frame:ClearAllPoints()
                frame:SetPoint(point, relativeTo, relativePoint, newXOfs, yOfs)
                
                if BoxxyAuras.DEBUG then
                    print(string.format("Right-aligned frame %s: width %.1f -> %.1f, adjusted X offset by %.1f (%.1f -> %.1f)", 
                        frameType, currentWidth, frameWidth, -widthDelta, xOfs, newXOfs))
                end
            else
                -- Fallback if we can't get position info
                frame:SetWidth(frameWidth)
            end
        else
            -- Width isn't changing significantly, just set it normally
            frame:SetWidth(frameWidth)
        end
    else
        -- For left-aligned and center-aligned frames, just set width normally
        frame:SetWidth(frameWidth)
    end

    -- Ensure frame is visible unless explicitly locked
    local isLocked = currentSettings and currentSettings.lockFrames
    if not isLocked then
        frame:Show()
    end

    -- Layout auras in the frame
    BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType)
end

-- Add back the stub functions that were removed
function BoxxyAuras.FrameHandler.UpdateEdgeHandleDimensions(frame, frameW, frameH)
end

function BoxxyAuras.FrameHandler.PollFrameHoverState(frame, frameDesc)
end

function BoxxyAuras.FrameHandler.ApplyLockState(isLocked)
    if BoxxyAuras.DEBUG then
        print(string.format("ApplyLockState called with isLocked = %s", tostring(isLocked)))
    end

    -- Enable/disable keyboard handling based on lock state
    if isLocked then
        if BoxxyAuras.DisableKeyboardHandling then
            BoxxyAuras.DisableKeyboardHandling()
        end
    else
        if BoxxyAuras.EnableKeyboardHandling then
            BoxxyAuras.EnableKeyboardHandling()
        end
    end

    -- Lock/unlock all frames
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if frame and frame.Lock and frame.Unlock then
            if isLocked then
                -- Save position before locking to ensure LibWindow has current position data
                if LibWindow and LibWindow.SavePosition then
                    LibWindow.SavePosition(frame)
                    if BoxxyAuras.DEBUG then
                        print(string.format("Saved position for %s frame before locking", frameType))
                    end
                end
                frame:Lock()
            else
                frame:Unlock()
            end

            -- Removed explicit handle locking/unlocking from here
        end
    end
end

function BoxxyAuras.FrameHandler.SetFrameScale(frame, scale)
    if frame and frame.SetFrameScale then
        frame:SetFrameScale(scale)
    elseif frame and frame.SetScale then
        frame:SetScale(scale)
    end
end

-- Force resize all icons in all frames to match current settings
function BoxxyAuras.FrameHandler.ForceResizeAllIcons()
    -- Loop through each frame type
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        -- Get frame-specific settings directly
        local frameSettings = BoxxyAuras.FrameHandler.GetFrameSettingsTable(frameType)

        if frameSettings then
            local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize

            -- Get the icons for this frame type
            local iconArray = BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[frameType]

            -- Apply the new size to each icon
            if iconArray then
                for i, icon in pairs(iconArray) do
                    if icon and icon.Resize then
                        icon:Resize(iconSize)
                    elseif icon and icon.frame then
                        BoxxyAuras.DebugLogError("Icon " .. i .. " doesn't have Resize method!")
                    end
                end
            else
                BoxxyAuras.DebugLogError("No icons found for " .. frameType)
            end
        end
    end

    -- Update layout in all frames
    BoxxyAuras.FrameHandler.UpdateAllFramesAuras()
end

function BoxxyAuras.FrameHandler.IsMouseOverAnyIcon(frame)
    if not frame or not frame:IsVisible() then
        return false
    end

    local frameType
    for fType, f in pairs(BoxxyAuras.Frames or {}) do
        if f == frame then
            frameType = fType
            break
        end
    end

    if not frameType then
        return false
    end

    local icons = BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[frameType]
    if not icons or #icons == 0 then
        return false
    end

    for _, icon in ipairs(icons) do
        if icon and icon.frame and icon.frame:IsVisible() and icon.frame:IsMouseOver() then
            return true
        end
    end

    return false
end

function BoxxyAuras.FrameHandler.ToggleFrameLock()
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    if BoxxyAuras.DEBUG then
        print(string.format("ToggleFrameLock called. Current lock state: %s", tostring(currentSettings.lockFrames)))
    end
    currentSettings.lockFrames = not currentSettings.lockFrames
    BoxxyAuras.FrameHandler.ApplyLockState(currentSettings.lockFrames)
end
