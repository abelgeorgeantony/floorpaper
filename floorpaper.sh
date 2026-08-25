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
for cmd in fzf chafa convert composite identify; do
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
# ---- State Locking ----
LockFile="$DataDir/floorpaper.lock"
exec 9> "$LockFile"
if ! flock -n 9; then
  echo "Error: Another floorpaper session is currently running. Exiting to prevent state clobbering." >&2
  exit 1
fi

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