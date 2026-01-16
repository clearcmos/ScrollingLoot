-- ScrollingLoot: Displays looted items as scrolling text with icons
-- For WoW Classic Anniversary Edition (2.5.5)

local addonName, addon = ...

-- Configuration defaults
local DEFAULT_SETTINGS = {
    enabled = true,
    iconSize = 26,
    fontSize = 18,
    scrollSpeed = 3.5,          -- Duration in seconds
    fadeStartTime = 2.5,        -- When fade begins
    startOffsetX = 200,         -- Horizontal offset from screen center
    startOffsetY = -20,         -- Vertical offset from screen center (negative = below)
    scrollDistance = 150,       -- How far text scrolls upward
    maxMessages = 10,           -- Maximum simultaneous messages
    anchorPoint = "RIGHT",      -- Which side of screen center (LEFT or RIGHT)
    showQuantity = true,        -- Show stack counts
    minQuality = 0,             -- Minimum quality to show (0 = all)
    showBackground = false,     -- Show opaque background behind loot text
};

-- Local references for performance
local CreateFrame = CreateFrame;
local GetTime = GetTime;
local pairs = pairs;
local ipairs = ipairs;
local tinsert = table.insert;
local tremove = table.remove;
local wipe = table.wipe;
local format = string.format;
local strmatch = string.match;
local tonumber = tonumber;
local floor = math.floor;
local min = math.min;
local max = math.max;

-- Item quality colors (fallback if API unavailable)
local QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, name = "Poor" },
    [1] = { r = 1.00, g = 1.00, b = 1.00, name = "Common" },
    [2] = { r = 0.12, g = 1.00, b = 0.00, name = "Uncommon" },
    [3] = { r = 0.00, g = 0.44, b = 0.87, name = "Rare" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, name = "Epic" },
    [5] = { r = 1.00, g = 0.50, b = 0.00, name = "Legendary" },
    [6] = { r = 0.00, g = 0.80, b = 1.00, name = "Artifact" },
    [7] = { r = 0.90, g = 0.80, b = 0.50, name = "Heirloom" },
};

-- State
local messagePool = {};
local activeMessages = {};
local db;

-- Live preview state
local livePreviewActive = false;
local livePreviewTimer = 0;
local LIVE_PREVIEW_INTERVAL = 1.5; -- Spawn new preview every 1.5 seconds

-- Main frame
local ScrollingLoot = CreateFrame("Frame", "ScrollingLootFrame", UIParent);
ScrollingLoot:SetAllPoints();
ScrollingLoot:SetFrameStrata("HIGH");

--------------------------------------------------------------------------------
-- Core Addon Functions
--------------------------------------------------------------------------------

-- Create a message frame (icon + text + optional background)
local function CreateMessageFrame()
    local frame = CreateFrame("Frame", nil, ScrollingLoot);
    frame:SetSize(300, 32);
    frame:Hide();

    -- Background texture (behind everything) - sized dynamically
    frame.background = frame:CreateTexture(nil, "BACKGROUND");
    frame.background:SetColorTexture(0, 0, 0, 0.7);
    frame.background:Hide();

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK");
    frame.icon:SetSize(DEFAULT_SETTINGS.iconSize, DEFAULT_SETTINGS.iconSize);
    frame.icon:SetPoint("LEFT", 0, 0);

    -- Item name text
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0);
    frame.text:SetJustifyH("LEFT");

    -- Animation state
    frame.scrollTime = 0;
    frame.startX = 0;
    frame.startY = 0;
    frame.isPreview = false;

    return frame;
end

-- Get a frame from pool or create new one
local function AcquireMessageFrame()
    local frame = tremove(messagePool);
    if not frame then
        frame = CreateMessageFrame();
    end
    return frame;
end

-- Return frame to pool
local function ReleaseMessageFrame(frame)
    frame:Hide();
    frame:ClearAllPoints();
    frame.scrollTime = 0;
    frame.isPreview = false;
    frame.background:Hide();
    tinsert(messagePool, frame);
end

-- Get quality color
local function GetQualityColor(quality)
    -- Try API first (Classic TBC)
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality);
        if r then
            return r, g, b;
        end
    end

    -- Try global function
    if GetItemQualityColor then
        local r, g, b = GetItemQualityColor(quality);
        if r then
            return r, g, b;
        end
    end

    -- Fallback to local table
    local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1];
    return color.r, color.g, color.b;
