-- Run from the repository root: lua5.1 tests/forever.lua
-- Frame and API stand-ins exercise the adapter and the shared file's event
-- routing. They do not establish template availability, rendering or the
-- client's runtime restrictions.
local passed = 0
local function test(name, run)
    run()
    passed = passed + 1
    print("PASS " .. name)
end

-- ---------------------------------------------------------------------------
-- Stand-ins
-- ---------------------------------------------------------------------------
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %1$s x%2$d."

table.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
wipe = table.wipe
string.trim = function(s) return s:match("^%s*(.-)%s*$") end

local now = 100
GetTime = function() return now end
local money = 0
GetMoney = function() return money end

local timers = {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { at = now + delay, run = callback } end }
local function advance(seconds)
    now = now + seconds
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
    end
    for i = #due, 1, -1 do due[i].run() end
end

local lockdown = false
C_ChatInfo = { InChatMessagingLockdown = function() return lockdown end }

local secret = setmetatable({}, { __tostring = function() error("secret escaped") end })
issecretvalue = function(value) return rawequal(value, secret) end

-- Items: the async loader completes immediately once an item is cached
local itemNames = { [123] = "Sample Item", [2589] = "Linen Cloth", [4306] = "Silk Cloth" }
local cached, completion, requestedLink = false
local bagCounts = {}
Item = { CreateFromItemLink = function(_, itemLink)
    requestedLink = itemLink
    return { IsItemEmpty = function() return false end,
        ContinueOnItemLoad = function(_, callback) completion = callback end }
end }
C_Item = {
    GetItemInfo = function(itemLink)
        local id = tonumber(itemLink:match("item:(%d+)"))
        if cached and itemNames[id] then return itemNames[id], itemLink, 2, nil, nil, nil, nil, nil, nil, 1000 + id end
    end,
    GetItemCount = function(id) return bagCounts[id] or 0 end,
}
local function itemLink(id) return "|cffffffff|Hitem:" .. id .. ":0:0:0|h[" .. itemNames[id] .. "]|h|r" end

