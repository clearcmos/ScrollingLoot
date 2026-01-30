# ScrollingLoot - Development Guide

## Project Overview

**ScrollingLoot** is a WoW Classic Anniversary addon that displays looted items as animated scrolling text with icons near the center of the screen (similar to Diablo-style loot notifications).

### Key Files
- `ScrollingLoot.lua` - Main addon code (all logic in single file)
- `ScrollingLoot.toc` - Addon manifest
- `README.md` - Documentation (also used for CurseForge description)
- Deployed to: `/mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/ScrollingLoot/`

### Features
- Scrolling loot notifications with item icons and quality-colored text
- **Money notifications**: Gold/silver/copper pickups with appropriate coin icons
- **Honor notifications**: Honor point gains with faction PvP icons (Horde/Alliance) and customizable text color
- Ace3-style options GUI (`/sloot` command)
- Live preview while configuring (auto-spawns test messages)
- **Drag-to-position**: Blue highlighted areas appear over previews; drag to reposition in real-time
- **Fast Loot mode**: Auto-loot items instantly and completely hide loot window (SHIFT override to show normally)
- **Enhanced BoP confirmation**: Custom Bind-on-Pickup dialog shows item icon and name (replaces generic popup when Fast Loot enabled)
- Optional background rectangle behind loot text (disabled by default, hybrid width: min 180px, max 320px)
- Configurable: icon/font size, scroll speed/distance, fade timing, quality filter, background toggle

### Architecture
- Uses object pooling for message frames
- OnUpdate-based animation (no XML AnimationGroups)
- Custom widget factory functions for sliders, checkboxes, dropdowns
- Draggable preview area frames for real-time positioning (loot notifications + BoP dialog)
- Messages store relative `stackOffsetY` (not absolute positions) so they follow when dragging
- Fast Loot system: `FastLootFrame` handles `LOOT_OPENED` (hide window) and `LOOT_READY` (auto-loot) events
- BoP confirmation: hooks `StaticPopup_Show("LOOT_BIND")` to show custom dialog with item icon/name
- SavedVariables: `ScrollingLootDB`

### Slash Commands
- `/sloot` - Open options GUI (live preview + drag-to-position active)
- `/sloot test` - Show test loot messages
- `/sloot testmoney` - Show test money messages
- `/sloot testhonor` - Show test honor messages
- `/sloot on/off` - Enable/disable
- `/sloot reset` - Reset to defaults
- `/sloot help` - Show commands

### Development Workflow

**Before committing any changes:**

1. **Test in-game first** - Copy changed files to the addon folder for testing:
   ```
   /mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/ScrollingLoot/
   ```
   Then `/reload` in-game to verify the changes work.

2. **Update version numbers** - Before committing:
   - Add a new version section to `CHANGELOG.md` with the changes
   - Increment the version in `ScrollingLoot.toc` (`## Version: x.x.x`)

3. **Commit and push** - Only after testing and updating versions.

4. **Deploy to CurseForge** - Follow the steps in `CI.md` to create a tag and trigger the automated release.

### Manual Zip (Legacy - only if CI/CD is unavailable)

```bash
cd ~/git/mine && \
rm -f ~/ScrollingLoot-*.zip && \
zip -r ~/ScrollingLoot-$(grep "## Version:" ScrollingLoot/ScrollingLoot.toc | cut -d' ' -f3 | tr -d '\r').zip \
    ScrollingLoot/ScrollingLoot.toc ScrollingLoot/ScrollingLoot.lua ScrollingLoot/LICENSE.md
```
This creates `~/ScrollingLoot-x.x.x.zip` containing a `ScrollingLoot/` folder with the addon files.

---

# WoW Classic Anniversary Edition UI Source - Development Guide

This document provides comprehensive technical documentation for the World of Warcraft Classic Anniversary Edition (20th Anniversary) UI source code (version 2.5.5, build 65340). Use this guide when creating or modifying WoW addons for Classic Anniversary.

> **IMPORTANT**: If additional API references, function signatures, or implementation details are needed beyond what is documented here, refer directly to the Blizzard UI source code at `~/git/reference/wow-ui-source/`. This repository contains the complete official UI source and serves as the authoritative reference for all WoW Classic API patterns and implementations. Ensure the repo is on the `classic_anniversary` branch.

## Version Information

- **Game Version**: 2.5.5
- **Build**: 65340
- **Branch**: classic_anniversary
- **Game Type**: Classic Anniversary (TBC content, level 70 cap, WOW_PROJECT_ID = 5)