end

-- Calculate position based on scroll progress
local function CalculatePosition(frame)
    local progress = frame.scrollTime / db.scrollSpeed;
    local yOffset = db.scrollDistance * progress;
    return frame.startX, frame.startY + yOffset;
end

-- Add a loot message to display (internal, skips enabled check for preview)
local function AddLootMessageInternal(itemName, itemIcon, itemQuality, quantity, isPreview)
    if not isPreview and not db.enabled then return; end
    if not isPreview and itemQuality < db.minQuality then return; end

    -- Limit active messages
    while #activeMessages >= db.maxMessages do
        local oldFrame = tremove(activeMessages, 1);
        ReleaseMessageFrame(oldFrame);
    end

    local frame = AcquireMessageFrame();
    frame.isPreview = isPreview;

    -- Set icon
    frame.icon:SetTexture(itemIcon);
    frame.icon:SetSize(db.iconSize, db.iconSize);

    -- Set text with quality color
    local r, g, b = GetQualityColor(itemQuality);
    local displayText = itemName;
    if db.showQuantity and quantity and quantity > 1 then
        displayText = format("%s x%d", itemName, quantity);
    end
    frame.text:SetText(displayText);
    frame.text:SetTextColor(r, g, b);
    frame.text:SetFont(frame.text:GetFont(), db.fontSize, "OUTLINE");

    -- Configure background (hybrid: actual width with min/max bounds)
    if db.showBackground then
        local textWidth = frame.text:GetStringWidth();
        local contentWidth = db.iconSize + 4 + textWidth;
        local contentHeight = max(db.iconSize, db.fontSize + 4);
        local padding = 6;

        -- Clamp width to reasonable bounds
        local minWidth = 180;
        local maxWidth = 320;
        local bgWidth = max(minWidth, min(maxWidth, contentWidth + (padding * 2)));

        frame.background:ClearAllPoints();
        frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", -padding, padding);
        frame.background:SetSize(bgWidth, contentHeight + (padding * 2));
        frame.background:SetColorTexture(0, 0, 0, 0.7);
        frame.background:Show();
    else
        frame.background:Hide();
    end

    -- Calculate start position relative to screen center
    local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale();
    local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
    local centerX = screenWidth / 2;
    local centerY = screenHeight / 2;

    if db.anchorPoint == "RIGHT" then
        frame.startX = centerX + db.startOffsetX;
    else
        frame.startX = centerX - db.startOffsetX - 200;
    end
    frame.startY = centerY + db.startOffsetY;

    -- Stack messages to avoid overlap
    for _, existingFrame in ipairs(activeMessages) do
        local _, existingY = CalculatePosition(existingFrame);
        local overlap = frame.startY - existingY;
        if overlap > -30 and overlap < 30 then
            frame.startY = existingY - 30;
        end
    end

    -- Position and show
    frame.scrollTime = 0;
    frame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", frame.startX, frame.startY);
    frame:SetAlpha(1);
    frame:Show();

    tinsert(activeMessages, frame);
end

-- Add a loot message to display (public API)
local function AddLootMessage(itemName, itemIcon, itemQuality, quantity)
    AddLootMessageInternal(itemName, itemIcon, itemQuality, quantity, false);
end

