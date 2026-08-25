Project Path: floorpaper

Source Tree:

```txt
floorpaper
├── backends
│   ├── gnome.sh
│   ├── kde.sh
│   └── termux.sh
├── floorpaper.sh
├── install.sh
├── tiler.sh
└── tiles
    ├── jessefalzone
    │   └── windows-wallpaper-tiles
    ├── rann01
    │   └── IRIX-tiles
    ├── rasatpc
    │   └── Tiled-wallpapers
    ├── sources.md
    ├── stephenmkbrady
    │   └── seamless_tileable_wallpapers
    ├── tile-anon
    │   └── tiles
    └── wallace-aph
        └── tiles-and-such

```

`backends/gnome.sh`:

```sh
#!/bin/bash
#
# backends/gnome.sh - GNOME desktop-environment backend for floorpaper.
#
# Every backend is a standalone executable implementing this subcommand
# protocol (floorpaper.sh calls these as subprocesses, never sources them,
# so they work fine inside fzf's --preview subshell too):
#
#   is-supported              exit 0 if this backend applies to the running
#                              session, exit 1 otherwise. No output.
#   get-resolution             print "WxH" for the primary display to stdout.
#   get-current                print two lines to stdout: the current
#                              picture-uri, then the current picture-uri-dark.
#   set-wallpaper <path>       apply <path> (a local file) as the wallpaper.
#   restore <uri> <uri-dark>   set picture-uri/picture-uri-dark back to
#                              exact raw URI values (used to undo set-wallpaper).
#
set -euo pipefail

Schema="org.gnome.desktop.background"

cmd_is_supported() {
  command -v gsettings &>/dev/null && [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]]
}

cmd_get_resolution() {
  if command -v xrandr &>/dev/null && [ -n "${DISPLAY:-}" ]; then
    local res
    res="$(xrandr --current 2>/dev/null | awk '/\*/ {print $1; exit}')"
    if [ -n "$res" ]; then
      echo "$res"
      return 0
    fi
  fi
  # GNOME on pure Wayland (no XWayland info available) has no simple CLI
  # for this. Fall back to a common default; callers can override with
  # floorpaper.sh --size.
  echo "Warning: could not detect display resolution, defaulting to 1920x1080." >&2
  echo "1920x1080"
}

cmd_get_current() {
  gsettings get "$Schema" picture-uri | sed -e "s/^'//" -e "s/'$//"
  gsettings get "$Schema" picture-uri-dark | sed -e "s/^'//" -e "s/'$//"
}

cmd_set_wallpaper() {
  local path="$1" dir base ext cache_buster unique_path uri
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  ext="${base##*.}"
  cache_buster="${base%.*}_$(date +%s%N).${ext}"
  unique_path="$dir/$cache_buster"
  cp -f "$path" "$unique_path"
  uri="file://$unique_path"
  gsettings set "$Schema" picture-uri "$uri"
  gsettings set "$Schema" picture-uri-dark "$uri"
  find "$dir" -maxdepth 1 -type f -name "${base%.*}_*.${ext}" ! -name "$cache_buster" -delete 2>/dev/null || true
}

cmd_restore() {
  local uri="$1" uri_dark="$2"

  # Helper function to generate a cache-busted URI
  _cache_bust_uri() {
    local target_uri="$1"
    local path="${target_uri#file://}" # Strip file:// prefix to get raw file path

    if [ -n "$path" ] && [ -f "$path" ]; then
      local dir base ext cache_buster unique_path
      dir="$(dirname "$path")"
      base="$(basename "$path")"
      ext="${base##*.}"
      cache_buster="${base%.*}_$(date +%s%N).${ext}"
      unique_path="$dir/$cache_buster"

      cp -f "$path" "$unique_path"
      find "$dir" -maxdepth 1 -type f -name "${base%.*}_*.${ext}" ! -name "$cache_buster" -delete 2>/dev/null || true
      echo "file://$unique_path"
    else
      echo "$target_uri"
    fi
  }

  if [ "$uri" = "$uri_dark" ]; then
    local new_uri
    new_uri="$(_cache_bust_uri "$uri")"
    gsettings set "$Schema" picture-uri "$new_uri"
    gsettings set "$Schema" picture-uri-dark "$new_uri"
  else
    local new_uri new_uri_dark
    new_uri="$(_cache_bust_uri "$uri")"
    new_uri_dark="$(_cache_bust_uri "$uri_dark")"
    gsettings set "$Schema" picture-uri "$new_uri"
    gsettings set "$Schema" picture-uri-dark "$new_uri_dark"
  fi
}

case "${1:-}" in
  is-supported)   cmd_is_supported ;;
  get-resolution) cmd_get_resolution ;;
  get-current)    cmd_get_current ;;
  set-wallpaper)  [ $# -eq 2 ] || { echo "Usage: $0 set-wallpaper <path>" >&2; exit 1; }; cmd_set_wallpaper "$2" ;;
  restore)        [ $# -eq 3 ] || { echo "Usage: $0 restore <uri> <uri-dark>" >&2; exit 1; }; cmd_restore "$2" "$3" ;;
  *) echo "Usage: $0 {is-supported|get-resolution|get-current|set-wallpaper|restore}" >&2; exit 1 ;;
esac
```
`backends/kde.sh`:

```sh
#!/bin/bash
#
# backends/kde.sh - KDE Plasma backend for floorpaper.
#
set -euo pipefail

cmd_is_supported() {
  [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] && command -v plasma-apply-wallpaperimage &>/dev/null
}

cmd_get_resolution() {
  # Attempt native KDE Wayland resolution detection safely
  if command -v kscreen-doctor &>/dev/null; then
    local res
    res="$(kscreen-doctor -o 2>/dev/null | grep -oE 'geometry: [0-9,-]+ [0-9x]+' | head -n 1 | awk '{print $3}' || true)"
    if [ -n "$res" ]; then
      echo "$res"
      return 0
    fi
  fi
  
  # Fallback to xrandr
  if command -v xrandr &>/dev/null && [ -n "${DISPLAY:-}" ]; then
    local res
    res="$(xrandr --current 2>/dev/null | awk '/\*/ {print $1; exit}' || true)"
    if [ -n "$res" ]; then
      echo "$res"
      return 0
    fi
  fi
  
  echo "1920x1080"
}

cmd_get_current() {
  local config_file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  if [ -f "$config_file" ]; then
    local current_img
    current_img="$(grep '^Image=' "$config_file" 2>/dev/null | tail -n 1 | sed -e 's/^Image=//' -e 's/^file:\/\///' || true)"
    echo "$current_img"
    echo "$current_img"
  else
    echo ""
    echo ""
  fi
}

cmd_set_wallpaper() {
  local path="$1"
  if [ ! -f "$path" ]; then
    return 1
  fi
  
  local dir filename cache_buster unique_path
  dir="$(dirname "$path")"
  filename="$(basename "$path")"
  
  cache_buster="${filename%.*}_kde_$(date +%s%N).${filename##*.}"
  unique_path="$dir/$cache_buster"
  
  if cp -f "$path" "$unique_path" 2>/dev/null; then
    plasma-apply-wallpaperimage "$unique_path" >/dev/null 2>&1 || true
    # Clean up old previews safely
    find "$dir" -maxdepth 1 -type f -name "${filename%.*}_kde_*.*" ! -name "$cache_buster" -delete 2>/dev/null || true
  fi
}

cmd_restore() {
  local uri="$1"
  if [ -n "$uri" ]; then
    plasma-apply-wallpaperimage "$uri" >/dev/null 2>&1 || true
  fi
}

case "${1:-}" in
  is-supported)   cmd_is_supported ;;
  get-resolution) cmd_get_resolution ;;
  get-current)    cmd_get_current ;;
  set-wallpaper)  [ $# -eq 2 ] || { echo "Usage: $0 set-wallpaper <path>" >&2; exit 1; }; cmd_set_wallpaper "$2" ;;
  restore)        [ $# -eq 3 ] || { echo "Usage: $0 restore <uri> <uri-dark>" >&2; exit 1; }; cmd_restore "$2" "$3" ;;
  *) echo "Usage: $0 {is-supported|get-resolution|get-current|set-wallpaper|restore}" >&2; exit 1 ;;
esac
```
`backends/termux.sh`:

```sh
#!/bin/bash
#
# backends/android.sh - Termux/Android backend for floorpaper.
#
set -euo pipefail

cmd_is_supported() {
  # Check if we are running in Termux and have the termux-api installed
  [[ -n "${TERMUX_VERSION:-}" ]] && command -v termux-wallpaper &>/dev/null
}

cmd_get_resolution() {
  # Termux cannot reliably query the physical screen resolution without root.
  # We return a common modern Android resolution; users can override via --size.
  echo "1080x2400"
}

cmd_get_current() {
  # Android does not expose the current wallpaper's file path.
  echo ""
  echo ""
}

cmd_set_wallpaper() {
  local path="$1"
  # -f sets the wallpaper from a local file
  termux-wallpaper -f "$path" >/dev/null 2>&1
}

cmd_restore() {
  # Cannot restore because we cannot retrieve the original wallpaper URI.
  :
}

case "${1:-}" in
  is-supported)   cmd_is_supported ;;
  get-resolution) cmd_get_resolution ;;
  get-current)    cmd_get_current ;;
  set-wallpaper)  [ $# -eq 2 ] || { echo "Usage: $0 set-wallpaper <path>" >&2; exit 1; }; cmd_set_wallpaper "$2" ;;
  restore)        [ $# -eq 3 ] || { echo "Usage: $0 restore <uri> <uri-dark>" >&2; exit 1; }; cmd_restore "$2" "$3" ;;
  *) echo "Usage: $0 {is-supported|get-resolution|get-current|set-wallpaper|restore}" >&2; exit 1 ;;
esac
```
`floorpaper.sh`:

