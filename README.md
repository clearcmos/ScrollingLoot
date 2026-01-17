# ScrollingLoot

Displays looted items as scrolling text notifications with icons, fully configurable via an intuitive options panel with drag-to-position support.

Built for WoW Classic Anniversary Edition (2.5.5).

## Features

- Displays loot as scrolling text anywhere on your screen
- Shows item icons alongside item names
- Colors item names by rarity (grey, white, green, blue, purple, orange)
- Displays stack quantities for multi-item loots
- **Drag-to-position**: Open options and drag the highlighted area to reposition loot text in real-time
- Minimum quality filter to reduce clutter
- Adjustable font and icon sizes
- Configurable scroll speed, distance, and fade timing
- Optional background rectangle behind loot text
- Smooth fade-out animation
- Live preview while configuring

## Installation

1. Download or clone this repository
2. Copy the `ScrollingLoot` folder to your `Interface/AddOns/` directory
3. Restart WoW or type `/reload`

## Commands

- `/sloot` - Open options GUI (with live preview and drag-to-position)
- `/sloot test` - Display test messages
- `/sloot on` - Enable the addon
- `/sloot off` - Disable the addon
- `/sloot reset` - Reset all settings to defaults
- `/sloot help` - Show available commands

## Configuration

Open the options panel with `/sloot` to configure:

- **Enable/Disable** - Toggle the addon on/off
- **Show Stack Counts** - Display quantity for multi-item loots
- **Show Background** - Optional dark background behind loot text
- **Background Opacity** - Adjust background transparency
- **Minimum Quality** - Filter out items below a certain rarity
- **Max Simultaneous Messages** - Limit how many loot messages show at once
- **Icon Size** - Adjust item icon size
- **Font Size** - Adjust text size
- **Scroll Duration** - How long messages stay on screen
- **Fade Start Time** - When the fade-out begins
- **Scroll Distance** - How far messages scroll upward

### Positioning

While the options panel is open, a **blue highlighted area** appears over the preview messages. Simply **drag this area** to reposition where loot notifications appear on your screen. The preview messages move in real-time as you drag.

## Quality Values

| Value | Quality |
|-------|---------|
| 0 | Poor (grey) |
| 1 | Common (white) |
| 2 | Uncommon (green) |
| 3 | Rare (blue) |
| 4 | Epic (purple) |
| 5 | Legendary (orange) |

## Saved Variables

Settings are saved per-account in `ScrollingLootDB`.

## License

MIT License - See [LICENSE.md](LICENSE.md)