---

## Directory Structure

```
Interface/AddOns/
├── Blizzard_SharedXMLBase/     # Core framework utilities (Mixin, Pools, Tables)
├── Blizzard_SharedXML/         # Shared UI templates and widgets
├── Blizzard_SharedXMLGame/     # Game-specific shared components
├── Blizzard_FrameXMLBase/      # Frame XML base definitions
├── Blizzard_FrameXML/          # Core frame implementations
├── Blizzard_UIParent/          # Main UI root frame
├── Blizzard_UIParentPanelManager/
├── Blizzard_UIPanelTemplates/  # Standard panel templates
└── [180+ other Blizzard_* addons]
```

### Version-Specific Subdirectories

Many addons contain version-specific code in subdirectories:
- `Classic/` - Classic Era specific code
- `Vanilla/` - Original WoW (1.x) code
- `Shared/` - Code shared across versions

---

## Core Framework Architecture

### Mixin System (Object-Oriented Pattern)

The framework uses **Lua mixins** for inheritance and composition. This is the primary OOP pattern throughout the codebase.

**Location**: `Blizzard_SharedXMLBase/Mixin.lua`

```lua
-- Define a mixin
MyMixin = {};

function MyMixin:OnLoad()
    self:Initialize();
end

function MyMixin:Initialize()
    self.value = 0;
end

function MyMixin:GetValue()
    return self.value;
end

function MyMixin:SetValue(newValue)
    self.value = newValue;
end

-- Create object from mixin(s)
local obj = CreateFromMixins(MyMixin);
local obj = CreateFromMixins(MixinA, MixinB, MixinC);

-- Apply mixin to existing object
Mixin(existingObject, MyMixin);

-- Create and initialize in one call
local obj = CreateAndInitFromMixin(MyMixin, arg1, arg2);
```

**Secure Variants** (for combat-safe code):
```lua
-- Only work in secure execution context
if issecure() then
    local obj = CreateFromSecureMixins(SecureMixin);
    SecureMixin(frame, SecureMixinA);
end
```

### Callback Registry System

Custom event system separate from WoW's built-in events.

**Location**: `Blizzard_SharedXMLBase/CallbackRegistry.lua`

```lua
-- Define mixin with callbacks
MyFrameMixin = CreateFromMixins(CallbackRegistryMixin);

-- Declare custom events
MyFrameMixin:GenerateCallbackEvents({
    "OnValueChanged",
    "OnStateUpdated",
    "OnSelectionChanged",
});

function MyFrameMixin:OnLoad()
    CallbackRegistryMixin.OnLoad(self);
end

-- Register callback
frame:RegisterCallback("OnValueChanged", function(frame, newValue)
    print("Value changed to:", newValue);
end, owner);

-- Register with handle for easy unregistration
local handle = frame:RegisterCallbackWithHandle("OnValueChanged", callback, owner);
handle:Unregister();

-- Trigger event
frame:TriggerEvent("OnValueChanged", self.value);

-- Unregister
frame:UnregisterCallback("OnValueChanged", owner);
```

### WoW Event Registration

Standard WoW event handling pattern:

```lua
function MyMixin:OnLoad()
    self:RegisterEvent("PLAYER_LOGIN");
    self:RegisterEvent("PLAYER_LOGOUT");
    self:RegisterEvent("UNIT_HEALTH");
end

function MyMixin:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        self:HandlePlayerLogin();
    elseif event == "PLAYER_LOGOUT" then
        self:HandlePlayerLogout();
    elseif event == "UNIT_HEALTH" then
        local unit = ...;
        self:HandleUnitHealth(unit);
    end
end

-- Using FrameUtil for bulk registration
FrameUtil.RegisterFrameForEvents(frame, {
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "PLAYER_ENTERING_WORLD",
});

-- Unit-specific events
FrameUtil.RegisterFrameForUnitEvents(frame, {"UNIT_HEALTH", "UNIT_POWER_UPDATE"}, "player");
```

---

## Frame and Widget Patterns

### Object Pooling

Efficient frame reuse to prevent memory churn.

**Location**: `Blizzard_SharedXMLBase/Pools.lua`

