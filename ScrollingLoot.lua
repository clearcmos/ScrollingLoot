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
    startOffsetX = 200,         -- Horizontal offset from screen center (negative = left, positive = right)
    startOffsetY = -20,         -- Vertical offset from screen center (negative = below)
    scrollDistance = 150,       -- How far text scrolls upward
    staticMode = false,         -- Static mode: no scrolling, just fade in place
    maxMessages = 10,           -- Maximum simultaneous messages
    showQuantity = true,        -- Show stack counts
    minQuality = 0,             -- Minimum quality to show (0 = all)
    showBackground = false,     -- Show background behind loot text
    backgroundOpacity = 0.7,    -- Background opacity (0.0 to 1.0)
    fastLoot = false,           -- Fast loot: auto-loot and hide loot window (hold SHIFT to show)
    bopFrameOffsetX = 0,        -- BoP confirmation frame X offset from center
    bopFrameOffsetY = 100,      -- BoP confirmation frame Y offset from center
    glowEnabled = false,        -- Enable glow effect on loot notifications
    glowMinQuality = 0,         -- Minimum quality for glow (0 = all)
    showMoney = true,           -- Show money pickups (gold, silver, copper)
    showHonor = true,           -- Show honor points gained
    honorColor = { r = 0.8, g = 0.2, b = 1.0 },  -- Honor text color (default purple)
    textAlign = "left",         -- Text alignment: "left", "center", or "right"
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
local gsub = string.gsub;

-- Build localized pattern for "You receive loot:" from LOOT_ITEM_SELF
-- LOOT_ITEM_SELF is "You receive loot: %s" in English, localized in other languages
local function BuildLootSelfPattern()
    -- LOOT_ITEM_SELF format: "You receive loot: %s" (where %s is the item link)
    local pattern = LOOT_ITEM_SELF or "You receive loot: %s";
    -- Escape Lua pattern special characters, then replace %s with (.+)
    pattern = gsub(pattern, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1");
    pattern = gsub(pattern, "%%%%s", "(.+)");
    return "^" .. pattern;
end
local LOOT_SELF_PATTERN = BuildLootSelfPattern();

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

-- Track when honor color picker is active (for preview filtering)
local honorColorPickerActive = false;


-- Draggable preview area frame
local PreviewAreaFrame = nil;

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

    -- Glow texture (for proc-style effect) - around icon only
    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 7);
    frame.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert");
    frame.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375);
    frame.glow:SetBlendMode("ADD");
    frame.glow:SetAlpha(0);
    frame.glow:SetPoint("CENTER", frame.icon, "CENTER", 0, 0);

    -- Glow animation group
    frame.glowAnimGroup = frame.glow:CreateAnimationGroup();

    -- Fade in
    local fadeIn = frame.glowAnimGroup:CreateAnimation("Alpha");
    fadeIn:SetFromAlpha(0);
    fadeIn:SetToAlpha(0.8);
    fadeIn:SetDuration(0.2);
    fadeIn:SetOrder(1);

    -- Hold
    local hold = frame.glowAnimGroup:CreateAnimation("Alpha");
    hold:SetFromAlpha(0.8);
    hold:SetToAlpha(0.8);
    hold:SetDuration(0.4);
    hold:SetOrder(2);

    -- Fade out
    local fadeOut = frame.glowAnimGroup:CreateAnimation("Alpha");
    fadeOut:SetFromAlpha(0.8);
    fadeOut:SetToAlpha(0);
    fadeOut:SetDuration(0.4);
    fadeOut:SetOrder(3);

    frame.glowAnimGroup:SetScript("OnFinished", function()
        frame.glow:SetAlpha(0);
    end);

    -- Animation state
    frame.scrollTime = 0;
    frame.stackOffsetY = 0;  -- Offset from base spawn point (for stacking)
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
    frame.stackOffsetY = 0;
    frame.contentWidth = nil;
    frame.isPreview = false;
    frame.background:Hide();
    frame.glowAnimGroup:Stop();
    frame.glow:SetAlpha(0);
    -- Reset icon anchor to default (in case it was modified by honor messages)
    frame.icon:ClearAllPoints();
    frame.icon:SetPoint("LEFT", 0, 0);
    -- Reset text anchor to default
    frame.text:ClearAllPoints();
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0);
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
-- Uses current db offset so messages follow when dragging the preview area
local function CalculatePosition(frame)
    local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale();
    local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
    local centerX = screenWidth / 2;
    local centerY = screenHeight / 2;

    -- Base position from current settings + message's stack offset
    local baseX = centerX + db.startOffsetX;
    local baseY = centerY + db.startOffsetY + frame.stackOffsetY;

    -- Adjust x position based on text alignment
    if frame.contentWidth then
        if db.textAlign == "center" then
            -- Center: offset by half the content width
            baseX = baseX - (frame.contentWidth / 2);
        elseif db.textAlign == "right" then
            -- Right: offset by full content width so right edge aligns with target
            baseX = baseX - frame.contentWidth;
        end
        -- Left: no offset needed (default)
    end

    -- Add scroll progress (only if not in static mode)
    if not db.staticMode then
        local progress = frame.scrollTime / db.scrollSpeed;
        local scrollOffset = db.scrollDistance * progress;
        baseY = baseY + scrollOffset;
    end

    return baseX, baseY;
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

    -- Calculate text gap (extra indent when glow is enabled)
    local textGap = 4;
    if db.glowEnabled and itemQuality >= db.glowMinQuality then
        textGap = 12; -- Extra space for glow
    end

    -- Set text with quality color
    local r, g, b = GetQualityColor(itemQuality);
    local displayText = itemName;
    if db.showQuantity and quantity and quantity > 1 then
        displayText = format("%s x%d", itemName, quantity);
    end
    frame.text:SetText(displayText);
    frame.text:SetTextColor(r, g, b);
    frame.text:SetFont(frame.text:GetFont(), db.fontSize, "OUTLINE");
    frame.text:ClearAllPoints();
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", textGap, 0);

    -- Calculate and store content width (for center alignment)
    local textWidth = frame.text:GetStringWidth();
    frame.contentWidth = db.iconSize + textGap + textWidth;

    -- Configure background (hybrid: actual width with min/max bounds)
    if db.showBackground then
        local contentWidth = frame.contentWidth + 8; -- Extra 8px to ensure text is fully covered
        local contentHeight = max(db.iconSize, db.fontSize + 4);
        local padding = 6;

        -- For center alignment, fit to content; for left/right alignment, use minimum width
        local bgWidth;
        if db.textAlign == "center" then
            bgWidth = contentWidth + (padding * 2);
        else
            local minWidth = 180;
            bgWidth = max(minWidth, contentWidth + (padding * 2));
        end

        frame.background:ClearAllPoints();
        if db.textAlign == "center" then
            -- Center background around the content
            local contentCenter = frame.contentWidth / 2;
            frame.background:SetPoint("CENTER", frame, "LEFT", contentCenter, 0);
        elseif db.textAlign == "right" then
            -- Right-align background to extend leftward from content
            frame.background:SetPoint("RIGHT", frame, "LEFT", frame.contentWidth + padding, 0);
        else
            -- Left-align (default)
            frame.background:SetPoint("LEFT", frame, "LEFT", -padding, 0);
        end
        frame.background:SetSize(bgWidth, contentHeight + (padding * 2));
        frame.background:SetColorTexture(0, 0, 0, db.backgroundOpacity);
        frame.background:Show();
    else
        frame.background:Hide();
    end

    -- Calculate stack offset to avoid overlap with existing messages
    -- Spacing based on content height plus margin (extra padding if background shown)
    local contentHeight = max(db.iconSize, db.fontSize + 4);
    local stackSpacing = contentHeight + (db.showBackground and 14 or 6);

    frame.stackOffsetY = 0;
    for _, existingFrame in ipairs(activeMessages) do
        -- Check if this message would overlap with existing one
        local existingY;
        if db.staticMode then
            -- In static mode, no scroll offset - just use stack offset
            existingY = existingFrame.stackOffsetY;
        else
            -- In scroll mode, account for scroll progress
            local existingProgress = existingFrame.scrollTime / db.scrollSpeed;
            local existingScrollOffset = db.scrollDistance * existingProgress;
            existingY = existingFrame.stackOffsetY + existingScrollOffset;
        end

        local overlap = frame.stackOffsetY - existingY;
        if overlap > -stackSpacing and overlap < stackSpacing then
            frame.stackOffsetY = existingY - stackSpacing;
        end
    end

    -- Position and show
    frame.scrollTime = 0;
    local x, y = CalculatePosition(frame);
    frame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x, y);
    -- Static mode: start at 0 alpha for fade-in effect
    if db.staticMode then
        frame:SetAlpha(0);
    else
        frame:SetAlpha(1);
    end
    frame:Show();

    -- Trigger glow effect if enabled and quality meets threshold
    if db.glowEnabled and itemQuality >= db.glowMinQuality then
        local glowSize = db.iconSize * 2.5; -- Chunky glow around icon
        frame.glow:SetSize(glowSize, glowSize);
        frame.glowAnimGroup:Stop();
        frame.glow:SetAlpha(0);
        frame.glowAnimGroup:Play();
    end

    tinsert(activeMessages, frame);
