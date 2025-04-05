local addonNameString, privateTable = ... -- Use different names for the local vars from ...
_G.BoxxyAuras = _G.BoxxyAuras or {} -- Explicitly create/assign the GLOBAL table
local BoxxyAuras = _G.BoxxyAuras -- Create a convenient local alias to the global table
BoxxyAuras.FrameHandler = {}
BoxxyAurasDB = BoxxyAurasDB or {}

-- Import LibWindow
local LibWindow = LibStub("LibWindow-1.1")

-- Define constants and shared variables needed by frame functions
local HandleWidth = 12 -- Increased handle size SIGNIFICANTLY for testing

-- =========================================
--       LOCAL HELPER FUNCTIONS (RESIZE - User Provided Version)
-- =========================================

local function HandleOnMouseDown(self, button)
    if BoxxyAuras.DEBUG then
        print("HandleOnMouseDown fired for handle: " .. self:GetName() .. " Button: " .. button)
    end
    if button == "LeftButton" and not BoxxyAuras.Config.FramesLocked then
        local parentFrame = self:GetParent()
        local resizeSide = self.resizeSide

        parentFrame.isResizing = true
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

                local newWidth = self.resizeStartWidth
                if self.resizeHandle.resizeSide == "RIGHT" then
                    newWidth = self.resizeStartWidth + deltaX
                elseif self.resizeHandle.resizeSide == "LEFT" then
                    newWidth = self.resizeStartWidth - deltaX
                    if newWidth < 10 then
                        newWidth = 10
                    end -- Ensure minimum width
                end

                -- Find frameType for settings lookup
                local frameType = nil
                for fType, f in pairs(BoxxyAuras.Frames or {}) do
                    if f == self then
                        frameType = fType;
                        break
                    end
                end
                if not frameType then
                    return
                end

                -- Get settings and calculate needed dimensions
                local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
                local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
                if not currentSettings or not settingsKey or not currentSettings[settingsKey] then
                    return
                end

                local frameSettings = currentSettings[settingsKey]
                local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
                local iconSpacing = BoxxyAuras.Config.IconSpacing or 6
                local framePadding = BoxxyAuras.Config.FramePadding or 6
                local internalPadding = BoxxyAuras.Config.Padding or 6
                local iconWidth = iconSize + (internalPadding * 2)
                local iconSlotWidth = iconWidth + iconSpacing

                -- Calculate how many icons fit based on potential new width
                local availableWidth = newWidth - (framePadding * 2) + iconSpacing -- Add back one spacing for calc
                local numIcons = math.max(1, math.floor(availableWidth / iconSlotWidth))

                -- Get current frame geometry (needed for repositioning)
                local currentLeft, currentBottom, currentWidth, currentHeight = self:GetRect()
                local currentRight = currentLeft + currentWidth

                -- Only apply change IF the number of icons fitting has changed
                local widthChanged = false
                if numIcons ~= (frameSettings.numIconsWide or 1) then

                    -- Calculate the EXACT width needed for the new number of icons
                    local calculatedWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIcons, iconSize)

                    -- Check if the *calculated* width is different enough
                    if math.abs(self:GetWidth() - calculatedWidth) > 0.5 then
                        self:SetWidth(calculatedWidth)
                        widthChanged = true

                        -- Reposition frame to keep the opposite edge stationary
                        local newLeft = 0
                        if self.resizeHandle.resizeSide == "LEFT" then
                            -- Keep right edge stationary
                            newLeft = self.resizeStartRight - calculatedWidth
                        else -- Right handle drag
                            -- Keep left edge stationary
                            newLeft = self.resizeStartLeft
                        end
                        self:ClearAllPoints()
                        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, self.resizeStartTop)
                        BoxxyAuras.FrameHandler.UpdateAurasInFrame(frameType, numIcons)
                    end
                end
            end
        end)
    end
end