```lua
-- Create object pool
local pool = CreateObjectPool(
    function(pool)  -- Creator function
        return CreateFrame("Frame", nil, parent, "MyTemplate");
    end,
    function(pool, frame)  -- Resetter function
        frame:Hide();
        frame:ClearAllPoints();
        frame:SetParent(nil);
    end
);

-- Acquire from pool (reuses or creates)
local frame, isNew = pool:Acquire();
if isNew then
    -- First-time initialization
end

-- Release back to pool
pool:Release(frame);

-- Release all objects
pool:ReleaseAll();

-- Get count
local activeCount = pool:GetNumActive();
```

### Frame Factory

Higher-level pooling with template support.

**Location**: `Blizzard_SharedXMLBase/FrameFactory.lua`

```lua
local factory = CreateFrameFactory();

-- Create frame (reuses from pool if available)
local frame, isNew = factory:Create(parent, "MyTemplate");

-- Release back to factory
factory:Release(frame);

-- Release all
factory:ReleaseAll();
```

### Button Templates

**Location**: `Blizzard_SharedXML/Shared/Button/`

```lua
-- Standard button mixin
UIButtonMixin = {};

function UIButtonMixin:InitButton()
    if self.buttonArtKit then
        self:SetButtonArtKit(self.buttonArtKit);
    end
end

function UIButtonMixin:OnClick(button, down)
    PlaySound(self.onClickSoundKit or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
    if self.onClickHandler then
        self.onClickHandler(self, button, down);
    end
end

function UIButtonMixin:SetButtonArtKit(artKit)
    self.buttonArtKit = artKit;
    self:SetNormalAtlas(artKit);
    self:SetPushedAtlas(artKit .. "-Pressed");
    self:SetDisabledAtlas(artKit .. "-Disabled");
    self:SetHighlightAtlas(artKit .. "-Highlight");
end
```

### Event Frame Template

Frames with built-in callback events for show/hide/size changes.

**Location**: `Blizzard_SharedXML/Shared/Frame/EventFrame.lua`

```lua
EventFrameMixin = CreateFromMixins(CallbackRegistryMixin);

EventFrameMixin:GenerateCallbackEvents({
    "OnHide",
    "OnShow",
    "OnSizeChanged",
});

function EventFrameMixin:OnLoad_Intrinsic()
    CallbackRegistryMixin.OnLoad(self);
end

function EventFrameMixin:OnShow_Intrinsic()
    self:TriggerEvent("OnShow");
end

function EventFrameMixin:OnHide_Intrinsic()
    self:TriggerEvent("OnHide");
end
```

---

## XML Template Patterns

### Basic Frame Declaration

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\..\UI.xsd">

    <!-- Virtual template (not instantiated directly) -->
    <Frame name="MyFrameTemplate" mixin="MyFrameMixin" virtual="true">
        <Size x="200" y="150"/>

        <KeyValues>
            <KeyValue key="title" value="My Frame" type="string"/>
            <KeyValue key="maxValue" value="100" type="number"/>
            <KeyValue key="enabled" value="true" type="boolean"/>
            <KeyValue key="callback" value="MyGlobalFunction" type="global"/>
        </KeyValues>

        <Anchors>
            <Anchor point="CENTER"/>
        </Anchors>

        <Scripts>
            <OnLoad method="OnLoad"/>
            <OnShow method="OnShow"/>
            <OnHide method="OnHide"/>
            <OnEvent method="OnEvent"/>
        </Scripts>
    </Frame>
</Ui>
```

### Frame Hierarchy with parentKey

```xml
<Frame name="MyDialogTemplate" mixin="MyDialogMixin" virtual="true">
    <Size x="400" y="300"/>

    <Frames>
        <!-- Access via self.CloseButton -->
        <Button name="$parentCloseButton" parentKey="CloseButton"
                inherits="UIPanelCloseButton">
            <Anchors>
                <Anchor point="TOPRIGHT" x="-5" y="-5"/>
            </Anchors>
        </Button>

        <!-- Access via self.ContentFrame -->
        <Frame name="$parentContent" parentKey="ContentFrame">
            <Size x="380" y="250"/>
            <Anchors>
                <Anchor point="TOPLEFT" x="10" y="-40"/>
            </Anchors>
        </Frame>

        <!-- Access via self.TitleText -->
        <FontString parentKey="TitleText" inherits="GameFontNormalLarge">
            <Anchors>
                <Anchor point="TOP" y="-15"/>
            </Anchors>
        </FontString>
    </Frames>