end

-- Add a loot message to display (public API)
local function AddLootMessage(itemName, itemIcon, itemQuality, quantity)
    AddLootMessageInternal(itemName, itemIcon, itemQuality, quantity, false);
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

--------------------------------------------------------------------------------
-- Money Display Functions
--------------------------------------------------------------------------------

-- Constants for money conversion
local COPPER_PER_SILVER = 100;
local SILVER_PER_GOLD = 100;
local COPPER_PER_GOLD = COPPER_PER_SILVER * SILVER_PER_GOLD;

-- Icons for currency (copper/silver/gold coins)
-- 01-02 = gold, 03-04 = silver, 05-06 = copper
local GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01";
local SILVER_ICON = "Interface\\Icons\\INV_Misc_Coin_03";
local COPPER_ICON = "Interface\\Icons\\INV_Misc_Coin_05";

-- Honor icons (faction-specific square PvP banner icons from Icons folder)
local HORDE_HONOR_ICON = "Interface\\Icons\\INV_BannerPVP_01";
local ALLIANCE_HONOR_ICON = "Interface\\Icons\\INV_BannerPVP_02";

-- Get faction-appropriate honor icon
local function GetHonorIcon()
    local faction = UnitFactionGroup("player");
    if faction == "Horde" then
        return HORDE_HONOR_ICON;
    else
        return ALLIANCE_HONOR_ICON;
    end
end

-- Get appropriate coin icon based on amount
local function GetMoneyIcon(copper)
    if copper >= COPPER_PER_GOLD then
        return GOLD_ICON;
    elseif copper >= COPPER_PER_SILVER then
        return SILVER_ICON;
    else
        return COPPER_ICON;
    end
end

-- Money color (golden/yellow)
local MONEY_COLOR = { r = 1.0, g = 0.82, b = 0.0 };

-- Honor color is now configurable via db.honorColor

-- Track previous money for delta calculation
local previousMoney = nil;

-- Build localized patterns for parsing money from chat messages
-- GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT are localized strings like "%d Gold"
local function BuildMoneyPattern(formatString)
    -- Escape Lua pattern special characters, then replace %d with (%d+)
    local pattern = gsub(formatString, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1");
    pattern = gsub(pattern, "%%%%d", "(%%d+)");
    return pattern;
end

local GOLD_PATTERN = BuildMoneyPattern(GOLD_AMOUNT or "%d Gold");
local SILVER_PATTERN = BuildMoneyPattern(SILVER_AMOUNT or "%d Silver");
local COPPER_PATTERN = BuildMoneyPattern(COPPER_AMOUNT or "%d Copper");

-- Parse money from chat message text (e.g., "You loot 7 Silver, 23 Copper")
-- Returns total copper amount, or nil if parsing fails
local function ParseMoneyFromText(message)
    if not message then return nil; end

    local gold = tonumber(strmatch(message, GOLD_PATTERN)) or 0;
    local silver = tonumber(strmatch(message, SILVER_PATTERN)) or 0;
    local copper = tonumber(strmatch(message, COPPER_PATTERN)) or 0;

    local total = (gold * COPPER_PER_GOLD) + (silver * COPPER_PER_SILVER) + copper;

    return total > 0 and total or nil;
end

-- Format money amount into readable string (e.g., "1g 50s 25c")
local function FormatMoneyText(copper)
    local gold = floor(copper / COPPER_PER_GOLD);
    local silver = floor((copper - (gold * COPPER_PER_GOLD)) / COPPER_PER_SILVER);
    local copperLeft = copper % COPPER_PER_SILVER;

    local parts = {};
    if gold > 0 then
        tinsert(parts, gold .. "g");
    end
    if silver > 0 then
        tinsert(parts, silver .. "s");
    end
    if copperLeft > 0 or #parts == 0 then
        tinsert(parts, copperLeft .. "c");
    end

    return table.concat(parts, " ");
end

-- Add a money notification
local function AddMoneyMessage(copperAmount, isPreview)
    if not isPreview and not db.enabled then return; end
    if not isPreview and not db.showMoney then return; end
    if copperAmount <= 0 then return; end

    -- Limit active messages
    while #activeMessages >= db.maxMessages do
        local oldFrame = tremove(activeMessages, 1);
        ReleaseMessageFrame(oldFrame);
    end

    local frame = AcquireMessageFrame();
    frame.isPreview = isPreview;

    -- Set icon based on denomination
    frame.icon:SetTexture(GetMoneyIcon(copperAmount));
    frame.icon:SetSize(db.iconSize, db.iconSize);

    -- Calculate text gap
    local textGap = 4;

    -- Set text with money color
    local displayText = FormatMoneyText(copperAmount);
    frame.text:SetText(displayText);
    frame.text:SetTextColor(MONEY_COLOR.r, MONEY_COLOR.g, MONEY_COLOR.b);
    frame.text:SetFont(frame.text:GetFont(), db.fontSize, "OUTLINE");
    frame.text:ClearAllPoints();
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", textGap, 0);

    -- Calculate and store content width (for center alignment)
    local textWidth = frame.text:GetStringWidth();
    frame.contentWidth = db.iconSize + textGap + textWidth;

    -- Configure background
    if db.showBackground then
        local contentWidth = frame.contentWidth + 8;
        local contentHeight = max(db.iconSize, db.fontSize + 4);
        local padding = 6;

        -- For center alignment, fit to content; for left/right alignment, use minimum width
        local bgWidth;
        if db.textAlign == "center" then
            bgWidth = contentWidth + (padding * 2);
        else
            local minWidth = 180;
            bgWidth = max(minWidth, contentWidth + (padding * 2));
        end

        frame.background:ClearAllPoints();
        if db.textAlign == "center" then
            -- Center background around the content
            local contentCenter = frame.contentWidth / 2;
            frame.background:SetPoint("CENTER", frame, "LEFT", contentCenter, 0);
        elseif db.textAlign == "right" then
            -- Right-align background to extend leftward from content
            frame.background:SetPoint("RIGHT", frame, "LEFT", frame.contentWidth + padding, 0);
        else
            -- Left-align (default)
            frame.background:SetPoint("LEFT", frame, "LEFT", -padding, 0);
        end
        frame.background:SetSize(bgWidth, contentHeight + (padding * 2));
        frame.background:SetColorTexture(0, 0, 0, db.backgroundOpacity);
        frame.background:Show();
    else
        frame.background:Hide();
    end

    -- Calculate stack offset
    local contentHeight = max(db.iconSize, db.fontSize + 4);
    local stackSpacing = contentHeight + (db.showBackground and 14 or 6);

    frame.stackOffsetY = 0;
    for _, existingFrame in ipairs(activeMessages) do
        local existingY;
        if db.staticMode then
            existingY = existingFrame.stackOffsetY;
        else
            local existingProgress = existingFrame.scrollTime / db.scrollSpeed;
            local existingScrollOffset = db.scrollDistance * existingProgress;
            existingY = existingFrame.stackOffsetY + existingScrollOffset;
        end

        local overlap = frame.stackOffsetY - existingY;
        if overlap > -stackSpacing and overlap < stackSpacing then
            frame.stackOffsetY = existingY - stackSpacing;
        end
    end

    -- Position and show
    frame.scrollTime = 0;
    local x, y = CalculatePosition(frame);
    frame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x, y);
    if db.staticMode then
        frame:SetAlpha(0);
    else
        frame:SetAlpha(1);
    end
    frame:Show();

    tinsert(activeMessages, frame);