-- Add a preview message (always shows regardless of enabled state)
local function AddPreviewMessage()
    local qualities = {2, 3, 4, 5};
    local quality = qualities[math.random(1, #qualities)];
    local icons = {
        "Interface\\Icons\\INV_Misc_Gem_01",
        "Interface\\Icons\\INV_Misc_Gem_02",
        "Interface\\Icons\\INV_Sword_04",
        "Interface\\Icons\\INV_Helmet_01",
        "Interface\\Icons\\INV_Jewelry_Ring_14",
    };
    local names = {
        "[Preview Epic Item]",
        "[Preview Rare Sword]",
        "[Preview Uncommon Helm]",
        "[Preview Legendary Ring]",
        "[Preview Blue Gem]",
    };

    local idx = math.random(1, #icons);
    AddLootMessageInternal(names[idx], icons[idx], quality, 1, true);
end

-- Parse item link to extract info
local function ParseItemLink(itemLink)
    if not itemLink then return nil; end

    -- Extract item ID from link: |cff......|Hitem:12345:...|h[Item Name]|h|r
    local itemID = strmatch(itemLink, "item:(%d+)");
    if not itemID then return nil; end

    -- Get item info
    local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink);

    if not itemName then
        -- Item not cached, try with just the ID
        itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(tonumber(itemID));
    end

    return itemName, itemIcon, itemQuality;
end

-- Parse loot message to extract item link and quantity
local function ParseLootMessage(message)
    if not message then return nil; end

    -- Pattern: "You receive loot: |cff......|Hitem:...|h[Item Name]|h|r"
    -- Or with quantity: "You receive loot: |cff......|Hitem:...|h[Item Name]|h|rx2"
    local itemLink = strmatch(message, "(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)");
    if not itemLink then return nil; end

    -- Check for quantity
    local quantity = strmatch(message, "|rx(%d+)") or strmatch(message, "|r ?x(%d+)");
    quantity = quantity and tonumber(quantity) or 1;

    return itemLink, quantity;
end

-- OnUpdate handler for animation
local function OnUpdate(self, elapsed)
    -- Handle live preview spawning
    if livePreviewActive then
        livePreviewTimer = livePreviewTimer + elapsed;
        if livePreviewTimer >= LIVE_PREVIEW_INTERVAL then
            livePreviewTimer = 0;
            AddPreviewMessage();
        end
    end

    -- Animate active messages
    if #activeMessages == 0 then return; end

    local i = 1;
    while i <= #activeMessages do
        local frame = activeMessages[i];
        frame.scrollTime = frame.scrollTime + elapsed;

        -- Check if animation complete
        if frame.scrollTime >= db.scrollSpeed then
            tremove(activeMessages, i);
            ReleaseMessageFrame(frame);
        else
            -- Update position
            local x, y = CalculatePosition(frame);
            frame:ClearAllPoints();
            frame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x, y);

            -- Fade out near end
            if frame.scrollTime >= db.fadeStartTime then
                local fadeProgress = (frame.scrollTime - db.fadeStartTime) /
                                    (db.scrollSpeed - db.fadeStartTime);
                frame:SetAlpha(1 - fadeProgress);
            end

            i = i + 1;
        end
    end
end

-- Start live preview
local function StartLivePreview()
    livePreviewActive = true;
    livePreviewTimer = LIVE_PREVIEW_INTERVAL; -- Spawn one immediately
end

-- Stop live preview
local function StopLivePreview()
    livePreviewActive = false;
    livePreviewTimer = 0;
    -- Clear any preview messages
    local i = 1;
    while i <= #activeMessages do
        if activeMessages[i].isPreview then
            local frame = tremove(activeMessages, i);
            ReleaseMessageFrame(frame);
        else
            i = i + 1;
        end
    end
end

--------------------------------------------------------------------------------
-- Options GUI (Ace3-Style)
--------------------------------------------------------------------------------

local OptionsFrame;

-- Backdrop templates
local FrameBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
};

local SliderBackdrop = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 }
};

local EditBoxBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, edgeSize = 1, tileSize = 5,
};

local PaneBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 5, bottom = 3 }
};

