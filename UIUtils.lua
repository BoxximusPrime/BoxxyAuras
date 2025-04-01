local BOXXYAURAS, BoxxyAuras = ... -- Get addon name and private table
BoxxyAuras = BoxxyAuras or {}
BoxxyAuras.AllAuras = {} -- Global cache for aura info

BoxxyAuras.UIUtils = {}

-- Copied from WhoGotLoots/UIBuilder.lua
BoxxyAuras.FrameTextures =
{
    -- We might only need a few of these initially
    ItemEntryBG = {
        file = "ItemBG", -- Assuming this texture exists or we replace it
        cornerSize = 4,
        cornerCoord = 16/64,
    },
    ItemEntryBorder = {
        file = "EdgedBorder_Sharp", -- Assuming this exists or we replace it
        cornerSize = 8,
        cornerCoord = 24/64,
    },
    -- Adding a simple border option
    TooltipBorder = {
        file = "Tooltip-Border", -- Standard WoW Tooltip Border
        cornerSize = 16,
        cornerCoord = 16/64, -- Typical coord for 16px corner on 64px texture
    },
    MainFrameHoverBG = { -- Added for main frame background
        file = "SelectionBox", -- Assumed texture file name
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    EdgedBorder = { -- Adding this border option from WhoGotLoots
        file = "EdgedBorder",
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    -- >>> ADDED Options Window Background <<<
    OptionsWindowBG = {
        file = "OptionsWindowBG", -- Assuming this texture file exists in Art/
        cornerSize = 12,        -- Adjust if needed
        cornerCoord = 0.25,       -- Adjust if needed
    }
    -- Add more keys from WhoGotLoots FrameTextures if needed
}

-- Copied from WhoGotLoots/UIBuilder.lua (Adapted slightly)
function BoxxyAuras.UIUtils.DrawSlicedBG(frame, textureKey, layer, shrink)
    shrink = shrink or 0;
    local group, subLevel;

    if layer == "backdrop" then
        if not frame.backdropTextures then
            frame.backdropTextures = {};
        end
        group = frame.backdropTextures;
        subLevel = -8; -- Ensure backdrop is behind other things
    elseif layer == "border" then
        if not frame.borderTextures then
            frame.borderTextures = {};
        end
        group = frame.borderTextures;
        subLevel = -7; -- Ensure border is above backdrop but behind content
    else
        return
    end

    local data = BoxxyAuras.FrameTextures[textureKey];
    if not data then
        return
    end

    -- Construct file path - ensures forward slashes and adds extension
    local file = "Interface/AddOns/BoxxyAuras/Art/" .. data.file .. ".tga";
    local cornerSize = data.cornerSize;
    local coord = data.cornerCoord;
    local buildOrder = {1, 3, 7, 9, 2, 4, 6, 8, 5};
    local tex, key;

    for i = 1, 9 do
        key = buildOrder[i];
        if not group[key] then
            group[key] = frame:CreateTexture(nil, "BACKGROUND", nil, subLevel);
        else
            -- Texture already exists, ensure it's shown if frame is shown
            if frame:IsShown() then group[key]:Show() else group[key]:Hide() end
        end
        tex = group[key];
        tex:SetTexture(file, nil, nil, "LINEAR");

        if key == 2 or key == 8 then
            if key == 2 then
                tex:SetPoint("TOPLEFT", group[1], "TOPRIGHT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[3], "BOTTOMLEFT", 0, 0);
                tex:SetTexCoord(coord, 1-coord, 0, coord);
            else
                tex:SetPoint("TOPLEFT", group[7], "TOPRIGHT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[9], "BOTTOMLEFT", 0, 0);
                tex:SetTexCoord(coord, 1-coord, 1-coord, 1);
            end
        elseif key == 4 or key == 6 then
            if key == 4 then
                tex:SetPoint("TOPLEFT", group[1], "BOTTOMLEFT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[7], "TOPRIGHT", 0, 0);
                tex:SetTexCoord(0, coord, coord, 1-coord);
            else
                tex:SetPoint("TOPLEFT", group[3], "BOTTOMLEFT", 0, 0);
                tex:SetPoint("BOTTOMRIGHT", group[9], "TOPRIGHT", 0, 0);
                tex:SetTexCoord(1-coord, 1, coord, 1-coord);
            end
        elseif key == 5 then
            tex:SetPoint("TOPLEFT", group[1], "BOTTOMRIGHT", 0, 0);
            tex:SetPoint("BOTTOMRIGHT", group[9], "TOPLEFT", 0, 0);
            tex:SetTexCoord(coord, 1-coord, coord, 1-coord);
        else
            tex:SetSize(cornerSize, cornerSize);
            if key == 1 then
                tex:SetPoint("TOPLEFT", frame, "TOPLEFT", shrink, -shrink);
                tex:SetTexCoord(0, coord, 0, coord);
            elseif key == 3 then
                tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -shrink, -shrink);
                tex:SetTexCoord(1-coord, 1, 0, coord);
            elseif key == 7 then
                tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", shrink, shrink);
                tex:SetTexCoord(0, coord, 1-coord, 1);
            elseif key == 9 then
                tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -shrink, shrink);
                tex:SetTexCoord(1-coord, 1, 1-coord, 1);
            end
        end
    end
end

-- Copied from WhoGotLoots/UIBuilder.lua (Adapted slightly)
function BoxxyAuras.UIUtils.ColorBGSlicedFrame(frame, layer, r, g, b, a)
    local group = nil
    if layer == "backdrop" then
        group = frame.backdropTextures
    elseif layer == "border" then
        group = frame.borderTextures
    end

    if group then
        for key, tex in pairs(group) do
            local success, err = pcall(tex.SetVertexColor, tex, r, g, b, a)
            if not success then
                print(string.format("|cffFF0000ERROR:|r ColorBGSlicedFrame: pcall failed for SetVertexColor on key %s. Error: %s", tostring(key), tostring(err)))
            end
        end
    else
        print(string.format("|cffFF0000ColorBGSlicedFrame Error: Invalid layer or texture group not found for frame %s, layer: %s |r", frame:GetName(), tostring(layer)))
    end 
end

-- Function to set up buttons inheriting from BAURASGeneralButton
function BoxxyAuras_SetupGeneralButton(button)
    if not button then return end

    -- Ensure UIUtils functions are available before using them
    if BoxxyAuras and BoxxyAuras.UIUtils and 
       BoxxyAuras.UIUtils.DrawSlicedBG and BoxxyAuras.UIUtils.ColorBGSlicedFrame then
        
        -- Draw initial background and border
        BoxxyAuras.UIUtils.DrawSlicedBG(button, "BtnBG", "border", -2)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(button, "border", 0.1, 0.1, 0.1, 1) -- Default border color
        BoxxyAuras.UIUtils.DrawSlicedBG(button, "BtnBorder", "backdrop", -2)
        BoxxyAuras.UIUtils.ColorBGSlicedFrame(button, "backdrop", 0.3, 0.3, 0.3, 1) -- Default backdrop color

        -- Define methods directly on the button object
        function button:SetText(text)
            if self.Text then -- Check if the FontString child exists
                self.Text:SetText(text)
            end
        end

        function button:SetEnabled(enabled)
            self.Enabled = enabled -- Use the .Enabled property set in XML OnLoad
            -- Update appearance based on enabled state
            if enabled then
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.3, 0.3, 0.3, 1)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.1, 0.1, 0.1, 1)
                if self.Text then self.Text:SetTextColor(0.75, 0.75, 0.75) end
            else
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "backdrop", 0.2, 0.2, 0.2, 1)
                BoxxyAuras.UIUtils.ColorBGSlicedFrame(self, "border", 0.3, 0.3, 0.3, 1)
                if self.Text then self.Text:SetTextColor(0.28, 0.28, 0.28) end
            end
        end

        function button:IsEnabled()
            return self.Enabled
        end

        -- Apply the initial enabled state visuals
        button:SetEnabled(button.Enabled)

    else
        print(string.format("|cffFF0000BoxxyAuras Error:|r UIUtils functions not found when setting up button '%s' via BoxxyAuras_SetupGeneralButton.", button:GetName() or "(unknown)"))
    end
end 