end

-- Add an honor notification
local function AddHonorMessage(honorAmount, isPreview)
    if not isPreview and not db.enabled then return; end
    if not isPreview and not db.showHonor then return; end
    if honorAmount <= 0 then return; end

    -- Limit active messages
    while #activeMessages >= db.maxMessages do
        local oldFrame = tremove(activeMessages, 1);
        ReleaseMessageFrame(oldFrame);
    end

    local frame = AcquireMessageFrame();
    frame.isPreview = isPreview;

    -- Set faction-appropriate honor icon (proper square icons, same size as items)
    frame.icon:SetTexture(GetHonorIcon());
    frame.icon:SetSize(db.iconSize, db.iconSize);

    -- Position text after icon (same as items)
    local textGap = 4;
    local displayText = "+" .. honorAmount .. " Honor";
    frame.text:SetText(displayText);
    frame.text:SetTextColor(db.honorColor.r, db.honorColor.g, db.honorColor.b);
    frame.text:SetFont(frame.text:GetFont(), db.fontSize, "OUTLINE");
    frame.text:ClearAllPoints();
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", textGap, 0);

    -- Calculate and store content width (for center alignment)
    local textWidth = frame.text:GetStringWidth();
    frame.contentWidth = db.iconSize + textGap + textWidth;

    -- Configure background (same as items)
    if db.showBackground then
        local contentWidth = frame.contentWidth + 8;
        local contentHeight = max(db.iconSize, db.fontSize + 4);
        local padding = 6;

        -- For center alignment, fit to content; for left/right alignment, use minimum width
        local bgWidth;
        if db.textAlign == "center" then
            bgWidth = contentWidth + (padding * 2);
        else
            local minWidth = 180;
            bgWidth = max(minWidth, contentWidth + (padding * 2));
        end

        frame.background:ClearAllPoints();
        if db.textAlign == "center" then
            -- Center background around the content
            local contentCenter = frame.contentWidth / 2;
            frame.background:SetPoint("CENTER", frame, "LEFT", contentCenter, 0);
        elseif db.textAlign == "right" then
            -- Right-align background to extend leftward from content
            frame.background:SetPoint("RIGHT", frame, "LEFT", frame.contentWidth + padding, 0);
        else
            -- Left-align (default)
            frame.background:SetPoint("LEFT", frame, "LEFT", -padding, 0);
        end
        frame.background:SetSize(bgWidth, contentHeight + (padding * 2));
        frame.background:SetColorTexture(0, 0, 0, db.backgroundOpacity);
        frame.background:Show();
    else
        frame.background:Hide();
    end

    -- Calculate stack offset (same as items)
    local contentHeight = max(db.iconSize, db.fontSize + 4);
    local stackSpacing = contentHeight + (db.showBackground and 14 or 6);

    frame.stackOffsetY = 0;
    for _, existingFrame in ipairs(activeMessages) do
        local existingY;
        if db.staticMode then
            existingY = existingFrame.stackOffsetY;
        else
            local existingProgress = existingFrame.scrollTime / db.scrollSpeed;
            local existingScrollOffset = db.scrollDistance * existingProgress;
            existingY = existingFrame.stackOffsetY + existingScrollOffset;
        end

        local overlap = frame.stackOffsetY - existingY;
        if overlap > -stackSpacing and overlap < stackSpacing then
            frame.stackOffsetY = existingY - stackSpacing;
        end
    end

    -- Position and show
    frame.scrollTime = 0;
    local x, y = CalculatePosition(frame);
    frame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x, y);
    if db.staticMode then
        frame:SetAlpha(0);
    else
        frame:SetAlpha(1);
    end
    frame:Show();

    tinsert(activeMessages, frame);
end

-- Parse honor amount from chat message
local function ParseHonorMessage(message)
    if not message then return nil; end

    -- Honor messages typically look like "+15 Honor" or "You have gained 15 honor."
    -- Try to extract the number
    local honor = strmatch(message, "%+?(%d+)%s*[Hh]onor");
    if honor then
        return tonumber(honor);
    end

    -- Alternative pattern for "X honorable kill" or similar
    honor = strmatch(message, "(%d+)");
    if honor then
        return tonumber(honor);
    end

    return nil;
end

