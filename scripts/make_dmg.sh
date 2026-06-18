#!/usr/bin/env bash
# Builds Macda.app and packages it into a drag-to-install DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Macda.app"
STAGING="$ROOT/build/dmg"
DMG="$ROOT/build/Macda.dmg"
VOLNAME="Macda"

# Ensure a fresh release build exists.
"$ROOT/scripts/build_app.sh" release

echo "▶︎ Staging DMG contents…"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

echo "▶︎ Creating DMG…"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGING"
SIZE="$(du -h "$DMG" | cut -f1)"
echo "✓ Created $DMG ($SIZE)"
echo "  Install: open the DMG and drag Macda into Applications."