</Frame>
```

### Template Inheritance

```xml
<!-- Base template -->
<Button name="BaseButtonTemplate" virtual="true">
    <Size x="100" y="30"/>
    <NormalTexture file="Interface\Buttons\UI-Panel-Button-Up"/>
    <PushedTexture file="Interface\Buttons\UI-Panel-Button-Down"/>
    <HighlightTexture file="Interface\Buttons\UI-Panel-Button-Highlight"/>
</Button>

<!-- Extended template -->
<Button name="LargeButtonTemplate" inherits="BaseButtonTemplate" virtual="true">
    <Size x="200" y="40"/>
    <KeyValues>
        <KeyValue key="isLarge" value="true" type="boolean"/>
    </KeyValues>
</Button>
```

### Intrinsic Script Handlers

For templates that need to run code before or after inherited handlers:

```xml
<Frame name="EventFrame" mixin="EventFrameMixin" intrinsic="true">
    <Scripts>
        <OnLoad method="OnLoad_Intrinsic"/>
        <OnShow method="OnShow_Intrinsic" intrinsicOrder="postcall"/>
        <OnHide method="OnHide_Intrinsic" intrinsicOrder="postcall"/>
    </Scripts>
</Frame>
```

---

## Secure Frame System

### Secure Execution Context

Combat-sensitive operations require secure code.

**Location**: `Blizzard_FrameXML/SecureHandlers.lua`

```lua
-- Check if in secure context
if issecure() then
    -- Can perform protected operations
end

-- Secure function execution
securecallfunction(myFunction, arg1, arg2);

-- Secure range execution (for arrays)
secureexecuterange(table, 1, #table, function(index, value)
    -- Process each element securely
end);
```

### Secure State Drivers

Automatically manage frame state based on conditions.

**Location**: `Blizzard_FrameXML/SecureStateDriver.lua`

```lua
-- Register visibility driver (macro conditions)
RegisterStateDriver(frame, "visibility", "[combat] hide; show");

-- Register attribute driver
RegisterAttributeDriver(frame, "state-inCombat", "[combat] 1; 0");

-- Unit watch (show/hide based on unit existence)
RegisterUnitWatch(frame);  -- Shows when unit exists
RegisterUnitWatch(frame, true);  -- Sets state-unitexists attribute

-- Unregister
UnregisterStateDriver(frame, "visibility");
UnregisterUnitWatch(frame);
```

### Secure Types

Taint-safe container types.

**Location**: `Blizzard_SharedXMLBase/SecureTypes.lua`

```lua
-- Secure map
local secureMap = SecureTypes.CreateSecureMap();
secureMap:SetValue("key", "value");
local value = secureMap:GetValue("key");
for key, value in secureMap:Enumerate() do
    -- Safe iteration
end

-- Secure stack
local secureStack = SecureTypes.CreateSecureStack();
secureStack:Push(value);
local value = secureStack:Pop();

-- Secure number
local secureNum = SecureTypes.CreateSecureNumber();
secureNum:SetValue(100);
local value = secureNum:GetValue();
```

---

## Utility Functions

### FrameUtil

**Location**: `Blizzard_SharedXMLBase/FrameUtil.lua`

```lua
-- Apply mixins and auto-wire script handlers
FrameUtil.SpecializeFrameWithMixins(frame, MixinA, MixinB);

-- Register events
FrameUtil.RegisterFrameForEvents(frame, {"EVENT_A", "EVENT_B"});
FrameUtil.UnregisterFrameForEvents(frame, {"EVENT_A"});

-- Unit events
FrameUtil.RegisterFrameForUnitEvents(frame, {"UNIT_HEALTH"}, "player", "target");

-- Update function (periodic callback)
FrameUtil.RegisterUpdateFunction(frame, 0.1, function(frame, elapsed)
    -- Called every 0.1 seconds
end);
FrameUtil.UnregisterUpdateFunction(frame);

-- Get root parent
local root = FrameUtil.GetRootParent(frame);

-- Fit child to parent
FitToParent(parent, child);
```

### TableUtil

**Location**: `Blizzard_SharedXMLBase/TableUtil.lua`

```lua
-- Table operations
tContains(table, value)           -- Check if value exists
tInvert(table)                    -- Swap keys and values
tDeleteItem(table, value)         -- Remove by value
CountTable(table)                 -- Count elements

-- Find operations
local found = FindInTableIf(table, function(element)
    return element.id == targetId;
end);

local exists = ContainsIf(table, function(element)
    return element.active;
end);

-- Iteration
for index, value in ipairs_reverse(table) do
    -- Iterate backwards
