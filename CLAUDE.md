# ScrollingLoot - Development Guide

## Project Overview

**ScrollingLoot** is a WoW Classic Anniversary addon, with WoW Forever support since v1.1.0, that displays looted items as animated scrolling text with icons near the center of the screen (similar to Diablo-style loot notifications).

### Key Files
- `ScrollingLoot.lua` - Main addon code (all logic in single file), shared by both games
- `ScrollingLoot.toc` - Anniversary manifest (interface 20506, patch 2.5.6)
- `ScrollingLoot_Camelot.toc` - Forever manifest (interface 16001, `AllowLoadGameType: camelot`); loads `Compat_Forever.lua` before the shared source
- `Compat_Forever.lua` - Forever adapter: settings launcher, defaults, self-loot matching, restricted-message guards, asynchronous C_Item lookup and the loot window source
- `tests/forever.lua` - Standalone Lua adapter/event tests with frame stand-ins; excluded from packages
- `README.md` - Documentation and the source for the CurseForge description. A release upload does not change the project page; update its description (and summary, if needed) separately once the release is live
- Deployed to: `/mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/ScrollingLoot/` and `/mnt/data/games/World of Warcraft/_forever_/Interface/AddOns/ScrollingLoot/`, the same files in both

### Features
- Scrolling loot notifications with item icons and quality-colored text
- **Money notifications**: Gold/silver/copper pickups with appropriate coin icons
- **Honor notifications**: Honor point gains with faction PvP icons (Horde/Alliance) and customizable text color
- Ace3-style options GUI (`/sloot` command)
- Live preview while configuring (auto-spawns test messages)
- **Repeats add up and lines queue** (v1.2.0, user confirmed in game on Forever 2026-11-05): a pickup of something already on screen adds to its line; past the maximum, new lines wait instead of pushing the oldest out
- **Hover to pause** (`hoverTooltips`, on by default): hovering a notification freezes the feed at full opacity and shows the item tooltip
- **Drag-to-position**: Blue highlighted areas appear over previews; drag to reposition in real-time
- **Fast Loot mode**: Loots every slot on `LOOT_READY` and hides the loot window (SHIFT shows it); the window stays open under master loot or when bags are full and the loot has an item
- **BoP confirmation (Anniversary only)**: Custom Bind-on-Pickup dialog shows item icon and name (replaces the generic popup when Fast Loot is enabled; Forever keeps the game's prompt)
- Optional background rectangle behind loot text (disabled by default, hybrid width: min 180px, max 320px)
- Configurable: icon/font size, scroll speed/distance, fade timing, quality filter, background toggle

### Architecture
- Uses object pooling for message frames
- OnUpdate-based animation (no XML AnimationGroups)
- Custom widget factory functions for sliders, checkboxes, dropdowns
- Draggable preview area frames for real-time positioning (loot notifications + BoP dialog)
- Messages store relative `stackOffsetY` (not absolute positions) so they follow when dragging. In static mode `PlaceNewMessage` puts a new line below the lowest one and `OnUpdate` eases each line toward slot `-(index - 1) * StackSpacing()` (`STATIC_SLIDE_RATE`), so lines keep arrival order and close the gap an expired line leaves (v1.2.2). Scrolling lines keep their spawn offset
- Hover pause: message frames are motion-enabled and click-disabled (clicks reach the world), sized to icon plus text with 6px hit insets. `MessageFrame_OnEnter` sets `feedPaused`, which stops `OnUpdate` timers and holds alpha at 1; new loot, money and honor messages are queued (`QueueWhilePaused`) so the hovered line never moves or expires. `MessageFrame_OnLeave` resumes after 0.1s unless another line is hovered; static-mode lines restart their fade. Item lines carry `itemLink` for `GameTooltip:SetHyperlink` (`Compat.EmitItem` passes the link on Forever). `ApplyHoverSetting` turns motion off on every frame when the option is off
- Feed lines (`ShowMessage`): every loot, money and honor message is a table (`kind`, `key`, `amount`, display fields) drawn by `ApplyMessage`. A message whose `key` matches a visible line (`item:<item string>`, `money`, `honor`) adds its amount to that line; static lines then restart their time (scrollTime back to the fade-in end), scrolling lines merge only before `FadeStart()`. Options-window samples and the `testmoney`/`testhonor` messages have no key and never merge; `/sloot test` items have one, so a second run adds to the first. Past `maxMessages`, messages wait in `overflowQueue` (merging there too) and `DrainQueue` shows them at the end of `OnUpdate` as lines expire
- Fast Loot system: `FastLootFrame` handles `LOOT_OPENED` (hide window) and `LOOT_READY` (auto-loot) events
- Fast Loot throttle (0.3s) guards only against repeated `LOOT_READY` in one window. It clears on `LOOT_CLOSED`, and `LOOT_SLOT_CLEARED` retries bypass it without refreshing it. Hiding the window ends the loot session, so a stale throttle used to hide the next corpse's window before anything was taken, and the corpse needed a second loot (fixed in v1.1.0; commit `bec17db`'s reset on `LOOT_OPENED` came too late)
- Full bags: `LOOT_OPENED` leaves the loot window up only when no bag slot is free and the loot has an item slot (`LootHasItem`), so empty and money-only loot stays hidden
- BoP confirmation: hooks `StaticPopup_Show("LOOT_BIND")` to show custom dialog with item icon/name
- SavedVariables: `ScrollingLootDB`

### WoW Forever (from v1.1.0)

