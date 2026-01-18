# Changelog

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