end

for index, value in CreateTableEnumerator(table, minIndex, maxIndex) do
    -- Range iteration
end
```

### FunctionUtil

**Location**: `Blizzard_SharedXMLBase/FunctionUtil.lua`

```lua
-- Generate closure with pre-bound arguments
local closure = GenerateClosure(myFunction, arg1, arg2);
closure(arg3);  -- Calls myFunction(arg1, arg2, arg3)

-- Execute next frame
RunNextFrame(function()
    -- Runs on next frame update
end);

-- Safe method call
FunctionUtil.SafeInvokeMethod(object, "MethodName", arg1, arg2);

-- Execute frame script
ExecuteFrameScript(frame, "OnClick", "LeftButton", false);

-- Call method on ancestor
CallMethodOnNearestAncestor(frame, "UpdateLayout");
```

### EnumUtil

**Location**: `Blizzard_SharedXMLBase/EnumUtil.lua`

```lua
-- Create enum
local MyEnum = EnumUtil.MakeEnum("NONE", "ACTIVE", "PAUSED", "COMPLETE");
-- Result: { NONE = 1, ACTIVE = 2, PAUSED = 3, COMPLETE = 4 }

-- Validate
if EnumUtil.IsValid(MyEnum, value) then
    -- Valid enum value
end

-- Name translator
local getName = EnumUtil.GenerateNameTranslation(MyEnum);
print(getName(2));  -- "ACTIVE"
```

### Color Utilities

**Location**: `Blizzard_SharedXMLBase/Color.lua`

```lua
-- Create color
local color = CreateColor(1.0, 0.5, 0.0, 1.0);  -- RGBA

-- Color operations
color:SetRGBA(r, g, b, a);
local r, g, b, a = color:GetRGBA();
local hex = color:GenerateHexColor();  -- "FF8000"

-- Predefined colors (globals)
HIGHLIGHT_FONT_COLOR
NORMAL_FONT_COLOR
RED_FONT_COLOR
GREEN_FONT_COLOR
GRAY_FONT_COLOR
WHITE_FONT_COLOR
YELLOW_FONT_COLOR
ORANGE_FONT_COLOR
```

---

## UI Animation and Effects

### Frame Fading

```lua
-- Fade out
UIFrameFadeOut(frame, duration, startAlpha, endAlpha);
UIFrameFadeOut(frame, 0.5, 1.0, 0.0);

-- Fade in
UIFrameFadeIn(frame, duration, startAlpha, endAlpha);
UIFrameFadeIn(frame, 0.5, 0.0, 1.0);

-- Custom fade with callback
UIFrameFade(frame, {
    mode = "IN",  -- or "OUT"
    timeToFade = 0.5,
    startAlpha = 0.0,
    endAlpha = 1.0,
    finishedFunc = function()
        print("Fade complete");
    end,
    finishedArg1 = customArg,
});

-- Check fading state
if UIFrameIsFading(frame) then
    UIFrameFadeRemoveFrame(frame);  -- Cancel fade
end
```

---

## TOC File Structure

### Required Fields

```
## Interface: 20505
## Title: My Addon
## Notes: Description of my addon
## Author: Your Name
## Version: 1.0.0

## Dependencies: Blizzard_UIParent
## OptionalDeps: SomeOtherAddon

## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB

## DefaultState: enabled
## LoadOnDemand: 0

## AllowLoad: Game
## AllowLoadGameType: tbc

MyAddon.lua
MyAddon.xml
```

### Game Type Values

- `vanilla` - Classic Era (1.x)
- `tbc` - Burning Crusade Classic / Anniversary Edition (2.x)
- `wrath` - Wrath of the Lich King Classic (3.x)
- `cata` - Cataclysm Classic (4.x)
- `mainline` - Retail (current)

> **Note for Anniversary Edition**: Classic Anniversary uses Interface 20505 with TBC content. Use `tbc` as the game type. WOW_PROJECT_ID = 5 (same as TBC Classic).

---

## Lua Coding Conventions

### Naming Patterns

```lua
-- Mixins: PascalCase + "Mixin" suffix
MyFrameMixin = {};
ButtonControllerMixin = {};

-- Mixin methods: PascalCase
function MyFrameMixin:OnLoad()
function MyFrameMixin:GetValue()
function MyFrameMixin:SetEnabled(enabled)

-- Private/internal methods
function MyFrameMixin:UpdateInternal()

