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
  local path="$1"
  local uri="file://$path"
  gsettings set "$Schema" picture-uri "$uri"
  gsettings set "$Schema" picture-uri-dark "$uri"
}

cmd_restore() {
  local uri="$1" uri_dark="$2"
  gsettings set "$Schema" picture-uri "$uri"
  gsettings set "$Schema" picture-uri-dark "$uri_dark"
}

case "${1:-}" in
  is-supported)   cmd_is_supported ;;
  get-resolution) cmd_get_resolution ;;
  get-current)    cmd_get_current ;;
  set-wallpaper)  [ $# -eq 2 ] || { echo "Usage: $0 set-wallpaper <path>" >&2; exit 1; }; cmd_set_wallpaper "$2" ;;
  restore)        [ $# -eq 3 ] || { echo "Usage: $0 restore <uri> <uri-dark>" >&2; exit 1; }; cmd_restore "$2" "$3" ;;
  *) echo "Usage: $0 {is-supported|get-resolution|get-current|set-wallpaper|restore}" >&2; exit 1 ;;
esac
