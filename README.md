# floorpaper

A tiled alternative to wallpaper. Pick a small tile image, floorpaper repeats
it across your screen and sets it as your desktop background.

## Architecture

The project is split into two scripts with a clean separation of concerns:

- **`tiler.sh`** - a standalone image-generation tool. Given one tile image,
  it produces a larger image made of that tile repeated across a canvas.
  It has no idea what a desktop environment is, and can be used on its own.
- **`floorpaper.sh`** - the interactive picker. It knows where your tile
  sources live, scans them for images, drives an `fzf` + `chafa` TUI with a
  live preview, and calls `tiler.sh` to generate each candidate. Setting the
  actual desktop wallpaper is delegated to a **backend** script.
- **`backends/*.sh`** - one script per desktop environment. Currently only
  GNOME is implemented (`backends/gnome.sh`), but the interface is small and
  generic on purpose, see [Adding a new backend](#adding-a-new-backend).

```
floorpaper.sh  --scans-->  tiles/ (git submodules, images only)
      |
      |--calls-->  tiler.sh   (generates the tiled image)
      |
      |--calls-->  backends/<de>.sh  (applies it, gets/restores current wallpaper)
```

## Dependencies

- `fzf` - interactive tile selection
- `chafa` - terminal image preview
- `imagemagick` (`convert`, `composite`, `identify`) - tile generation
- A supported desktop backend's own tools - for GNOME, `gsettings`
  (usually already present)

On Debian/Ubuntu:

```bash
sudo apt-get install fzf chafa imagemagick
```

## Usage

Run the picker:

```bash
./floorpaper.sh
```

This scans `tiles/` for image files, and opens an `fzf` window where moving
between candidates live-previews them as your actual wallpaper. Press Enter
to pick one, then confirm with `y`/`n`.

Useful flags:

```
-d, --tiles-dir <path>   Directory to scan for tile images (default: ./tiles)
-s, --size <WxH>         Force output resolution instead of auto-detecting
-c, --columns <N>        Tile repetitions across the width
-r, --rows <N>           Tile repetitions down the height
-t, --tile-size <WxH>    Explicit per-tile pixel size
```

With no sizing flags, tiles repeat at their native pixel size, same as the
original single-script version.

### Using tiler.sh directly

`tiler.sh` doesn't know or care about wallpapers - it just makes a tiled
image, so it's also useful on its own:

```bash
./tiler.sh -i mytile.png -o out.png -s 2560x1440 -c 12
```

See `./tiler.sh -h` for all options.

## Tile sources

Tile sources are managed as git submodules under `tiles/`. Only recognised
image extensions are scanned (`png jpg jpeg bmp gif tiff tif webp`) -
everything else in those repos (READMEs, licenses, etc.) is ignored
automatically.

See `tiles/sources.md` for the list of source repositories.

## Adding a new backend

A backend is a standalone executable script that implements five
subcommands. `floorpaper.sh` never sources a backend - it always calls it as
a subprocess (this also makes it work correctly from inside fzf's live
preview, which runs in its own subshell):

| Subcommand                     | Behaviour                                                              |
|---------------------------------|--------------------------------------------------------------------------|
| `is-supported`                  | Exit 0 if this backend applies to the current session, 1 otherwise.    |
| `get-resolution`                 | Print the primary display resolution as `WxH` to stdout.               |
| `get-current`                    | Print two lines: the current light-mode and dark-mode wallpaper URIs.  |
| `set-wallpaper <path>`           | Apply the local file at `<path>` as the wallpaper.                     |
| `restore <uri> <uri-dark>`       | Set the wallpaper back to two raw, previously-captured URIs.           |

`floorpaper.sh` tries every `backends/*.sh` in order and uses the first one
whose `is-supported` succeeds. To support another desktop (KDE, XFCE, sway,
i3, ...), drop in a new `backends/<name>.sh` implementing the same five
subcommands - no changes to `floorpaper.sh` itself are needed.

## Known limitations

- **Wayland resolution detection**: `backends/gnome.sh` gets the display
  resolution via `xrandr` (through XWayland), which isn't always exact under
  fractional scaling or multi-monitor setups. Use `floorpaper.sh --size` to
  override it explicitly if needed.
- **Uneven tile grids**: if the canvas size doesn't divide evenly by the
  computed tile size, the last tile in a row/column gets cropped at the
  edge. This is normal tiling behaviour, not a bug.
- Filenames containing spaces or quotes are not well-tested through the fzf
  preview pipeline.