-- Global functions: PascalCase
function CreateMyWidget(parent, name)
function GetPlayerInfo()

-- Global constants: SCREAMING_SNAKE_CASE
MY_ADDON_VERSION = "1.0.0";
MAX_ITEM_COUNT = 100;

-- Local variables: camelCase or snake_case
local frameFactory = CreateFrameFactory();
local current_value = 0;
```

### Standard Script Handler Names

These method names are automatically wired as script handlers by `FrameUtil.SpecializeFrameWithMixins`:

```lua
StandardScriptHandlerSet = {
    OnLoad = true,
    OnShow = true,
    OnHide = true,
    OnEvent = true,
    OnEnter = true,
    OnLeave = true,
    OnClick = true,
    OnDragStart = true,
    OnReceiveDrag = true,
};
```

### Local References for Performance

```lua
-- Cache frequently used globals
local pairs = pairs;
local ipairs = ipairs;
local select = select;
local type = type;
local wipe = table.wipe;
local tinsert = table.insert;
local tremove = table.remove;

-- Cache API functions
local CreateFrame = CreateFrame;
local GetTime = GetTime;
local UnitHealth = UnitHealth;
```

### Typical Mixin Structure

```lua
MyAddonFrameMixin = CreateFromMixins(CallbackRegistryMixin);

MyAddonFrameMixin:GenerateCallbackEvents({
    "OnDataUpdated",
    "OnSelectionChanged",
});

function MyAddonFrameMixin:OnLoad()
    CallbackRegistryMixin.OnLoad(self);

    self:InitializeState();
    self:SetupChildren();
    self:RegisterEvents();
end

function MyAddonFrameMixin:InitializeState()
    self.data = {};
    self.selectedIndex = nil;
end

function MyAddonFrameMixin:SetupChildren()
    self.CloseButton:SetScript("OnClick", function()
        self:Hide();
    end);
end

function MyAddonFrameMixin:RegisterEvents()
    self:RegisterEvent("PLAYER_LOGIN");
    self:RegisterEvent("PLAYER_LOGOUT");
end

function MyAddonFrameMixin:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        self:OnPlayerLogin();
    end
end

function MyAddonFrameMixin:OnPlayerLogin()
    self:RefreshData();
end

function MyAddonFrameMixin:RefreshData()
    -- Update data
    self:TriggerEvent("OnDataUpdated", self.data);
end
```

---

## Classic/Anniversary-Specific Features

### Frame Locks

Control UI visibility based on game states.

**Location**: `Blizzard_FrameXMLBase/Classic/FrameLocks.lua`

```lua
-- Check if frame should be hidden due to lock
if IsFrameLockActive("PETBATTLES") then
    -- Pet battle UI lock is active
end

-- Smart show/hide (respects locks)
SmartShow(frame);
SmartHide(frame);

-- Check smart visibility
if IsFrameSmartShown(frame) then
    -- Frame is logically visible
end
```

### Store UI

```lua
-- Toggle store
ToggleStoreUI();

-- Set store visibility
SetStoreUIShown(true);
SetStoreUIShown(false);

-- Check if shown
if StoreFrame_IsShown() then
    -- Store is open
end
```

---

## Common Patterns

### Loot Events

Events for tracking looted items:

```lua
-- Chat-based loot event (fires when loot message appears in chat)
"CHAT_MSG_LOOT"     -- args: message, playerName, languageName, channelName, ...

-- Direct loot frame events
"LOOT_OPENED"       -- Loot window opens (arg: autoLoot bool)
"LOOT_READY"        -- Loot is ready for looting
"LOOT_SLOT_CHANGED" -- Item in slot changed (arg: slot index)
"LOOT_SLOT_CLEARED" -- Item looted/removed (arg: slot index)
"LOOT_CLOSED"       -- Loot window closed

-- Get loot slot info (when loot frame is open)
local texture, item, quantity, currencyID, quality, locked = GetLootSlotInfo(slot);
```

### Item Link Parsing from Chat Messages

Extract item information from chat messages containing item links:

```lua
-- Extract item link from chat message
-- Format: |cffRRGGBB|Hitem:itemID:...|h[Item Name]|h|r
local function ParseItemLink(message)
    local itemLink = strmatch(message, "(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)");
    if not itemLink then return nil; end

    -- Extract quantity (e.g., "x2" or "x5")
    local quantity = strmatch(message, "|rx(%d+)") or 1;
    quantity = tonumber(quantity);

    -- Get item info from link
    local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink);

    return itemName, itemIcon, itemQuality, quantity;