-- Frames
local objects, messages, hooks = {}, {}, {}
local methods = {}
local function object(name)
    local value = setmetatable({ scripts = {}, events = {}, shown = false }, { __index = methods })
    objects[#objects + 1] = value
    if name then _G[name] = value end
    return value
end
setmetatable(methods, { __index = function(_, key)
    if key:match("^Get") then return function() return 1 end end
    return function() end
end })
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:CreateTexture() return object() end
function methods:CreateFontString()
    local value = object()
    value.owner = self
    return value
end
function methods:CreateAnimationGroup() return object() end
function methods:CreateAnimation() return object() end
function methods:SetText(text) self.textValue = text; messages[#messages + 1] = text end
-- Show and Hide run OnShow and OnHide when the state changes, as the client does
function methods:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:GetFont() return "font", 12 end
function methods:GetStringWidth() return 100 end
CreateFrame = function(_, name, parent)
    local value = object(name)
    value.parent = parent
    return value
end
UIParent = object()
GetScreenWidth = function() return 1920 end
GetScreenHeight = function() return 1080 end
SlashCmdList = {}
UISpecialFrames = {}
IsShiftKeyDown = function() return false end
PlaySound = function() end
-- The game's settings panel: the AddOns entry is a canvas with one button
local launcherPanel, launcherCategory
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        launcherPanel = frame
        return { name = name }
    end,
    RegisterAddOnCategory = function(category) launcherCategory = category end,
}
SettingsPanel = object("SettingsPanel")
HideUIPanel = function(frame) frame:Hide() end
local freeBagSlots = 10
C_Container = { GetContainerNumFreeSlots = function() return freeBagSlots end }
-- Wraps the global like the real hooksecurefunc, so hooked calls run the hook
hooksecurefunc = function(name, hook)
    hooks[#hooks + 1] = name
    local original = _G[name]
    _G[name] = function(...)
        local a, b, c = original(...)
        hook(...)
        return a, b, c
    end
end

-- Event dispatch in registration (creation) order, as the client does
local function fire(event, ...)
    for _, frame in ipairs(objects) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

-- Loot window: a list of slots; LootSlot takes one
local lootSlots = {}
local lootRequests = {}
GetNumLootItems = function() return #lootSlots end
GetLootSlotType = function(slot) return lootSlots[slot] and lootSlots[slot].type or 0 end
GetLootSlotLink = function(slot) return lootSlots[slot] and lootSlots[slot].link end
GetLootSlotInfo = function(slot)
    local s = lootSlots[slot]
    if s then return 1, "name", s.quantity or 0, nil, 1, false end
end
LootSlot = function(slot) lootRequests[#lootRequests + 1] = slot end
LootFrame = object("LootFrame")

-- ---------------------------------------------------------------------------
-- Adapter
-- ---------------------------------------------------------------------------
local addon = {}
assert(loadfile("Compat_Forever.lua"))("ScrollingLoot", addon)
local Compat = addon.Compat
local link = "|cff1eff00|Hitem:123:0:0:0|h[Sample Item]|h|r"

test("only own loot and reward messages match", function()
    assert(Compat.IsOwnLoot("You receive loot: " .. link .. "."))
    assert(Compat.IsOwnLoot("You receive loot: " .. link .. "x3."))
    assert(Compat.IsOwnLoot("You receive item: " .. link .. "."))
    assert(not Compat.IsOwnLoot("Otherplayer receives loot: " .. link .. "."))
end)
test("numbered placeholders and literal punctuation match", function()
    assert(Compat.IsOwnLoot("You create: " .. link .. " x4."))
    assert(not Compat.IsOwnLoot("You create: " .. link .. " x4!"))
end)
test("restricted chat is discarded before parsing", function()
    assert(not Compat.IsOwnLoot(secret))
end)
test("uncached item waits and emits its full-link details once loaded", function()
    local emitted = 0
    Compat.EmitItem(link, 3, function(name, icon, quality, quantity)
        assert(name == "Sample Item" and icon == 1123 and quality == 2 and quantity == 3)
        emitted = emitted + 1
    end)
    assert(requestedLink == link and emitted == 0)
    cached = true
    completion()
    assert(emitted == 1)
end)
test("failed item load is not replaced with invented data", function()
    cached = false
    Compat.EmitItem(link, 1, function() error("unexpected notification") end)
    completion()
end)

-- ---------------------------------------------------------------------------
-- Shared file on the Forever path
-- ---------------------------------------------------------------------------
local function loadMain(namespace)
    local first = #objects + 1
    assert(loadfile("ScrollingLoot.lua"))("ScrollingLoot", namespace)
    ScrollingLootFrame.scripts.OnEvent(ScrollingLootFrame, "ADDON_LOADED", "ScrollingLoot")
    ScrollingLootFrame.scripts.OnEvent(ScrollingLootFrame, "PLAYER_LOGIN")
    return first
end
local function hooked(name)
    for _, n in ipairs(hooks) do if n == name then return true end end
    return false
end

test("Forever keeps Fast Loot and the game's bind-on-pickup prompt", function()
    GetItemInfo = nil
    ScrollingLootDB = { fastLoot = true }
    loadMain(addon)
    assert(ScrollingLootDB.fastLoot == true, "saved Fast Loot setting must be kept")
    assert(ScrollingLootDB.staticMode and ScrollingLootDB.iconSize == 22)
    assert(hooked("LootSlot"), "loot window source must watch LootSlot")
    assert(not hooked("StaticPopup_Show"), "custom bind-on-pickup dialog must stay off")
end)

-- Helper: the visible notifications since a mark
local function shownSince(mark)
    local out = {}
    for i = mark + 1, #messages do out[#out + 1] = messages[i] end
    return table.concat(out, "\n")
end
-- Runs the item loader's callback only if this step started a new item load
local function finishLoad(step)
    completion = nil
    step()
    if completion then completion() end
end
local function chatLoot(id, quantity)
    local text = "You receive loot: " .. itemLink(id) .. (quantity and ("x" .. quantity) or "") .. "."
    finishLoad(function() fire("CHAT_MSG_LOOT", text) end)
end

test("real loot event preserves quantity through async notification", function()
    cached = true
    local mark = #messages
    ScrollingLootFrame.scripts.OnEvent(ScrollingLootFrame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. "x3.")
    completion()
    local shown = shownSince(mark)
    assert(shown:find("Sample Item", 1, true) and shown:find("3", 1, true))
end)

test("restricted events never reach parsers", function()
    for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_HONOR_GAIN" }) do
        ScrollingLootFrame.scripts.OnEvent(ScrollingLootFrame, event, secret)
    end
end)

test("Fast Loot takes every slot on LOOT_READY and hides the window afterwards", function()
    lootSlots = { { type = 1, link = itemLink(2589), quantity = 2 }, { type = 1, link = itemLink(4306), quantity = 1 } }
    lootRequests = {}
    LootFrame.shown = true
    fire("LOOT_READY", false)
    assert(#lootRequests == 2, "both slots requested")
    fire("LOOT_OPENED", false)
    assert(not LootFrame.shown, "window hidden after looting")
    fire("LOOT_CLOSED")
    advance(10)
end)

test("Fast Loot takes a corpse opened right after another before hiding its window", function()
    local function openCorpse()
        lootSlots = { { type = 1, link = itemLink(2589), quantity = 1 }, { type = 1, link = itemLink(4306), quantity = 1 } }
        lootRequests = {}
        LootFrame.shown = true
        fire("LOOT_READY", false)
    end
    -- First corpse; its slot-cleared retry and close arrive in the same instant
    openCorpse()
    fire("LOOT_OPENED", false)
    fire("LOOT_SLOT_CLEARED", 1)
    fire("LOOT_CLOSED")
    -- Second corpse within the 0.3 s throttle
    openCorpse()
    assert(#lootRequests == 2, "second corpse looted: " .. #lootRequests)
    fire("LOOT_OPENED", false)
    fire("LOOT_CLOSED")
    -- A late slot-cleared retry after the close must not block the next corpse
    fire("LOOT_SLOT_CLEARED", 2)
    openCorpse()
    assert(#lootRequests == 2, "third corpse looted: " .. #lootRequests)
    fire("LOOT_OPENED", false)
    fire("LOOT_CLOSED")
    advance(10)
end)

test("with full bags, Fast Loot shows the window only when there is an item to pick up", function()
    freeBagSlots = 0
    local function open(slots)
        lootSlots = slots
        LootFrame.shown = true
        fire("LOOT_READY", false)
        fire("LOOT_OPENED", false)
        local shown = LootFrame.shown
        fire("LOOT_CLOSED")
        return shown
    end
    assert(not open({}), "empty corpse: window hidden")
    assert(not open({ { type = 2 } }), "money only: window hidden")
    assert(open({ { type = 1, link = itemLink(2589), quantity = 1 } }), "item with full bags: window kept")
    freeBagSlots = 10
    advance(10)
end)

test("in a chat lockdown, a loot window pickup shows at once and its chat copy is skipped", function()
    lockdown = true
    cached = true
    local mark = #messages
    lootSlots = { { type = 1, link = itemLink(2589), quantity = 2 } }
    fire("LOOT_READY", false)       -- Fast Loot requests slot 1
    fire("LOOT_OPENED", false)
    fire("LOOT_CLOSED")             -- window gone before the slot reported clearing
    bagCounts[2589] = 2
    finishLoad(function() fire("BAG_UPDATE_DELAYED") end)  -- pickup confirmed by the bag count
    assert(shownSince(mark):find("Linen Cloth", 1, true), "shown from the loot window")
    local before = #messages
    chatLoot(2589, 2)               -- the same pickup, readable after all
    assert(#messages == before, "chat copy skipped")
    lockdown = false
    advance(10)
end)

test("outside a lockdown, readable chat shows the pickup and the record stays hidden", function()
    local mark = #messages
    lootSlots = { { type = 1, link = itemLink(4306), quantity = 1 } }
    fire("LOOT_READY", false)
    fire("LOOT_SLOT_CLEARED", 1)
    chatLoot(4306)
    local afterChat = #messages
    assert(shownSince(mark):find("Silk Cloth", 1, true))
    finishLoad(function() advance(2) end)  -- record's wait ends; it must not show again
    assert(#messages == afterChat, "no duplicate")
    fire("LOOT_CLOSED")
    advance(10)
end)

test("when chat text never arrives readable, the record shows after the wait", function()
    local mark = #messages
    lootSlots = { { type = 1, link = itemLink(2589), quantity = 4 } }
    fire("LOOT_READY", false)
    fire("LOOT_SLOT_CLEARED", 1)
    fire("CHAT_MSG_LOOT", secret)   -- hidden chat text is ignored
    assert(#messages == mark)
    finishLoad(function() advance(2) end)
    assert(shownSince(mark):find("Linen Cloth", 1, true))
    fire("LOOT_CLOSED")
    advance(10)
end)

test("chat arriving before the slot clears still prevents a duplicate", function()
    local mark = #messages
    lootSlots = { { type = 1, link = itemLink(4306), quantity = 1 } }
    fire("LOOT_READY", false)
    chatLoot(4306)
    local afterChat = #messages
    finishLoad(function()
        fire("LOOT_SLOT_CLEARED", 1)
        advance(2)
    end)
    assert(#messages == afterChat and shownSince(mark):find("Silk Cloth", 1, true))
    fire("LOOT_CLOSED")
    advance(10)
end)

test("looted money shows once, from chat or from the money change", function()
    local mark = #messages
    lootSlots = { { type = 2 } }
    fire("LOOT_READY", false)       -- Fast Loot requests the money slot
    money = money + 150
    fire("PLAYER_MONEY")
    fire("CHAT_MSG_MONEY", "You loot 1 Silver, 50 Copper")
    advance(2)
    local shown = shownSince(mark)
    local _, count = shown:gsub("1s 50c", "")
    assert(count == 1, "money must show exactly once: " .. shown)
    fire("LOOT_CLOSED")
    advance(10)
    -- hidden chat: the money change alone shows it
    mark = #messages
    fire("LOOT_READY", false)
    money = money + 25
    fire("PLAYER_MONEY")
    fire("CHAT_MSG_MONEY", secret)
    advance(2)
    assert(shownSince(mark):find("25c", 1, true), "money shown from the change in GetMoney")
    fire("LOOT_CLOSED")
    advance(10)
end)

-- The widget container whose label has this text
local function labelled(text)
    for _, value in ipairs(objects) do
        if value.textValue == text and value.owner then return value.owner end
    end
end

test("the game's AddOns entry opens the options window and closes the game's panel", function()
    assert(launcherCategory and launcherCategory.name == "Scrolling Loot (Experimental)")
    local button
    for _, value in ipairs(objects) do
        if value.parent == launcherPanel and value.scripts.OnClick then button = value end
    end
    assert(button, "launcher button")
    SettingsPanel.shown = true
    button.scripts.OnClick(button)
    assert(not SettingsPanel.shown, "game's panel closed")
    assert(ScrollingLootOptionsFrame and ScrollingLootOptionsFrame.shown, "options window shown")
end)

test("the options window runs the live preview, without the custom bind-on-pickup preview", function()
    assert(ScrollingLootPreviewArea and ScrollingLootPreviewArea.shown, "draggable position area")
    local mark = #messages
    ScrollingLootFrame.scripts.OnUpdate(ScrollingLootFrame, 0.01)  -- the first sample spawns at once
    ScrollingLootFrame.scripts.OnUpdate(ScrollingLootFrame, 1.6)
    assert(#messages >= mark + 2, "samples spawn while the window is open")

    local fastLoot = labelled("Fast Loot (hide window)")
    fastLoot.checkbox.scripts.OnClick(fastLoot.checkbox)
    assert(ScrollingLootDB.fastLoot, "Fast Loot set from the window")
    assert(ScrollingLootBoPPreviewArea == nil and ScrollingLootBoPConfirmFrame == nil,
        "the game's prompt is used, so no custom dialog preview")

    SlashCmdList.SCROLLINGLOOT("")  -- toggles the window closed
    assert(not ScrollingLootOptionsFrame.shown and not ScrollingLootPreviewArea.shown)
    mark = #messages
    ScrollingLootFrame.scripts.OnUpdate(ScrollingLootFrame, 2)
    assert(#messages == mark, "no samples once the window is closed")
end)

test("Anniversary retains its defaults, Fast Loot events and custom bind dialog", function()
    ScrollingLootDB = nil
    StaticPopupDialogs = { LOOT_BIND = {} }
    StaticPopup_Show = function() end
    local first = loadMain({})
    assert(ScrollingLootDB.staticMode == false and ScrollingLootDB.iconSize == 26)
    local registered = false
    for index = first, #objects do
        if objects[index].events.LOOT_READY then registered = true end
    end
    assert(registered)
    assert(hooked("StaticPopup_Show"), "Anniversary installs its bind-on-pickup dialog")
end)

print(string.format("%d tests passed", passed))
