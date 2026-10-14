# FS22_CropBrush

A Farming Simulator 22 mod that lets you **paint crops onto your fields from the build menu**, just like painting terrain textures. You can also plant a **whole field at once**.

## Features

- One brush per sowable crop (wheat, barley, canola, maize, sugar beet, grass, ...) plus a **Remove crop** brush
- Choose the growth stage: seeded, growing, ready to harvest, withered or harvested (stubble)
- Adjustable brush size (1 to 25 m)
- **Whole field** mode: plant or clear the entire field under the cursor in one click
- Only works on land you own, and only changes existing field ground
- Multiplayer: clients send their paint requests to the server

## Installation

1. Download `FS22_CropBrush.zip` from the [Releases](../../releases) page, or zip the contents of this repository yourself. `modDesc.xml` must be at the root of the zip.
2. Put the zip in `Documents\My Games\FarmingSimulator2022\mods`.
3. Turn on **Crop Brush** when you load your savegame.

## Usage

Open the build menu and go to **Landscaping → Paint**. The crop brushes are at the end of the list.

| Input | Action |
|---|---|
| Left mouse (hold) | Paint the selected crop |
| Mouse wheel | Change brush size |
| Secondary action | Choose growth stage |
| Tertiary action | Plant (or clear) the whole field under the cursor |

The key for each action is shown in the help bar at the bottom of the build menu.

## Status

This is an early version and hasn't been fully tested in game yet. If something doesn't work, open
`Documents\My Games\FarmingSimulator2022\log.txt`, search for `[CropBrush]`, and open an issue with those lines.

## Files

- `modDesc.xml`: mod description
- `scripts/CropBrush.lua`: the build menu brush and the hook that adds it to the menu
- `scripts/CropBrushUtil.lua`: field lookup and writing crops into the field
- `scripts/CropBrushEvent.lua`: multiplayer event (client to server)

## Credits

Made by Timo. The build menu integration follows the approach used by [Courseplay for FS22](https://github.com/Courseplay/Courseplay_FS22).