end

-- Get quality color
local r, g, b = GetItemQualityColor(quality);
-- Or via C_Item namespace:
local r, g, b = C_Item.GetItemQualityColor(quality);
```

### Screen-Relative Positioning

Position frames relative to screen center with proper UI scale handling:

```lua
-- Get actual screen dimensions accounting for UI scale
local function GetScaledScreenDimensions()
    local scale = UIParent:GetEffectiveScale();
    local screenWidth = GetScreenWidth() * scale;
    local screenHeight = GetScreenHeight() * scale;
    return screenWidth, screenHeight;
end

-- Position frame at screen center with offset
local function PositionAtScreenCenter(frame, offsetX, offsetY)
    local screenWidth, screenHeight = GetScaledScreenDimensions();
    local centerX = screenWidth / 2;
    local centerY = screenHeight / 2;

    frame:ClearAllPoints();
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX + offsetX, centerY + offsetY);
end
```

### Simple OnUpdate Animation

Animate frames without XML AnimationGroups using OnUpdate:

```lua
local SCROLL_SPEED = 3.0;      -- Duration in seconds
local FADE_START = 2.0;        -- When fade begins
local SCROLL_DISTANCE = 150;   -- Pixels to scroll

local activeFrames = {};

local function OnUpdate(self, elapsed)
    local i = 1;
    while i <= #activeFrames do
        local frame = activeFrames[i];
        frame.elapsed = frame.elapsed + elapsed;

        -- Check if animation complete
        if frame.elapsed >= SCROLL_SPEED then
            frame:Hide();
            tremove(activeFrames, i);
        else
            -- Update position (scroll upward)
            local progress = frame.elapsed / SCROLL_SPEED;
            local yOffset = SCROLL_DISTANCE * progress;
            frame:SetPoint("CENTER", UIParent, "CENTER", frame.startX, frame.startY + yOffset);

            -- Fade out near end
            if frame.elapsed >= FADE_START then
                local fadeProgress = (frame.elapsed - FADE_START) / (SCROLL_SPEED - FADE_START);
                frame:SetAlpha(1 - fadeProgress);
            end

            i = i + 1;
        end
    end
end

-- Start animation
local function StartAnimation(frame, startX, startY)
    frame.elapsed = 0;
    frame.startX = startX;
    frame.startY = startY;
    frame:SetAlpha(1);
    frame:Show();
    tinsert(activeFrames, frame);
end

-- Attach to parent frame
parentFrame:SetScript("OnUpdate", OnUpdate);
```

---

## Common API Functions (Classic Anniversary)

### Unit Functions

```lua
-- Unit info
UnitName(unit)
UnitClass(unit)
UnitLevel(unit)
UnitRace(unit)

-- Health/Power
UnitHealth(unit)
UnitHealthMax(unit)
UnitPower(unit, powerType)
UnitPowerMax(unit, powerType)

-- Status
UnitIsPlayer(unit)
UnitIsEnemy(unit, otherUnit)
UnitIsFriend(unit, otherUnit)
UnitIsDead(unit)
UnitIsGhost(unit)
UnitIsAFK(unit)

-- Combat
UnitAffectingCombat(unit)
UnitCanAttack(unit, target)
UnitThreatSituation(unit, target)
```

### Frame Functions

```lua
-- Creation
CreateFrame(frameType, name, parent, template)

-- Positioning
frame:SetPoint(point, relativeTo, relativePoint, x, y)
frame:ClearAllPoints()
frame:SetAllPoints(relativeTo)

-- Size
frame:SetSize(width, height)
frame:SetWidth(width)
frame:SetHeight(height)
frame:GetSize()

-- Visibility
frame:Show()
frame:Hide()
frame:SetShown(shown)
frame:IsShown()
frame:IsVisible()

-- Hierarchy
frame:SetParent(parent)
frame:GetParent()
frame:GetChildren()

-- Alpha/Visibility
frame:SetAlpha(alpha)
frame:GetAlpha()
frame:GetEffectiveAlpha()

-- Level
frame:SetFrameLevel(level)
frame:GetFrameLevel()
frame:SetFrameStrata(strata)

-- Mouse
frame:EnableMouse(enable)
frame:EnableMouseWheel(enable)
frame:SetMovable(movable)
frame:SetResizable(resizable)
```

### Texture Functions

```lua
-- Create texture
local tex = frame:CreateTexture(name, layer)