-- Create a slider widget (Ace3 style)
local function CreateSlider(parent, label, minVal, maxVal, step, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 50);

    -- Label
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    labelText:SetPoint("TOPLEFT");
    labelText:SetPoint("TOPRIGHT");
    labelText:SetJustifyH("CENTER");
    labelText:SetHeight(15);
    labelText:SetText(label);
    labelText:SetTextColor(1, 0.82, 0);

    -- Slider frame
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate");
    slider:SetOrientation("HORIZONTAL");
    slider:SetSize(width or 200, 15);
    slider:SetPoint("TOP", labelText, "BOTTOM", 0, -2);
    slider:SetBackdrop(SliderBackdrop);
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal");
    slider:SetMinMaxValues(minVal, maxVal);
    slider:SetValueStep(step or 1);
    slider:SetObeyStepOnDrag(true);

    -- Min/Max labels
    local lowText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 3);
    lowText:SetText(minVal);

    local highText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 3);
    highText:SetText(maxVal);

    -- Editable value box
    local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate");
    editBox:SetAutoFocus(false);
    editBox:SetFontObject(GameFontHighlightSmall);
    editBox:SetPoint("TOP", slider, "BOTTOM", 0, -2);
    editBox:SetSize(60, 14);
    editBox:SetJustifyH("CENTER");
    editBox:EnableMouse(true);
    editBox:SetBackdrop(EditBoxBackdrop);
    editBox:SetBackdropColor(0, 0, 0, 0.5);
    editBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8);

    -- Wire up slider <-> editbox sync
    slider:SetScript("OnValueChanged", function(self, value)
        value = floor(value / step + 0.5) * step;
        editBox:SetText(value);
        if container.OnValueChanged then
            container:OnValueChanged(value);
        end
    end);

    editBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText());
        if value then
            value = max(minVal, min(maxVal, value));
            slider:SetValue(value);
        end
        self:ClearFocus();
    end);

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(floor(slider:GetValue() / step + 0.5) * step);
        self:ClearFocus();
    end);

    -- API
    container.slider = slider;
    container.editBox = editBox;
    container.labelText = labelText;

    function container:SetValue(value)
        slider:SetValue(value);
        editBox:SetText(floor(value / step + 0.5) * step);
    end

    function container:GetValue()
        return slider:GetValue();
    end

    function container:SetMinMax(newMin, newMax)
        slider:SetMinMaxValues(newMin, newMax);
        lowText:SetText(newMin);
        highText:SetText(newMax);
        -- Clamp current value if needed
        local currentVal = slider:GetValue();
        if currentVal < newMin then
            slider:SetValue(newMin);
        elseif currentVal > newMax then
            slider:SetValue(newMax);
        end
    end

    return container;
end

-- Create a checkbox widget (Ace3 style)
local function CreateCheckbox(parent, label, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 24);

    local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate");
    checkbox:SetPoint("LEFT");
    checkbox:SetSize(24, 24);

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    labelText:SetPoint("LEFT", checkbox, "RIGHT", 2, 0);
    labelText:SetText(label);

    checkbox:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and 856 or 857);
        if container.OnValueChanged then
            container:OnValueChanged(self:GetChecked());
        end
    end);

    container.checkbox = checkbox;
    container.labelText = labelText;

    function container:SetValue(value)
        checkbox:SetChecked(value);
    end

    function container:GetValue()
        return checkbox:GetChecked();
    end

    return container;
end

-- Create a dropdown widget (Ace3 style)
local function CreateDropdown(parent, label, options, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 50);

    -- Label
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    labelText:SetPoint("TOPLEFT");
    labelText:SetPoint("TOPRIGHT");
    labelText:SetJustifyH("CENTER");
    labelText:SetHeight(15);
    labelText:SetText(label);
    labelText:SetTextColor(1, 0.82, 0);

    -- Dropdown frame (simple button-based)
    local dropdown = CreateFrame("Frame", nil, container, "BackdropTemplate");
    dropdown:SetSize(width or 200, 24);
    dropdown:SetPoint("TOP", labelText, "BOTTOM", 0, -2);
    dropdown:SetBackdrop(PaneBackdrop);
    dropdown:SetBackdropColor(0.1, 0.1, 0.1);
    dropdown:SetBackdropBorderColor(0.4, 0.4, 0.4);

    local selectedText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    selectedText:SetPoint("LEFT", 8, 0);
    selectedText:SetPoint("RIGHT", -24, 0);
    selectedText:SetJustifyH("LEFT");

    local expandButton = CreateFrame("Button", nil, dropdown);
    expandButton:SetSize(20, 20);
    expandButton:SetPoint("RIGHT", -2, 0);
    expandButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up");
    expandButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down");
    expandButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");

    -- Menu frame (no gap so mouse doesn't lose hover)
    local menuFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate");
    menuFrame:SetBackdrop(PaneBackdrop);
    menuFrame:SetBackdropColor(0.1, 0.1, 0.1);
    menuFrame:SetBackdropBorderColor(0.4, 0.4, 0.4);
    menuFrame:SetPoint("TOP", dropdown, "BOTTOM", 0, 2); -- Overlap slightly to prevent gap
    menuFrame:SetFrameStrata("TOOLTIP");
    menuFrame:SetFrameLevel(200);
    menuFrame:Hide();

    local menuButtons = {};
    local buttonHeight = 20;
    local menuHeight = 4;

    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, menuFrame);
        btn:SetSize((width or 200) - 6, buttonHeight);
        btn:SetPoint("TOPLEFT", 3, -2 - (i - 1) * buttonHeight);

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
        btnText:SetPoint("LEFT", 4, 0);
        btnText:SetText(opt.text);

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT");
        highlight:SetAllPoints();
        highlight:SetColorTexture(0.3, 0.3, 0.5, 0.5);

        btn:SetScript("OnClick", function()
            container.selectedValue = opt.value;
            selectedText:SetText(opt.text);
            menuFrame:Hide();
            PlaySound(856);
            if container.OnValueChanged then
                container:OnValueChanged(opt.value);
            end
        end);

        menuButtons[i] = btn;
        menuHeight = menuHeight + buttonHeight;
    end

    menuFrame:SetSize((width or 200), menuHeight + 4);

    local function ToggleMenu()
        if menuFrame:IsShown() then
            menuFrame:Hide();
        else
            menuFrame:Show();
        end
    end

    expandButton:SetScript("OnClick", ToggleMenu);
    dropdown:EnableMouse(true);
    dropdown:SetScript("OnMouseDown", ToggleMenu);

    -- Close menu when clicking elsewhere
    menuFrame:SetScript("OnShow", function()
        menuFrame:SetScript("OnUpdate", function()
            if not dropdown:IsMouseOver() and not menuFrame:IsMouseOver() then
                menuFrame:Hide();
            end
        end);
    end);

    menuFrame:SetScript("OnHide", function()
        menuFrame:SetScript("OnUpdate", nil);
    end);

    container.dropdown = dropdown;
    container.selectedText = selectedText;
    container.options = options;

    function container:SetValue(value)
        container.selectedValue = value;
        for _, opt in ipairs(options) do
            if opt.value == value then
                selectedText:SetText(opt.text);
                break;
            end
        end
    end

    function container:GetValue()
        return container.selectedValue;
    end

    return container;