-- Add a preview message (always shows regardless of enabled state)
local function AddPreviewMessage()
    -- If honor color picker is open, only show honor previews
    if honorColorPickerActive then
        local honorAmounts = {15, 25, 50, 100, 200};
        AddHonorMessage(honorAmounts[math.random(1, #honorAmounts)], true);
        return;
    end

    -- Randomly decide what type of preview to show
    -- Weight towards items but occasionally show money/honor when enabled
    local previewType = math.random(1, 10);

    if previewType <= 2 and db.showMoney then
        -- Show money preview (20% chance when enabled)
        local moneyAmounts = {12345, 5000, 250, 50000, 100};
        AddMoneyMessage(moneyAmounts[math.random(1, #moneyAmounts)], true);
        return;
    elseif previewType <= 4 and db.showHonor then
        -- Show honor preview (20% chance when enabled)
        local honorAmounts = {15, 25, 50, 100, 200};
        AddHonorMessage(honorAmounts[math.random(1, #honorAmounts)], true);
        return;
    end

    -- Default: show item preview
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

-- Fade-in duration for static mode (seconds)
local STATIC_FADE_IN_DURATION = 0.3;

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

            -- Calculate alpha based on fade-in and fade-out
            local alpha = 1;

            -- Fade-in for static mode
            if db.staticMode and frame.scrollTime < STATIC_FADE_IN_DURATION then
                alpha = frame.scrollTime / STATIC_FADE_IN_DURATION;
            end

            -- Fade out near end (applies to both modes)
            if frame.scrollTime >= db.fadeStartTime then
                local fadeProgress = (frame.scrollTime - db.fadeStartTime) /
                                    (db.scrollSpeed - db.fadeStartTime);
                alpha = alpha * (1 - fadeProgress);
            end

            frame:SetAlpha(alpha);

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

-- Create the draggable preview area frame (one large frame covering the preview area)
local function CreatePreviewAreaFrame()
    if PreviewAreaFrame then return PreviewAreaFrame; end

    local frame = CreateFrame("Frame", "ScrollingLootPreviewArea", UIParent);
    frame:SetSize(380, db.scrollDistance + 60); -- Wide enough for text + glow, tall enough for scroll distance
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(50);
    frame:EnableMouse(true);
    frame:SetMovable(true);
    frame:SetClampedToScreen(true);
    frame:Hide();

    -- Light blue hover highlight (covers the whole area)
    frame.highlight = frame:CreateTexture(nil, "BACKGROUND");
    frame.highlight:SetAllPoints();
    frame.highlight:SetColorTexture(0.2, 0.5, 0.8, 0.25);
    frame.highlight:Hide();

    -- Border (shows on hover)
    frame.border = frame:CreateTexture(nil, "BORDER");
    frame.border:SetPoint("TOPLEFT", -2, 2);
    frame.border:SetPoint("BOTTOMRIGHT", 2, -2);
    frame.border:SetColorTexture(0.3, 0.6, 1.0, 0.6);
    frame.border:Hide();

    -- Inner area (to create border effect)
    frame.inner = frame:CreateTexture(nil, "BORDER", nil, 1);
    frame.inner:SetAllPoints();
    frame.inner:SetColorTexture(0, 0, 0, 0);
    frame.inner:Hide();

    -- Hover handlers
    frame:SetScript("OnEnter", function(self)
        self.highlight:Show();
        self.border:Show();
        self.inner:Show();
        SetCursor("Interface\\CURSOR\\UI-Cursor-Move");
    end);

    frame:SetScript("OnLeave", function(self)
        if not self.isDragging then
            self.highlight:Hide();
            self.border:Hide();
            self.inner:Hide();
        end
        SetCursor(nil);
    end);

    -- Drag handlers
    frame:RegisterForDrag("LeftButton");

    frame:SetScript("OnDragStart", function(self)
        self.isDragging = true;
        self.highlight:Show();
        self.border:Show();
        self.inner:Show();
        -- Store initial position and offsets for delta-based movement
        self.dragStartLeft = self:GetLeft();
        self.dragStartTop = self:GetTop();
        self.dragStartOffsetX = db.startOffsetX;
        self.dragStartOffsetY = db.startOffsetY;
        self:StartMoving();
    end);

    -- Real-time update while dragging (delta-based to avoid jitter)
    frame:SetScript("OnUpdate", function(self)
        if self.isDragging then
            local deltaX = self:GetLeft() - self.dragStartLeft;
            local deltaY = self:GetTop() - self.dragStartTop;
            db.startOffsetX = self.dragStartOffsetX + deltaX;
            db.startOffsetY = self.dragStartOffsetY + deltaY;
        end
    end);

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
        self.isDragging = false;

        if not self:IsMouseOver() then
            self.highlight:Hide();
            self.border:Hide();
            self.inner:Hide();
        end

        -- Final delta calculation
        local deltaX = self:GetLeft() - self.dragStartLeft;
        local deltaY = self:GetTop() - self.dragStartTop;
        db.startOffsetX = self.dragStartOffsetX + deltaX;
        db.startOffsetY = self.dragStartOffsetY + deltaY;

        -- Round to nearest 5 for cleaner saved values
        db.startOffsetX = floor(db.startOffsetX / 5 + 0.5) * 5;
        db.startOffsetY = floor(db.startOffsetY / 5 + 0.5) * 5;
    end);

    PreviewAreaFrame = frame;
    return frame;
end

-- Update preview area frame position based on current db settings
local function UpdatePreviewAreaPosition()
    if not PreviewAreaFrame then return; end

    -- Use exact same coordinate calculation as messages do
    local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale();
    local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
    local centerX = screenWidth / 2;
    local centerY = screenHeight / 2;

    local x = centerX + db.startOffsetX;
    local y = centerY + db.startOffsetY;

    local frameWidth = 380;

    if db.staticMode then
        -- Static mode: items spawn at y and stack DOWNWARD (negative Y)
        -- Anchor from TOPLEFT so frame extends downward to contain all items
        local staticHeight = 150; -- Enough for ~4 stacked items + padding for glow/background
        PreviewAreaFrame:SetSize(frameWidth, staticHeight);
        PreviewAreaFrame:ClearAllPoints();
        if db.textAlign == "center" then
            -- Center the frame horizontally around the target position
            PreviewAreaFrame:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, y + 30);
        elseif db.textAlign == "right" then
            -- Right-align: frame extends leftward from target position
            PreviewAreaFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x + 25, y + 30);
        else
            -- Left-align (default): frame extends rightward from target position
            PreviewAreaFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 25, y + 30);
        end
    else
        -- Scroll mode: frame covers the scroll distance
        PreviewAreaFrame:SetSize(frameWidth, db.scrollDistance + 60);
        PreviewAreaFrame:ClearAllPoints();
        if db.textAlign == "center" then
            -- Center the frame horizontally around the target position
            PreviewAreaFrame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y - 20);
        elseif db.textAlign == "right" then
            -- Right-align: frame extends leftward from target position
            PreviewAreaFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", x + 25, y - 20);
        else
            -- Left-align (default): frame extends rightward from target position
            PreviewAreaFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x - 25, y - 20);
        end
    end
end

-- Show preview area frame
local function ShowPreviewArea()
    if not PreviewAreaFrame then
        CreatePreviewAreaFrame();
    end
    UpdatePreviewAreaPosition();
    PreviewAreaFrame:Show();
end

-- Hide preview area frame
local function HidePreviewArea()
    if PreviewAreaFrame then
        PreviewAreaFrame:Hide();
    end
end

--------------------------------------------------------------------------------
-- Fast Loot System
--------------------------------------------------------------------------------

local FastLootFrame = CreateFrame("Frame");
local fastLootDelay = 0;
-- Track when loot window is shown due to exception (master loot or full inventory)
-- When true, use default BoP popup instead of custom one
local usingDefaultLootBehavior = false;
-- Track which slot FastLoot last attempted to loot (for BoP confirmation)
local lastFastLootSlot = nil;

-- Check if player has at least one free inventory slot
local function HasFreeInventorySlot()
    local GetNumFreeSlots = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots;
    for bag = 0, 4 do
        local freeSlots = GetNumFreeSlots(bag);
        if freeSlots and freeSlots > 0 then
            return true;
        end
    end
    return false;
end

-- Perform fast looting of all items
local function DoFastLoot(skipThrottle)
    if skipThrottle or GetTime() - fastLootDelay >= 0.3 then
        fastLootDelay = GetTime();
        -- Fast Loot is already gated by db.fastLoot check in event handler
        -- No need to check auto-loot CVar - addon setting takes precedence
        local lootMethod = C_PartyInfo and C_PartyInfo.GetLootMethod and C_PartyInfo.GetLootMethod();
        if lootMethod == 2 then
            -- Master loot enabled: only fast loot items below threshold
            local lootThreshold = GetLootThreshold();
            for i = GetNumLootItems(), 1, -1 do
                local _, _, _, _, quality, locked = GetLootSlotInfo(i);
                if quality and lootThreshold and quality < lootThreshold and not locked then
                    lastFastLootSlot = i;
                    LootSlot(i);
                end
            end
        else
            -- Normal loot: fast loot everything
            for i = GetNumLootItems(), 1, -1 do
                local _, _, _, _, _, locked = GetLootSlotInfo(i);
                if not locked then
                    lastFastLootSlot = i;
                    LootSlot(i);
                end
            end
        end
    end
end

-- Handle loot events
local function FastLoot_OnEvent(self, event, ...)
    if event == "LOOT_CLOSED" then
        -- Reset state when loot window closes
        usingDefaultLootBehavior = false;
        return;
    end

    if not db.fastLoot then return; end

    -- SHIFT override: show loot window normally
    if IsShiftKeyDown() then
        usingDefaultLootBehavior = true;
        return;
    end

    if event == "LOOT_OPENED" then
        -- Check if master loot has items to distribute
        local hasMasterLootItems = false;
        local lootMethod = C_PartyInfo and C_PartyInfo.GetLootMethod and C_PartyInfo.GetLootMethod();
        if lootMethod == 2 then
            local lootThreshold = GetLootThreshold();
            for i = 1, GetNumLootItems() do
                local _, _, _, _, quality = GetLootSlotInfo(i);
                if quality and lootThreshold and quality >= lootThreshold then
                    hasMasterLootItems = true;
                    break;
                end
            end
        end

        -- Check if inventory is full
        local inventoryFull = not HasFreeInventorySlot();

        -- If master loot items or inventory full, show loot window normally
        if hasMasterLootItems or inventoryFull then
            usingDefaultLootBehavior = true;
            return;
        end

        -- Safe to hide the loot frame
        usingDefaultLootBehavior = false;
        if LootFrame and LootFrame:IsShown() then
            LootFrame:Hide();
        end
    elseif event == "LOOT_READY" then
        DoFastLoot();
    elseif event == "LOOT_SLOT_CLEARED" then
        -- Retry after each slot clears (e.g. containers with multiple items)
        DoFastLoot(true);
    end
end

FastLootFrame:RegisterEvent("LOOT_OPENED");
FastLootFrame:RegisterEvent("LOOT_READY");
FastLootFrame:RegisterEvent("LOOT_SLOT_CLEARED");
FastLootFrame:RegisterEvent("LOOT_CLOSED");
FastLootFrame:SetScript("OnEvent", FastLoot_OnEvent);

--------------------------------------------------------------------------------
-- BoP Confirmation Frame (Enhanced)
--------------------------------------------------------------------------------

local BoPConfirmFrame = nil;
local BoPPreviewAreaFrame = nil;
local pendingBoPSlot = nil;

-- Create the BoP confirmation frame
local function CreateBoPConfirmFrame()
    if BoPConfirmFrame then return BoPConfirmFrame; end

    local frame = CreateFrame("Frame", "ScrollingLootBoPConfirmFrame", UIParent, "BackdropTemplate");
    frame:SetSize(280, 150);
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100);
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    });
    frame:SetBackdropColor(0, 0, 0, 1);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(100);
    frame:SetMovable(true);
    frame:SetClampedToScreen(true);
    frame:EnableMouse(true);
    frame:Hide();

    -- Item icon
    frame.icon = frame:CreateTexture(nil, "ARTWORK");
    frame.icon:SetSize(36, 36);
    frame.icon:SetPoint("TOPLEFT", 15, -15);

    -- Item name
    frame.itemName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    frame.itemName:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -2);
    frame.itemName:SetPoint("RIGHT", frame, "RIGHT", -15, 0);
    frame.itemName:SetJustifyH("LEFT");
    frame.itemName:SetWordWrap(false);

    -- Warning text
    frame.warning = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    frame.warning:SetPoint("TOPLEFT", frame.icon, "BOTTOMLEFT", 0, -10);
    frame.warning:SetPoint("RIGHT", frame, "RIGHT", -15, 0);
    frame.warning:SetJustifyH("LEFT");
    frame.warning:SetText("This item will bind to you when picked up.\nAre you sure you want to loot it?");
    frame.warning:SetTextColor(1, 0.82, 0);

    -- OK button
    frame.okButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    frame.okButton:SetSize(80, 22);
    frame.okButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 18);
    frame.okButton:SetText("Loot");
    frame.okButton:SetScript("OnClick", function()
        if pendingBoPSlot then
            ConfirmLootSlot(pendingBoPSlot);
            pendingBoPSlot = nil;
        end
        frame:Hide();
    end);

    -- Cancel button
    frame.cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    frame.cancelButton:SetSize(80, 22);
    frame.cancelButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 5, 18);
    frame.cancelButton:SetText("Cancel");
    frame.cancelButton:SetScript("OnClick", function()
        pendingBoPSlot = nil;
        frame:Hide();
    end);

    -- ESC to close
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false);
            pendingBoPSlot = nil;
            self:Hide();
        else
            self:SetPropagateKeyboardInput(true);
        end
    end);

    BoPConfirmFrame = frame;
    return frame;
