#!/bin/bash
#
# backends/kde.sh - KDE Plasma backend for floorpaper.
#
# This standalone script implements the five subcommands required by
# floorpaper.sh's backend protocol.
#
set -euo pipefail

cmd_is_supported() {
  # Exit 0 if running KDE Plasma and the native wallpaper tool is available
  [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] && command -v plasma-apply-wallpaperimage &>/dev/null
}

cmd_get_resolution() {
  # Try xrandr first (works on X11 and XWayland)
  if command -v xrandr &>/dev/null && [ -n "${DISPLAY:-}" ]; then
    local res
    res="$(xrandr --current 2>/dev/null | awk '/\*/ {print $1; exit}')"
    if [ -n "$res" ]; then
      echo "$res"
      return 0
    fi
  fi
  
  # Fall back to a common default if xrandr fails; users can override with --size
  echo "Warning: could not detect display resolution, defaulting to 1920x1080." >&2
  echo "1920x1080"
}

cmd_get_current() {
  local config_file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  if [ -f "$config_file" ]; then
    # KDE stores wallpaper paths mapped per screen. We grep the last known 'Image=' string.
    local current_img
    current_img="$(grep '^Image=' "$config_file" 2>/dev/null | tail -n 1 | sed -e 's/^Image=//' -e 's/^file:\/\///')"
    
    # floorpaper expects two lines (light mode and dark mode)
    # KDE does not separate these strictly, so we output the same path twice.
    echo "$current_img"
    echo "$current_img"
  else
    echo ""
    echo ""
  fi
}

cmd_set_wallpaper() {
  local path="$1"
  plasma-apply-wallpaperimage "$path" >/dev/null 2>&1 || true
}

cmd_restore() {
  local uri="$1"
  # KDE does not require uri_dark, so we just restore using the first argument
  if [ -n "$uri" ]; then
    cmd_set_wallpaper "$uri"
  fi
}

# Entrypoint routing based on floorpaper.sh contract
case "${1:-}" in
  is-supported)   cmd_is_supported ;;
  get-resolution) cmd_get_resolution ;;
  get-current)    cmd_get_current ;;
  set-wallpaper)  [ $# -eq 2 ] || { echo "Usage: $0 set-wallpaper <path>" >&2; exit 1; }; cmd_set_wallpaper "$2" ;;
  restore)        [ $# -eq 3 ] || { echo "Usage: $0 restore <uri> <uri-dark>" >&2; exit 1; }; cmd_restore "$2" "$3" ;;
  *) echo "Usage: $0 {is-supported|get-resolution|get-current|set-wallpaper|restore}" >&2; exit 1 ;;
esac