end

-- Create the main options frame
local function CreateOptionsFrame()
    if OptionsFrame then return OptionsFrame; end

    -- Main frame
    local frame = CreateFrame("Frame", "ScrollingLootOptionsFrame", UIParent, "BackdropTemplate");
    frame:SetSize(500, 500);
    frame:SetPoint("CENTER");
    frame:SetBackdrop(FrameBackdrop);
    frame:SetBackdropColor(0, 0, 0, 1);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:SetToplevel(true);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(100);
    frame:Hide();

    -- Title bar
    local titleBg = frame:CreateTexture(nil, "OVERLAY");
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBg:SetTexCoord(0.31, 0.67, 0, 0.63);
    titleBg:SetPoint("TOP", 0, 12);
    titleBg:SetSize(200, 40);

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    titleText:SetPoint("TOP", titleBg, "TOP", 0, -14);
    titleText:SetText("ScrollingLoot Options");

    local titleBgL = frame:CreateTexture(nil, "OVERLAY");
    titleBgL:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgL:SetTexCoord(0.21, 0.31, 0, 0.63);
    titleBgL:SetPoint("RIGHT", titleBg, "LEFT");
    titleBgL:SetSize(30, 40);

    local titleBgR = frame:CreateTexture(nil, "OVERLAY");
    titleBgR:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgR:SetTexCoord(0.67, 0.77, 0, 0.63);
    titleBgR:SetPoint("LEFT", titleBg, "RIGHT");
    titleBgR:SetSize(30, 40);

    -- Make title draggable
    local titleArea = CreateFrame("Frame", nil, frame);
    titleArea:SetAllPoints(titleBg);
    titleArea:EnableMouse(true);
    titleArea:SetScript("OnMouseDown", function() frame:StartMoving(); end);
    titleArea:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); end);

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    closeBtn:SetPoint("TOPRIGHT", -5, -5);

    -- Content area
    local content = CreateFrame("Frame", nil, frame);
    content:SetPoint("TOPLEFT", 20, -30);
    content:SetPoint("BOTTOMRIGHT", -20, 50);

    -- Left column - General Settings
    local leftCol = CreateFrame("Frame", nil, content);
    leftCol:SetPoint("TOPLEFT");
    leftCol:SetSize(220, 350);

    local generalLabel = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    generalLabel:SetPoint("TOPLEFT");
    generalLabel:SetText("General Settings");
    generalLabel:SetTextColor(1, 0.82, 0);

    local yOffset = -25;

    -- Enabled checkbox
    local enabledCheckbox = CreateCheckbox(leftCol, "Enable ScrollingLoot", 200);
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    enabledCheckbox:SetValue(db.enabled);
    enabledCheckbox.OnValueChanged = function(self, value)
        db.enabled = value;
    end;
    yOffset = yOffset - 30;

    -- Show quantity checkbox
    local quantityCheckbox = CreateCheckbox(leftCol, "Show Stack Counts", 200);
    quantityCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    quantityCheckbox:SetValue(db.showQuantity);
    quantityCheckbox.OnValueChanged = function(self, value)
        db.showQuantity = value;
    end;
    yOffset = yOffset - 30;

    -- Show background checkbox
    local bgCheckbox = CreateCheckbox(leftCol, "Show Background", 200);
    bgCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    bgCheckbox:SetValue(db.showBackground);
    bgCheckbox.OnValueChanged = function(self, value)
        db.showBackground = value;
    end;
    yOffset = yOffset - 35;

    -- Anchor point dropdown
    local anchorDropdown = CreateDropdown(leftCol, "Anchor Side", {
        { value = "RIGHT", text = "Right of Center" },
        { value = "LEFT", text = "Left of Center" },
    }, 200);
    anchorDropdown:SetPoint("TOPLEFT", 0, yOffset);
    anchorDropdown:SetValue(db.anchorPoint);
    anchorDropdown.OnValueChanged = function(self, value)
        db.anchorPoint = value;
    end;
    yOffset = yOffset - 55;

    -- Min quality dropdown
    local qualityOptions = {};
    for i = 0, 5 do
        tinsert(qualityOptions, { value = i, text = QUALITY_COLORS[i].name });
    end
    local qualityDropdown = CreateDropdown(leftCol, "Minimum Quality", qualityOptions, 200);
    qualityDropdown:SetPoint("TOPLEFT", 0, yOffset);
    qualityDropdown:SetValue(db.minQuality);
    qualityDropdown.OnValueChanged = function(self, value)
        db.minQuality = value;
    end;
    yOffset = yOffset - 55;

    -- Max messages slider
    local maxMsgSlider = CreateSlider(leftCol, "Max Simultaneous Messages", 1, 20, 1, 200);
    maxMsgSlider:SetPoint("TOPLEFT", 0, yOffset);
    maxMsgSlider:SetValue(db.maxMessages);
    maxMsgSlider.OnValueChanged = function(self, value)
        db.maxMessages = value;
    end;
    yOffset = yOffset - 55;

    -- Position section (in left column)
    local posLabel = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    posLabel:SetPoint("TOPLEFT", 0, yOffset);
    posLabel:SetText("Position");
    posLabel:SetTextColor(1, 0.82, 0);
    yOffset = yOffset - 25;

    -- X offset slider
    local xSlider = CreateSlider(leftCol, "Horizontal Offset", 0, 600, 10, 200);
    xSlider:SetPoint("TOPLEFT", 0, yOffset);
    xSlider:SetValue(db.startOffsetX);
    xSlider.OnValueChanged = function(self, value)
        db.startOffsetX = value;
    end;
    yOffset = yOffset - 55;

    -- Y offset slider
    local ySlider = CreateSlider(leftCol, "Vertical Offset", -400, 400, 10, 200);
    ySlider:SetPoint("TOPLEFT", 0, yOffset);
    ySlider:SetValue(db.startOffsetY);
    ySlider.OnValueChanged = function(self, value)
        db.startOffsetY = value;
    end;

    -- Right column - Appearance & Animation
    local rightCol = CreateFrame("Frame", nil, content);
    rightCol:SetPoint("TOPLEFT", 240, 0);
    rightCol:SetSize(220, 350);

    local appearLabel = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    appearLabel:SetPoint("TOPLEFT");
    appearLabel:SetText("Appearance");
    appearLabel:SetTextColor(1, 0.82, 0);

    yOffset = -25;

    -- Icon size slider
    local iconSlider = CreateSlider(rightCol, "Icon Size", 12, 48, 2, 200);
    iconSlider:SetPoint("TOPLEFT", 0, yOffset);
    iconSlider:SetValue(db.iconSize);
    iconSlider.OnValueChanged = function(self, value)
        db.iconSize = value;
    end;
    yOffset = yOffset - 55;

    -- Font size slider
    local fontSlider = CreateSlider(rightCol, "Font Size", 8, 32, 1, 200);
    fontSlider:SetPoint("TOPLEFT", 0, yOffset);
    fontSlider:SetValue(db.fontSize);
    fontSlider.OnValueChanged = function(self, value)
        db.fontSize = value;
    end;
    yOffset = yOffset - 55;

    -- Animation section
    local animLabel = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    animLabel:SetPoint("TOPLEFT", 0, yOffset);
    animLabel:SetText("Animation");
    animLabel:SetTextColor(1, 0.82, 0);
    yOffset = yOffset - 25;

    -- Forward declare fadeSlider so speedSlider can reference it
    local fadeSlider;

    -- Scroll speed slider
    local speedSlider = CreateSlider(rightCol, "Scroll Duration (seconds)", 1, 10, 0.5, 200);
    speedSlider:SetPoint("TOPLEFT", 0, yOffset);
    speedSlider:SetValue(db.scrollSpeed);
    speedSlider.OnValueChanged = function(self, value)
        db.scrollSpeed = value;
        -- Update fadeSlider max to be scrollSpeed - 0.5
        if fadeSlider then
            local newMax = value - 0.5;
            fadeSlider:SetMinMax(0.5, newMax);
            -- Clamp fade start time if needed
            if db.fadeStartTime > newMax then
                db.fadeStartTime = newMax;
            end
        end
    end;
    yOffset = yOffset - 55;

    -- Fade start slider (max is scrollSpeed - 0.5)
    fadeSlider = CreateSlider(rightCol, "Fade Start Time (seconds)", 0.5, db.scrollSpeed - 0.5, 0.5, 200);
    fadeSlider:SetPoint("TOPLEFT", 0, yOffset);
    fadeSlider:SetValue(db.fadeStartTime);
    fadeSlider.OnValueChanged = function(self, value)
        db.fadeStartTime = value;
    end;
    yOffset = yOffset - 55;

    -- Scroll distance slider
    local distSlider = CreateSlider(rightCol, "Scroll Distance (pixels)", 50, 400, 10, 200);
    distSlider:SetPoint("TOPLEFT", 0, yOffset);
    distSlider:SetValue(db.scrollDistance);
    distSlider.OnValueChanged = function(self, value)
        db.scrollDistance = value;
    end;

    -- Bottom buttons
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    closeButton:SetSize(100, 22);
    closeButton:SetPoint("BOTTOMRIGHT", -20, 15);
    closeButton:SetText("Close");
    closeButton:SetScript("OnClick", function()
        frame:Hide();
    end);

    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    resetBtn:SetSize(100, 22);
    resetBtn:SetPoint("BOTTOMLEFT", 20, 15);
    resetBtn:SetText("Reset Defaults");
    resetBtn:SetScript("OnClick", function()
        -- Reset all settings
        for key, value in pairs(DEFAULT_SETTINGS) do
            db[key] = value;
        end
        -- Update all widgets
        enabledCheckbox:SetValue(db.enabled);
        quantityCheckbox:SetValue(db.showQuantity);
        bgCheckbox:SetValue(db.showBackground);
        anchorDropdown:SetValue(db.anchorPoint);
        qualityDropdown:SetValue(db.minQuality);
        maxMsgSlider:SetValue(db.maxMessages);
        iconSlider:SetValue(db.iconSize);
        fontSlider:SetValue(db.fontSize);
        speedSlider:SetValue(db.scrollSpeed);
        fadeSlider:SetValue(db.fadeStartTime);
        distSlider:SetValue(db.scrollDistance);
        xSlider:SetValue(db.startOffsetX);
        ySlider:SetValue(db.startOffsetY);
        print("|cff00ff00ScrollingLoot|r settings reset to defaults.");
    end);

    -- Live preview info text
    local previewInfo = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    previewInfo:SetPoint("BOTTOM", 0, 18);
    previewInfo:SetText("Live preview active while options are open");
    previewInfo:SetTextColor(0.7, 0.7, 0.7);

    -- OnShow/OnHide for live preview
    frame:SetScript("OnShow", function()
        StartLivePreview();
    end);

    frame:SetScript("OnHide", function()
        StopLivePreview();
    end);

    -- ESC to close
    tinsert(UISpecialFrames, "ScrollingLootOptionsFrame");

    OptionsFrame = frame;
    return frame;