end

-- Update BoP frame position from saved settings
local function UpdateBoPFramePosition()
    if not BoPConfirmFrame then return; end

    local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale();
    local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
    local centerX = screenWidth / 2;
    local centerY = screenHeight / 2;

    BoPConfirmFrame:ClearAllPoints();
    BoPConfirmFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        centerX + db.bopFrameOffsetX,
        centerY + db.bopFrameOffsetY);
end

-- Show BoP confirmation for an item
local function ShowBoPConfirmation(slot, itemName, itemIcon, itemQuality)
    if not BoPConfirmFrame then
        CreateBoPConfirmFrame();
    end

    pendingBoPSlot = slot;

    -- Set item info
    BoPConfirmFrame.icon:SetTexture(itemIcon);

    local r, g, b = GetQualityColor(itemQuality or 1);
    BoPConfirmFrame.itemName:SetText(itemName or "Unknown Item");
    BoPConfirmFrame.itemName:SetTextColor(r, g, b);

    UpdateBoPFramePosition();
    BoPConfirmFrame:Show();
    BoPConfirmFrame:SetFrameStrata("DIALOG");
    BoPConfirmFrame:Raise();
end

-- Show preview BoP frame (for options panel)
local function ShowBoPPreview()
    if not BoPConfirmFrame then
        CreateBoPConfirmFrame();
    end

    pendingBoPSlot = nil;

    -- Set preview item info
    BoPConfirmFrame.icon:SetTexture("Interface\\Icons\\INV_Sword_04");
    BoPConfirmFrame.itemName:SetText("[Preview Epic Sword]");
    local r, g, b = GetQualityColor(4); -- Epic
    BoPConfirmFrame.itemName:SetTextColor(r, g, b);

    UpdateBoPFramePosition();
    BoPConfirmFrame:Show();
end

-- Hide BoP frame
local function HideBoPFrame()
    if BoPConfirmFrame then
        BoPConfirmFrame:Hide();
        pendingBoPSlot = nil;
    end
end

-- Create draggable preview area for BoP frame
local function CreateBoPPreviewAreaFrame()
    if BoPPreviewAreaFrame then return BoPPreviewAreaFrame; end

    local frame = CreateFrame("Frame", "ScrollingLootBoPPreviewArea", UIParent);
    frame:SetSize(280, 150);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(150);
    frame:EnableMouse(true);
    frame:SetMovable(true);
    frame:SetClampedToScreen(true);
    frame:Hide();

    -- Light blue hover highlight
    frame.highlight = frame:CreateTexture(nil, "BACKGROUND");
    frame.highlight:SetAllPoints();
    frame.highlight:SetColorTexture(0.2, 0.5, 0.8, 0.25);
    frame.highlight:Hide();

    -- Border
    frame.border = frame:CreateTexture(nil, "BORDER");
    frame.border:SetPoint("TOPLEFT", -2, 2);
    frame.border:SetPoint("BOTTOMRIGHT", 2, -2);
    frame.border:SetColorTexture(0.3, 0.6, 1.0, 0.6);
    frame.border:Hide();

    -- Inner area
    frame.inner = frame:CreateTexture(nil, "BORDER", nil, 1);
    frame.inner:SetAllPoints();
    frame.inner:SetColorTexture(0, 0, 0, 0);
    frame.inner:Hide();

    -- Hover handlers
    frame:SetScript("OnEnter", function(self)
        self.highlight:Show();
        self.border:Show();
        self.inner:Show();
        SetCursor("Interface\\CURSOR\\UI-Cursor-Move");
    end);

    frame:SetScript("OnLeave", function(self)
        if not self.isDragging then
            self.highlight:Hide();
            self.border:Hide();
            self.inner:Hide();
        end
        SetCursor(nil);
    end);

    -- Drag handlers
    frame:RegisterForDrag("LeftButton");

    frame:SetScript("OnDragStart", function(self)
        self.isDragging = true;
        self.highlight:Show();
        self.border:Show();
        self.inner:Show();
        self:StartMoving();
    end);

    local function UpdateOffsetFromFrame(self)
        local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale();
        local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
        local centerX = screenWidth / 2;
        local centerY = screenHeight / 2;

        local left = self:GetLeft();
        local bottom = self:GetBottom();
        local width = self:GetWidth();
        local height = self:GetHeight();

        local frameCenterX = left + width / 2;
        local frameCenterY = bottom + height / 2;

        db.bopFrameOffsetX = frameCenterX - centerX;
        db.bopFrameOffsetY = frameCenterY - centerY;

        -- Update actual BoP frame position
        UpdateBoPFramePosition();
    end

    frame:SetScript("OnUpdate", function(self)
        if self.isDragging then
            UpdateOffsetFromFrame(self);
        end
    end);

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
        self.isDragging = false;

        if not self:IsMouseOver() then
            self.highlight:Hide();
            self.border:Hide();
            self.inner:Hide();
        end

        UpdateOffsetFromFrame(self);

        -- Round to nearest 5
        db.bopFrameOffsetX = floor(db.bopFrameOffsetX / 5 + 0.5) * 5;
        db.bopFrameOffsetY = floor(db.bopFrameOffsetY / 5 + 0.5) * 5;
    end);

    BoPPreviewAreaFrame = frame;
    return frame;
end

-- Update BoP preview area position
local function UpdateBoPPreviewAreaPosition()
    if not BoPPreviewAreaFrame then return; end

    local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale();
    local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
    local centerX = screenWidth / 2;
    local centerY = screenHeight / 2;

    BoPPreviewAreaFrame:ClearAllPoints();
    BoPPreviewAreaFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        centerX + db.bopFrameOffsetX,
        centerY + db.bopFrameOffsetY);
