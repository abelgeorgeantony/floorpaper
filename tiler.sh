#!/bin/bash

if [ "$EUID" -eq 0 ]
then
        echo -e "Do not run tiler as root!\nTiler stopped!"
        exit
fi

# Dependency check
for cmd in fzf chafa composite; do
  if ! command -v "$cmd" &> /dev/null; then
    echo -e "Error: $cmd is not installed.\nPlease make sure the required dependencies: fzf, chafa, and composite(imagemagick) are installed." >&2
    exit 1
  fi
done

# Tiler for GNOME(Wayland)
TilesFolder=/home/abelgeorgeantony/workspace/side/floorpaper/TilesArchive/repo1
SetWallpaper="gsettings set org.gnome.desktop.background picture-uri-dark file://$TilesFolder/wallpaper.png"
SaveCurrentWallpaper() {
  if [ ! -f $TilesFolder/backup.wallpaper.png ]; then
    cp $TilesFolder/wallpaper.png $TilesFolder/backup.wallpaper.png
  fi
}
SetOriginalWallpaper() {
  mv $TilesFolder/backup.wallpaper.png $TilesFolder/wallpaper.png
  $SetWallpaper
}

MakePreview="composite -tile {} -size 1920x1200 xc:none $TilesFolder/wallpaper.png"
DesktopPreview="$MakePreview && $SetWallpaper"
TilePreview="echo -e 'Tile: {}\n' && chafa {}"

## User-Interaction begins here
SaveCurrentWallpaper
trap SetOriginalWallpaper EXIT
while true
do
  clear
  SelectedTile=$(find "$TilesFolder" -type f | fzf --preview="$TilePreview && $DesktopPreview")
  chafa $SelectedTile
  echo -e "You selected this tile.\nConfirm to apply(y/n):"
  read tileconfirmation
  if [ "$tileconfirmation" = "y" ]; then
    cp $TilesFolder/wallpaper.png $TilesFolder/backup.wallpaper.png
    break
  else
    SetOriginalWallpaper
    echo "Do you want to select another tile?(y/n):"
    read loopconfirmation
    if [ "$loopconfirmation" = "n" ]; then
      break
    fi
  fi
done