local function HandleOnMouseUp(self, button)
    if button == "LeftButton" and not BoxxyAuras.Config.FramesLocked then
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
                local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
                local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
                if settingsKey and currentSettings[settingsKey] then
                    local frameSettings = currentSettings[settingsKey]
                    local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
                    local iconSpacing = BoxxyAuras.Config.IconSpacing or 6
                    local framePadding = BoxxyAuras.Config.FramePadding or 6
                    local internalPadding = BoxxyAuras.Config.Padding or 6
                    local iconWidth = iconSize + (internalPadding * 2)
                    local iconSlotWidth = iconWidth + iconSpacing

                    -- Recalculate final numIcons based on the frame's width *at the end* of the drag
                    local finalWidth = parentFrame:GetWidth()
                    local finalAvailableWidth = finalWidth - (framePadding * 2) + iconSpacing
                    local finalNumIcons = math.max(1, math.floor(finalAvailableWidth / iconSlotWidth))

                    if frameSettings.numIconsWide ~= finalNumIcons then
                        if BoxxyAuras.DEBUG then
                            print(string.format("Saving FINAL numIconsWide for %s: %d (was %d)", frameType,
                                finalNumIcons, frameSettings.numIconsWide or -1))
                        end
                        frameSettings.numIconsWide = finalNumIcons
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
    elseif frameType == "Custom" then
        return "customFrameSettings"
    else
        return nil
    end
end

-- Calculate Width Helper (Keep this utility)
function BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconSize)
    local framePadding = (BoxxyAuras.Config and BoxxyAuras.Config.FramePadding) or 6
    local iconSpacing = (BoxxyAuras.Config and BoxxyAuras.Config.IconSpacing) or 6
    local internalPadding = (BoxxyAuras.Config and BoxxyAuras.Config.Padding) or 6
    local iconW = iconSize + (internalPadding * 2)
    local width = framePadding + (numIconsWide * iconW) + math.max(0, numIconsWide - 1) * iconSpacing + framePadding
    return width
end

