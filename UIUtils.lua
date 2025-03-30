local ADDON_NAME, Addon = ... -- Get addon name and private table

Addon.UIUtils = {}

-- Copied from WhoGotLoots/UIBuilder.lua
local FrameTextures =
{
    -- We might only need a few of these initially
    ItemEntryBG = {
        file = "ItemBG", -- Assuming this texture exists or we replace it
        cornerSize = 4,
        cornerCoord = 16/64,
    },
    ItemEntryBorder = {
        file = "EdgedBorder_Sharp", -- Assuming this exists or we replace it
        cornerSize = 4,
        cornerCoord = 16/64,
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
    -- Add Keys for Buff/Debuff Display Frame Backdrops
    BuffFrameHoverBG = { 
        file = "SelectionBox", -- Reuse SelectionBox texture
        cornerSize = 12,
        cornerCoord = 0.25,
    },
    DebuffFrameHoverBG = { 
        file = "SelectionBox", -- Reuse SelectionBox texture
        cornerSize = 12,
        cornerCoord = 0.25,
    }
    -- Add more keys from WhoGotLoots FrameTextures if needed
}

-- Copied from WhoGotLoots/UIBuilder.lua (Adapted slightly)
function Addon.UIUtils.DrawSlicedBG(frame, textureKey, layer, shrink)
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
        print("|cffff0000DrawSlicedBG Error: Invalid layer specified: " .. tostring(layer) .. "|r")
        return
    end

    local data = FrameTextures[textureKey];
    if not data then
        print("|cffff0000DrawSlicedBG Error: Invalid textureKey specified: " .. tostring(textureKey) .. "|r")
        return
    end

    -- Construct file path - assumes textures are in an 'Art' subfolder
    -- We might need to adjust this path later!
    local file = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Art\\" .. data.file;
    -- print(string.format("DEBUG DrawSlicedBG: Addon='%s', Key='%s', Layer='%s', Trying path: %s", 
    --     tostring(ADDON_NAME), tostring(textureKey), tostring(layer), file)) -- DEBUG PATH
        
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
function Addon.UIUtils.ColorBGSlicedFrame(frame, layer, r, g, b, a)
    local group = nil
    if layer == "backdrop" then
        group = frame.backdropTextures
    elseif layer == "border" then
        group = frame.borderTextures
    end

    if group then
        for _, tex in pairs(group) do
            tex:SetVertexColor(r, g, b, a);
        end
    else
        print("|cffff0000ColorBGSlicedFrame Error: Invalid layer or texture group not found: " .. tostring(layer) .. "|r")
    end
end 