end

-- Show BoP preview area
local function ShowBoPPreviewArea()
    if not BoPPreviewAreaFrame then
        CreateBoPPreviewAreaFrame();
    end
    UpdateBoPPreviewAreaPosition();
    BoPPreviewAreaFrame:Show();
    ShowBoPPreview();
end

-- Hide BoP preview area
local function HideBoPPreviewArea()
    if BoPPreviewAreaFrame then
        BoPPreviewAreaFrame:Hide();
    end
    HideBoPFrame();
end

-- Hook the LOOT_BIND StaticPopup to use our custom frame
local originalLootBindOnShow = nil;

local function SetupBoPHook()
    if not StaticPopupDialogs or not StaticPopupDialogs["LOOT_BIND"] then
        return;
    end

    -- Store original OnShow if it exists
    originalLootBindOnShow = StaticPopupDialogs["LOOT_BIND"].OnShow;

    -- Hook StaticPopup_Show for LOOT_BIND
    hooksecurefunc("StaticPopup_Show", function(which, text_arg1, text_arg2, data)
        -- Only use custom popup when Fast Loot is enabled AND we're not in default behavior mode
        -- (default behavior = loot window shown due to master loot, full inventory, or SHIFT override)
        if which == "LOOT_BIND" and db.fastLoot and not usingDefaultLootBehavior then
            -- Hide the default popup
            StaticPopup_Hide("LOOT_BIND");

            -- Get the slot from LootFrame (or from FastLoot tracking)
            local slot = LootFrame.selectedSlot or lastFastLootSlot;
            if slot then
                local texture, item, quantity, currencyID, quality = GetLootSlotInfo(slot);
                ShowBoPConfirmation(slot, item, texture, quality);
            end
        end
    end);
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