Started as a local experiment on 2026-10-31; packaged for release with v1.1.0.
One package serves both games. Anniversary loads the base `ScrollingLoot.toc`.
The Forever client loads `ScrollingLoot_Camelot.toc` instead: the `_Camelot`
suffix string is in Forever's `Wow.exe`, and the BigWigs packager maps that
suffix and interface 16xxx to CurseForge's Forever game versions. That TOC loads
`Compat_Forever.lua` before the shared source. Without the adapter, the shared
source follows the Anniversary path. v1.1.0 labeled Forever support
"Experimental" in the TOC title, the Options > AddOns entry, the README and the
changelog; v1.2.0 dropped the label (user decision 2026-11-05). Solo dungeons and
open-world groups work (user report 2026-11-08). Group dungeon, raid and
battleground behavior is still untested, and the README says so without the technical reasons (user decision
2026-11-08). Untested gaps: group roll wins and master loot never pass through
the player's loot window, so where Forever hides loot chat they have no source;
battleground honor is chat only.

Forever defaults: static feed, five messages, 22px icons, 14px text, four-second
duration and a dark background. Native loot toasts are unchanged.

Options (2026-11-04, user request for the old live preview): Forever uses the same
custom options window as Anniversary (`CreateOptionsFrame`), with its live sample
feed and draggable position area. It replaced an earlier native Settings page,
because the game's settings panel (920x724, centered) covers the feed's default
position. The only Forever difference in the window is that Fast Loot never shows
the custom bind-on-pickup preview. `Compat.RegisterSettingsLauncher` adds an
Options > AddOns entry (a canvas category) whose button closes the game's panel
and opens the window.

Restored on 2026-11-04 (user request: restore what Forever does not already do):

- Fast Loot runs unchanged on Forever (off by default; saved settings are kept).
  Forever's loot window, like Anniversary's, calls `CloseLoot()` when hidden, and
  Fast Loot already loots on `LOOT_READY` before hiding the window on
  `LOOT_OPENED`.
- The custom bind-on-pickup dialog stays off (`Compat.nativeBindConfirm`): Forever's
  own `LOOT_BIND` prompt already names the item in its quality color and is
  driven by the bind event, not the loot window.
- Loot window source (`Compat_Forever.lua`): Forever can hide loot and money chat
  text from addons. Pickups are also recorded from the loot window: slots
  requested through `LootSlot` (hooked) confirm when the slot clears or the bag
  count rises; with auto loot, every cleared slot counts; money comes from the
  `GetMoney()` change after a money slot is taken. A record shows at once during
  `C_ChatInfo.InChatMessagingLockdown()`, otherwise after 1.5s unless a readable
  chat message for the same item ID or amount arrives. Records and readable chat
  messages cancel each other in either order within 4s (`ConsumeChatLoot`,
  `ConsumeChatMoney`). The adapter registers its loot events at load so it runs
  before Fast Loot's `LOOT_READY` handler.
- Forever item links color by quality name (`|cnIQ1:|Hitem:...`), not hex
  (`|cffffffff|Hitem:...`), so `ParseLootMessage` matches `|c[^|]+`. Before
  v1.2.1 it matched only hex: on Forever every chat pickup was dropped and shown
  1.5s late by the loot window source. The tests' item links use the Forever form.
- Battleground honor still has only the chat source.

Run `luac5.1 -p ScrollingLoot.lua Compat_Forever.lua` and `lua5.1 tests/forever.lua`.
The 24 tests cover merging repeated pickups, static lines sliding into the gap an expired line leaves, the overflow queue, `testhonor` lines not merging, hover pause (tooltip, held pickups, resume), async item lookup, message ownership, restricted input, Fast
Loot event order, a corpse opened within the throttle of the previous one, the
full-bags window rule (kept only when the loot has an item), the
loot window source and its duplicate suppression (both
arrival orders, lockdown and hidden chat), money, the settings launcher, the
options window's live preview without the bind-on-pickup preview, and
Anniversary defaults, Fast Loot events and bind dialog. They do not validate
rendering, the real event order in the client, or Blizzard's runtime
restrictions. The frame stand-ins intentionally do not emulate every UI method.

Test installs: copy the packaged folder (both TOCs, `ScrollingLoot.lua`,
`Compat_Forever.lua`, `LICENSE.md`) into each client's
`Interface/AddOns/ScrollingLoot/`, unchanged. A new or renamed TOC file is only
picked up after a client restart, not a `/reload`. `.pkgmeta` excludes `tests/`.
To check a package locally without uploading, run the BigWigs packager's
`release.sh -d -z -t <repo> -r <outdir>` from outside the repo.

### Slash Commands
- `/sloot` - Open options GUI (live preview + drag-to-position active)
- `/sloot test` - Show test loot messages
- `/sloot testmoney` - Show test money messages
- `/sloot testhonor` - Show test honor messages
- `/sloot on/off` - Enable/disable
- `/sloot reset` - Reset to defaults
- `/sloot help` - Show commands

### Development Workflow

See the `/wow-addon` skill for the standard development workflow (test, version, commit, deploy).

### Manual Zip (Deprecated - use CI/CD instead)

```bash
cd ~/git/mine && \
rm -f ~/ScrollingLoot-*.zip && \
zip -r ~/ScrollingLoot-$(grep "## Version:" ScrollingLoot/ScrollingLoot.toc | cut -d' ' -f3 | tr -d '\r').zip \
    ScrollingLoot/ScrollingLoot.toc ScrollingLoot/ScrollingLoot.lua ScrollingLoot/LICENSE.md
```



## WoW API Reference

For WoW Classic Anniversary API documentation, patterns, and development workflow, use the `/wow-addon` skill:
```
/wow-addon
```
This loads the shared TBC API reference, common patterns, and gotchas.
