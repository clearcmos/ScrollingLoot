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
