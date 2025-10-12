# floorpaper

A simple script to set tiled wallpapers on GNOME desktops.

## Dependencies

- `fzf` - for the interactive file selection
- `chafa` - for image preview in the terminal
- `imagemagick` - for creating the tiled wallpaper

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/floorpaper.git
   ```
2. Make sure you have the required dependencies installed. On Debian/Ubuntu, you can install them with:
   ```bash
   sudo apt-get install fzf chafa imagemagick
   ```

## Usage

Run the `tiler.sh` script:

```bash
./tiler.sh
```

This will open an interactive `fzf` window where you can select a tile. The script will then generate a tiled wallpaper and set it as your desktop background.

## Tile Sources

The script currently uses tiles from the following repository:

- `https://github.com/tile-anon/tiles.git`

You can find other tile sources in `TilesArchive/sources.md`. To use a different source, you will need to update the `TilesFolder` variable in `tiler.sh`.