-- Frame Setup
function BoxxyAuras.FrameHandler.SetupDisplayFrame(frameName)

    local frame = CreateFrame("Frame", "BoxxyAuraPanel_" .. frameName, UIParent)
    frame:SetFrameStrata("MEDIUM") -- Explicitly set parent strata

    -- Ensure we have a profile for this frame
    BoxxyAurasDB.profiles[BoxxyAurasDB.activeProfile][frameName] =
        BoxxyAurasDB.profiles[BoxxyAurasDB.activeProfile][frameName] or {}

    -- Calculate frame size based on number of icons and icon size
    local frameSize = BoxxyAuras.FrameHandler.CalculateFrameWidth(1, BoxxyAuras.Config.IconSize)
    frame:SetSize(frameSize, frameSize)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Draw frame visuals (Keep this part as it sets up appearance)
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "MainFrameHoverBG", "backdrop", 0)
    BoxxyAuras.UIUtils.DrawSlicedBG(frame, "EdgedBorder", "border", 0)

    -- Set colors
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "backdrop", BoxxyAuras.Config.MainFrameBGColorNormal)
    BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, "border", BoxxyAuras.Config.BorderColor)

    -- Create handles
    CreateHandles(frame)

    -- Prepare LibWindow for dragging
    LibWindow.RegisterConfig(frame, BoxxyAurasDB.profiles[BoxxyAurasDB.activeProfile][frameName])
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
        if not BoxxyAuras.Config.FramesLocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        LibWindow.SavePosition(self)
    end)

    -- Register helper methods.
    function frame:Lock(button)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", {
            r = 0,
            g = 0,
            b = 0,
            a = 0
        })
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", {
            r = 0,
            g = 0,
            b = 0,
            a = 0
        }) -- Hide border
        if self.titleLabel then
            self.titleLabel:Hide()
        end -- Hide title
        self:EnableMouse(false) -- Disable mouse interaction
    end
    function frame:Unlock()
        if BoxxyAuras.DEBUG then
            print("Executing frame:Unlock() for " .. self:GetName())
        end
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", BoxxyAuras.Config.MainFrameBGColorNormal)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", BoxxyAuras.Config.BorderColor) -- Restore border
        if self.titleLabel then
            self.titleLabel:Show()
        end -- Show title
        self:EnableMouse(true) -- Re-enable mouse interaction
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

    leftHandle:SetSize(HandleWidth, FrameHeight)
    leftHandle:SetPoint("LEFT", frame, "LEFT", 0, 0) -- Corrected anchor
    leftHandle:SetFrameLevel(frame:GetFrameLevel() + 10) -- Add back frame level
    leftHandle:SetFrameStrata("HIGH") -- Add back strata
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
    leftHandle:SetBackdropColor(1.0, 1.0, 1.0, 0) -- NEW: Start transparent
    leftHandle:EnableMouse(true)
    leftHandle.resizeSide = "LEFT" -- Add back resize side
    leftHandle:SetScript("OnMouseDown", HandleOnMouseDown) -- Add back mouse down
    leftHandle:SetScript("OnMouseUp", HandleOnMouseUp) -- Add back mouse up
    leftHandle:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnEnter: Parent (%s) isLocked=%s", self:GetName(), parentName, tostring(isLocked)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0.8)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0.8", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked or Parent Resizing)", self:GetName()))
            end
        end
    end)
    leftHandle:SetScript("OnLeave", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnLeave: Parent (%s) isLocked=%s", self:GetName(), parentName, tostring(isLocked)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked or Parent Resizing)", self:GetName()))
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

    rightHandle:SetSize(HandleWidth, FrameHeight)
    rightHandle:SetPoint("RIGHT", frame, "RIGHT", 0, 0) -- Corrected anchor
    rightHandle:SetFrameLevel(frame:GetFrameLevel() + 10) -- Add back frame level
    rightHandle:SetFrameStrata("HIGH") -- Add back strata
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
    rightHandle:SetBackdropColor(1.0, 1.0, 1.0, 0) -- NEW: Start transparent
    rightHandle:EnableMouse(true)
    rightHandle.resizeSide = "RIGHT" -- Add back resize side
    rightHandle:SetScript("OnMouseDown", HandleOnMouseDown) -- Add back mouse down
    rightHandle:SetScript("OnMouseUp", HandleOnMouseUp) -- Add back mouse up
    rightHandle:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnEnter: Parent (%s) isLocked=%s", self:GetName(), parentName, tostring(isLocked)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0.8)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0.8", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked or Parent Resizing)", self:GetName()))
            end
        end
    end)
    rightHandle:SetScript("OnLeave", function(self)
        local parent = self:GetParent()
        local parentName = parent:GetName()
        local isLocked = BoxxyAuras:GetCurrentProfileSettings().lockFrames
        if BoxxyAuras.DEBUG then
            print(string.format("%s OnLeave: Parent (%s) isLocked=%s", self:GetName(), parentName, tostring(isLocked)))
        end
        if not isLocked and not parent.isResizing then
            self:SetBackdropColor(1.0, 1.0, 1.0, 0)
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Setting Alpha: 0", self:GetName()))
            end
        else
            if BoxxyAuras.DEBUG then
                print(string.format("  -> %s Not Changing Alpha (Locked or Parent Resizing)", self:GetName()))
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

    -- Get settings key
    local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    if not settingsKey then
        BoxxyAuras.DebugLogError("No settings key for frame type: " .. frameType)
        return
    end

    -- Get current settings
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()
    if not currentSettings[settingsKey] then
        currentSettings[settingsKey] = {}
    end

    -- Calculate frame width
    local iconSize = currentSettings[settingsKey].iconSize or BoxxyAuras.Config.IconSize
    local numIconsWide = currentSettings[settingsKey].numIconsWide or 1
    local frameWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconSize)

    -- Set the frame size
    frame:SetWidth(frameWidth)

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

    -- Get the frame object using frameType
    local frame = BoxxyAuras.Frames and BoxxyAuras.Frames[frameType]
    if not frame then
        BoxxyAuras.DebugLogError("UpdateAurasInFrame called with invalid frameType: " .. tostring(frameType))
        throw("UpdateAurasInFrame called with invalid frameType: " .. tostring(frameType))
        return
    end

    -- Determine the correct icon array based on the frame type
    local iconsArray = BoxxyAuras.iconArrays and BoxxyAuras.iconArrays[frameType] or {}

    -- Get current profile settings
    local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    if not currentSettings or not settingsKey or not currentSettings[settingsKey] then
        BoxxyAuras.DebugLogError("Missing settings for frame type: " .. frameType)
        return
    end

    local frameSettings = currentSettings[settingsKey]

    -- Get icon configuration and alignment
    local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
    local alignment = "LEFT" -- Default alignment
    if frameType == "Buff" then
        alignment = frameSettings.buffTextAlign or "LEFT"
    elseif frameType == "Debuff" then
        alignment = frameSettings.debuffTextAlign or "LEFT"
    elseif frameType == "Custom" then
        alignment = frameSettings.customTextAlign or "LEFT"
    end

    -- Get icons per row: Use override if provided, otherwise use settings
    local iconsPerRow = overrideNumIconsWide or frameSettings.numIconsWide or 1 -- Use override first
    iconsPerRow = math.max(1, iconsPerRow) -- Ensure at least 1

    local iconSpacing = BoxxyAuras.Config.IconSpacing or 6
    local framePadding = BoxxyAuras.Config.FramePadding or 6
    local internalPadding = BoxxyAuras.Config.Padding or 6

    -- Calculate icon dimensions including padding
    local iconWidth = iconSize + (internalPadding * 2)
    local iconHeight = iconSize + (internalPadding * 2) + (BoxxyAuras.Config.TextHeight or 8)

    -- Calculate frame width and available space (still needed for centering)
    local frameWidth = frame:GetWidth()
    local availableWidth = frameWidth - (framePadding * 2)

    -- Build a table of visible icons
    local visibleIcons = {}
    for _, icon in ipairs(iconsArray) do -- Use ipairs for ordered iteration
        if icon and icon.frame and icon.frame:IsShown() then
            table.insert(visibleIcons, icon)
        end
    end
    local numVisibleIcons = #visibleIcons

    -- Calculate number of rows needed
    local numRows = math.max(1, math.ceil(numVisibleIcons / iconsPerRow)) -- Ensure at least 1 row height

    -- Calculate frame height based on rows
    local calculatedFrameHeight = (framePadding * 2) + (numRows * iconHeight) + math.max(0, numRows - 1) * iconSpacing
    calculatedFrameHeight = math.max(calculatedFrameHeight, iconHeight + (framePadding * 2)) -- Ensure minimum height

    -- Resize frame height if needed
    if frame:GetHeight() ~= calculatedFrameHeight then
        frame:SetHeight(calculatedFrameHeight)

        -- === Update Handle Dimensions ===
        if frame.handles then
            local parentH = frame:GetHeight()
            if frame.handles.left then
                frame.handles.left:SetSize(HandleWidth, parentH) -- NEW: Set both dimensions
                frame.handles.left:ClearAllPoints() -- Re-anchor to ensure vertical centering
                frame.handles.left:SetPoint("LEFT", frame, "LEFT", 0, 0)
            end
            if frame.handles.right then
                frame.handles.right:SetSize(HandleWidth, parentH) -- NEW: Set both dimensions
                frame.handles.right:ClearAllPoints() -- Re-anchor to ensure vertical centering
                frame.handles.right:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            end
        end
        -- === End Handle Update ===
    end

    -- Arrange icons one by one, calculating position based on alignment
    for i, icon in ipairs(visibleIcons) do
        if icon and icon.frame then
            -- Calculate the logical row and column index (0-based) assuming LTR layout
            local logicalIndex = i - 1
            local row = math.floor(logicalIndex / iconsPerRow)
            local col = logicalIndex % iconsPerRow

            -- Calculate Y position (same for all alignments)
            local yPos = -framePadding - row * (iconHeight + iconSpacing)

            -- Calculate X position based on alignment
            local xPos = 0
            if alignment == "LEFT" then
                xPos = framePadding + col * (iconWidth + iconSpacing)
            elseif alignment == "RIGHT" then
                -- Calculate position relative to the right edge
                xPos = frameWidth - framePadding - iconWidth - col * (iconWidth + iconSpacing)
            elseif alignment == "CENTER" then
                -- Calculate how many icons are *actually* in this row
                local startIconIndexForRow = row * iconsPerRow + 1
                local endIconIndexForRow = math.min(startIconIndexForRow + iconsPerRow - 1, numVisibleIcons)
                local iconsInThisRow = endIconIndexForRow - startIconIndexForRow + 1

                -- Calculate the exact width needed for just the icons in this row
                local rowContentWidth = (iconsInThisRow * iconWidth) + math.max(0, iconsInThisRow - 1) * iconSpacing

                -- Calculate the starting X to center *this row's content* within the available width
                local centeredStartX = framePadding + (availableWidth - rowContentWidth) / 2

                -- Ensure start position isn't less than padding (can happen with very wide icons/small frames)
                centeredStartX = math.max(framePadding, centeredStartX)

                xPos = centeredStartX + col * (iconWidth + iconSpacing)
            end

            -- Position icon
            icon.frame:ClearAllPoints()
            icon.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, yPos)
        end
    end

    -- Store the count for potential use elsewhere
    frame.visibleAuraCount = numVisibleIcons