end

-- Toggle options frame
local function ToggleOptionsFrame()
    if not OptionsFrame then
        CreateOptionsFrame();
    end

    if OptionsFrame:IsShown() then
        OptionsFrame:Hide();
    else
        OptionsFrame:Show();
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

-- Event handler
local function OnEvent(self, event, ...)
    if event == "CHAT_MSG_LOOT" then
        local message, _, _, _, playerName = ...;

        -- Only show our own loot
        local myName = UnitName("player");
        if playerName and playerName ~= "" and playerName ~= myName then
            return;
        end

        -- Also check message content for "You receive"
        if not strmatch(message, "You receive") and not strmatch(message, myName) then
            -- Might be someone else's loot, skip
            if strmatch(message, "receives loot") then
                return;
            end
        end

        local itemLink, quantity = ParseLootMessage(message);
        if not itemLink then return; end

        local itemName, itemIcon, itemQuality = ParseItemLink(itemLink);
        if itemName and itemIcon then
            AddLootMessage(itemName, itemIcon, itemQuality or 1, quantity);
        end

    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...;
        if loadedAddon == addonName then
            -- Initialize saved variables
            if not ScrollingLootDB then
                ScrollingLootDB = {};
            end

            -- Copy defaults for any missing values
            for key, value in pairs(DEFAULT_SETTINGS) do
                if ScrollingLootDB[key] == nil then
                    ScrollingLootDB[key] = value;
                end
            end

            db = ScrollingLootDB;

            self:UnregisterEvent("ADDON_LOADED");
            print("|cff00ff00ScrollingLoot|r loaded. Type |cff00ffff/sloot|r for options.");
        end

    elseif event == "PLAYER_LOGIN" then
        -- Additional initialization if needed
    end
