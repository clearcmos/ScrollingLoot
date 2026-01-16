# ScrollingLoot

A lightweight World of Warcraft addon that displays looted items as scrolling text with icons and quality colors.

Built for WoW Classic Anniversary Edition (2.5.5).

## Features

- Displays loot as scrolling combat text near the center of your screen
- Shows item icons alongside item names
- Colors item names by rarity (grey, white, green, blue, purple, orange)
- Displays stack quantities for multi-item loots
- Configurable positioning (left/right side, x/y offsets)
- Minimum quality filter to reduce clutter
- Adjustable font and icon sizes
- Smooth fade-out animation

## Installation

1. Download or clone this repository
2. Copy the `ScrollingLoot` folder to your `Interface/AddOns/` directory
3. Restart WoW or type `/reload`

## Commands

| Command | Description |
|---------|-------------|
| `/sloot` | Show help and available commands |
| `/sloot on` | Enable the addon |
| `/sloot off` | Disable the addon |
| `/sloot test` | Display test messages |
| `/sloot left` | Position text on left side of screen center |
| `/sloot right` | Position text on right side of screen center |
| `/sloot x <0-800>` | Set horizontal offset from center |
| `/sloot y <-500 to 500>` | Set vertical offset (negative = lower) |
| `/sloot size <8-32>` | Set font size |
| `/sloot minquality <0-5>` | Set minimum item quality to display |

### Quality Values

| Value | Quality |
|-------|---------|
| 0 | Poor (grey) |
| 1 | Common (white) |
| 2 | Uncommon (green) |
| 3 | Rare (blue) |
| 4 | Epic (purple) |
| 5 | Legendary (orange) |

## Configuration

Settings are saved per-account in `ScrollingLootDB`. Default values:

- **Font size**: 18
- **Icon size**: 26
- **Scroll duration**: 3.5 seconds
- **Scroll distance**: 150 pixels
- **Position**: Right side of screen center
- **Minimum quality**: 0 (show all items)

## Similar Addons

- [Scrolling Loot Text (SLoTe)](https://www.curseforge.com/wow/addons/slote) - Similar functionality with auto-loot
- [Mik's Scrolling Battle Text](https://www.curseforge.com/wow/addons/mik-scrolling-battle-text) - Comprehensive SCT with loot support

## License

MIT License - See [LICENSE.md](LICENSE.md)
