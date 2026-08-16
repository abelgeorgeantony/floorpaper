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