-- Create a color swatch widget that opens the color picker
local function CreateColorSwatch(parent, label, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 24);

    -- Color swatch button
    local swatch = CreateFrame("Button", nil, container);
    swatch:SetSize(20, 20);
    swatch:SetPoint("LEFT");

    -- Solid color fill (the main color display)
    local swatchColor = swatch:CreateTexture(nil, "BACKGROUND");
    swatchColor:SetPoint("TOPLEFT", 2, -2);
    swatchColor:SetPoint("BOTTOMRIGHT", -2, 2);
    swatchColor:SetColorTexture(1, 1, 1, 1);

    -- Border frame (dark outline around the color)
    local borderTop = swatch:CreateTexture(nil, "ARTWORK");
    borderTop:SetColorTexture(0.3, 0.3, 0.3, 1);
    borderTop:SetPoint("TOPLEFT", 0, 0);
    borderTop:SetPoint("TOPRIGHT", 0, 0);
    borderTop:SetHeight(2);

    local borderBottom = swatch:CreateTexture(nil, "ARTWORK");
    borderBottom:SetColorTexture(0.3, 0.3, 0.3, 1);
    borderBottom:SetPoint("BOTTOMLEFT", 0, 0);
    borderBottom:SetPoint("BOTTOMRIGHT", 0, 0);
    borderBottom:SetHeight(2);

    local borderLeft = swatch:CreateTexture(nil, "ARTWORK");
    borderLeft:SetColorTexture(0.3, 0.3, 0.3, 1);
    borderLeft:SetPoint("TOPLEFT", 0, 0);
    borderLeft:SetPoint("BOTTOMLEFT", 0, 0);
    borderLeft:SetWidth(2);

    local borderRight = swatch:CreateTexture(nil, "ARTWORK");
    borderRight:SetColorTexture(0.3, 0.3, 0.3, 1);
    borderRight:SetPoint("TOPRIGHT", 0, 0);
    borderRight:SetPoint("BOTTOMRIGHT", 0, 0);
    borderRight:SetWidth(2);

    -- Label
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    labelText:SetPoint("LEFT", swatch, "RIGHT", 6, 0);
    labelText:SetText(label);

    container.swatch = swatch;
    container.swatchColor = swatchColor;
    container.labelText = labelText;

    -- Current color storage
    container.r = 1;
    container.g = 1;
    container.b = 1;

    function container:SetColor(r, g, b)
        self.r = r;
        self.g = g;
        self.b = b;
        swatchColor:SetColorTexture(r, g, b, 1);
    end

    function container:GetColor()
        return self.r, self.g, self.b;
    end

    -- Track if we've hooked the OnHide
    local onHideHooked = false;

    -- Click handler to open color picker
    swatch:SetScript("OnClick", function()
        -- Notify that color picker is opening (for preview filtering)
        if container.OnPickerOpened then
            container:OnPickerOpened();
        end

        local info = {
            r = container.r,
            g = container.g,
            b = container.b,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB();
                container:SetColor(r, g, b);
                if container.OnColorChanged then
                    container:OnColorChanged(r, g, b);
                end
            end,
            cancelFunc = function()
                local r, g, b = ColorPickerFrame:GetPreviousValues();
                container:SetColor(r, g, b);
                if container.OnColorChanged then
                    container:OnColorChanged(r, g, b);
                end
            end,
            hasOpacity = false,
        };
        ColorPickerFrame:SetupColorPickerAndShow(info);

        -- Hook the OnHide once to detect when picker closes
        if not onHideHooked then
            onHideHooked = true;
            ColorPickerFrame:HookScript("OnHide", function()
                if container.OnPickerClosed then
                    container:OnPickerClosed();
                end
            end);
        end
    end);

    -- Highlight on hover (brighten border)
    swatch:SetScript("OnEnter", function(self)
        borderTop:SetColorTexture(0.6, 0.6, 0.4, 1);
        borderBottom:SetColorTexture(0.6, 0.6, 0.4, 1);
        borderLeft:SetColorTexture(0.6, 0.6, 0.4, 1);
        borderRight:SetColorTexture(0.6, 0.6, 0.4, 1);
    end);
    swatch:SetScript("OnLeave", function(self)
        borderTop:SetColorTexture(0.3, 0.3, 0.3, 1);
        borderBottom:SetColorTexture(0.3, 0.3, 0.3, 1);
        borderLeft:SetColorTexture(0.3, 0.3, 0.3, 1);
        borderRight:SetColorTexture(0.3, 0.3, 0.3, 1);
    end);

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
    frame:SetSize(500, 590);
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
    leftCol:SetSize(220, 420);

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
    yOffset = yOffset - 30;

    -- Show money checkbox
    local moneyCheckbox = CreateCheckbox(leftCol, "Show Money Pickups", 200);
    moneyCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    moneyCheckbox:SetValue(db.showMoney);
    moneyCheckbox.OnValueChanged = function(self, value)
        db.showMoney = value;
    end;
    moneyCheckbox.checkbox.tooltipText = "Display gold, silver, and copper pickups as scrolling notifications.";
    moneyCheckbox.checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    moneyCheckbox.checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    yOffset = yOffset - 30;

    -- Forward declare honorColorSwatch so checkbox can reference it
    local honorColorSwatch;

    -- Show honor checkbox
    local honorCheckbox = CreateCheckbox(leftCol, "Show Honor Points", 200);
    honorCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    honorCheckbox:SetValue(db.showHonor);
    honorCheckbox.OnValueChanged = function(self, value)
        db.showHonor = value;
        -- Grey out honor color swatch when disabled
        if honorColorSwatch then
            if value then
                honorColorSwatch:SetAlpha(1);
                honorColorSwatch.swatch:EnableMouse(true);
            else
                honorColorSwatch:SetAlpha(0.5);
                honorColorSwatch.swatch:EnableMouse(false);
            end
        end
    end;
    honorCheckbox.checkbox.tooltipText = "Display honor point gains as scrolling notifications.";
    honorCheckbox.checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    honorCheckbox.checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    yOffset = yOffset - 30;

    -- Honor color swatch
    honorColorSwatch = CreateColorSwatch(leftCol, "Honor Text Color", 200);
    honorColorSwatch:SetPoint("TOPLEFT", 20, yOffset);  -- Indented to show it's related to honor
    honorColorSwatch:SetColor(db.honorColor.r, db.honorColor.g, db.honorColor.b);
    honorColorSwatch.OnColorChanged = function(self, r, g, b)
        db.honorColor.r = r;
        db.honorColor.g = g;
        db.honorColor.b = b;
    end;
    honorColorSwatch.OnPickerOpened = function(self)
        honorColorPickerActive = true;
    end;
    honorColorSwatch.OnPickerClosed = function(self)
        honorColorPickerActive = false;
    end;
    honorColorSwatch.swatch.tooltipText = "Click to choose the color for honor point notifications.";
    honorColorSwatch.swatch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    honorColorSwatch.swatch:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    -- Set initial greyed-out state based on showHonor
    if not db.showHonor then
        honorColorSwatch:SetAlpha(0.5);
        honorColorSwatch.swatch:EnableMouse(false);
    end
    yOffset = yOffset - 30;

    -- Fast loot checkbox
    local fastLootCheckbox = CreateCheckbox(leftCol, "Fast Loot (hide window)", 200);
    fastLootCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    fastLootCheckbox:SetValue(db.fastLoot);
    fastLootCheckbox.OnValueChanged = function(self, value)
        db.fastLoot = value;
        -- Show/hide BoP preview based on Fast Loot state
        if value then
            ShowBoPPreviewArea();
        else
            HideBoPPreviewArea();
        end
    end;
    fastLootCheckbox.checkbox.tooltipText = "Auto-loot items instantly and hide the loot window.\nBind-on-Pickup confirmations show item icon and name.\nHold SHIFT while looting to show the window normally.";
    fastLootCheckbox.checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    fastLootCheckbox.checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    yOffset = yOffset - 35;

    -- Background opacity slider
    local bgOpacitySlider = CreateSlider(leftCol, "Background Opacity", 0, 100, 5, 200);
    bgOpacitySlider:SetPoint("TOPLEFT", 0, yOffset);
    bgOpacitySlider:SetValue(db.backgroundOpacity * 100);
    bgOpacitySlider.OnValueChanged = function(self, value)
        db.backgroundOpacity = value / 100;
    end;
    yOffset = yOffset - 55;

    -- Forward declare glowQualityDropdown so checkbox can reference it
    local glowQualityDropdown;

    -- Glow effect checkbox
    local glowCheckbox = CreateCheckbox(leftCol, "Glow Effect", 200);
    glowCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    glowCheckbox:SetValue(db.glowEnabled);
    glowCheckbox.OnValueChanged = function(self, value)
        db.glowEnabled = value;
        -- Grey out glow quality dropdown when disabled
        if glowQualityDropdown then
            if value then
                glowQualityDropdown:SetAlpha(1);
                glowQualityDropdown.dropdown:EnableMouse(true);
            else
                glowQualityDropdown:SetAlpha(0.5);
                glowQualityDropdown.dropdown:EnableMouse(false);
            end
        end
    end;
    glowCheckbox.checkbox.tooltipText = "Show a glowing effect around the item icon.";
    glowCheckbox.checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    glowCheckbox.checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    yOffset = yOffset - 30;

    -- Glow min quality dropdown
    local glowQualityOptions = {};
    for i = 0, 5 do
        tinsert(glowQualityOptions, { value = i, text = QUALITY_COLORS[i].name });
    end
    glowQualityDropdown = CreateDropdown(leftCol, "Glow Min Quality", glowQualityOptions, 200);
    glowQualityDropdown:SetPoint("TOPLEFT", 0, yOffset);
    glowQualityDropdown:SetValue(db.glowMinQuality);
    glowQualityDropdown.OnValueChanged = function(self, value)
        db.glowMinQuality = value;
    end;
    -- Initialize greyed state
    if not db.glowEnabled then
        glowQualityDropdown:SetAlpha(0.5);
        glowQualityDropdown.dropdown:EnableMouse(false);
    end
    yOffset = yOffset - 55;

    -- Min quality dropdown
    local qualityOptions = {};
    for i = 0, 5 do
        tinsert(qualityOptions, { value = i, text = QUALITY_COLORS[i].name });
    end
    local qualityDropdown = CreateDropdown(leftCol, "Notifications Min Quality", qualityOptions, 200);
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

    -- Text alignment dropdown
    local alignOptions = {
        { value = "left", text = "Left" },
        { value = "center", text = "Center" },
        { value = "right", text = "Right" },
    };
    local alignDropdown = CreateDropdown(rightCol, "Text Alignment", alignOptions, 200);
    alignDropdown:SetPoint("TOPLEFT", 0, yOffset);
    alignDropdown:SetValue(db.textAlign);
    alignDropdown.OnValueChanged = function(self, value)
        db.textAlign = value;
        UpdatePreviewAreaPosition();
    end;
    alignDropdown.dropdown.tooltipText = "Left: notifications anchored to left edge.\nCenter: notifications centered on screen.\nRight: notifications anchored to right edge.";
    alignDropdown.dropdown:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    alignDropdown.dropdown:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    yOffset = yOffset - 55;

    -- Animation section
    local animLabel = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    animLabel:SetPoint("TOPLEFT", 0, yOffset);
    animLabel:SetText("Animation");
    animLabel:SetTextColor(1, 0.82, 0);
    yOffset = yOffset - 25;

    -- Forward declare sliders so staticModeCheckbox can reference them
    local fadeSlider;
    local distSlider;

    -- Static mode checkbox
    local staticModeCheckbox = CreateCheckbox(rightCol, "Static Mode (no scrolling)", 200);
    staticModeCheckbox:SetPoint("TOPLEFT", 0, yOffset);
    staticModeCheckbox:SetValue(db.staticMode);
    staticModeCheckbox.OnValueChanged = function(self, value)
        db.staticMode = value;
        -- Grey out Scroll Distance when static mode is enabled
        if distSlider then
            if value then
                distSlider.slider:SetAlpha(0.5);
                distSlider.slider:EnableMouse(false);
                distSlider.editBox:SetAlpha(0.5);
                distSlider.editBox:EnableMouse(false);
                distSlider.labelText:SetAlpha(0.5);
            else
                distSlider.slider:SetAlpha(1);
                distSlider.slider:EnableMouse(true);
                distSlider.editBox:SetAlpha(1);
                distSlider.editBox:EnableMouse(true);
                distSlider.labelText:SetAlpha(1);
            end
        end
        -- Update preview area size/position for the new mode
        UpdatePreviewAreaPosition();
    end;
    staticModeCheckbox.checkbox.tooltipText = "Items appear in place and fade out without scrolling upward.";
    staticModeCheckbox.checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    staticModeCheckbox.checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    yOffset = yOffset - 30;

    -- Scroll speed slider (renamed label based on mode would be nice but keeping simple)
    local speedSlider = CreateSlider(rightCol, "Display Duration (seconds)", 1, 10, 0.5, 200);
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
    distSlider = CreateSlider(rightCol, "Scroll Distance (pixels)", 50, 400, 10, 200);
    distSlider:SetPoint("TOPLEFT", 0, yOffset);
    distSlider:SetValue(db.scrollDistance);
    distSlider.OnValueChanged = function(self, value)
        db.scrollDistance = value;
        -- Update preview area size to match new scroll distance
        UpdatePreviewAreaPosition();
    end;
    -- Grey out if static mode is already enabled
    if db.staticMode then
        distSlider.slider:SetAlpha(0.5);
        distSlider.slider:EnableMouse(false);
        distSlider.editBox:SetAlpha(0.5);
        distSlider.editBox:EnableMouse(false);
        distSlider.labelText:SetAlpha(0.5);
    end

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
        -- Reset all settings (deep copy for tables like honorColor)
        for key, value in pairs(DEFAULT_SETTINGS) do
            if type(value) == "table" then
                db[key] = {};
                for k, v in pairs(value) do
                    db[key][k] = v;
                end
            else
                db[key] = value;
            end
        end
        -- Update all widgets
        enabledCheckbox:SetValue(db.enabled);
        quantityCheckbox:SetValue(db.showQuantity);
        bgCheckbox:SetValue(db.showBackground);
        moneyCheckbox:SetValue(db.showMoney);
        honorCheckbox:SetValue(db.showHonor);
        honorColorSwatch:SetColor(db.honorColor.r, db.honorColor.g, db.honorColor.b);
        -- Enable honor color swatch since showHonor defaults to true
        honorColorSwatch:SetAlpha(1);
        honorColorSwatch.swatch:EnableMouse(true);
        fastLootCheckbox:SetValue(db.fastLoot);
        bgOpacitySlider:SetValue(db.backgroundOpacity * 100);
        glowCheckbox:SetValue(db.glowEnabled);
        glowQualityDropdown:SetValue(db.glowMinQuality);
        -- Grey out glow quality since glowEnabled defaults to false
        glowQualityDropdown:SetAlpha(0.5);
        glowQualityDropdown.dropdown:EnableMouse(false);
        qualityDropdown:SetValue(db.minQuality);
        maxMsgSlider:SetValue(db.maxMessages);
        iconSlider:SetValue(db.iconSize);
        fontSlider:SetValue(db.fontSize);
        staticModeCheckbox:SetValue(db.staticMode);
        speedSlider:SetValue(db.scrollSpeed);
        fadeSlider:SetValue(db.fadeStartTime);
        distSlider:SetValue(db.scrollDistance);
        -- Re-enable distSlider since staticMode defaults to false
        distSlider.slider:SetAlpha(1);
        distSlider.slider:EnableMouse(true);
        distSlider.editBox:SetAlpha(1);
        distSlider.editBox:EnableMouse(true);
        distSlider.labelText:SetAlpha(1);
        -- Update preview area positions
        UpdatePreviewAreaPosition();
        UpdateBoPPreviewAreaPosition();
        UpdateBoPFramePosition();
        print("|cff00ff00ScrollingLoot|r settings reset to defaults.");
    end);

    -- Live preview info text - big text at top center of screen with background
    local previewInfoFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate");
    previewInfoFrame:SetPoint("TOP", UIParent, "TOP", 0, -50);
    previewInfoFrame:SetSize(500, 40);
    previewInfoFrame:SetFrameStrata("DIALOG");
    previewInfoFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    });
    previewInfoFrame:SetBackdropColor(0, 0, 0, 0.8);
    previewInfoFrame:SetBackdropBorderColor(0.3, 0.6, 1.0, 0.8);
    previewInfoFrame:Hide();

    local previewInfo = previewInfoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    previewInfo:SetPoint("CENTER");
    previewInfo:SetText("Hover over preview elements to reveal draggable areas");
    previewInfo:SetTextColor(1, 0.82, 0); -- Yellow/gold color
    previewInfo:SetFont(previewInfo:GetFont(), 16, "OUTLINE");

    -- OnShow/OnHide for live preview and draggable areas
    frame:SetScript("OnShow", function()
        StartLivePreview();
        ShowPreviewArea();
        previewInfoFrame:Show();
        -- Only show BoP preview if Fast Loot is enabled
        if db.fastLoot then
            ShowBoPPreviewArea();
        end
    end);

    frame:SetScript("OnHide", function()
        StopLivePreview();
        HidePreviewArea();
        HideBoPPreviewArea();
        previewInfoFrame:Hide();
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
        local message = ...;

        -- Only show items that enter YOUR inventory
        -- Uses localized LOOT_ITEM_SELF pattern (e.g., "You receive loot: %s" in English)
        -- This filters out: other players looting, items being rolled on, etc.
        if not strmatch(message, LOOT_SELF_PATTERN) then
            return;
        end

        local itemLink, quantity = ParseLootMessage(message);
        if not itemLink then return; end

        local itemName, itemIcon, itemQuality = ParseItemLink(itemLink);
        if itemName and itemIcon then
            AddLootMessage(itemName, itemIcon, itemQuality or 1, quantity);
        end

    elseif event == "CHAT_MSG_MONEY" then
        -- Money looted - parse amount from chat message text
        if db.showMoney then
            local message = ...;
            local moneyAmount = ParseMoneyFromText(message);
            if moneyAmount and moneyAmount > 0 then
                AddMoneyMessage(moneyAmount, false);
            end
        end

    elseif event == "PLAYER_MONEY" then
        -- Track money changes (kept for potential future use)
        previousMoney = GetMoney();

    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        -- Honor gained
        if db.showHonor then
            local message = ...;
            local honor = ParseHonorMessage(message);
            if honor and honor > 0 then
                AddHonorMessage(honor, false);
            end
        end

    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...;
        if loadedAddon == addonName then
            -- Initialize saved variables
            if not ScrollingLootDB then
                ScrollingLootDB = {};
            end

            -- Migrate old anchorPoint setting to free-form X offset
            if ScrollingLootDB.anchorPoint then
                if ScrollingLootDB.anchorPoint == "LEFT" then
                    -- Convert LEFT anchor to negative offset
                    local oldOffset = ScrollingLootDB.startOffsetX or DEFAULT_SETTINGS.startOffsetX;
                    ScrollingLootDB.startOffsetX = -(oldOffset + 200);
                end
                ScrollingLootDB.anchorPoint = nil; -- Remove deprecated setting
            end

            -- Copy defaults for any missing values
            for key, value in pairs(DEFAULT_SETTINGS) do
                if ScrollingLootDB[key] == nil then
                    if type(value) == "table" then
                        ScrollingLootDB[key] = {};
                        for k, v in pairs(value) do
                            ScrollingLootDB[key][k] = v;
                        end
                    else
                        ScrollingLootDB[key] = value;
                    end
                end
            end

            -- Ensure honorColor has all required fields (for existing saves)
            if ScrollingLootDB.honorColor then
                if ScrollingLootDB.honorColor.r == nil then
                    ScrollingLootDB.honorColor.r = DEFAULT_SETTINGS.honorColor.r;
                end
                if ScrollingLootDB.honorColor.g == nil then
                    ScrollingLootDB.honorColor.g = DEFAULT_SETTINGS.honorColor.g;
                end
                if ScrollingLootDB.honorColor.b == nil then
                    ScrollingLootDB.honorColor.b = DEFAULT_SETTINGS.honorColor.b;
                end
            end

            db = ScrollingLootDB;

            self:UnregisterEvent("ADDON_LOADED");
            print("|cff00ff00ScrollingLoot|r loaded. Type |cff00ffff/sloot|r for options.");
        end

    elseif event == "PLAYER_LOGIN" then
        -- Setup BoP confirmation hook
        SetupBoPHook();
        -- Initialize money tracker for accurate delta calculation
        previousMoney = GetMoney();
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

    elseif msg == "testmoney" then
        AddMoneyMessage(12345, true);   -- 1g 23s 45c
        AddMoneyMessage(500, true);      -- 5s
        AddMoneyMessage(15, true);       -- 15c

    elseif msg == "testhonor" then
        AddHonorMessage(15, true);
        AddHonorMessage(50, true);
        AddHonorMessage(100, true);

    elseif msg == "reset" then
        for key, value in pairs(DEFAULT_SETTINGS) do
            db[key] = value;
        end
        print("|cff00ff00ScrollingLoot|r settings reset to defaults.");

    elseif msg == "help" then
        print("|cff00ff00ScrollingLoot|r commands:");
        print("  |cff00ffff/sloot|r - Open options panel (with live preview)");
        print("  |cff00ffff/sloot test|r - Show test loot messages");
        print("  |cff00ffff/sloot testmoney|r - Show test money messages");
        print("  |cff00ffff/sloot testhonor|r - Show test honor messages");
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
ScrollingLoot:RegisterEvent("CHAT_MSG_MONEY");
ScrollingLoot:RegisterEvent("PLAYER_MONEY");
ScrollingLoot:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN");
ScrollingLoot:RegisterEvent("ADDON_LOADED");
ScrollingLoot:RegisterEvent("PLAYER_LOGIN");

-- Initialize db with defaults (will be overwritten on ADDON_LOADED)
db = DEFAULT_SETTINGS;

-- Initialize money tracker
previousMoney = GetMoney and GetMoney() or 0;
