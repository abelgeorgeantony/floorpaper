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

## Disabled to reduce tiler.sh not check at every iteration. tiler.sh is an internal tool of floorpaper.sh so check disabling is ok.
# ---- Dependency check ----
#for cmd in convert composite identify; do
#  if ! command -v "$cmd" &>/dev/null; then
#    echo "Error: $cmd is not installed. Please install imagemagick." >&2
#    exit 1
#  fi
#done

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