end

-- The TriggerLayout function should call LayoutAuras
BoxxyAuras.FrameHandler.TriggerLayout = function(frameType)
    local frame = BoxxyAuras.Frames[frameType]
    if frame then
        BoxxyAuras.FrameHandler.UpdateAurasInFrame(frame)
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

    -- Create the three main frame types if they don't exist yet
    local frameTypes = {"Buff", "Debuff", "Custom"}

    for _, frameType in ipairs(frameTypes) do
        if not BoxxyAuras.Frames[frameType] then
            -- Create frame
            local frame = BoxxyAuras.FrameHandler.SetupDisplayFrame(frameType)
            BoxxyAuras.Frames[frameType] = frame

            -- Restore position from saved variables
            LibWindow.RestorePosition(frame)
        end
    end

    -- Apply current settings to all frames
    for _, frameType in ipairs(frameTypes) do
        BoxxyAuras.FrameHandler.ApplySettings(frameType)
    end
end

-- Implement the ApplySettings function
function BoxxyAuras.FrameHandler.ApplySettings(frameType, resetPosition_IGNORED)
    local frame = BoxxyAuras.Frames[frameType]
    if not frame then
        return
    end

    -- Apply frame width based on current settings
    local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
    local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

    if currentSettings and settingsKey and currentSettings[settingsKey] then
        local frameSettings = currentSettings[settingsKey]

        -- Apply frame scale if specified using our helper method
        if frameSettings.scale then
            BoxxyAuras.FrameHandler.SetFrameScale(frame, frameSettings.scale)
        end

        -- Apply global scale if specified - this overrides individual frame scale
        if currentSettings.optionsScale then
            BoxxyAuras.FrameHandler.SetFrameScale(frame, currentSettings.optionsScale)
        end

        -- Calculate frame width based on config
        local iconSize = frameSettings.iconSize or BoxxyAuras.Config.IconSize
        local numIconsWide = frameSettings.numIconsWide or 1
        local frameWidth = BoxxyAuras.FrameHandler.CalculateFrameWidth(numIconsWide, iconSize)

        -- Set frame width
        frame:SetWidth(frameWidth)
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
    -- Lock/unlock all frames
    for frameType, frame in pairs(BoxxyAuras.Frames or {}) do
        if frame and frame.Lock and frame.Unlock then
            if isLocked then
                frame:Lock() -- Calls frame:EnableMouse(false) among other things
            else
                frame:Unlock() -- Calls frame:EnableMouse(true) among other things
            end

            -- Explicitly lock/unlock handles as well
            if frame.handles then
                if frame.handles.left then
                    frame.handles.left:EnableMouse(not isLocked)
                end
                if frame.handles.right then
                    frame.handles.right:EnableMouse(not isLocked)
                end
            end
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
        -- Get current settings
        local settingsKey = BoxxyAuras.FrameHandler.GetSettingsKeyFromFrameType(frameType)
        local currentSettings = BoxxyAuras:GetCurrentProfileSettings()

        if currentSettings and settingsKey and currentSettings[settingsKey] then
            local iconSize = currentSettings[settingsKey].iconSize or BoxxyAuras.Config.IconSize

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