```sh
#!/bin/bash
#
# floorpaper.sh - Interactive tiled-wallpaper picker.
#
set -euo pipefail

if [ "$EUID" -eq 0 ]; then
  echo -e "Do not run floorpaper as root!\nfloorpaper stopped!"
  exit 1
fi

ScriptDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TilerScript="$ScriptDir/tiler.sh"
BackendsDir="$ScriptDir/backends"
TilesDir="${TILES_DIR:-$ScriptDir/tiles}"

DataDir="${XDG_DATA_HOME:-$HOME/.local/share}/floorpaper"
PreviewWallpaper="$DataDir/preview_wallpaper.png"
GeneratedWallpaper="$DataDir/wallpaper.png"
BackupWallpaper="$DataDir/backup_wallpaper.png"

ImageExtensions=(png jpg jpeg bmp gif tiff tif webp)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -d, --tiles-dir <path>     Directory to scan for tile images (default: ./tiles)
  -s, --size <WxH>           Force output resolution instead of auto-detecting
  -c, --columns <N>          Tile repetitions across the width (passed to tiler.sh)
  -r, --rows <N>             Tile repetitions down the height (passed to tiler.sh)
  -t, --tile-size <WxH>      Explicit per-tile pixel size (passed to tiler.sh)
  -bf, --backend-flags <str> Pass custom flags directly to the backend
  -u, --uninstall            Uninstall floorpaper global binary and assets
  -h, --help                 Show this help and exit
EOF
}

cmd_uninstall() {
  echo "Uninstalling floorpaper..."
  local bin_dirs=()
  if [ -n "${PREFIX:-}" ]; then
    bin_dirs+=("$PREFIX/bin")
  fi
  bin_dirs+=("$HOME/.local/bin" "/usr/local/bin")

  for bdir in "${bin_dirs[@]}"; do
    if [ -f "$bdir/floorpaper" ]; then
      rm -f "$bdir/floorpaper"
      echo "Removed binary: $bdir/floorpaper"
    fi
  done

  if [ -d "$DataDir" ]; then
    rm -rf "$DataDir"
    echo "Removed data directory: $DataDir"
  fi

  echo "Floorpaper uninstalled successfully."
  exit 0
}

OverrideSize=""
Columns=""
Rows=""
TileSize=""
BackendFlags=""

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--tiles-dir)     TilesDir="${2:-}"; shift 2 ;;
    -s|--size)          OverrideSize="${2:-}"; shift 2 ;;
    -c|--columns)       Columns="${2:-}"; shift 2 ;;
    -r|--rows)          Rows="${2:-}"; shift 2 ;;
    -t|--tile-size)     TileSize="${2:-}"; shift 2 ;;
    -bf|--backend-flags) BackendFlags="${2:-}"; shift 2 ;;
    -u|--uninstall)     cmd_uninstall ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "Error: unknown option '$1'" >&2; usage; exit 1 ;;
  esac
done

# ---- Dependency check ----
for cmd in fzf chafa; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is not installed." >&2
    exit 1
  fi
done
if [ ! -x "$TilerScript" ]; then
  echo "Error: tiler.sh not found or not executable at $TilerScript" >&2
  exit 1
fi
if [ ! -d "$TilesDir" ]; then
  echo "Error: tiles directory not found: $TilesDir" >&2
  exit 1
fi

# ---- Backend detection ----
Backend=""
if [ -d "$BackendsDir" ]; then
  for candidate in "$BackendsDir"/*.sh; do
    [ -x "$candidate" ] || continue
    if "$candidate" is-supported 2>/dev/null; then
      Backend="$candidate"
      break
    fi
  done
fi

if [ -z "$Backend" ]; then
  echo "Error: no supported desktop-environment backend found for this session." >&2
  echo "Currently available backends:" >&2
  for candidate in "$BackendsDir"/*.sh; do
    echo "  - $(basename "$candidate")" >&2
  done
  exit 1
fi

# Forward backend flags if supplied
if [ -n "$BackendFlags" ]; then
  "$Backend" set-flags "$BackendFlags"
fi

# ---- Resolution ----
if [ -n "$OverrideSize" ]; then
  Resolution="$OverrideSize"
else
  Resolution="$("$Backend" get-resolution)"
fi
CanvasW="${Resolution%x*}"

# ---- Extra sizing args for tiler.sh ----
TilerExtraArgs=()
if [ -n "$TileSize" ]; then
  TilerExtraArgs+=(-t "$TileSize")
else
  [ -n "$Columns" ] && TilerExtraArgs+=(-c "$Columns")
  [ -n "$Rows" ] && TilerExtraArgs+=(-r "$Rows")
fi

# ---- Scan for tile images and format fzf items ----
FindExprParts=()
for ext in "${ImageExtensions[@]}"; do
  FindExprParts+=(-o -iname "*.$ext")
done

mapfile -t TileFiles < <(find "$TilesDir" -type f \( "${FindExprParts[@]:1}" \) -not -path '*/.git/*' | sort)

if [ "${#TileFiles[@]}" -eq 0 ]; then
  echo "Error: no tile images found under $TilesDir" >&2
  exit 1
fi

# Build tab-delimited list for fzf: <filename_without_extension>\t<full_path>
FzfInput=()
for filepath in "${TileFiles[@]}"; do
  fname="${filepath##*/}"
  name_no_ext="${fname%.*}"
  FzfInput+=("${name_no_ext}"$'\t'"${filepath}")
done

mkdir -p "$DataDir"

# Backup existing wallpaper image if present
if [ -f "$GeneratedWallpaper" ]; then
  cp -f "$GeneratedWallpaper" "$BackupWallpaper" 2>/dev/null || true
fi

# ---- Zoom/Grid State ----
ColFile="$DataDir/columns"
ColInitFile="$DataDir/columns_init"
echo "${Columns:-}" > "$ColFile"
echo "${Columns:-}" > "$ColInitFile"

# ---- Backup current wallpaper URI state ----
mapfile -t OriginalUris < <("$Backend" get-current)
OriginalLight="${OriginalUris[0]:-}"
OriginalDark="${OriginalUris[1]:-}"

RestoreOriginal() {
  if [ -f "$BackupWallpaper" ]; then
    cp -f "$BackupWallpaper" "$GeneratedWallpaper" 2>/dev/null || true
  fi

  if [ -n "$OriginalLight" ] || [ -n "$OriginalDark" ]; then
    "$Backend" restore "$OriginalLight" "$OriginalDark" 2>/dev/null || true
  elif [ -f "$GeneratedWallpaper" ]; then
    "$Backend" set-wallpaper "$GeneratedWallpaper" 2>/dev/null || true
  fi

  rm -f "$PreviewWallpaper" 2>/dev/null || true
}

trap RestoreOriginal EXIT INT TERM HUP

# ---- Determine terminal shape for responsive preview layout ----
TermCols="$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")"
TermLines="$(tput lines 2>/dev/null || echo "${LINES:-24}")"

# Multiply TermLines by 2 to account for the roughly 1:2 (Width:Height) 
# aspect ratio of standard terminal characters.
if (( TermLines * 2 >= TermCols )); then
  PreviewWindowOpt="top:60%"
else
  PreviewWindowOpt="right:50%"
fi

# Helper command for zoom bindings
ZoomCmd='zoom() { delta="$1"; img="$2"; cols=$(tr -d "[:space:]" < "'"$ColFile"'"); if [ -z "$cols" ]; then w=$(identify -format "%w" "$img" 2>/dev/null || echo 0); if [ "${w:-0}" -gt 0 ]; then cols=$(( '"$CanvasW"' / w )); [ "$cols" -lt 1 ] && cols=1; else cols=10; fi; fi; cols=$(( cols + delta )); [ "$cols" -lt 1 ] && cols=1; echo "$cols" > "'"$ColFile"'"; }; zoom'
# Preview command: skips identify calls when explicit columns are defined
PreviewCmd='cols=$(tr -d "[:space:]" < "'"$ColFile"'"); if [ -n "$cols" ]; then opts="-c $cols"; grid_str="$cols columns"; else opts="'"${TilerExtraArgs[*]:-}"'"; grid_str="Native"; fi; "'"$TilerScript"'" -i {2} -o "'"$PreviewWallpaper"'" -s "'"$Resolution"'" $opts >/dev/null 2>&1 && "'"$Backend"'" set-wallpaper "'"$PreviewWallpaper"'" >/dev/null 2>&1; f="{2}"; ext="${f##*.}"; echo -e "Path: {2}\nExtension: $ext\nGrid: $grid_str\n"; chafa {2} 2>/dev/null || true'

while true
do
  clear
  SelectedLine="$(printf '%s\n' "${FzfInput[@]}" | fzf \
    --delimiter=$'\t' \
    --with-nth=1 \
    --preview="$PreviewCmd" \
    --preview-window="$PreviewWindowOpt" \
    --header="Keys: [+/-] Zoom In/Out | [0] Reset Grid" \
    --bind "=:execute-silent($ZoomCmd -1 {2})+refresh-preview" \
    --bind "+:execute-silent($ZoomCmd -1 {2})+refresh-preview" \
    --bind "-:execute-silent($ZoomCmd 1 {2})+refresh-preview" \
    --bind "0:execute-silent(cat \"$ColInitFile\" > \"$ColFile\")+refresh-preview")"

  if [ -z "$SelectedLine" ]; then
    # Cancelled via Esc or Ctrl-C: trap triggers RestoreOriginal and reverts
    break
  fi

  SelectedTile="${SelectedLine#*$'\t'}"

  chafa "$SelectedTile" 2>/dev/null || true
  echo -e "\nYou selected this tile.\nConfirm to apply (y/n):"
  if ! read -r tileconfirmation; then
    tileconfirmation="n"
  fi

  if [ "$tileconfirmation" = "y" ]; then
    FinalCols="$(tr -d '[:space:]' < "$ColFile")"
    if [ -n "$FinalCols" ]; then
      "$TilerScript" -i "$SelectedTile" -o "$GeneratedWallpaper" -s "$Resolution" -c "$FinalCols"
    else
      "$TilerScript" -i "$SelectedTile" -o "$GeneratedWallpaper" -s "$Resolution" "${TilerExtraArgs[@]}"
    fi
    
    "$Backend" set-wallpaper "$GeneratedWallpaper"
    rm -f "$BackupWallpaper" "$PreviewWallpaper" 2>/dev/null || true
    trap - EXIT INT TERM HUP
    break
  else
    RestoreOriginal
  fi
done
```
`install.sh`:

