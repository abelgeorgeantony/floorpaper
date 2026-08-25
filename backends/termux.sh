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