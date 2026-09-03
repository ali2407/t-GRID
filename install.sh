#!/usr/bin/env bash
# t-GRID installer. Puts `tgrid` on your PATH and optionally builds the menu bar app.
# Makes exactly two changes: one symlink, and (if you say yes) one .app bundle.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/bin/tgrid"
QSRC="$HERE/bin/tgrid-queue"

[[ "$(uname)" == "Darwin" ]] || { echo "t-GRID is macOS only."; exit 1; }
chmod +x "$SRC" "$QSRC" "$HERE/app/build.sh"

# pick the first directory that is on PATH and writable
TARGET=""
for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
  case ":$PATH:" in *":$d:"*) [[ -w "$d" ]] && { TARGET="$d"; break; } ;; esac
done
if [[ -z "$TARGET" ]]; then
  mkdir -p "$HOME/.local/bin"
  TARGET="$HOME/.local/bin"
  echo "note: $TARGET is not on your PATH. Add this to your shell profile:"
  echo "      export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

ln -sf "$SRC" "$TARGET/tgrid"
echo "installed: $TARGET/tgrid  ->  $SRC"
# tgrid-queue is linked beside tgrid on purpose: `tgrid --queue` follows the
# symlink back to the checkout to find it, and the menu bar app looks for it
# next to whichever tgrid it found.
ln -sf "$QSRC" "$TARGET/tgrid-queue"
echo "installed: $TARGET/tgrid-queue  ->  $QSRC"

if command -v swiftc >/dev/null; then
  read -r -p "Build the menu bar app too? [Y/n] " reply
  case "${reply:-y}" in
    [Yy]*|"") "$HERE/app/build.sh" && open "$HOME/Applications/TGrid.app" ;;
    *) echo "skipped — run ./app/build.sh any time." ;;
  esac
else
  echo "swiftc not found, skipping the menu bar app."
  echo "Install the Xcode Command Line Tools and run ./app/build.sh to get it:"
  echo "  xcode-select --install"
fi

echo
echo "Try it:  tgrid --reflow"