```sh
#!/bin/bash
#
# install.sh - Installer for floorpaper.
#
set -euo pipefail

if [ "$EUID" -eq 0 ]; then
  echo "Do not run install.sh as root!" >&2
  echo "Installation stopped!" >&2
  exit 1
fi

# Dynamically resolve the script directory so it works no matter where it's stored
ScriptDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Detect target installation directory for global binary launcher
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/bin" ]; then
  BinDir="$PREFIX/bin"
else
  BinDir="$HOME/.local/bin"
fi

DataDir="${XDG_DATA_HOME:-$HOME/.local/share}/floorpaper"
AppDir="$DataDir/app"

echo "Clearing existing floorpaper installation artifacts..."
if [ -x "$ScriptDir/floorpaper.sh" ]; then
  "$ScriptDir/floorpaper.sh" --uninstall >/dev/null 2>&1 || true
fi
rm -f "$BinDir/floorpaper"
rm -rf "$AppDir"

echo "Checking runtime dependencies..."
MissingDeps=()
for cmd in fzf chafa convert composite identify; do
  if ! command -v "$cmd" &>/dev/null; then
    MissingDeps+=("$cmd")
  fi
done

if [ ${#MissingDeps[@]} -gt 0 ]; then
  echo "Warning: The following required tools are missing: ${MissingDeps[*]}" >&2
  echo "Make sure to install them before running floorpaper." >&2
else
  echo "All required dependencies are installed."
fi

echo "Initializing submodules for tile repositories..."
if command -v git &>/dev/null && [ -d "$ScriptDir/.git" ]; then
  # Run in a subshell to avoid changing the installer's working directory
  (cd "$ScriptDir" && git submodule update --init --recursive)
else
  echo "Notice: Not a git repository or git is missing. Skipping submodules."
fi

echo "Installing floorpaper..."
mkdir -p "$BinDir" "$AppDir"

# Copy scripts and tile assets using -a to preserve permissions and attributes
cp -a "$ScriptDir/floorpaper.sh" "$AppDir/floorpaper.sh"
cp -a "$ScriptDir/tiler.sh" "$AppDir/tiler.sh"
cp -a "$ScriptDir/backends" "$AppDir/backends"
cp -a "$ScriptDir/tiles" "$AppDir/tiles"

chmod +x "$AppDir/floorpaper.sh" "$AppDir/tiler.sh" "$AppDir/backends"/*.sh

# Global binary launcher named "floorpaper"
cat << 'EOF' > "$BinDir/floorpaper"
#!/bin/bash
AppDir="${XDG_DATA_HOME:-$HOME/.local/share}/floorpaper/app"
if [ ! -f "$AppDir/floorpaper.sh" ]; then
  echo "Error: floorpaper installation not found at $AppDir" >&2
  exit 1
fi
exec "$AppDir/floorpaper.sh" "$@"
EOF

chmod +x "$BinDir/floorpaper"

echo "floorpaper installed successfully!"
echo "Global binary: $BinDir/floorpaper"
echo "Assets directory: $AppDir"

if [[ ":$PATH:" != *":$BinDir:"* ]]; then
  echo ""
  echo "Note: $BinDir is not in your PATH."
  echo "Add it to your shell configuration (e.g., ~/.bashrc or ~/.zshrc):"
  echo "  export PATH=\"$BinDir:\$PATH\""
fi
```
`tiler.sh`:

