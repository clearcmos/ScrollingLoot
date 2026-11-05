local _, addon = ...
-- isForever: this adapter is loaded. nativeBindConfirm: Forever's own
-- bind-on-pickup prompt already names the item, so the custom dialog stays off.
local Compat = { isForever = true, nativeBindConfirm = true }
addon.Compat = Compat

function Compat.Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

-- Only the Forever TOC loads this file. Anniversary keeps its existing defaults.
function Compat.ConfigureDefaults(defaults)
    defaults.iconSize = 22
    defaults.fontSize = 14
    defaults.staticMode = true
    defaults.maxMessages = 5
    defaults.showBackground = true
    defaults.backgroundOpacity = 0.55
    defaults.scrollSpeed = 4
    defaults.fadeStartTime = 3
    defaults.startOffsetX = 260
    defaults.startOffsetY = -80
    defaults.fastLoot = false
end

local selfPatterns = {}
for _, key in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE" }) do
    local template = _G[key]
    if type(template) == "string" then
        -- Match localized self-loot only, including numbered format placeholders.
        local pattern = template:gsub("%%%d+%$[sd]", "\001"):gsub("%%[sd]", "\001")
        pattern = pattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        selfPatterns[#selfPatterns + 1] = "^" .. pattern:gsub("\001", ".+") .. "$"
    end
end

function Compat.IsOwnLoot(message)
    if not Compat.Accessible(message) or type(message) ~= "string" then return false end
    for _, pattern in ipairs(selfPatterns) do
        if message:match(pattern) then return true end
    end
    return false
end

function Compat.EmitItem(link, quantity, emit)
    if not Compat.Accessible(link) or type(link) ~= "string" then return end
    local function Loaded()
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
        if not Compat.Accessible(name) or not Compat.Accessible(icon)
            or not Compat.Accessible(quality) then return end
        if name and icon and quality then emit(name, icon, quality, quantity, link) end
    end
    -- Keep the full link, so suffixes and bonus variants retain their item names.
    local item = Item:CreateFromItemLink(link)
    if not item:IsItemEmpty() then item:ContinueOnItemLoad(Loaded) end
end

-- ============================================================================
-- Loot window source
-- Forever can hide loot and money chat text from addons. Items and money taken
-- from a loot window are therefore recorded too. A record is shown at once
-- while chat messaging is locked down, otherwise after a short wait if no
-- readable chat message for it arrives. A record and a readable chat message
-- for the same pickup cancel each other in whichever order they arrive, so
-- nothing appears twice.
-- ============================================================================

local CHAT_WAIT = 1.5     -- seconds to wait for a readable chat message
local MATCH_WINDOW = 4    -- seconds a record and a chat message can still match
local SLOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
local SLOT_MONEY = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2

local emitItem, emitMoney
local records = {}        -- loot window pickups, oldest first
local chatSeen = {}       -- readable chat pickups, oldest first
local requested = {}      -- [slot] = item pickup waiting to be confirmed
local openSlots = {}      -- [slot] = slot contents while a loot window is open
local autoLootSession = false
local moneyBase, moneyWatchUntil = 0, 0

local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() and true or false
end

local function Prune(list)
    local now = GetTime()
    for i = #list, 1, -1 do
        if now - list[i].time > MATCH_WINDOW then table.remove(list, i) end
    end
end

-- Removes and returns the oldest entry of this kind and value
local function TakeMatch(list, kind, value)
    Prune(list)
    for i, entry in ipairs(list) do
        if entry.kind == kind and entry.value == value then
            return table.remove(list, i)
        end
    end
end

local function ShowRecord(record)
    if record.shown or record.consumed or not emitItem then return end
    record.shown = true
    if record.kind == "item" then
        Compat.EmitItem(record.link, record.quantity, emitItem)
    else
        emitMoney(record.value)
    end
end

local function AddRecord(record)
    record.time = GetTime()
    -- The readable chat message for this pickup came first and was shown
    if TakeMatch(chatSeen, record.kind, record.value) then return end
    Prune(records)
    records[#records + 1] = record
    if ChatLocked() then
        ShowRecord(record)
    else
        C_Timer.After(CHAT_WAIT, function() ShowRecord(record) end)
    end
end

-- Called for each readable own-loot chat message. Returns true when the loot
-- window already showed this pickup, in which case the chat message is skipped.
local function ConsumeChat(kind, value)
    local record = TakeMatch(records, kind, value)
    if record then
        if record.shown then return true end
        record.consumed = true
        return false
    end
    chatSeen[#chatSeen + 1] = { kind = kind, value = value, time = GetTime() }
    Prune(chatSeen)
    return false
end

function Compat.ConsumeChatLoot(itemLink)
    local itemID = type(itemLink) == "string" and tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return false end
    return ConsumeChat("item", itemID)
end

function Compat.ConsumeChatMoney(amount)
    return ConsumeChat("money", amount)
end

-- Contents of one loot slot, or nil if it is empty or unreadable
local function ReadSlot(slot)
    local slotType = GetLootSlotType(slot)
    if not Compat.Accessible(slotType) then return nil end
    if slotType == SLOT_MONEY then return { money = true } end
    if slotType ~= SLOT_ITEM then return nil end
    local _, _, quantity = GetLootSlotInfo(slot)
    local link = GetLootSlotLink(slot)
    if not Compat.Accessible(link) or type(link) ~= "string" or not Compat.Accessible(quantity) then
        return nil
    end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return nil end
    return { link = link, itemID = itemID, quantity = quantity or 1 }
end

local function WatchMoney()
    moneyWatchUntil = GetTime() + 3
end

local function ItemRecord(contents)
    return { kind = "item", value = contents.itemID, link = contents.link,
        quantity = contents.quantity, requestedAt = GetTime(),
        countBefore = C_Item.GetItemCount(contents.itemID) or 0 }
end

local function DropStaleRequests()
    local now = GetTime()
    for slot, record in pairs(requested) do
        if now - record.requestedAt > MATCH_WINDOW then requested[slot] = nil end
    end
end

-- A slot this player asked to loot (Fast Loot, a loot window click or anything
-- else that calls LootSlot). Its pickup counts once the slot clears or the
-- item count in the bags goes up.
local function OnLootSlotRequested(slot)
    local contents = openSlots[slot] or ReadSlot(slot)
    if not contents then return end
    if contents.money then
        WatchMoney()
        return
    end
    local pendingRecord = requested[slot]
    if pendingRecord and pendingRecord.value == contents.itemID
        and GetTime() - pendingRecord.requestedAt <= MATCH_WINDOW then
        return  -- the same pickup asked for again
    end
    requested[slot] = ItemRecord(contents)
end

-- Registered at load so it runs before ScrollingLoot's Fast Loot handler,
-- which asks for slots during the same LOOT_READY event.
local lootFrame = CreateFrame("Frame")
for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED",
    "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
    lootFrame:RegisterEvent(event)
end
lootFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        if event == "LOOT_READY" then
            DropStaleRequests()
            autoLootSession = false
            moneyBase = GetMoney()
        end
        -- With auto loot on, the game takes every slot itself
        if arg1 then autoLootSession = true end
        wipe(openSlots)
        for slot = 1, GetNumLootItems() do
            openSlots[slot] = ReadSlot(slot)
        end
        if autoLootSession then
            for _, contents in pairs(openSlots) do
                if contents.money then WatchMoney() end
            end
        end
    elseif event == "LOOT_SLOT_CHANGED" then
        openSlots[arg1] = ReadSlot(arg1)
    elseif event == "LOOT_SLOT_CLEARED" then
        local record = requested[arg1]
        local contents = openSlots[arg1]
        if not record and autoLootSession and contents and not contents.money then
            record = ItemRecord(contents)
        end
        requested[arg1] = nil
        openSlots[arg1] = nil
        if record then AddRecord(record) end
    elseif event == "LOOT_CLOSED" then
        wipe(openSlots)
        autoLootSession = false
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Fast Loot can close the window before its slots report clearing
        DropStaleRequests()
        for slot, record in pairs(requested) do
            if (C_Item.GetItemCount(record.value) or 0) > record.countBefore then
                requested[slot] = nil
                AddRecord(record)
            end
        end
    elseif event == "PLAYER_MONEY" then
        local money = GetMoney()
        local gained = money - moneyBase
        moneyBase = money
        if gained > 0 and GetTime() <= moneyWatchUntil then
            AddRecord({ kind = "money", value = gained })
        end
    end
end)

-- Starts showing records once ScrollingLoot hands over its display functions.
function Compat.StartLootWindowSource(itemEmitter, moneyEmitter)
    if emitItem then return end
    emitItem, emitMoney = itemEmitter, moneyEmitter
    moneyBase = GetMoney()
    hooksecurefunc("LootSlot", OnLootSlotRequested)
end

-- ============================================================================
-- Settings launcher
-- Options use ScrollingLoot's own window, which shows a live sample feed and a
-- draggable position area. The game's settings panel (920x724, centered) would
-- cover the feed, so its AddOns entry only opens that window.
-- ============================================================================

function Compat.RegisterSettingsLauncher(openOptions)
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Scrolling Loot (Experimental)")
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetText("Options open in their own window, with a live preview of the feed. /sloot opens it too.")
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(160, 24)
    button:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    button:SetText("Open options")
    button:SetScript("OnClick", function()
        -- Close the game's panel so the preview feed is not hidden behind it
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        openOptions()
    end)
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "Scrolling Loot (Experimental)"))
end