end

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

local function SlashCommandHandler(msg)
    msg = msg and msg:lower():trim() or "";

    if msg == "" or msg == "options" or msg == "config" then
        ToggleOptionsFrame();

    elseif msg == "on" or msg == "enable" then
        db.enabled = true;
        print("|cff00ff00ScrollingLoot|r enabled.");

    elseif msg == "off" or msg == "disable" then
        db.enabled = false;
        print("|cff00ff00ScrollingLoot|r disabled.");

    elseif msg == "test" then
        AddLootMessage("[Test Epic Item]", "Interface\\Icons\\INV_Misc_Gem_01", 4, 1);
        AddLootMessage("[Test Rare Item]", "Interface\\Icons\\INV_Misc_Gem_02", 3, 5);
        AddLootMessage("[Test Uncommon Item]", "Interface\\Icons\\INV_Misc_Gem_03", 2, 1);

    elseif msg == "reset" then
        for key, value in pairs(DEFAULT_SETTINGS) do
            db[key] = value;
        end
        print("|cff00ff00ScrollingLoot|r settings reset to defaults.");

    elseif msg == "help" then
        print("|cff00ff00ScrollingLoot|r commands:");
        print("  |cff00ffff/sloot|r - Open options panel (with live preview)");
        print("  |cff00ffff/sloot test|r - Show test messages");
        print("  |cff00ffff/sloot on/off|r - Enable/disable addon");
        print("  |cff00ffff/sloot reset|r - Reset to defaults");

    else
        print("|cff00ff00ScrollingLoot|r: Unknown command. Use |cff00ffff/sloot help|r for commands.");
    end
end

-- Register slash commands
SLASH_SCROLLINGLOOT1 = "/scrollingloot";
SLASH_SCROLLINGLOOT2 = "/sloot";
SlashCmdList["SCROLLINGLOOT"] = SlashCommandHandler;

-- Set up event handling
ScrollingLoot:SetScript("OnUpdate", OnUpdate);
ScrollingLoot:SetScript("OnEvent", OnEvent);
ScrollingLoot:RegisterEvent("CHAT_MSG_LOOT");
ScrollingLoot:RegisterEvent("ADDON_LOADED");
ScrollingLoot:RegisterEvent("PLAYER_LOGIN");

-- Initialize db with defaults (will be overwritten on ADDON_LOADED)
db = DEFAULT_SETTINGS;
