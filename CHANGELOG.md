# Changelog

## Unreleased

**New Features:**

- **Repeats Add Up** - Looting the same item again while its line is on screen adds to that line ("Linen Cloth x3") instead of opening a new one. Gold and honor add up the same way. In static mode the line also stays up for its full duration again; a scrolling line takes more only until it starts to fade.
- **No Lost Lines** - When the feed holds its maximum number of lines, new pickups wait and appear as older lines expire, instead of pushing the oldest line out. Waiting pickups of the same item add up too.

## v1.1.0

**Testing note:** None of these changes have been tried on Anniversary in game; they have local tests, and hover to pause was used on WoW Forever. Anniversary was last tested in game during the early phase (Karazhan and Magtheridon's Lair). Please report anything that breaks.

**New Features:**

- **WoW Forever Support (Experimental)** - The same download now loads on WoW Forever through its own TOC, listed as "Scrolling Loot (Forever Experimental)". It defaults to a compact static feed, reads pickups from the loot window as well as chat (Forever can hide loot chat text from addons), uses Forever's own bind-on-pickup prompt, and adds an Options > AddOns entry that opens the options window. Tested solo in the open world only: groups, dungeons, raids, battlegrounds and boss fights are untested. In those places Forever can hide loot chat text from addons, and the loot window fallback has not been checked there yet, so the feed may miss loot inside instances.

- **Hover to Pause** - Hovering a notification pauses the feed at full opacity and shows the item's tooltip. Pickups that arrive meanwhile appear once the cursor leaves. Clicks still pass through to the game world. On by default; toggle it under Animation in the options.

**Bug Fixes:**

- **Fast Loot Second Loot** - Looting corpses in quick succession could hide the next corpse's loot window before anything was taken, so it needed a second loot. The v1.0.9 fix reset the throttle too late; it now clears when a loot window closes.
- **Fast Loot With Full Bags** - With full bags, an empty corpse or money-only loot no longer flashes the loot window. The window stays open only when there is an item to pick up.
- **Anniversary Patch 2.5.6** - The TOC now targets interface 20506, so the game no longer lists the addon as out of date.

## v1.0.9

**Bug Fixes:**

- **Fast Loot Throttle Fix** - Fixed an issue where looting ground quest items (or any loot) in quick succession could silently fail, requiring a second interaction. The 0.3s anti-spam throttle now resets when a new loot window opens so it no longer blocks fresh loot attempts.

## v1.0.8

**Bug Fixes:**

- **Fast Loot Container Fix** - Fixed items getting stuck when opening containers (e.g. Nolkai's Box) with Fast Loot enabled. Now retries looting remaining items after each slot clears instead of relying on a single pass.
- **BoP Confirmation in Fast Loot** - Fixed custom Bind-on-Pickup confirmation dialog not appearing when Fast Loot auto-loots a BoP item. The addon now tracks the loot slot internally instead of relying on `LootFrame.selectedSlot` which is unset when the loot frame is hidden.

## v1.0.7

**Bug Fixes:**

- **Fast Loot Independence** - Fast Loot now works regardless of the game's auto-loot CVar setting. Previously, Fast Loot required either the game's auto-loot option to be enabled or the auto-loot modifier key to be held. Now the addon's Fast Loot setting is sufficient on its own.

## v1.0.6

**New Features:**

- **Text Alignment Option** - New dropdown in Appearance settings to choose between "Left", "Center", and "Right" alignment. Center mode positions notifications centered on screen like scrolling combat text. Right mode anchors notifications to the right edge, mirroring the left mode.

## v1.0.5

**New Features:**

- **Money Notifications** - Display gold, silver, and copper pickups as scrolling notifications with appropriate coin icons. Shows formatted amounts like "1g 50s 25c". Enabled by default. Supports all client languages.
- **Honor Point Notifications** - Display honor point gains as scrolling notifications with faction-appropriate PvP banner icons (Horde/Alliance). Enabled by default.
- **Honor Text Color Picker** - Customize the color of honor notifications via a color picker in the options panel. Only honor previews are shown while picking a color.
- New slash commands: `/sloot testmoney` and `/sloot testhonor` to preview the new notification types.

## v1.0.4

**Bug Fixes:**

- **Localization Support** - Fixed loot notifications not appearing for non-English clients. Now uses WoW's localized `LOOT_ITEM_SELF` pattern instead of hardcoded English text.

## v1.0.3

**Improvements:**

- **Full Inventory Handling** - When Fast Loot is enabled but inventory is full, the loot window now shows normally (instead of being hidden) to provide proper visual feedback
- When loot window is shown due to full inventory, master loot, or SHIFT override, the default BoP confirmation popup is used instead of the custom one

## v1.0.2

**New Features:**

- **Glow Effect** - Optional glowing effect around item icons for quality-based highlights. Configure minimum quality threshold for when glow appears.

**Improvements:**

- Renamed "Minimum Quality" to "Notifications Min Quality" for clarity
- Background now dynamically sizes to fit any item name length
- Drag instructions now appear as prominent text at top of screen when options are open

**Bug Fixes:**

- Fixed optional background not being vertically centered around loot text
- Fixed stacked loot notifications overlapping in static mode

## v1.0.1

**New Features:**

- **Fast Loot Mode** - Auto-loot items instantly and completely hide the loot window for seamless looting. Hold SHIFT while looting to show the window normally when you need it.

- **Enhanced Bind-on-Pickup Confirmation** - When Fast Loot is enabled, BoP items display a custom confirmation dialog showing the item's icon and name (instead of the generic popup).

- **Static Mode** - New display option where loot notifications fade in and out in place without scrolling upward. Great for a cleaner, less distracting look.

- **Drag-to-Position** - Open the options panel (`/sloot`) and drag the blue highlighted areas to reposition both loot notifications and the BoP confirmation dialog in real-time. No more fiddling with coordinate sliders!

- **Draggable BoP Dialog** - The BoP confirmation popup has its own separate position, also configurable via drag-to-position.

**Improvements:**

- Notifications now only appear for items entering YOUR inventory (no more seeing party members' loot)
- Master Loot protection: loot window stays visible when there are items above threshold that need to be distributed
- Live preview while configuring - see your changes instantly

## v1.0.0

- Initial release
