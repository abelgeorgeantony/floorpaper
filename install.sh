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