-- Set texture
tex:SetTexture(path)
tex:SetAtlas(atlasName)
tex:SetColorTexture(r, g, b, a)

-- Coordinates
tex:SetTexCoord(left, right, top, bottom)

-- Color
tex:SetVertexColor(r, g, b, a)

-- Blend mode
tex:SetBlendMode(mode)  -- "BLEND", "ADD", "ALPHAKEY", etc.
```

### FontString Functions

```lua
-- Create
local fs = frame:CreateFontString(name, layer, template)

-- Text
fs:SetText(text)
fs:GetText()
fs:SetFormattedText(format, ...)

-- Font
fs:SetFontObject(fontObject)
fs:SetFont(font, size, flags)

-- Color
fs:SetTextColor(r, g, b, a)

-- Justification
fs:SetJustifyH(justify)  -- "LEFT", "CENTER", "RIGHT"
fs:SetJustifyV(justify)  -- "TOP", "MIDDLE", "BOTTOM"
```

---

## Important Files Reference

| File | Purpose |
|------|---------|
| `Blizzard_SharedXMLBase/Mixin.lua` | Mixin system implementation |
| `Blizzard_SharedXMLBase/CallbackRegistry.lua` | Custom event system |
| `Blizzard_SharedXMLBase/Pools.lua` | Object pooling |
| `Blizzard_SharedXMLBase/FrameFactory.lua` | Frame factory pattern |
| `Blizzard_SharedXMLBase/TableUtil.lua` | Table utilities |
| `Blizzard_SharedXMLBase/FrameUtil.lua` | Frame utilities |
| `Blizzard_SharedXMLBase/FunctionUtil.lua` | Function utilities |
| `Blizzard_SharedXMLBase/SecureTypes.lua` | Taint-safe containers |
| `Blizzard_SharedXMLBase/Color.lua` | Color utilities |
| `Blizzard_SharedXMLBase/EnumUtil.lua` | Enum utilities |
| `Blizzard_FrameXML/SecureHandlers.lua` | Secure handler templates |
| `Blizzard_FrameXML/SecureStateDriver.lua` | State driver system |
| `Blizzard_FrameXMLBase/Classic/FrameLocks.lua` | Classic frame locks |

---

## Best Practices

### Avoid Taint

```lua
-- Use local references to avoid tainting globals
local CreateFrame = CreateFrame;
local securecallfunction = securecallfunction;

-- Use secure call for callbacks that might run in combat
securecallfunction(callback, arg1, arg2);
```

### Efficient Event Handling

```lua
-- Register only needed events
function MyMixin:OnLoad()
    -- Don't register for events you don't use
    self:RegisterEvent("SPECIFIC_EVENT_NEEDED");
end

-- Unregister when not needed
function MyMixin:OnHide()
    self:UnregisterAllEvents();
end

function MyMixin:OnShow()
    self:RegisterEvent("SPECIFIC_EVENT_NEEDED");
end
```

### Memory Management

```lua
-- Use object pools for frequently created/destroyed frames
local buttonPool = CreateObjectPool(
    function() return CreateFrame("Button", nil, parent, "MyButtonTemplate"); end,
    function(pool, button)
        button:Hide();
        button:ClearAllPoints();
    end
);

-- Reuse tables instead of creating new ones
local reuseTable = {};
function ProcessData(data)
    wipe(reuseTable);
    -- Use reuseTable instead of creating new table
end
```

### Error Handling

```lua
-- Protected calls for potentially failing code
local success, result = pcall(function()
    -- Potentially dangerous code
end);

if not success then
    print("Error:", result);
end

-- xpcall with error handler
xpcall(
    function()
        -- Code that might error
    end,
    function(err)
        print("Error occurred:", err);
        print(debugstack());
    end
);
```

---

## Debugging Tips

```lua
-- Print debug info
print("Debug:", variable);

-- Dump table contents
DevTools_Dump(myTable);

-- Stack trace
print(debugstack());

-- Frame inspection (in game)
/fstack  -- Show frame stack under cursor
/eventtrace  -- Show event trace

-- Reload UI
/reload
ReloadUI()
```

---

## Resources

- **Wowpedia API Documentation**: https://wowpedia.fandom.com/wiki/World_of_Warcraft_API
- **WoW Programming**: https://wowprogramming.com/
- **Townlong Yak**: https://www.townlong-yak.com/framexml/live