```sh
#!/bin/bash
#
# tiler.sh - Generate a repeating-tile image from a single source tile.
#
# This script has ZERO knowledge of desktop environments, wallpaper settings,
# or tile sources. It does exactly one thing: take a tile image and produce a
# larger image made of that tile repeated across a canvas. Desktop-environment
# concerns live in floorpaper.sh and backends/*.sh.
#
set -euo pipefail

ScriptName="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $ScriptName -i <tile_image> -o <output_image> [OPTIONS]

Required:
  -i, --input <path>       Source tile image
  -o, --output <path>      Path to write the generated tiled image

Options:
  -s, --size <WxH>         Output canvas size, e.g. 1920x1080 (default: 1920x1080)
  -c, --columns <N>        Repeat the tile N times across the canvas width
  -r, --rows <N>           Repeat the tile N times down the canvas height
  -t, --tile-size <WxH>    Explicit per-tile pixel size, e.g. 128x128.
                            Cannot be combined with -c/-r.
  -h, --help                Show this help and exit

Notes:
  - If none of -c, -r, -t are given, the tile is repeated at its native
    pixel size (same behaviour as plain ImageMagick tiling).
  - If only -c is given, the tile height is scaled to preserve the source
    tile's aspect ratio. Same for -r alone, in the other direction.
  - If the canvas size does not divide evenly by the tile size, the last
    tile in a row/column will be cropped at the edge. This is normal.
EOF
}

Input=""
Output=""
Size="1920x1080"
Columns=""
Rows=""
TileSize=""

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--input)     Input="${2:-}"; shift 2 ;;
    -o|--output)    Output="${2:-}"; shift 2 ;;
    -s|--size)      Size="${2:-}"; shift 2 ;;
    -c|--columns)   Columns="${2:-}"; shift 2 ;;
    -r|--rows)      Rows="${2:-}"; shift 2 ;;
    -t|--tile-size) TileSize="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Error: unknown option '$1'" >&2; usage; exit 1 ;;
  esac
done

# ---- Dependency check ----
for cmd in convert composite identify; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is not installed. Please install imagemagick." >&2
    exit 1
  fi
done

# ---- Validation ----
is_dims() { [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]; }
is_count() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

if [ -z "$Input" ] || [ -z "$Output" ]; then
  echo "Error: -i/--input and -o/--output are required." >&2
  usage
  exit 1
fi

if [ ! -f "$Input" ]; then
  echo "Error: input tile not found: $Input" >&2
  exit 1
fi

if ! is_dims "$Size"; then
  echo "Error: --size must look like WIDTHxHEIGHT, got '$Size'" >&2
  exit 1
fi

if [ -n "$TileSize" ] && { [ -n "$Columns" ] || [ -n "$Rows" ]; }; then
  echo "Error: --tile-size cannot be combined with --columns/--rows." >&2
  exit 1
fi

if [ -n "$TileSize" ] && ! is_dims "$TileSize"; then
  echo "Error: --tile-size must look like WIDTHxHEIGHT, got '$TileSize'" >&2
  exit 1
fi

if [ -n "$Columns" ] && ! is_count "$Columns"; then
  echo "Error: --columns must be a positive integer, got '$Columns'" >&2
  exit 1
fi

if [ -n "$Rows" ] && ! is_count "$Rows"; then
  echo "Error: --rows must be a positive integer, got '$Rows'" >&2
  exit 1
fi

CanvasW="${Size%x*}"
CanvasH="${Size#*x}"

# ---- Work out the per-tile pixel size ----
TileW=""
TileH=""

if [ -n "$TileSize" ]; then
  TileW="${TileSize%x*}"
  TileH="${TileSize#*x}"
elif [ -n "$Columns" ] || [ -n "$Rows" ]; then
  read -r NativeW NativeH < <(identify -format "%w %h\n" "$Input")
  if [ -n "$Columns" ] && [ -n "$Rows" ]; then
    TileW=$(( CanvasW / Columns ))
    TileH=$(( CanvasH / Rows ))
  elif [ -n "$Columns" ]; then
    TileW=$(( CanvasW / Columns ))
    TileH=$(( TileW * NativeH / NativeW ))
  else
    TileH=$(( CanvasH / Rows ))
    TileW=$(( TileH * NativeW / NativeH ))
  fi
  if [ "$TileW" -lt 1 ] || [ "$TileH" -lt 1 ]; then
    echo "Error: computed tile size (${TileW}x${TileH}) is too small for canvas $Size." >&2
    exit 1
  fi
fi

# ---- Build the output ----
mkdir -p "$(dirname "$Output")"

if [ -n "$TileW" ]; then
  # Single-pass in-memory resize and tile without temporary file I/O
  convert "$Input" -resize "${TileW}x${TileH}!" -write mpr:tile +delete -size "${CanvasW}x${CanvasH}" tile:mpr:tile "$Output"
else
  # Single-pass native tiling
  convert -size "${CanvasW}x${CanvasH}" tile:"$Input" "$Output"
fi

echo "Generated: $Output (${CanvasW}x${CanvasH})"
```
`tiles/sources.md`:

```md
[--ACTIVE]repo1 - https://github.com/tile-anon/tiles.git
[INACTIVE]repo2 - https://github.com/wallace-aph/tiles-and-such.git
[INACTIVE]repo3 - https://github.com/rann01/IRIX-tiles.git
[INACTIVE]repo4 - https://github.com/rasatpc/Tiled-wallpapers.git
[INACTIVE]repo5 - https://github.com/jessefalzone/windows-wallpaper-tiles.git
[INACTIVE]repo6 - https://github.com/stephenmkbrady/seamless_tileable_wallpapers.git
[DELETED]repo7 - https://github.com/wesker-albert/tiled-wallpaper-archive.git

```