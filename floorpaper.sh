#!/bin/bash
#
# floorpaper.sh - Interactive tiled-wallpaper picker.
#
# This is the orchestrator: it knows where tile sources live, scans them for
# image files, drives an fzf TUI with a live chafa+wallpaper preview, and
# talks to a desktop-environment "backend" (backends/*.sh) to actually set
# the wallpaper. It has no image-generation logic of its own - that's
# tiler.sh's job - and no direct GNOME/KDE/etc-specific code either, so new
# desktops are added by dropping in a new backends/<name>.sh.
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
GeneratedWallpaper="$DataDir/wallpaper.png"

# Only these extensions are treated as tiles. The tile-source repos also
# contain READMEs, licenses, etc. - everything else is ignored.
ImageExtensions=(png jpg jpeg bmp gif tiff tif webp)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -d, --tiles-dir <path>   Directory to scan for tile images (default: ./tiles)
  -s, --size <WxH>         Force output resolution instead of auto-detecting
  -c, --columns <N>        Tile repetitions across the width (passed to tiler.sh)
  -r, --rows <N>           Tile repetitions down the height (passed to tiler.sh)
  -t, --tile-size <WxH>    Explicit per-tile pixel size (passed to tiler.sh)
  -h, --help                Show this help and exit

With no sizing options, tiles are repeated at their native pixel size.
EOF
}

OverrideSize=""
Columns=""
Rows=""
TileSize=""

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--tiles-dir) TilesDir="${2:-}"; shift 2 ;;
    -s|--size)      OverrideSize="${2:-}"; shift 2 ;;
    -c|--columns)   Columns="${2:-}"; shift 2 ;;
    -r|--rows)      Rows="${2:-}"; shift 2 ;;
    -t|--tile-size) TileSize="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
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

# ---- Resolution ----
if [ -n "$OverrideSize" ]; then
  Resolution="$OverrideSize"
else
  Resolution="$("$Backend" get-resolution)"
fi

# ---- Build the extra sizing args to forward to tiler.sh ----
TilerExtraArgs=()
if [ -n "$TileSize" ]; then
  TilerExtraArgs+=(-t "$TileSize")
else
  [ -n "$Columns" ] && TilerExtraArgs+=(-c "$Columns")
  [ -n "$Rows" ] && TilerExtraArgs+=(-r "$Rows")
fi

# ---- Scan for tile images ----
FindExprParts=()
for ext in "${ImageExtensions[@]}"; do
  FindExprParts+=(-o -iname "*.$ext")
done
# Drop the leading -o
mapfile -t TileFiles < <(find "$TilesDir" -type f \( "${FindExprParts[@]:1}" \) -not -path '*/.git/*' | sort)

if [ "${#TileFiles[@]}" -eq 0 ]; then
  echo "Error: no tile images found under $TilesDir" >&2
  exit 1
fi

mkdir -p "$DataDir"
# ---- Initialize Zoom/Grid State ----
ColFile="$DataDir/columns"
ColInitFile="$DataDir/columns_init"
echo "${Columns:-}" > "$ColFile"
echo "${Columns:-}" > "$ColInitFile"

# ---- Backup current wallpaper so we can restore it ----
mapfile -t OriginalUris < <("$Backend" get-current)
OriginalLight="${OriginalUris[0]:-}"
OriginalDark="${OriginalUris[1]:-}"

RestoreOriginal() {
  if [ -n "$OriginalLight" ] || [ -n "$OriginalDark" ]; then
    "$Backend" restore "$OriginalLight" "$OriginalDark" 2>/dev/null || true
  fi
}
trap RestoreOriginal EXIT

# ---- The fzf preview: regenerate the tile and live-apply it as you browse ----
PreviewCmd="cols=\$(tr -d '[:space:]' < \"$ColFile\"); if [ -n \"\$cols\" ]; then opts=\"-c \$cols\"; else opts=\"${TilerExtraArgs[*]:-}\"; fi; \"$TilerScript\" -i {} -o \"$GeneratedWallpaper\" -s \"$Resolution\" \$opts >/dev/null 2>&1 && \"$Backend\" set-wallpaper \"$GeneratedWallpaper\" >/dev/null 2>&1; echo -e \"Tile: {}\nGrid: \${cols:-Native} columns\n\"; chafa {} 2>/dev/null"

while true
do
  clear
  SelectedTile="$(printf '%s\n' "${TileFiles[@]}" | fzf \
    --preview="$PreviewCmd" \
    --header="Keys: [+/-] Zoom In/Out | [0] Reset Grid" \
    --bind "=:execute-silent(awk '{c=\$1; if(c==\"\"){c=10}; c=c-1; if(c<1){c=1}; print c}' \"$ColFile\" > \"${ColFile}.tmp\" && mv \"${ColFile}.tmp\" \"$ColFile\")+refresh-preview" \
    --bind "+:execute-silent(awk '{c=\$1; if(c==\"\"){c=10}; c=c-1; if(c<1){c=1}; print c}' \"$ColFile\" > \"${ColFile}.tmp\" && mv \"${ColFile}.tmp\" \"$ColFile\")+refresh-preview" \
    --bind "-:execute-silent(awk '{c=\$1; if(c==\"\"){c=10}; c=c+1; print c}' \"$ColFile\" > \"${ColFile}.tmp\" && mv \"${ColFile}.tmp\" \"$ColFile\")+refresh-preview" \
    --bind "0:execute-silent(cat \"$ColInitFile\" > \"$ColFile\")+refresh-preview")"

  if [ -z "$SelectedTile" ]; then
    # User cancelled (Esc/Ctrl-C in fzf) - restore and exit cleanly.
    break
  fi

  chafa "$SelectedTile" 2>/dev/null || true
  echo -e "You selected this tile.\nConfirm to apply (y/n):"
  read -r tileconfirmation
  if [ "$tileconfirmation" = "y" ]; then
    FinalCols="$(tr -d '[:space:]' < "$ColFile")"
    if [ -n "$FinalCols" ]; then
      "$TilerScript" -i "$SelectedTile" -o "$GeneratedWallpaper" -s "$Resolution" -c "$FinalCols"
    else
      "$TilerScript" -i "$SelectedTile" -o "$GeneratedWallpaper" -s "$Resolution" "${TilerExtraArgs[@]}"
    fi
    
    "$Backend" set-wallpaper "$GeneratedWallpaper"
    # Wallpaper is now applied on purpose - don't restore the old one on exit.
    trap - EXIT
    break
  fi
done